# NitroQuake Architectural Assessment

- **Review date:** 2026-11-14
- **Scope:** Outer NitroQuake workspace and nested `quake/` game repository
- **Review basis:** Outer revision `a4b29288fcff87a7a2def32d8c95c590b0650b08`; nested game revision `41174145098667ccb1162dbc2b5e6524400402c5`; the working tree also contained pre-existing, uncommitted renderer edits in `quake/src/renderer/r_main.c`, `r_framecontrol_profile.inc`, and `r_framecontrol_release.inc`.
- **Method:** Read-only source, documentation, and build-script inspection. No source edits, builds, tests, or performance runs were made for this assessment.

This report is a snapshot of the stated revisions and working-tree state; later commits are outside its scope.

## Executive assessment

NitroQuake has a coherent DOS-first architecture with a strong separation between the benchmark/tooling repository and the nested game repository. The supported game build interface is intentionally small, toolchain selection is explicit, and the renderer is being improved with renderer-owned warp scratch and a guarded fallback. There is also useful evidence for the warp change: the renderer notes report matching checksums for 980 demo2 frames and matching 320x200 captures between allocated and fallback paths in DOSBox-X.

The highest architectural risk is still stack use in the edge renderer. The ordinary edge-drawing path allocates large edge and surface arrays on the stack, while the current precise stack preflight is associated with the warp stack-fallback path. A legacy general stack high-water check is disabled. This leaves a large, compiler- and call-chain-sensitive stack frame without a comprehensive runtime budget check. The current fallback is a valuable containment measure, but DOSBox evidence does not establish behavior on physical 486-class hardware.

The main maintainability cost is the broad legacy dependency surface: most C translation units still include the compatibility umbrella `quakedef.h`, and C/assembly interfaces duplicate structure offsets. The build selector implementation is large, though the user-facing build commands remain appropriately narrow. A custom ISO-9660 writer and a split-repository gitlink workflow are further areas where automated structural checks and provenance would reduce operational risk.

## Architecture and data flow

The outer repository owns benchmark automation, fixtures, scenarios, and reports. The nested `quake/` repository owns the game, assets, DOS build, and game verification tools. The game’s main frame path is `Host_Frame` in `quake/src/core/host.c:681`, through `SCR_UpdateScreen` in `quake/src/client/screen.c:1133`, `V_RenderView` in `quake/src/client/view.c:1090`, and into `R_RenderView` in `quake/src/renderer/r_main.c:1137`.

The platform and build boundary is explicit: `quake/tools/build-dos.ps1` exposes named product profiles, while `quake/BUILD-DOS.md` describes the i486 release and C-reference workflows. The game is still a classic C and assembly renderer with DOS-specific allocation and display assumptions. The custom zone, hunk, and cache allocator in `quake/src/memory/zone.c` reflects that target rather than introducing a general-purpose runtime heap abstraction.

## Prioritized findings

| Priority | Finding | Expected impact | Effort | Risk |
| --- | --- | --- | --- | --- |
| P1 | Audit and budget stack use across the full renderer call chain | High reliability impact on DOS | Medium | Medium |
| P1 | Qualify renderer behavior on physical 486-class hardware, or state emulator-only support limits | High confidence impact | Medium to high | Low |
| P2 | Reduce broad header coupling and make C/assembly layouts mechanically checked | Medium maintainability impact | Medium | Medium |
| P2 | Add structural tests and fuller provenance for generated ISO images | Medium release confidence impact | Low to medium | Low |
| P2 | Reduce selector maintenance burden while preserving the narrow supported build interface | Medium build maintainability impact | Medium to high | Medium |
| P3 | Add workspace integrity checks for the nested gitlink and document current architecture in one source of truth | Low to medium operational impact | Low | Low |

### P1 — Stack capacity is not budgeted consistently

The edge renderer declares large local arrays in `R_EdgeDrawing`: `ledges` and `lsurfs` at `quake/src/renderer/r_main.c:991–998`. The source also maintains a calculated `R_WARP_EDGE_FRAME_BYTES` budget at `r_main.c:75–105`; the described frame is roughly 128 KB. That is a major allocation for a DOS stack and is sensitive to compiler output, nested calls, interrupt usage, and future local-variable growth.

