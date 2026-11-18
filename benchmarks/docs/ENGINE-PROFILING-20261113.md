# Whole-engine profile findings (2026-11-13)

## Measurement scope

Profiles and uninstrumented controls cover the profiled 320x200 i486 DOS source
tree (`B2E82FFFA773C6BE8FFBBE6212692034C5A22582BEF0F87434DB29CEF4414EAD`)
under DOSBox-X 2026.08.31 (`cputype=486`, FPU 387, fixed 33,445 cycles,
dynamic core; profile SHA-256
`53D9CFC80AB2B59DB607EDFE2BF1A5DC2E416BD9BF316E6D7303C0F3D7D1759C`). The
DOSBox-X executable SHA-256 is
`F17F47DFD6DA895747ACFC70A533077D0B4C55B3A8B79551A04750E2A51B8D34`. Demo
captures measured 969/985/1090 frames. Scripted e1m1/e1m2
captures ran 256 measured frames after 64 warm-up frames, with a fixed
0.0625-second simulation step and sound both disabled and enabled. Every
profile/control group passed its final framebuffer checksum check.

The source-bound i486 profile executable SHA-256 is
`8318A37CC2D91F831508BAD9A1DC3C571E6579E68E66845DE38606F8BD5CCD86`; its
strict audit passed 325,388 relocated instructions, 529 startup instructions,
and 9,207 DPMI-provider instructions with no above-i486, unknown, or exempt
instructions. The [profile build manifest](../out/engine-profile-session-final-20261113/profile-build-manifest.json)
and full [session analysis](../out/engine-profile-session-final-20261113/analysis.json)
retain the remaining provenance.

This is DOSBox elapsed-time attribution, not a count of cycles or cache misses
on a physical 486. Instrumentation overhead measured 5.4-7.0% for coarse
scopes, 11.8-12.6% for component scopes, and 35-50% for detailed scopes.
Coarse profiles are the best whole-engine split; corrected component shares
below are useful rankings, not exact release-time fractions.

## Ranked cost centers

The first percentage column is the corrected exclusive share of the demo1
component profile. The second is the range across the sound-on e1m1/e1m2
component profiles.

| Rank | Scope | Demo1 | Sound-on local maps | Notes |
| ---: | --- | ---: | ---: | --- |
| 1 | Renderer root | 96.5% coarse | 77.5-79.0% coarse | Rendering dominates every demo and remains most of local gameplay. |
| 2 | Texture spans | 28.28% | 32.20-35.64% | Largest component in each measured scene. Existing simple addressing variants have already lost; new work should reduce required span/pixel work. |
| 3 | World BSP and face path | 12.97% | 9.06-9.49% | Includes traversal/visible-face work; the profile does not isolate visibility tests from face setup. |
| 4 | Alias rasterization | 12.74% | 8.48-13.49% | Includes model triangle raster work and depth interaction. Black-triangle skipping was separately benchmarked and rejected. |
| 5 | Z spans | 11.09% | 5.44-6.48% | A substantial second per-pixel path; optimize only with exact color/Z parity. |
| 6 | Edge scan | 10.07% | 6.43-7.63% | World geometry setup remains a large aggregate after the span loops. |
| 7 | Surface cache | 9.12% | 4.71-7.02% | Cache counters show 77.5-92.1% hits and no thrash in these captures. This is the engine surface cache, not a measurement of CPU L1 behavior. |
| 8 | Local server: collision + physics + QuakeC | not run by client demos | 14.20–14.84% | Material in scripted local gameplay. QuakeC includes AI and other game logic; this profile does not isolate AI alone. |
| 9 | 8-bit sound mixing | near zero when muted | 1.64–2.60% | Higher on e1m2. A four-sample loop candidate measured +0.029209% pooled FPS over these two sound-on maps. |

The component shares come from the profiled source fingerprint above. The audio
timing is a separate, later candidate build; its parity, matched runs, and build
audit are recorded in the [mixer ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-snd-mixa-four-sample-unroll-promoted.md).

### Local-gameplay server detail

The detailed sound-on captures expose the main local-server scopes separately.
Times below are corrected detailed-probe exclusive self time, normalized per
measured frame. They rank the work in these scripted maps; instrumentation still
adds overhead and these values are not physical 486 cycles.

| Scope | e1m1 | e1m2 | Share of corrected frame scopes |
| --- | ---: | ---: | ---: |
| Collision | 2.71 ms/frame | 2.48 ms/frame | 4.95–5.93% |
| Server physics | 2.12 ms/frame | 1.80 ms/frame | 3.60–4.63% |
| QuakeC VM | 1.96 ms/frame | 2.83 ms/frame | 4.28–5.65% |
| **These three together** | **6.80 ms/frame** | **7.11 ms/frame** | **14.20–14.84%** |
| Visibility / PVS | 0.039 ms/frame | 0.034 ms/frame | below 0.1% |

