# NitroQuake workspace documentation

This repository combines documentation for two separate Git histories. The
outer checkout owns benchmark orchestration and workspace guidance; `quake/`
owns the DOS engine, build, and optimization ledger.

## Start here

| Need | Read |
|---|---|
| Understand repository ownership and the game gitlink | [Repository layout](repository-layout.md) |
| Read current architecture and verification boundaries | [Current architecture](architecture/current-state.md) |
| Build and verify the game | Game checkout: [`BUILD-DOS.md`](../quake/BUILD-DOS.md) |
| Run DOSBox-X scenarios and benchmark checks | [Benchmark suite guide](../benchmarks/README.md) |
| Find a benchmark procedure or result | [Benchmark documentation index](../benchmarks/docs/INDEX.md) |
| Follow repository contribution practices | [Repository guidelines](repository-guidelines.md) |

## Current evidence

The [2026-11-17 engine profile](../benchmarks/docs/results/current-source-engine-profile-2026-11-17.md)
is a dated DOSBox-X attribution capture. It records its source revision,
instrumentation overhead, and one uninstrumented timing sample per workload;
use it to rank investigations, not to claim repeatable gains or physical-486
performance.

## Historical archive

[History index](history/INDEX.md) groups earlier architectural assessments,
checklists, and repository migration records. They remain available as
revision-specific snapshots. Current guidance is maintained in the pages
linked above.
