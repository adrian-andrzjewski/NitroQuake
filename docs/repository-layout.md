# Game and benchmarking repository boundary

The workspace contains two existing Git histories. `quake/` remains the game
repository. The outer repository owns the independent suite under `benchmarks/`.
The suite can target another complete game checkout through `-GameRoot` (or
`NITROQUAKE_GAME_ROOT`); the sibling `quake/` is only its workspace default.

## Canonical checkouts and worktrees

The primary outer checkout is `workspace` on `master`. The primary
game checkout is `workspace\quake`, also on `master`. New linked
worktrees belong under `workspace-worktrees\outer\<topic>` or
`workspace-worktrees\quake\<topic>`; do not create NitroQuake or
NQ worktree directories directly under `D:\`. Retired experiment output is
kept under `benchmarks/out/worktree-archives/<date>/<former-worktree>/out`.
The dated mapping in `docs/worktree-archive-map-2026-11-13.csv` records the
checkout, branch, commit, and archived output location for this consolidation.

## Ownership

| Game repository | Benchmarking repository |
| --- | --- |
| Native C and assembly, including optional engine instrumentation and native correctness fixtures | Python analysis, image/report comparison, ownership reports, and charts |
| DJGPP bootstrap, compiler configuration, selector profiles, source-bound ISA verification, and their tests | DOSBox bootstrap, pinned emulator configuration, staging, smoke, coverage, profiling, parity, and timedemo runners |
| Game assets, licenses, engine documentation, and optimization decision records used by build identity | Scenario definitions, captured-frame oracles, benchmark qualification tests, alternative DPMI comparison inputs, and operating guides |

Python used for compiler/source/binary verification is build infrastructure and
stays with the game. A language-only move would break the standalone i486 gate.
The optimization ledger stays with the game as build-identity provenance; its
historic measurements and source quotations must not be silently rewritten.
Native BENCH486 fixtures are optional game test code, not Python orchestration.

## Integration contracts

The game owns `tools/build-dos.ps1`, its resolved `-DumpFlags` configuration,
generated build identity, build manifests, native artifacts, and ISA proofs.
Benchmarking consumes those interfaces and records its own tooling revision
separately from the game revision. Emulator staging and new measurement output
belong under `benchmarks/out/`; game compilation output remains under `quake/out/`.
Historical output is an archive and is preserved in place.

The game bootstrap installs only the compiler toolchain. The benchmark bootstrap
uses a separate pinned emulator definition and delegates to the same verified
artifact installer. Game build helpers do not import the benchmark suite.

Existing timedemo, profile, checksum, PCX, event, and parity-report semantics are
preserved. New path resolution must distinguish engine inputs, suite fixtures,
user data, tool installations, and run output explicitly.

## Migration and preservation

`benchmarks/migration.json` records both starting revisions, each transferred
tracked path, and its original working-file and Git-blob digests. The old game ancestry remains available; the outer
history records new ownership without rewriting either repository's history.
Cross-repository transfer cannot be represented by an ordinary single-repository
rename; the manifest provides explicit source attribution without history rewriting.

Workspace branding now belongs to `quake/assets/branding/`. Local comparison
executables moved to ignored `benchmarks/baselines/`, with a hash inventory.
License files, canonical game PAKs, tool caches, junctions, accepted artifacts,
and historical reports are preserved. Historical output from a retired
worktree is moved byte-for-byte into the central archive above before its
checkout is removed. Unreferenced experiment output is not assumed disposable.

## Verification procedure

- Build and run game build checks from an independent full-history checkout
  without a neighboring benchmark suite or installed emulator requirement.
- Verify compiler flags and selector propagation across i386/i486 and native
  release/BENCH486/profiling configurations.
- Exercise suite path resolution against explicit and sibling game checkouts,
  including paths with spaces, and run its host format/comparison tests.
- After the existing Quake2 hold is released, validate DOS startup, a deterministic
  timedemo, native drawing parity, and profile collection through the relocated
  runners. Keep diagnostic profiling separate from timing claims.
- Generate comparison charts from recorded evidence and preserve data/provenance.
- Review exact staged scopes, commit logical changes locally, verify the outer
  gitlink matches the game revision, and finish with clean worktrees.
