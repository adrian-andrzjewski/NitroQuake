# NitroQuake workspace documentation

This repository contains benchmark orchestration and project reports. The
engine source, DOS build, verification, and optimization ledger are published
in the separate [NitroQuake engine repository](https://github.com/adrian-andrzjewski/NitroQuake-engine).
The workspace's `engine.lock` identifies the exact engine commit used for
reproducible builds.

## Start here

| Need | Read |
|---|---|
| Understand repository ownership and setup | [Repository layout](repository-layout.md) |
| Read current architecture and verification boundaries | [Current architecture](architecture/current-state.md) |
| Build and verify the engine | [Engine build guide](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/BUILD-DOS.md) |
| Run DOSBox-X scenarios and benchmark checks | [Benchmark suite guide](../benchmarks/README.md) |
| Find a benchmark procedure or result | [Benchmark documentation index](../benchmarks/docs/INDEX.md) |
| Follow contribution practices | [Repository guidelines](repository-guidelines.md) |
| Review distribution terms | [Third-party notices](../THIRD-PARTY-NOTICES.md) |

## Current evidence

The [2026-11-17 engine profile](../benchmarks/docs/results/current-source-engine-profile-2026-11-17.md)
is a dated DOSBox-X attribution capture. It records its source revision,
instrumentation overhead, and one uninstrumented timing sample per workload;
use it to rank investigations, not to claim repeatable gains or physical-486
performance. Dated reports identify their source revision and evidence scope;
they do not replace fresh validation of a current checkout.
