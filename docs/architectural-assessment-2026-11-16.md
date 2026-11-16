# NitroQuake Architectural Assessment

- **Assessment date:** 2026-11-16
- **Outer repository:** HEAD 71f17310c58464ed5910b43db73393b63d18e9e1; implementation/tool baseline 94c492a
- **Game repository:** HEAD 38873bce04762ced607ac36c5d59891173dbe275
- **Checkout state at review start:** outer and nested worktrees clean; committed and staged outer gitlinks point to the reviewed game HEAD. The outer HEAD after 94c492a contains documentation updates.
- **Method:** Read-only inspection of source, build scripts, architecture documentation, test contracts, and recorded profiling/parity evidence. No code was changed. No build, test suite, DOSBox scenario, or hardware run was executed for this review.

This report supersedes the November 14 snapshots in [architectural-assessment-2026-11-14.md](architectural-assessment-2026-11-14.md) and [architectural-assessment-2026-11-14-current.md](architectural-assessment-2026-11-14-current.md). Those documents describe an earlier source and worktree state.

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
“Substantial engineering opportunities.” Other findings remain tied to the
reviewed baseline unless covered by a later dated follow-up.

## Executive assessment

NitroQuake is a mature, DOS-first software renderer and game engine with unusually strong evidence discipline for a legacy 486 target. The repository split is explicit: the nested game checkout owns C, GNU assembly, game assets, the DJGPP build, native correctness fixtures, and ISA verification; the outer checkout owns DOSBox automation, scenario data, output analysis, and reports. A read-only workspace doctor now verifies that the nested checkout matches the committed and staged gitlinks.

The game source is grouped by subsystem, production C files no longer directly include the legacy quakedef.h umbrella, and C-to-assembly layout checks have been expanded. Build identity is based on source/configuration inputs, while historical optimization inventory remains separate provenance. Strict i486 object and linked-image audits, exact C/assembly parity checks, and rendering oracles are meaningful safeguards.

The remaining risks are concentrated in three areas:

1. **Hardware qualification is still pending.** DOSBox-X provides repeatable screening, but it cannot establish physical 486 performance, DPMI stack behavior, or device compatibility. Recent candidate measurements are workload-dependent and include regressions.
2. **Renderer stack use is large and modeled.** A roughly 128 KB edge/surface frame is now protected by generated-frame checks and runtime DJGPP stack preflight. The safety model is a significant improvement, but its call-path formulas and recursion assumptions need continued maintenance and physical-system evidence.
3. **Subsystem interfaces are clearer than before, but ownership remains global and several files mix unrelated responsibilities.** The largest example is core/host_cmd.c, which combines gameplay commands with a very large BENCH486 profiling and fixture harness. The principal assembly experiment source is also a large selector-conditional translation unit.

The pragmatic direction is to preserve the current DOS memory model, C/assembly calling conventions, narrow shipping build interface, exact output contracts, and evidence gates. Avoid broad modernization that adds indirection to pixel and span loops without measurements.

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

At 320x200, the surface cache baseline is 2,457,600 bytes (renderer/d_local.h and renderer/d_surf.c:117–135). It grows with framebuffer area and can be overridden with -surfcachesize. Renderer setup also allocates edge/surface arrays based on capacity; smaller scenes can use automatic arrays, while larger configured capacities use hunk storage. The waterwarp image is a 64,000-byte libc allocation retained for renderer lifetime (renderer/r_main.c:1396–1416). Allocation failure has a fallback path, but the buffer is outside the zone/hunk ownership API, so engine memory summaries do not describe every renderer-owned allocation in one place.

The largest persistent stack demand is the edge renderer. The arrays in renderer/r_main.c:1030–1035 correspond to generated frames near 128 KB. Current release requirements are 172,864 + 128 × world_depth bytes for the normal render and 236,880 + 128 × world_depth for the warp stack fallback. At the documented DOSBox-X world depth of 72, that is 182,080 bytes normal and 246,096 bytes for fallback. The documented DPMI stack had 523,772 bytes available, leaving 277,676 bytes of fallback headroom in that emulator setup.

