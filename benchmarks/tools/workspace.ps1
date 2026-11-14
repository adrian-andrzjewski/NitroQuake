# Benchmark-side discovery. The game never imports this file.
function Resolve-NitroQuakeGameRoot {
    [CmdletBinding()]
    param([string]$GameRoot)
    if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = $env:NITROQUAKE_GAME_ROOT }
    if ([string]::IsNullOrWhiteSpace($GameRoot)) {
        $GameRoot = Join-Path (Split-Path $PSScriptRoot -Parent) '../quake'
    }
    $resolved = [IO.Path]::GetFullPath($GameRoot)
    foreach ($required in @('tools/build-dos.ps1', 'tools/build-dos-experimental.ps1',
            'tools/common.ps1', 'src/quakedef.h')) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolved $required) -PathType Leaf)) {
            throw "Not a NitroQuake game checkout: '$resolved' (missing $required). Pass -GameRoot or set NITROQUAKE_GAME_ROOT."
        }
    }
    return $resolved
}

function Get-NitroQuakeBenchmarkRoot {
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Read-BenchmarkToolchainManifest {
    [CmdletBinding()]
    param([string]$ToolsDirectory = $PSScriptRoot)
    $game = Read-ToolchainManifest -ToolsDirectory (Join-Path $script:GameRepositoryRoot 'tools')
    $benchmark = Get-Content -LiteralPath (Join-Path $ToolsDirectory 'dosbox-toolchain.json') -Raw | ConvertFrom-Json
    return [pscustomobject]@{ djgpp = $game.djgpp; dosboxX = $benchmark.dosboxX }
}
