# NitroQuake benchmarking suite

Run these commands from `benchmarks/`. PowerShell 7 and Python 3.9+ are required.
Core parsing, fixture generation and comparisons use Python's standard library.
The optional chart command additionally needs Matplotlib; install it in a local
virtual environment using `python -m pip install -r requirements-charts.txt`.
The game builder has its own compiler manifest and no Matplotlib dependency.
The game exposes two supported DOS configurations, `i486-release` and
`c-reference`. Per-routine selector combinations, experimental variants and
dead-scratch probes belong to this benchmark suite and are forwarded to the
game's internal selector-driven build backend.

For per-frame FPS/time graphs across demo1, demo2 and demo3, see the
[frame timeline workflow](docs/FRAME-TIMING.md):

```powershell
python tools/frame-benchmark.py run --label "Baseline" --output out/baseline-timelines --runs 3 --overhead-controls
```

The [frame timing validation record](docs/FRAME-TIMING-VALIDATION.md) documents
the completed three-demo batch, replay checks and measured capture overhead.

For renderer, physics, QuakeC, collision and active audio attribution, use the
[whole-engine profiling workflow](docs/ENGINE-PROFILING.md). The
[320×200 i486 analysis](docs/ENGINE-PERFORMANCE-20261108.md) ranks measured costs,
records observer overhead and distinguishes emulator evidence from hardware
expectations.

The [measured i486 optimization record](docs/I486-OPTIMIZATION-20261108.md) covers
the accepted warp-table and QuakeC changes, independent attribution, combined
timings, release checks and a reproducible matched-comparison graph.

The [collision optimization record](docs/I486-COLLISION-OPTIMIZATION-20261109.md)
adds Build 856 server work reductions, native differential fixtures and matched
local gameplay results.

The [native QuakeC fixture](docs/QC-INTERPRETER-VALIDATION.md) compares all opcodes,
overlapping operands, control flow and x87 settings against a retained source
checkout without requiring game PAKs.

The [native collision fixtures](docs/COLLISION-VALIDATION.md) compare move-clip
initialization and area-tree traversal against a retained source checkout,
including complete clip data, helper order, ABI and x87 state without PAKs.

```powershell
pwsh -NoProfile -File tools/bootstrap-dos.ps1
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
pwsh -NoProfile -File tools/smoke-dos.ps1 -NoBootstrap
pwsh -NoProfile -File tools/timedemo-dos.ps1 -Runs 3 -NoBootstrap -NoFpsStats
```

The sibling `quake/` checkout is discovered automatically. Every runtime runner
also accepts `-GameRoot` when using a different checkout; the environment
variable propagates to child processes and Python source-contract tests. Use
absolute paths for user-supplied inputs. Built-in scenarios, golden PCX files
and emulator settings resolve relative to this suite; renderer selector
profiles resolve against the game. Compiler output remains in the selected
game's `out/` directory.

Supply legally obtained `pak0.pak` and optionally `pak1.pak` with `-DataRoot`,
or put them in the selected game's `testdata/id1/`. PAKs are hash-verified when
staged, using hardlinks where possible and copies otherwise. User configurations
and autoexec files are excluded. Baseline executables belong in ignored
`baselines/`; [local artifact hashes](baselines/local-artifacts.json) preserve
the migration inventory. Original game binaries and licensed PAKs are not shipped.

`run-tests.ps1` composes the game's verification runner with suite host checks,
DOS startup, server coverage, native C/assembly fixtures, image parity and
timedemos. `-HostOnly` runs suite host checks without repeating the game's host
runner; run that from the game checkout separately. `-SkipRendering` and
`-SkipSlow` omit their named runtime gates, and report them as skipped.
Historical test debt is documented in the game's
`docs/ledger/2026-11-08-commit-validation-and-test-debt.md`.

See [interfaces](docs/INTERFACES.md), [operations and historical results](docs/OPERATIONS.md),
[render validation](docs/RENDERING-VALIDATION.md), and
[comparison methodology](docs/BENCHMARK-COMPARISON.md).
The [reorganization validation record](docs/REORGANIZATION-VALIDATION.md) lists
passing checks, retained test debt and checks deferred by the external hold.
Instrumented profiles rank costs; performance acceptance uses matched
uninstrumented runs with deterministic correctness evidence. DOSBox timings
are emulator measurements and do not establish physical 486 performance.
Use the [physical 486 acceptance procedure](docs/PHYSICAL-486-ACCEPTANCE.md)
when a real target is available; emulator runs cannot satisfy that gate.
The [2026-11-15 release-profile report](docs/ENGINE-PROFILING-20261115.md)
refreshes attribution against the current i486 release selector set.

Compare the normal Nitro executable with the supplied stock executables using
`tools/compare-executables.ps1 -NitroManifest <absolute-build-manifest-path>`.
It retains all nine samples from three rotating rounds and verifies staged
inputs before producing `verified-summary.json`. Generate PNG, SVG and CSV with
`python tools/chart-comparison.py <verified-summary.json> --output <directory>`.
The chart also accepts the preserved historical verified-summary format; its
provenance explicitly identifies the recorded source and adds no new timings.

## Portable MS-DOS benchmark ISO

Build a self-contained, non-bootable ISO from `benchmarks/`:

```powershell
pwsh -NoProfile -File tools/build-launcher-iso.ps1
```

The builder makes a fresh i486 game build, verifies the packaged comparison
executables against `baselines/local-artifacts.json`, and includes legally
obtained `pak0.pak` and `pak1.pak` from `quake/testdata/id1/`. Override those
inputs with `-GameRoot`, `-DataRoot`, `-ToolRoot`, or `-NitroExecutable` when
needed. The default image is `benchmarks/out/NitroQuake-Portable.iso`; use
`-OutputPath` to choose another destination and `-Force` to replace that
portable image. The retained `../out/NitroQuake-Benchmark.iso` is protected.

Boot DOS with a CD-ROM driver and MSCDEX, switch to the assigned CD letter,
then run `START` from the disc root or `\NQ`. The real-mode startup locates the
disc and a writable fixed disk, copies the small launcher and DPMI host to
`\NQDATA`, and starts the keyboard menu. No fixed drive letter or mount path is
assumed; the only manual step is switching DOS to the CD's assigned letter to
run `START`. No DOSBox configuration or writes to the ISO are required.
Benchmark profiles and logs remain on the writable disk. The included
`README.TXT` covers menu shortcuts and direct batch commands.

The previous launcher notes depended on DOSBox `imgmount`, a fixed `D:\NQ`
mount, and fixed `C:\N` output paths. Those assumptions failed when the image
or writable disk used other letters and could not run on an ordinary DOS
machine. The new startup uses DOS CD-ROM discovery and fixed-disk/writable-path
probing; all engine variants receive the same PAKs, VGA 320x200 mode, viewsize
100, and disabled audio. A run of demo1, demo2, or demo3 rotates which engine
runs first; the full batch keeps that rotation across all three demos.
