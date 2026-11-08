#!/usr/bin/env python3
"""Verify every recorded console sample and its staged inputs before summarizing."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics

PATTERN = r'(\d+) frames\s+([\d.]+) seconds\s+([\d.]+) fps'
VARIANTS = ('original', 'quake486', 'nitro')
PROFILE_SHA = '532284EA01C1A93C8B96D70FB538625B694DFAD0172BA13B9BA9C36C8FE845BA'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def runtime_base(text):
    return re.sub(r'(?ms)^\[autoexec\]\s*.*?(?=^\[devices\])', '[autoexec]\n', text).strip()


def verify(root: Path):
    root = root.resolve()
    data = json.loads((root/'results.json').read_text(encoding='utf-8-sig'))
    normalized = Path(data['profile']).read_text(encoding='ascii').replace('\r\n', '\n')
    require(hashlib.sha256(normalized.encode('ascii')).hexdigest().upper() == data['profileSha256'] == PROFILE_SHA,
            'Profile differs from the pinned 486DX configuration')
    expected = [('original', 1), ('quake486', 1), ('nitro', 1),
                ('quake486', 2), ('nitro', 2), ('original', 2),
                ('nitro', 3), ('original', 3), ('quake486', 3)]
    require([(r['variant'], r['round']) for r in data['results']] == expected, 'Missing, duplicated or reordered samples')
    for variant, source in data['inputs'].items():
        require(sha(source) == data['executableSha256'][variant], f'Input executable changed: {variant}')
    used = set()
    for result in data['results']:
        log = Path(result['consoleLog']).resolve()
        stage = log.parents[2]
        require(stage.parent == root and stage.name == f"round-{result['round']:02}-{result['variant']}", 'Unexpected staging path')
        used.add(stage)
        text = log.read_text(encoding='ascii', errors='replace')
        matches = re.findall(PATTERN, text)
        require(len(matches) == 1, f'Expected one completed sample: {log}')
        frames, seconds, fps = matches[0]
        require(int(frames) == result['frames'] == 969, f'Frame count differs: {log}')
        require(float(seconds) == result['seconds'] and float(fps) == result['fps'] and float(seconds) > 0 and float(fps) > 0, f'Timing mismatch: {log}')
        dimensions = re.findall(r'(?<![A-Za-z0-9])([1-9]\d{2,})x([1-9]\d{2,})(?![A-Za-z0-9])', text)
        require(dimensions and set(dimensions) == {('320', '200')}, f'Resolution mismatch: {log}')
        require('Host_Error:' not in text and 'Sys_Error:' not in text, f'Game error: {log}')
        require(sha(stage/'quake/quake.exe') == data['executableSha256'][result['variant']], 'Staged executable mismatch')
        require(sha(stage/'quake/cwsdpmi.exe') == data['dpmiProviderSha256'], 'DPMI mismatch')
        for pak, digest in data['gameDataSha256'].items():
            require(Path(pak).name == pak and sha(stage/'quake/id1'/pak) == digest, 'Game data mismatch')
        require((stage/'quake/id1/bench.cfg').read_text().splitlines() == ['viewsize 100', 'startdemos', 'timedemo demo1'], 'Measurement command queue changed')
        require(runtime_base((stage/'dosbox-x.conf').read_text()) == runtime_base(normalized), 'Runtime emulator settings changed')
    for stage in root.glob('round-*'):
        if stage.is_dir() and stage.resolve() not in used:
            log = stage/'quake/id1/qconsole.log'
            require(not log.exists() or not re.search(PATTERN, log.read_text(errors='replace')), f'Completed sample excluded: {stage}')
    manifest = json.loads((root/'nitro-build-manifest.json').read_text(encoding='utf-8-sig'))
    require(not manifest['benchmarkBuild'] and not manifest['profileBuild'] and manifest['isaAuditStatus'] == 'PASS' and manifest['sourceBoundIsa'], 'Nitro build must be uninstrumented with source-bound ISA proofs')
    require(manifest['executableSha256'] == data['executableSha256']['nitro'], 'Native manifest executable mismatch')
    summary = {}
    for variant in VARIANTS:
        rows = [r for r in data['results'] if r['variant'] == variant]
        fps = [r['fps'] for r in rows]; seconds = [r['seconds'] for r in rows]
        summary[variant] = dict(fpsSamples=fps, secondsSamples=seconds, medianFps=statistics.median(fps),
                                medianSeconds=statistics.median(seconds), fpsSpread=max(fps)-min(fps),
                                secondsSpread=max(seconds)-min(seconds))
    result = dict(verified=True, runs=9, framesPerRun=969, summary=summary, nitroVersion=data['nitroVersion'],
                  source='results.json', sourceSha256=sha(root/'results.json'), dosboxSha256=sha(data['dosbox']),
                  noPerFrameInstrumentation=True, precision='Console values rounded to 0.1',
                  environment='DOSBox-X 486/387 fixed33445 32MiB 320x200; sound/CD/input disabled',
                  limitations='Delivered video/cache defaults may differ. Stock pixel/Z parity and physical 486 performance are unmeasured.')
    (root/'verified-summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.directory)
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2))