The current code is materially safer than the November 14 snapshot. renderer-stack-budget.py parses generated assembly prologues and validates selected view, edge, world, polygon, recursive clip, dispatch, and fallback frames. R_RenderViewDispatch reads ESP and DJGPP stack bounds before the normal render. It skips the render if normal capacity is insufficient, and disables waterwarp if only the extra fallback capacity is insufficient. The loaded BSP depth is measured with an iterative parent-link walk and cached for the current world.

This guard should be treated as a hard safety boundary, not a reason to increase stack use. Generated frame sizes are checked, while some complete path relationships remain explicit model constants (such as polygon-path and recursive-step costs). Changes in call structure, instrumentation callbacks, compiler output, or selector profile must update and validate that model. Moving the 128 KB arrays into permanent storage could reduce stack pressure but consumes scarce hunk/DPMI memory and may change 486 addressing and cache behavior. The current preflight is a reasonable default; consider scratch migration only if real-hardware evidence shows stack rejection or inadequate headroom.

### Renderer costs and optimization evidence

The renderer combines classic BSP visibility and front-to-back world traversal, edge-list scan conversion, surface-cache texture reconstruction, Z spans, and separate alias-model triangle rasterization. These algorithms are suited to software rendering and indexed VGA/VESA output, but their cost varies strongly by scene, view size, model density, sound, and presentation mode. The same 486-oriented profile deliberately mixes C and handwritten assembly based on measured implementations; the current release profile selects C for BSP traversal and exact-zero-T span paths for texture spans while retaining many assembly paths.

The most recent detailed profile report, benchmarks/docs/ENGINE-PROFILING-20261115.md, attributes 50.00% of the corrected parts-mode time on e1m1 and 44.44% on e1m2 to the combined surface, texture, Z, and cache group. Local server work is 17.55% and 16.98%; models and sprites 10.05% and 16.64%; world BSP and faces 9.48% and 9.96%; edges and dispatch 8.05% and 6.81%. Those are DOSBox attribution shares for the measured workloads, not physical 486 cycle shares.

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
| P2 | Split gameplay command ownership from the BENCH486 harness and reduce cross-subsystem state coupling | High maintainability impact in a central 14K-line translation unit | Medium to high | Medium |
| P2 | Make engine memory accounting cover all large allocations and practical low-memory modes | Medium reliability and diagnostic impact | Low to medium | Low |
| P2 | Add host structural tests and complete provenance for the custom ISO writer | Medium release confidence impact | Low to medium | Low |
| P2 | Reduce assembly translation-unit and selector maintenance cost incrementally | Medium maintainability impact across a large set of selectable routines | High | Medium to high |

### P1 — Physical 486/DPMI qualification remains open

The repository has a detailed acceptance procedure and extensive DOSBox-X parity/timing records, but no physical-machine evidence in the reviewed documentation. Emulator timing cannot establish the 486’s cache, memory wait states, FPU behavior, BIOS/VESA compatibility, or the DPMI provider’s stack allocation. Recent candidate timing results differ between timedemos and local maps, demonstrating why one workload is insufficient.

**Action:** When hardware is available, run the existing physical procedure without weakening it: verify normal startup, collect three color/Z parity replays for demo1/2/3, run local-map checks, then gather at least five alternating uninstrumented pairs per workload. Preserve raw logs and hashes, report each workload and spread separately, and qualify the stack guard on the actual machine. Until then, keep claims explicitly scoped to DOSBox-X.

### P1 — Stack safety now has a guard, but the model is part of the architecture

The 128 KB edge/surface frame is a significant DOS design constraint, not an unguarded defect in the current code. The build gate checks generated frame prologues, and the dispatcher rejects insufficient capacity before entering the large normal render. The fallback has a separate budget and controlled degradation behavior.