The current warp implementation allocates a 64,000-byte renderer-owned buffer in `R_InitWarpBuffer` around `r_main.c:1364–1384`. When it cannot use that buffer, the fallback path reserves stack space in `R_RenderViewStackFallback` around line 1586 and checks available stack using `R_WarpStackHasRoom` around lines 1532–1553. That protection is narrowly scoped to the warp fallback. The legacy general high-water check in `quake/src/platform/dos/sys_dos.c:71–96` is under `#if 0`, so ordinary stack-heavy rendering is not covered by the same check.

**Recommendation:** First make the stack budget explicit for every renderer path that can consume large automatic storage. Prefer moving the largest renderer scratch arrays to renderer-owned storage with a documented lifetime and capacity, while keeping a deterministic failure or fallback path for allocation failure. In the short term, retain compile-time estimates and add a low-cost guard before entering the risky path. Treat compiler version, optimization profile, and interrupt headroom as inputs to the budget; do not infer safety from nominal available memory alone.

The current scratch note, `quake/docs/renderer-assembly/warp-scratch.md`, reports DOSBox-X measurements of 246,020 required bytes versus 523,772 available for the release profile, with 277,752 bytes of calculated headroom. The fallback matched all 980 demo2 frame checksums and a 320x200 capture. The C-reference measurements report 245,732 bytes required and 523,720 available. These are useful parity and emulator-capacity results. The forced-short test changes test capacity after checking the actual bounds, so it does not demonstrate operation under a genuinely smaller DOS stack. This qualification should be made clear in future reports.

### P1 — DOSBox results do not qualify real 486 performance or reliability

The latest available profiling report, `benchmarks/docs/ENGINE-PROFILING-20261113.md`, identifies world/face work, alias-model work, Z-buffer spans, edge scanning, and surface-cache behavior as important costs after correcting exclusive timing spans. It notes instrumentation overhead and reports DOSBox-X configured as a 486/387 with a fixed cycle budget. This supports prioritizing required span and pixel work, but it does not prove physical 486 throughput, stack behavior, timing, or compatibility.

**Recommendation:** Keep emulator checks as the fast regression gate. Establish a repeatable physical-hardware qualification record for representative low-memory and rendering scenarios, including compiler/profile identity, machine details, frame parity, and failure behavior. Until that exists, label performance and capacity conclusions as DOSBox-X evidence. Re-profile after source changes and compare matched, uninstrumented runs; instrumentation should guide hypotheses, not serve as the sole performance result.

### P2 — Broad compatibility headers obscure module boundaries

The source-layout guide, `quake/docs/source-layout.md`, documents public headers such as `render.h`, `vid.h`, `zone.h`, `client.h`, and `server.h`, and recommends narrow headers for new code. However, the current inventory shows 77 of 83 C files include `quakedef.h`, which remains a compatibility umbrella. This makes dependencies difficult to see, increases rebuild coupling, and makes it harder to identify ownership when moving code between client, renderer, platform, and memory subsystems.

Assembly interfaces also duplicate C layout knowledge. For example, `quake/src/renderer/asm_draw.h:37` describes `espan_t` offsets that must mirror `r_local.h`; `sspan_t` has a similar declaration around line 59. Some compile-time checks exist near `r_main.c:975`, but the source still has multiple manually synchronized declarations.

**Recommendation:** Keep `quakedef.h` as a compatibility boundary, but stop expanding its use. Migrate files in small subsystem batches to narrow headers and document the allowed dependency direction. Add compile-time size/offset assertions for every structure consumed by assembly; if the toolchain can support it reliably, generate the assembler offsets from one authoritative definition. Avoid a wholesale header rewrite, which would create large churn without an immediate runtime benefit.

### P2 — Build selector internals are harder to maintain than the supported interface

The public builder has a concise named-profile interface in `quake/tools/build-dos.ps1`, and the documented product configurations are `i486-release` and `c-reference`. The implementation behind it is substantially larger: `quake/tools/build-dos-experimental.ps1` is about 1,347 lines, and `quake/tools/renderer-profiles/selectors.ps1` is about 2,587 lines with a large selector catalog. Those files are internal machinery, not evidence that the supported product builder exposes hundreds of user options. The ordered-selector contract and drift checks documented in the selector source are useful safeguards and should be retained.

