[CmdletBinding()]
param([switch]$Force, [string]$ToolRoot, [string]$GameRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'workspace.ps1')
$game = Resolve-NitroQuakeGameRoot -GameRoot $GameRoot
# One hash-verifying artifact installer; each repository owns its own definition.
& (Join-Path $game 'tools/bootstrap-dos.ps1') -ToolRoot $ToolRoot -Force:$Force `
    -ManifestPath (Join-Path $PSScriptRoot 'dosbox-toolchain.json')
