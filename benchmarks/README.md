# NitroQuake benchmarking suite

Run these commands from `benchmarks/`. PowerShell 7 and Python 3.9+ are required.
Core parsing, fixture generation and comparisons use Python's standard library.
The optional chart command additionally needs Matplotlib; install it in a local
virtual environment using `python -m pip install -r requirements-charts.txt`.
The game builder has its own compiler manifest and no Matplotlib dependency.

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

The [native QuakeC fixture](docs/QC-INTERPRETER-VALIDATION.md) compares all opcodes,
overlapping operands, control flow and x87 settings against a retained source
checkout without requiring game PAKs.

```powershell
$env:NITROQUAKE_GAME_ROOT = 'workspace\quake'
pwsh -NoProfile -File tools/bootstrap-dos.ps1
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
pwsh -NoProfile -File tools/smoke-dos.ps1 -NoBootstrap
pwsh -NoProfile -File tools/timedemo-dos.ps1 -Runs 3 -NoBootstrap -NoFpsStats
```

Every runtime runner also accepts `-GameRoot`. The environment variable propagates
to child processes and Python source-contract tests. Use absolute paths for
user-supplied inputs. Built-in scenarios, golden PCX files and emulator settings
resolve relative to this suite; renderer selector profiles resolve against the
game. Compiler output remains in the selected game's `out/` directory.

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

Compare the normal Nitro executable with the supplied stock executables using
`tools/compare-executables.ps1 -NitroManifest <absolute-build-manifest-path>`.
It retains all nine samples from three rotating rounds and verifies staged
inputs before producing `verified-summary.json`. Generate PNG, SVG and CSV with
`python tools/chart-comparison.py <verified-summary.json> --output <directory>`.
The chart also accepts the preserved historical verified-summary format; its
provenance explicitly identifies the recorded source and adds no new timings.
