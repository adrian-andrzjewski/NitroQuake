[CmdletBinding()]
param(
    [string]$GameRoot,
    [Parameter(Mandatory)][string]$NitroManifest,
    [string]$OriginalExecutable,
    [string]$Quake486Executable,
    [string]$DataRoot,
    [string]$ToolRoot,
    [ValidateRange(3,3)][int]$Rounds = 3,
    [string]$OutputName = ('exe-comparison-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = $script:GameRepositoryRoot
$suite = $script:BenchmarkRepositoryRoot
$tools = $PSScriptRoot
$DataRoot = Resolve-DataRoot -DataRoot $DataRoot -RepoRoot $repo
$ToolRoot = Resolve-ToolRoot -ToolRoot $ToolRoot
if ($OutputName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $OutputName.Contains('..')) { throw 'OutputName must be a simple directory name.' }
if (-not $OriginalExecutable) { $OriginalExecutable = Join-Path $suite 'baselines/QUAKE.EXE' }
if (-not $Quake486Executable) { $Quake486Executable = Join-Path $suite 'baselines/486quake.exe' }
$native = Get-Content -LiteralPath $NitroManifest -Raw | ConvertFrom-Json
if ($native.benchmarkBuild -or $native.profileBuild -or $native.isaAuditStatus -ne 'PASS' -or -not $native.sourceBoundIsa) {
    throw 'Comparison requires a normal, uninstrumented NitroQuake build with passing source-bound ISA proofs.'
}
$nativeResolved = [pscustomobject]@{ outputRoot=(Split-Path ([IO.Path]::GetFullPath($NitroManifest)) -Parent); manifest=(Split-Path $NitroManifest -Leaf); executable=$native.executable }
$null = Assert-RunnerBuildManifest -Resolved $nativeResolved -BuildParameters @{}
function Invoke-ConsoleTimedemo {
    param([string]$Dosbox, [string]$Config, [string]$DataDirectory)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Dosbox
    $info.ArgumentList.Add('-conf')
    $info.ArgumentList.Add($Config)
    $info.ArgumentList.Add('-exit')
    $info.WorkingDirectory = Split-Path $Dosbox -Parent
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'DOSBox-X did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while ($timer.Elapsed.TotalSeconds -lt 240) {
            $log = Join-Path $DataDirectory 'qconsole.log'
            $text = ''
            if (Test-Path -LiteralPath $log) {
                try { $text = [IO.File]::ReadAllText($log) } catch [IO.IOException] { }
            }
            $match = [regex]::Match($text, '(\d+) frames\s+([\d.]+) seconds\s+([\d.]+) fps')
            if ($match.Success) {
                if ([int]$match.Groups[1].Value -ne 969) { throw 'Unexpected timedemo frame count.' }
                return [pscustomobject]@{match=$match;consoleLog=$log;processId=$process.Id;hostElapsed=$timer.Elapsed.TotalSeconds}
            }
            if ($process.HasExited) { throw "DOSBox-X exited before producing a timedemo result: $($process.ExitCode)" }
            $process.WaitForExit(500) | Out-Null
        }
        throw 'Timed out waiting for the timedemo console result.'
    } finally {
        # This handle belongs only to the child created above. Timing is already
        # complete when its console result is observed; no guest-frame polling.
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $stageRoot = Split-Path (Split-Path $DataDirectory -Parent) -Parent
        [IO.File]::WriteAllText((Join-Path $stageRoot 'dosbox-stdout.log'), $stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $stageRoot 'dosbox-stderr.log'), $stderr.GetAwaiter().GetResult())
        $process.Dispose()
    }
}
$toolchain = Read-BenchmarkToolchainManifest -ToolsDirectory $tools
$dosbox = Resolve-DosboxExecutable -Manifest $toolchain -ToolRoot $ToolRoot -ToolsDirectory $tools -NoBootstrap
$profile = Get-DosboxProfilePath -ToolsDirectory $tools
$profileHash = Get-TextFileHash -Path $profile
if ($profileHash -ne '532284EA01C1A93C8B96D70FB538625B694DFAD0172BA13B9BA9C36C8FE845BA') { throw 'Unexpected DOSBox-X profile.' }
$sources = [ordered]@{
    original = [IO.Path]::GetFullPath($OriginalExecutable)
    quake486 = [IO.Path]::GetFullPath($Quake486Executable)
    nitro = [IO.Path]::GetFullPath($native.executable)
}
$expected = @{
    original = 'E0A1936400CA56E94D44D585097BD9E490035FCFB6E7D806D7E879F423928642'
    quake486 = 'CF461CFA0FEA989AA1E2E834B6D5482B7C64F3279BD7BE56C52F92752FFF429E'
    nitro = $native.executableSha256
}
foreach ($name in $sources.Keys) {
    if ((Get-FileHash -LiteralPath $sources[$name] -Algorithm SHA256).Hash -ne $expected[$name]) { throw "Unexpected input executable: $name" }
}
$root = Join-Path (Join-Path $suite 'out') $OutputName
if (Test-Path -LiteralPath $root) { throw "Refusing existing comparison output: $root" }
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -LiteralPath $NitroManifest -Destination (Join-Path $root 'nitro-build-manifest.json')
Get-BenchmarkToolingProvenance | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root 'tooling-provenance.json')
$summary = [ordered]@{
    protocol = 'Three balanced rotating rounds; all samples retained; fresh staging/config each run; ordinary clock; no per-frame instrumentation or command queue; host console-log watcher stops owned emulator after result'
    dosbox = $dosbox
    profile = $profile
    profileSha256 = $profileHash
    cpu = '486'
    fpu = '387'
    fixedCycles = 33445
    memoryMiB = 32
    demo = 'demo1'
    video = 'Each executable automatic/default 320x200 mode; identical arguments; inspect console evidence for backend'
    arguments = 'quake.exe -nosound -nocdaudio -nojoy -nomouse -condebug +exec bench.cfg'
    nitroVersion = "$($native.productVersion) $($native.productBuild)"
    inputs = $sources
    executableSha256 = $expected
    dpmiProviderSha256 = (Get-FileHash -LiteralPath (Join-Path $repo 'src/cwsdpmi.exe') -Algorithm SHA256).Hash
    gameDataSha256 = @{}
    results = @()
}
Get-ChildItem -LiteralPath ($DataRoot) -Filter 'pak*.pak' -File | ForEach-Object {
    $summary.gameDataSha256[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
}
$orders = @(@('original','quake486','nitro'), @('quake486','nitro','original'), @('nitro','original','quake486'))
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'results.json') -Encoding utf8
foreach ($round in 1..$Rounds) {
    foreach ($name in $orders[$round-1]) {
        if (@($summary.results | Where-Object { $_.round -eq $round -and $_.variant -eq $name }).Count -gt 0) { continue }
        Write-Host "Comparison round $round/$Rounds : $name"
        $stageRoot = Join-Path $root ('round-{0:00}-{1}' -f $round,$name)
        $stage = New-QuakeStaging -RepoRoot $repo -StagingRoot $stageRoot -Executable $sources[$name] -StagedExecutableName 'quake.exe' -DataRoot ($DataRoot) -StageDpmiHost
        # Empty command buffer throughout measurement. startdemos with no names
        # leaves the legacy demo loop disabled before timedemo starts.
        $commands = @('viewsize 100','startdemos','timedemo demo1')
        [IO.File]::WriteAllLines((Join-Path $stage.StagedData 'bench.cfg'), $commands, [Text.Encoding]::ASCII)
        $batch = @('@echo off','cd \quake','echo started > boot.txt','quake.exe -nosound -nocdaudio -nojoy -nomouse -condebug +exec bench.cfg','echo completed > done.txt','exit')
        [IO.File]::WriteAllLines((Join-Path $stage.QuakeRoot 'bench.bat'), $batch, [Text.Encoding]::ASCII)
        $config = New-DosboxRuntimeConfig -ProfileTemplate $profile -StagingRoot $stageRoot -BatchName 'bench.bat' -CpuTarget i486 -ConfigName 'dosbox-x.conf'
        $run = Invoke-ConsoleTimedemo -Dosbox $dosbox -Config $config -DataDirectory $stage.StagedData
        $match = $run.match
        $result = [ordered]@{round=$round;variant=$name;consoleLog=$run.consoleLog;processId=$run.processId;termination='owned emulator stopped after valid console result';hostElapsed=$run.hostElapsed;fps=$null;frames=969;seconds=$null;rawResult=$match.Value;precision='console output rounded to 0.1'}
        $result.seconds = [double]::Parse($match.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
        $result.fps = [double]::Parse($match.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)
        $summary.results += [pscustomobject]$result
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'results.json') -Encoding utf8
        Write-Host "Recorded $name : $($match.Value)"
    }
}
& python (Join-Path $PSScriptRoot 'verify-executable-comparison.py') $root
if ($LASTEXITCODE -ne 0) { throw 'Comparison evidence verification failed.' }
Write-Host "Comparison evidence: $root"
