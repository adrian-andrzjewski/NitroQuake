# NitroQuake Architectural Assessment

- **Original assessment:** 2026-11-16
- **Current-state refresh:** 2026-11-17
- **Original baseline:** outer HEAD `71f17310c58464ed5910b43db73393b63d18e9e1`; game HEAD `38873bce04762ced607ac36c5d59891173dbe275`.
- **Refresh baseline:** outer HEAD `7ea6d146e1b410487d87c2c9549dbbd58fb5e8a8`; game HEAD `ab81c94b83765e78723c48c62cb335c96fc41d96`. The outer gitlink points to that game HEAD. Both worktrees were clean before this report refresh.
- **Method:** Read-only inspection of source, build scripts, architecture documentation, test contracts, and recorded profiling/parity evidence. No code was changed. No build, test suite, DOSBox scenario, or hardware run was executed during the refresh.

This report supersedes the November 14 snapshots in [architectural-assessment-2026-11-14.md](architectural-assessment-2026-11-14.md) and [architectural-assessment-2026-11-14-current.md](architectural-assessment-2026-11-14-current.md). The November 16 findings below are the original review baseline; the November 17 refresh supersedes findings explicitly marked as completed or revised.

Line-number anchors in the original architecture walkthrough describe the
November 16 review baseline. The refresh uses stable paths, symbols, and
subsystem documentation where later commits may have shifted line numbers.

## Follow-up after renderer assembly split (2026-11-16)

This assessment records the source state at game commit `38873bce`. The
subsequent game commit `2a965f3` split `src/renderer/asm486_experiments.s` into
renderer units for alias, BSP, edges, lighting, memory, particles, raster and
sky/warp work, sprite rendering, surface cache, surface drawing, and world
rendering, with collision helpers moved to `src/collision/asm486_collision.s`.
The pre-existing sprite geometry routines remain in `asm486_sprite.s`. The
source-layout map records the original monolith as a one-to-many migration.

The split preserves all 88 exported symbols from the former monolith with no
duplicate exports. Clean i486 release and C-reference builds passed their
linked ISA gates: 98 and 92 assembly sources, respectively, with zero above-
i486 instructions and zero exemptions. The renderer stack budget passed in
both configurations; the benchmark host suite passed 20/20 gates. A focused
`demo1-drawspans8` DOSBox-X parity run matched exact frame checksums and
framebuffer/palette output over two repeats per profile. No physical 486 timing
or qualification was performed.

This follow-up supersedes the assembly-file finding in P2 and item 4 under
"Substantial engineering opportunities." The 2026-11-17 refresh below revises
the assembly, benchmark-harness, memory-accounting, and stack-model findings.

## Current-state refresh (2026-11-17)

Three changes after the original review materially changed its priorities:

| Area | Current evidence | Assessment status |
| --- | --- | --- |
| Assembly source ownership | The 11,914-line `asm486_experiments.s` was split into subsystem files plus `collision/asm486_collision.s`; the release inventory has 98 assembly sources and the C-reference inventory has 92. The documented split preserved the former 88 exported symbols without duplicate exports. | The monolithic-file finding is closed. No further broad split is recommended without a specific ownership or review problem. |
| BENCH486 ownership | The roughly 13.2K-line harness was moved from `core/host_cmd.c` into `src/tests/bench486/bench486_harness.c`; regular host commands remain in `host_cmd.c`. | The production/test ownership finding is closed. The test harness remains a large file and is a lower-priority, demand-driven decomposition candidate. |
| Memory and stack visibility | `quake/docs/memory-budget.md`, the `meminfo` command, and `quake/tools/test-memory-budget.py` account for engine, video, renderer, warp, and DPMI stack resources. `renderer-stack-budget.py` checks generated frames and cross-checks formulas parsed from preprocessed runtime C. | The missing-budget finding is closed. The unexplained low-memory map boundary and physical-DPMI qualification remain open. |
| Release artifact guard | Commit `ab81c94` normalizes generated build identity for the release hash guard and adds `tools/test-i486-release-guard.py` to the game host-gate inventory. | The identity-guard correction is present in the current source. This refresh did not rerun its test or rebuild the release artifact. |

