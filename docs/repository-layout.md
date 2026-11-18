# Repository layout

NitroQuake is split across two public Git repositories with separate histories:

- [NitroQuake workspace](https://github.com/adrian-andrzjewski/NitroQuake)
  contains benchmarks, fixtures, workspace automation, and project reports.
- [NitroQuake engine](https://github.com/adrian-andrzjewski/NitroQuake-engine)
  contains Quake-derived source, DOS build tools, optimization records, and
  engine verification.

The workspace's `engine.lock` pins the engine repository URL and exact commit.
Run `benchmarks/tools/bootstrap-workspace.ps1` after cloning the workspace to
fetch complete engine history into a local `quake/` directory. That directory
is ignored by the workspace repository and remains a standalone engine clone.
The full history is required for the optimization-attempt build number.

## Ownership

| Engine repository | Workspace repository |
| --- | --- |
| Native C and assembly, DOS build, DJGPP bootstrap, selector profiles, and source-bound ISA verification | Benchmark orchestration, Python analysis, fixtures, scenarios, charts, and reports |
| Optimization ledger and automatic product build identity | DOSBox-X bootstrap, staging, smoke, coverage, profiling, parity, and timedemo tools |
| Engine-specific licenses and third-party notices | Workspace license, third-party notices, and instructions for supplying local game data |

The engine can be built without the benchmark workspace or DOSBox-X. Benchmark
commands can use the checked-out sibling engine or another complete checkout
with `-GameRoot` or `NITROQUAKE_GAME_ROOT`.

## Build and test

From the workspace root, provision the pinned engine and build it:

```powershell
pwsh -NoProfile -File benchmarks/tools/bootstrap-workspace.ps1
Set-Location quake
pwsh -NoProfile -File tools/bootstrap-dos.ps1
pwsh -NoProfile -File tools/build-dos.ps1 -Configuration i486-release
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
```

From `benchmarks/`, run suite host checks with
`pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly`. Runtime rendering and
gameplay tests require legally obtained Quake data and DOSBox-X. Reference
captures are user-supplied; the project does not distribute game imagery.

## Game data and generated files

Neither repository contains commercial Quake PAK files or game assets. The
engine ignores its `id1/` directory and common game-data formats. Keep personal
game data outside Git and provide legally obtained registered data at runtime.
Both repositories ignore generated `out/` trees, local tools, binaries, and
other build artifacts. See each repository's `.gitignore` and third-party
notices for distribution boundaries.