The QuakeC scope includes scripted AI and gameplay code, so it does not isolate
AI as its own cost. In the earlier measured attacking-soldier encounter, the
`PF_CheckClientLeaf` cache reduced that query from 0.683 to 0.439 ms/frame and
the complete local-gameplay benchmark improved 0.387% pooled FPS; see the
[AI leaf-cache ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-08-engine-wide-profile-and-ai-cache.md).
That is evidence for this specific AI query, not a general AI share. Collision,
physics, and QuakeC are the best measured non-renderer targets in these moving
and firing scenarios. The very small visibility share gives no support for
adding a general portal/PVS hierarchy for these workloads.

Other individual client scopes such as screen drawing, presentation, and client
command reads are generally around 0.6–2.1% in the local profiles. Moving their
small cost cannot rival a successful work reduction in the renderer or local
server.

The existing QuakeC VM statement counter further localizes a sound-off e1m2
capture (256 measured frames, 320x200): it executed 166,678 VM statements.
`FindTarget` accounts for 46,296 (27.8%), followed by `ai_walk` at 17,280
(10.4%), `ai_stand` at 9,600 (5.8%), and `PlayerPreThink` at 9,472 (5.7%).
`visible` and `range` account for 5,652 (3.4%) and 5,868 (3.5%), respectively.
These are bytecode execution counts, not elapsed-time shares; opcodes have
different costs and this capture has a fixed scripted workload. They point to
target acquisition and monster/player AI as the next QuakeC paths to time before
changing behavior. The source capture and its complete CSV are retained under
Raw profiling captures from this run are local generated artifacts and are not
distributed with the source repository.

### Static entity dispatch measurement

The added detailed scopes break physics into movement types and collision into
world clipping, bounds calculation, and linked-entity clipping. In the
sound-off e1m1/e1m2 profiles, `MOVETYPE_NONE` dispatched 85/124 times per
measured frame. Its raw self windows were 0.162/0.236 seconds over 256 frames,
but 77.6% was the calibrated 5.779-microsecond profiler read floor. The corrected
residual is 0.141/0.206 ms per frame, with instrumentation still changing code
layout; it is not a physical-cycle estimate.

A conservative exact-positive-zero guard before `SV_Physics_None` removes this
no-op path. Three alternating uninstrumented control/candidate pairs per map
showed the same final simulation and framebuffer checksums on every pair:

| Map | Control mean FPS | Candidate mean FPS | Change |
| --- | ---: | ---: | ---: |
| e1m1 | 23.672474 | 23.678175 | +0.024081% |
| e1m2 | 22.033745 | 22.040938 | +0.032644% |
| Both maps pooled | 22.823732 | 22.830241 | +0.028518% |

This is reproducible but small, under 0.04% on either map. It does not change
the optimization ranking: reducing texture-span and other renderer work remains
the largest opportunity, with collision, physics, and QuakeC a secondary
gameplay track. The detailed profile used source-tree fingerprint
`8AD0FA0F5D20A429FDCCD60FF2CBD71CDE5E4136E71E6F4B621EBAB94E338E13`; the
candidate fingerprint was
`B18492AD3A5E669C5D8306A5F3AE6C70F7B172B724F014844A520F73296DE5C3`. The
detailed profile and per-run outputs are
[`e1m1`](../out/server-functions-e1m1-20261113.json),
[`e1m2`](../out/server-functions-e1m2-20261113.json), and the six alternating
timing records under `benchmarks/out/static-think-match-*-20261113.json`.

### QuakeC statement-index stores

The QuakeC VM contributes 1.96 ms/frame on e1m1 and 2.83 ms/frame on e1m2 in
the corrected component scopes (4.28-5.65% of measured local gameplay). The VM
previously wrote the global current-statement index after every instruction,
although the value is read only for trace output, errors, and saved callsites.
The retained change updates it only on those paths. It preserves the reported
statement for `PR_RunError`, `PR_EnterFunction`, and `PR_LeaveFunction` while
removing the common-path store.

Three alternating uninstrumented qbench pairs per map produced exact final
simulation and framebuffer checksums on every run. The timing was highly
repeatable:

| Map / pair | Control seconds / FPS | Candidate seconds / FPS |
| --- | ---: | ---: |
| e1m1 / 1 | 10.811644 / 23.678174 | 10.805390 / 23.691880 |
| e1m1 / 2 | 10.811643 / 23.678176 | 10.805394 / 23.691871 |
| e1m1 / 3 | 10.811633 / 23.678200 | 10.805396 / 23.691867 |
| e1m2 / 1 | 11.614758 / 22.040925 | 11.607127 / 22.055415 |
| e1m2 / 2 | 11.614754 / 22.040931 | 11.607126 / 22.055416 |
| e1m2 / 3 | 11.614751 / 22.040937 | 11.607133 / 22.055403 |

The measured change is **+0.05781%** on e1m1 and **+0.06570%** on e1m2,
or **+0.06190% pooled** across 1,536 frames. Checksums were
`2568184557 / 1299435123` (simulation/framebuffer) on e1m1 and
`1496920581 / 1246513233` on e1m2. This is a small but repeatable DOSBox-X
improvement. It does not change the ranking: rendering still dominates, while
QuakeC remains a secondary optimization track alongside collision and physics.
See the [QuakeC statement-store ledger]
(../../quake/docs/ledger/2026-11-13-quakec-statement-store-elision-promoted.md)
and the six pairs of source-pinned result records under
`benchmarks/out/vm-statement-store-match-*.json`.

