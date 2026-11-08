# Measured i486 optimizations â€” 2026-11-08

Two changes remove repeated work without reducing rendering quality or simulation
work: cached underwater warp geometry tables and opcode-local QuakeC operand
resolution. The improvements are modest. This record separates their independent
measurements from verification of the combined release.

## Scope and method

The control is game revision `fd2b7a559f9838a539f5075c83ebf3a2543c4f9f` (Build 852).
Both candidate changes were developed independently against that control, then
combined without other engine changes. The existing AI leaf-query cache is already
in the control and contributes no new gain reported here.

Production game commits are `10db93c` (warp geometry) and `b7aef96` (QuakeC
operands). The final tested sources and ledgers are committed without changing
their working bytes. Both source-bound binaries remain fresh after these commits.

All performance captures use DOSBox-X 2026.08.31, dynamic core, `cputype=486`,
FPU 387, **fixed 33445 cycles**, 32 MiB and VGA 320Ã—200. PAKs, maintained CWSDPMI,
compiler profile and runtime commands are pinned in retained results. Three pairs
per workload alternate execution order: control/candidate, candidate/control,
control/candidate. Demos contain 969/985/1090 measured frames. Local games run
256 frames after 64 warm-up frames on e1m1/e1m2, with god mode, forward movement
and firing. Simulation advances by 0.0625 seconds, fixed from startup in local
captures. Local captures compare the complete per-function statement-count CSV
and final framebuffer/selected numeric simulation checksums within each group.

Timing uses uninstrumented BENCH486 binaries with per-frame FPS and color/Z stream
collection disabled. Local captures retain their fixed boundary/state and QuakeC
count bookkeeping in both variants. Final-state hashes and statement counts are
useful guards, not exhaustive proofs of every intermediate gameplay state.
Detailed profiling runs are excluded from all gains below.

Combined correctness replays use a separate accelerated max-cycle profile with
the deterministic presentation clock. A control probe reproduces retained fixed-
cycle color/Z streams and raw PCX bytes; all three combined demo pairs also match
the retained control bytes. **Accelerated replay FPS never supplies performance
evidence.** Full timings retain the original fixed-cycle profile.

## Independent attribution

| Candidate | Test population | Control pooled FPS | Candidate pooled FPS | FPS change |
|---|---|---:|---:|---:|
| Warp tables | Three pairs Ã— three demos | 16.654398 | 16.658120 | +0.022348% |
| QuakeC operands | Three pairs Ã— two maps Ã— sound off/on | 22.372902 | 22.405018 | +0.143550% |

Pooled FPS is total measured frames divided by total elapsed time across all runs,
not the arithmetic mean of run FPS. Demo and local populations remain separate.

Warp's gain is concentrated in demo2 (+0.071831% median FPS); demo1 changes
-0.000110% and demo3 +0.000004%. QuakeC's four independent local group gains range
from +0.138305% to +0.148910%. Native ledgers retain each full table and decision.
These independent captures are not added together to predict a combined gain.

### Warp geometry tables

`D_WarpScreen` reuses assembly row/column tables until viewport, screen dimensions,
source stride/address or the complete x87 control word changes. Time phase and
pixel copying stay per-frame. The old table builder is used on misses; assembly
does not delegate the work to C. Static storage costs 9,304 bytes; per-call stack
allocation falls by 9,264 bytes. The renderer is single-threaded and no table
pointer escapes the routine.

The native differential fixture passes 1,512 cases covering three geometries,
twelve x87 settings, cold/hit paths and independently changed inputs. Destination
and guard bytes, preserved registers, ESP, DF, CW, TOP, preloaded x87 values and
tag word match the original assembly wrapper. Initial diagnostic failures came
from an undersized synthetic source buffer in the fixture; these excluded records
are retained separately, and the corrected fixture passed before acceptance.

### QuakeC operand resolution

`PR_ExecuteProgram` resolves only operands consumed by the dispatched opcode.
Branch displacements and unused fields no longer cause unconditional global
pointer setup. Arithmetic expressions, profiling, tracing, calls, returns and
error behavior remain. It allocates no new runtime state.

Generated i486 code removes six eager instructions from the common dispatch
header, keeps the runaway counter in a register and reduces stack locals from
44 to 28 bytes. Arithmetic cases still need their operands. The object text grows
by 768 bytes (0x12e0 â†’ 0x15e0), which is an instruction-cache tradeoff requiring
physical-hardware measurement.

