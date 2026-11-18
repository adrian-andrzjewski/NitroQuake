# NitroQuake CI and release architecture

**Status:** automated build and release pipeline; public releases require a verified version tag.

**Reviewed:** 2026-11-18

## Overview

The engine and its benchmark workspace have separate Git histories, so each
repository owns a workflow. Engine CI validates changes to the DOS source and
optimization ledger. Workspace CI provisions the exact engine commit from
`engine.lock`, repeats the shipping build at the integration boundary, runs
workspace host checks, and creates an allowlisted release package.

The release targets i486-compatible DOS machines with x87. Public CI does not
run DOSBox gameplay or image comparisons because those require a legally
obtained Quake installation and optional local reference captures. The source,
CI cache, Actions artifact, and release assets contain no Quake PAK files or
captured gameplay images.

## Build identity and number

The engine's `tools/optimization-history.py` is the source of the numeric build
number. It counts unique optimization attempts classified as accepted or
rejected in the ledger and supporting documentation. The inventory rejects
incomplete Git history, missing classifications, and duplicate experiment
identities. The build embeds both the number and a source/configuration
identity; `tools/test-build-number.ps1` and
`tools/test-optimization-history.py` verify the contract.

The build does not use a hand-maintained integer or the commit-count fallback.
Both workflows provide complete engine history. The current locked engine
revision computes **Build 888** from **494 accepted** and **394 rejected**
attempts. CI checks that the manifest, complete optimization inventory, and
console identity agree. Future values continue to come from the ledger without
changing workflow files.

## Workflows

| Repository | Workflow | Triggers | Gates |
| --- | --- | --- | --- |
| `NitroQuake-engine` | `.github/workflows/ci.yml` | Pull requests, `main` pushes, manual dispatch | Complete engine history; host contracts; numbered i486 build; source and linked-image ISA audits; release hash guard |
| `NitroQuake` | `.github/workflows/ci-release.yml` | Pull requests, `main` pushes, manual dispatch; versioned build tags | Exact `engine.lock` checkout; pinned DJGPP bootstrap; full engine test/build gates; workspace host suite; package validation |

Both workflows use `windows-2022`, exact Python 3.14.9, full-SHA-pinned
Actions, read-only `contents` permissions for validation, and finite job
timeouts. The Windows runner's native MinGW GCC must report target
`mingw32` and version 14.2.0; the job stops if the reviewed runner image changes
that compiler. The DJGPP build components are downloaded through the engine's
versioned manifest and hash-checked bootstrap. Caches contain only those public
toolchain archives, keyed by the manifest inputs.

Engine CI clones the public workspace shallowly for cross-repository document
links, then fetches the exact event revision of the engine with complete
history. Workspace CI checks out full workspace history, runs
`benchmarks/tools/bootstrap-workspace.ps1`, and verifies that the clean engine
checkout matches the committed lock. It runs
`quake/tools/run-tests.ps1 -NoBootstrap` without skipping the release guard,
then `benchmarks/tools/run-tests.ps1 -GameRoot quake -HostOnly`.

The workspace host suite covers documentation, runner and bootstrap behavior,
parsers, synthetic fixtures, ISO structure, and packaging contracts. The engine
suite compiles the actual `i486-release` target and verifies source-level,
linked-image, and embedded runtime ISA constraints. A passing CI run is source
and build validation; it is not evidence from a physical 486 or a
game-data-backed runtime session.

## Artifact and first release

On every successful workspace build, CI creates a 14-day downloadable Actions
artifact containing:

- `NitroQuake.exe`, copied byte-for-byte from the verified `quake.exe`;
- the corresponding engine source archive from the exact `engine.lock` commit;
- a sanitized build manifest, optimization inventory, ISA audit reports,
  checksums, runtime instructions, `LICENSE`, `THIRD-PARTY-NOTICES.md`, and the
  verbatim CWSDPMI `COPYING.CWS` notice.

Before upload, the workflow checks the DOS MZ header and executable SHA-256,
requires `NitroQuake v0.999`, verifies the i486 ISA gates, matches the
manifest's build number to accepted plus rejected attempts, confirms the
source commit equals `engine.lock`, and scans the source archive for PAKs and
common Quake game-data formats. The package is built from an explicit list of
files; ignored files in a checkout are not implicitly included.

Pushing a `v0.999-build-<number>` tag starts the same build again from the tag
commit. The publishing job requires the tag number to equal the verified
manifest, requires the tag commit to be reachable from `main`, downloads the
artifact produced by that run, and checks its contents and executable hash
again. Only this job receives `contents: write`; it creates the GitHub Release
and attaches the executable, exact source archive, build evidence, and notices.
For the current inventory, the matching release tag is
`v0.999-build-888`. The workflow checks that every release tag suffix matches
the build number in the generated manifest.

The release contains no PAK, map, model, sound, demo, or captured game imagery.
Users must supply legally obtained Quake data in `id1/` and run from the game
root under DOS with a DPMI host or in DOSBox-X with DPMI support. The engine is
GPL version 2 or, at the recipient's option, any later version; the release
includes the corresponding source and retained third-party notices.

## Data and publication boundaries

The public workspace's reachable `main` history and the locked engine history
were inspected for Quake data formats. The workspace README branding images
remain because the project owner confirmed their rights for publication. The
engine source archive retains the CWSDPMI verification material with its
corresponding source and original license terms. The downloadable NitroQuake
executable does not bundle a DPMI host; the release separately includes
`COPYING.CWS` with the third-party notices.

`.gitignore` excludes local `quake/`, build output, executable outputs, game
data, runtime directories, and local captures. The two approved logo PNGs are
explicit exceptions to the generic PNG ignore rule; the approved banner SVG is
tracked separately. Git ignore rules do not replace history or artifact
inspection; the build packages only its verified staging directory.

No PAK or reference-image secrets are configured in GitHub. Public fork PRs
receive no publishing token. There is no self-hosted public runner. PAK-backed
runtime correctness, rendered-image comparisons, timedemo performance, and
physical-486 qualification remain documented maintainer procedures using
locally supplied game data; they are not reported as CI passes.

## Validation record

The ledger document-structure gate passes in the supported sibling layout
(workspace root with engine under `quake/`). The workspace host suite passes
locally with 23 gates and no failures. The workflow YAML parses and all ten
PowerShell steps pass the PowerShell parser. Successful pull-request and main
builds upload a 14-day Actions artifact; tagged releases publish the verified
package permanently. Local syntax and host-suite results are not treated as a
hosted compiler build, and no game-data-backed runtime result is claimed.

## References

- [Engine build guide](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/BUILD-DOS.md)
- [Optimization build-number policy](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/docs/optimization/policy.md)
- [Workspace repository layout](repository-layout.md)
- [Benchmark operations](../benchmarks/docs/OPERATIONS.md)
- [Physical 486 acceptance](../benchmarks/docs/PHYSICAL-486-ACCEPTANCE.md)
- [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub Actions caching](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching)
