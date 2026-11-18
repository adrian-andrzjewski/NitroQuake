# Benchmark documentation

Use the maintained guides for current commands and acceptance rules. Reports
and dated experiment records describe only their recorded source, workload, and
environment.

## Workflows and acceptance

| Need | Document |
|---|---|
| Install tools, stage game data, and run the suite | [Benchmark suite guide](../README.md) |
| Choose and interpret runtime operations | [Operations guide](OPERATIONS.md) |
| Profile engine work and account for instrumentation | [Engine profiling](ENGINE-PROFILING.md) |
| Capture per-frame timing | [Frame timing](FRAME-TIMING.md) |
| Validate deterministic rendering | [Rendering validation](RENDERING-VALIDATION.md) |
| Qualify on a real 486-class system | [Physical 486 acceptance](PHYSICAL-486-ACCEPTANCE.md) |
| Understand game/suite interfaces | [Interfaces](INTERFACES.md) |
| Compare complete delivered executables | [Comparison methodology](BENCHMARK-COMPARISON.md) |

## Results

- [Current-source engine profile — 2026-11-17](results/current-source-engine-profile-2026-11-17.md)
- [Quake DOS executable comparison](BENCHMARK-COMPARISON.md)
- [Frame-timing validation](FRAME-TIMING-VALIDATION.md)
- [2026-11-15 release-profile report](ENGINE-PROFILING-20261115.md)
- Additional dated profiling, parity, video, collision, and optimization reports
  remain in this directory. Their scope and limitations are stated in each file.

The [history directory](history/) contains the former operations notebook and
optimization-opportunities snapshot. The engine checkout owns attempt policy and
the automatically derived build number; see its
[optimization policy](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/optimization/policy.md).
