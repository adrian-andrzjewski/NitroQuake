# Repository Guidelines

## Project Structure & Module Organization

This workspace coordinates two Git repositories. `benchmarks/` contains DOSBox automation, Python analysis, test fixtures, scenarios, and performance reports. `docs/` describes the repository boundary and migration. `quake/` is a standalone game checkout recorded by the outer repository as a gitlink; it owns the C and assembly sources, game assets, DJGPP build, and game verification tools. Commit game changes inside `quake/` first, then update the outer repository's gitlink. See `docs/repository-layout.md` for ownership details.

## Build, Test, and Development Commands

Run game commands from `quake/` and benchmark commands from `benchmarks/`:

```powershell
# From quake/: build the i486 DOS executable
pwsh -NoProfile -File tools/build-dos.ps1 -CpuTarget i486
# From quake/: run host-side game checks
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
# From benchmarks/: run host-side suite checks
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
```

The game build uses the pinned DJGPP toolchain. Runtime checks additionally need the benchmark toolchain and legally obtained game PAK files; see `quake/BUILD-DOS.md` and `benchmarks/README.md` for full workflows.

## Coding Style & Naming Conventions

Match the surrounding C, GNU assembly, PowerShell, and Python style; keep changes focused and preserve existing APIs, calling conventions, and supported CPU targets. Name new test scripts `test-*.py` or `test-*.ps1`, following the neighboring tools. No repository-wide formatter is configured.

## Testing Guidelines

Run the relevant host checks for changes in either repository. For runtime or rendering changes, use the documented benchmark scenarios and report the exact checks performed. Performance claims require correctness/parity evidence and repeatable matched runs; DOSBox measurements alone do not establish real-hardware performance.

## Commit & Pull Request Guidelines

Recent commits use `type(scope): summary`, for example `perf(i486): ...` or `test(benchmarks): ...`. Keep game-source commits in `quake/` and gitlink updates in the outer repository. Pull requests should identify the affected repository, summarize behavior changes, list commands and results, and include relevant comparison data for performance or visual changes. Do not commit licensed PAK files or generated output under `out/`.