Subsequent verification on 2026-11-17 built the i486 release, C-reference,
and PROFILE486 configurations from game revision `ab81c94`. All three generated
stack-frame/runtime-formula checks and linked i486 ISA gates passed. The
measured emulator stack headroom remains specific to its DOSBox-X/CWSDPMI
environment; physical DPMI qualification is still pending. This later build
verification does not change the read-only method used for the assessment
refresh above.

The assembly split's documented gates include clean i486 release and C-reference
linked ISA audits with zero above-i486 instructions and zero exemptions, a
20/20 benchmark host suite, and focused `demo1-drawspans8` parity with exact
frame checksums over two repeats per profile. These are recorded results, not
tests rerun for this refresh. At that snapshot, the handoff reported 29
selector/profile expectation mismatches in `tools/test-build-dos.py`, even
though source counts and release/C-reference source inventories matched. The
2026-11-17 follow-up below records their classification and the passing matrix
test. The focused parity case is not the full six-scene gate, and none of these
results qualifies physical 486 performance.

## Executive assessment

NitroQuake is a mature, DOS-first software renderer and game engine with unusually strong evidence discipline for a legacy 486 target. The nested checkout owns C, GNU assembly, game assets, the DJGPP build, native correctness fixtures, and ISA verification; the outer checkout owns DOSBox automation, scenario data, output analysis, and reports. The read-only workspace doctor verifies that the nested checkout matches the committed and staged gitlinks.

Subsystem directories and headers now expose the source map without direct production includes of the legacy `quakedef.h` umbrella. The renderer assembly monolith has been split by subsystem, the BENCH486 harness has moved into test-owned sources, and the memory budget is documented and reported at runtime. Build identity is source/configuration based; strict i486 audits, exact C/assembly fixtures, and image oracles protect important contracts.

The remaining risks are more focused:

1. **Physical 486 qualification is pending.** DOSBox-X supports repeatable screening, but it cannot establish real CPU timing, DPMI stack behavior, or device compatibility.
2. **Renderer stack use is large and formula-based.** Generated frame checks and runtime DJGPP stack preflight exist, and the build tool cross-checks runtime formulas. The call-path assumptions still need maintenance and physical-system evidence.
3. **Low-memory map behavior is not explained.** Current captures bracket one e1m1 load transition and show registered-data minimum runs stopping before `POSTMAP`; logs do not identify the failed allocation or pool.
4. **Selector/profile contracts needed reconciliation.** The release/reference inventories agree. The 29 reported profile-test mismatches have since been addressed in the goldens and selector probes; the six-scene parity gate remains pending.
5. **Ownership is improved but mutable state remains global.** The benchmark harness and assembly files have clearer owners; renderer, host, client, server, and memory state still crosses subsystem boundaries through globals and broad legacy structures.

Preserve the DOS memory model, C/assembly calling conventions, narrow shipping build interface, exact output contracts, and evidence gates. Avoid broad modernization that adds indirection to pixel and span loops without measurements.

## Architecture and runtime flow

### Repository and build boundary

The outer repository contains benchmark orchestration, captured-frame oracles, scenarios, analysis tools, and documentation. The independent quake/ checkout owns the game and can build without the benchmark suite or DOSBox-X. It is recorded as a Git gitlink rather than a configured submodule; benchmarks/tools/check-workspace.ps1 reports outer, index, and nested revisions, dirty state, shallow status, and tool availability without changing either checkout.

The public game builder is quake/tools/build-dos.ps1. It exposes named i486-release and c-reference configurations and a resolved -DumpFlags contract. Per-routine alternatives and experimental probes remain behind build-dos-experimental.ps1 for the benchmark suite. The build verifies source-bound and linked i486 instruction constraints and emits source/configuration identity and manifests.

### Frame and subsystem data flow

At startup, platform/dos/sys_dos.c initializes the DOS/DPMI environment, gets the engine memory block, and enters Host_Init in core/host.c. Host_Init calls Memory_Init, initializes command and filesystem services, loads the game data, then initializes server and network services. Interactive mode additionally initializes input, video, drawing, renderer, sound, CD audio, status bar, and client. The shared executable also supports dedicated-server mode, so startup conditionally omits interactive facilities while retaining some shared renderer/model initialization.

