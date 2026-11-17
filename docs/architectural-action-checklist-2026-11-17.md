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

### Maintain the renderer stack model as a build invariant

- [x] For changes to renderer entry points, BSP traversal, polygon clipping, or profiling callbacks, update the call-path ledger and generated/runtime formula checks together.
- [x] Keep generated-frame and preprocessed-runtime formula checks enabled for release, C-reference, and PROFILE486 configurations.
- [x] Preserve the runtime guard that rejects an insufficient normal render stack and disables waterwarp when only fallback capacity is insufficient.
- [x] Treat reduced-stack DOSBox runs as emulator regression evidence; qualify DPMI stack margin separately on hardware.

**Completion evidence (2026-11-17):** Fresh i486 release, C-reference, and PROFILE486 builds passed generated-frame and runtime-formula checks. Their linked ISA gates passed with 166,300, 176,959, and 326,951 instructions, respectively, and zero above-i486, unknown, or exempt instructions. Existing 192 KiB/160 KiB reduced-stack runs and warp fallback parity are DOSBox-X/CWSDPMI regression evidence only; physical DPMI stack margin remains open under the hardware qualification item. Exact commands and source/build identities are recorded in [`quake/docs/renderer-assembly/warp-scratch.md`](../quake/docs/renderer-assembly/warp-scratch.md).

## P2 — Configuration, memory, and release confidence

### Explain the low-memory map-load boundary

- [ ] Instrument map loading to identify the exact allocation request or resource pool that prevents `POSTMAP` completion.
- [ ] Repeat controlled base-game and registered-data runs with the same build, map, and DPMI setup; preserve console/error logs and `meminfo` output.
- [ ] Record startup minimum separately from map-specific capacity. Do not generalize the observed e1m1 transition (7,241,728 bytes fails before `POSTMAP`; 7,258,112 bytes completes) to other hosts or maps.

**Completion evidence:** Failure and success runs identify the limiting allocation/pool and state their build, map, and DPMI conditions. See [`quake/docs/memory-budget.md`](../quake/docs/memory-budget.md).

### Reconcile selector/profile expectation mismatches

- [x] Triage each of the 29 reported `test-build-dos.py` selector/profile mismatches against the selector table, resolved flags, manifests, and actual source inventories.
- [x] Correct stale expectations or implementation defects based on evidence. Do not suppress or bulk-update mismatches without classifying them.
- [ ] Run the game host checks after the corrections; ensure release and C-reference inventories agree with their declared profiles.
- [ ] Run the full documented multi-scene parity suite after selector expectations are clean; retain exact framebuffer/palette and color/Z evidence.
- [ ] Reconfirm source-bound and linked-image i486 ISA gates and release artifact identity after any selector or assembly-source change.

**Triage progress (2026-11-17):** `tools/test-build-dos.py` now passes after updating i486/i386 flag goldens from current `DumpFlags` output and correcting selector probes that omitted dependencies, varied sibling selectors, or removed the wrong occurrence of a shared profile token. The full `tools/run-tests.ps1 -HostOnly` run passed 15/17 gates; `test-sysinfo-dos.py` has a stale source-slice assertion and `test-video-dos.py` could not start without a host `gcc`. The multi-scene parity run is still pending, so the selector/profile item remains open.

**Completion evidence:** No unexplained selector/profile mismatches remain, the host gates pass, and the full parity evidence identifies the exact source revision and profile. See [`quake/ASM486-HANDOFF.md`](../quake/ASM486-HANDOFF.md), [`quake/tools/selectors.ps1`](../quake/tools/selectors.ps1), and [`quake/tools/test-build-dos.py`](../quake/tools/test-build-dos.py).

### Add direct host coverage and provenance for the ISO writer

- [x] Add synthetic-tree tests that parse generated ISO structures: volume descriptors, path tables in both byte orders, directory records, extent allocation, alignment, payload bytes, and empty directories.
- [x] Cover boundary-sized inputs, invalid names, duplicate names, and rejected links/reparse points.
- [x] Register the tests in `benchmarks/tools/run-tests.ps1` and retain boot validation as a separate integration check.
- [x] Extend the launcher sidecar with the benchmark-suite revision and selected game build-manifest/configuration identity.

