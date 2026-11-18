[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pwsh = Get-Command pwsh -ErrorAction Stop
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) { $git = Get-Command git -ErrorAction Stop }
$bootstrap = Join-Path $PSScriptRoot 'bootstrap-workspace.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('nitroquake-workspace-bootstrap-' + [guid]::NewGuid().ToString('N'))

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& $script:git.Source -C $RepositoryPath @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git -C '$RepositoryPath' $($Arguments -join ' ') failed: $(($output | ForEach-Object { [string]$_ }) -join ' ')"
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Set-TestGitIdentity {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)
    [void](Invoke-TestGit -RepositoryPath $RepositoryPath -Arguments @('config', 'user.name', 'Workspace Bootstrap Test'))
    [void](Invoke-TestGit -RepositoryPath $RepositoryPath -Arguments @('config', 'user.email', 'workspace-bootstrap@example.invalid'))
}

function New-FixtureOuterRepository {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$EngineUrl,
        [Parameter(Mandatory = $true)][string]$EngineRevision
    )

    New-Item -ItemType Directory -Path $RepositoryPath -Force | Out-Null
    [void](Invoke-TestGit -RepositoryPath $RepositoryPath -Arguments @('init', '--quiet'))
    Set-TestGitIdentity -RepositoryPath $RepositoryPath
    [IO.File]::WriteAllText((Join-Path $RepositoryPath 'README.txt'), 'outer fixture')
    $engineLock = [ordered]@{ schemaVersion = 1; repository = $EngineUrl; commit = $EngineRevision }
    [IO.File]::WriteAllText(
        (Join-Path $RepositoryPath 'engine.lock'),
        ($engineLock | ConvertTo-Json -Depth 3) + [Environment]::NewLine)
    [void](Invoke-TestGit -RepositoryPath $RepositoryPath -Arguments @('add', 'README.txt', 'engine.lock'))
    [void](Invoke-TestGit -RepositoryPath $RepositoryPath -Arguments @('commit', '--quiet', '-m', 'fixture: pin engine revision'))
}