The main frame path is:

1. Host_Frame and _Host_Frame in core/host.c process timing, key and input events, command-buffer work, network polling, local-client commands, server simulation, remote-client sends/reads, then screen presentation.
2. Host_ServerFrame dispatches server updates. server/sv_phys.c owns entity physics and invokes the QuakeC interpreter in server/pr_exec.c. Collision and movement helpers live under collision/ and are used by server movement and world traces.
3. client/cl_main.c serializes client commands, consumes server messages, and updates client state. client/cl_parse.c owns protocol parsing.
4. client/screen.c composes the screen and calls V_RenderView in client/view.c. The view code prepares camera state, dynamic lights, and optional interleaved views.
5. renderer/r_main.c sets up the view, marks visible leaves, and dispatches the render. renderer/r_bsp.c walks the world BSP and emits visible face/edge work. R_EdgeDrawing builds and scans edge lists, draws brush entities, then hands ordered surfaces to renderer/d_edge.c. The surface stage uses cache and texture gradients, then renderer/d_scan.c emits textured and Z spans. Alias models follow a separate transform/clip/triangle-span path through renderer/r_alias.c and d_polyse.c. Sprites, particles, view effects, and overlays are separate stages.
6. video/vid_dos.c selects VGA/VESA presentation and updates the framebuffer. audio/snd_dma.c mixes/spatializes sound while audio/snd_dos.c provides the DOS DMA device boundary. Network transports are grouped under network/ and called through net.h.

Representative source points: core/host.c:716 and :1060; client/cl_main.c:720 and :791; client/screen.c:1154 and :1310; client/view.c:1111; renderer/r_main.c:624, :1030, :1174, :1310, and :1650; renderer/r_bsp.c:1027 and :1139; renderer/d_edge.c:1022; renderer/d_scan.c:384 and :529; renderer/r_alias.c:1344; renderer/d_polyse.c:814; video/vid_dos.c:145 and :517; audio/snd_dma.c:692; network/net_main.c:809 and :932.

The subsystem directories and public headers now make the source map understandable. The data flow itself remains intentionally stateful: host, client, server, model, video, and renderer state is shared through globals and legacy structures. The headers define callable seams, but they do not yet provide isolated runtime contexts or ownership of mutable frame state.

## Resource and performance model

### Memory ownership

The DOS system layer obtains a large memory block through dos_getmaxlockedmem, with a -mem option that uses malloc. Host_Init requires at least 0x550000 bytes for the standard game and one additional MiB for the larger registered-data path (core/host.c:57–58). Memory_Init in memory/zone.c creates a default 48 KiB zone, since DYNAMIC_SIZE is 0xc000. Small strings and structures use the zone allocator; larger and lifetime-oriented allocations use the hunk and cache.

The hunk grows from low and high ends of the same block. Low allocations hold persistent startup and level data; high marks support temporary allocations. Cache blocks occupy the space between those ends, carry owner handles and LRU links, and can be moved or evicted when hunk growth needs room. The allocator is DOS-appropriate and avoids general-purpose heap fragmentation, but it is a complex shared mechanism: zone, hunk, cache, surface cache, and selected assembly implementations all interact through global state in memory/zone.c.

The current memory budget is documented in `quake/docs/memory-budget.md`, and the `meminfo` command reports engine, video, renderer, warp, and DPMI stack resources. At 320x200, the source-derived surface cache is 2,457,600 bytes, the default zone is 49,152 bytes, video hunk payload is 2,649,936 bytes, frame-local edge/surface arrays total 128,096 bytes, and the waterwarp image is a 64,000-byte renderer-lifetime `malloc`. These values belong to different pools and must not be summed as if they were independent allocations: video and extra edge/surface storage are already inside the engine hunk.

The release edge frame is 128,176 generated bytes. Current release stack requirements are `172,868 + 128 * world_depth` bytes for normal rendering and `236,884 + 128 * world_depth` for the stack warp fallback. At depth 72, the requirements are 182,084 and 246,100 bytes. The recorded DOSBox-X/CWSDPMI capture at depth 87 reported 523,940 bytes available, with 184,004 normal and 248,020 fallback requirements; fallback headroom was 275,920 bytes in that emulator setup. These are not physical-machine measurements.

