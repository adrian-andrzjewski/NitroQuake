# NitroQuake whole-engine performance analysis — 320×200, i486

This study's source refresh is the pre-change `fd2b7a5` control. Subsequent
warp-table/QuakeC changes and the combined Build 854 release are measured in the
[i486 optimization record](I486-OPTIMIZATION-20261108.md). The budgets below remain
reference measurements for their recorded sources and protocols.
The [Build 856 collision record](I486-COLLISION-OPTIMIZATION-20261109.md) measures
subsequent server-side work reductions against Build 854.

## Main finding and evidence boundaries

Surface drawing, texture/Z spans and software-cache work are the largest measured
CPU budget. Models, world/face processing and edge scanning follow. Native server
simulation is important in populated local worlds, but client timedemos do not run
it. Active sound is measurable and substantially smaller than the main rendering
groups. PVS marking, cleanup and allocation totals are poor targets for speculative
optimization in the measured steady-state scenes.

Two evidence sets must remain separate:

1. **Audited calibrated reference study:** three demos, stationary e1m1/e2m2,
   a qualified incoming-fire encounter, active PCM and algorithm/work censuses.
   The original report and 104 recorded file hashes still match. Expected changes
   to primary/build/documentation files and one migrated document prevent treating
   the old audit as a claim that today's entire tree is byte-identical.
2. **Current source refresh:** fresh BENCH486/PROFILE486 builds, VGA 320×200,
   fixed 0.0625 simulation step, all three demos and scripted local e1m1/e1m2
   movement/fire with sound off/on. Controls and component captures repeat.
   Its general probes are more intrusive; measured overhead is retained explicitly.

The reference used its recorded VESA/fixed-step protocols, including 0.05 for local
simulation. It predates subsequent identity/tooling and drawing-boundary changes.
The reference server table below is the **uncached** control; today's engine already
contains the accepted immutable checkclient leaf cache. Do not combine FPS, hashes
or shares across these different protocols as though they were one experiment.

The environment is DOSBox-X 2026.08.31, dynamic core, CPU 486/FPU 387, fixed 33445
cycles and 32 MiB. DOSBox's cycles setting is not physical MHz. These are measured
emulator elapsed-time budgets, not physical i486 cycle or cache-miss counts.

## Current source refresh

The serial matrix contains 42 captures: two ordinary controls and two component
profiles, plus one coarse and one detailed capture for each of seven workload/device
configurations. Local games measure 256 frames after 64 warm-up frames. They use
god mode, continuous forward movement and firing. This bounded script exercises
real simulation; it is not a claim of representative human play or missile-heavy
combat. Both sound-enabled cases initialize 11,025 Hz stereo 16-bit output.

Control FPS uses frames divided by median elapsed time. Attribution below uses
timer-read-corrected exclusive coarse scopes, normalized within each capture.

| Workload | Control FPS | Renderer | Local server | Audio scope | Coarse elapsed overhead | Component elapsed overhead |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| demo1, silent | 16.9518 | 96.53% | 0% | 0.05% | 6.83% | 12.13% |
| demo2, silent | 17.2834 | 97.02% | 0% | 0.05% | 6.86% | 12.34% |
| demo3, silent | 15.8756 | 93.88% | 0% | 0.04% | 6.91% | 12.45% |
| e1m1, silent | 23.5034 | 80.31% | 16.41% | 0.06% | 5.33% | 11.77% |
| e1m1, sound | 23.0715 | 78.84% | 16.17% | 1.82% | 5.34% | 11.75% |
| e1m2, silent | 21.8684 | 79.78% | 15.92% | 0.06% | 5.90% | 11.79% |
| e1m2, sound | 21.2003 | 77.38% | 15.49% | 3.00% | 5.87% | 11.68% |

Remainders cover screen/HUD, video transfer, client/network, input and frame
orchestration. The tiny silent audio scope includes light decay and disabled-device
checks. Component captures split the renderer and server further:

