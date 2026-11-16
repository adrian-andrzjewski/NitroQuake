# NitroQuake workspace

This workspace coordinates two Git repositories:

| Location | Responsibility |
| --- | --- |
| `quake/` | Standalone game source, assembly, assets, DJGPP build and strict ISA verification |
| `benchmarks/` | DOSBox automation, Python analysis, scenarios, parity checks and performance reports, versioned by this outer repository |

Build the game from `quake/` using its [build guide](quake/BUILD-DOS.md).
Run performance and runtime checks using the [benchmark guide](benchmarks/README.md).
The game does not import or install benchmark tooling.

The nested game is an existing Git checkout recorded by a gitlink, not a
configured Git submodule. Preserve both repositories when copying this workspace.
Commit game changes first, then record the resulting gitlink in this repository.
A shallow game checkout can build from its available `HEAD`; full history is
needed only for a complete optimization-attempt inventory.
For an independent benchmark checkout, supply `-GameRoot` or
`NITROQUAKE_GAME_ROOT`; the sibling directory is only a default.

Check checkout alignment and local prerequisites with the read-only workspace
doctor:

```powershell
pwsh -NoProfile -File benchmarks/tools/check-workspace.ps1
```

It reports outer and game revisions, compares the committed and staged gitlink
with the nested `HEAD`, lists dirty state and checks pinned tool availability.
It does not fetch, reset, bootstrap, or replace repositories or tools. The
[current architectural assessment](docs/architectural-assessment-2026-11-16.md)
records the reviewed baseline and remaining priorities.

See [repository boundaries](docs/repository-layout.md) and
[migration provenance](benchmarks/migration.json). Existing `quake/out/` evidence,
accepted artifacts, worktrees and canonical PAK files are preserved in place.
New benchmark output goes to `benchmarks/out/`; it is not committed.