`renderer-stack-budget.py` parses generated assembly prologues, validates selected view, edge, world, polygon, recursive clip, dispatch, and fallback frames, and cross-checks the preprocessed runtime formula in `r_main.i`. `R_RenderViewDispatch` reads ESP and DJGPP stack bounds before rendering. It skips rendering if the normal requirement does not fit, and disables waterwarp if only the additional fallback capacity does not fit. The BSP depth is measured with an iterative parent-link walk and cached for the current world.

Treat this guard as a hard safety boundary, not a reason to increase stack use. Several whole-path relationships remain modeled terms (including polygon-path and recursive-step costs); any call-structure, instrumentation, compiler, or selector-profile change must preserve the generated/runtime cross-check. Moving the 128 KB arrays to permanent storage would trade stack for scarce hunk memory and may affect 486 addressing and cache behavior. Consider that only if physical-system evidence shows stack rejection or inadequate headroom.

### Renderer costs and optimization evidence

The renderer combines classic BSP visibility and front-to-back world traversal, edge-list scan conversion, surface-cache texture reconstruction, Z spans, and separate alias-model triangle rasterization. These algorithms are suited to software rendering and indexed VGA/VESA output, but their cost varies strongly by scene, view size, model density, sound, and presentation mode. The same 486-oriented profile deliberately mixes C and handwritten assembly based on measured implementations; the current release profile selects C for BSP traversal and exact-zero-T span paths for texture spans while retaining many assembly paths.

The latest detailed profile currently documented, `benchmarks/docs/ENGINE-PROFILING-20261115.md`, attributes 50.00% of corrected parts-mode time on e1m1 and 44.44% on e1m2 to the combined surface, texture, Z, and cache group. Local server work is 17.55% and 16.98%; models and sprites 10.05% and 16.64%; world BSP and faces 9.48% and 9.96%; edges and dispatch 8.05% and 6.81%. These are DOSBox attribution shares from the measured builds, not physical 486 cycle shares. No fresh full-workload profile after the November 16 source-ownership changes is documented here.

Instrumentation itself is expensive: detailed mode added roughly 43–50% elapsed overhead on the captured workloads, and parts mode about 12–13%. The report therefore uses profile modes for attribution and separate uninstrumented runs for timing. It also records a useful caution against narrow special cases: same-row texture-span links were only 0.41–1.09% of spans, and prior no-row-cross and alternative span-indexing experiments measured slower. The current zero-T candidate improved the two local maps in the documented emulator runs but regressed demo1 and demo3, with demo2 inconclusive. No general renderer-speedup claim or physical-486 acceptance follows from that evidence.

The project already has strong optimization controls: exact color/Z stream and image checks, per-routine C/assembly fixtures, strict ISA audits, repeated matched uninstrumented A/B protocols, and an optimization ledger that preserves rejected candidates. Preserve these gates. The next renderer optimization should reduce work in the measured surface/texture/Z/cache or model paths; avoid adding a branch or specialized path for a small input population without workload and parity evidence.

### 486 and DOS constraints

The product target is a 32-bit DJGPP executable for i486-class hardware. The build has i486 and i386 targets where documented, and the release configuration requires i486. The strict ISA tooling checks selected object and linked executable ranges so compiler or assembly changes do not silently introduce later instructions. The DOS platform boundary owns DPMI memory acquisition, timer and interrupt handling, input, and VGA/VESA operations. These are appropriate target-specific dependencies; a generic cross-platform abstraction layer would add indirection without a current second platform requirement.

Physical-hardware acceptance is explicitly pending in benchmarks/docs/PHYSICAL-486-ACCEPTANCE.md. That procedure records machine, DPMI, memory, video, audio, build, PAK, and executable identity; it separates deterministic parity from uninstrumented timing; it requires several demos and local maps with alternating pairs. Until that evidence exists, label performance and stack observations as DOSBox-X/DPMI evidence. This is a qualification gap, not proof that the current release fails on hardware.

## Prioritized findings

