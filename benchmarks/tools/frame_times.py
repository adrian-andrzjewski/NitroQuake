"""Strict raw-timing ingestion and statistics. Python standard library only."""
from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

SCHEMA = 1
MAX_FRAMES = 8192


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path: Path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def percentile(values, fraction):
    """Nearest-rank percentile, with p0 defined as the minimum."""
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered)*fraction)-1)]


def read_samples(path: Path, expected: int):
    if not 1 <= expected <= MAX_FRAMES:
        raise ValueError('Expected frame count is outside the engine capture limit')
    rows = []
    previous_end = 0.0
    with path.open(newline='', encoding='ascii') as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != ['sample_index', 'elapsed_seconds', 'frame_seconds']:
            raise ValueError('Unsupported raw timing CSV header')
        for index, row in enumerate(reader):
            if index >= expected or None in row or any(value is None for value in row.values()):
                raise ValueError('Extra or malformed timing sample')
            if int(row['sample_index']) != index:
                raise ValueError('Timing samples must be contiguous and remain in playback order')
            end = float(row['elapsed_seconds']); duration = float(row['frame_seconds'])
            if not math.isfinite(end) or not math.isfinite(duration) or duration <= 0 or end <= previous_end:
                raise ValueError('Non-finite, non-positive or non-monotonic frame timing')
            # Native elapsed endpoints are buffered as float32. Their precision
            # falls with duration; allow rounding, never a substantial overlap.
            tolerance = max(.000002, abs(end)*2e-7)
            if end-duration < previous_end-tolerance:
                raise ValueError('Timing samples overlap or precede the capture origin')
            rows.append(dict(sample_index=index, elapsed_seconds=end,
                             start_elapsed_seconds=previous_end,
                             work_start_elapsed_seconds=max(0.0, end-duration),
                             frame_seconds=duration, frame_ms=duration*1000,
                             work_fps=1/duration, cadence_seconds=end-previous_end,
                             cadence_ms=(end-previous_end)*1000,
                             inter_frame_gap_ms=max(0.0, end-previous_end-duration)*1000,
                             instantaneous_fps=1/(end-previous_end)))
            previous_end = end
    if len(rows) != expected:
        raise ValueError(f'Incomplete timing CSV: {len(rows)} samples, expected {expected}')
    return rows


def summarize(rows, timedemo_seconds: float):
    if not math.isfinite(timedemo_seconds) or timedemo_seconds <= 0:
        raise ValueError('Timedemo duration must be finite and positive')
    times = [row['cadence_seconds'] for row in rows]
    count = len(times)
    slow_count = max(1, math.ceil(count*.01))
    slow_tenth = max(1, math.ceil(count*.001))
    descending = sorted(times, reverse=True)
    mean = statistics.fmean(times)
    total = math.fsum(times)
    work_total = math.fsum(row['frame_seconds'] for row in rows)
    elapsed = rows[-1]['elapsed_seconds']
    threshold = statistics.median(times)*1.5
    slow = sorted(rows, key=lambda row: row['cadence_seconds'], reverse=True)[:10]
    intervals = []
    for row in rows:
        if row['cadence_seconds'] < threshold:
            continue
        if intervals and row['sample_index'] == intervals[-1]['last_sample']+1:
            interval = intervals[-1]
            interval.update(last_sample=row['sample_index'], end_seconds=row['elapsed_seconds'])
            interval['frame_work_seconds'] += row['frame_seconds']
            interval['interval_seconds'] += row['cadence_seconds']
            interval['frames'] += 1
        else:
            intervals.append(dict(first_sample=row['sample_index'], last_sample=row['sample_index'],
                                  start_seconds=row['start_elapsed_seconds'], end_seconds=row['elapsed_seconds'],
                                  frame_work_seconds=row['frame_seconds'], interval_seconds=row['cadence_seconds'], frames=1))
    return dict(frames=count, timedemo_seconds=timedemo_seconds,
                average_fps=count/timedemo_seconds, sample_throughput_fps=count/work_total,
                capture_cadence_fps=count/total,
                minimum_fps=1/max(times), maximum_fps=1/min(times),
                median_fps=1/statistics.median(times),
                low_1_percent_fps=1/statistics.fmean(descending[:slow_count]),
                slowest_1_percent_time_share_percent=100*math.fsum(descending[:slow_count])/total,
                low_0_1_percent_fps=1/statistics.fmean(descending[:slow_tenth]),
                slowest_1_percent_frames=slow_count, mean_frame_ms=mean*1000,
                frame_time_percentiles_ms={name: percentile(times, fraction)*1000 for name, fraction in
                    [('p50', .5), ('p90', .9), ('p95', .95), ('p99', .99), ('p99_9', .999)]},
                standard_deviation_frame_ms=statistics.pstdev(times)*1000,
                sampled_work_seconds=work_total, capture_elapsed_seconds=elapsed,
                inter_frame_gap_seconds=max(0.0, elapsed-work_total),
                headline_minus_sampled_seconds=timedemo_seconds-work_total,
                spike_threshold_ms=threshold*1000,
                spike_frames=sum(t >= threshold for t in times), slowest_frames=slow,
                slow_intervals=sorted(intervals, key=lambda item: item['interval_seconds'], reverse=True)[:10])