The remaining maintenance risk is that the whole-stack requirement combines selected generated frames with a small number of modeled path constants and assumptions about recursion and tail-call behavior. This is understandable for C plus handwritten assembly, but a new call edge or profile callback can invalidate the formula even if individual frames still pass.

**Action:** Keep the frame-budget test adjacent to the release, C-reference, and PROFILE486 build gates. Require source review of every call-path assumption when modifying renderer entry points, BSP traversal, polygon clipping, or profiling callbacks. Add a concise mapping from each budget term to the actual caller/callee path in the report and stack tool. Keep the reduced-stack DOSBox test as a useful regression; do not describe the synthetic forced-short mode as a real reduced stack. Physical validation remains a separate requirement.

### P2 — The command module mixes gameplay, diagnostics, and a large benchmark harness

core/host_cmd.c is 14,165 lines. It begins with broad dependencies across client, server, renderer, video, sound, memory, input, and model APIs. Most of its early body contains BENCH486 profiling, checksum/event reporting, memory and renderer fixtures, and benchmark command handling; ordinary host command implementations such as Host_Quit_f begin around line 13,231, with Host_InitCommands around line 15,078. The BENCH486 code is excluded from ordinary release behavior, but it keeps the benchmark harness embedded in the gameplay command translation unit and gives that unit a very wide include and rebuild surface.

**Action:** Split by ownership in stages. First move self-contained BENCH486 reporting, checksum serialization, timer/profile aggregation, and fixture case groups behind test-owned interfaces. Then split gameplay command groups such as lifecycle/map/save-load, client interaction, and server/player controls where dependencies permit. Keep a small command registration layer and preserve the current command strings, public entry points, and test output formats. Do not expose renderer globals broadly just to make the first extraction easy; create narrow test interfaces for the data a fixture actually observes.

### P2 — Memory pressure is intentional but not visible as one budget

The hunk/zone/cache design suits the target, and surface-cache sizing is explicit. However, the user-visible minimum memory check is a coarse threshold, the renderer’s surface and edge capacities can allocate additional hunk storage, the warp image uses libc malloc, and stack requirements are a separate DPMI resource. Those allocations are governed by related but distinct allocators and diagnostics. A successful Host_Init memory threshold does not by itself show how much remains for a large BSP, caches, sound, and stack.

**Action:** Add or maintain a memory-budget document for the supported 320x200 release profile: minimum engine block, default zone, surface cache, edge/surface capacity policy, warp allocation/fallback, level hunk growth, and stack requirement by BSP depth. Improve diagnostics to distinguish engine arena remaining, renderer caches, libc/DPMI allocations where observable, and stack headroom. Do not merge the allocators or raise the minimum blindly; first use the current profiling counters and real low-memory runs to identify pressure.

### P2 — The ISO writer is a bespoke format implementation without direct regression coverage

benchmarks/tools/build-iso9660.py implements directory records, both-endian path tables, extent allocation, volume descriptors, and atomic output replacement. Its input validation is careful about DOS/ISO names, duplicate names, links/reparse points, and volume limits. However, the benchmark test inventory has no dedicated ISO-structure test, and benchmarks/tools/run-tests.ps1 does not invoke an ISO writer test. The launcher sidecar at benchmarks/tools/build-launcher-iso.ps1:229–242 records game revision, executable and ISO hashes, and staged-file hashes, but it omits the benchmark-suite revision and the complete game build-manifest/configuration identity.

**Action:** Add synthetic-tree host tests that parse the output and verify volume descriptors, path tables, directory records, extents, alignment, payload bytes, empty directories, boundary sizes, invalid names, and duplicate names. Include them in the host runner. Add suite revision and game build-manifest hash/profile identity to the sidecar. Keep DOS boot validation separate from writer-format tests.

### P2 — The C/assembly implementation matrix is powerful and costly

