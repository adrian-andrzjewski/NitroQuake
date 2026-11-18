# Current-source engine profile — 2026-11-17

This capture refreshes whole-engine attribution before selecting the next optimization target. It is DOSBox-X elapsed-time evidence, not a measurement of physical 486 cycles or a claim about physical-hardware performance.

## Provenance

- Game source revision: `ae559389c9d400baac3fabbc42a3424382e7650d`.
- Source-tree SHA-256: `62E839885135C33C074624F6B52901D88AB2D63BEC881489CA8C9DE116532453`.
- Release-selector profile: `i486-asm-selectable-current`, SHA-256 `CCF865D39DB35A93B66571A65E3E1555B2EB5E4350FE35D593BCB8E517FF4759`.
- Uninstrumented i486 BENCH control: build ID `ae559389c9d4-74217eb445f3`, executable SHA-256 `13ECEE6DDF81CF5A3966CC699DAB110CFC241686EF523189211E03C234B3C2E8`.
- Instrumented PROFILE486 build: build ID `ae559389c9d4-ed7941efa85b`, executable SHA-256 `545BF4B4E9C1DAADE1671BFD7782C53A0872AA4440A61C4ECDE5C10EBCBA217C`.
- Both builds used the same source-tree fingerprint and passed their build-manifest freshness and ISA checks. The PROFILE486 linked audit verified 327,390 relocated instructions, with zero above-i486, unknown, or exempt instructions; startup and CWSDPMI provider proofs also passed.
- Emulator: pinned DOSBox-X 2026.08.31, executable SHA-256 `F17F47DFD6DA895747ACFC70A533077D0B4C55B3A8B79551A04750E2A51B8D34`, i486 profile SHA-256 `53D9CFC80AB2B59DB607EDFE2BF1A5DC2E416BD9BF316E6D7303C0F3D7D1759C`, VGA 320×200. The staged CWSDPMI executable SHA-256 was `FF3501B50BCF320E6615E025BDFF94261A087F83212858D4B12E42C19C7E3883`.
- Base-game inputs: `pak0.pak` SHA-256 `35A9C55E5E5A284A159AD2A62E0E8DEF23D829561FE2F54EB402DBC0A9A946AF`; `pak1.pak` SHA-256 `94E355836EC42BC464E4CBE794CFB7B5163C6EFA1BCC575622BB36475BF1CF30`.

## Method and integrity

The completed session contains 20 captures across five workload/device groups: demo1 with sound disabled, and e1m1/e1m2 with sound disabled and enabled. Each group has one uninstrumented control, coarse profile, component profile, and detailed profile. Demo1 measured 969 frames. Local maps measured 256 frames after the documented 64-frame warm-up. The collection took 840.6 seconds.

Final framebuffer checksums matched across the four modes in every group. Local-map simulation checksums also matched across modes and sound configurations. This verifies final-state consistency for these runs; it is not a per-frame color/Z comparison between C-reference and assembly candidates. There was one uninstrumented timing sample per group, so the session has no timing spread and does not establish repeatability.

The raw session, logs, build manifests, and per-run JSON are retained locally in the ignored directory `benchmarks/out/engine-profile-current-release-20261117/`. The analyzer generated `analysis.json`, `ranked-scopes.csv`, and whole-engine/component plots there. Collection and analysis used [`ENGINE-PROFILING.md`](../ENGINE-PROFILING.md).

## Uninstrumented controls and final checksums

| Workload | Sound | Frames | Seconds | FPS | Framebuffer checksum | Simulation checksum |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| demo1 | off | 969 | 57.252863 | 16.924918 | `1047377823` | — |
| e1m1 | off | 256 | 10.407477 | 24.597699 | `1299435123` | `2568184557` |
| e1m1 | on | 256 | 10.603304 | 24.143419 | `1299435123` | `2568184557` |
| e1m2 | off | 256 | 11.283889 | 22.687214 | `1246513233` | `1496920581` |
| e1m2 | on | 256 | 11.640417 | 21.992340 | `1246513233` | `1496920581` |

Observed instrumentation overhead relative to the single uninstrumented control was:

| Workload / device | Coarse | Components | Detailed |
| --- | ---: | ---: | ---: |
| demo1, sound off | 8.00% | 13.21% | 49.57% |
| e1m1, sound off | 7.31% | 14.07% | 43.69% |
| e1m1, sound on | 7.31% | 14.04% | 43.50% |
| e1m2, sound off | 8.29% | 14.44% | 51.01% |
| e1m2, sound on | 8.23% | 14.29% | 50.39% |

These percentages include instrumentation bookkeeping, code layout, and possible timer-driven DMA effects. Detailed profiles are especially observer-heavy; they rank work populations but do not provide release timing.

## Measured work populations

Timer-read-corrected exclusive component profiles put the combined surface, texture, Z, and cache work at 34.25 ms/frame in demo1 and 21.86 and 21.19 ms/frame in e1m1 and e1m2. The same component captures measured models/sprites at 11.12 ms/frame in demo1 and 4.69 and 8.43 ms/frame in the maps. These are instrumented attribution values, not additive inclusive times or achieved savings.

The detailed sound-off captures ranked these scopes highest:

| Workload | Top corrected exclusive scopes (ms/frame) |
| --- | --- |
| demo1 | texture spans 19.670; renderface 13.048; Z spans 6.995; surface cache 6.985; edge scan 6.398 |
| e1m1 | texture spans 16.243; renderface 5.561; surface cache 3.996; edge scan 3.514; Z spans 2.953 |
| e1m2 | texture spans 16.311; renderface 7.640; edge scan 3.244; surface cache 2.930; QuakeC 2.762 |

Texture-span scopes ran 54,359 times in the 969-frame demo1 capture, 10,301 times in the 256-frame e1m1 capture, and 8,959 times in the 256-frame e1m2 capture. The shared texture-span/surface-cache/Z path is therefore the best-supported next area to investigate; model work is also measurable. No optimization candidate was changed or accepted by this profiling task. Any candidate still needs exact parity, a strict i486 audit, and repeated matched uninstrumented runs.

Sound-on and sound-off local-map final checksums matched, but the elapsed times differ. The profiling workflow uses real timer-driven DMA, so those device timings are not treated as otherwise-identical CPU work. Physical 486/DPMI qualification remains separate and was not available for this capture.
