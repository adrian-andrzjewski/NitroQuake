<#
.SYNOPSIS
    Check the NitroQuake outer checkout, game gitlink and local tool availability.
.DESCRIPTION
    This is a read-only check. It does not fetch, reset, update, bootstrap or
    replace either repository or any tool installation.
#>
[CmdletBinding()]
param(
    [string]$OuterRoot,
    [string]$GameRoot,
    [string]$ToolRoot,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OuterRoot)) {
    $OuterRoot = Join-Path $PSScriptRoot '../..'
}
$OuterRoot = [IO.Path]::GetFullPath($OuterRoot)
if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Join-Path $OuterRoot 'quake'
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $ToolRoot = ''
    }
    else {
        $ToolRoot = Join-Path $localAppData '486quake/tools'
    }
}
if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
    $ToolRoot = [IO.Path]::GetFullPath($ToolRoot)
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
if ($null -eq $gitCommand) { throw 'Git is required to inspect repository revisions and the gitlink.' }

function Invoke-WorkspaceGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    $env:GIT_OPTIONAL_LOCKS = '0'
    try {
        $output = @(& $script:gitCommand.Source -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousOptionalLocks) {
            Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue
        }
        else {
            $env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks
        }
    }
    if ($exitCode -ne 0) {
        throw "git -C '$RepositoryPath' $($Arguments -join ' ') failed: $($output -join ' ')"
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Get-RepositoryRecord {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        throw "Repository directory does not exist: '$RepositoryPath'."
    }
    $topLevel = Invoke-WorkspaceGit -RepositoryPath $RepositoryPath -Arguments @('rev-parse', '--show-toplevel')
    $revision = Invoke-WorkspaceGit -RepositoryPath $RepositoryPath -Arguments @('rev-parse', '--verify', 'HEAD')
    if ($revision -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw "Git returned an invalid HEAD revision for '$RepositoryPath'."
    }
    $branch = Invoke-WorkspaceGit -RepositoryPath $RepositoryPath -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    $statusOutput = Invoke-WorkspaceGit -RepositoryPath $RepositoryPath -Arguments @('status', '--porcelain=v1', '--untracked-files=normal')
    $dirtyLines = @($statusOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $isShallow = (Invoke-WorkspaceGit -RepositoryPath $RepositoryPath -Arguments @('rev-parse', '--is-shallow-repository')) -eq 'true'

    return [pscustomobject]@{
        path = [IO.Path]::GetFullPath($topLevel)
        revision = $revision.ToLowerInvariant()
        branch = $branch
        dirty = ($dirtyLines.Count -gt 0)
        changes = $dirtyLines
        shallow = $isShallow
    }
}

function Get-ManifestToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ManifestProperty,
        [Parameter(Mandatory = $true)][string]$ToolRootPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $definition = $manifest.$ManifestProperty
        if ($null -eq $definition -or
            [string]::IsNullOrWhiteSpace([string]$definition.installDirectory)) {
            return $null
        }
        $definitionProperties = @($definition.PSObject.Properties.Name)
        $relativeExecutable = if ($definitionProperties -contains 'compiler') {
            [string]$definition.compiler
        } elseif ($definitionProperties -contains 'executable') {
            [string]$definition.executable
        } else {
            ''
        }
        if ([string]::IsNullOrWhiteSpace($relativeExecutable)) { return $null }
        $installPath = Join-Path $ToolRootPath $definition.installDirectory
        $toolPath = Join-Path $installPath $relativeExecutable
        return [pscustomobject]@{
            path = [IO.Path]::GetFullPath($toolPath)
            version = [string]$definition.version
        }
    }
    catch {
        return $null
    }
}

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $output = @(& $Command.Source @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { return 'version unavailable' }
    return (($output | ForEach-Object { [string]$_ }) -join ' ').Trim()
}

$outer = Get-RepositoryRecord -RepositoryPath $OuterRoot
$game = Get-RepositoryRecord -RepositoryPath $GameRoot
$gitlinkOutput = Invoke-WorkspaceGit -RepositoryPath $OuterRoot -Arguments @('ls-tree', 'HEAD', '--', 'quake')
$indexOutput = Invoke-WorkspaceGit -RepositoryPath $OuterRoot -Arguments @('ls-files', '--stage', '--', 'quake')
$gitlinkMatch = [regex]::Match($gitlinkOutput, '^160000 commit ([0-9a-fA-F]{40,64})\tquake$')
$indexMatch = [regex]::Match($indexOutput, '^160000 ([0-9a-fA-F]{40,64}) 0\tquake$')
$recordedGitlink = if ($gitlinkMatch.Success) { $gitlinkMatch.Groups[1].Value.ToLowerInvariant() } else { $null }
$indexedGitlink = if ($indexMatch.Success) { $indexMatch.Groups[1].Value.ToLowerInvariant() } else { $null }
$gitlinkMatchesHead = ($null -ne $recordedGitlink -and $recordedGitlink -eq $game.revision)
$gitlinkMatchesIndex = ($null -ne $indexedGitlink -and $indexedGitlink -eq $game.revision)

