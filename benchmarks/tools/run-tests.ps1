<#
.SYNOPSIS
    Compose standalone game verification with benchmark host and DOS gates.
.DESCRIPTION
    Run from any directory. -GameRoot or NITROQUAKE_GAME_ROOT selects the game.
    -HostOnly runs source/format checks without compilation or DOSBox. Runtime
    gates retain their frame, event, image and ISA acceptance requirements.
#>
[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$DataRoot,
    [switch]$HostOnly,
    [switch]$SkipSlow,
    [ValidateRange(1, 9)]
    [int]$Runs = 3,
    [ValidateSet('i486', 'i386')]
    [string]$CpuTarget = 'i486',
    [switch]$NoBootstrap,
    [switch]$SkipReleaseGuard,
    [switch]$SkipRendering
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'common.ps1')
$repoRoot = $script:GameRepositoryRoot
$benchmarkRoot = $script:BenchmarkRepositoryRoot
$pushLocation = Get-Location
Set-Location $benchmarkRoot

$results = New-Object System.Collections.Generic.List[object]
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string[]]$Command,
        [int]$TimeoutSeconds = 0
    )

    Write-Host ''
    Write-Host ('=' * 78)
    Write-Host ("  {0}" -f $Name)
    Write-Host ('=' * 78)

    $gateWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($TimeoutSeconds -gt 0) {
            # A job, not an in-process call: the only way to bound a child that
            # wedges.  -ArgumentList takes ONE flat array whose elements become
            # the scriptblock's parameters, so the command vector and the
            # directory are its two elements.  Passing -ArgumentList twice is a
            # binding error, and wrapping the command in a unary comma nests it
            # one level too deep ($Command[0] is then the whole vector, which
            # splats as a single joined command name), so both of those forms
            # were broken and this branch was unreachable.  The job's last
            # statement is the child's exit code, because a job returns values
            # rather than setting the caller's $LASTEXITCODE.
            $job = Start-Job -ScriptBlock {
                param($Command, $RepoRoot)
                Set-Location $RepoRoot
                & $Command[0] @($Command[1..($Command.Count - 1)])
                $LASTEXITCODE
            } -ArgumentList @($Command, $benchmarkRoot)
            try {
                if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
                    Stop-Job $job
                    throw "timed out after $TimeoutSeconds s"
                }
                $output = @(Receive-Job $job)
                $output | Out-Host
                $code = if ($output.Count -gt 0) { [int]$output[-1] } else { 1 }
            }
            finally {
                Remove-Job $job -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            & $Command[0] @($Command[1..($Command.Count - 1)]) 2>&1 | Out-Host
            $code = $LASTEXITCODE
        }
    }
    catch {
        Write-Host ("  FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $code = 1
    }
    $gateWatch.Stop()

    $ok = ($code -eq 0)
    $results.Add([pscustomobject]@{
            gate     = $Name
            kind     = $Kind
            exit     = $code
            seconds  = [math]::Round($gateWatch.Elapsed.TotalSeconds, 1)
            result   = $(if ($ok) { 'PASS' } else { 'FAIL' })
        })
    if (-not $ok) {
        Write-Host ("  -> FAIL (exit {0})" -f $code) -ForegroundColor Red
    }
    else {
        Write-Host ("  -> PASS ({0:N1}s)" -f $gateWatch.Elapsed.TotalSeconds) -ForegroundColor Green
    }
    return $ok
}

$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue)
if ($null -eq $pwshExe) { $pwshExe = (Get-Command powershell) }
$env:NITROQUAKE_GAME_ROOT = $repoRoot
$nb = if ($NoBootstrap) { @('-NoBootstrap') } else { @() }
$runtimeInputs = @()
if ($DataRoot) { $runtimeInputs += @('-DataRoot', $DataRoot) }