| Priority | Finding | Expected impact | Complexity / effort | Risk |
| --- | --- | --- | --- | --- |
| P1 | Complete physical 486/DPMI qualification | High confidence for target reliability and performance claims | High effort; hardware access and repeated runs | Low implementation risk |
| P1 | Keep the generated/runtime renderer stack model synchronized with call paths | High reliability impact; large frames remain in the hot path | Medium effort; ongoing validation | Medium |
| P2 | Diagnose the observed low-memory map-load boundary | High reliability and supportability impact for constrained DOS/DPMI hosts | Medium; requires controlled captures and pool-level evidence | Medium |
| P2 | Complete six-scene parity with reconciled selector profiles | High confidence in configuration coverage | Medium; DOSBox runtime and captured-output review | Medium |
| P2 | Add host structural tests and complete provenance for the custom ISO writer (completed 2026-11-17) | Medium release confidence impact | Low to medium | Low |
| P2 | Continue incremental ownership work around global renderer and engine state | Medium maintainability impact | Medium to high; preserve legacy interfaces | Medium to high |
| P3 | Decompose the remaining large BENCH486 test harness only where it improves ownership or review | Local maintainability impact; no runtime effect | Low to medium, demand-driven | Low |

### P1 — Physical 486/DPMI qualification remains open

The repository has a detailed acceptance procedure and extensive DOSBox-X parity/timing records, but no physical-machine evidence in the reviewed documentation. Emulator timing cannot establish the 486’s cache, memory wait states, FPU behavior, BIOS/VESA compatibility, or the DPMI provider’s stack allocation. Recent candidate timing results differ between timedemos and local maps, demonstrating why one workload is insufficient.

**Action:** When hardware is available, run the existing physical procedure without weakening it: verify normal startup, collect three color/Z parity replays for demo1/2/3, run local-map checks, then gather at least five alternating uninstrumented pairs per workload. Preserve raw logs and hashes, report each workload and spread separately, and qualify the stack guard on the actual machine. Until then, keep claims explicitly scoped to DOSBox-X.

### P1 — Stack safety has strong checks; physical-system margin remains unknown

The 128 KB edge/surface frame is a significant DOS design constraint. The build checks generated frame prologues and cross-checks preprocessed runtime formulas; the dispatcher rejects a render that does not fit and can disable waterwarp when only the fallback budget is short. The formulas and their caller/callee terms are documented in `quake/docs/renderer-assembly/warp-scratch.md`.

The residual maintenance risk is that complete path requirements include modeled relationships and recursion assumptions. A new call edge, selector, compiler frame, or profiling callback can invalidate the model even if its individual frame remains below the limit. The captured DOSBox-X stack margin does not establish the bounds provided by real DPMI hosts.

**Action:** Keep the frame-budget check in release, C-reference, and PROFILE486 gates. When changing renderer entry points, BSP traversal, polygon clipping, or callbacks, update the call-path ledger and generated/runtime cross-check together. Retain the reduced-stack DOSBox regression as emulator evidence. Complete the physical acceptance procedure before making hardware safety claims.

### P2 — Low-memory map-load failures need pool-level diagnosis

`quake/docs/memory-budget.md` and `meminfo` now account for the engine arena, video hunk, cache, renderer capacities, warp allocation, and stack as distinct pools. The evidence brackets one e1m1 transition between 7,241,728 bytes (stops before `POSTMAP`) and 7,258,112 bytes (completes) for the recorded DOSBox-X/CWSDPMI setup. Standard `-minmemory` and the captured registered-data minimum runs also stop during map loading. The captured logs contain no `Sys_Error`, `Host_Error`, or hunk-allocation failure, so the evidence does not identify which request failed.

**Action:** Preserve these runs as an observed boundary for that build and DPMI setup, not a general minimum requirement. Add targeted instrumentation or allocation-failure diagnostics around map loading, then repeat with matched build, map, and DPMI settings to identify the pool/request at the failure point. Do not raise the startup minimum or claim every map loads at that minimum based on the current captures.

### P2 — Selector flag matrix is reconciled; full parity remains open