function Invoke-Bootstrap {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    $arguments = @('-OuterRoot', $RepositoryPath)
    $output = @(& $script:pwsh.Source -NoProfile -File $script:bootstrap @arguments 2>&1)
    return [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = (($output | ForEach-Object { [string]$_ }) -join "`n")
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $source = Join-Path $temporaryRoot 'game source'
    $remote = Join-Path $temporaryRoot 'game remote.git'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    [void](Invoke-TestGit -RepositoryPath $source -Arguments @('init', '--quiet'))
    Set-TestGitIdentity -RepositoryPath $source

    [IO.File]::WriteAllText((Join-Path $source 'README.txt'), 'initial game revision')
    [void](Invoke-TestGit -RepositoryPath $source -Arguments @('add', 'README.txt'))
    [void](Invoke-TestGit -RepositoryPath $source -Arguments @('commit', '--quiet', '-m', 'fixture: initial game revision'))
    $firstRevision = Invoke-TestGit -RepositoryPath $source -Arguments @('rev-parse', 'HEAD')

    [IO.File]::WriteAllText((Join-Path $source 'optimization.txt'), 'second game revision')
    [void](Invoke-TestGit -RepositoryPath $source -Arguments @('add', 'optimization.txt'))
    [void](Invoke-TestGit -RepositoryPath $source -Arguments @('commit', '--quiet', '-m', 'fixture: add second game revision'))
    $secondRevision = Invoke-TestGit -RepositoryPath $source -Arguments @('rev-parse', 'HEAD')

    $cloneOutput = @(& $script:git.Source clone --bare -- $source $remote 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not create the local fixture remote: $($cloneOutput -join ' ')" }

    $freshOuter = Join-Path $temporaryRoot 'fresh outer checkout'
    New-FixtureOuterRepository -RepositoryPath $freshOuter -EngineUrl $remote -EngineRevision $secondRevision
    $freshResult = Invoke-Bootstrap -RepositoryPath $freshOuter
    if ($freshResult.exitCode -ne 0) {
        throw "Bootstrap failed for a fresh workspace: $($freshResult.output)"
    }

    $freshGame = Join-Path $freshOuter 'quake'
    $checkedOutRevision = Invoke-TestGit -RepositoryPath $freshGame -Arguments @('rev-parse', '--verify', 'HEAD')
    $isShallow = Invoke-TestGit -RepositoryPath $freshGame -Arguments @('rev-parse', '--is-shallow-repository')
    $historyCount = [int](Invoke-TestGit -RepositoryPath $freshGame -Arguments @('rev-list', '--count', 'HEAD'))
    $gameRoot = [IO.Path]::GetFullPath((Invoke-TestGit -RepositoryPath $freshGame -Arguments @('rev-parse', '--show-toplevel')))
    if ($checkedOutRevision -ne $secondRevision -or $isShallow -ne 'false' -or $historyCount -ne 2 -or
        -not [string]::Equals($gameRoot.TrimEnd('\', '/'), $freshGame.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Bootstrap did not create a complete engine checkout at the pinned revision.'
    }

    $repeatResult = Invoke-Bootstrap -RepositoryPath $freshOuter
    if ($repeatResult.exitCode -ne 0 -or $repeatResult.output -notmatch 'already matches engine.lock') {
        throw "Bootstrap did not safely recognize an already ready checkout: $($repeatResult.output)"
    }

    $nonRepositoryOuter = Join-Path $temporaryRoot 'outer with existing files'
    New-FixtureOuterRepository -RepositoryPath $nonRepositoryOuter -EngineUrl $remote -EngineRevision $secondRevision
    $nonRepositoryGame = Join-Path $nonRepositoryOuter 'quake'
    New-Item -ItemType Directory -Path $nonRepositoryGame -Force | Out-Null
    $preservedFile = Join-Path $nonRepositoryGame 'keep.txt'
    [IO.File]::WriteAllText($preservedFile, 'preserve this existing file')
    $nonRepositoryResult = Invoke-Bootstrap -RepositoryPath $nonRepositoryOuter
    if ($nonRepositoryResult.exitCode -eq 0 -or (Get-Content -LiteralPath $preservedFile -Raw) -ne 'preserve this existing file') {
        throw 'Bootstrap did not reject and preserve non-repository content at quake/.'
    }

    $mismatchOuter = Join-Path $temporaryRoot 'outer with mismatched game'
    New-FixtureOuterRepository -RepositoryPath $mismatchOuter -EngineUrl $remote -EngineRevision $firstRevision
    $mismatchGame = Join-Path $mismatchOuter 'quake'
    $mismatchCloneOutput = @(& $script:git.Source clone --no-checkout -- $remote $mismatchGame 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not create mismatched game fixture: $($mismatchCloneOutput -join ' ')" }
    [void](Invoke-TestGit -RepositoryPath $mismatchGame -Arguments @('checkout', '--quiet', '--detach', $secondRevision))
    $beforeMismatch = Invoke-TestGit -RepositoryPath $mismatchGame -Arguments @('rev-parse', 'HEAD')
    $mismatchResult = Invoke-Bootstrap -RepositoryPath $mismatchOuter
    $afterMismatch = Invoke-TestGit -RepositoryPath $mismatchGame -Arguments @('rev-parse', 'HEAD')
    if ($mismatchResult.exitCode -eq 0 -or $beforeMismatch -ne $afterMismatch -or $afterMismatch -ne $secondRevision) {
        throw 'Bootstrap did not reject and preserve a checkout at the wrong game revision.'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $resolvedTemporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        if (-not $resolvedTemporaryRoot.StartsWith($resolvedTemporaryParent + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedTemporaryRoot) -notlike 'nitroquake-workspace-bootstrap-*') {
            throw "Refusing to remove a test directory outside its unique temporary root: '$resolvedTemporaryRoot'."
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

Write-Host 'PASS: full-history clone, exact engine.lock checkout, idempotent rerun and existing-content preservation'
