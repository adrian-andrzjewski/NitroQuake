# Physical 486 acceptance procedure

## Status

Physical-hardware qualification is pending access to a real 486 system. DOSBox,
86Box, PCem and other emulators can screen changes, but do not satisfy this
acceptance gate or support a physical-486 performance claim.

## Pinned workstation preflight (2026-11-17)

The current i486 release artifact and base-game data are pinned here to reduce
setup work when a physical target is available. This was a host build only; it
does not satisfy any target-machine, startup, rendering, device, timing or DPMI
stack acceptance requirement.

| Item | Recorded value |
| --- | --- |
| Game revision | `432ae1afaf00e3551d6564ad94fcd4263c5708a6` |
| Product build ID | `432ae1afaf00-8153186631e7` |
| Build command | `quake/tools/build-dos.ps1 -Configuration i486-release -CpuTarget i486 -NoBootstrap -LocalOutputDirectoryName physical-486-preflight-432ae1a` |
| Executable | `quake/out/local-physical-486-preflight-432ae1a/quake.exe` |
| Executable SHA-256 | `2165ab8f06a8f387977492ee36a14b31f1e4ee4d846749afd331dcc182eb26a3` |
| Build manifest SHA-256 | `f06deaf51d678ea3dc2da7d05e1283e90fe43c12a7ae973ba0eee1d3202d9ee9` |
| Renderer profile | `i486-asm-selectable-current` |
| Renderer profile SHA-256 | `ccf865d39db35a93b66571a65e3e1555b2eb5e4350fe35d593bcb8e517ff4759` |
| Workstation CWSDPMI SHA-256 | `ff3501b50bcf320e6615e025bdff94261a087f83212858d4b12e42c19c7e3883` |
| `id1/pak0.pak` SHA-256 | `35a9c55e5e5a284a159ad2a62e0e8def23d829561fe2f54eb402dbc0a9a946af` |
| `id1/pak1.pak` SHA-256 | `94e355836ec42bc464e4cbe794cfb7b5163c6efa1bcc575622bb36475bf1cf30` |
| Generated stack budget | PASS; normal `172868 + 128 * world_depth`; fallback `236884 + 128 * world_depth` |
| Complete linked i486 ISA gate | PASS; 166,287 relocated instructions, 529 startup rows and 9,207 provider instructions; zero exemptions |

The build output and executable are ignored local files under `quake/out/`.
Rebuild from the recorded revision if the checkout or configuration changes.
Record the target's machine, BIOS, FPU, memory, video, audio and DPMI details
alongside these values during the physical run, including the hash of the DPMI
provider actually used on the target.

The uninstrumented BENCH486 pair specified below was also built from the same
revision, using the committed release selectors and changing only the two
texture-span T-zero selectors. Both manifests record the same source-tree hash,
`62e839885135c33c074624f6b52901d88ab2d63bec881489ca8c9de116532453`,
`benchmarkBuild=true`, `profileBuild=false`, `isaAuditStatus=PASS`, and the
generated stack formulas above:

| Configuration | Product build ID | Executable SHA-256 | Manifest SHA-256 |
| --- | --- | --- | --- |
| Control (`control` / `control`) | `432ae1afaf00-a5e78aed24e6` | `b0ca76a5e0e286431c7ac3e624756f1fbe01397d5cb28f3444c2282d039b8a55` | `0c6ed16f4bbdd07f7b7d1d9bdd2454135b32a25fe09d84d354762abb92aa99c6` |
| Candidate (`zerot` / `zerot`) | `432ae1afaf00-bc3c3cecfb7e` | `58cbe190d2059f945ee96524daa31a7e379bbe452919ddcec5ca96dd8843f905` | `dbc48be9d65eb02a7c2df2374129909022f4a8ac3801404cd17b68ca05e32088` |

Their ignored output directories are
`quake/out/local-physical-486-control-432ae1a/` and
`quake/out/local-physical-486-zerot-432ae1a/`. These builds are ready for the
documented physical correctness and timing procedure.

One emulator-only correctness preflight was run for each build on demo1, demo2
and demo3 using DOSBox-X 2026.08.31, `dosbox-x-486-high.conf` (normalized
profile SHA-256
`532284ea01c1a93c8b96d70fb538625b694dfad0172ba13b9ba9c36c8fe845ba`), and
CWSDPMI SHA-256
`ff3501b50bcf320e6615e025bdff94261a087f83212858d4b12e42c19c7e3883`. Each
replay used `-framechecksums -zchecksums -parityclock` with sound disabled and
the renderer settings above. The `compare-rendering.py` framebuffer and depth
comparisons matched every record, with no mismatches; captured frame counts and
final framebuffer checksums were:

| Demo | Records per stream | Final framebuffer checksum | Framebuffer stream SHA-256 | Depth stream SHA-256 |
| --- | ---: | ---: | --- | --- |
| demo1 | 970 | `1047377823` | `3bc7d80f12b90de7031b4d9cf4ca9349ceec9d10dbde482f8917bbaf46412768` | `4d995848bef742f2e2b8362a978f21ab3f4a4885acb95794dac512964135fd37` |
| demo2 | 986 | `1887495667` | `7750444bb8f2b05a224a1cccd06d0fa7b8544cb4eff949a96f120e9a6df8d999` | `cd43ea9d321a0761966aa40505134388c5996c1778de2f13f4681dca543e30a8` |
| demo3 | 1091 | `3722973491` | `6479268b7fa33dafc0d4280d769f3ff57fa77b54addc48e4004081bb52a4b996` | `7d76499b5e42697d3ff172b910795ae5f0afc7e3ef67321af5cf2e5626846f4c` |

The hashes shown are for the control streams; candidate streams have the same
hashes. All color checksum captures reported zero overflow, and the timedemo
runner verified that each depth stream had the same number of records. The raw
control/candidate run directories are `benchmarks/out/dos-timedemo-20261117-182806/`
and `...183052/` for demo1, `...183638/` and `...183839/` for demo2, and
`...184040/` and `...184258/` for demo3. These are single fixed-clock
correctness captures, not timing samples; local-map checks, repeated runs,
physical startup/devices and runtime stack bounds remain pending on a real
486/DPMI system.

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
[current renderer acceptance rule](../../quake/docs/optimization/policy.md).
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