# ---- 1-3: host-only tests.  No compiler, no emulator, seconds each. --------
# The full game gate below already runs its host checks. HostOnly here verifies
# suite contracts; native compiler/source checks have their own game entry point.
$hostTests = @(
    'test-runner-selectors.ps1',
    'test-render-progress.ps1',
    'test-timedemo-command-tail.ps1',
    'test-bench-event-repeat.ps1',
    'test-workspace-doctor.ps1',
    'test-workspace-bootstrap.ps1',
    'test-workspace.ps1'
)
foreach ($test in $hostTests) {
    Invoke-Gate -Name $test -Kind 'host' -Command @($pwshExe.Source, '-NoProfile', '-File', "tools/$test") | Out-Null
}
Invoke-Gate -Name 'test-dosbox-profile' -Kind 'host' -Command @('python', 'tools/test-dosbox-profile.py') | Out-Null
Invoke-Gate -Name 'test-build-iso9660 (ISO structure, extents and input validation)' -Kind 'host' `
    -Command @('python', 'tools/test-build-iso9660.py') | Out-Null
Invoke-Gate -Name 'test-launcher-provenance (manifest/configuration identity)' -Kind 'host' `
    -Command @($pwshExe.Source, '-NoProfile', '-File', 'tools/test-launcher-provenance.ps1') | Out-Null
Invoke-Gate -Name 'test-particle-scenario' -Kind 'host' -Command @('python', 'tools/test-particle-scenario.py') | Out-Null
Invoke-Gate -Name 'test-executable-comparison' -Kind 'host' -Command @('python', 'tools/test-executable-comparison.py') | Out-Null
Invoke-Gate -Name 'test-frame-times' -Kind 'host' -Command @('python', 'tools/test-frame-times.py') | Out-Null
Invoke-Gate -Name 'test-engine-profile-analysis' -Kind 'host' -Command @('python', 'tools/test-engine-profile-analysis.py') | Out-Null
Invoke-Gate -Name 'test-rendering (PCX comparison + frame-log parser)' -Kind 'host' -Command @('python', 'tools/test-rendering.py') | Out-Null
Invoke-Gate -Name 'test-blobexplosion-demo-fixture (PACK + .dem format)' -Kind 'host' `
    -Command @('python', '-B', 'tools/test_blobexplosion_demo_fixture.py') | Out-Null
Invoke-Gate -Name 'test-lavasplash-fixture (assembly source contract)' -Kind 'host' `
    -Command @('python', '-B', 'tools/test-lavasplash.py') | Out-Null
Invoke-Gate -Name 'test-teleportsplash-fixture (assembly source contract)' -Kind 'host' `
    -Command @('python', '-B', 'tools/test-teleportsplash.py') | Out-Null
Invoke-Gate -Name 'test-runparticleeffect-fixture (assembly source contract)' -Kind 'host' `
    -Command @('python', '-B', 'tools/test-runparticleeffect.py') | Out-Null
Invoke-Gate -Name 'test-entityparticles-fixture (assembly source contract)' -Kind 'host' `
    -Command @('python', '-B', 'tools/test-entityparticles.py') | Out-Null
Invoke-Gate -Name 'test-timedemo-event-record (BENCH486 event report parser)' -Kind 'host' `
    -Command @($pwshExe.Source, '-NoProfile', '-File', 'tools/test-timedemo-event-record.ps1') | Out-Null
