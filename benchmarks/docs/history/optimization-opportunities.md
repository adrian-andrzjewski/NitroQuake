# Remaining optimization opportunities

## Earlier profile and renderer promotions (2026-11-11)

The pre-C-default source revision `68d05e4` was profiled at VGA 320x200 on the
pinned DOSBox-X 486 configuration, with the then-default assembly BSP walk.
The lower-overhead `demo1` parts pass completed 969 frames at 15.170257
instrumented FPS and ranked these components:

| Component | Profiled self time | Share |
| --- | ---: | ---: |
| Texture spans | 17.650799 s | 27.65% |
| World BSP | 8.042513 s | 12.60% |
| Alias rasterization | 7.830096 s | 12.27% |
| Z spans | 7.126712 s | 11.16% |
| Edge scan | 6.196171 s | 9.71% |
| Surface cache | 5.923291 s | 9.28% |

These are instrumented attributions, not release timing shares. The capture is
[`engine-profile-demo1-currentparts-after-clipdot-20261111.json`](../out/engine-profile-demo1-currentparts-after-clipdot-20261111.json).
The detailed capture for the preceding source revision `23672ac` counted
789,805 `R_ClipEdge` calls and 1,479,208 plane tests; its counts ranked repeated
work but are not timing evidence. See
[`engine-profile-demo1-currentdetailed-20261111.json`](../out/engine-profile-demo1-currentdetailed-20261111.json).

The `R_ClipEdge` endpoint-at-a-time x87 schedule removed five `FXCH`
instructions per plane-test pair while preserving the left-associative dot
products and exact output. Three alternating uninstrumented `demo1` pairs
improved mean FPS from 16.823771 to 16.888323 (+0.383695%); all 970 color and Z
records and the captured frame 482 PCX matched, and the complete strict i486
gate passed. See the [promotion ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-11-r-clipedge-dot-product-stack-reschedule-promoted.md).

The C BSP walk is now the i486 default after three alternating pairs measured
it +0.024255% faster than assembly, with exact 970-record color/Z and frame 482
PCX parity and complete strict i486 gates. Assembly remains explicitly
selectable. See the [BSP-walk ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-11-bsp-walk-c-default-promoted.md).
These results are DOSBox-X measurements, not physical-486 performance claims.

## Current default-C parts and detailed profile (2026-11-11)

After the C BSP walk became the default and mip-0 horizontal-flat rows were
unrolled eight at a time, Build 871 profiled the checked-in game source at VGA
320x200 using the pinned DOSBox-X 486 configuration. The source-tree fingerprint
is `7921548FCDB5F5B1215C691BE8DF0939FC1A55DB151049C946AB44F8953C60C2`. Both
passes completed 969 frames. The parts pass took 63.829079 seconds at 15.181169
instrumented FPS; the detailed pass took 84.707108 seconds at 11.439418
instrumented FPS. Instrumented FPS is not release timing evidence. The complete
strict i486 audit passed.

The parts timer-read floor was 5.779 microseconds per read. The table subtracts
`instr_reads * 5.779 us` from each node's exclusive self time, then divides by
the sum of corrected exclusive self times (61.371039 seconds):

| Component | Corrected self time | Corrected share |
| --- | ---: | ---: |
| Texture spans | 17.336627 s | 28.249% |
| World BSP | 8.002589 s | 13.040% |
| Alias rasterization | 7.807875 s | 12.722% |
| Z spans | 6.796941 s | 11.075% |
| Edge scan | 6.176247 s | 10.064% |
| Surface cache | 5.607413 s | 9.137% |

The parts capture is
[`engine-profile-currentparts-after-surf8-unroll8-20261111.json`](../out/engine-profile-currentparts-after-surf8-unroll8-20261111.json);
the detailed capture is
[`engine-profile-currentdetailed-after-surf8-unroll8-20261111.json`](../out/engine-profile-currentdetailed-after-surf8-unroll8-20261111.json).
Detailed counters record 3,512,959 texture segments and 43,955,018 texture
pixels, with zero unit-stride pixels; 3,846 alias models and 281,663 alias
vertices; and 46,005 surface-cache hits, 8,354 rebuilds, and zero thrash
frames. The mip-0 horizontal-flat path ran 6,607 blocks, including 4,753 fully
flat blocks. These are DOSBox-X profile attributions for one scene, not
physical-486 timing shares or general gameplay estimates.

## Mip-0 horizontal-flat rows fully unrolled (2026-11-12)

