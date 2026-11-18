# Current architecture and verification boundaries

NitroQuake is a DOS software-renderer fork of Quake, tuned for 486-class
systems. The game engine and benchmark suite live in separate Git histories;
the outer repository records `quake/` as a gitlink and does not fetch its source
when cloned by itself. See the [repository layout guide](../repository-layout.md).

## Runtime shape

The game is predominantly single threaded. DOS/DPMI startup enters the host
frame loop, which coordinates commands, client work, networking, server
simulation, audio, and presentation. The server uses shared collision code and
the QuakeC interpreter. The client prepares views and calls the software
renderer, which traverses world and entity data and writes the indexed
framebuffer. VGA/VESA video and DMA audio are handled at DOS device boundaries.

Subsystem directories and public headers provide useful ownership boundaries,
but shared global state, aggregate headers, C/assembly data layouts, and legacy
calling conventions still connect engine areas. The architecture is
intentionally conservative about broad state or ABI refactors because the
target has strict memory and instruction constraints.

## Build and optimization identity

The game repository owns the supported `i486-release` and `c-reference` builds,
the pinned DJGPP toolchain, and source-bound plus linked-image i486 ISA checks.
The benchmark suite owns DOSBox-X orchestration, runtime comparisons,
parity scenarios, and reporting. Start with the game
[build guide](../../quake/BUILD-DOS.md) and the
[benchmark documentation index](../../benchmarks/docs/INDEX.md).

The console's optimization build number counts distinct accepted and rejected
optimization attempts recorded in the game ledger and its classified legacy
source. It does not count commits or benchmark runs. The supported builder
requires complete Git history and fails when it cannot classify the inventory;
the product version and source/configuration fingerprint are separate values.
The current rules and the derived count are documented in the game's
[optimization policy](../../quake/docs/optimization/policy.md).

## What current checks establish

- The i486 release build and linked-image audit establish compiler integration
  and instruction compatibility for the built executable.
- Selector and C-reference tests establish the tested configuration contracts;
  they do not prove every selector combination has full-scene parity.
- Deterministic emulator comparisons establish output equality only for their
  recorded source revisions, scenarios, and devices.
- Instrumented profiles identify where measured work occurs. Matched
  uninstrumented runs are required to accept performance changes.
- DOSBox-X is an emulator. Physical 486 timing, device behavior, and DPMI/stack
  margin require the separate hardware procedure and remain open until measured
  on a physical target.

The [history index](../history/INDEX.md) preserves earlier assessments and
their limitations. Do not read a dated audit as a fresh validation of the
current checkout.
