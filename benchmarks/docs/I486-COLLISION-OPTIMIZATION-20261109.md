# Collision work reductions — 320×200, i486, 2026-11-09

Two changes reduce collision-query overhead: removing an overwritten temporary
clear and reusing the final area-tree child frame. Together they improve pooled
scripted local-gameplay FPS by **0.140803%**, from **22.405025 to 22.436572** in the
pinned DOSBox environment. The improvement is modest. Client timedemos remain
effectively unchanged; they do not run the local server targeted by these changes.

The control is `b7aef96`, Build 854, including the previously accepted AI, warp
and QuakeC changes. Those earlier gains are already in this baseline and are
not counted again. The combined candidate is automatically **Build 856**
(473 accepted + 383 rejected attempts). No version header was edited.

## Why this work was selected

The [engine-wide analysis](ENGINE-PERFORMANCE-20261108.md) measured collision
queries at approximately 5–6% of local frame time, with about 30 queries/frame
in these scripts. This is an actual server workload outside the renderer.
It does not make collision the largest engine cost: surfaces/spans, models and
world/edge processing remain much larger aggregate targets in the recorded study.

`SV_Move` cleared a 124-byte `moveclip_t` and then assigned every byte before its
consumer. The compiler retained a 31-dword `rep stosl`. Removing this clear avoids
those writes on every query. The returned trace copy remains.

`SV_ClipToLinks` called child 1 and then returned. That child now enters the
per-node body using the current frame. Child 0 recursion, entity order, filtering,
trace merging, helper calls and logical-node counters remain. Node/clip pointers,
the x87 control-word snapshot and list successor are refreshed on each entry.
This removes a recursive activation's local stack allocation and save/argument/
return traffic on that path; it does not claim all traversal stack usage vanishes.

No arithmetic expression, rendering quality or simulated work population was
reduced. Neither change adds a cache or runtime allocation.

## Protocol and independent attribution

All timing captures use DOSBox-X 2026.08.31, dynamic core, CPU 486/FPU 387,
**fixed 33445 cycles**, 32 MiB and VGA 320×200. Native PAK/provider/compiler inputs
are pinned. Local captures measure 256 server frames after 64 warm-up frames,
with god mode, forward movement and firing. Simulation advances by 0.0625 seconds
from startup. Each group uses three alternating pairs: control/candidate,
candidate/control, control/candidate.

Timing uses uninstrumented BENCH486 binaries with detailed profiling, per-frame
FPS and diagnostic logging disabled. Existing boundary/state/count bookkeeping
is retained in both variants. Full QuakeC per-function counts and final selected
numeric simulation/framebuffer checksums match within each configuration.
These checks complement native interface tests; final-state hashes are not an
exhaustive per-frame simulation proof.

| Independent candidate | Population | Control pooled FPS | Candidate pooled FPS | Change |
|---|---|---:|---:|---:|
| Overwritten clip clear | Two maps × sound off/on × three pairs | 22.405021 | 22.421317 | +0.072735% |
| Final-child frame reuse | Two maps × sound off/on × three pairs | 22.405024 | 22.420016 | +0.066912% |

Each independent matrix contains 24 native captures, 3,072 measured frames per
variant. Pooled FPS divides total frames by total elapsed time; it does not average
the FPS values across unlike populations. Their deltas are not added to claim a
combined measurement.

For the clear removal, group median gains range from +0.068934% to +0.078696%.
One e1m1 sound sample has a small timing spike: its paired gain is +0.065138%
instead of about +0.078%. That sample remains in the pooled result. Frame reuse
has group median gains from +0.049969% to +0.085198%. All individual paired gains
in both matrices are positive. The initial six-capture screens are retained
separately and are not pooled into the expanded matrices.

## Native correctness and release-code correspondence

The [maintained collision fixture](COLLISION-VALIDATION.md) independently rebuilt
and ran **25,344 comparisons** from the retained reference/candidate sources:

- 18,432 `SV_Move`/`SV_MoveBounds` cases compare all 124 clip bytes at the consumer,
  the entire 52-byte returned trace, helper arguments, movement modes, null/non-null
  passedict, varied/special float patterns, trace outcomes, stack poison and twelve
  x87 settings, including CW/TOP/tag checks.
- 6,912 old/new assembly cases cover balanced and deep left/right traversal
  layouts, filters/owners, helper order/bounds, errors, complete clip and node
  counts, preserved EBP/EBX/ESI/EDI, ESP/DF, CW/TOP/tag and two preloaded FPU values.

Helpers are explicit native stubs in these interface tests. Real BSP helpers,
gameplay and sound are exercised by the separate engine captures. The compiler
profile includes the retained `-ffast-math`; special float patterns establish
differential behavior for that build, rather than strict IEEE arithmetic claims.

