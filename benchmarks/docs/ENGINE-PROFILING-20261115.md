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

## Next candidate investigation

The e1m2 `Models / sprites` share is 16.64%, versus 10.05% in e1m1; the
detailed e1m2 capture counted 490 alias models and 42,967 alias vertices over
256 frames. This makes alias-model raster work the next renderer investigation:
measure triangle, rejected-area and covered-pixel populations before proposing
any code change. The present profile shows cost, but not a safe condition that
removes work. For local gameplay, the server remains 16.5-17.6% of the measured
component share; function-level QuakeC/collision attribution is a separate
follow-up if the workload expands beyond timedemos.

This report is emulator evidence only. Physical qualification remains pending;
follow the [physical 486 acceptance procedure](PHYSICAL-486-ACCEPTANCE.md) when a
real test machine is available.
