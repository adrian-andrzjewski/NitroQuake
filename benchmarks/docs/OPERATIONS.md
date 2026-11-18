# Benchmark operations

The [benchmark suite guide](../README.md) is the entry point for prerequisites,
bootstrap, game-data staging, and portable ISO creation. This page summarizes
the normal measurement sequence and links to the detailed procedures.

## Select the engine checkout

Run commands from `benchmarks/`. The sibling `quake/` checkout is the default;
use `-GameRoot` or `NITROQUAKE_GAME_ROOT` to select another complete game
checkout. Supply legally obtained Quake PAK files through `-DataRoot` or the
game's `testdata/id1/`. Generated builds stay in the selected game's `out/`, and
benchmark captures stay in `benchmarks/out/`.

## Standard checks

```powershell
pwsh -NoProfile -File tools/bootstrap-dos.ps1
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
pwsh -NoProfile -File tools/smoke-dos.ps1 -NoBootstrap
pwsh -NoProfile -File tools/timedemo-dos.ps1 -Runs 3 -NoBootstrap -NoFpsStats
```

Run the engine repository's host checks separately. Use
[`run-tests.ps1`](../tools/run-tests.ps1) without `-HostOnly` for the registered
runtime suite, and report skipped gates explicitly.

## Measurement rules

- Use profiling to locate work; instrumentation changes runtime cost.
- Compare matched, uninstrumented executables with the same profile, data,
  workload, resolution, and frame count.
- Keep exact rendering or simulation parity evidence with each candidate.
- Retain every sample and report the spread; do not compare unlike controls.
- Treat DOSBox-X results as emulator evidence. Physical-486 acceptance follows
  the separate [hardware procedure](PHYSICAL-486-ACCEPTANCE.md).

The game build number counts documented accepted and rejected optimization
attempts, not benchmark runs or commits. Its inventory and reproducibility rules
are maintained in the game's
[optimization policy](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/optimization/policy.md).

## Historical operations notes

The former operations notebook is preserved in
[`history/OPERATIONS.md`](history/OPERATIONS.md). It includes dated implementation
notes and measurements; use this page and the linked workflows for current
commands.