Generated `SV_Move` instruction text matches between normal, BENCH and native
fixture builds for both reference and candidate after normalizing local labels
and constant symbols. The assembly clipper's native-tested bodies/constants also
match the game build. Normal and BENCH clipper cores match after omitting the
two BENCH-only counter increments. Linked addresses and alignment padding can
differ; this is not whole-binary byte equivalence.

`out/collision-release-code-equivalence.json` retains that proof. It confirms that
the native-tested optimizations are present in the normal executable as well as
the binary used for matched timing.

## Combined results

The combined matrix has 45 handoffs / 48 native executions: three two-run
correctness replays, 18 fresh demo timings and 24 fresh local gameplay timings.
Retained reference replay bytes are bound to the unchanged Build 854 executable.
Both reference files and metadata are hash-checked before comparison.

| Workload | Control median FPS | Combined median FPS | Change |
|---|---:|---:|---:|
| demo1, silent | 16.955335 | 16.955331 | -0.000023% |
| demo2, silent | 17.299522 | 17.299525 | +0.000021% |
| demo3, silent | 15.878673 | 15.878673 | +0.000000% |
| e1m2, silent | 21.901000 | 21.927416 | +0.120618% |
| e1m1, silent | 23.536098 | 23.574698 | +0.164001% |
| e1m2, sound | 21.231523 | 21.256791 | +0.119013% |
| e1m1, sound | 23.103394 | 23.141076 | +0.163099% |

Local pooled totals: 3,072 frames per variant, 137.112096 -> 136.919309 seconds,
**22.405025 -> 22.436572 FPS (+0.140803%)**. Every local group and paired sample
improves. The three-demo pool is 16.658122 -> 16.658122 FPS: an eight-microsecond
total-time difference across 548 seconds, not a material demo speedup. The tiny
negative demo1 result is retained.

All three demos match the complete color/Z streams and raw PCX captures against
the reference, twice per candidate. All local groups match selected state/image
checksums and entire QuakeC count CSVs. The evidence audit independently verifies
45 result hashes, native report/compatibility pins, 36 parity artifacts, staged
inputs, group populations and recalculated timing aggregates.

Correctness replays use the previously qualified max-cycle 486/x87 profile with
the deterministic presentation clock. Their elapsed times and FPS are excluded
from performance results. Every actual timing above uses the fixed-33445 profile.

The [comparison graph](../out/collision-comparison-20261109/comparison.png) shows
zero-based FPS bars and percentage changes with observed paired ranges. The
[CSV](../out/collision-comparison-20261109/comparison.csv) retains every elapsed-time
sample. Three pairs give an observed spread, not a confidence interval.
The PNG was visually inspected. From `benchmarks/`, regenerate to a fresh path:

```powershell
python tools/plot-matched-comparison.py --session out/collision-integration-validation-20261109/session.json --output out/collision-comparison-copy
```

## Compatibility, normal runtime and artifacts

Both complete i486 gates pass with zero above-target, unknown or exempt
instructions. BENCH checks 316,298 relocated instructions; normal checks 163,878.
Each also verifies 529 embedded startup rows and 9,207 maintained provider
instructions, with 403 source-bound project/runtime objects.

The normal executable completed demo1's 969-frame smoke test, then local e1m2
movement/fire with sound and a clean exit. The inspected 320×200 gameplay PCX is
byte-identical to the retained Build 854 normal control. Its console capture
shows Build 856 and native metadata confirms 11025 Hz stereo, 16-bit mixing.
This verifies device/runtime behavior, not subjective listening. Normal console
timing rounds to 0.1 seconds/FPS and is excluded from marginal gain calculations.

The 19 benchmark host gates, 17 identity tests and native documentation checks
(672 documents / 659 ledger records) pass. Existing unrelated native host-test
debt is documented in the game's `2026-11-08-commit-validation-and-test-debt.md`;
this record does not claim the entire legacy suite passes.

| Artifact | SHA-256 |
|---|---|
| Build 854 control BENCH | `367902E6643BB231A8D906E4C91226BA67199837C364263527414E74BFDCE221` |
| Build 856 combined BENCH | `CC9CFF9DDCF2CC40884B1E2AFC7D12C64FCF3A421AC34837E716B01FB08F589A` |
| Build 856 normal DOS release | `FB39E74CD728B48FF69F7CBC842FB69FE85EF3A6956D7188A99AE7F0A14BA875` |