The [reusable native fixture](QC-INTERPRETER-VALIDATION.md) passes 11,076 cases:
all 66 opcodes, ten input/alias variants, twelve x87 precision/rounding settings,
flow/error cases and mixed overlapping programs. It compares complete fixture
globals, edicts, function/profile counters, stack/error and FPU state. Both sides
use the actual retained compiler flags, including `-ffast-math`; signed-zero,
subnormal and non-finite patterns are differential tests of that build rather
than claims of strict IEEE behavior.

## Combined artifact and final gates

All 45 handoffs / 48 native executions completed. A separate retained-evidence
audit verifies the exact session/result/build-manifest hashes, compatibility
proofs, staged environments, 36 parity artifacts, raw local reports and complete
QuakeC count files. It independently recalculates the timing aggregates.

| Combined workload | Control median FPS | Candidate median FPS | FPS change |
|---|---:|---:|---:|
| demo1, silent | 16.955343 | 16.955332 | -0.000068% |
| demo2, silent | 17.287106 | 17.299526 | +0.071847% |
| demo3, silent | 15.878670 | 15.878671 | +0.000001% |
| e1m2, silent | 21.868398 | 21.900987 | +0.149021% |
| e1m1, silent | 23.503418 | 23.536090 | +0.139010% |
| e1m2, sound | 21.200293 | 21.231546 | +0.147418% |
| e1m1, sound | 23.071487 | 23.103409 | +0.138359% |

Pooling nine demo runs per variant: **16.654397 â†’ 16.658122 FPS (+0.022370%)**,
9,132 measured frames each, 548.323677 â†’ 548.201047 seconds. Pooling twelve local
runs per variant: **22.372894 â†’ 22.405024 FPS (+0.143610%)**, 3,072 frames each,
137.309011 â†’ 137.112104 seconds. The near-zero demo1 regression is not hidden.
Three pairs provide an observed repeatability range, not a confidence interval
or evidence about all maps, play styles and real hardware.

The generated [comparison graph](../out/integrated-comparison-chart-final-20261108/comparison.png)
shows zero-based FPS bars alongside percentage changes and observed paired ranges.
The corresponding [CSV](../out/integrated-comparison-chart-final-20261108/comparison.csv)
retains every elapsed-time sample. From `benchmarks/`, regenerate into a fresh path:

```powershell
python tools/plot-matched-comparison.py --session out/integrated-validation-20261108/session.json --output out/integrated-comparison-chart-copy
```

The optional Matplotlib dependency uses the suite's existing chart requirements.
The tool requires an audit bound to the exact session, rejects non-finite/incomplete
timings and excludes parity replay groups. Its regression-retention and replay-
exclusion checks passed; the produced PNG was visually inspected.

Both normal and BENCH486 builds pass complete i486 compatibility auditing with
zero above-target, unknown or exempt instructions. The combined BENCH486 audit
covers 316,311 relocated instructions; normal covers 163,886. Each also verifies
529 embedded startup instructions and 9,207 maintained provider instructions.

Normal and BENCH486 `pr_exec.obj` text is byte-identical (5,600 bytes); the
preprocessed warp function bodies also match. This verifies that these two
optimizations are present in the normal release, without claiming whole-binary
equivalence between diagnostic and normal builds.

| Artifact | SHA-256 |
|---|---|
| Retained control BENCH486 | `02029D4A19D4DF01193354A35DB8AAE79A23A2B98C24DAC16C60492C1472A2B4` |
| Combined BENCH486 | `367902E6643BB231A8D906E4C91226BA67199837C364263527414E74BFDCE221` |
| Combined normal release | `9AA178C5B1D8C9BC982F223A039487E68BAFC36A3B9AB3EC16B08A4F299DCCB0` |

Only two normalized engine source files differ across 435 C/H/S/INC inputs.
The combined source is identical to the independently measured implementations:
`pr_exec.c` SHA-256 `e19a3c3a2fe33956adfad2d726a87d71bc5a1dae47d9090d39588e68d786baa1`;
`asm486_experiments.s` SHA-256
`8bece8906cd87c4ddbb902cb882b4a8de6457c10edb84525556be241c3485a88`.

Automatic identity is **NitroQuake v0.999, Build 854** (471 accepted + 383 rejected
attempts). The two classified ledger additions drive this number; there is no
manual version-header edit.

