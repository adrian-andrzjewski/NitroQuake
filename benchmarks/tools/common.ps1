# DOSBox orchestration consumes the standalone game's build API in one direction.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'workspace.ps1')
$requestedGameRoot = Get-Variable -Name GameRoot -ValueOnly -ErrorAction SilentlyContinue
$script:GameRepositoryRoot = Resolve-NitroQuakeGameRoot -GameRoot $requestedGameRoot
$script:BenchmarkRepositoryRoot = Get-NitroQuakeBenchmarkRoot
. (Join-Path $script:GameRepositoryRoot 'tools/common.ps1')

function Resolve-DataRoot {
    <#
    .SYNOPSIS
        Resolve the directory holding the game data.

    .DESCRIPTION
        Defaults to testdata\id1 in the repository.  Game data is deliberately not
        in Git, so the caller reports a missing directory itself, with the
        reminder about where to put it.
    #>
    [CmdletBinding()]
    param(
        [string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($DataRoot)) {
        $DataRoot = Join-Path $RepoRoot 'testdata\id1'
    }
    return [IO.Path]::GetFullPath($DataRoot)
}

function Resolve-DosboxExecutable {
    <#
    .SYNOPSIS
        Locate the DOSBox-X binary, bootstrapping the toolchain if allowed.

    .DESCRIPTION
        The executable name comes from dos-toolchain.json.dosboxX.executable, never
        from a literal.  coverage-dos.ps1 used to hardcode 'dosbox-x.exe' beside
        installDirectory, so it alone would break on a manifest that named the
        binary differently or shipped it in a subdirectory.

        With -NoBootstrap, a missing emulator is an error naming the fix.  Without
        it, bootstrap-dos.ps1 runs first.  coverage-dos.ps1 had no fallback at all,
        which made -NoBootstrap mean one thing there and another everywhere else.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ToolRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDirectory,
        [switch]$NoBootstrap
    )

    $dosboxRoot = Join-Path $ToolRoot $Manifest.dosboxX.installDirectory
    $dosbox = Join-Path $dosboxRoot (
        $Manifest.dosboxX.executable -replace '/', [IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path -LiteralPath $dosbox -PathType Leaf)) {
        if ($NoBootstrap) {
            throw "DOSBox-X not found at '$dosbox'. Run bootstrap-dos.ps1 first or omit -NoBootstrap."
        }
        & (Join-Path $ToolsDirectory 'bootstrap-dos.ps1') -ToolRoot $ToolRoot -GameRoot $script:GameRepositoryRoot
    }
    if (-not (Test-Path -LiteralPath $dosbox -PathType Leaf)) {
        throw "Required DOSBox-X executable is missing: '$dosbox'."
    }
    return $dosbox
}

function Get-DosboxProfilePath {
    <#
    .SYNOPSIS
        The pinned 486-high DOSBox-X profile.

    .DESCRIPTION
        One profile template serves all four runners.  Its SHA-256 is a promotion
        gate in timedemo-dos.ps1, so this returns the file rather than its text:
        the hash is taken over the bytes on disk, and re-serialising the text first
        would let a line-ending change slip past a pin that exists precisely to
        catch one.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ToolsDirectory)

    $profile = Join-Path $ToolsDirectory 'dosbox-x-486-high.conf'
    if (-not (Test-Path -LiteralPath $profile -PathType Leaf)) {
        throw "DOSBox-X profile is missing: '$profile'."
    }
    return $profile
}

