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
For an independent game checkout, use a full-history clone of `quake/`.
For an independent benchmark checkout, supply `-GameRoot` or
`NITROQUAKE_GAME_ROOT`; the sibling directory is only a default.

See [repository boundaries](docs/repository-layout.md) and
[migration provenance](benchmarks/migration.json). Existing `quake/out/` evidence,
accepted artifacts, worktrees and canonical PAK files are preserved in place.
New benchmark output goes to `benchmarks/out/`; it is not committed.
