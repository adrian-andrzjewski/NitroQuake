# NitroQuake Architecture Action Checklist

**Assessment snapshot:** 2026-11-17  
**Outer repository:** `7ea6d146e1b410487d87c2c9549dbbd58fb5e8a8`  
**Game repository:** `ab81c94b83765e78723c48c62cb335c96fc41d96` (outer gitlink matches)

This checklist converts the findings in [the architectural assessment](architectural-assessment-2026-11-16.md) into reviewable work items. The snapshot hashes identify the source state used to create the list; dated completion notes below record work performed afterward. Recorded test evidence identifies when and against which source the checks ran.

## P1 — Target reliability and stack safety

### Complete physical 486/DPMI qualification

- [ ] Record machine/CPU, BIOS, FPU, DPMI provider/version, available memory and stack, video mode/device, audio device, game revision, build profile, executable hash, manifest, and PAK hashes.
- [ ] Verify release startup and VGA/VESA presentation on the target; record audio/device behavior where supported by the acceptance procedure.
- [ ] Run the prescribed demo1/demo2/demo3 parity replays and local-map checks. Preserve raw logs and output hashes.
- [ ] Collect at least five alternating uninstrumented timing pairs per workload. Report each workload and its spread separately.
- [ ] Exercise normal rendering, waterwarp fallback behavior, and stack rejection on the actual DPMI stack. Preserve the generated stack-budget report.
- [ ] Keep DOSBox-X measurements labeled as emulator evidence; do not use them to claim physical 486 performance or compatibility.

**Completion evidence:** The raw captures and hashes satisfy [`benchmarks/docs/PHYSICAL-486-ACCEPTANCE.md`](../benchmarks/docs/PHYSICAL-486-ACCEPTANCE.md), with parity, startup, stack, and timing results reported separately.

**Status update (2026-11-17):** No physical 486/DPMI system was available for this pass. The new engine profile is explicitly DOSBox-X evidence and does not close this hardware qualification item.

### Maintain the renderer stack model as a build invariant

- [x] For changes to renderer entry points, BSP traversal, polygon clipping, or profiling callbacks, update the call-path ledger and generated/runtime formula checks together.
- [x] Keep generated-frame and preprocessed-runtime formula checks enabled for release, C-reference, and PROFILE486 configurations.
- [x] Preserve the runtime guard that rejects an insufficient normal render stack and disables waterwarp when only fallback capacity is insufficient.
- [x] Treat reduced-stack DOSBox runs as emulator regression evidence; qualify DPMI stack margin separately on hardware.

**Completion evidence (2026-11-17):** Fresh i486 release, C-reference, and PROFILE486 builds passed generated-frame and runtime-formula checks. Their linked ISA gates passed with 166,300, 176,959, and 326,951 instructions, respectively, and zero above-i486, unknown, or exempt instructions. Existing 192 KiB/160 KiB reduced-stack runs and warp fallback parity are DOSBox-X/CWSDPMI regression evidence only; physical DPMI stack margin remains open under the hardware qualification item. Exact commands and source/build identities are recorded in [`quake/docs/renderer-assembly/warp-scratch.md`](../quake/docs/renderer-assembly/warp-scratch.md).

## P2 — Configuration, memory, and release confidence

### Explain the low-memory map-load boundary

- [x] Instrument map loading to identify the exact allocation request or resource pool that prevents `POSTMAP` completion.
- [x] Repeat controlled base-game and registered-data runs with the same build, map, and DPMI setup; preserve console/error logs and `meminfo` output.
- [x] Record startup minimum separately from map-specific capacity. Do not generalize the observed e1m1 transition (7,241,728 bytes fails before `POSTMAP`; 7,258,112 bytes completes) to other hosts or maps.