function New-DosboxRuntimeConfig {
    <#
    .SYNOPSIS
        Write a DOSBox-X config for one run and return its path.

    .DESCRIPTION
        Takes the pinned profile and replaces its [autoexec] section with one that
        mounts the staging directory and calls the run's batch file.  Then, for a
        non-i486 target, forces cputype to match the build target.

        On the cputype: one profile serves both CPU targets, and only the emulated
        CPU changes -- the base profile uses a fixed cycle count so timings stay
        comparable between them.  Note that DOSBox-X's cputype changes cycle costs
        but does not enforce instruction-set gating, so this makes a run
        representative and is not the ISA gate.  tools\isa-audit.ps1 is.

        The replacement is anchored on the [devices] header that follows
        [autoexec], and the result is compared against the input: an unchanged
        config means the substitution did not happen, and writing that out would
        run the pinned profile's own autoexec instead of the scenario's.

        The injected block adopts the template's own line ending rather than a
        hardcoded one.  A here-string takes its line endings from the .ps1 file it
        is written in, and this tree is not self-consistent about them: git stores
        these files as LF and core.autocrlf=true rewrites them to CRLF on checkout,
        so the same commit produces a different generated config depending on the
        machine's git configuration.  Worse, HEAD's version appended
        [Environment]::NewLine after a TrimEnd, which put CRLF at the end of a block
        whose interior was LF -- a mixed-ending block inside an otherwise CRLF
        file.

        Detecting the newline from the template makes the block match whatever it
        is being inserted into, on any checkout, under any git configuration.  The
        rest of the config is the template's bytes copied through unchanged, so this
        is the only place line endings are chosen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProfileTemplate,
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)][string]$BatchName,
        [Parameter(Mandatory = $true)][ValidateSet('i486', 'i386')][string]$CpuTarget,
        [Parameter(Mandatory = $true)][string]$ConfigName
    )

    $profileText = Get-Content -LiteralPath $ProfileTemplate -Raw
    # CRLF unless the template is entirely LF.
    $newline = if ($profileText.Contains("`r`n")) { "`r`n" } else { "`n" }
    # DOSBox-X parses the mount argument itself, so an embedded quote is doubled.
    $mountPath = $StagingRoot.Replace('"', '""')
    $autoexec = @(
        '[autoexec]'
        "mount c `"$mountPath`""
        'c:'
        'cd \quake'
        "call $BatchName"
        'exit'
        ''
    ) -join $newline
    $runtimeConfig = [regex]::Replace(
        $profileText,
        '(?ms)^\[autoexec\]\s*.*?(?=^\[devices\])',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $autoexec })
    if ($runtimeConfig -eq $profileText) {
        throw "Could not replace the autoexec section in '$ProfileTemplate'."
    }

    if ($CpuTarget -ne 'i486') {
        $cpuModel = $CpuTarget -replace '^i', ''
        $forcedConfig = [regex]::Replace(
            $runtimeConfig,
            '(?m)^cputype\s*=\s*\S+',
            "cputype            = $cpuModel")
        if ($forcedConfig -eq $runtimeConfig) {
            throw "Could not set the DOSBox-X cputype to '$cpuModel' in '$ProfileTemplate'."
        }
        $runtimeConfig = $forcedConfig
    }

    $configPath = Join-Path $StagingRoot $ConfigName
    $runtimeConfig | Set-Content -LiteralPath $configPath -Encoding ASCII
    return $configPath
}

function ConvertTo-ProcessArgument {
    <#
    .SYNOPSIS
        Quote one argument for a ProcessStartInfo.Arguments string.

    .DESCRIPTION
        ProcessStartInfo on .NET takes a single Arguments string on Windows, so an
        argument containing a space has to be quoted by hand.  Doubles any embedded
        quote rather than backslash-escaping it, which is what the Win32 command
        line parser expects.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Assert-DosPspCommandTail {
    <#
    .SYNOPSIS
        Reject a DOS executable argument tail that cannot fit in its PSP.

    .DESCRIPTION
        DOS reserves one byte for the tail length and one byte for the final
        carriage return in the 128-byte PSP command-tail area. This leaves 126
        argument bytes. The executable name is not part of this value; callers
        must pass the exact PSP tail, including the normally present separating
        space after the executable name. ASCII is used because the generated DOS
        batch file is ASCII too.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$CommandTail)

    $dosPspCommandTailMaxBytes = 126
    $commandTailBytes = [Text.Encoding]::ASCII.GetByteCount($CommandTail)
    if ($commandTailBytes -gt $dosPspCommandTailMaxBytes) {
        throw ("DOS command argument tail is {0} ASCII bytes; the PSP limit is {1}. " +
            "Shorten the command-line options or move supported settings into autoexec.cfg.") -f `
            $commandTailBytes, $dosPspCommandTailMaxBytes
    }
    return $commandTailBytes
}

