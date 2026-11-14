[CmdletBinding()]
param(
    [string]$GameRoot,
    [Parameter(Mandatory=$true)][string]$LocalOutputDirectoryName,
    [ValidateSet('demo1','demo2','demo3','e1m1','e1m2')][string]$Workload='demo1',
    [ValidateSet('detailed','coarse','parts','off')][string]$Mode='detailed',
    [ValidateSet('c','asm')][string]$HullCheckImplementation='asm',
    [ValidateSet('control','zerot')][string]$TextureSpanTZeroPath='control',
    [ValidateSet('control','zerot')][string]$TextureSpanTailTZeroPath='control',
    [switch]$Instrumentation,
    [switch]$Sound,
    [switch]$DiagnosticLog,
    [ValidateRange(16,4096)][int]$Frames=256,
    [ValidateRange(8,512)][int]$WarmupFrames=64,
    [int]$TimeoutSeconds=600,
    [string]$DataRoot,
    [string]$ToolRoot,
    [Parameter(Mandatory=$true)][string]$ResultJson
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$ResultJson=[IO.Path]::GetFullPath($ResultJson)
if (Test-Path -LiteralPath $ResultJson) { throw "Refusing existing result '$ResultJson'." }
if ($Mode -ne 'off' -and -not $Instrumentation) { throw 'Attribution requires -Instrumentation.' }
if ($Mode -eq 'off' -and $Instrumentation) { throw 'Use the BENCH486 build without -Instrumentation for unprofiled controls.' }
if ($Sound -and $Workload.StartsWith('demo')) { throw 'Use local-game workloads for measured audio with native device metadata.' }
$commands=@('startdemos','host_framerate 0.0625','viewsize 100','vid_mode 0','d_subdiv16 1','r_fullbright 0','con_notifytime -1')
$isDemo=$Workload.StartsWith('demo')
if (-not $isDemo) {
    # map already connects its local client; reconnecting shuts that server down.
    $commands+=@('skill 1',"map $Workload")
    $commands+=(1..$WarmupFrames | ForEach-Object {'wait'})
    $commands+=@('god','+forward','+attack',"benchprofile $Frames")
    # Capture exits itself. This guard makes a rejected capture fail promptly.
    $commands+=(1..($Frames+4) | ForEach-Object {'wait'})
    $commands+='quit'
}
$commandText=$commands -join "`r`n"
# Quake's command buffer is 8192 bytes. Leave room for startup/signon commands.
if ([Text.Encoding]::ASCII.GetByteCount($commandText) -gt 6000) {
    throw 'Local capture script exceeds the command-buffer budget; reduce Frames or WarmupFrames.'
}
$repoRoot=$script:GameRepositoryRoot
$build=Join-Path $repoRoot 'tools/build-dos-experimental.ps1'
$params=@{Benchmark=$true;CpuTarget='i486';LocalOutputDirectoryName=$LocalOutputDirectoryName;
    HullCheckImplementation=$HullCheckImplementation;
    TextureSpanTZeroPath=$TextureSpanTZeroPath;TextureSpanTailTZeroPath=$TextureSpanTailTZeroPath}
if ($Instrumentation) { $params.Instrumentation=$true }
$resolved=(& $build @params -DumpFlags | Out-String) | ConvertFrom-Json
$fingerprint=Get-BuildFingerprint -RepoRoot $repoRoot -Resolved $resolved
$sourceTreeFingerprint=Get-SourceTreeFingerprint -RepoRoot $repoRoot
$freshness=Get-BuildFreshness -Executable $resolved.executable -Fingerprint $fingerprint
if ($freshness.Stale) { throw "Build is missing or stale: $($resolved.executable). Build a fresh isolated output first." }
$verification=Assert-RunnerBuildManifest -Resolved $resolved -BuildParameters $params
$ToolRoot=Resolve-ToolRoot -ToolRoot $ToolRoot
$manifest=Read-BenchmarkToolchainManifest -ToolsDirectory $PSScriptRoot
$dosbox=Resolve-DosboxExecutable -Manifest $manifest -ToolRoot $ToolRoot -ToolsDirectory $PSScriptRoot -NoBootstrap
$DataRoot=Resolve-DataRoot -DataRoot $DataRoot -RepoRoot $repoRoot
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
$name=[IO.Path]::GetFileName($resolved.executable)
$stage=New-QuakeStaging -RepoRoot $repoRoot -StagingRoot (Join-Path $script:BenchmarkRepositoryRoot "out/engine-profile-$stamp") `
    -Executable $resolved.executable -StagedExecutableName $name -DataRoot $DataRoot -OnExistingStaging Throw -StageDpmiHost
$provider=Assert-RunnerDpmiProvider -CpuTarget i486 -BuildVerification $verification -ProviderPath (Join-Path $stage.QuakeRoot 'cwsdpmi.exe')
Write-Host "Staging: $($stage.StagingRoot)"
$commandText | Set-Content -LiteralPath (Join-Path $stage.StagedData 'autoexec.cfg') -Encoding ascii
$options='-stdvid -nojoy -nomouse -nocdaudio -forcquit'
if ($DiagnosticLog) { $options+=' -condebug' }
if (-not $Sound) { $options+=' -nosound' }
if ($Mode -eq 'coarse') { $options+=' -profilecoarse' }
if ($Mode -eq 'parts') { $options+=' -profileparts' }
if ($Mode -eq 'off') { $options+=' -profileoff' }
if (-not $isDemo) { $options+=' -gamebench' }
if ($isDemo) { $options+=" -timedemoexit -fpsstats +timedemo $Workload" }
if ([Text.Encoding]::ASCII.GetByteCount(' '+$options) -gt 126) { throw 'DOS command tail exceeds PSP capacity.' }
$batchText=@"
@echo off
set BLASTER=A220 I7 D1 H5 T6
cd \quake
$name $options
if errorlevel 1 echo 1 > RUN.EXI
if not errorlevel 1 echo 0 > RUN.EXI
exit
"@
($batchText -replace '\r?\n',"`r`n") | Set-Content -LiteralPath (Join-Path $stage.QuakeRoot 'PROFILE.BAT') -Encoding ascii
$profile=Get-DosboxProfilePath -ToolsDirectory $PSScriptRoot
$config=New-DosboxRuntimeConfig -ProfileTemplate $profile -StagingRoot $stage.StagingRoot -BatchName PROFILE.BAT -CpuTarget i486 -ConfigName dosbox-x.conf
$watch=[Diagnostics.Stopwatch]::StartNew()
$execution=Invoke-DosboxProcess -Dosbox $dosbox -ConfigPath $config -TimeoutSeconds $TimeoutSeconds -Description "Engine profile $Workload/$Mode/sound=$Sound"
$watch.Stop()
if ($execution.TimedOut -or $execution.ExitCode -ne 0) { throw "DOSBox failed or timed out; retained $($stage.StagingRoot)." }
$marker=Join-Path $stage.QuakeRoot 'RUN.EXI'
if (-not (Test-Path -LiteralPath $marker) -or (Get-Content $marker -Raw).Trim() -ne '0') { throw 'Native process did not exit successfully.' }
$reportPath=Join-Path $stage.QuakeRoot $(if ($isDemo) {'timedemo.txt'} else {'GAMEPROF.TXT'})
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Measurement report missing: capture did not complete.' }
$report=Get-Content -LiteralPath $reportPath -Raw
$match=[regex]::Match($report,'(?m)^(\d+) frames ([0-9.]+) seconds ([0-9.]+) fps')
if (-not $match.Success) { throw 'Invalid measurement report.' }
$expected=if ($isDemo) { @{demo1=969;demo2=985;demo3=1090}[$Workload] } else {$Frames}
if ([int]$match.Groups[1].Value -ne $expected) { throw 'Unexpected measured frame count.' }
if (-not $isDemo -and $report -notmatch "map $Workload width 320 height 200 server 1 ") {
    throw 'Local capture changed map, video dimensions or active-server state.'
}
if ($isDemo) {
    $timing=Get-Content -LiteralPath (Join-Path $stage.QuakeRoot 'timedemo.jsn') -Raw | ConvertFrom-Json
    if ($timing.frame_timing.width -ne 320 -or $timing.frame_timing.height -ne 200 -or
            $timing.fps.stored_frames -ne $expected -or $timing.fps.invalid_frames -ne 0 -or $timing.fps.overflow_frames -ne 0) {
        throw 'Invalid raw timing capture or actual resolution.'
    }
}
$profilePath=Join-Path $stage.QuakeRoot 'profile.jsn'
$data=$null
if ($Mode -ne 'off') {
    if (-not (Test-Path -LiteralPath $profilePath)) { throw 'Missing attribution profile.' }
    $data=Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    if ($data.profiler.stack_overflows -ne 0 -or $data.profiler.bad_leaves -ne 0) { throw 'Profiler stack integrity failed.' }
    if ($data.benchmark.demo_frames -ne $expected) { throw 'Profile frame count mismatch.' }
}
if ($Sound -and $report -notmatch 'sound 1 rate [1-9][0-9]* channels [12] bits (8|16)') { throw 'Audio device did not initialize.' }
$result=[ordered]@{schemaVersion=1;workload=$Workload;mode=$Mode;instrumentation=[bool]$Instrumentation;sound=[bool]$Sound;
    hullCheckImplementation=$HullCheckImplementation;
    textureSpanTZeroPath=$TextureSpanTZeroPath;textureSpanTailTZeroPath=$TextureSpanTailTZeroPath;
    diagnosticLog=[bool]$DiagnosticLog;
    frames=$expected;seconds=[double]::Parse($match.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture);
    fps=[double]::Parse($match.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture);hostSeconds=$watch.Elapsed.TotalSeconds;
    commands=$commands;options=$options;stagingRoot=$stage.StagingRoot;report=$report;profile=$data;
    sourceFingerprint=$fingerprint;executableSha256=(Get-FileHash $resolved.executable).Hash;
    sourceTreeFingerprint=$sourceTreeFingerprint;
    dosboxSha256=(Get-FileHash $dosbox).Hash;profileSha256=(Get-FileHash $profile).Hash;providerVerification=$provider;
    stagedData=(Get-Content -LiteralPath (Join-Path $stage.StagingRoot 'staged-data.json') -Raw | ConvertFrom-Json);
    reportPath=$reportPath;reportSha256=(Get-FileHash $reportPath).Hash;
    profilePath=$(if ($Mode -ne 'off') {$profilePath} else {$null});
    profileDataSha256=$(if ($Mode -ne 'off') {(Get-FileHash $profilePath).Hash} else {$null});
    runnerSha256=(Get-FileHash $PSCommandPath).Hash;
    buildVerification=$verification;scope='DOSBox elapsed-time attribution, not physical 486 cycles'}
New-Item -ItemType Directory -Path (Split-Path $ResultJson -Parent) -Force | Out-Null
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ResultJson -Encoding utf8
Write-Host "$Workload/$Mode/sound=$Sound : $($result.fps) FPS -> $ResultJson"
