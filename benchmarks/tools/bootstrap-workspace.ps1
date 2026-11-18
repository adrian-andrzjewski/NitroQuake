<#
.SYNOPSIS
    Provision the game checkout recorded by the outer repository's quake gitlink.
.DESCRIPTION
    Clone the game repository with complete history and check out the exact
    commit recorded in outer HEAD. A game repository URL is needed only when
    the checkout must be cloned; supply it explicitly or through
    NITROQUAKE_GAME_REPOSITORY_URL. Existing content is never replaced.
#>
[CmdletBinding()]
param(
    [string]$GameRepositoryUrl = $env:NITROQUAKE_GAME_REPOSITORY_URL,
    [string]$OuterRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OuterRoot)) {
    $OuterRoot = Join-Path $PSScriptRoot '../..'
}
$OuterRoot = [IO.Path]::GetFullPath($OuterRoot)
$GameRoot = [IO.Path]::GetFullPath((Join-Path $OuterRoot 'quake'))

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
if ($null -eq $gitCommand) { throw 'Git is required to provision the game checkout.' }

function Invoke-BootstrapGit {
    param(
        [string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $gitArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) {
        $gitArguments += @('-C', $RepositoryPath)
    }
    $gitArguments += $Arguments
    $output = @(& $script:gitCommand.Source @gitArguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($gitArguments -join ' ') failed: $(($output | ForEach-Object { [string]$_ }) -join ' ')"
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

$outerTopLevel = Invoke-BootstrapGit -RepositoryPath $OuterRoot -Arguments @('rev-parse', '--show-toplevel')
$outerTopLevel = [IO.Path]::GetFullPath($outerTopLevel)
if (-not [string]::Equals($outerTopLevel.TrimEnd('\', '/'), $OuterRoot.TrimEnd('\', '/'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "OuterRoot must be the outer Git repository root: '$outerTopLevel'."
}

$gitlinkOutput = Invoke-BootstrapGit -RepositoryPath $OuterRoot -Arguments @('ls-tree', 'HEAD', '--', 'quake')
$gitlinkMatch = [regex]::Match($gitlinkOutput, '^160000 commit ([0-9a-fA-F]{40,64})\tquake$')
if (-not $gitlinkMatch.Success) {
    throw "Outer HEAD does not record a Git link at '$OuterRoot\quake'."
}
$expectedRevision = $gitlinkMatch.Groups[1].Value.ToLowerInvariant()

if (Test-Path -LiteralPath $GameRoot) {
    $gameItem = Get-Item -LiteralPath $GameRoot -Force
    if (($gameItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to bootstrap through a reparse point: '$GameRoot'. Existing content was preserved."
    }
    if (-not $gameItem.PSIsContainer) {
        throw "Refusing to replace the existing file '$GameRoot'. Existing content was preserved."
    }

    $existingItems = @(Get-ChildItem -LiteralPath $GameRoot -Force)
    if ($existingItems.Count -gt 0) {
        $existingTopLevel = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--show-toplevel')
        $existingTopLevel = [IO.Path]::GetFullPath($existingTopLevel)
        if (-not [string]::Equals($existingTopLevel.TrimEnd('\', '/'), $GameRoot.TrimEnd('\', '/'),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace non-repository content at '$GameRoot'. Existing content was preserved."
        }

        $existingRevision = (Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--verify', 'HEAD')).ToLowerInvariant()
        if ($existingRevision -ne $expectedRevision) {
            throw "Existing game checkout is at $existingRevision; outer HEAD records $expectedRevision. Existing content was preserved."
        }
        $isShallow = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--is-shallow-repository')
        if ($isShallow -eq 'true') {
            throw "Existing game checkout at '$GameRoot' is shallow. Fetch complete history manually, then rerun the workspace check."
        }
        $status = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=normal')
        if (-not [string]::IsNullOrWhiteSpace($status)) {
            throw "Existing game checkout at '$GameRoot' has local changes. Existing content was preserved."
        }

        Write-Host "Game checkout already matches outer HEAD at $expectedRevision and has complete history."
        exit 0
    }
}

if ([string]::IsNullOrWhiteSpace($GameRepositoryUrl)) {
    throw 'Pass -GameRepositoryUrl or set NITROQUAKE_GAME_REPOSITORY_URL to clone the NitroQuake game repository.'
}

Write-Host "Cloning full game history from the supplied repository URL..."
$cloneOutput = @(& $script:gitCommand.Source clone --no-checkout --no-single-branch -- `
        $GameRepositoryUrl $GameRoot 2>&1)
$cloneExitCode = $LASTEXITCODE
$cloneOutput | ForEach-Object { Write-Host ([string]$_) }
if ($cloneExitCode -ne 0) {
    throw "Git clone failed with exit code $cloneExitCode. Any partial checkout was left in place for inspection."
}

try {
    [void](Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('cat-file', '-e', "$expectedRevision^{commit}"))
    [void](Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('checkout', '--detach', $expectedRevision))
    $actualRevision = (Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--verify', 'HEAD')).ToLowerInvariant()
    if ($actualRevision -ne $expectedRevision) {
        throw "Checkout resolved to $actualRevision instead of expected $expectedRevision."
    }
    $isShallow = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--is-shallow-repository')
    if ($isShallow -eq 'true') {
        throw 'The cloned game repository is shallow; a complete history is required for numbered builds.'
    }
    $status = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=normal')
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "The newly cloned game checkout is unexpectedly dirty: $status"
    }
}
catch {
    throw "Workspace bootstrap could not complete at '$GameRoot'. Any created checkout was preserved for inspection. $($_.Exception.Message)"
}

Write-Host "Game checkout ready at $GameRoot"
Write-Host "Checked out outer HEAD's recorded game revision $expectedRevision with complete history."