| Exclusive scope | demo1 | demo2 | demo3 | e1m1 silent | e1m2 silent |
| --- | ---: | ---: | ---: | ---: | ---: |
| Texture spans | 28.13% | 28.36% | 26.71% | 36.10% | 33.00% |
| World BSP / face work | 13.39% | 13.90% | 11.10% | 9.47% | 10.11% |
| Alias rasterization | 12.67% | 10.41% | 12.17% | 8.59% | 13.82% |
| Z spans | 11.03% | 11.00% | 9.70% | 6.57% | 5.58% |
| Edge scan | 10.03% | 10.93% | 10.27% | 7.75% | 6.61% |
| Surface-cache work | 9.10% | 7.65% | 11.16% | 7.13% | 4.83% |
| Collision queries | 0% | 0% | 0% | 6.16% | 5.19% |
| QuakeC and remaining built-ins | 0% | 0% | 0% | 4.41% | 5.88% |
| Physics orchestration | 0% | 0% | 0% | 4.69% | 3.69% |

These are medians of two component captures, not percentages of an uninstrumented
hardware cycle counter. Collision and QuakeC costs are removed from enclosing
physics scopes rather than counted twice. Alias rasterization excludes separate
model setup/transform/culling work. Surface-cache work includes rebuilding cached
surfaces; it is not merely a lookup instruction count.

Current local scenes issue 7,929 and 7,566 collision queries per 256 frames,
respectively: about 31 and 30 per frame. QuakeC executes `FindTarget` heavily
(46,428 and 46,296 statements); e1m2 also executes `ai_run`, visibility and range
logic. These statement populations identify relevant paths but do not price
individual QuakeC functions. Current sound-mix scopes cost about 0.75 ms/frame
on e1m1 and 1.31 ms/frame on e1m2, with four mix-scope calls per frame.

The repeated controls vary by less than 0.0002% in this emulator's recorded elapsed
time. That repeatability does not establish corresponding physical-hardware
accuracy. All modes' final framebuffer checksums and selected simulation-state
checksums must match within each workload/device group; cross-device final
checksums also match for these local scripts. They are final-state checks, not
exhaustive per-frame simulation equivalence.

General profiling adds 5.3–6.9% elapsed time even in coarse mode and 11.7–12.5%
in component mode. Timer subtraction does not remove instrumentation branches,
bookkeeping, code layout or real DMA feedback. Use the less intrusive reference
groups below as an independent broad-budget check. No profiling FPS difference is
claimed as a production-engine regression or optimization gain.
Detailed profiling adds 48.60–49.55% in the demos and 34.82–41.80% in local games;
its timings are unsuitable for promoting small optimization gains.

The final audit verifies all 42 result hashes and 70 native report/profile hashes,
the expected mode/frame counts and zero profiler stack errors. All final checksums
match within their workload/device group. Session SHA-256 is
`B7837DA80B8A6FC74EAC7A261F4645B449C32C9E0B784BF2C0A24137CB9C5FBC`.
After collection, the runner gained an oversized-command preflight and an explicit
source-only digest field; the measured runner/collector snapshots remain retained
unchanged. Successful workload commands and native measured source are unchanged.

The [current HTML report](../out/engine-analysis-verified-20261108/report.html)
links both charts, the ranked CSV, raw measurements, source-bound build manifests
and session pins. The measured source-tree digest is
`4F06430E32CF5E1EB6E0410D0578A40B4E373C63BEE44D24EC0A2AA0A144CA44`.
The native instrumentation is committed as `fd2b7a5`; build manifests retain their
pre-commit base revision. The digest above binds the measured working-copy bytes,
including line endings. Post-commit freshness checks pass for both executables.
The suite workflow is committed as `61adc65`.
`out/engine-analysis-source-refresh.json` independently confirms both executables
are fresh against this same tree. The historical JSON field `sourceFingerprint`
contains the configuration-bound build digest, so control and profile values
correctly differ; it must not be interpreted as a source-only digest.

## Ranked renderer budget: calibrated reference

Exclusive broad groups below avoid counting parent and child time twice.
Three ordinary controls and three low-overhead renderer profiles were retained
per demo. Observed profiling overhead was 1.23%, 1.04% and 1.03%, respectively.

| Exclusive group | demo1 | demo2 | demo3 |
| --- | ---: | ---: | ---: |
| Surface drawing, texture/Z and software cache | 53.78% | 53.16% | 51.10% |
| Alias models, culling and rasterization | 14.64% | 11.53% | 13.21% |
| World BSP and face submission | 12.67% | 13.25% | 10.60% |
| Edge scanning and dispatch | 9.74% | 10.61% | 10.03% |
| Presentation | 0.67% | 0.67% | 0.61% |
| Setup and PVS marking | 0.24% | 0.24% | 0.16% |
| Underwater screen warp | 0% | 3.32% | 0% |

