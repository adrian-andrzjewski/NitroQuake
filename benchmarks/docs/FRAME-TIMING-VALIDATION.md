# Frame timeline validation — 2026-11-08

The `nitroquake-frame-timeline-v1` workflow completed a live DOSBox-X batch
for NitroQuake Build 852: two timed runs each of demo1, demo2 and demo3,
one capture-off control per demo, and two separate color/Z correctness replays
per demo. All fifteen playbacks completed. No optimization gain is claimed.

## Measured results

These are medians of the two measured runs. Minimum FPS is the lower of the two
per-run minima. Percentiles and lows use frame-to-frame cadence, including gaps.

| Demo | Frames/run | Average FPS | Minimum FPS | 1% low FPS | p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| demo1 | 969 | 16.951997 | 7.446744 | 7.941724 | 120.213031 |
| demo2 | 985 | 17.283643 | 8.279190 | 8.651974 | 109.836578 |
| demo3 | 1090 | 15.875739 | 7.354067 | 8.245530 | 114.917755 |

The capture-on run took 0.020789%, 0.021226% and 0.019537% longer than its
capture-off control, respectively. Each is a single matched pair with the same
executable and framebuffer checksum; these observations include measurement
noise and are neither a correction factor nor physical 486 overhead estimates.

The protocol uses DOSBox-X 2026.08.31, the pinned i486 profile, VGA 320×200,
fixed simulation delta 0.0625 and the ordinary real DOS timer. Sound/input,
detailed profiling and per-frame checksum I/O are disabled during FPS collection.
These fixed-step diagnostics are not comparable to historical ordinary-clock
timedemos. Client replay does not measure local server AI or physics.

## Validation evidence

- Native BENCH486 build: complete strict i486 audit passed, with 315,621 relocated
  instructions, 529 startup rows, 9,207 provider instructions and zero exemptions.
- Native controlled-clock C harness passed: original sample order, elapsed gaps,
  existing timer reads, capacity handling and no in-frame export writes.
- All 18 suite host gates passed, including 11 frame-timeline tests covering
  cadence stalls, lows/percentiles, malformed/truncated data, provenance,
  staged-input changes and comparison compatibility/math.
- All six timing captures had complete ordered samples, no invalid/overflow
  frames and measured dimensions 320×200. Timer counters were 1,939, 1,971 and
  2,181 per run: two reads per measured frame plus one warm-up start read.
- Both complete color and Z streams matched exactly for every correctness pair.
  Repeated timing runs and their capture-off controls also matched final color
  checksums: demo1 1047377823, demo2 1887495667, demo3 3722973491.
- Offline `report` regenerated all six PNG/SVG pairs with an invalid game-root
  environment variable, establishing that recorded reports need no game checkout.
  Graphs for all three demos were inspected; a single slowest-frame callout
  avoids overlapping annotations. Updated generator hashes are recorded.
- The comparison CLI produced all three overlays and aligned CSV deltas from
  the first and second recorded repetitions. Inputs explicitly identify their
  derivation from the same batch/build. This validates comparison and
  repeatability, not a change in engine performance.

The broader game's previously recorded host-test debt remains documented in
`quake/docs/ledger/2026-11-08-commit-validation-and-test-debt.md`; these results
do not assert that those unrelated tests passed.

## Retained local outputs

Generated measurements and graphs remain ignored, outside source commits:

- `benchmarks/out/frame-timelines-validated/index.html`: all six graphs, CSV/JSON
  statistics and session metadata; full batch wall time 1,435.453 seconds.
- `benchmarks/out/frame-timeline-repeatability/`: same-build repetition overlays,
  frame deltas and comparison JSON.
- `benchmarks/out/frame-timeline-repeatability-inputs/`: explicitly derived
  comparison inputs with the original session hash.
- `quake/out/local-frame-timeline-v2/`: native executable, build manifest and ISA
  proofs. Executable SHA-256:
  `074cacdb39aa88f7210ca0fe5e1ce90be53266f95fb9a30ff0efbfec1ba5203d`.
- Each `source-result.json` references its preserved DOS staging archive and raw
  `FRAMTIME.CSV`; the session retains the exact measurement-tool source snapshot.

An earlier externally interrupted attempt remains under
`benchmarks/out/frame-timelines-validation/`, marked failed. Its partial results
are excluded from this completed batch. No archive, accepted build or PAK was
deleted or overwritten.

See [workflow and metric definitions](FRAME-TIMING.md) to reproduce the batch,
select another build, regenerate reports or compare compatible sessions.
