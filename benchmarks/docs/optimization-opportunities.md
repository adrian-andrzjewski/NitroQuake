# Choosing optimization opportunities

Start with the [current-source profile](results/current-source-engine-profile-2026-11-17.md)
to find measured work, then search the game's
[optimization ledger](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/ledger/INDEX.md) for accepted, rejected,
and combined experiments. The profile is an attribution snapshot from game
revision `644fb3a`; it uses a single uninstrumented timing sample per workload
and does not establish repeatable performance.

The capture found substantial work in texture spans, surface-cache operations,
Z spans, and model drawing. These are investigation areas, not accepted
optimization candidates. Refresh profiling when source or workloads change.

## Candidate workflow

1. State one narrow hypothesis and select a representative deterministic
   workload.
2. Check the ledger for prior variants and known parity or timing failures.
3. Keep the current implementation as the control and collect at least three
   matched uninstrumented samples per variant at 320x200.
4. Require exact affected-output parity and the strict linked-image i486 audit.
5. Record all samples, spread, executable identity, and the accepted or rejected
   decision in the ledger.

See the game's [optimization policy](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/optimization/policy.md)
for the complete acceptance and attempt-count rules. The dated
[opportunity survey](history/optimization-opportunities.md) remains available
as a historical profile note.