def ingest(result_path: Path, output: Path, label: str, protocol: dict):
    """Accept one independently staged, completed run. Never accept partial data."""
    data = read_json(result_path)
    if data.get('instrumentation') or data.get('deterministicPresentationClock') or not data.get('frameFpsStats'):
        raise ValueError('Frame analysis requires lightweight real-clock timings, not PROFILE486/parityclock')
    if data.get('frameChecksums') or data.get('zBufferChecksums') or data.get('frameCaptureIndex') is not None:
        raise ValueError('Per-frame checksum/capture I/O is forbidden in performance captures; use a separate replay')
    if data.get('isaAuditStatus') != 'PASS':
        raise ValueError('The native build must have passed its ISA audit')
    if data.get('autoexecCommands') != protocol['autoexecCommands']:
        raise ValueError('Simulation/render cvars differ from the benchmark protocol')
    if data.get('profileSha256', '').upper() != protocol['dosboxProfileSha256']:
        raise ValueError('Emulator profile differs from the benchmark protocol')
    if data.get('quakeExtraArgs') != protocol['quakeExtraArgs']:
        raise ValueError('Game arguments differ from the benchmark protocol')
    if data.get('cpuTarget') != 'i486' or data.get('demo') not in protocol['demos']:
        raise ValueError('Unsupported CPU or demo')
    if len(data['results']) != 1:
        raise ValueError('Batch inputs must contain one freshly staged run')
    run = data['results'][0]
    expected = protocol['demos'][data['demo']]
    native = run['fpsStats']
    capture = native.get('frame_timing', {})
    if capture.get('schema') != 1 or [capture.get('width'), capture.get('height')] != [320, 200]:
        raise ValueError('Native capture schema or measured resolution differs from 320x200')
    if (run['frames'] != expected or native['fps']['stored_frames'] != expected or
        native['fps']['measured_frames'] != expected or native['fps']['overflow_frames'] or
        native['fps']['invalid_frames'] or native['benchmark']['frames'] != expected):
        raise ValueError('Capture is incomplete, invalid, overflowed or has the wrong demo length')
    raw = Path(run['frameTimesPath'])
    rows = read_samples(raw, expected)
    stats = summarize(rows, float(run['seconds']))
    if abs(float(native['benchmark']['duration_seconds'])-float(run['seconds'])) > .000002:
        raise ValueError('Native statistics and timedemo duration disagree')
    stage = Path(data['stagingRoot'])
    assets = read_json(stage/'staged-data.json')
    if isinstance(assets, dict): assets = [assets]
    tooling = read_json(stage/'tooling-provenance.json')
    if not assets or not any(asset['name'].lower() == 'pak0.pak' for asset in assets):
        raise ValueError('PAK provenance is missing')
    # Re-hash the actual staged inputs, not the source filenames alone.
    for asset in assets:
        if Path(asset['name']).name != asset['name']:
            raise ValueError('Invalid asset provenance filename')
        if sha256(stage/'quake/id1'/asset['name']).upper() != asset['sha256'].upper():
            raise ValueError('Staged PAK changed after measurement')
    exe = stage/'quake/qbench.exe'
    dpmi = stage/'quake/cwsdpmi.exe'
    if sha256(dpmi).upper() != data['dpmiHostSha256'].upper():
        raise ValueError('Staged provider changed after measurement')
    environment = dict(protocol=protocol, dosboxVersion=data['dosboxVersion'],
                       dosboxExecutableSha256=data['dosboxExecutableSha256'],
                       dosboxProfileSha256=data['profileSha256'],
                       pakSha256={asset['name']: asset['sha256'].lower() for asset in assets},
                       dpmiHost=data['dpmiHost'], dpmiSha256=sha256(dpmi))
    report = dict(schemaVersion=SCHEMA, label=label, demo=data['demo'], statistics=stats,
                  environment=environment, executableSha256=sha256(exe),
                  sourceFingerprint=data['sourceFingerprint'], sourceTreeFingerprint=data['sourceTreeFingerprint'],
                  framebufferChecksum=_checksum(run['report']), timerReads=native['fps']['timer_reads'],
                  sourceResult=str(result_path.resolve()), sourceResultSha256=sha256(result_path),
                  rawSource=str(raw.resolve()), rawSourceSha256=sha256(raw), tooling=tooling,
                  metricDefinitions='average_fps=demo_frames/demo_seconds; instantaneous_fps=1/(current_end-previous_end); low_1_percent_fps=1/mean(slowest ceil(1%*N) cadence intervals); nearest-rank cadence-time percentiles; raw frame_seconds and work_fps cover Host_Frame work, cadence includes inter-frame gaps, loading/export excluded')
    output.mkdir(parents=True, exist_ok=True)
    with (output/'frames.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    report['framesCsvSha256'] = sha256(output/'frames.csv')
    write_json(output/'statistics.json', report)
    return report, rows


def _checksum(text):
    import re
    match = re.search(r'framebuffer-checksum\s+(\d+)', text)
    if not match:
        raise ValueError('Final framebuffer checksum is missing')
    return int(match[1])


def load_run(path: Path):
    report = read_json(path/'statistics.json')
    if report['schemaVersion'] != SCHEMA or sha256(path/'frames.csv') != report['framesCsvSha256']:
        raise ValueError('Run data schema or hash mismatch')
    with (path/'frames.csv').open(newline='', encoding='utf-8') as stream:
        rows = [{key: int(value) if key == 'sample_index' else float(value)
                 for key, value in row.items()} for row in csv.DictReader(stream)]
    return report, rows
