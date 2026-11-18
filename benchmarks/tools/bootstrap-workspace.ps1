<#
.SYNOPSIS
    Provision the engine checkout pinned by the outer repository's engine.lock.
.DESCRIPTION
    Clone the engine repository with complete history and check out the exact
    commit recorded in engine.lock. The pinned repository URL can be overridden
    through -EngineRepositoryUrl or NITROQUAKE_ENGINE_REPOSITORY_URL. Existing
    content is never replaced.
#>
[CmdletBinding()]
param(
    [string]$EngineRepositoryUrl = $env:NITROQUAKE_ENGINE_REPOSITORY_URL,
    [string]$OuterRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OuterRoot)) {
    $OuterRoot = Join-Path $PSScriptRoot '../..'
}
$OuterRoot = [IO.Path]::GetFullPath($OuterRoot)
$GameRoot = [IO.Path]::GetFullPath((Join-Path $OuterRoot 'quake'))
$EngineLockPath = Join-Path $OuterRoot 'engine.lock'

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
if ($null -eq $gitCommand) { throw 'Git is required to provision the engine checkout.' }

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

if (-not (Test-Path -LiteralPath $EngineLockPath -PathType Leaf)) {
    throw "Engine lock file is missing: '$EngineLockPath'."
}
$committedEngineLock = Invoke-BootstrapGit -RepositoryPath $OuterRoot -Arguments @('show', 'HEAD:engine.lock')
$engineLock = $committedEngineLock | ConvertFrom-Json
$workingEngineLock = Get-Content -LiteralPath $EngineLockPath -Raw | ConvertFrom-Json
if ([int]$engineLock.schemaVersion -ne 1) {
    throw "Unsupported engine lock schema in committed HEAD:engine.lock."
}
$lockedRepositoryUrl = [string]$engineLock.repository
$expectedRevision = ([string]$engineLock.commit).ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($lockedRepositoryUrl)) {
    throw "Engine lock file '$EngineLockPath' must define a repository URL."
}
if ($expectedRevision -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw "Engine lock file '$EngineLockPath' must define a full 40- or 64-character commit ID."
}
if ([string]$workingEngineLock.repository -ne $lockedRepositoryUrl -or
        ([string]$workingEngineLock.commit).ToLowerInvariant() -ne $expectedRevision) {
    throw "Working '$EngineLockPath' differs from committed HEAD:engine.lock. Commit the pin before bootstrapping."
}
if ([string]::IsNullOrWhiteSpace($EngineRepositoryUrl)) {
    $EngineRepositoryUrl = $lockedRepositoryUrl
}

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
            throw "Existing engine checkout is at $existingRevision; engine.lock pins $expectedRevision. Existing content was preserved."
        }
        $isShallow = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('rev-parse', '--is-shallow-repository')
        if ($isShallow -eq 'true') {
            throw "Existing engine checkout at '$GameRoot' is shallow. Fetch complete history manually, then rerun the workspace check."
        }
        $status = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=normal')
        if (-not [string]::IsNullOrWhiteSpace($status)) {
            throw "Existing engine checkout at '$GameRoot' has local changes. Existing content was preserved."
        }

        Write-Host "Engine checkout already matches engine.lock at $expectedRevision and has complete history."
        exit 0
    }
}

Write-Host "Cloning full engine history from $EngineRepositoryUrl..."
$cloneOutput = @(& $script:gitCommand.Source clone --no-checkout --no-single-branch -- `
        $EngineRepositoryUrl $GameRoot 2>&1)
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
        throw 'The cloned engine repository is shallow; a complete history is required for numbered builds.'
    }
    $status = Invoke-BootstrapGit -RepositoryPath $GameRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=normal')
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "The newly cloned engine checkout is unexpectedly dirty: $status"
    }
}
catch {
    throw "Workspace bootstrap could not complete at '$GameRoot'. Any created checkout was preserved for inspection. $($_.Exception.Message)"
}

Write-Host "Engine checkout ready at $GameRoot"
Write-Host "Checked out engine.lock revision $expectedRevision with complete history."