The normal release completed its 969-frame demo1 smoke test and scripted local
e1m2 gameplay with sound enabled, then exited cleanly. Two inspected 320×200 PCX
captures show gameplay and the console's automatic Build 854 identity. Native
device metadata confirms 11025 Hz, stereo, 16-bit mixing; this is device/runtime
evidence rather than a subjective listening test. Normal console timing rounds
to 0.1 seconds/FPS and is excluded from marginal gain calculations.

The final public QuakeC fixture independently rebuilt reference/candidate code
and passed all 11,076 comparisons using the current committed driver/helper.
Its metadata pins source headers, compiler/flags, generated/preprocessed code,
objects, executable, emulator/provider and the execution record.

The benchmark suite's 19 host gates pass against the combined tree. The native
identity test passes, and documentation checks pass across 670 documents and
657 ledger records. Existing unrelated native host-test debt remains documented
in the game's `2026-11-08-commit-validation-and-test-debt.md`; this record does not
claim that entire legacy suite passes.

## Evidence and reproduction

Paths here are relative to the workspace, with generated evidence intentionally
kept outside the game source and excluded from Git:

- `benchmarks/out/warp-cache-validation-20261108/`: 24 handoffs / 30 executions,
  exact three-demo parity, matched timings and passing retained-evidence audit.
- `benchmarks/out/qc-operands-validation-20261108/`: 24 local captures, matching
  selected state and complete QuakeC counts, and passing retained-evidence audit.
- `benchmarks/out/integrated-validation-20261108/`: combined captures, copied
  build manifests, source/runner pins, raw native reports and session record.
- `out/integrated-20261108/out/local-integrated-release-v1/`: normal release
  executable, source-bound build manifest, ISA audit and disassembly evidence.
- `out/integrated-release-code-equivalence.json`: normal/BENCH opcode text and
  warp preprocessed-body comparison.
- `benchmarks/out/integrated-validation-20261108/post-commit-artifacts.json`:
  both compiled artifacts remain source-bound and fresh after native commits.
- `benchmarks/out/integrated-release-smoke-20261108/`: successful normal runtime,
  audio/device/identity logs, raw PCX images and their checked dimensions/hashes.
- `benchmarks/out/qc-interpreter-final-validation-20261108/`: final source-built
  native fixture, exact compiler inputs and passing execution record.
- `benchmarks/out/integrated-validation-20261108/final-delivery-audit.json`:
  current fixture/chart pins, normal smoke, inspected capture dimensions,
  normalized main-versus-compiled source equality and clean owned native trees.

The combined session SHA-256 is
`A7CF911EAC923E6D06EBC50D6C60736CAB5F01EFA07B19E7B5BA8CAC10907F0F`.
The retained manifest records the original base revision because compilation
preceded promotion commits. Exact source bytes, inventory, compiler/artifact
hashes, and the post-commit freshness/compatibility checks bind it to the reviewed
content; generated manifests were not rewritten to pretend a later compilation.
The compiled root is retained because build fingerprints also include output
paths and raw source line endings. The main checkout can be built independently
with its normal supported builder; copying fingerprint sidecars across roots
would not establish freshness there.

Runtime commands follow [timedemo comparisons](BENCHMARK-COMPARISON.md) and
[live-server profiling](ENGINE-PROFILING.md), using `-Mode off` for local timing.
The native [QuakeC fixture](QC-INTERPRETER-VALIDATION.md) accepts an explicit
reference checkout and rebuilds both implementations from source without PAKs.
Keep the original control checkout while running matched captures; rebuilding
it after promotion changes its automatic inventory-derived identity.

## What these results establish

The measurements support small, repeatable emulator improvements from removing
invariant table setup and unused interpreter work. They do not establish real
486 cycles, cache misses, memory wait states or physical-machine FPS. DOSBox's
fixed-cycle setting is not a CPU frequency. A genuine 486 can price memory,
branches, cache footprint and x87 work differently.

The [engine-wide analysis](ENGINE-PERFORMANCE-20261108.md) remains the source for
ranked subsystem budgets. It identifies much larger surface/span, model, world
and edge costs; these small improvements do not imply those major costs have
been eliminated. Preserve exact parity and run matched uninstrumented controls
before accepting further renderer, collision, AI or audio changes.
