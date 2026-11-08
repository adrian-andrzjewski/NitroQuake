[CmdletBinding()]
param([string]$GameRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$game = $script:GameRepositoryRoot
$suite = $script:BenchmarkRepositoryRoot
if ((Resolve-NitroQuakeGameRoot -GameRoot $game) -ne $game) { throw 'Explicit game discovery failed.' }
$manifest = Read-BenchmarkToolchainManifest
if (-not $manifest.djgpp.compiler -or -not $manifest.dosboxX.executable) { throw 'Composed manifest is incomplete.' }
$compilerManifest = Read-ToolchainManifest -ToolsDirectory (Join-Path $game 'tools')
if ($compilerManifest.PSObject.Properties.Name -contains 'dosboxX') { throw 'Standalone game manifest depends on emulator.' }

foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "PowerShell parse failure in $($file.Name): $parseErrors" }
}
$testRoot = Join-Path $suite ('out/workspace-test-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $testRoot 'data'
New-Item -ItemType Directory -Path $data -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $data 'pak0.pak'), [byte[]]@(80,65,67,75))
[IO.File]::WriteAllText((Join-Path $data 'autoexec.cfg'), 'quit')
$exe = Join-Path $testRoot 'fixture.exe'
[IO.File]::WriteAllBytes($exe, [byte[]]@(77,90))
$stagePath = Join-Path $testRoot 'stage'
$stage = New-QuakeStaging -RepoRoot $game -StagingRoot $stagePath -Executable $exe -StagedExecutableName 'quake.exe' -DataRoot $data
if (Test-Path -LiteralPath (Join-Path $stage.StagedData 'autoexec.cfg')) { throw 'Staging copied user configuration.' }
if ((Get-FileHash (Join-Path $stage.StagedData 'pak0.pak')).Hash -ne (Get-FileHash (Join-Path $data 'pak0.pak')).Hash) { throw 'Staging changed game data.' }
try {
    New-QuakeStaging -RepoRoot $game -StagingRoot $game -Executable $exe -StagedExecutableName 'quake.exe' -DataRoot $data -OnExistingStaging Overwrite
    throw 'Unexpected acceptance of an unsafe staging path.'
} catch {
    if ($_.Exception.Message -notlike 'Staging must be a child*') { throw }
}
try {
    New-QuakeStaging -RepoRoot $game -StagingRoot $stagePath -Executable $exe -StagedExecutableName 'quake.exe' -DataRoot $data
    throw 'Unexpected overwrite of existing run.'
} catch {
    if ($_.Exception.Message -notlike 'Staging path already exists*') { throw }
}
# Force the cross-volume/hardlink-limit fallback without depending on drive layout.
function New-Item {
    param($ItemType, $Path, $Value, [switch]$Force, $ErrorAction)
    if ($ItemType -eq 'HardLink') { throw [IO.IOException]::new('Simulated unsupported hardlink') }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
}
try {
    $copyStage = New-QuakeStaging -RepoRoot $game -StagingRoot (Join-Path $testRoot 'copy-stage') -Executable $exe -StagedExecutableName 'quake.exe' -DataRoot $data
    $copyRecord = Get-Content -LiteralPath (Join-Path $copyStage.StagingRoot 'staged-data.json') -Raw | ConvertFrom-Json
    if (@($copyRecord)[0].storage -ne 'copy') { throw 'Copy fallback was not recorded.' }
} finally { Remove-Item Function:New-Item }
Write-Host "PASS: explicit game discovery, independent manifests, PS parsing, isolated staging, copy fallback and path guards ($testRoot)"