The C-reference profile also needs precise wording: `quake/tools/renderer-profiles/i486-c-reference.json:3` disables selected renderer paths but retains some legacy assembly and fixed low-level controls. It is a reference for selectable rendering paths, not a fully assembly-free build.

**Recommendation:** Preserve the named-profile public interface. Reduce implementation complexity only where generated or declarative data can replace duplicated selector logic without weakening drift checks. Add a machine-readable profile summary to build output so artifacts can be traced to resolved settings. Keep “C-reference” semantics explicit in documentation and benchmark metadata.

### P2 — Custom ISO output needs structural regression coverage and complete provenance

`benchmarks/tools/build-iso9660.py:204` implements ISO-9660 layout and extent/path-table logic directly. The current benchmark host-test runner, `benchmarks/tools/run-tests.ps1:117`, does not invoke dedicated tests for the ISO writer. The launcher ISO sidecar in `quake/tools/build-launcher-iso.ps1:229–245` records format, creation time, volume ID, game revision, executable size and SHA, ISO size and SHA, and payload hashes. It does not identify the benchmark-suite revision or a complete game build fingerprint/configuration.

**Recommendation:** Add host-side tests that parse the generated image and verify directory records, path tables, extents, file ordering, payload hashes, and alignment using synthetic fixtures. Test malformed paths and boundary sizes. Extend the sidecar with suite revision and the game build manifest/fingerprint so a launcher image can be reproduced from its evidence. Keep a DOS launch smoke check as a separate integration gate.

### P3 — Workspace gitlink and assessment documentation can drift

The outer repository records `quake/` as a gitlink rather than a normal directory. This review observed outer status `m quake` while the nested checkout had three modified renderer files. That is expected for nested development, but it makes it easy to review or benchmark a nested revision different from the recorded gitlink. A lightweight workspace check could report this clearly before a build or benchmark.

The existing `docs/architectural-assessment-2026-11-14.md` describes an older source state: its recorded revisions are `8a64282` and `db4831f`, and some findings are now stale. In particular, it describes warp scratch as render-local, calls the source layout flat, and treats full Git history as required for product build identity. Current code has a renderer-owned warp buffer and fallback; source-layout guidance and subsystem directories exist; build identity uses a source/configuration fingerprint, with history optional for inventory. Keep the older file as historical evidence, but label it superseded and link to the current assessment when the repository documentation is next updated.

**Recommendation:** Add a read-only workspace doctor that reports outer HEAD, nested HEAD, gitlink target, dirty state, and required tool availability. Make it warn rather than mutate. Add a short assessment index or supersession note so readers do not mistake historical reviews for current findings.

## Roadmap

### Quick wins

1. Document the exact scope and limits of the existing warp stack test, including that the forced-short case is synthetic and DOSBox-X is not physical-hardware evidence.
2. Record resolved build profile, compiler/toolchain identity, and source/configuration fingerprint alongside benchmark and ISO artifacts.
3. Add host-side structural tests for the ISO writer and include them in the benchmark host-test runner.
4. Add assembly structure size/offset assertions for every C structure accessed by handwritten assembly.
5. Add a read-only workspace check for gitlink mismatch and nested dirty state; do not make it auto-clean or auto-reset either repository.

### Substantial engineering opportunities

1. Build a renderer stack-usage budget for ordinary, warp, and fallback paths using the actual release compiler output and call graph. Move the largest stack scratch arrays to an owned workspace if measurements confirm the budget is fragile.
2. Create a physical 486 qualification matrix with repeatable parity, memory-pressure, and performance scenarios. Preserve DOSBox-X as a fast regression environment and report both evidence types distinctly.
3. Migrate from `quakedef.h` to narrow subsystem headers incrementally, with explicit dependency rules and no broad compatibility break.
4. Simplify selector internals through generated profile data or smaller capability groups, but preserve the current stable profile interface and selector drift validation.
5. Re-profile renderer hot paths using matched uninstrumented runs and exact output parity. Optimize measured work in edge/span generation, world/face traversal, alias drawing, Z spans, and surface-cache access before adding architecture-wide abstractions.

## Review limits

This assessment is based on source, documentation, build scripts, and recorded benchmark evidence. No build, host suite, DOSBox run, or physical hardware run was performed for this review. The renderer worktree edits were pre-existing and were not changed. Conclusions about performance and stack headroom are therefore limited to the documented DOSBox-X measurements and source-level analysis.
