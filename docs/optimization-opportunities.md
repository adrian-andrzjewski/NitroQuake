# Remaining optimization opportunities

The latest nearby instrumented profile attributes 18.52 seconds to perspective
texture spans across 3.51 million segments and 43.96 million pixels. These
measurements rank work; their timings are not comparable to uninstrumented FPS
results. The source profile is [`profile.jsn`](../quake/out/dos-timedemo-20261029-221148/quake/profile.jsn).

## Profile ranking

| Priority | Opportunity | Assessment |
|---|---|---|
| 1 | `D_DrawSpans16` perspective arithmetic | Highest plausible upside in the profile. Exact algorithm changes could reduce per-segment work, but reciprocal and x87 stack rewrites tested on October 31 did not produce a correct, repeatable gain; see the [focused Span16 record](../quake/docs/ledger/2026-10-31-span16-perspective-arithmetic-trials-rejected.md). |
| 2 | Z spans, edge traversal, and `R_RenderFace` | Meaningful profile share, though recent scheduling, unroll, and branch trials are mostly marginal or regressions. Larger changes would be needed for material gains. |
| 3 | Alias raster and spans | Still measurable work, but recent alignment, carry, and load/store reorderings have not shown a dependable win. |
| 4 | Surface cache | The October 31 static-hit leaf path gained **0.019160%** in a matched uninstrumented 320x200 benchmark with exact output parity. The workload had 46,532 hits, 8,773 rebuilds, no cache thrash, and no dynamic-light probes, so remaining hit-path headroom appears small. See the [promotion record](../quake/docs/ledger/2026-10-31-surface-cache-hit-leaf-entry-promoted.md). |
| 5 | Store width and cache layout | Word stores remain best in recorded comparisons. Dword, byte, loop, and `stosw` variants lost. DOSBox-X cannot establish gains from physical 486 cache behavior. |

## October 31 Span16 result

Three focused candidates were checked with deterministic 320x200 DOSBox-X
runs and strict i486 audits. Reusing the reciprocal when horizontal inverse
depth was zero was 0.7705% slower and changed intermediate frame checksums.
Changing the x87 division stack order caused visible texture banding and failed
the framebuffer checksum. Replacing two stack exchanges with direct S/T
stack-slot updates had a slower three-run mean and changed only the transient
pickup message in the two captured differing frames; it did not show a
repeatable gain. The original `D_DrawSpans16` arithmetic remains in place.

## Remaining headroom

The renderer already uses hand-scheduled x87 work, fixed-point stepping,
unrolled span loops, and i486-safe scalar instructions. The earlier estimate
was that routine scheduling changes might add less than 1% cumulatively, with
most individual ideas below a tenth of a percent. A further 1–3% was considered
plausible only from substantial exact algorithmic work on perspective spans
or raster traversal. That range is a hypothesis, not a measured result; the
recent perspective-arithmetic experiments did not realize it. DOSBox-X also
cannot establish how cache layout and instruction latency behave on physical
486 variants.
