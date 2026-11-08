# Whole-engine performance captures

Use this workflow to separate renderer costs from local-server simulation,
QuakeC, collision, client messages, audio and video transfer. It measures real
DOS timer intervals under the pinned DOSBox-X i486 profile at VGA 320×200.
It does not measure physical Intel 486 pipeline cycles or cache misses.

## Build and collect

From the workspace root, choose fresh native output names and a fresh session:

```powershell
pwsh -NoProfile -File quake/tools/build-dos.ps1 -Benchmark -CpuTarget i486 -NoBootstrap -LocalOutputDirectoryName engine-control
pwsh -NoProfile -File quake/tools/build-dos.ps1 -Benchmark -Instrumentation -CpuTarget i486 -NoBootstrap -LocalOutputDirectoryName engine-profile
python benchmarks/tools/profile-engine.py --control-build engine-control --profile-build engine-profile --output benchmarks/out/engine-profile-session
python benchmarks/tools/analyze-engine-profiles.py benchmarks/out/engine-profile-session
```

Collection requires PowerShell 7, Python and legally obtained PAKs. Reporting
additionally uses the existing Matplotlib chart dependency. Optional
`--game-root`, `--data-root` and `--tool-root` select independent checkouts and
inputs. `--workloads` selects demo1/demo2/demo3/e1m1/e1m2; `--frames` bounds each
local game, and `--runs` controls repeated controls/component captures.
Local scripts must fit a conservative 6,000-byte command-buffer budget; oversized
frame/warm-up combinations fail before staging or launching DOSBox. The default
256-frame capture and 64-frame warm-up fit this budget.

The collector launches one DOSBox process at a time. Each launch verifies the
source-bound build manifest, complete ISA audit and staged DPMI provider. It
uses fresh PAK staging, freezes runner/native hashes and rejects input/emulator
changes. Commands, results, native build manifests, runner snapshots and logs
are retained. Partial sessions are never silently counted as complete.
`sourceTreeFingerprint` pins source bytes independently of build settings. The
legacy `sourceFingerprint` field is the configuration-bound build fingerprint.

## Four complementary modes

| Mode | Purpose |
| --- | --- |
| `off` | BENCH486 control without PROFILE486 scopes or premise counters |
| `coarse` | Frame, input, game/client, server phases, renderer, video and audio; dense premise counters disabled |
| `parts` | Adds major rendering components, QuakeC and collision; dense premise counters remain disabled |
| `detailed` | Existing complete scope/counter inventory for work populations, reuse, cache management and algorithm premises |

The first repetition collects controls, coarse and component profiles. Later
repetitions rotate workload order and repeat component profiles and controls.
One detailed capture per workload/device configuration follows. Sound-off cases
cover all three demos and both local maps; local maps also run with the emulated
Sound Blaster enabled. Detailed profiling time is never advertised as release FPS.

All modes retain the existing compiled assembly implementations. Profile builds
use maintained instrumented assembly adapters where applicable. Their extra
branches/calls and layout can change cost even with dense counters disabled.

## Workload and clock contracts

The demo protocol fixes simulation delta to 0.0625, uses seeded demo playback,
sets viewsize 100, vid_mode 0, d_subdiv16 1 and r_fullbright 0, and disables
transient console notifications and external input. Demo lengths are 969,
985 and 1,090 measured frames. Lightweight frame timings are enabled equally
on control and profiled demos; their small cost is separate from PROFILE486.

Local maps use skill 1, 64 warm-up frames, then god mode, forward movement and
continuous attack. `map` already connects its local client: a second
`connect local` would disconnect and shut down that server. The native capture
requires an active server and completed client sign-on.

BENCH486 `-gamebench` fixes simulation advancement from the **first** host frame
and bypasses startup frame throttling. This prevents variable numbers of skipped
frame attempts from consuming different random values. It preserves actual
`realtime` and `Sys_FloatTime`; it does not use the synthetic `-parityclock`.
`benchprofile N` starts at the next frame boundary, seeds capture RNG, resets
existing QuakeC instruction counts and exits after exactly N completed frames.
No timing report or checksum I/O occurs inside measured frames.

Local outputs are `GAMEPROF.TXT`, `QCPROF.CSV` and, when profiling, `profile.jsn`.
The report records actual video/device format, server state, simulation time,
final framebuffer checksum and a checksum over selected numeric edict fields.
This selected-state checksum is a reproducibility diagnostic, not an exhaustive
proof of all simulation state. QuakeC CSV counts executed statements per function;
statement counts are not function CPU times, particularly for native built-ins.

Real DMA progress remains timer-driven. Audio work can change with elapsed CPU
time, and shared RNG/channel behavior can make device comparisons diverge.
Check recorded checksums and repeated spreads before treating differences as
matched overhead. Do not silently normalize away a mismatch.

## Attribution and limits

`ranked-scopes.csv` uses **exclusive self time**. Adding inclusive parent and
child times would double-count work. The analyzer subtracts each scope's
recorded timer-read floor, flags below-floor results and normalizes positive
corrected self time. It does not remove profiler bookkeeping, code-layout,
branch or data-cache effects. Compare component totals against coarse captures
and actual controls to assess that uncertainty. Dense detailed-counter timings
are supporting diagnostics, not interchangeable with low-counter component costs.

`analysis.json` records coarse categories, raw samples, checksums and observed
profiling overhead. Its Amdahl scenarios are conditional: reducing fraction
`f` of frame time by proportion `r` would change FPS by `1/(1-f*r)-1`.
They are ceilings/planning scenarios rather than achieved optimization gains.
`whole-engine-breakdown.png` and `.svg` visualize coarse attribution.

Audio includes spatialization and mixing calls from inside rendering as well as
the host audio phase. The existing host sound-spatial scope also includes
`CL_DecayLights`; disabled sound does not imply this entire category is idle.
Networking here is local loopback. CD audio, joystick calibration/polling,
serial/IPX traffic, loading and menu interaction are outside these steady-state
workloads. The source audit must distinguish inactive paths from optimized paths.

Unit checks are `python quake/tools/test-profile-coarse.py` and
`python benchmarks/tools/test-engine-profile-analysis.py`.