Only two normalized sources differ across 435 C/H/S/INC files:
`world.c` SHA-256 `78a999bf521b2950a0a2b914223df2bfbd8aaaf5e8190b0848925ded23997357`, and
`sv_cliptolinks_asm.inc` SHA-256
`bf1bc57fd26ef03d646ab0945789b0af4d78502a46f8bad49e3f9f4b195fc015`.

## Retained evidence and reproduction

Workspace-relative generated paths are excluded from Git:

- `benchmarks/out/move-init-validation-20261109/`: 24 captures and passing audit;
  session SHA-256 `7CAEC5F9569589C8F99505DB022D41EC19B46EE018BDCAF906A44C75FF69F4FB`.
- `benchmarks/out/cliplinks-tail-validation-20261109/`: 24 captures and passing audit;
  session SHA-256 `A66760813998DC4F16A9AFA2D8ABB2099C2BF6682B44CD4ABDD04408F6CE16D6`.
- `benchmarks/out/collision-integration-validation-20261109/`: combined inputs,
  manifests, native reports, state/count/replay evidence and passing audit;
  session SHA-256 `FDBBA3E9CA7627DB68E5DF4ADAED37FC4EE3A0582D098BC6543F2312109DEFB6`.
- `benchmarks/out/collision-final-review-validation-v2-20261109/`: current public
  fixture, compiler/header/source pins, staged executable/provider verification
  and both successful native execution records. Earlier preflight diagnostics
  remain separate from acceptance evidence.
- `benchmarks/out/collision-release-smoke-20261109/`: normal runtime records,
  console/audio metadata, PCXs, inspected PNG previews and dimension/hash checks.
- `out/collision-integrated-20261109/out/local-collision-release-v1/`: validated
  normal executable, source-bound build manifest and complete compatibility proof.

Native correctness can be rebuilt using the [public fixture command](COLLISION-VALIDATION.md).
Matched runtime commands use the [local-gameplay protocol](ENGINE-PROFILING.md)
with `-Mode off` and the [timedemo protocol](BENCHMARK-COMPARISON.md) with per-frame FPS off.
Retain the b7aef96 control while collecting comparisons. Source/code/ledger bytes
were frozen through compilation and collection; manifests retain their pre-commit
base revision. Generated manifests are not rewritten to claim a later build.
Compiled outputs remain in their original root because fingerprints also include
paths and raw line endings; copying sidecars into another checkout would not
establish build freshness there.

## Commit review and final rebuild

The production changes are committed separately as `b5bd9fd` (overwritten clear)
and `4924f47` (final-child frame reuse). The main game checkout fast-forwards to
the latter; isolated prototypes remain on archive branches. The benchmark suite
commits its maintained native fixtures separately from this performance record.

Review corrected unintended UTF-8 punctuation corruption in the ledger index,
restoring all historical rows and retaining only the two new inventory rows.
That documentation correction changes the inventory hash, while the automatic
identity remains Build 856. Fresh builds are retained in
`out/collision-integrated-20261109/out/local-collision-bench-reviewed-v2/` and
`out/collision-integrated-20261109/out/local-collision-release-reviewed-v2/`.
The original benchmarked artifacts and manifests remain unchanged.

| Final reviewed artifact | SHA-256 |
|---|---|
| BENCH | `3B73073E536CDE0611AE3F2F6E0B3642EF4F1C18868BD328F22617A80F3C6A31` |
| Normal release | `5C7991F519003DEC8A4EA6EDDA3B3C1F3CF8DA0435775C4DC4DF414546AB62E7` |

`out/collision-delivery-audit.json` verifies entire executable byte equality
between the benchmarked and reviewed builds except for exactly two same-length
compile-time clock literals at identical offsets. Instructions, addresses,
alignment and every other byte match. This transfers the retained runtime and
performance evidence; it does not add new benchmark samples. The audit also
binds the final committed fixture templates and driver to the 25,344-case native
execution record. A fresh benchmark host run passes all 19 gates; documentation
checks pass 672 documents and 659 ledger files. The 17 build-identity contract
tests also pass after committing the corrected index.
Both reviewed builds pass their complete i486 audits, including startup and
provider coverage, and remain source-bound and fresh after the native commits.
The verification is retained as
`benchmarks/out/collision-integration-validation-20261109/post-commit-artifacts.json`.

## Limits

These are repeatable emulator measurements, not physical 486 cycle/cache-miss
or FPS measurements. DOSBox's cycles setting is not a physical CPU frequency.
Reduced memory writes and call/stack traffic follow from the code; their cost
on a real 486 depends on cache, memory, bus and instruction timing. This scripted
population does not establish gains for every map or human play style.

The measured renderer remains the dominant budget. These collision improvements
are useful incremental work reductions, not evidence that the larger rendering
and simulation costs have been eliminated.
