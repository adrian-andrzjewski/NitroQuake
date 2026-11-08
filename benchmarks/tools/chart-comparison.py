#!/usr/bin/env python3
"""Plot an existing verified executable comparison; never runs a benchmark."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from pathlib import Path


def chart(source: Path, output: Path) -> None:
    report = json.loads(source.read_text(encoding='utf-8-sig'))
    if report.get('verified') is not True:
        raise ValueError('Input must be a verified comparison summary')
    variants = list(report['summary'])
    if not variants:
        raise ValueError('Comparison has no variants')
    labels = {'original': 'Quake.exe', 'quake486': '486quake.exe',
              'nitro': report.get('nitroVersion', 'NitroQuake')}
    rows = []
    for variant in variants:
        values = report['summary'][variant]
        samples = values['fpsSamples']
        if not samples or len(samples) != len(values['secondsSamples']) or any(float(x) <= 0 for x in samples):
            raise ValueError(f'Invalid or missing samples for {variant}')
        rows.append((variant, labels.get(variant, variant), values))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    output.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(11, 6))
    values = [float(row[2]['medianFps']) for row in rows]
    bars = ax.bar([row[1] for row in rows], values, color=['#82909e', '#b76c36', '#426a9c'])
    for bar, value in zip(bars, values):
        ax.text(bar.get_x()+bar.get_width()/2, value+max(values)*.015, f'{value:.1f} FPS', ha='center')
    ax.set_ylim(0, max(values)*1.25)
    ax.set_ylabel('Median recorded timedemo FPS')
    ax.set_title('Recorded executable comparison')
    fig.text(.03, .035, 'DOSBox measurements. Consult the source report for configuration and comparability limits.', fontsize=9)
    fig.tight_layout(rect=(0, .06, 1, 1))
    for extension in ('png', 'svg'):
        fig.savefig(output/f'comparison-chart.{extension}', dpi=150)
    plt.close(fig)
    with (output/'chart-data.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['variant', 'label', 'median_fps', 'median_seconds', 'fps_samples', 'seconds_samples'])
        for variant, label, values in rows:
            writer.writerow([variant, label, values['medianFps'], values['medianSeconds'],
                             json.dumps(values['fpsSamples']), json.dumps(values['secondsSamples'])])
    (output/'chart-provenance.json').write_text(json.dumps({
        'schemaVersion': 1, 'source': str(source.resolve()),
        'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'generatorSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'recordedRuns': report.get('runs'), 'newMeasurements': False,
    }, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('summary', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    chart(args.summary, args.output)
