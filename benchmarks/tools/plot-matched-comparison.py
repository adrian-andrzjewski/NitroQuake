"""Plot retained matched control/candidate groups; never use parity replay FPS."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics


def summarize(session):
    rows = []
    for name, group in session['groups'].items():
        if group['kind'] not in ('timing', 'local'):
            continue
        samples = group['samples']
        if (len(samples['control']) != len(samples['candidate']) or
                any(len(samples[v]) < 3 or any(not math.isfinite(t) or t <= 0 for t in samples[v])
                    for v in ('control', 'candidate'))):
            raise ValueError(f'{name}: require at least three positive timing samples per variant')
        medians = {v: statistics.median(samples[v]) for v in ('control', 'candidate')}
        frames = group['frames']
        pairs = [100 * (c / n - 1) for c, n in zip(samples['control'], samples['candidate'])]
        rows.append(dict(workload=group['workload'], kind=group['kind'],
                         sound=group['sound'], frames=frames,
                         control_fps=frames / medians['control'],
                         candidate_fps=frames / medians['candidate'],
                         median_fps_change_percent=100 * (medians['control'] / medians['candidate'] - 1),
                         paired_change_min_percent=min(pairs), paired_change_max_percent=max(pairs),
                         control_seconds=json.dumps(samples['control']),
                         candidate_seconds=json.dumps(samples['candidate'])))
    if not rows:
        raise ValueError('No matched timing groups')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    session_bytes = args.session.read_bytes()
    session = json.loads(session_bytes.decode('utf-8-sig'))
    if session['status'] not in ('measured-awaiting-final-review', 'validated'):
        raise ValueError('Session is incomplete')
    audit = json.loads(args.session.with_name('audit.json').read_text(encoding='utf-8-sig'))
    if audit['status'] != 'PASS' or audit['sessionSha256'].lower() != hashlib.sha256(session_bytes).hexdigest():
        raise ValueError('Require a passing audit bound to this exact session')
    rows = summarize(session)
    if args.output.exists():
        raise ValueError('Choose a fresh output directory')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    args.output.mkdir(parents=True)
    with (args.output / 'comparison.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    labels = [r['workload'] + (' / sound' if r['sound'] else ' / silent') for r in rows]
    fig, axes = plt.subplots(1, 2, figsize=(13, 6), gridspec_kw={'width_ratios': [1, 1.2]})
    positions = list(range(len(rows)))
    for offset, variant, color in [(-.18, 'control', '#667085'), (.18, 'candidate', '#167d9a')]:
        axes[0].barh([i + offset for i in positions], [r[variant + '_fps'] for r in rows],
                     height=.33, label=variant.title(), color=color)
    axes[0].set_yticks(positions, labels)
    axes[0].invert_yaxis()
    axes[0].set_xlabel('Median FPS (zero-based axis)')
    axes[0].legend(loc='upper center', bbox_to_anchor=(.5, 1.09), ncol=2, frameon=False)
    deltas = [r['median_fps_change_percent'] for r in rows]
    axes[1].barh(positions, deltas, height=.6,
                 color=['#137e62' if d >= 0 else '#b54739' for d in deltas])
    for i, row in enumerate(rows):
        axes[1].plot([row['paired_change_min_percent'], row['paired_change_max_percent']],
                     [i, i], color='#101828', linewidth=2)
        axes[1].annotate(f"{deltas[i]:+.6f}%", (max(deltas[i], row['paired_change_max_percent']), i),
                         xytext=(7, 0), textcoords='offset points', va='center', fontsize=9)
    axes[1].set_yticks(positions, labels)
    axes[1].invert_yaxis()
    axes[1].axvline(0, color='#667085', linewidth=.8)
    axes[1].set_xlabel('FPS change (%) - lines show observed paired range')
    axes[1].margins(x=.3)
    fig.suptitle('NitroQuake: combined optimizations versus retained control', fontsize=14)
    fig.text(.5, .015, 'DOSBox-X 486 / fixed 33445 cycles / 320x200 / 3 pairs per group. '
             'Emulator results; parity replay timing excluded.', ha='center', fontsize=9)
    fig.tight_layout(rect=(0, .04, 1, .94))
    for suffix in ('png', 'svg'):
        fig.savefig(args.output / ('comparison.' + suffix), dpi=160)
    plt.close(fig)
    (args.output / 'provenance.json').write_text(json.dumps(dict(
        session=str(args.session.resolve()), sessionSha256=hashlib.sha256(session_bytes).hexdigest(),
        scriptSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        matplotlibVersion=matplotlib.__version__, scope='Matched timing groups only; observed range is not a confidence interval.'),
        indent=2) + '\n', encoding='utf-8')
    print(args.output)


if __name__ == '__main__':
    main()
