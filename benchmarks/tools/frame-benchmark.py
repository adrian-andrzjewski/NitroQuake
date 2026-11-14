#!/usr/bin/env python3
"""Run demo1/2/3 frame timelines, render reports, or compare recorded builds."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import html
from importlib.metadata import version
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time
import uuid

from _workspace import BENCHMARK_ROOT, BENCHMARK_TOOLS, game_root
from frame_times import ingest, load_run, read_json, sha256, write_json

PROTOCOL = BENCHMARK_TOOLS/'frame-timing-protocol.json'
RUNTIME_FILES = ['frame-benchmark.py', 'frame_times.py', '_workspace.py',
                 'timedemo-dos.ps1', 'common.ps1', 'workspace.ps1', 'frame-timing-protocol.json']


def runtime_sources():
    return {name: sha256(BENCHMARK_TOOLS/name) for name in RUNTIME_FILES}


def verify_replays(command, directory: Path, timeout: int):
    directory.mkdir()
    handoff = directory/'source-result.json'
    command = command.copy()
    command[command.index('-Runs')+1] = '2'
    command[command.index('-ResultJson')+1] = str(handoff)
    extra_index = command.index('-QuakeExtraArgs')+1
    command[extra_index] += ' -zchecksums'
    run_process(command+['-NoFpsStats', '-FrameChecksums'], directory/'runner.log', directory, 2*timeout+120)
    result = read_json(handoff)
    streams = {}
    for field in ['frameChecksumPath', 'frameZChecksumPath']:
        paths = [Path(run['renderingDiagnostics'][field]) for run in result['results']]
        if len(paths) != 2: raise ValueError('Correctness replay did not retain both runs')
        contents = [p.read_bytes().replace(b'\r\n', b'\n') for p in paths]
        if contents[0] != contents[1]: raise ValueError('Fixed-step color/Z checksum streams differ between replays')
        streams[field] = dict(paths=[str(p) for p in paths], sha256=[sha256(p) for p in paths])
    return dict(demo=result['demo'], sourceResult=str(handoff), streams=streams,
                purpose='Exact color/Z replay validation; timings excluded from performance results')


def pyplot():
    try:
        import matplotlib
        matplotlib.use('Agg')
        matplotlib.rcParams['svg.hashsalt'] = 'nitroquake-frame-timeline-v1'
        matplotlib.rcParams['font.family'] = 'DejaVu Sans'
        import matplotlib.pyplot as plt
    except ImportError as error:
        raise RuntimeError('Charts require Matplotlib: install benchmarks/requirements-charts.txt') from error
    return plt


def save_charts(fig, base: Path):
    fig.savefig(base.with_suffix('.png'), dpi=150, metadata={'Software': 'NitroQuake frame benchmark'})
    fig.savefig(base.with_suffix('.svg'), metadata={'Date': None, 'Creator': 'NitroQuake frame benchmark'})


def plot_run(directory: Path):
    report, rows = load_run(directory)
    stats = report['statistics']
    plt = pyplot()
    fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
    elapsed = [r['elapsed_seconds'] for r in rows]
    fps = [r['instantaneous_fps'] for r in rows]
    frame_ms = [r['cadence_ms'] for r in rows]
    axes[0].plot(elapsed, fps, color='#376c9d', linewidth=.8, label='Instantaneous FPS (frame-to-frame cadence)')
    # Time-weighted rolling throughput, never an arithmetic average of FPS.
    rolling = []
    left = 0; work = 0.0
    for index, row in enumerate(rows):
        work += row['cadence_seconds']
        while left < index and row['elapsed_seconds']-rows[left]['elapsed_seconds'] > 1:
            work -= rows[left]['cadence_seconds']; left += 1
        rolling.append((index-left+1)/work)
    axes[0].plot(elapsed, rolling, color='#df8631', linewidth=1.5, label='Trailing 1 s throughput')
    axes[0].axhline(stats['average_fps'], color='#37424d', linestyle='--', linewidth=.8, label='Whole-demo average')
    axes[0].set_ylabel('FPS'); axes[0].set_ylim(bottom=0); axes[0].legend(loc='best', fontsize=8)
    axes[1].plot(elapsed, frame_ms, color='#376c9d', linewidth=.8, label='Frame interval including gaps')
    axes[1].plot(elapsed, [r['frame_ms'] for r in rows], color='#6e9477', linewidth=.6, alpha=.7, label='Host-frame work only')
    axes[1].axhline(stats['frame_time_percentiles_ms']['p99'], color='#b24c40', linestyle='--', label='p99 frame time')
    slow = stats['slowest_frames'][:5]
    for row in slow:
        axes[1].scatter(row['elapsed_seconds'], row['cadence_ms'], color='#b24c40', s=16)
    # One callout avoids overlapping labels when adjacent frames share a spike.
    worst = slow[0]
    axes[1].annotate(f"Slowest: sample {worst['sample_index']}",
                     (worst['elapsed_seconds'], worst['cadence_ms']),
                     xytext=(.5, .93), textcoords='axes fraction', ha='center', va='top', fontsize=8,
                     bbox=dict(boxstyle='round,pad=.3', facecolor='white', edgecolor='#b24c40', alpha=.9),
                     arrowprops=dict(arrowstyle='->', color='#b24c40', linewidth=.8))
    axes[1].set_ylabel('Frame interval / work (ms)'); axes[1].set_ylim(bottom=0)
    axes[1].set_xlabel('Elapsed DOS timer time from capture origin (s)')
    axes[1].legend(loc='best', fontsize=8)
    for ax in axes:
        ax.grid(alpha=.2)
    fig.suptitle(f"{report['label']} | {report['demo']} | {directory.name}", fontsize=13)
    fig.text(.06, .025,
             f"Average {stats['average_fps']:.2f} FPS   Min {stats['minimum_fps']:.2f}   "
             f"1% low {stats['low_1_percent_fps']:.2f}   p99 {stats['frame_time_percentiles_ms']['p99']:.2f} ms\n"
             'DOSBox-X i486, 320x200. Fixed simulation step; real timer. Timing capture includes its own instrumentation cost.', fontsize=9)
    fig.tight_layout(rect=(0, .075, 1, .96))
    save_charts(fig, directory/'fps-versus-time')
    plt.close(fig)
    write_json(directory/'chart-provenance.json', dict(schemaVersion=1,
        generatorSha256=sha256(Path(__file__)), matplotlib=version('matplotlib'),
        statisticsSha256=sha256(directory/'statistics.json'), framesCsvSha256=sha256(directory/'frames.csv'),
        pngSha256=sha256(directory/'fps-versus-time.png'), svgSha256=sha256(directory/'fps-versus-time.svg')))


def run_process(command, log: Path, cwd: Path, timeout: int):
    started = time.monotonic()
    with log.open('w', encoding='utf-8') as stream:
        stream.write(json.dumps(command)+'\n'); stream.flush()
        # The established PowerShell runner owns DOSBox's watchdog and handle.
        # This outer bound includes report generation, with no per-frame polling.
        process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            else:
                process.kill()
            process.wait()
            raise
    if code:
        raise RuntimeError(f'Command failed ({code}); retained log: {log}')
    return time.monotonic()-started


def build_parameters(args):
    values = ['-CpuTarget', 'i486', '-Benchmark']
    if args.tool_root: values += ['-ToolRoot', str(args.tool_root.resolve())]
    if args.local_output: values += ['-LocalOutputDirectoryName', args.local_output]
    if args.selector_profile:
        profile = read_json(args.selector_profile)
        if profile.get('schemaVersion') != 1 or not profile.get('selectors'):
            raise ValueError('Unsupported selector profile')
        for name, value in profile['selectors'].items():
            if not name.endswith('Implementation') or not name.isidentifier() or not isinstance(value, str):
                raise ValueError('Invalid renderer selector')
            values += ['-'+name, value]
    return values


def fresh_output(path: Path):
    path = path.resolve()
    if path.exists(): raise ValueError(f'Refusing existing output directory: {path}')
    path.mkdir(parents=True)
    return path


def run_batch(args):
    pyplot()  # Fail before any build or measurement if chart dependencies are missing.
    root = game_root(args.game_root)
    if args.timeout <= 0 or args.build_timeout <= 0:
        raise ValueError('Timeouts must be positive seconds')
    if not args.local_output and not args.skip_build:
        args.local_output = 'timeline-'+datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
    protocol = read_json(PROTOCOL)
    demos = args.demos or list(protocol['demos'])
    if len(demos) != len(set(demos)) or any(d not in protocol['demos'] for d in demos):
        raise ValueError('Select demo1, demo2 and/or demo3 without duplicates')
    output = fresh_output(args.output)
    pwsh = shutil.which('pwsh')
    if not pwsh: raise RuntimeError('PowerShell 7 (pwsh) is required')
    params = build_parameters(args)
    resolved = json.loads(subprocess.check_output(
        [pwsh, '-NoProfile', '-File', str(root/'tools/build-dos-experimental.ps1'), *params, '-DumpFlags'], text=True))
    session = dict(schemaVersion=1, status='building', label=args.label, protocol=protocol,
                   startedUtc=datetime.now(timezone.utc).isoformat(),
                   gameRoot=str(root), resolvedBuild=resolved,
                   host=dict(platform=platform.platform(), logicalCpus=os.cpu_count(), python=sys.version),
                   samples=[], controls=[], verification=[], aggregate={},
                   runtimeSources=runtime_sources(), scope='DOSBox emulator measurement; no physical 486 claim')
    snapshot = output/'tooling-snapshot'; snapshot.mkdir()
    for name in RUNTIME_FILES: shutil.copyfile(BENCHMARK_TOOLS/name, snapshot/name)
    write_json(output/'session.json', session)
    started = time.monotonic()
    try:
        if not args.skip_build:
            print('Building the benchmark executable and strict ISA proofs...', flush=True)
            session['buildWallSeconds'] = run_process(
                [pwsh, '-NoProfile', '-File', str(root/'tools/build-dos-experimental.ps1'), *params,
                 *(['-NoBootstrap'] if args.no_bootstrap else [])], output/'build.log', root, args.build_timeout)
        else:
            session['buildWallSeconds'] = 0.0
        manifest_path = Path(resolved['outputRoot'])/resolved['manifest']
        manifest = read_json(manifest_path)
        if manifest.get('profileBuild') or not manifest.get('benchmarkBuild'):
            raise ValueError('Use a BENCH486 build without PROFILE486')
        session['nativeManifestSha256'] = sha256(manifest_path)
        session['executableSha256'] = sha256(Path(resolved['executable']))
        shutil.copyfile(manifest_path, output/'native-build-manifest.json')
        session['status'] = 'running'
        write_json(output/'session.json', session)
        native_params = [v for v in params if v != '-Benchmark']
        expected_checksums = {}
        for repetition in range(1, args.runs+1):
            # Rotate demos to distribute host drift across the repeat blocks.
            shift = (repetition-1) % len(demos)
            for demo in demos[shift:]+demos[:shift]:
                name = f'{demo}-run-{repetition:02}'
                directory = output/name; directory.mkdir()
                print(f'Capturing {args.label}: {name}', flush=True)
                result_path = directory/'source-result.json'
                command = [pwsh, '-NoProfile', '-File', str(BENCHMARK_TOOLS/'timedemo-dos.ps1'),
                           '-GameRoot', str(root), *native_params, '-SkipBuild', '-Runs', '1',
                           '-DemoName', demo, '-ExpectedFrames', str(protocol['demos'][demo]),
                           '-ExpectedChecksum', '0', '-QuakeExtraArgs', protocol['quakeExtraArgs'],
                           '-AutoexecCommandsJson', json.dumps(protocol['autoexecCommands']),
                           '-TimeoutSeconds', str(args.timeout), '-ResultJson', str(result_path)]
                if args.data_root: command += ['-DataRoot', str(args.data_root.resolve())]
                if args.no_bootstrap: command += ['-NoBootstrap']
                if args.verify_replays and repetition == 1:
                    print(f'Verifying exact color/Z replay streams: {demo}', flush=True)
                    session['verification'].append(verify_replays(command, output/f'{demo}-verification', args.timeout))
                    write_json(output/'session.json', session)
                wall = run_process(command+['-FrameTimings'], directory/'runner.log', output, args.timeout+120)
                if runtime_sources() != session['runtimeSources']:
                    raise ValueError('Benchmark tooling changed during the session; raw attempt retained, restart with frozen sources')
                if sha256(Path(resolved['executable'])) != session['executableSha256']:
                    raise ValueError('Native executable changed during the session')
                report, _ = ingest(result_path, directory, args.label, protocol)
                if report['executableSha256'] != session['executableSha256']:
                    raise ValueError('Measured executable differs from the recorded build')
                plot_run(directory)
                session['samples'].append(dict(demo=demo, repetition=repetition, directory=name,
                                               hostProcessSeconds=wall, statistics=report['statistics']))
                write_json(output/'session.json', session)
                prior = expected_checksums.setdefault(demo, report['framebufferChecksum'])
                if report['framebufferChecksum'] != prior:
                    raise ValueError(f'{demo} final framebuffer differs between repeated deterministic runs')
                if args.overhead_controls and repetition == 1:
                    control_dir = output/f'{demo}-control'; control_dir.mkdir()
                    control_path = control_dir/'source-result.json'
                    control_command = command.copy()
                    control_command[control_command.index('-ResultJson')+1] = str(control_path)
                    run_process(control_command+['-NoFpsStats'], control_dir/'runner.log', output, args.timeout+120)
                    control = read_json(control_path)
                    if (control['sourceFingerprint'] != report['sourceFingerprint'] or
                        control['results'][0]['frames'] != protocol['demos'][demo]):
                        raise ValueError('Overhead control used a different build/workload')
                    from frame_times import _checksum
                    if _checksum(control['results'][0]['report']) != prior:
                        raise ValueError('Timing capture changed the fixed-step final framebuffer')
                    seconds = control['results'][0]['seconds']
                    session['controls'].append(dict(demo=demo, directory=control_dir.name,
                        noStatsSeconds=seconds, captureSeconds=report['statistics']['timedemo_seconds'],
                        observedOverheadPercent=100*(report['statistics']['timedemo_seconds']/seconds-1),
                        interpretation='Single matched pair includes timing noise; not a correction factor'))
                    write_json(output/'session.json', session)
        if runtime_sources() != session['runtimeSources']:
            raise ValueError('Benchmark tooling changed during the session')
        session['status'] = 'complete'
    except BaseException as error:
        session['status'] = 'failed'; session['error'] = str(error)
        raise
    finally:
        session['wallSeconds'] = time.monotonic()-started
        session['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        session['aggregate'] = aggregate(session['samples'])
        write_json(output/'session.json', session)
        write_index(output, session)
    print(output/'index.html')


def aggregate(samples):
    result = {}
    for demo in sorted({sample['demo'] for sample in samples}):
        values = [sample['statistics'] for sample in samples if sample['demo'] == demo]
        fps = [value['average_fps'] for value in values]
        result[demo] = dict(runs=len(values), fpsSamples=fps, medianAverageFps=statistics.median(fps),
                            minAverageFps=min(fps), maxAverageFps=max(fps),
                            median1PercentLow=statistics.median(v['low_1_percent_fps'] for v in values),
                            medianP99FrameMs=statistics.median(v['frame_time_percentiles_ms']['p99'] for v in values))
    return result


def write_index(output, session):
    table = []
    for sample in session['samples']:
        stats = sample['statistics']; name = sample['directory']
        table.append(f'<tr><td><a href="{html.escape(name)}/fps-versus-time.png">{html.escape(name)}</a></td>'
                     f'<td>{stats["average_fps"]:.2f}</td><td>{stats["minimum_fps"]:.2f}</td>'
                     f'<td>{stats["low_1_percent_fps"]:.2f}</td><td>{stats["frame_time_percentiles_ms"]["p99"]:.2f}</td>'
                     f'<td>{stats["timedemo_seconds"]:.3f}</td><td><a href="{name}/frames.csv">CSV</a> '
                     f'<a href="{name}/statistics.json">JSON</a></td></tr>')
    document = ('<!doctype html><meta charset="utf-8"><title>Frame timing report</title>'
                '<style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:0 20px;color:#24364a}'
                'table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:12px;border-bottom:1px solid #ccd}'
                'a{color:#245d93}pre{white-space:pre-wrap}</style>'
                f'<h1>{html.escape(session["label"])}: frame timing</h1>'
                f'<p>Status: <strong>{html.escape(session["status"])}</strong>. '
                'DOSBox-X i486, 320×200, fixed simulation step with real-clock timing.</p>'
                '<p>Each run has a separate FPS/time and frame-time plot. Sample indices identify slow workload locations; '
                'a curve alone does not identify the responsible engine function. Detailed profiling is a separate diagnostic.</p>'
                '<table><tr><th>Run / graph</th><th>Average FPS</th><th>Minimum FPS</th><th>1% low</th>'
                '<th>p99 ms</th><th>Demo seconds</th><th>Data</th></tr>'+''.join(table)+'</table>'
                '<p>1% low = reciprocal of the mean of the slowest ceil(1% × N) frame times. '
                'Frame percentiles use nearest rank. Timers and buffered stores add measurement cost; '
                'no disk writes or graphs occur inside measured frames. Elapsed positions include inter-frame gaps.</p>'
                '<p><a href="session.json">Session metadata, aggregates and overhead controls</a></p>'
                f'<pre>{html.escape(session.get("error", ""))}</pre>')
    (output/'index.html').write_text(document, encoding='utf-8')
    with (output/'summary.csv').open('w', newline='', encoding='utf-8') as stream:
        fields = ['demo', 'repetition', 'directory', 'average_fps', 'minimum_fps', 'low_1_percent_fps', 'timedemo_seconds', 'p99_ms']
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader()
        for sample in session['samples']:
            stats = sample['statistics']
            writer.writerow(dict(demo=sample['demo'], repetition=sample['repetition'], directory=sample['directory'],
                **{key: stats[key] for key in fields[3:-1]}, p99_ms=stats['frame_time_percentiles_ms']['p99']))


def compare_sessions(baseline: Path, candidate: Path, output: Path):
    a = read_json(baseline/'session.json'); b = read_json(candidate/'session.json')
    if a['status'] != 'complete' or b['status'] != 'complete':
        raise ValueError('Compare completed sessions only')
    if set(a['aggregate']) != set(b['aggregate']): raise ValueError('Sessions cover different demos')
    output = fresh_output(output)
    plt = pyplot(); results = {}
    for demo in a['aggregate']:
        groups = []
        environment = None; checksum = None
        for root, session in [(baseline, a), (candidate, b)]:
            runs = []
            for sample in session['samples']:
                if sample['demo'] != demo: continue
                report, rows = load_run(root/sample['directory'])
                if environment is None: environment = report['environment']
                if report['environment'] != environment: raise ValueError('Incompatible environment/data/protocol')
                if checksum is None: checksum = report['framebufferChecksum']
                if report['framebufferChecksum'] != checksum: raise ValueError('Final framebuffer checksum differs across builds/runs')
                runs.append(rows)
            if not runs: raise ValueError('Session demo has no runs')
            groups.append(runs)
        if len({len(run) for group in groups for run in group}) != 1: raise ValueError('Frame counts differ')
        median_times = [[statistics.median(run[index]['cadence_ms'] for run in group)
                         for index in range(len(group[0]))] for group in groups]
        delta = [new-old for old, new in zip(*median_times)]
        aa = a['aggregate'][demo]; bb = b['aggregate'][demo]
        results[demo] = dict(baseline=aa, candidate=bb,
            averageFpsChangePercent=100*(bb['medianAverageFps']/aa['medianAverageFps']-1),
            p99FrameTimeChangePercent=100*(bb['medianP99FrameMs']/aa['medianP99FrameMs']-1),
            meaning='Positive FPS change is faster; positive frame-time change is slower. Spread remains visible; no significance claim.')
        fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
        x = range(len(delta))
        for values, group, label in zip(median_times, groups, [a['label'], b['label']]):
            line, = axes[0].plot(x, [1000/v for v in values], linewidth=.9, label=label)
            axes[0].fill_between(x,
                [1000/max(run[i]['cadence_ms'] for run in group) for i in x],
                [1000/min(run[i]['cadence_ms'] for run in group) for i in x],
                color=line.get_color(), alpha=.12)
        axes[0].set_ylabel('Median frame-cadence FPS'); axes[0].legend()
        axes[1].plot(x, delta, color='#964b40', linewidth=.8); axes[1].axhline(0, color='#333', linewidth=.7)
        axes[1].set_ylabel('Candidate − baseline (ms)'); axes[1].set_xlabel('Measured sample index (same demo workload)')
        fig.suptitle(f'{demo}: aligned build comparison; positive ms delta is a regression')
        for ax in axes: ax.grid(alpha=.2)
        fig.tight_layout()
        save_charts(fig, output/f'{demo}-comparison')
        plt.close(fig)
        with (output/f'{demo}-frame-deltas.csv').open('w', newline='', encoding='utf-8') as stream:
            writer = csv.writer(stream); writer.writerow(['sample_index', 'baseline_median_ms', 'candidate_median_ms', 'delta_ms'])
            writer.writerows((index, old, new, new-old) for index, (old, new) in enumerate(zip(*median_times)))
    write_json(output/'comparison.json', dict(schemaVersion=1, baseline=str(baseline.resolve()),
        candidate=str(candidate.resolve()), baselineSessionSha256=sha256(baseline/'session.json'),
        candidateSessionSha256=sha256(candidate/'session.json'), demos=results))
    print(output/'comparison.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    run = commands.add_parser('run', help='Fresh-process timedemos and per-run graphs')
    run.add_argument('--label', required=True)
    run.add_argument('--output', type=Path, required=True)
    run.add_argument('--game-root', type=Path)
    run.add_argument('--tool-root', type=Path)
    run.add_argument('--data-root', type=Path)
    run.add_argument('--local-output')
    run.add_argument('--selector-profile', type=Path)
    run.add_argument('--runs', type=int, default=3, choices=range(1, 10))
    run.add_argument('--demos', nargs='+', choices=['demo1', 'demo2', 'demo3'])
    run.add_argument('--skip-build', action='store_true')
    run.add_argument('--no-bootstrap', action='store_true')
    run.add_argument('--overhead-controls', action='store_true', help='One uninstrumented matched control per demo')
    run.add_argument('--verify-replays', action='store_true', help='Separate two-run exact color/Z validation per demo; no timing claims')
    run.add_argument('--timeout', type=int, default=300)
    run.add_argument('--build-timeout', type=int, default=3600)
    report = commands.add_parser('report', help='Regenerate graphs from a recorded session')
    report.add_argument('directory', type=Path)
    compare = commands.add_parser('compare', help='Compare compatible completed sessions by frame index')
    compare.add_argument('baseline', type=Path); compare.add_argument('candidate', type=Path)
    compare.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'run': run_batch(args)
    elif args.command == 'compare': compare_sessions(args.baseline, args.candidate, args.output)
    else:
        session = read_json(args.directory/'session.json')
        for sample in session['samples']: plot_run(args.directory/sample['directory'])
        write_index(args.directory, session)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
