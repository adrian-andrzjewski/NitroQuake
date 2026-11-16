"""Build and run source-based native collision differential fixtures."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from _workspace import BENCHMARK_TOOLS, game_root


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def headers(root):
    return {path.relative_to(root / 'src').as_posix():
            path.read_bytes().replace(b'\r\n', b'\n')
            for path in (root / 'src').rglob('*.h')}


def extract(source, name):
    masked = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
                    lambda match: ' ' * len(match[0]), source, flags=re.S)
    match = re.search(r'\b(?:void|trace_t)\s+' + name + r'\s*\([^;{}]*\)\s*\{', masked)
    if not match:
        raise ValueError(f'Cannot find supported function definition: {name}')
    end, depth = match.end(), 1
    while depth:
        depth += (masked[end] == '{') - (masked[end] == '}')
        end += 1
    return source[match.start():end]


def verify(args):
    if not 30 <= args.timeout <= 1800 or not 0 <= args.wait_for_slot <= 3600:
        raise ValueError('Timeout must be 30..1800 seconds; slot wait must be 0..3600 seconds')
    reference, candidate = game_root(args.reference_root), game_root(args.game_root)
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Choose a fresh output directory')
    for root in (reference, candidate):
        for inputs in ('src', 'tools'):
            if output.is_relative_to(root / inputs):
                raise ValueError('Keep generated fixtures outside game source/build-tool inputs')
    reference_headers = headers(reference)
    if reference_headers != headers(candidate):
        raise ValueError('Reference and candidate headers differ; review the fixture ABI')
    pwsh = shutil.which('pwsh')
    if not pwsh:
        raise ValueError('PowerShell 7 is required')
    tool_root = (args.tool_root or Path(os.environ['LOCALAPPDATA']) / '486quake/tools').resolve()
    manifest_path = candidate / 'tools/dos-toolchain.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    compiler = tool_root / manifest['djgpp']['installDirectory'] / manifest['djgpp']['compiler']
    if not compiler.is_file():
        raise ValueError('Install the pinned game compiler toolchain before running this fixture')
    resolved = json.loads(subprocess.run([
        pwsh, '-NoProfile', '-File', str(candidate / 'tools/build-dos-experimental.ps1'), '-Benchmark',
        '-CpuTarget', 'i486', '-LocalOutputDirectoryName', 'collision-fixture', '-DumpFlags'],
        check=True, capture_output=True, text=True).stdout)
    cflags = resolved['cFlags'] + resolved.get('cSourceExtraFlags', {}).get('world.c', [])
    asmflags = resolved['asmFlags'] + resolved.get('asmSourceExtraFlags', {}).get('asm486_collision.s', [])
    defines = {value.split('=', 1)[0] for value in asmflags}
    for define in ('-DBENCH486', '-DASM486_CLIP_TO_LINKS'):
        if define not in defines:
            raise ValueError('Fixture requires the supported BENCH486 assembly clipper profile')
    source_paths = [root / 'src' / filename for root in (reference, candidate)
                    for filename in ('world.c', 'sv_cliptolinks_asm.inc')]
    source_pins = {str(path): digest(path) for path in source_paths}
    output.mkdir(parents=True)
    state = dict(schemaVersion=1, status='building', reference=str(reference), candidate=str(candidate),
                 driverSha256=digest(__file__), sourceSha256=source_pins,
                 compiler=str(compiler), compilerSha256=digest(compiler),
                 toolchainManifestSha256=digest(manifest_path), cFlags=cflags, asmFlags=asmflags,
                 normalizedHeaderSha256={name: hashlib.sha256(data).hexdigest()
                                         for name, data in sorted(reference_headers.items())}, units={})

    def save():
        (output / 'fixture.json').write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')

    def compile_command(command):
        subprocess.run([str(compiler), *command], check=True, timeout=args.timeout)

    def run_unit(name, expected):
        directory = output / name
        deadline = time.monotonic() + args.wait_for_slot
        attempt = 0
        while True:
            expected_executable = state['units'][name]['compiledFiles']['fixture.exe']
            if digest(directory / 'fixture.exe') != expected_executable:
                raise ValueError(f'{name} executable changed after compilation')
            attempt += 1
            log_path = directory / f'runner-attempt-{attempt}.log'
            command = [pwsh, '-NoProfile', '-File', str(BENCHMARK_TOOLS / 'run-native-fixture.ps1'),
                       '-GameRoot', str(candidate), '-OutputRoot', str(directory),
                       '-ExpectedResultPrefix', f'PASS {expected} ', '-ToolRoot', str(tool_root),
                       '-TimeoutSeconds', str(args.timeout)]
            with log_path.open('w', encoding='utf-8') as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                try:
                    code = process.wait(timeout=args.timeout + 120)
                except BaseException:
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                    process.wait()
                    raise
            if code == 0:
                execution = json.loads((directory / 'execution.json').read_text(encoding='utf-8-sig'))
                if (execution['status'] != 'PASS' or not execution['report'].startswith(f'PASS {expected} ') or
                        digest(directory / 'quake/fixture.exe') != expected_executable or
                        digest(directory / 'quake/cwsdpmi.exe').upper() != execution['providerSha256'].upper()):
                    raise RuntimeError(f'{name} staged execution inputs/results do not match their pins')
                state['units'][name].update(status='PASS', executionSha256=digest(directory / 'execution.json'),
                                           runtimeExecutableSha256=expected_executable,
                                           runnerAttempts=attempt, runnerLogSha256=digest(log_path))
                save()
                print(f'{name}: PASS ({expected} native comparisons)', flush=True)
                return
            busy = (not (directory / 'quake').exists() and
                    'DOSBox is occupied' in log_path.read_text(encoding='utf-8-sig'))
            if not busy or time.monotonic() >= deadline:
                raise RuntimeError(f'{name} failed; retained {log_path}')
            print(f'{name}: DOSBox occupied; retrying within the requested slot wait', flush=True)
            time.sleep(min(10, max(0, deadline - time.monotonic())))

    save()
    try:
        for unit, fixture_name, expected in [('move', 'collision-move-cases.c', 18432),
                                              ('cliplinks', 'collision-links-cases.c', 6912)]:
            directory = output / unit
            directory.mkdir()
            state['units'][unit] = dict(status='building', expectedCases=expected)
            for suffix, root in [('Control', reference), ('Candidate', candidate)]:
                target = directory / suffix.lower()
                if unit == 'move':
                    source = (root / 'src/collision/world.c').read_text(encoding='utf-8-sig')
                    bodies = '\n\n'.join(extract(source, fn) for fn in ('SV_MoveBounds', 'SV_Move'))
                    for fn in ('SV_MoveBounds', 'SV_Move'):
                        bodies = re.sub(r'\b' + fn + r'\b', fn + suffix, bodies)
                    target = target.with_suffix('.c')
                    target.write_text('#include "quakedef.h"\n#include "asm_cliplinks.h"\n'
                                      '#include "asm_clipmovetoentity.h"\nextern areanode_t sv_areanodes[];\n'
                                      + bodies + '\n', encoding='utf-8')
                    compile_command([*cflags, '-Wall', '-c', str(target), '-o', str(target.with_suffix('.obj'))])
                else:
                    source = (root / 'src/collision/sv_cliptolinks_asm.inc').read_text(encoding='utf-8-sig')
                    source, changed = re.subn(r'C\(\s*SV_ClipToLinks\s*\)',
                                             'C(SV_ClipToLinks' + suffix + ')', source)
                    if not changed:
                        raise ValueError('Assembly clipper interface changed; review this fixture')
                    target = target.with_suffix('.s')
                    target.write_text('#define C2(x) _##x\n#define C(x) C2(x)\n' + source, encoding='utf-8')
                    preprocessed = target.with_suffix('.pp.s')
                    compile_command([*asmflags, '-x', 'assembler-with-cpp', '-E', str(target), '-o', str(preprocessed)])
                    compile_command([*asmflags, '-x', 'assembler', '-c', str(preprocessed), '-o', str(target.with_suffix('.obj'))])
            shutil.copyfile(BENCHMARK_TOOLS / 'fixtures' / fixture_name, directory / 'fixture.c')
            compile_command([*cflags, '-Wall', '-c', str(directory / 'fixture.c'), '-o', str(directory / 'fixture.obj')])
            objects = [directory / (name + '.obj') for name in ('fixture', 'control', 'candidate')]
            if unit == 'cliplinks':
                shutil.copyfile(BENCHMARK_TOOLS / 'fixtures/collision-links-abi.s', directory / 'abi.s')
                compile_command(['-march=i486', '-c', str(directory / 'abi.s'), '-o', str(directory / 'abi.obj')])
                objects.append(directory / 'abi.obj')
            compile_command(['-march=i486', '-mtune=i486', '-mfpmath=387', *map(str, objects), '-o', str(directory / 'fixture.exe')])
            state['units'][unit].update(status='prepared', compiledFiles={path.name: digest(path)
                for path in directory.iterdir() if path.suffix in ('.c', '.s', '.i', '.obj', '.exe')})
            save()
        if (source_pins != {str(path): digest(path) for path in source_paths} or
                headers(candidate) != reference_headers or headers(reference) != reference_headers):
            raise ValueError('Game inputs changed while compiling; choose fresh output after source edits finish')
        state['status'] = 'prepared'
        save()
        if not args.build_only:
            state['status'] = 'running'
            save()
            for unit, expected in [('move', 18432), ('cliplinks', 6912)]:
                run_unit(unit, expected)
            state['status'] = 'PASS'
    except BaseException as error:
        state.update(status='failed', error=str(error))
        raise
    finally:
        save()
    return state


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', required=True, type=Path)
    parser.add_argument('--game-root', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--tool-root', type=Path)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--wait-for-slot', type=int, default=0, help='Seconds to wait on a busy DOSBox slot')
    parser.add_argument('--build-only', action='store_true')
    print(verify(parser.parse_args())['status'])