Remaining costs include brush entities, particles, view lighting, screen/HUD and
client work. In demo1, particles were 1.08%, screen/HUD self 1.42%, and client/input
1.27%. These figures describe these scenes, not maximum explosion or network load.

PVS marking is distinct from the much larger BSP/face budget. Optimizing visibility
bit marking on the assumption that it owns the whole BSP cost would target the
wrong stage. The world/face group includes traversal, rejection, clipping and
submission; the broad measurement does not assign all of it to tree traversal.

The earlier fine-grained reference experiment added 14.31% elapsed time and
recorded backward clock clamps. Its individual-function percentages are retained
as diagnostics, not promoted over the calibrated broad budget.

## Outside rendering: simulation, AI and messages

The reference stationary local worlds execute real physics, QuakeC, native AI,
collision and loopback client/server traffic. They are not recorded demo playback.
Three off/server-profile pairs were retained per map; profiler overhead was 2.14%
on e1m1 and 2.89% on e2m2. Shares below are raw exclusive frame percentages, except
the explicitly inclusive total row.

| Scope | e1m1 reference | e2m2 reference |
| --- | ---: | ---: |
| Whole server, **inclusive** | 9.51% | 17.22% |
| Collision traces, exclusive | 1.86% | 4.54% |
| Physics orchestration, exclusive | 2.28% | 3.65% |
| QuakeC/interpreter and remaining built-ins, exclusive | 1.92% | 2.47% |
| Native AI movement, exclusive | 0.69% | 2.00% |
| Ground-support checks, exclusive | 0.59% | 1.70% |
| Checkclient/PVS query, exclusive, before accepted cache | 0.74% | 1.32% |
| Entity-send work, exclusive | 0.41% | 0.48% |
| Entity cleanup, exclusive | 0.13% | 0.13% |

Do not add the inclusive server row to its children. QuakeC statement counts
identify executed logic; they do not measure per-function CPU time because native
built-ins have very different costs.

The denser map made 6,020 collision traces in 240 frames. Camera ideal-pitch
calculation alone issued 1,440 traces, six per frame, even with a stationary player.
Its inclusive scope was about 1.02%; its own non-collision self cost was 0.12%.
This is a concrete repeated-work population worth checking. A cache cannot simply
assume unchanged player position: dynamic entities can change trace results.

Ground support reached 3.81% inclusive in e2m2. Its existing four-corner shortcut
already handled 1,240 of 1,680 calls; 440 took the slower trace path. An attempted
axial-prefix premise saved no BSP node visits on that map and under 4% on e1m1,
before added instructions. It was screened out rather than treated as a win.

A separately qualified hard-skill e1m1 encounter included a visible attacking
soldier, incoming damage and final health 68. Its uncached server share was 10.16%.
That is another workload point, not an isolated experiment on combat versus idle.

The accepted 1,536-byte immutable leaf-query cache is already present in
[pr_cmds.c](../../quake/src/pr_cmds.c). Across 18 retained off-mode samples, its
frame-weighted diagnostic gain was 0.387% (0.288–0.493% by workload). It preserves
target/PVS decisions rather than caching mutable AI state. This is an existing
improvement, not a new gain from this analysis or a physical-hardware speed claim.

## Active audio

The audited sound-enabled workload measured audio at 3.588% of frame time;
painting and buffer transfer accounted for 2.868%. The actual format was 11,025 Hz
stereo 16-bit output with 8-bit inputs. Three matched off/coarse samples showed
0.648% elapsed profiling difference. PCM activity was counted, not inferred from
an update function being called.

Sound updates also occur inside rendering through `S_ExtraUpdate`, so timing only
the final host audio phase misses work. The current component probes retain these
calls under unselected rendering scopes. The legacy host sound-spatial scope also
contains `CL_DecayLights`; it is not a pure audio-only scope.

