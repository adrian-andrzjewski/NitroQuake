# Current release-profile attribution (2026-11-15)

## Scope and provenance

This refresh profiles the source tree at `b65ff69116b555f44803d44366a1b80581b11e20`
(`E2F30E6F7E2AC23FA5358646281E12A4CD82AF05A3952E95CBF75839E023B0D8`). Both
benchmark builds loaded the committed `i486-asm-selectable-current` selectors
from `quake/tools/renderer-profiles/i486-asm-selectable-current.json`
(`CCF865D39DB35A93B66571A65E3E1555B2EB5E4350FE35D593BCB8E517FF4759`). The
full-span and tail exact-zero-T paths were both `zerot` in both builds.

The uninstrumented i486 `qbench.exe` SHA-256 is
`1611F2C8AFBD3D2FAAD6DFD191484C343706428183CE04D5ED92F1839ACEAF89`; the
instrumented `qprof.exe` SHA-256 is
`81E8DFA3E4B2EC638503EB34C999D7DD5BBC5D25B838F3AB6E55BD0AD93E955A`. Both
builds passed the strict linked i486 ISA gate with zero above-i486 instructions.
The current renderer stack-frame budget also passed for both builds.

The 20-job serial session used DOSBox-X 2026.08.31 (`cputype=486`, 387 FPU,
33,445 fixed cycles, dynamic core; profile SHA-256
`53D9CFC80AB2B59DB607EDFE2BF1A5DC2E416BD9BF316E6D7303C0F3D7D1759C`; DOSBox-X
executable SHA-256
`F17F47DFD6DA895747ACFC70A533077D0B4C55B3A8B79551A04750E2A51B8D34`). It used
the maintained CWSDPMI provider and the same staged PAK hashes in every run.
The complete session, logs, manifests and analysis are retained locally under
`benchmarks/out/engine-profile-current-release-20261114-r2/`.

Captures covered `demo1`, plus 256-frame e1m1/e1m2 local-game runs after 64
warm-up frames, with sound both off and on. All five workload/device groups
passed final framebuffer checksum comparison across control, coarse, parts and
detailed modes. Instrumentation elapsed overhead versus control was:

| Workload | Coarse | Parts | Detailed |
| --- | ---: | ---: | ---: |
| demo1, sound off | 7.00% | 12.21% | 48.51% |
| e1m1, sound off | 6.57% | 13.34% | 42.92% |
| e1m1, sound on | 6.58% | 13.31% | 42.75% |
| e1m2, sound off | 7.17% | 13.32% | 49.83% |
| e1m2, sound on | 7.11% | 13.17% | 49.21% |

These are one-run instrumentation checks, not candidate timing results. Profile
elapsed time is not used for optimization claims.

## Current cost ranking

The corrected parts-mode shares for the sound-off local captures were:

| Scope | e1m1 | e1m2 |
| --- | ---: | ---: |
| Surface, texture, Z and cache | 50.00% | 44.44% |
| Local server | 17.55% | 16.98% |
| Models and sprites | 10.05% | 16.64% |
| World BSP and faces | 9.48% | 9.96% |
| Edges and dispatch | 8.05% | 6.81% |

These are DOSBox attribution shares for the captured workloads. They do not
describe physical 486 cycles or cache behavior.

The detailed counters confirm that the promoted texture-span fast paths already
cover the largest observed zero-T populations:

| Counter | e1m1 | e1m2 |
| --- | ---: | ---: |
| Texture spans | 229,739 | 223,149 |
| Texture pixels | 12,140,544 | 12,022,213 |
| Texture segments | 883,165 | 872,677 |
| Full segments with zero T delta | 482,008 (54.6%) | 400,332 (45.9%) |
| Zero-T tail samples | 642,567 | 648,659 |
| Adjacent same-row links | 2,514 (1.09% of spans) | 908 (0.41% of spans) |

The release build already selects the exact-zero-T full and tail paths. The
same-row population is too small to justify another texture-span specialization
from this evidence. No new source optimization is promoted from this pass.

## Alias raster work census

To quantify the alias workload, a PROFILE486-only counter in
`quake/src/renderer/d_polyse.c` mirrors the span drawer's right-edge stepping
before entering the timed draw scope. It records nonempty rows in
`work_items` and candidate pixel samples in `work_bytes`; it does not change
the renderer's span state or the non-instrumented release build. These samples
are submitted to the Z test, so the count is not the number of visible pixels
that pass depth testing.

Two 256-frame detailed captures used the committed i486 release selectors,
the same staged PAK files and DOSBox-X setup described above. The instrumented
executable SHA-256 was
`87AEFC279D63064C43227B071EE204E85344C562EC19AC62D3C348713C1DE985`; its
source fingerprint was
`FE30EAC15C5F43FB22FE5C83CA61C4243B1FDF50EB45C34720381B7EBF22563C`, and
source-tree fingerprint was
`C8638B0E0C06AD0DA267BBEB881BF39E318AF4962EB305803A0B2AF8D2D8D395`. Both
captures matched their earlier detailed runs exactly:

| Workload | Simulation checksum | Framebuffer checksum |
| --- | ---: | ---: |
| e1m1 | 2,568,184,557 | 1,299,435,123 |
| e1m2 | 1,496,920,581 | 1,246,513,233 |

The result JSONs are retained locally under
`benchmarks/out/alias-pixel-census-e1m2-20261115-v1/`.

