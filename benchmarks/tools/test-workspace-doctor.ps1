[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outerRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$doctor = Join-Path $PSScriptRoot 'check-workspace.ps1'
$pwsh = Get-Command pwsh -ErrorAction Stop
$git = Get-Command git -ErrorAction Stop
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('nitroquake-workspace-doctor-' + [guid]::NewGuid().ToString('N'))

function Get-StatusLines {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)
    $lines = @(& $git.Source -C $RepositoryPath status --porcelain=v1 --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw "Could not read Git status for '$RepositoryPath'." }
    return ,@($lines | ForEach-Object { [string]$_ })
}

function Invoke-DoctorJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = @(& $pwsh.Source -NoProfile -File $doctor @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $json = ($output | ForEach-Object { [string]$_ }) -join "`n"
    try { $report = $json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Workspace doctor emitted invalid JSON: $json" }
    return [pscustomobject]@{ exitCode = $exitCode; report = $report }
}

$outerBefore = Get-StatusLines -RepositoryPath $outerRoot
$gameBefore = Get-StatusLines -RepositoryPath (Join-Path $outerRoot 'quake')
try {
    $real = Invoke-DoctorJson -Arguments @('-Json')
    if ($real.exitCode -ne 0 -or -not $real.report.workspaceConsistent) {
        throw 'The workspace doctor did not confirm the current checkout and gitlink.'
    }
    if (-not $real.report.readOnly -or @($real.report.sideEffects).Count -ne 0) {
        throw 'The workspace doctor did not report its read-only behavior.'
    }
    if ($real.report.gitlink.committedRevision -ne $real.report.game.revision -or
        $real.report.gitlink.indexRevision -ne $real.report.game.revision) {
        throw 'The workspace doctor reported inconsistent gitlink revisions.'
    }
    if ($real.report.optimizationInventory.gameHistoryIsShallow -ne $false -or
        $real.report.optimizationInventory.fullHistoryRequiredForBuildIdentity -ne $false -or
        $real.report.optimizationInventory.fullHistoryRequiredForCompleteInventory -ne $true) {
        throw 'The workspace doctor reported incorrect history requirements.'
    }
    $requiredTools = @($real.report.tools | Where-Object { $_.requiredForBuild })
    if (@($requiredTools | Where-Object { $_.status -ne 'available' }).Count -ne 0) {
        throw 'A required build tool is unavailable in the current workspace.'
    }

    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $fixtureGame = Join-Path $temporaryRoot 'game checkout'
    New-Item -ItemType Directory -Path $fixtureGame -Force | Out-Null
    & $git.Source -C $fixtureGame init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the temporary game repository.' }
    & $git.Source -C $fixtureGame config user.name 'Workspace Doctor Test'
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the temporary repository identity.' }
    & $git.Source -C $fixtureGame config user.email 'workspace-doctor@example.invalid'
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the temporary repository identity.' }
    [IO.File]::WriteAllText((Join-Path $fixtureGame 'README.txt'), 'synthetic game revision')
    & $git.Source -C $fixtureGame add README.txt
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the temporary fixture.' }
    & $git.Source -C $fixtureGame commit --quiet -m 'fixture: create mismatched game revision'
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit the temporary fixture.' }

    $fixtureBefore = Get-StatusLines -RepositoryPath $fixtureGame
    $mismatch = Invoke-DoctorJson -Arguments @(
        '-Json', '-OuterRoot', $outerRoot, '-GameRoot', $fixtureGame,
        '-ToolRoot', (Join-Path $temporaryRoot 'missing-tools')
    )
    if ($mismatch.exitCode -eq 0 -or $mismatch.report.workspaceConsistent -or
        $mismatch.report.gitlink.matchesGameHead) {
        throw 'The workspace doctor did not reject a game revision that differs from the recorded gitlink.'
    }
    $fixtureAfter = Get-StatusLines -RepositoryPath $fixtureGame
    if (($fixtureBefore -join "`n") -ne ($fixtureAfter -join "`n")) {
        throw 'The workspace doctor changed the temporary game checkout.'
    }

    $outerAfter = Get-StatusLines -RepositoryPath $outerRoot
    $gameAfter = Get-StatusLines -RepositoryPath (Join-Path $outerRoot 'quake')
    if (($outerBefore -join "`n") -ne ($outerAfter -join "`n") -or
        ($gameBefore -join "`n") -ne ($gameAfter -join "`n")) {
        throw 'The workspace doctor changed a checkout while inspecting it.'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host 'PASS: read-only workspace report, required tools, matching gitlink and mismatched-revision rejection'
