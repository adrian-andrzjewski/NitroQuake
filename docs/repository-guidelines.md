# Repository guidelines

## Project structure

NitroQuake uses two independent Git repositories. The [engine repository](https://github.com/adrian-andrzjewski/NitroQuake-engine)
owns the C and assembly code, DOS build, optimization ledger, and engine tests.
This workspace owns benchmark automation, fixtures, analysis, and reports.
`engine.lock` pins the engine revision used by a workspace checkout; the
bootstrap script creates the ignored local `quake/` clone.

## Build and test commands

Build and verify the engine from its checkout:

```powershell
pwsh -NoProfile -File tools/bootstrap-dos.ps1
pwsh -NoProfile -File tools/build-dos.ps1 -Configuration i486-release
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
```

Run workspace host checks from `benchmarks/`:

```powershell
pwsh -NoProfile -File tools/run-tests.ps1 -HostOnly
```

The engine requires PowerShell 7, Python 3.9+, the pinned DJGPP toolchain, and
a native Windows GCC for its strict startup-source verification. Runtime
scenarios additionally need DOSBox-X and legally obtained Quake game data.
See the engine `BUILD-DOS.md` and workspace `benchmarks/README.md` for details.

## Changes and review

Keep source changes in the engine repository and benchmark/workspace changes in
this repository. When updating the engine pin, commit and publish the engine
revision first, then update `engine.lock` to its exact commit. Use focused
commits with `type(scope): summary` messages. Preserve existing public APIs,
calling conventions, and supported CPU targets. Do not commit PAK files,
commercial assets, unverified third-party binaries, or generated output under
`out/`.

Run the relevant host checks for each change. For rendering or runtime work,
report the exact scenarios, inputs, and results. Performance acceptance
requires correctness evidence and repeatable matched runs; DOSBox measurements
alone do not establish real-hardware performance.