The assembly block now emits all sixteen rows straight-line, removing the
two-iteration counter loop from the eight-row version. Three alternating
uninstrumented demo1 pairs improved mean FPS from 16.940373 to 16.940452
(+0.0004656%); every candidate sample beat its matched control. Demo1 and demo3
color and Z streams matched exactly, as did the frame-169 PCX captures, and
the strict release and qbench i486 gates passed. The measured gain is small
and comes from DOSBox-X, not physical-486 timing. See the
[promotion ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-12-surf8-mip0-horizontal-flat-unroll16-promoted.md)
for each timing sample, checksum hash, and artifact path. The earlier
[eight-row promotion](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-11-surf8-mip0-horizontal-flat-unroll8-promoted.md)
remains in the ledger as the preceding step.

## Current-source refresh (2026-11-10)

A fresh one-repetition `demo1` profile was collected from the current game tree
(`2a2448a`) and benchmark suite (`741beef`) at VGA 320x200 under DOSBox-X
2026.08.31, `cputype=486`, fixed 33,445 cycles, FPU 387, and the verified
`testdata/id1` PAKs. The game source-tree fingerprint is
`5555126FDDD71C350EB9ED7AA077042C8EA9E12610EDAC91EB9E8A39289666A5`. The full
session and captured artifacts are retained under
[`out/engine-profile-current-20261110/`](../out/engine-profile-current-20261110/).
The `session.json` SHA-256 is
`4502233F44781DE9F8730464BDC1F089BBAEFA9D61E0EDC78E3796221933C315`.

All four runs completed 969 frames and ended with framebuffer checksum
`1047377823`. The uninstrumented control was one sample at 16.951799 FPS
(57.162076 seconds); it is not a new baseline or a performance comparison.
The coarse, parts, and detailed runs measured 15.867923, 15.117910, and
11.401184 FPS respectively. Their lower rates show the profile overhead and
must not be compared with release timing.

The lower-overhead `parts` capture ranks these demo1 components:

| Component | Corrected share |
| --- | ---: |
| Texture spans | 28.13% |
| World BSP and face work | 13.39% |
| Alias rasterization | 12.67% |
| Z spans | 11.03% |
| Edge scan | 10.03% |
| Surface cache | 9.10% |

These are exclusive profiled shares from one capture, not uninstrumented cycle
fractions or confidence intervals. The detailed capture records 3,512,959
texture segments and 43,955,018 texture pixels. It again finds zero unit-stride
pixels; surface-cache counters report 46,005 hits, 8,354 rebuilds, and no cache
thrash. The profile does not split each Span16 segment's setup from its pixel
body, so that attribution remains open.

## Demo2 underwater warp pixel loop promoted (2026-11-10)

The measured `demo2` profile attributed 1.877079 seconds (3.13%) to 210
underwater warp calls. An eight-pixel assembly copy loop with a leading
four-pixel odd tail preserved store order and exact rendering output. Three
alternating uninstrumented pairs averaged 17.185951 FPS for control and
17.241270 FPS for the candidate (+0.321885%). The full strict i486 audit passed.
These DOSBox-X timings apply to this workload and do not establish physical-486
performance. The complete parity, audit, timing, and provenance record is in
the [promotion ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-10-underwater-warp-pixel-unroll8-promoted.md).

## Span16 decisions that remain closed

The latest profile still ranks texture spans first, but several obvious
specializations have already failed or lacked the required premise. The current
profile records zero unit-stride pixels. A power-of-two width shift was 0.688%
slower, the signed row-scale table was 0.430% slower, and the no-row-cross path
was 0.585% slower in their recorded 320x200 checks. See the [power-of-two
multiply result](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-10-29-span16-pow2-cachewidth-multiply-screen-rejected.md),
[row-scale table result](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-02-span16-row-scale-table-unqualified.md),
[no-row-cross result](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-10-29-span16-norowcross-current-recheck-rejected.md),
and the [unit-stride census](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-10-02-surf8-bundle-and-promotion.md).
Do not revive these exact paths. Any further texture-span change needs a
different algorithm that reduces required work while preserving exact output.

Use the corrected default-C profile above when selecting the next target. Any
further texture-span change needs a different algorithm that reduces required
work. Keep exact image/depth parity, the complete i486 ISA gate, and repeated
matched uninstrumented timings as promotion requirements. DOSBox-X timing
remains emulator evidence, not a physical-486 measurement.