The renderer/server profile baseline release, before the exact-zero-T candidate,
was Build 886, source-tree fingerprint
`3D39180539B22B8F3F3E59FBD198987463D4D7BBE6532AF1697F699274610DEA`,
executable SHA-256
`C280318A6513E36AD3FFDA0F16ADD72C0341DA86219DBB2A8BF3B890883E4ABA`.
Its complete strict i486 audit verified 165,097 linked instructions, 529
startup rows, and 9,207 provider instructions with no above-i486, unknown, or
exempt instructions. The source-bound manifest is fresh.

### Exact-zero-T texture-span specialization

The span profile counters found a common case that removes work from the
largest measured component: 54.58% of 16-pixel texture segments on e1m1 and
45.41% on e1m2 had an exactly zero T delta. A new `D_DrawSpans16` branch
specializes those segments to update only the S accumulator and source address;
it leaves every color write and the separate Z pass intact. Three uninstrumented
matched qbench runs per map measured a pooled **+2.800318% FPS** change over
control (+3.288160% e1m1, +2.350292% e1m2) with exact final simulation and
framebuffer checksums. Three fixed-clock demo1 replays also matched every
per-frame color and Z checksum across variants. The i486 release profile now
selects this measured path by default. Its complete strict i486 gate passed.
Full samples and trace hashes are recorded in the
[exact-zero-T ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-span16-exact-zero-tstep-promoted.md).

### Exact-zero-T texture-span tail specialization

The same profiles counted zero-T work in the short remainder after the first
pixel of each span: 44.13% of e1m1 tail samples and 46.11% of e1m2 tail samples
needed no T advance. An assembly suffix now updates S and writes those samples
without repeating T carry and texture-address work. Across three alternating
uninstrumented runs per variant and map, pooled FPS rose from **23.484092** to
**23.609711** (**+0.5349%**): +0.5441% e1m1 and +0.5265% e1m2. All samples were
faster; local simulation/framebuffer checksums and all 970 per-frame color and
Z checksums in three fixed-clock demo1 replays matched exactly. The i486 release
profile now selects this measured path by default. Strict qbench and release
ISA gates passed. See the [tail-zero ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-span16-tail-exact-zero-tstep-promoted.md)
and the matched result records under `benchmarks/out/span16-tail-tzero-*`.

## Amdahl estimates and next experiments

Texture spans offer the largest measured surface. At a 28.28% demo1 share, a
hypothetical 5% reduction in that component would yield about 1.4% whole-frame
FPS improvement; a 10% reduction would yield about 2.9%. These are
Amdahl scenarios, not measured candidate results. Prior single-instruction and
small-loop renderer candidates have generally delivered far less, so a larger
gain needs an algorithm that removes work rather than rearranging the same
per-pixel operations.

For scripted local gameplay, collision, server physics, and QuakeC together
represent roughly 14-15% of component-profile time. A 10% reduction in that
group would be worth about 1.4-1.5% FPS on these local maps, with no benefit in
client timedemos. That makes per-function server profiling a credible second
track alongside renderer work.

The profile does not measure hardware L1 misses, AGI stalls, memory bus cycles,
or real 486 instruction retirement. Surface-cache hit rate is healthy, and no
CPU-cache claim should be inferred from it. Physical-486 timing remains a
separate acceptance step.

## Validation status

The benchmark repository host suite passed **19/19** checks during the initial
profiling pass. The game
repository host suite reported **7 passed and 5 failed**: the existing ledger
index has 11 heading-count mismatches; the cumulative assembly-profile check
rejects the current BSP/edge-list selectors; the build-selector golden has 28
configuration mismatches; the sysinfo source-contract check expects a missing
`VID_ReportSystem` call; and the video check could not find host `gcc`. None of
these failures is in `sv_phys.c`, `world.c`, or the profiling node additions.
At that initial pass, the new ledger row and five-heading file passed the
document structure check; the same 11 pre-existing count errors remained.

The full-span and tail-segment exact-zero-T candidates were each validated
separately with three matched local-game timing runs per map, three fixed-clock
full-demo color/Z parity runs per variant, and a fresh strict release build.
Host suites were not rerun for these candidates.

## Retained evidence

- [Generated profile report](../out/engine-profile-session-final-20261113/report.html)
- [Corrected ranked-scope CSV](../out/engine-profile-session-final-20261113/ranked-scopes.csv)
- [Full profile analysis](../out/engine-profile-session-final-20261113/analysis.json)
- [Sound-mixer optimization ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-snd-mixa-four-sample-unroll-promoted.md)
- [QuakeC statement-store optimization ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-quakec-statement-store-elision-promoted.md)
- [Texture-span tail exact-zero-T optimization ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/2026-11-13-span16-tail-exact-zero-tstep-promoted.md)
