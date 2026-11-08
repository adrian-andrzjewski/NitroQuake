# Reproducible frame-rate timelines

## Run all three demos

From the workspace root:

```powershell
python -m pip install -r benchmarks/requirements-charts.txt
python benchmarks/tools/frame-benchmark.py run --label "Baseline" --output benchmarks/out/baseline --runs 3 --no-bootstrap --overhead-controls
```

The default covers demo1, demo2 and demo3 with three repetitions each. Every run
uses a new DOSBox process and freshly staged PAKs without local configs. Demo
order rotates across repetitions to distribute host drift. The engine and strict
source-bound i486 audit build first, using a fresh isolated game output directory.
Accepted artifacts are preserved. `--local-output NAME` chooses that build name.

Without `--no-bootstrap`, the existing pipeline can install missing pinned
compiler/emulator tools. Legally obtained PAKs are required: pass `--data-root`
or use the game's `testdata/id1/`. `--game-root` selects an independent complete
game checkout; `--tool-root` selects another tool cache.

To repeat a compiled build, use its same `--local-output NAME`, add `--skip-build`
and choose a **new** `--output` directory. Freshness and ISA-proof checks still
apply. Old binaries without ordered export are rejected. `--demos demo2` focuses
a diagnostic. `--timeout` bounds each playback; `--build-timeout` bounds building.
Failed/partial attempts retain structured status and logs rather than being
silently resumed, overwritten or counted as complete measurements.
Runtime tooling is snapshotted and hash-pinned at session start; changing it
during the batch fails the session instead of mixing analysis implementations.

## Determinism and overhead

`tools/frame-timing-protocol.json` pins i486, 320×200 VGA, viewport/span settings,
disabled sound/input and simulation delta `0.0625` seconds. The engine already
seeds demo RNG with `srand(1)`. Transient console notifications are disabled.
Expected demo lengths are 969, 985 and 1,090 frames. PAK, DPMI, emulator binary,
profile, native executable and tooling hashes are recorded. Repeated runs require
matching final framebuffer checksums. Workload is fixed; timing values fluctuate.

`host_framerate` fixes simulation advancement while the real DOS timer measures
performance. Do **not** use `-parityclock`: it replaces presentation time and is
rejected with timing capture. These fixed-step diagnostics are a different
workload from historical ordinary-clock results and must not be mixed with them.

`-FrameTimings` implies the existing `-fpsstats` capture. Native code reuses its
two start/end timer reads and buffers duration plus elapsed endpoint as float32.
The existing timer-read counter also includes one warm-up frame-start read.
The extra endpoint buffer is 32 KiB at the 8,192-frame capacity. Ordered
`FRAMTIME.CSV` export occurs **after** playback and before the old summary sorts
the buffer. No per-frame disk writes, host polling, screenshots, Z checksums or
detailed PROFILE486 scopes are enabled. Overflow or invalid/missing samples fail.

Samples cover host-frame input/commands, rendering/presentation and audio update.
Their origin is the first measured frame start; elapsed endpoints retain gaps
between frames. The headline average uses Quake's timed interval, excluding
loading/export. Sampled work duration and the difference from headline time are
reported separately; curves are not stretched to conceal that distinction.

`--overhead-controls` adds one capture-off matched run per demo after its first
capture. It requires the same executable, workload and final checksum. Observed
time differences include noise and may be negative; they are not universal timer
corrections. Detailed profiling is separate. DOSBox measurements do not establish
physical 486 cache/timer behavior or physical-machine speed gains.

Add `--verify-replays` for a stronger determinism gate: before measuring each
demo, run two separate correctness replays and require identical complete color
and Z checksum streams. These passes use per-frame I/O and are kept outside the
FPS dataset. Their paths/hashes are recorded under `verification` in the session.

## Results and definitions

Open the session's `index.html`. Each run has separate `fps-versus-time.png` and
`.svg` graphs, ordered `frames.csv`, `statistics.json`, `source-result.json`,
`runner.log`, and `chart-provenance.json`. The graphs show instantaneous FPS,
trailing one-second throughput, average FPS, frame times, p99 and slow samples.
The original raw DOS CSV/native summary remain in referenced staging archives.
`session.json` includes aggregates, controls, build/protocol provenance and wall
time; `summary.csv` supports spreadsheets. Every completed sample is retained.

| Metric | Definition |
| --- | --- |
| Average FPS | Demo frames / Quake timedemo seconds |
| Instantaneous FPS | Reciprocal of the interval between successive captured frame-end timestamps |
| Sample throughput | Samples / sum of measured frame work |
| Minimum FPS | Reciprocal of longest frame-cadence interval |
| 1% / 0.1% low | Reciprocal of mean cadence interval of slowest `ceil(N × fraction)` frames |
| Frame percentiles | Nearest-rank p50, p90, p95, p99 and p99.9 cadence intervals, in milliseconds |
| Slow intervals | Consecutive samples at least 1.5× median cadence interval |
| Host process seconds | Launcher/preflight, DOS startup/playback and native post-processing |

Derived CSV retains raw host-frame work as `frame_seconds`/`frame_ms`/`work_fps`,
plus `cadence_seconds`/`cadence_ms`/`instantaneous_fps` and gaps. Both curves appear
in the frame-time panel so delays outside Host_Frame cannot disappear. The first
cadence interval starts at the capture origin. Float32 endpoint precision is
explicit in the source format; do not interpret sub-timer-scale differences as gains.

The new 1% low uses cadence intervals; the older native summary's arithmetic mean
of slow-frame FPS remains available unchanged. Slowest frames, intervals and
slowest-1% time share locate expensive workload sections. Sample indices are
not exact demo-file timestamps or source functions: use focused profiling to
establish causes. Client demo playback does not exercise local server AI/physics.

## Compare builds or regenerate graphs

Run another build with identical protocol/data and a different label/output/native
local-output name (or independent game checkout), then:

```powershell
python benchmarks/tools/frame-benchmark.py compare benchmarks/out/baseline benchmarks/out/candidate --output benchmarks/out/comparison
python benchmarks/tools/frame-benchmark.py report benchmarks/out/candidate
```

Comparison requires completed sessions with matching demos, protocol, emulator,
provider, data hashes and final frame checksums. Each demo gets PNG/SVG overlays,
sample-index-aligned candidate-minus-baseline frame-time CSV deltas and metrics in
`comparison.json`. Shaded bands show repeat ranges. Positive FPS change is faster;
positive milliseconds are slower. Frame-index alignment compares the same work
even when builds reach it at different elapsed times. All samples/spread remain
visible; no statistical-significance claim follows from a small median change.

`report` needs only recorded data and Matplotlib, without a game checkout or
DOSBox. Stable SVG IDs and omitted date metadata reduce figure differences;
generator/input hashes and Matplotlib versions are recorded explicitly.

Host tests: `python benchmarks/tools/test-frame-times.py` and
`python quake/tools/test-frame-timing-export.py`. The latter runs the native
capture/export functions with a controlled clock, checking order, real gaps,
zero in-frame I/O, invalid samples and overflow handling.
