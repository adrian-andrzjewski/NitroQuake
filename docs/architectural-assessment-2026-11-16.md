# NitroQuake Architectural Assessment

**Assessment date:** 2026-11-16  
**Reviewed code baseline:** outer repository `94c492a`; game repository `38873bc`  
**Checkout relation:** the outer committed and staged `quake` gitlink both resolve to the reviewed game `HEAD`. The nested game worktree was clean; the outer documentation edits are the changes recorded by this assessment.  
**Method:** source, build, and documentation review plus the read-only workspace doctor and header-dependency check. No build, DOSBox run, or physical-hardware test was performed specifically for this assessment.

This assessment supersedes the November 14 snapshots in [architectural-assessment-2026-11-14.md](architectural-assessment-2026-11-14.md) and [architectural-assessment-2026-11-14-current.md](architectural-assessment-2026-11-14-current.md). The older reports remain available as historical records; their roadmaps describe earlier code states.

## Executive summary

NitroQuake keeps two independent Git histories: the outer repository owns benchmark orchestration, fixtures, and reports, while the nested game repository owns the DOS engine, assets, build, and engine checks. The nested game is recorded as an outer Git gitlink rather than a configured submodule. The new [workspace doctor](../benchmarks/tools/check-workspace.ps1) checks the committed and staged gitlink against the nested `HEAD`, reports dirty state and tool availability, and does not fetch or modify either checkout.

The game source is now grouped by subsystem, and narrow renderer, video, memory, client, and server interfaces are available. The header-dependency check reports 83 production C files and no remaining production includes of `quakedef.h`. The compatibility umbrella remains for downstream and reference code. Renderer state and calling relationships still have broad shared ownership in legacy paths, so continued targeted interface work remains appropriate.

The renderer-owned 64,000-byte warp image is no longer reserved in the normal render frame. Generated stack-frame budgets are checked during builds, and `R_RenderViewDispatch` checks the current DJGPP stack bounds before entering the large normal renderer path or its guarded warp fallback. The edge and surface arrays in `R_EdgeDrawing` still account for roughly 128 KB of stack use. Current preflight reduces the risk of entering that path without headroom; moving those arrays remains a possible follow-up that needs exact image parity and matched performance evidence.

Product build identity now derives from the source revision and resolved build configuration. The optimization-attempt count and inventory digest remain manifest provenance when the inventory can be completed, but neither determines the product identity. Full Git history is needed for a complete inventory, not for building from an available `HEAD`.

## Current boundaries

### Repositories and tools

The outer repo contains `benchmarks/` and `docs/`; `quake/` is an independent game checkout recorded by the outer gitlink. Commit game changes in the nested repo before updating the outer gitlink. The workspace check reports both revision values and detects a committed or staged gitlink that differs from the nested `HEAD`.

The check reads the pinned manifests and local tool cache without bootstrapping anything. At the reviewed workspace, Git 2.55.0, PowerShell 7.6.9, Python 3.10.11, DJGPP GCC 12.2.0 with its `objdump`, and DOSBox-X 2026.08.31 were available. Native host GCC was not installed; it is needed only for selected game host fault-injection tests. Matplotlib was not installed; it is needed only for optional chart generation. DOS runtime scenarios also require legally obtained game PAK files. These are availability observations for this machine, not repository-wide guarantees.

The game build remains independently usable without the benchmark checkout or DOSBox-X. Its named public configurations are `i486-release` and `c-reference`; selector-heavy comparisons remain behind the internal experimental backend. The benchmark suite consumes the game's `-DumpFlags` API and does not own native game compilation.

### Source and header ownership

Production files are grouped under `quake/src/` by assets, audio, client, collision, core, memory, network, platform, renderer, server, tests, and video. C and assembly implementations remain close to their subsystem. The public headers include `render.h`, `vid.h`, `zone.h`, `client.h`, `server.h`, and `host.h`. The migration intentionally leaves legacy symbols and calling conventions intact.

`tools/test-header-dependencies.py` reports 83 production C translation units, zero that include `quakedef.h`, and 27 production consumers that include their profiling interface directly. This verifies the include boundary, not independent runtime ownership: renderer globals and some cross-module state remain shared. The narrow-header migration should continue around stable seams without rewriting the DOS memory model or renderer state wholesale.

### Renderer stack and warp memory

`R_InitWarpBuffer` allocates the warp image for renderer lifetime. On allocation failure, the renderer checks available DJGPP stack capacity before using the separate fallback frame; if fallback capacity is insufficient, waterwarp is disabled. Before normal rendering, the dispatcher measures stack bounds and checks the generated requirement using loaded BSP depth. A failed normal preflight skips that render and reports the requirement and shortfall.

The current formulas and generated-frame values are recorded in [warp-scratch.md](../quake/docs/renderer-assembly/warp-scratch.md). The release, C-reference, and PROFILE486 build paths run [renderer-stack-budget.py](../quake/tools/renderer-stack-budget.py) against generated frames. Documented DOSBox-X runs include exact 320 x 200 parity across warp modes and a reduced-stack executable scenario. The forced-short warp-capacity mode is synthetic; the reduced-stack run changes the executable's staged DJGPP minimum stack field. Neither substitutes for testing a physical 486/DPMI environment.

`R_EdgeDrawing` still owns large automatic edge and surface arrays. The preflight and build-time frame checks are current safeguards, while a move to renderer-owned scratch is a performance-sensitive future option. Any such move should preserve exact C/assembly output and use matched timing on the target hardware before claiming a benefit.

### Product identity and optimization history

The displayed build ID combines the source revision with a fingerprint of source inputs and resolved configuration. The manifest separately records the optimization-attempt count and inventory digest when available; shallow history or unavailable inventory is represented explicitly. This keeps binary identity usable in shallow clones while retaining historical progress as provenance.

## Priorities

1. **Qualify renderer stack behavior on target hardware.** Preserve the generated-frame checks and normal-path preflight. When a physical 486/DPMI setup is available, record stack capacity, representative scenes, and output parity separately from DOSBox evidence.
2. **Evaluate edge/surface scratch migration with evidence.** A renderer-owned workspace may reduce pressure on the DOS stack, but it changes addressing and possibly 486 timings. Require exact output parity and matched measurements before adopting it.
3. **Continue narrowing shared renderer state.** Use the subsystem headers and source grouping for incremental migrations. Keep `quakedef.h`, public symbols, and calling conventions stable until compatibility consumers are known.
4. **Keep provenance dimensions distinct.** Continue recording source/configuration identity, optimization inventory, benchmark-suite revision, and emulator or hardware environment as separate fields.

## Verification evidence and limits

- `benchmarks/tools/test-workspace-doctor.ps1` passed: it checked the current gitlink, rejected a synthetic mismatched game revision, and compared repository status before and after inspection.
- `benchmarks/tools/run-tests.ps1 -HostOnly` passed all 20 gates, including the workspace doctor and staging checks.
- `quake/tools/test-header-dependencies.py` passed: 83 production C files, zero explicit legacy umbrella users, and 27 direct profiling consumers.
- `quake/tools/doc-structure-check.ps1` passed: 707 documents and 692 ledger files scanned.
- `benchmarks/tools/check-workspace.ps1 -Json` reported matching committed/index/nested revisions and available build and runtime toolchains. It reported native host GCC unavailable.
- No build, benchmark, DOSBox runtime scenario, or physical-486 test was run as part of this assessment. Runtime parity and stack observations above refer to the committed renderer report, not a new run in this review.
