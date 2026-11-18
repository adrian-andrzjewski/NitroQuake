# Native collision differential fixtures

`tools/verify-collision.py` rebuilds two collision comparisons from explicit
reference and candidate source checkouts, using the supported builder's resolved
BENCH486 i486 flags and the installed pinned DJGPP compiler. No game PAKs are
required. The game build has no dependency on this Python driver or its fixtures.

From the workspace root, retain the control and choose fresh output:

```powershell
git -C quake worktree add --detach D:/nq-collision-reference 682998a8a3eb
python benchmarks/tools/verify-collision.py --reference-root D:/nq-collision-reference --game-root quake --output benchmarks/out/collision-native-check --wait-for-slot 1800
```

Windows, Python 3.9+, PowerShell 7, the installed game-pinned DJGPP toolchain and
suite-pinned DOSBox-X are required. `--tool-root` selects another installed cache;
the driver does not bootstrap tools. `--build-only` generates and compiles both
executables without launching DOSBox. `--timeout` bounds each native run and
compiler call; `--wait-for-slot` optionally waits on a busy DOSBox slot, retaining
each refused-launch log. By default an occupied slot fails promptly.

## Coverage

The **18,432 SV_Move cases** compare extracted reference/candidate `SV_Move` and
`SV_MoveBounds`, with explicit native trace/consumer stubs. They compare the full
124-byte clip at the consumer and full 52-byte returned trace, helper arguments,
three movement types, null/non-null passedict, bounds and special float patterns,
two trace outcomes, distinct stack poison, and twelve x87 precision/rounding modes.
CW, TOP and tag state are checked.

The **6,912 area-clipper cases** compile the actual old/new assembly bodies, with
explicit native entity-trace stubs. Balanced and deep left/right traversal layouts
exercise filters, owner relationships, trace merging, errors, helper call order
and bounds. Snapshots compare the complete clip, node counters, preserved
EBP/EBX/ESI/EDI, ESP, DF, CW/TOP/tag and two preloaded FPU values. The fixture
requires a nonzero node count so disabled benchmark counters cannot masquerade
as a successful counter comparison.

The compiler profile retains `-ffast-math`. Special float patterns are differential
tests of this profile, rather than promises of strict IEEE arithmetic. These
fixtures isolate the tested interfaces with helper stubs. Actual BSP helpers,
gameplay, images, audio, complete game ISA compatibility and performance remain
separate acceptance checks.

## Inputs and retained records

All source headers must match after line-ending normalization. The driver refuses
existing output and output inside game source/tool inputs, and checks source/header
stability while compiling. It resolves common flags from the candidate builder;
source-specific world and assembly flags are included.

`fixture.json` records compiler/toolchain/driver pins, source/header hashes, flags,
per-unit expected counts and generated/preprocessed source, object/executable
hashes. Unit directories (`move/`, `cliplinks/`) retain executables, runtime logs,
native results and `execution.json`. Execution-record hashes bind those records
to the top-level result; staged executable/provider bytes are checked against
their build/runtime pins. The shared native runner pins DOSBox, the CPU profile
and maintained DPMI provider. A `prepared` build-only record is not a runtime pass.

The [collision optimization record](I486-COLLISION-OPTIMIZATION-20261109.md)
connects the native comparisons to full-engine timing and release validation.