**Verification evidence (2026-11-17):** The isolated `i486-c-reference`
memory-trace build (`762d22afa0db-e53a4a60da19`, source
`762d22afa0db7e093363d8c4c7d3522dbbfd40f0`) ran under DOSBox-X
2026.08.31/CWSDPMI (80486, DOS 5.00, DPMI 0.90, 31,280 KiB reported RAM). The
5,570,560-byte standard startup minimum first failed a 107,984-byte low-hunk
request with 47,760 bytes available; at 7,241,728 bytes `e1m1` first failed a
22,000-byte request with 15,056 available; at 7,258,112 bytes `e1m1` completed.
Hipnotic `hip1m1` and Rogue `r1m1` startup-minimum runs first failed low-hunk
requests of 129,772 and 141,172 bytes, with 47,168 and 63,328 bytes available.
These results identify this build's first failing pool and allocation; they do
not establish minima for other maps, DPMI hosts, or physical 486 systems. Raw
ignored run outputs are under
`benchmarks/out/memory-maptrace-20261117-125228/`. See
[`quake/docs/memory-budget.md`](../quake/docs/memory-budget.md) for build hashes,
PAK hashes, and detailed conditions.

### Reconcile selector/profile expectation mismatches

- [x] Triage each of the 29 reported `test-build-dos.py` selector/profile mismatches against the selector table, resolved flags, manifests, and actual source inventories.
- [x] Correct stale expectations or implementation defects based on evidence. Do not suppress or bulk-update mismatches without classifying them.
- [x] Run the game host checks after the corrections; ensure release and C-reference inventories agree with their declared profiles.
- [x] Run the full documented multi-scene parity suite after selector expectations are clean; retain exact framebuffer/palette and color/Z evidence.
- [x] Reconfirm source-bound and linked-image i486 ISA gates and release artifact identity after any selector or assembly-source change.

**Verification evidence (2026-11-17):** At game revision `762d22a`, `pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly` passed 17/17 gates in 458.7 seconds. `tools/test-build-dos.py` passed all 138 selectors; the release and C-reference inventories and the release artifact identity guard passed.

The seven-scene framebuffer, palette, and color-stream comparison passed at source revision `4de90f649243c59425919ef7a51d1e89044447d1` with source-tree fingerprint `F99D9FE3FBFAD1B5F4FBAB4FC46C11C8782EE8B48332D5D4059BAAD5D69A7797`. It compared `i486-c-reference` (source fingerprint `47546F60B85FC2BB630D76932EACB179936868386C4881656EEB1860A7A194E9`) with `i486-asm-selectable-current` (`9B96BD582E30BAAF1DB602916C6D7379B0D321F8EA8421DBD36190B3379B0D6C`). The following game commits `8aff712` and `762d22a` changed test fixtures only. All seven scenes matched exact 320x200 frame captures and palettes; their color streams compared 964 frames after six startup records. The report is `benchmarks/out/render-parity-20261117-074215/render-parity-result.json`.

A fresh C-reference (`i486-c-reference`, source fingerprint `2002B12C0199436302FAEEEE8FF855AA2EDB1277082066F048F12DF98626FED4`) versus assembly-selector (`i486-asm-selectable-current`, source fingerprint `F556F7694F9FDD4B85ED297C7DB68DC088D7A3AC0B44C45C33EDB500C6556C0F`) run at `762d22a` passed `demo1-vesa-full`, `demo2-entity-workload`, and `demo3-world-workload`, two repeats each. The source-tree fingerprint matched the seven-scene run. Color streams matched exactly for 964, 980, and 1,085 compared frames; every framebuffer and palette had zero differing pixels or bytes. Z-checksum streams matched exactly between profiles and across repeats at 970, 986, and 1,091 frames. C-reference and assembly builds both passed their source-bound and linked-image i486 gates: 218,760 and 319,035 relocated instructions, respectively, with 529 startup rows, 9,207 provider instructions, and zero above-i486, unknown, or exempt instructions. The report is `benchmarks/out/render-parity-z-20261117-091128/render-parity-result.json`; both builds used DOSBox-X and do not constitute physical-486 timing evidence.

**Completion evidence:** No unexplained selector/profile mismatches remain, the host gates pass, and the full parity evidence identifies the exact source revision and profile. See [`quake/ASM486-HANDOFF.md`](../quake/ASM486-HANDOFF.md), [`quake/tools/selectors.ps1`](../quake/tools/selectors.ps1), and [`quake/tools/test-build-dos.py`](../quake/tools/test-build-dos.py).

### Add direct host coverage and provenance for the ISO writer