The recorded release and C-reference inventories contain 98 and 92 assembly sources, respectively. The 2026-11-17 follow-up classified the 29 `test-build-dos.py` reports against current `DumpFlags` output and the ordered selector table. The i486/i386 goldens were refreshed for the resolved tail-Z and BSP frame-count flags and profile paths. Selector probes now set required dependencies, hold sibling implementations stable where flags are shared, and account for the two independent `skyasm` tokens and C reference tokens. The standalone selector test and its host-suite gate both pass.

The full game host suite passed 15/17 gates. `test-sysinfo-dos.py` failed on a stale substring boundary before compilation, and `test-video-dos.py` could not invoke its required native `gcc`, which is not installed in this environment. The full six-scene framebuffer/palette parity run has not yet been repeated against the updated source identity.

**Action:** Complete the full documented multi-scene parity suite and retain exact frame/checksum, framebuffer, palette, and color/Z evidence. Re-run the game host suite in an environment with native GCC after correcting the stale `VID_Init` test slice. Keep source-bound and linked-image i486 gates tied to the resulting build identity. This remains the highest-value follow-up to the assembly split because build-selection drift is a greater risk than runtime overhead.

### P2 — ISO writer host coverage and sidecar provenance added (2026-11-17)

`benchmarks/tools/test-build-iso9660.py` builds and parses synthetic images, checking volume descriptors, both-endian path tables, directory records, extent ordering, sector alignment, payload bytes, empty directories, boundary-sized payloads, invalid and duplicate names, and rejected links/reparse points. The benchmark host runner invokes it, and `test-launcher-provenance.ps1` validates manifest discovery, executable matching, and the selected build identity. The version-2 portable-ISO sidecar records the benchmark-suite revision, selected game build-manifest hash and configuration identity, executable hash, staged-file hashes, and ISO hash.

The 2026-11-17 benchmark host run passed 22/22 gates. A complete local ISO build produced 26,939 sectors from the current i486 release executable and local base-game PAKs; the generated sidecar's executable and manifest hashes matched. The ISO and PAKs remain local generated/licensed inputs. DOS boot validation remains a separate integration gate and was not run for this format/provenance change.

### P2 — Assembly-file ownership is improved; selector complexity remains

The original roughly 299 KB, 11,914-line `renderer/asm486_experiments.s` mixed many selector-conditional routines in one translation unit. It has been split into subsystem-owned renderer units and a collision unit. This materially improves source navigation, review ownership, and independent change/merge scope. The split preserved the documented 88 exported symbols without duplicate exports and did not claim an algorithmic or runtime speedup. The documented i486 release inventory now contains 98 assembly sources; the C-reference inventory contains 92 because six selector-independent helpers do not need to be rebuilt there.

This is the detailed status of priority action #6. The decision to split was sound because the old file crossed stable responsibilities. Source discovery is recursive, retains unique object basenames, and is mapped through `docs/source-layout-map.json`, including one-to-many mappings for moved routines. Keeping one ordered selector source is also sound: `tools/selectors.ps1` centralizes parameter validation, manifest names, profile suffixes, C and assembly flags, assembly inclusion, and expected assembly inventory. Replacing that table with multiple hand-maintained profile lists would recreate the drift it was designed to prevent.

The selector matrix remains the harder part. The handoff describes 115 current i486 assembly selectors. Each choice can affect compiler/assembler defines, active source files, profile identity, build manifests, selector inventory checks, and the C-versus-assembly comparison path. This multiplies configuration and review work, although the C oracle is valuable for exact parity and performance A/B work. The public builder limits shipping configurations to named profiles; the experimental builder carries the finer-grained choices. The documented expectation mismatches have been resolved in the current test contract; full multi-scene parity still needs to be repeated.

**Action:** Treat the translation-unit split as complete. Keep source discovery, symbol/ABI contracts, per-source ISA checks, profile manifests, release hash pins, and C-oracle parity synchronized with the reconciled selector table. Avoid splitting files further solely to reduce line counts; do it when a file crosses ownership boundaries or causes review/merge friction. Consider pruning only selectors that are both unused and unsupported by a current parity, measurement, or historical-reproduction need. Any such pruning must update the selector table, public experimental interface, tests, and provenance together.