function Invoke-DosboxProcess {
    <#
    .SYNOPSIS
        Run DOSBox-X against a config and wait for it.

    .DESCRIPTION
        Starts hidden, waits, and kills on timeout.  Returns the outcome rather
        than throwing on timeout, because the runners disagree about what a timeout
        means: smoke, bench and timedemo treat it as a failure, while coverage-dos
        has to go on to write a result document saying the scenario did not
        complete.  Deciding that here would force one of those behaviours on all
        four, so the caller decides.

    .OUTPUTS
        ExitCode ($null when the process was killed) and TimedOut.

    .PARAMETER ProgressFile
        Optional text file appended while DOSBox-X runs. Complete lines are
        echoed live to the caller, allowing long benchmarks to report progress.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Dosbox,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        # Prepended to the launch message, e.g. 'DOSBox-X smoke test'.
        [string]$Description = 'DOSBox-X',
        [string]$ProgressFile
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Dosbox
    $startInfo.Arguments = '-conf ' + (ConvertTo-ProcessArgument $ConfigPath) + ' -exit'
    # DOSBox-X resolves its own resources relative to its working directory.
    $startInfo.WorkingDirectory = Split-Path -Parent $Dosbox
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $timedOut = $false
    $exitCode = $null
    try {
        Write-Host "Launching $Description"
        if (-not $process.Start()) {
            throw 'DOSBox-X failed to start.'
        }
        if ([string]::IsNullOrWhiteSpace($ProgressFile)) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill()
                $timedOut = $true
            }
        }
        else {
            $progressOffset = 0
            $progressPending = ''
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            while (-not $process.HasExited) {
                if (Test-Path -LiteralPath $ProgressFile -PathType Leaf) {
                    try {
                        $progressText = [IO.File]::ReadAllText(
                            $ProgressFile, [Text.Encoding]::ASCII)
                        if ($progressText.Length -lt $progressOffset) {
                            $progressOffset = 0
                            $progressPending = ''
                        }
                        if ($progressText.Length -gt $progressOffset) {
                            $progressPending += $progressText.Substring($progressOffset)
                            $progressOffset = $progressText.Length
                            $lastNewline = $progressPending.LastIndexOf("`n")
                            if ($lastNewline -ge 0) {
                                $completeText = $progressPending.Substring(0, $lastNewline)
                                $progressPending = $progressPending.Substring($lastNewline + 1)
                                foreach ($line in ($completeText -split "`r?`n")) {
                                    if ($line.Length -gt 0) {
                                        Write-Host "[DOSBox-X] $line"
                                    }
                                }
                            }
                        }
                    }
                    catch [System.IO.IOException] {
                        # The DOS process may hold the report during a write;
                        # retry on the next poll without losing the offset.
                    }
                }

                if ($process.WaitForExit(1000)) {
                    break
                }
                if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    $process.Kill()
                    $timedOut = $true
                    break
                }
            }

            # Flush the last complete or partial line after DOSBox exits.
            if (Test-Path -LiteralPath $ProgressFile -PathType Leaf) {
                try {
                    $progressText = [IO.File]::ReadAllText(
                        $ProgressFile, [Text.Encoding]::ASCII)
                    if ($progressText.Length -gt $progressOffset) {
                        $progressPending += $progressText.Substring($progressOffset)
                    }
                }
                catch [System.IO.IOException] {
                }
            }
            if ($progressPending.Length -gt 0) {
                foreach ($line in ($progressPending -split "`r?`n")) {
                    if ($line.Length -gt 0) {
                        Write-Host "[DOSBox-X] $line"
                    }
                }
            }
        }

        if (-not $timedOut -and $process.HasExited) {
            # Read before the finally disposes the process; ExitCode is not
            # readable afterwards.
            $exitCode = $process.ExitCode
        }
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
    }
}