Invoke-Gate -Name 'test-rendering-reports (exact C/ASM parity report comparator)' -Kind 'host' -Command @('python', 'tools/test-rendering-reports.py') | Out-Null
Invoke-Gate -Name 'test-renderer-ownership (compiler clones and call traces)' -Kind 'host' -Command @('python', 'tools/test-renderer-ownership.py') | Out-Null
if (-not $HostOnly) {
$gameGateArgs = @($pwshExe.Source, '-NoProfile', '-File', (Join-Path $repoRoot 'tools/run-tests.ps1'), '-CpuTarget', $CpuTarget) + $nb
if ($SkipReleaseGuard) { $gameGateArgs += '-SkipReleaseGuard' }
Invoke-Gate -Name 'game build and ISA verification' -Kind 'build' `
    -Command $gameGateArgs | Out-Null

# ---- 6: smoke. ------------------------------------------------------------
Invoke-Gate -Name 'smoke-dos (DOSBox-X startup + clean exit)' -Kind 'dos' -TimeoutSeconds 300 `
    -Command (@($pwshExe.Source, '-NoProfile', '-File', 'tools/smoke-dos.ps1', '-CpuTarget', $CpuTarget, '-TimeoutSeconds', '90') + $nb + $runtimeInputs) | Out-Null

# ---- 7: coverage of the paths the parity gate cannot see. ------------------
# Cheap (seconds) and it is the only gate that executes the server, the collision
# code, the Quake bytecode builtins and the net socket layer.
Invoke-Gate -Name 'coverage-dos (localmp: server/world/pr/net reachable)' -Kind 'dos' -TimeoutSeconds 600 `
    -Command (@($pwshExe.Source, '-NoProfile', '-File', 'tools/coverage-dos.ps1', '-CpuTarget', $CpuTarget, '-SkipBuild') + $nb + $runtimeInputs) | Out-Null

# ---- 8: bench486 correctness. ---------------------------------------------
# The gate-level -TimeoutSeconds is a watchdog above the runner's own 3600 s, not a
# second limit on the benchmark: it exists so a wedged DOSBox-X or a child that
# never returns cannot hold the suite open indefinitely. Same idea on the timedemo.
Invoke-Gate -Name 'bench-dos (bench486 PASS, C-vs-asm parity)' -Kind 'dos' -TimeoutSeconds 3900 `
    -Command (@($pwshExe.Source, '-NoProfile', '-File', 'tools/bench-dos.ps1', '-CpuTarget', $CpuTarget, '-TimeoutSeconds', '3600') + $nb + $runtimeInputs) | Out-Null

# ---- 9: deterministic rendered scenes, temporal checks and image diffs. ---
if ($SkipRendering) {
    $results.Add([pscustomobject]@{
            gate    = 'render-validation (demo scenes, frame stability, PCX comparisons)'
            kind    = 'dos'
            exit    = '-'
            seconds = 0
            result  = 'SKIP'
        })
    Write-Host ''
    Write-Host '  render-validation: SKIPPED (-SkipRendering).' -ForegroundColor Yellow
}
else {
    Invoke-Gate -Name 'render-validation (demo1/2/3, VGA/VESA, quality, images)' -Kind 'dos' -TimeoutSeconds 3600 `
        -Command (@($pwshExe.Source, '-NoProfile', '-File', 'tools/render-validation-dos.ps1', '-CpuTarget', $CpuTarget, '-TimeoutSeconds', '600') + $nb + $runtimeInputs) | Out-Null
}

# ---- 10: deterministic correctness and performance regression evidence. --
if ($SkipSlow) {
    $results.Add([pscustomobject]@{
            gate    = 'timedemo (969 frames, checksum, median)'
            kind    = 'dos'
            exit    = '-'
            seconds = 0
            result  = 'SKIP'
        })
    Write-Host ''
    Write-Host '  timedemo: SKIPPED (-SkipSlow); final timing evidence omitted.'
}
else {
    Invoke-Gate -Name "timedemo ($Runs runs; 969 frames + checksum + median)" -Kind 'dos' -TimeoutSeconds 900 `
        -Command (@($pwshExe.Source, '-NoProfile', '-File', 'tools/timedemo-dos.ps1', '-CpuTarget', $CpuTarget, '-Runs', "$Runs", '-NoFpsStats') + $nb + $runtimeInputs) | Out-Null
}

}

$sw.Stop()

# ---- summary --------------------------------------------------------------
Write-Host ''
Write-Host ('=' * 78)
Write-Host '  SUMMARY'
Write-Host ('=' * 78)
$results | Format-Table -AutoSize | Out-Host

$failed = @($results | Where-Object { $_.result -eq 'FAIL' })
$skipped = @($results | Where-Object { $_.result -eq 'SKIP' })

Write-Host ("  {0} passed, {1} failed, {2} skipped, {3:N1}s total" -f
    @($results | Where-Object { $_.result -eq 'PASS' }).Count, $failed.Count, $skipped.Count, $sw.Elapsed.TotalSeconds)

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host '  Failing gates:' -ForegroundColor Red
    foreach ($f in $failed) { Write-Host ("    - {0} (exit {1})" -f $f.gate, $f.exit) -ForegroundColor Red }
}

Write-Host ''
# Current qualification limits are documented in the game's renderer status
# and the physical-486 acceptance procedure.
Write-Host '  See the game documentation index and renderer status for current limits.' -ForegroundColor Yellow
Write-Host '  Physical-machine gates are listed in docs/PHYSICAL-486-ACCEPTANCE.md.' -ForegroundColor Yellow

Set-Location $pushLocation

if ($failed.Count -gt 0) { exit 1 }
exit 0