The C/assembly matrix remains useful on a 486: it supports matched implementation comparisons and preserves a C oracle for selected routines. Its cost is real, however: every extra selector expands flag, object, identity, test, and review combinations. The practical control is to keep the public shipping builder limited to named profiles, isolate exploratory combinations behind the experimental builder, and require a documented reason for adding or retaining selectors. Do not simplify by removing the C oracle or parity gates without evidence that the alternative preserves correctness and the measurement workflow.

### P3 — BENCH486 harness decomposition is optional and demand-driven

The BENCH486 code has moved out of `core/host_cmd.c` into `src/tests/bench486/bench486_harness.c`, correcting the production/test ownership boundary and narrowing the normal host-command module. The test-owned harness remains a large, broad translation unit. Its size is no longer a production architecture defect, but can still increase test rebuild scope and make fixture ownership harder to review.

**Action:** Split only when a concrete maintenance issue appears, such as unrelated fixtures repeatedly conflicting, test-only dependencies leaking across cases, or reviewers being unable to trace one fixture's data. Extract cohesive groups behind test-owned headers; preserve benchmark command strings, report formats, checksums, and fixture ABI. Avoid turning each small fixture into a new module without a dependency or ownership benefit.

## Current strengths to preserve

- Subsystem source directories and public headers are documented; the production quakedef.h include inventory is empty. The header check verifies direct include contracts, while architecture review still needs to account for transitive dependencies and global mutable state.
- Renderer stack requirements are checked against generated release, C-reference, and PROFILE486 assembly, and runtime dispatch checks actual ESP against DJGPP bounds.
- C/assembly interfaces now have targeted compile-time size and offsetof assertions, including renderer data structures used by assembly. Keep extending the contracts where assembly consumes C layout.
- Build identity is based on source/configuration inputs. Optimization-history completeness is provenance, not a build prerequisite.
- The workspace doctor and benchmark/game interface documentation make the split checkout and toolchain boundary visible.
- Rendering and timing evidence separates exact parity, instrumented profile attribution, uninstrumented emulator timing, and physical-hardware acceptance.

## Action roadmap

### Quick wins

1. Run the documented full six-scene C-reference/i486 comparison against the reconciled selector matrix; retain exact output evidence and current source identities.
2. Diagnose the allocation or pool that causes the captured pre-`POSTMAP` failures, without turning the observed DOSBox boundary into a general memory minimum.
3. Keep physical qualification status visible in benchmark reports; avoid broad 486 claims based only on DOSBox-X.

### Substantial engineering opportunities

1. Complete the physical 486/DPMI acceptance matrix, including rendered parity, VGA/VESA startup, stack behavior, and alternating uninstrumented timing pairs.
2. Add pool-level evidence for the low-memory map-load boundary across base and registered data; distinguish startup minimums from map-specific capacity.
3. After selector expectations are reconciled, run complete multi-scene parity and matched release profiling on the current source revision. Keep emulator timing and physical timing separate.
4. Continue incremental state ownership through existing subsystem headers. Do not convert the complete renderer to context objects until a prototype shows that the 486 code generation remains acceptable.
5. Consider moving edge/surface scratch arrays only if physical stack measurements justify spending additional engine memory. Preserve exact image/Z output and compare matched timings on target hardware.
6. Keep the assembly split and single selector table stable. Reduce the selector matrix only where current parity, measurement, and historical-reproduction needs permit; preserve symbol/ABI, source-bound ISA, build identity, release pin, and C-oracle contracts.
7. Direct optimizations at measured surface, texture, Z/cache, and model work. Require exact color/Z parity, a strict i486 ISA pass, and repeated matched uninstrumented timings; refresh broad profiles after structural changes.

## Assessment limits

This is a source-level architecture assessment supplemented by existing project reports and a November 17 source/documentation refresh. The November 15 performance profile and DOSBox-X/CWSDPMI memory and stack captures are recorded evidence, not runs performed during this refresh. The November 16 assembly-split gates and focused parity results are reported by the handoff document and were not rerun here. No build or test command was executed for this refresh. Physical 486 qualification remains pending. The assembly split, BENCH486 extraction, and memory-budget instrumentation are completed work; remaining recommendations are not evidence that the current release build is incorrect.
