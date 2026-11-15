# Physical 486 acceptance procedure

## Status

Physical-hardware qualification is pending access to a real 486 system. DOSBox,
86Box, PCem and other emulators can screen changes, but do not satisfy this
acceptance gate or support a physical-486 performance claim.

## Acceptance target

Use the same physical machine, display mode, DOS setup, DPMI host, game data and
resident software for the control and candidate. Record enough configuration to
reproduce the result:

- CPU vendor, model, stepping and clock; motherboard and BIOS revision; FPU and
  cache configuration.
- Installed and available conventional, extended and expanded memory; DOS
  version; memory managers and TSRs; DPMI host name, version and options.
- Video adapter, monitor mode and refresh settings; audio device state; power
  supply or clock-control settings that can affect the CPU.
- Build source revision, renderer profile ID and SHA-256, full build-manifest
  SHA-256, executable SHA-256, DPMI-provider SHA-256 and both PAK SHA-256 values.

Build the normal `i486-release` executable with
`quake/tools/build-dos.ps1 -Configuration i486-release -CpuTarget i486` and
retain its manifest for the boot and smoke check. For timedemo parity and
performance, build an uninstrumented `BENCH486` executable from the same
release selector set. Load the selectors from the committed profile instead of
maintaining a second list in the benchmark command:

```powershell
$releaseProfile = Get-Content quake/tools/renderer-profiles/i486-asm-selectable-current.json -Raw | ConvertFrom-Json
$build = @{
    Benchmark = $true
    CpuTarget = 'i486'
    NoBootstrap = $true
    OptimizationProfile = 'aggressive'
    TextureAxisCacheEntries = 256
    LocalOutputDirectoryName = 'physical-486-control'
}
foreach ($selector in $releaseProfile.selectors.PSObject.Properties) {
    $build[$selector.Name] = [string]$selector.Value
}
$controlBuild = $build.Clone()
$controlBuild.LocalOutputDirectoryName = 'physical-486-control'
$controlBuild.TextureSpanTZeroPath = 'control'
$controlBuild.TextureSpanTailTZeroPath = 'control'
& quake/tools/build-dos-experimental.ps1 @controlBuild

$candidateBuild = $build.Clone()
$candidateBuild.LocalOutputDirectoryName = 'physical-486-zerot'
$candidateBuild.TextureSpanTZeroPath = 'zerot'
$candidateBuild.TextureSpanTailTZeroPath = 'zerot'
& quake/tools/build-dos-experimental.ps1 @candidateBuild
```

Build the control and candidate into separate output directories with the same
toolchain and settings; change only the implementation under test. For a
source-code candidate, build each recorded source revision separately. The
manifest must report `cpuTarget=i486`, `isaAuditStatus=PASS`, the expected
source revision and the intended selectors. Do not use an instrumented
`PROFILE486` executable for timing.

## Correctness run

Install each build in a separate directory with identical, legally obtained
`id1/pak0.pak` and `id1/pak1.pak` files. Keep the same `autoexec.cfg` for each;
use the established 320x200 timedemo settings:

```text
host_framerate 0.0625
viewsize 100
vid_mode 0
d_subdiv16 1
r_fullbright 0
con_notifytime -1
```

First confirm the normal release executable starts and renders on the machine.
Then run each target `BENCH486` build three times per demo with deterministic
color/depth checksums enabled:

```dos
QBENCH.EXE -timedemoexit -framechecksums -zchecksums -parityclock -nosound -nocdaudio +timedemo demo1
```

Repeat for `demo2` and `demo3`. Retain `timedemo.txt` and
`framechecksums.txt` from every run. Each replay must complete the expected
demo frame count, report a framebuffer checksum, report no checksum overflow,
and match the control's full color and Z checksum streams byte for byte. The
fixed parity clock is for correctness comparison only; do not use those runs
for timing.

## Local-game workloads