$tools = @()
$gitVersion = Get-CommandVersion -Command $gitCommand -Arguments @('--version')
$tools += [pscustomobject]@{
    name = 'Git'; purpose = 'workspace revision and gitlink checks'; requiredForBuild = $true
    status = 'available'; version = $gitVersion; path = $gitCommand.Source
}

$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
$pwshVersionText = 'not installed'
if ($null -ne $pwshCommand) {
    $pwshVersionOutput = @(& $pwshCommand.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $pwshVersionText = (($pwshVersionOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
    }
}
$pwshVersionMatch = [regex]::Match($pwshVersionText, '^\s*(\d+)\.(\d+)')
$pwshReady = ($pwshVersionMatch.Success -and [int]$pwshVersionMatch.Groups[1].Value -ge 7)
$tools += [pscustomobject]@{
    name = 'PowerShell 7'; purpose = 'build and verification scripts'; requiredForBuild = $true
    status = $(if ($pwshReady) { 'available' } else { 'missing' })
    version = $pwshVersionText
    path = $(if ($null -ne $pwshCommand) { $pwshCommand.Source } else { $null })
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) { $pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue }
$pythonVersionText = if ($null -ne $pythonCommand) {
    Get-CommandVersion -Command $pythonCommand -Arguments @('--version')
} else { 'not installed' }
$pythonVersionMatch = [regex]::Match($pythonVersionText, 'Python\s+(\d+)\.(\d+)(?:\.(\d+))?')
$pythonReady = $false
if ($pythonVersionMatch.Success) {
    $pythonMajor = [int]$pythonVersionMatch.Groups[1].Value
    $pythonMinor = [int]$pythonVersionMatch.Groups[2].Value
    $pythonReady = ($pythonMajor -gt 3 -or ($pythonMajor -eq 3 -and $pythonMinor -ge 9))
}
$tools += [pscustomobject]@{
    name = 'Python 3.9+'; purpose = 'build identity, source checks and benchmark host tools'; requiredForBuild = $true
    status = $(if ($pythonReady) { 'available' } elseif ($null -eq $pythonCommand) { 'missing' } else { 'version-too-old' })
    version = $pythonVersionText
    path = $(if ($null -ne $pythonCommand) { $pythonCommand.Source } else { $null })
}
$matplotlibStatus = 'optional-missing'
$matplotlibVersion = $null
if ($null -ne $pythonCommand) {
    try {
        $matplotlibOutput = @(& $pythonCommand.Source -B -c 'import importlib.metadata; print(importlib.metadata.version("matplotlib"))' 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $matplotlibStatus = 'available'
            $matplotlibVersion = (($matplotlibOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
        }
    }
    catch { }
}
$tools += [pscustomobject]@{
    name = 'Matplotlib'; purpose = 'optional chart generation'; requiredForBuild = $false
    status = $matplotlibStatus; version = $matplotlibVersion
    path = $(if ($null -ne $pythonCommand) { $pythonCommand.Source } else { $null })
}

if ([string]::IsNullOrWhiteSpace($ToolRoot)) { $ToolRootForChecks = '' } else { $ToolRootForChecks = $ToolRoot }
$gameTool = Get-ManifestToolPath -ManifestPath (Join-Path $GameRoot 'tools/dos-toolchain.json') `
    -ManifestProperty 'djgpp' -ToolRootPath $ToolRootForChecks
$gameObjdumpPath = $null
try {
    $gameToolManifest = Get-Content -LiteralPath (Join-Path $GameRoot 'tools/dos-toolchain.json') -Raw | ConvertFrom-Json
    $gameObjdumpPath = Join-Path (Join-Path $ToolRootForChecks $gameToolManifest.djgpp.installDirectory) $gameToolManifest.djgpp.objdump
} catch { }
$djgppAvailable = ($null -ne $gameTool -and (Test-Path -LiteralPath $gameTool.path -PathType Leaf) -and
    $null -ne $gameObjdumpPath -and (Test-Path -LiteralPath $gameObjdumpPath -PathType Leaf))
$tools += [pscustomobject]@{
    name = 'DJGPP compiler and objdump'; purpose = 'DOS executable build and ISA verification'; requiredForBuild = $true
    status = $(if ($djgppAvailable) { 'available' } elseif ($null -eq $gameTool) { 'manifest-or-tool-root-unavailable' } else { 'missing' })
    version = $(if ($null -ne $gameTool) { $gameTool.version } else { $null })
    path = $(if ($null -ne $gameTool) { $gameTool.path } else { $null })
    objdumpPath = $gameObjdumpPath
}

$dosboxTool = Get-ManifestToolPath -ManifestPath (Join-Path $OuterRoot 'benchmarks/tools/dosbox-toolchain.json') `
    -ManifestProperty 'dosboxX' -ToolRootPath $ToolRootForChecks
$dosboxAvailable = ($null -ne $dosboxTool -and (Test-Path -LiteralPath $dosboxTool.path -PathType Leaf))
$tools += [pscustomobject]@{
    name = 'DOSBox-X'; purpose = 'DOS runtime and benchmark scenarios'; requiredForBuild = $false
    status = $(if ($dosboxAvailable) { 'available' } elseif ($null -eq $dosboxTool) { 'manifest-or-tool-root-unavailable' } else { 'missing' })
    version = $(if ($null -ne $dosboxTool) { $dosboxTool.version } else { $null })
    path = $(if ($null -ne $dosboxTool) { $dosboxTool.path } else { $null })
}

$hostGcc = Get-Command gcc -ErrorAction SilentlyContinue
$tools += [pscustomobject]@{
    name = 'Host GCC'; purpose = 'selected native fault-injection host tests'; requiredForBuild = $false
    status = $(if ($null -ne $hostGcc) { 'available' } else { 'optional-missing' })
    version = $null
    path = $(if ($null -ne $hostGcc) { $hostGcc.Source } else { $null })
}

$buildToolsReady = $true
foreach ($tool in @($tools | Where-Object { $_.requiredForBuild })) {
    if ($tool.status -ne 'available') { $buildToolsReady = $false }
}
$runtimeToolsAvailable = ($buildToolsReady -and $dosboxAvailable)
$workspaceConsistent = ($gitlinkMatchesHead -and $gitlinkMatchesIndex)
$report = [pscustomobject]@{
    schemaVersion = 1
    readOnly = $true
    sideEffects = @()
    workspaceConsistent = $workspaceConsistent
    outer = $outer
    game = $game
    gitlink = [pscustomobject]@{
        path = 'quake'
        committedRevision = $recordedGitlink
        indexRevision = $indexedGitlink
        matchesGameHead = $gitlinkMatchesHead
        matchesIndex = $gitlinkMatchesIndex
    }
    buildToolsReady = $buildToolsReady
    runtimeToolsAvailable = $runtimeToolsAvailable
    optimizationInventory = [pscustomobject]@{
        gameHistoryIsShallow = $game.shallow
        fullHistoryRequiredForBuildIdentity = $true
        fullHistoryRequiredForCompleteInventory = $true
    }
    tools = $tools
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8 -Compress
}
else {
    Write-Host 'NitroQuake workspace check (read-only; no fetch, reset, bootstrap or replacement performed)'
    Write-Host ("Outer: {0}  {1}  branch={2}  dirty={3}" -f $outer.path, $outer.revision, $outer.branch, $outer.dirty)
    Write-Host ("Game:  {0}  {1}  branch={2}  dirty={3}" -f $game.path, $game.revision, $game.branch, $game.dirty)
    Write-Host ("Gitlink quake: committed={0}  index={1}  game-head-match={2}" -f `
        $recordedGitlink, $indexedGitlink, $workspaceConsistent)
    Write-Host ("Build tools ready: {0}; runtime toolchain available: {1}" -f $buildToolsReady, $runtimeToolsAvailable)
    Write-Host ("Game checkout is shallow: {0} (full history is required for numbered build identity)" -f `
        $game.shallow)
    Write-Host 'A complete optimization-attempt inventory and numbered build identity require full game history.'
    foreach ($tool in $tools) {
        $version = if ($tool.version) { " ($($tool.version))" } else { '' }
        Write-Host ("  {0}: {1}{2} - {3}" -f $tool.name, $tool.status, $version, $tool.purpose)
    }
}

if (-not $workspaceConsistent) { exit 1 }
