# Game and benchmark interfaces

## Native build API

The game owns `tools/build-dos.ps1 -DumpFlags`: JSON describing resolved flags,
sources, executable, object directory and build manifest for the selected
`i486-release` or `c-reference` configuration. Runners use this stable builder
for supported configurations and the game-owned `tools/common.ps1` API for
selector verification, freshness and source-bound ISA proofs. Benchmark runners
send per-routine comparisons and probes to the internal
`tools/build-dos-experimental.ps1` backend. The suite imports the game API; the
game never imports the suite.

Product build identity combines the game's source revision with the fingerprint
of source inputs and resolved build configuration. The manifest retains the
optimization-attempt count and inventory digest as provenance when a complete
inventory is available; full history is not required for the product identity
or for a shallow checkout to build. Moving tooling does not count as an
optimization attempt. Product identity and source fingerprints remain distinct
from the benchmark tooling revision. Do not edit generated headers, inventories,
manifests or proof reports.

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

## Ordered frame timing

Ordered frame timing export and its session/CSV/graph formats are documented in
`FRAME-TIMING.md`. The native DOS CSV is written after playback, before the legacy
FPS summary sorts its buffer; host analysis validates every sample and its
recorded environment. It uses a fixed simulation step with real timing, distinct
from the presentation `-parityclock` correctness mode.

## Whole-engine diagnostics

The game owns BENCH486 `-gamebench` and `benchprofile N`, fixed-step local capture,
selected-state checksums and native scope bookkeeping. PROFILE486 accepts
`-profilecoarse` and `-profileparts`; schema-1 `profile.jsn` adds `capture_mode`
without renumbering existing assembly scope IDs. Local exports are
`GAMEPROF.TXT`, `QCPROF.CSV` and optional `profile.jsn`. No host analysis dependency
is required to build or run these native interfaces.

The suite owns serial collection, source-bound validation, schema-version-1
session/result JSON, timer-floor correction, comparisons and chart generation.
Results retain hashes and paths to native exports; session jobs hash each result.
Coarse/component/detailed captures and unprofiled controls retain distinct mode
labels. Final selected-state checksums do not replace exhaustive replay parity,
and QuakeC statement counts do not imply per-function elapsed time.
See [the protocol](ENGINE-PROFILING.md) for clocks, limitations and commands.

The suite's [native QuakeC fixture](QC-INTERPRETER-VALIDATION.md) consumes explicit
reference/candidate roots and the supported builder's resolved flags. It checks
header/helper compatibility and produces a standalone diagnostic executable;
the game has no dependency on the fixture or its host-side Python driver.

The [collision fixtures](COLLISION-VALIDATION.md) use the same explicit-root,
resolved-builder and pinned native-runner boundaries. Their top-level
`fixture.json` binds source/header/compiler inputs and per-unit generated files
to separate `move/` and `cliplinks/` execution records. Helper stubs isolate the
interfaces; game/runtime/ISA and performance gates remain separate.

`plot-matched-comparison.py` consumes the retained matched-comparison session
format: `groups` contain `kind` (`timing`/`local`), `workload`, `sound`, `frames`
and `samples.control`/`samples.candidate` elapsed-second arrays, aligned by pair.
The terminal session must have a sibling `audit.json` with `status: PASS` and
`sessionSha256` matching its exact bytes. The tool excludes parity groups,
exports every timing sample to CSV, and plots median FPS/change plus observed
paired ranges. It does not turn those ranges into confidence intervals.

## History and archives

`../migration.json` records each transferred path's original game revision and
SHA-256, plus split interfaces and transferred workspace assets. Both existing
Git histories are retained without rewriting. To inspect an original script,
use `git -C <game> show <sourceRevision>:<sourcePath>` from the migration record.
Historical ledger commands describe their original checkout layout. Active
runtime commands now belong to this suite; native build commands remain in game.