Silent/audio FPS differences are not pure mixer benchmarks: audio startup shares
RNG state, and real DMA progress changes the number of samples mixed as CPU time
changes. Device comparisons must retain checksums and activity/format evidence.
No physical audible-output or PCM-output-parity claim follows from these timings.

## Work, redundancy and memory

The reference census identifies useful populations without pretending to measure
hardware cache misses:

- About 3,626 texture segments per frame, averaging 12.51 pixels per segment.
  Perspective/setup work matters alongside pixel stores. Optimizing stores alone
  does not remove segment setup, reciprocal/division or dependency-chain work.
- Software surface-cache rebuilds were 15.87% of recorded lookups, with zero
  thrash frames. Rebuilding cached lighting/animation data is different from
  capacity eviction; increasing cache size does not address every rebuild.
- All 16,801 recorded resource-cache checks hit, with no recorded misses/evictions.
  Allocator counters include loading; their totals are not a steady-frame budget.
- Same-row texture-span links were only 2.15% of links. A broad batching proposal
  needs its actual eligible population rather than an assumption of widespread reuse.
- Fewer than half the tracked face submissions reached the tracked emission path.
  Separate cached-edge reuse, rejection and clipping before calling all non-emission
  work redundant.
- Profile-only counters now cover the selected assembly cache-check path. Two
  256-frame local captures recorded 330 checks, 314 contributing and 16 false
  predicates (0.645 checks/frame combined). The check rate is low, and these
  counts do not price its CPU time.

The [assembly dlight census ledger](../../quake/docs/ledger/2026-11-09-surface-cache-dlight-probe-census.md)
records the two-map results, build audits, exact run checksums and hashes for the
ignored generated captures. The census corrects instrumentation coverage; it
does not establish a dlight optimization or FPS gain.

The default software surface cache is already 2,400 KiB. A retained same-binary
capacity experiment measured about 1.45% above 600 KiB; this benefit is already in
the default and must not be counted again as a proposed optimization.

Logical 320×200 color is 64,000 bytes and Z is 128,000 bytes. The normal VESA path
draws into RAM and copies dirty rectangles to mapped video memory; a linear VESA
mapping does not imply direct rendering into video memory. Current VGA captures
and the reference VESA route are separate presentation paths.

An Intel DX2's unified 8 KiB L1, or a DX4's 16 KiB L1, cannot hold all buffers,
geometry and hot code simultaneously. That is a working-set fact, not a measured
miss rate. The audio scale table's 32 KiB allocation also does not mean all entries
are active at once. Cache conflicts, L2/DRAM waits, write buffering, x87 latency
and video-bus throughput require hardware or a suitably calibrated model.

## Optimization priorities and realistic FPS impact

For frame fraction `f` and cost reduction `r`, conditional FPS gain is
`1 / (1 - f*r) - 1`. These are planning scenarios, not achieved gains.

| Target and measurement | Example cost reduction | Conditional total FPS gain |
| --- | ---: | ---: |
| Surface/texture/Z/cache, 53.78% in demo1 | 10% | 5.68% |
| Models/culling, 14.64% in demo1 | 10% | 1.49% |
| World/face work, 12.67% in demo1 | 10% | 1.28% |
| Edge scanning/dispatch, 9.74% in demo1 | 10% | 0.98% |
| Whole server, 17.22% in denser uncached reference | 25% | 4.50% |
| Whole server, 16.41% in current e1m1 movement/fire | 25% | 4.28% |
| Collision, 6.16% in current e1m1 component capture | 25% | 1.56% |
| QuakeC/built-ins, 5.88% in current e1m2 component capture | 25% | 1.49% |
| Ground support, 3.81% inclusive in that reference | 50% | 1.94% |
| Active audio, 3.588% in sound workload | 25% | 0.91% |
| Cleanup, 0.13% in local worlds | 50% | 0.065% |

The strongest opportunities are reducing actual surface/geometry/model work and
then targeting measured native AI/collision populations. Most small isolated
outside-renderer changes have a sub-1% whole-frame budget. Larger gains require
substantial work reduction in a large group, not merely rewriting another small
function in assembly.

The next focused measurements should be:

1. Split texture segment setup from the pixel body and separate actual rebuild
   causes on the active assembly cache path. Preserve exact color/Z and x87 order.
