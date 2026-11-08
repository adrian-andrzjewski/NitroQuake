# Native QuakeC interpreter comparisons

This fixture compares `PR_ExecuteProgram` against an explicit reference checkout.
It uses actual engine headers and the reference's unchanged function-entry,
function-exit, stack and error helpers. Both implementations run in one native
DJGPP DOS executable, with separate entry points and identical initial state.
No PAK files are required.

From the workspace root, provide a retained control and choose fresh output:

```powershell
git -C quake worktree add --detach D:/nq-qc-reference fd2b7a5
python benchmarks/tools/verify-qc-interpreter.py --reference-root D:/nq-qc-reference --game-root quake --output benchmarks/out/qc-interpreter-check
```

The tool needs the already installed, game-pinned DJGPP toolchain, the suite's
pinned DOSBox-X installation, PowerShell 7 and Python 3.9+. `--tool-root` selects
another installed cache. `--build-only` prepares sources, objects and the native
executable without launching DOSBox. The normal game build does not import or
depend on this tool.

## Checks and outputs

The 11,076 comparisons cover:

- All 66 opcodes with ten input/overlapping-operand variations.
- Twelve combinations of x87 precision and rounding settings.
- Forward/backward branches, nested and built-in calls, tracing, invalid calls,
  runaway execution and world-assignment errors.
- 256 deterministic mixed arithmetic/vector sequences per x87 setting, including
  overlapping operands. Individual cases include signed zero, subnormal and
  non-finite input bit patterns.

Snapshots compare complete fixture globals, edicts and function/profile counters,
as well as error, call-stack and x87 control/TOP/tag state. The shared helper prefix
and all source headers must match between checkouts; otherwise the tool rejects
the pair and requires a review of the fixture ABI. It uses the candidate builder's
resolved uninstrumented BENCH486 i486 flags for both implementations, including
any source-specific `pr_exec.c` flags.

`fixture.json` records source/compiler information, normalized header hashes, exact
flags, generated/preprocessed source, object/executable hashes and the execution-record hash. `execution.json`
records the emulator, profile and maintained DPMI-provider pins. Native outputs
and logs remain under `quake/` in the selected output directory. Existing output
and a concurrent DOSBox instance are refused.

This is differential correctness evidence for the tested inputs and compiler
profile. It does not measure FPS or replace complete game ISA audits, live local
gameplay comparisons, audio checks or release-binary smoke tests. Those checks
remain separate from this asset-free VM fixture.