- [x] Add synthetic-tree tests that parse generated ISO structures: volume descriptors, path tables in both byte orders, directory records, extent allocation, alignment, payload bytes, and empty directories.
- [x] Cover boundary-sized inputs, invalid names, duplicate names, and rejected links/reparse points.
- [x] Register the tests in `benchmarks/tools/run-tests.ps1` and retain boot validation as a separate integration check.
- [x] Extend the launcher sidecar with the benchmark-suite revision and selected game build-manifest/configuration identity.

**Completion evidence (2026-11-17):** `benchmarks/tools/run-tests.ps1 -HostOnly` passed 22/22 gates, including the three ISO structure tests and sidecar identity tests. The launcher built a 26,939-sector image from the current i486 release executable and local base-game PAKs; its version-2 sidecar matched the executable and build-manifest hashes and recorded the game and benchmark-suite revisions. The generated ISO is local output. DOS boot validation remains separate and was not part of this host-format change. See [`benchmarks/tools/build-iso9660.py`](../benchmarks/tools/build-iso9660.py), [`benchmarks/tools/build-launcher-iso.ps1`](../benchmarks/tools/build-launcher-iso.ps1), and [`benchmarks/README.md`](../benchmarks/README.md).

### Reduce global-state coupling incrementally

- [x] Identify one concrete cross-subsystem state flow that causes maintenance or testing friction; record its producer, consumers, and hot-path impact.
- [x] Introduce a narrow subsystem interface for that flow while preserving C/assembly symbol names, calling conventions, and structure layout contracts.
- [x] Compare generated i486 code and matched performance before expanding the pattern to more state.
- [x] Defer a full renderer context-object conversion unless a prototype demonstrates acceptable 486 code generation and measurable maintenance value.

**Completion evidence (2026-11-17):** `Host_Init` owns and loads `host_colormap`; the only
production consumers outside the host are `VGA_InitMode` and `VID_ExtraInitMode`, both during
video-mode initialization. The video test fixture also had to define the legacy host global.
`host_assets.h` now exposes `Host_GetColormap`, both video drivers use it, and the legacy
`host_colormap` symbol remains available. The accessor is not called in the frame-rendering path.

The strict i486 release build, renderer stack check, and linked ISA audit pass. Matched strict
i486 BENCH builds using the release selector schedule passed their ISA gates (319,474 baseline
instructions; 319,461 candidate instructions, with no above-i486 or unclassified instructions).
Eleven renderer/drawing object files were byte-identical; only the two video-driver objects
changed. A `+parityclock` demo1 replay produced identical 970-row frame-checksum streams, final
checksum `1047377823`, and event reports. Five uninstrumented DOSBox-X demo1 runs per build had
median times of 57.688425 s (baseline) and 57.688428 s (candidate), a 0.0000052% difference at the
reported precision. These are emulator-only results, not physical 486 measurements. Raw local
captures are under `benchmarks/out/dos-timedemo-20261117-133222/`,
`benchmarks/out/dos-timedemo-20261117-133355/`,
`benchmarks/out/dos-timedemo-20261117-133557/`, and
`benchmarks/out/dos-timedemo-20261117-134155/`.

The game host suite completed 15/17 gates; its sysinfo and video C tests could not run because
native `gcc` is unavailable on this host. The benchmark host suite passed 22/22. This interface
has not been expanded to other state, and a full renderer context-object conversion remains
deferred. See [`quake/docs/source-layout.md`](../quake/docs/source-layout.md) and
`quake/src/host_assets.h`.

## P3 — Demand-driven maintainability and optimization

### Preserve the assembly split and control selector growth

- [x] Split the monolithic `asm486_experiments.s` into subsystem-owned assembly units and a collision unit. The recorded split preserved 88 exported symbols without duplicate exports.
- [x] Keep one ordered selector table as the source for flags, profile suffixes, assembly inclusion, manifests, and inventory checks.
- [x] Review current ownership boundaries; avoid further broad source splitting unless ownership boundaries, review friction, or merge conflicts justify it.
- [x] Define and test a selector-addition gate requiring a documented parity, measurement, or historical-reproduction need plus test and build-identity coverage.
- [ ] Consider removing a selector only after confirming it is unused and no longer required for parity, measurements, or reproducible historical experiments.