The renderer also needs local-game coverage because a demo path and active map
play can rank renderer work differently. For each build, capture `e1m1` and
`e1m2` with the same 320x200 settings above, sound disabled, 64 warm-up frames,
256 measured frames and `host_framerate 0.0625`. The tested command sequence is
the one in [`engine-profile-dos.ps1`](../tools/engine-profile-dos.ps1):

```powershell
$commands = @(
    'startdemos',
    'host_framerate 0.0625',
    'viewsize 100',
    'vid_mode 0',
    'd_subdiv16 1',
    'r_fullbright 0',
    'con_notifytime -1',
    'skill 1',
    'map e1m1'
) + (1..64 | ForEach-Object { 'wait' }) + @(
    'god',
    '+forward',
    '+attack',
    'benchprofile 256'
) + (1..260 | ForEach-Object { 'wait' }) + @('quit')
$commands | Set-Content -LiteralPath autoexec.cfg -Encoding ascii
```

Use the same script with `map e1m2` for the second workload. Start a fresh game
process for every capture and retain three correctness captures per map and
build in `GAMEPROF.TXT`. Each run must report the requested map, 320x200
resolution, 256 measured frames, and matching simulation and framebuffer
checksums across control and candidate. `GAMEPROF` timings are uninstrumented;
do not enable `PROFILE486` or profiler modes.

## Timing run

Use the same fixed machine configuration and the same uninstrumented
`BENCH486` builds. Disable sound and live input; do not pass `-fpsstats`,
`-framechecksums` or `-parityclock` on timing runs. Warm each build with one
complete demo, then record at least five alternating control/candidate pairs
per target demo. Rotate the order between pairs to reduce warm-up and drift
bias. Capture the `frames`, `seconds`, `fps` and framebuffer checksum from each
`timedemo.txt`, along with the executable hash and pair number.

For local-game coverage, use the same fresh-process `e1m1`/`e1m2` command
sequence above and record at least five alternating pairs per map from
`GAMEPROF.TXT`.

All timing runs must complete the same frame count and produce the same final
framebuffer checksum. Report every raw sample, the paired ratios, per-demo
medians and run-to-run spread. Follow the renderer's current acceptance rule:
require a positive pooled mean FPS from at least three matched uninstrumented
runs per variant with matching output and strict ISA gates; the physical screen
uses five alternating pairs for stronger coverage. There is no minimum
percentage threshold. See the
[current renderer acceptance rule](../../quake/docs/OPTIMIZATION-PLAN.md#current-performance-acceptance-2026-10-21).
Report each workload separately and call out regressions; a positive pooled
result does not support a claim of improvement on every map. If pair results
are inconsistent or timer resolution obscures the sign, add alternating pairs
and keep the claim scoped to workloads with repeatable evidence. Do not infer
whole-game or all-map performance from one demo.

For a change affecting renderer stack usage or warp fallback behavior, also
retain the build's generated stack-budget report and the runtime DJGPP stack
bounds/headroom report from the physical run. The normal renderer must reject
insufficient capacity before entering its large frames; fallback warp must run
only when its generated requirement fits the available bounds. Run the
allocated-buffer, fallback, insufficient-capacity and waterwarp-disabled cases
from the [renderer stack procedure](../../quake/docs/renderer-assembly/warp-scratch.md).
Do not use a stack-fill high-water scan as a substitute for those bounds.

## Evidence bundle

Keep a non-committed result directory under `benchmarks/out/physical-486-<machine-id>/`
containing:

- The completed machine-configuration record and exact DOS startup files.
- Control and candidate executable manifests, binaries' SHA-256 values, and
  DPMI-provider and PAK hashes.
- Every raw `timedemo.txt`, `framechecksums.txt` and
  `framezchecksums.txt`, clearly named by build, demo, run and pair.
- Every raw `GAMEPROF.TXT` from the `e1m1` and `e1m2` local-game runs, plus the
  exact `autoexec.cfg` used for those captures.
- A CSV with one timing sample per row and a short summary with the paired
  medians, spread, parity result and pass/inconclusive decision.

Until this evidence comes from a physical 486 and passes the gates above, keep
DOSBox-X results labeled as emulator measurements and leave physical-hardware
qualification pending.