| Population over 256 frames | e1m1 | e1m2 | e1m2 / e1m1 |
| --- | ---: | ---: | ---: |
| Alias models | 256 | 490 | 1.91x |
| Alias vertices | 19,118 | 42,967 | 2.25x |
| Alias span-drawer calls | 10,748 | 25,486 | 2.37x |
| Nonempty alias span rows | 124,720 | 187,656 | 1.50x |
| Candidate alias pixels submitted to Z | 602,150 | 1,046,870 | 1.74x |

The existing alias-occlusion counters reported 20 queries, 20 culls and 11,184
Z samples for e1m1, and 436 queries, 202 culls and 105,064 Z samples for e1m2.
They describe the occlusion probe's tests, not triangle-area rejection. The
captures were diagnostic and instrumented; their elapsed times are not
candidate timings.

## Next candidate investigation

The e1m2 `Models / sprites` share is 16.64%, versus 10.05% in e1m1. It also
submits 1.74x as many alias pixels and 2.37x as many spans, but the counters
show work volume rather than a conservative rejection condition. Earlier
triangle-prefilter and alias-occlusion attempts in the ledger were rejected
for slower matched runs or exact color/Z divergence. No new alias optimization
is selected from this census. A future candidate needs a safe per-triangle or
per-tile rejection population and exact color/Z parity before timing.

For local gameplay, the server remains 16.5-17.6% of the measured component
share; function-level QuakeC/collision attribution is a separate follow-up if
the workload expands beyond timedemos.

This report is emulator evidence only. Physical qualification remains pending;
follow the [physical 486 acceptance procedure](PHYSICAL-486-ACCEPTANCE.md) when a
real test machine is available.

## Current-source exact-zero-T screen

A fresh uninstrumented `BENCH486` A/B screen used the source at Quake commit
`b017ffb7f50f69160a58194ade457c322e389586` and the committed
`i486-asm-selectable-current` renderer profile (SHA-256
`CCF865D39DB35A93B66571A65E3E1555B2EB5E4350FE35D593BCB8E517FF4759`). The
control overrode `TextureSpanTZeroPath` and `TextureSpanTailTZeroPath` to
`control`; the candidate used `zerot` for both. The remaining selectors and
build inputs were loaded from the same release profile. The source-tree
fingerprint matched (`C8638B0E0C06AD0DA267BBEB881BF39E318AF4962EB305803A0B2AF8D2D8D395`);
the configuration-bound build fingerprints were
`A89579414EC23FC444C511DA1BBB1E96014D69313AE90E4AF992EB107283EE9E` for
control and `B557210FF7948F26ED950189937DD22966C56B79CDBE270EDC9B37012473AF45`
for candidate.

Both executables passed the strict linked i486 ISA gate with zero above-i486
instructions and zero exemptions. Both builds also passed the generated
renderer stack budget check: normal rendering requires `172864 + 128 *
world_depth` bytes. The control executable SHA-256 is
`0117A1F6DE0CE9A1088035F4732B13A33C45BFFC66E0F1E47F0409A901C06296`; the
candidate executable SHA-256 is
`619DB6E149A5D7978296E3F38702C8CA0E9D28D200FF400156EA4FF3F3DD3D62`.

Correctness used DOSBox-X 2026.08.31 (executable SHA-256
`F17F47DFD6DA895747ACFC70A533077D0B4C55B3A8B79551A04750E2A51B8D34`), the
pinned 486 profile (SHA-256
`532284EA01C1A93C8B96D70FB538625B694DFAD0172BA13B9BA9C36C8FE845BA`) and
CWSDPMI (SHA-256
`FF3501B50BCF320E6615E025BDFF94261A087F83212858D4B12E42C19C7E3883`). One
fixed-clock `demo1` replay per executable recorded all 970 checksum entries
(initial frame plus 969 timedemo frames), with zero overflow. Final framebuffer
checksums were `1047377823`. The complete per-frame color and Z files matched
byte for byte:

| Stream | Bytes | SHA-256 |
| --- | ---: | --- |
| Color | 14,154 | `C1C6DF62FA795D62D958FEC9F1B7F0811CB92B35E0C14D32BA45CEEFD9DF919B` |
| Z buffer | 14,182 | `4D995848BEF742F2E2B8362A978F21AB3F4A4885ACB95794DAC512964135FD37` |

Three uninstrumented timing runs per build completed 969 frames and returned
the same final framebuffer checksum in every run:

| Selector values (full / tail) | Seconds (runs 1, 2, 3) | FPS (runs 1, 2, 3) | Median FPS |
| --- | --- | --- | ---: |
| `control / control` | 57.240511, 57.240421, 57.240417 | 16.928570, 16.928597, 16.928598 | 16.928597 |
| `zerot / zerot` | 57.686949, 57.686941, 57.686980 | 16.797560, 16.797563, 16.797551 | 16.797560 |

The candidate was 0.77% slower by median FPS in this DOSBox screen. All control
runs preceded all candidate runs, so this was not an alternating paired test;
the small difference is not sufficient to change the release profile. These
results screen correctness and emulator timing only. Physical 486 qualification
remains pending, and the hardware acceptance procedure's three-demo,
five-pair alternating timing gate has not been met. Local JSON results and raw
checksum streams remain under the ignored `benchmarks/out/` directory.