2. Price face rejection/clipping and model culling/transform/raster populations
   against the broad measured budgets before proposing more caches or unrolling.
3. Count repeated ground/ideal-pitch trace inputs and distinguish immutable-world
   queries from dynamic-entity traces. Existing fast paths and rejected premises
   already constrain the potential gain.
4. Split `D_WarpBuildTables_asm486` from pixel copying. Demo2 spends 3.32% in the
   entire warp, across 210 calls. The assembly already hoists scale divisions;
   geometry tables are still rebuilt. Any reuse must account for viewport, stride,
   buffer base and floating-point conversion state. Setup's share remains unsplit,
   so a table-cache FPS prediction would be speculative.
5. Investigate active mixer/table working sets and DMA polling with PCM validation.
   Removing extra updates blindly risks audio continuity and is not justified by
   a call count alone.

## Reproduction and retained evidence

Validation completed for this refresh:

- BENCH486 and PROFILE486 i486 builds passed complete executable, startup and
  external DPMI-provider ISA audits with zero above-target instructions/exemptions.
- All 19 suite host gates passed. Native GCC execution of the actual coarse
  entry/leave and mid-timedemo activation functions passed, including both
  enclosing inactive scopes. Native documentation structure checks passed.
- The final runner's oversized-command rejection was exercised before build/DOS
  launch. A separate 16-frame diagnostic smoke completed at 320×200 with matching
  retained smoke checksums and the expected source-only digest. Console logging
  marks that smoke ineligible as performance evidence; it is outside the 42 runs.

This does not claim the entire historical game host suite is green. Existing
unrelated test debt remains recorded in
[the prior validation ledger](../../quake/docs/ledger/2026-11-08-commit-validation-and-test-debt.md).

Coverage is explicit rather than inferred from a successful demo:

| Subsystem | Evidence and boundary |
| --- | --- |
| Assembly rasterization, geometry, Z and screen presentation | Source-bound i486 builds; broad reference groups and current component scopes |
| BSP and visibility | World/face budget measured separately from PVS marking; no physical branch/cache-miss counts |
| Lighting and surface cache | Work/rebuild census and grouped time; active-assembly dlight probes are counted but not separately timed |
| Physics, native AI and QuakeC | Live local-server workloads and retained encounter; not inferred from client demos |
| Audio | Real emulated Sound Blaster format plus retained active-PCM evidence; no physical/audio-output-parity claim |
| Memory | Software-cache populations, source routes and helper counts; hardware stalls/misses unmeasured |
| Networking | Local loopback/message work; remote transports and multiplayer load unmeasured |
| Input, HUD and menus | Scripted input and HUD measured; mouse/joystick, calibration and menu interaction excluded |
| Loading and disk I/O | Map startup excluded; runtime asset work remains if triggered; no profiling-report writes inside measured frames; loading-inclusive allocator counters labeled separately |

- [Reusable collection and interpretation workflow](ENGINE-PROFILING.md).
- Current refresh: `benchmarks/out/engine-analysis-verified-20261108/`, including
  native/source pins, all raw results and ordinary/profiled samples.
- [Audited reference report](../../quake/out/engine-performance-analysis-20261108/report.html),
  [reference ledger](../../quake/docs/ledger/2026-11-08-engine-wide-profile-and-ai-cache.md)
  and original evidence files remain preserved.
- `out/prior-engine-evidence-refresh.json` records this audit's 104 matching hashes
  and the expected changed/migrated paths; interrupted prototype captures remain
  explicitly excluded.

Scope covers these recorded scenes, bounded local movement/fire, stationary worlds
and the retained hitscan encounter. It does not establish human-input, missile-heavy,
multiplayer transport, CD-audio, joystick, loading, menu, low-memory or physical-486
performance. Inactive paths are not evidence that their implementation is fast.

Hardware references: [official DOSBox-X CPU guide](https://dosbox-x.com/wiki/Guide:CPU-settings-in-DOSBox%E2%80%90X)
and [Intel Embedded Intel486 Hardware Reference Manual, section 9.3.1](https://mark-ogden.uk/files/intel/publications/273025-001%20Embedded%20Intel486%20Processor%20Hardware%20Reference%20Manual-Jul97.pdf).
The latter's retained local PDF hash is recorded in the reference hardware evidence.