**Completion evidence (2026-11-17):** `benchmarks/tools/run-tests.ps1 -HostOnly` passed 22/22 gates, including the three ISO structure tests and sidecar identity tests. The launcher built a 26,939-sector image from the current i486 release executable and local base-game PAKs; its version-2 sidecar matched the executable and build-manifest hashes and recorded the game and benchmark-suite revisions. The generated ISO is local output. DOS boot validation remains separate and was not part of this host-format change. See [`benchmarks/tools/build-iso9660.py`](../benchmarks/tools/build-iso9660.py), [`benchmarks/tools/build-launcher-iso.ps1`](../benchmarks/tools/build-launcher-iso.ps1), and [`benchmarks/README.md`](../benchmarks/README.md).

### Reduce global-state coupling incrementally

- [ ] Identify one concrete cross-subsystem state flow that causes maintenance or testing friction; record its producer, consumers, and hot-path impact.
- [ ] Introduce a narrow subsystem interface for that flow while preserving C/assembly symbol names, calling conventions, and structure layout contracts.
- [ ] Compare generated i486 code and matched performance before expanding the pattern to more state.
- [ ] Defer a full renderer context-object conversion unless a prototype demonstrates acceptable 486 code generation and measurable maintenance value.

**Completion evidence:** The chosen state boundary has a focused interface, documented ownership, unchanged parity, and acceptable release-profile code generation. See [`quake/docs/source-layout.md`](../quake/docs/source-layout.md) and the subsystem headers under `quake/src/`.

## P3 — Demand-driven maintainability and optimization

### Preserve the assembly split and control selector growth

- [x] Split the monolithic `asm486_experiments.s` into subsystem-owned assembly units and a collision unit. The recorded split preserved 88 exported symbols without duplicate exports.
- [x] Keep one ordered selector table as the source for flags, profile suffixes, assembly inclusion, manifests, and inventory checks.
- [ ] Avoid further broad source splitting unless ownership boundaries, review friction, or merge conflicts justify it.
- [ ] Before adding a selector, document its parity, measurement, or historical-reproduction need and update its tests and build identity contracts.
- [ ] Consider removing a selector only after confirming it is unused and no longer required for parity, measurements, or reproducible historical experiments.

**Completion evidence:** Source ownership stays subsystem-based; selector behavior remains represented once; each supported profile retains symbol/ABI, ISA, build identity, release pin, and C-oracle coverage. The recorded split evidence and the former selector-test mismatch set are detailed in the assessment.

### Keep BENCH486 test ownership focused

- [x] Move the BENCH486 harness out of `quake/src/core/host_cmd.c` into `quake/src/tests/bench486/bench486_harness.c`.
- [ ] Split the remaining large test harness only if unrelated fixtures cause repeated conflicts, dependency leakage, or review difficulty.
- [ ] If split, use cohesive test-owned interfaces and preserve command strings, report formats, checksums, and fixture ABI.

### Refresh performance evidence before optimizing

- [ ] Capture broad profile attribution and uninstrumented matched timings from the current source revision before selecting the next optimization target.
- [ ] Prioritize measured surface, texture, Z/cache, and model work; avoid specializing paths with small observed populations without a full workload win.
- [ ] Require exact color/Z or framebuffer parity, a strict i486 ISA pass, and repeated matched uninstrumented runs for each candidate.
- [ ] Report DOSBox-X and physical-hardware measurements as separate evidence.

**Completion evidence:** The performance report names source/build/profile identity, workload, parity result, instrumentation mode, repetitions, spread, and hardware/emulator environment.

## Completed supporting work

- [x] Document the 320x200 memory budget and expose engine, video, renderer, warp, and DPMI stack figures through `meminfo`.
- [x] Cross-check generated renderer stack frames against formulas parsed from preprocessed runtime C.
- [x] Normalize generated build identity in the release hash guard and register `test-i486-release-guard.py` in the game host-gate inventory.

These checked items describe source and documentation state at the snapshot above. Their host tests and runtime behavior still require the verification appropriate to each open item; this checklist preparation did not run builds, tests, DOSBox scenarios, or hardware checks.