The current release profile includes many independently selectable C/assembly routines. That is justified by the 486 target and by measurement: the release profile retains the C BSP walk because it measured faster in its qualified DOSBox workload, while many pixel, memory, and setup routines use assembly. The C-reference profile changes selectable paths but deliberately retains legacy assembly and fixed low-level controls; it is a reference configuration, not an all-C executable.

The risk is implementation drift and review cost. A large portion of renderer assembly is centralized in renderer/asm486_experiments.s, a roughly 299 KB source file with selector-conditional entry points. The internal build machinery is also large: build-dos-experimental.ps1 is about 1,371 lines and selectors.ps1 about 2,587 lines. The selector table is intentionally the single ordered source for flag mapping, live assembly selection, and inventory checks; that consolidation is valuable. The supported public builder remains small and named-profile based.

**Action:** Preserve the single selector source and public profiles. Consider splitting the large assembly file by stable subsystem ownership while retaining one selector table and unchanged symbol/ABI contracts. Keep C layout assertions, source-bound ISA proofs, release/profile checks, and exact C/assembly parity tests next to each split. Simplify internal build mechanics only when a measured maintenance problem is solved; do not replace the selector table with repeated hand-maintained profile lists.

## Current strengths to preserve

- Subsystem source directories and public headers are documented; the production quakedef.h include inventory is empty. The header check verifies direct include contracts, while architecture review still needs to account for transitive dependencies and global mutable state.
- Renderer stack requirements are checked against generated release, C-reference, and PROFILE486 assembly, and runtime dispatch checks actual ESP against DJGPP bounds.
- C/assembly interfaces now have targeted compile-time size and offsetof assertions, including renderer data structures used by assembly. Keep extending the contracts where assembly consumes C layout.
- Build identity is based on source/configuration inputs. Optimization-history completeness is provenance, not a build prerequisite.
- The workspace doctor and benchmark/game interface documentation make the split checkout and toolchain boundary visible.
- Rendering and timing evidence separates exact parity, instrumented profile attribution, uninstrumented emulator timing, and physical-hardware acceptance.

## Action roadmap

### Quick wins

1. Add host structural tests for build-iso9660.py and include them in benchmarks/tools/run-tests.ps1.
2. Extend the portable ISO manifest with benchmark-suite revision and the selected game build manifest/configuration identity.
3. Document the renderer stack formula terms alongside the corresponding callers and callees; make future call-path edits explicitly update this contract.
4. Add a concise release memory budget showing the 320x200 surface cache, default zone, hunk growth, warp image, edge/surface storage, and stack as separate resource pools.
5. Keep physical qualification status visible in benchmark reports; avoid broad 486 claims based only on DOSBox-X.

### Substantial engineering opportunities

1. Complete the physical 486/DPMI acceptance matrix, including rendered parity, VGA/VESA startup, low-memory behavior, and alternating uninstrumented timing pairs.
2. Evaluate moving the edge/surface scratch arrays only if the physical stack measurements justify spending additional engine memory. Preserve exact image/Z output and compare matched timings on the target.
3. Split core/host_cmd.c into command-owned modules and a test-owned BENCH486 harness. Introduce narrow interfaces around state observed by tests rather than adding new global access.
4. Divide renderer/asm486_experiments.s into subsystem-owned assembly units where that reduces merge, review, or ISA-audit scope. Retain the current profile-selection contract and C oracle.
5. Continue incremental renderer state ownership work through existing subsystem headers. Do not convert the complete renderer to context objects until a prototype shows the 486 code generation remains acceptable.
6. Direct future optimizations at measured work in surface, texture, Z/cache, and model paths. Require exact color/Z parity, a strict i486 ISA pass, and repeated matched uninstrumented timings; treat emulator and physical results as separate evidence.

## Assessment limits

This is a source-level architecture assessment supplemented by existing project reports. The November 15 performance and November 14 stack values are recorded historical runs, not runs performed during this review. No build or test command was executed here. Physical 486 qualification remains pending. Recommendations about restructuring the legacy renderer and command modules are architectural opportunities, not evidence that the current build is incorrect.
