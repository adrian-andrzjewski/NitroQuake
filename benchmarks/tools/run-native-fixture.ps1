[CmdletBinding()]
param(
    [string]$GameRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ExpectedResultPrefix,
    [string]$ToolRoot,
    [ValidateRange(30,1800)][int]$TimeoutSeconds=600
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root=[IO.Path]::GetFullPath($OutputRoot)
$runtime=Join-Path $root 'quake'
if(Test-Path -LiteralPath $runtime){throw 'Fixture runtime directory already exists; choose a fresh output.'}
if(-not(Test-Path -LiteralPath (Join-Path $root 'fixture.exe'))){throw 'Build fixture.exe before launching.'}
$ToolRoot=Resolve-ToolRoot -ToolRoot $ToolRoot
$toolchain=Read-BenchmarkToolchainManifest -ToolsDirectory $PSScriptRoot
$dosbox=Resolve-DosboxExecutable -Manifest $toolchain -ToolRoot $ToolRoot -ToolsDirectory $PSScriptRoot -NoBootstrap
$fixtureProfilePath=Get-DosboxProfilePath -ToolsDirectory $PSScriptRoot
if((Get-TextFileHash -Path $fixtureProfilePath) -ne '532284EA01C1A93C8B96D70FB538625B694DFAD0172BA13B9BA9C36C8FE845BA'){
    throw 'Native fixture requires the pinned i486 DOSBox profile.'
}
$provider=Join-Path $script:GameRepositoryRoot 'src/cwsdpmi.exe'
$providerManifest=Join-Path $script:GameRepositoryRoot 'tools/isa-provider-reference/manifest.json'
$providerPin=Get-Content -LiteralPath $providerManifest -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $provider).Hash -ne $providerPin.candidateSha256){throw 'DPMI provider does not match its maintained source manifest.'}
if(@(Get-Process dosbox-x -ErrorAction SilentlyContinue).Count){throw 'DOSBox is occupied; refusing a concurrent fixture launch.'}
New-Item -ItemType Directory -Path $runtime | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'fixture.exe') -Destination $runtime
Copy-Item -LiteralPath $provider -Destination $runtime
$batch=(@('@echo off','fixture.exe > CONSOLE.TXT','exit') -join "`r`n")+"`r`n"
[IO.File]::WriteAllText((Join-Path $runtime 'FIXTURE.BAT'),$batch,[Text.Encoding]::ASCII)
$config=New-DosboxRuntimeConfig -ProfileTemplate $fixtureProfilePath -StagingRoot $root -BatchName FIXTURE.BAT -CpuTarget i486 -ConfigName dosbox-x.conf
$execution=Invoke-DosboxProcess -Dosbox $dosbox -ConfigPath $config -TimeoutSeconds $TimeoutSeconds -Description 'Native differential fixture'
$reportPath=Join-Path $runtime 'RESULT.TXT'
if($execution.TimedOut -or $execution.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $reportPath)){
    throw 'Native fixture did not complete; retained runtime and emulator logs.'
}
$report=Get-Content -LiteralPath $reportPath -Raw
if(-not $report.StartsWith($ExpectedResultPrefix,[StringComparison]::Ordinal)){
    Get-Content -LiteralPath (Join-Path $runtime 'CONSOLE.TXT') -ErrorAction SilentlyContinue
    throw "Native fixture rejected its comparisons: $report"
}
[ordered]@{schemaVersion=1;status='PASS';report=$report;execution=$execution;
    dosboxSha256=(Get-FileHash $dosbox).Hash;profileSha256=(Get-TextFileHash $fixtureProfilePath);
    providerSha256=(Get-FileHash $provider).Hash;providerManifestSha256=(Get-FileHash $providerManifest).Hash;
    reportSha256=(Get-FileHash $reportPath).Hash;runnerSha256=(Get-FileHash $PSCommandPath).Hash;
    scope='Differential correctness only; complete game ISA and performance gates remain separate.'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'execution.json') -Encoding utf8
Write-Host $report.Trim()
