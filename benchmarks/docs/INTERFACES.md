# Game and benchmark interfaces

## Native build API

The game owns `tools/build-dos.ps1 -DumpFlags`: JSON describing resolved selectors,
flags, sources, executable, object directory and build manifest. Runners invoke
the same builder to compile and use the game-owned `tools/common.ps1` API for
selector verification, freshness and source-bound ISA proofs. The suite imports
the game API; the game never imports the suite.

Build identity comes from the game's full Git history and optimization ledger.
Moving tooling does not count as an optimization attempt. Product identity and
source fingerprints remain distinct from the benchmark tooling revision.
Do not edit generated headers, inventories, manifests or proof reports.

## Paths and toolchains

`-GameRoot`, then `NITROQUAKE_GAME_ROOT`, then the sibling `quake/` selects a game
checkout. Python source-contract tools use the same environment variable.
`tools/dos-toolchain.json` in the game pins DJGPP. The suite's
`tools/dosbox-toolchain.json` pins DOSBox-X. The shared hash-verified installer
is game build infrastructure; the suite passes its own manifest to it.
`-ToolRoot` defaults to the existing local application-data cache. A standalone
game build only needs DJGPP, even when the emulator has never been installed.

Game compilation and ISA proofs live in the game's `out/`. New emulator staging,
timedemo results, captures and analysis live in this suite's ignored `out/`.
Staging refuses existing run directories unless explicitly using the smoke
runner's overwrite policy, and rejects paths outside the suite output root or
through reparse points. Old `quake/out/` archives retain their original paths.

## Recorded data

Existing schemas and field meanings are retained: `timedemo-result.json` includes
per-run frame count, seconds, FPS, checksum and selected build/emulator metadata;
`profile.jsn` schema 1 records inclusive/self costs and invocation counts;
frame checksum streams retain their frame order and optional Z checksums.
PCX comparison operates on decoded indexed pixels and palettes. Scene manifests
specify demo, expected frames, captures, checksums, event requirements and
comparison thresholds. Paired rendering reports enforce the existing exact
stream and image contracts. No migration or rebaselining of golden images occurs.

`staged-data.json` additionally records each input PAK's path, SHA-256 and storage
method. `tooling-provenance.json` identifies suite source bytes separately from
native game provenance. Record executable/data/profile hashes with every result;
do not infer comparability from filenames or product build numbers alone.

## History and archives

`../migration.json` records each transferred path's original game revision and
SHA-256, plus split interfaces and transferred workspace assets. Both existing
Git histories are retained without rewriting. To inspect an original script,
use `git -C <game> show <sourceRevision>:<sourcePath>` from the migration record.
Historical ledger commands describe their original checkout layout. Active
runtime commands now belong to this suite; native build commands remain in game.