function Get-BenchmarkToolingProvenance {
    $suite = $script:BenchmarkRepositoryRoot
    $files = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $suite 'tools') -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]__pycache__[\\/]' } | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($suite, $file.FullName).Replace('\', '/')
        $files[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $revision = & git -C $suite rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $revision = $null }
    $changes = @(& git -C $suite status --porcelain --untracked-files=all -- tools 2>$null)
    return [ordered]@{ schemaVersion=1; purpose='benchmark-tooling-provenance'; gitRevision=$revision; dirty=($changes.Count -gt 0); files=$files }
}

function Get-OrCreateSharedPakCacheFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Sha256
    )

    if ($Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid PAK SHA-256 '$Sha256'." }
    $cacheRoot = Join-Path (Join-Path (Join-Path $script:BenchmarkRepositoryRoot 'out') '.pak-cache') `
        ([DateTime]::UtcNow.ToString('yyyyMMdd'))
    [IO.Directory]::CreateDirectory($cacheRoot) | Out-Null
    $cacheName = $Sha256.ToLowerInvariant() + '-' + [IO.Path]::GetFileName($FileName).ToLowerInvariant()
    $cachePath = Join-Path $cacheRoot $cacheName

    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $cachePath -Algorithm SHA256).Hash -ne $Sha256) {
            throw [IO.InvalidDataException]::new("Shared PAK cache hash mismatch: '$cachePath'.")
        }
        return $cachePath
    }

    $temporaryPath = Join-Path $cacheRoot ('.pak-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash -ne $Sha256) {
            throw [IO.InvalidDataException]::new("Source PAK changed while populating shared cache: '$SourcePath'.")
        }
        try {
            [IO.File]::Move($temporaryPath, $cachePath)
        }
        catch {
            # Another runner may have populated the same content-addressed entry.
            if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { throw }
            if ((Get-FileHash -LiteralPath $cachePath -Algorithm SHA256).Hash -ne $Sha256) {
                throw [IO.InvalidDataException]::new("Shared PAK cache hash mismatch: '$cachePath'.")
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    return $cachePath
}

function New-QuakeStaging {
    <#
    .SYNOPSIS
        Stage a DOS build, its DPMI host and the game data into a run directory.

    .DESCRIPTION
        The layout is fixed because the batch files and the DOSBox autoexec both
        assume it:  <staging>\quake\{quake.exe,cwsdpmi.exe,<batch>}  and
        <staging>\quake\id1\*.pak.

        Prefer hardlinks for immutable PAKs. If the source is on another volume
        or has exhausted its NTFS hardlink count, use a SHA-256 verified shared
        cache under benchmarks\out\.pak-cache\<UTC date> and hardlink to that
        entry. Daily cache files bound NTFS hardlink fanout. If hardlinks remain
        unavailable, fall back to a SHA-256 verified copy.

        Only paks are staged.  A Steam id1 directory also holds configs, saves and
        autoexec lines, and a local autoexec can prevent +quit from ever returning
        under the cycle cap -- which reads as a hung emulator, not as bad data.

    .PARAMETER OnExistingStaging
        Throw    refuse to touch an existing directory (bench, timedemo, which
                 stamp their directory with a UTC timestamp).
        Overwrite remove it first (smoke, whose directory name is fixed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$StagedExecutableName,
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [ValidateSet('Throw', 'Overwrite')][string]$OnExistingStaging = 'Throw',
        [switch]$StageDpmiHost
    )

    $StagingRoot = [IO.Path]::GetFullPath($StagingRoot)
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $script:BenchmarkRepositoryRoot 'out'))
    if (-not $StagingRoot.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Staging must be a child of '$allowedRoot': '$StagingRoot'."
    }
    $ancestor = $StagingRoot
    while ($ancestor -and $ancestor -ne [IO.Path]::GetPathRoot($ancestor)) {
        if ((Test-Path -LiteralPath $ancestor) -and
            ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Staging must not traverse a reparse point: '$ancestor'."
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    # Validate inputs before creating or replacing any staging directory.
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Missing executable '$Executable'." }
    if ([IO.Path]::GetFileName($StagedExecutableName) -ne $StagedExecutableName) { throw 'Staged executable name must be a filename.' }
    if (-not (Test-Path -LiteralPath (Join-Path $DataRoot 'pak0.pak') -PathType Leaf)) {
        throw "'$DataRoot' must contain legally obtained pak0.pak. Pass -DataRoot."
    }
    $pakFiles = @(Get-ChildItem -LiteralPath $DataRoot -Filter 'pak*.pak' -File)
    if (Test-Path -LiteralPath $StagingRoot) {
        if ($OnExistingStaging -eq 'Throw') {
            throw "Staging path already exists; refusing to overwrite '$StagingRoot'."
        }
        foreach ($inputPath in @($Executable, $DataRoot)) {
            $fullInput = [IO.Path]::GetFullPath($inputPath)
            if ($fullInput -eq $StagingRoot -or $fullInput.StartsWith($StagingRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to overwrite staging containing an input: '$fullInput'."
            }
        }
        if (@(Get-ChildItem -LiteralPath $StagingRoot -Recurse -Force |
                Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
            throw "Refusing to overwrite staging containing reparse points: '$StagingRoot'."
        }
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
    $quakeRoot = Join-Path $StagingRoot 'quake'
    $stagedData = Join-Path $quakeRoot 'id1'
    New-Item -ItemType Directory -Path $stagedData -Force | Out-Null

    Copy-Item -LiteralPath $Executable -Destination (Join-Path $quakeRoot $StagedExecutableName) -Force
    if ($StageDpmiHost) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'src\cwsdpmi.exe') `
            -Destination (Join-Path $quakeRoot 'cwsdpmi.exe') -Force
    }

    $storage = @()
    foreach ($pak in $pakFiles) {
        $destination = Join-Path $stagedData $pak.Name
        $sourceHash = (Get-FileHash -LiteralPath $pak.FullName -Algorithm SHA256).Hash
        $method = 'hardlink'
        $cachePath = $null
        try {
            New-Item -ItemType HardLink -Path $destination -Value $pak.FullName -ErrorAction Stop | Out-Null
        }
        catch {
            try {
                $cachePath = Get-OrCreateSharedPakCacheFile -SourcePath $pak.FullName -FileName $pak.Name -Sha256 $sourceHash
                New-Item -ItemType HardLink -Path $destination -Value $cachePath -ErrorAction Stop | Out-Null
                $method = 'hardlink-cache'
            }
            catch [IO.InvalidDataException] {
                throw
            }
            catch {
                if (Test-Path -LiteralPath $destination -PathType Leaf) {
                    Remove-Item -LiteralPath $destination -Force
                }
                $cachePath = $null
                $method = 'copy'
                Copy-Item -LiteralPath $pak.FullName -Destination $destination -ErrorAction Stop
            }
        }
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) {
            throw "Staged PAK hash mismatch: '$destination'."
        }
        $storage += [pscustomobject]@{ name=$pak.Name; source=$pak.FullName; sha256=$sourceHash; storage=$method; cache=$cachePath }
    }
    $storage | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StagingRoot 'staged-data.json') -Encoding utf8
    Get-BenchmarkToolingProvenance | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $StagingRoot 'tooling-provenance.json') -Encoding utf8

    return [pscustomobject]@{
        StagingRoot = $StagingRoot
        QuakeRoot   = $quakeRoot
        StagedData  = $stagedData
        PakFiles    = @($pakFiles)
    }
}