**Completion evidence:** Source ownership stays subsystem-based; selector behavior remains represented once; each supported profile retains symbol/ABI, ISA, build identity, release pin, and C-oracle coverage. The recorded split evidence and the former selector-test mismatch set are detailed in the assessment.

**Review update (2026-11-17):** The current work added no assembly source split and no selector. The profile build used the committed i486 release selector schedule; selector growth or removal was not needed to complete the current-source measurement. No further split or selector change is proposed from this review.

**Current layout review (2026-11-17, game revision `644fb3a`):** `test-source-layout.py` passes with 182 production units, 109 BENCH fixtures, and 402 mapped files. `test-header-dependencies.py` passes with 83 production C files and no explicit `quakedef.h` umbrella users. The latest host/video boundary change adds a narrow colormap accessor without moving unrelated sources. These ownership checks and the reviewed recent diff do not show a boundary, repeated conflict, or review-friction case that justifies another broad split.

**Selector-addition gate (2026-11-17, game commit `05641e2`):** [`quake/docs/SELECTOR-CHANGE-CHECKLIST.md`](../quake/docs/SELECTOR-CHANGE-CHECKLIST.md) now requires a recorded parity, measurement, or historical-reproduction need, updates to the ordered selector table, profile, matrix tests and build identity, and the applicable parity/ISA gates. `BUILD-DOS.md` and the selector table point to this review. `test-build-fingerprints.ps1` now explicitly proves that changing the resolved profile suffix changes the artifact identity. The fingerprint, build-number, profile-completeness and document-structure checks passed; `test-build-dos.py` passed all 138 selector cases at game revision `644fb3a` before this documentation/test-only commit, with the selector table unchanged.

### Keep BENCH486 test ownership focused

- [x] Move the BENCH486 harness out of `quake/src/core/host_cmd.c` into `quake/src/tests/bench486/bench486_harness.c`.
- [x] Review whether another harness split is justified; split only if unrelated fixtures cause repeated conflicts, dependency leakage, or review difficulty.

**Review update (2026-11-17):** The current `quake/src/tests/bench486` organization already separates 109 fixture headers/hooks from the central harness. The harness is large, but the conditional triggers for another split—repeated conflicts, dependency leakage, or review difficulty—were not found in the current ownership checks or recent file history. No split was justified by this pass; command strings, reports, checksums, and fixture ABI were left unchanged.

Any future split should use cohesive test-owned interfaces and preserve command strings, report formats, checksums, and fixture ABI.

### Refresh performance evidence before optimizing

- [x] Capture broad profile attribution and uninstrumented matched timings from the current source revision before selecting the next optimization target.
- [x] Prioritize measured surface, texture, Z/cache, and model work; avoid specializing paths with small observed populations without a full workload win.
- [ ] Require exact color/Z or framebuffer parity, a strict i486 ISA pass, and repeated matched uninstrumented runs for each candidate.
- [x] Report DOSBox-X and physical-hardware measurements as separate evidence.

**Completion evidence (2026-11-17):** [`current-source-engine-profile-2026-11-17.md`](current-source-engine-profile-2026-11-17.md) records source/build/profile identity, workload matrix, final checksum parity, instrumentation modes, the single sample and lack of a spread estimate, and the DOSBox-X environment. The measured texture-span and surface/cache/Z populations make that shared path the next area to investigate; no candidate optimization was changed. Per-candidate parity and repeated timing gates remain mandatory before accepting an optimization.

## Completed supporting work

- [x] Document the 320x200 memory budget and expose engine, video, renderer, warp, and DPMI stack figures through `meminfo`.
- [x] Cross-check generated renderer stack frames against formulas parsed from preprocessed runtime C.
- [x] Normalize generated build identity in the release hash guard and register `test-i486-release-guard.py` in the game host-gate inventory.

The opening sections record the assessment snapshot. Dated follow-up evidence in this checklist and the linked report records later builds, tests, emulator runs, and hardware limits; unchecked items still require the evidence specified by their acceptance criteria.
