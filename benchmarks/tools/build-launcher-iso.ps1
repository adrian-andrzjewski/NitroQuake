[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$DataRoot,
    [string]$NitroExecutable,
    [string]$OutputPath,
    [string]$ToolRoot,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'workspace.ps1')
$suiteRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $suiteRoot '..'))
$gameRoot = Resolve-NitroQuakeGameRoot -GameRoot $GameRoot
$isoSourceRoot = Join-Path $suiteRoot 'iso'
$baselineRoot = Join-Path $suiteRoot 'baselines'
$toolManifestPath = Join-Path $gameRoot 'tools/dos-toolchain.json'
$toolManifest = Get-Content -LiteralPath $toolManifestPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw 'Could not determine the local tool cache directory. Pass -ToolRoot.'
    }
    $ToolRoot = Join-Path $localAppData '486quake/tools'
}
$ToolRoot = [IO.Path]::GetFullPath($ToolRoot)

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $gameRoot 'testdata/id1'
}
$DataRoot = [IO.Path]::GetFullPath($DataRoot)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $suiteRoot 'out/NitroQuake-Portable.iso'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$protectedIso = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'out/NitroQuake-Benchmark.iso'))
if ([string]::Equals($OutputPath, $protectedIso, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The retained benchmark ISO is protected. Choose another output path: $protectedIso"
}
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "Output already exists; pass -Force to replace this portable ISO: $OutputPath"
}

foreach ($requiredName in @('pak0.pak', 'pak1.pak')) {
    $requiredPak = Join-Path $DataRoot $requiredName
    if (-not (Test-Path -LiteralPath $requiredPak -PathType Leaf)) {
        throw "Missing $requiredName under '$DataRoot'. Supply legally obtained PAK files with -DataRoot."
    }
}

$baselineManifestPath = Join-Path $baselineRoot 'local-artifacts.json'
$baselineManifest = Get-Content -LiteralPath $baselineManifestPath -Raw | ConvertFrom-Json
function Assert-LocalBaseline {
    param([Parameter(Mandatory)][string]$Name)
    $definitions = @($baselineManifest | Where-Object {
        [string]::Equals([string]$_.name, $Name, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($definitions.Count -ne 1) {
        throw "Expected exactly one local-artifact hash for $Name in $baselineManifestPath."
    }
    $path = Join-Path $baselineRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing local baseline executable: $path"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$definitions[0].sha256).ToLowerInvariant()) {
        throw "SHA-256 mismatch for $path; refusing to package an unverified baseline."
    }
    return $path
}
$q486Executable = Assert-LocalBaseline -Name '486quake.exe'
$quakeExecutable = Assert-LocalBaseline -Name 'QUAKE.EXE'

if ([string]::IsNullOrWhiteSpace($NitroExecutable)) {
    $gameBuildName = 'iso-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' +
        [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $buildScript = Join-Path $gameRoot 'tools/build-dos.ps1'
    Write-Host "Building the i486 NitroQuake executable ($gameBuildName)."
    & $buildScript -Configuration i486-release -CpuTarget i486 -LocalOutputDirectoryName $gameBuildName -ToolRoot $ToolRoot
    $NitroExecutable = Join-Path $gameRoot ("out/local-{0}/quake.exe" -f $gameBuildName)
} else {
    $NitroExecutable = [IO.Path]::GetFullPath($NitroExecutable)
}
if (-not (Test-Path -LiteralPath $NitroExecutable -PathType Leaf)) {
    throw "NitroQuake executable was not produced or does not exist: $NitroExecutable"
}

$djgppRoot = Join-Path $ToolRoot $toolManifest.djgpp.installDirectory
$compiler = Join-Path $djgppRoot ($toolManifest.djgpp.compiler -replace '/', [IO.Path]::DirectorySeparatorChar)
$assembler = Join-Path $djgppRoot 'bin/i586-pc-msdosdjgpp-as.exe'
$linker = Join-Path $djgppRoot 'bin/i586-pc-msdosdjgpp-ld.exe'
$objcopy = Join-Path $djgppRoot 'bin/i586-pc-msdosdjgpp-objcopy.exe'
foreach ($toolPath in @($compiler, $assembler, $linker, $objcopy)) {
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        throw "Pinned DJGPP tool is missing: $toolPath. Run tools/bootstrap-dos.ps1 first."
    }
}

$cwsdpmiSource = Join-Path $gameRoot 'src/cwsdpmi.exe'
$cwsdpmiLicense = Join-Path $gameRoot 'tools/isa-provider-reference/primary/COPYING.CWS'
foreach ($required in @($cwsdpmiSource, $cwsdpmiLicense)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required DPMI host input is missing: $required"
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    throw 'Python 3.9 or later is required to write the ISO-9660 image.'
}
$pythonVersion = & $python.Source --version 2>&1
if ($LASTEXITCODE -ne 0 -or $pythonVersion -notmatch 'Python 3\.(9|[1-9][0-9])') {
    throw "Python 3.9 or later is required; found '$pythonVersion'."
}

$benchOut = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'out'))
New-Item -ItemType Directory -Path $benchOut -Force | Out-Null
$stageName = '.iso-stage-' + [Guid]::NewGuid().ToString('N')
$stage = Join-Path $benchOut $stageName
if (Test-Path -LiteralPath $stage) {
    throw "Refusing to reuse an existing ISO staging path: $stage"
}
New-Item -ItemType Directory -Path $stage | Out-Null

function Copy-IsoFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "ISO input is missing: $Source"
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

try {
    $nq = Join-Path $stage 'NQ'
    $id1 = Join-Path $nq 'ID1'
    New-Item -ItemType Directory -Path $id1 -Force | Out-Null

    Copy-IsoFile (Join-Path $isoSourceRoot 'README.TXT') (Join-Path $stage 'README.TXT')
    Copy-IsoFile (Join-Path $isoSourceRoot 'START.BAT') (Join-Path $stage 'START.BAT')
    foreach ($name in @('NQ.ID', 'START.BAT', 'RUNNQ.BAT', 'RUN486.BAT', 'RUNQUAKE.BAT',
                        'DEMO1.BAT', 'DEMO2.BAT', 'DEMO3.BAT', 'ALLDEMO.BAT')) {
        Copy-IsoFile (Join-Path $isoSourceRoot ("NQ/{0}" -f $name)) (Join-Path $nq $name)
    }
    Copy-IsoFile (Join-Path $isoSourceRoot 'NQ/ID1/CONFIG.CFG') (Join-Path $id1 'CONFIG.CFG')
    Copy-IsoFile $NitroExecutable (Join-Path $nq 'NQ.EXE')
    Copy-IsoFile $q486Executable (Join-Path $nq 'Q486.EXE')
    Copy-IsoFile $quakeExecutable (Join-Path $nq 'QUAKE.EXE')
    Copy-IsoFile (Join-Path $DataRoot 'pak0.pak') (Join-Path $id1 'PAK0.PAK')
    Copy-IsoFile (Join-Path $DataRoot 'pak1.pak') (Join-Path $id1 'PAK1.PAK')
    # The writable copy is used by DJGPP. Keep the CD copy from being auto-selected.
    Copy-IsoFile $cwsdpmiSource (Join-Path $nq 'CWSDPMI.DAT')
    Copy-IsoFile $cwsdpmiLicense (Join-Path $nq 'COPYING.CWS')

    $oldDjdir = $env:DJDIR
    $oldGccExecPrefix = $env:GCC_EXEC_PREFIX
    $oldPath = $env:PATH
    try {
        $env:DJDIR = Join-Path $djgppRoot 'i586-pc-msdosdjgpp'
        $env:GCC_EXEC_PREFIX = Join-Path $djgppRoot 'lib/gcc/'
        $env:PATH = (Join-Path $djgppRoot 'bin') + ';' +
            (Join-Path $djgppRoot 'i586-pc-msdosdjgpp/bin') + ';' + $oldPath

        $launcherSource = Join-Path $isoSourceRoot 'NQ/LAUNCHER.C'
        $menuOutput = Join-Path $nq 'NQMENU.EXE'
        $compilerArgs = @(
            '-x', 'c', '-Os', '-march=i386', '-mtune=i486', '-Wall', '-Wextra', '-Werror',
            '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections', '-s',
            $launcherSource, '-o', $menuOutput
        )
        & $compiler @compilerArgs
        if ($LASTEXITCODE -ne 0) {
            throw "DJGPP failed to build NQMENU.EXE (exit $LASTEXITCODE)."
        }

        $object = Join-Path $stage 'PREP.OBJ'
        $linked = Join-Path $stage 'PREP.LNK'
        $prepSource = Join-Path $isoSourceRoot 'NQ/PREP.S'
        $prepOutput = Join-Path $nq 'NQPREP.COM'
        & $assembler --32 $prepSource '-o' $object
        if ($LASTEXITCODE -ne 0) {
            throw "GNU assembler failed to build NQPREP.COM (exit $LASTEXITCODE)."
        }
        & $linker '-m' 'i386go32' '-Ttext=0x100' '-e' '_start' '-o' $linked $object
        if ($LASTEXITCODE -ne 0) {
            throw "GNU linker failed to build NQPREP.COM (exit $LASTEXITCODE)."
        }
        & $objcopy '-O' 'binary' '-j' '.text' $linked $prepOutput
        if ($LASTEXITCODE -ne 0) {
            throw "GNU objcopy failed to build NQPREP.COM (exit $LASTEXITCODE)."
        }
        if ((Get-Item -LiteralPath $prepOutput).Length -ge 65536) {
            throw 'NQPREP.COM exceeds the DOS .COM size limit.'
        }
        Remove-Item -LiteralPath $object, $linked -Force
    } finally {
        $env:DJDIR = $oldDjdir
        $env:GCC_EXEC_PREFIX = $oldGccExecPrefix
        $env:PATH = $oldPath
    }

    $writer = Join-Path $PSScriptRoot 'build-iso9660.py'
    $writerArgs = @('--tree', $stage, '--output', $OutputPath, '--volume-id', 'NQBENCH')
    if ($Force) { $writerArgs += '--force' }
    & $python.Source $writer @writerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ISO-9660 writer failed (exit $LASTEXITCODE)."
    }

    $fileManifest = @(Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object {
        [pscustomobject]@{
            path = [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object path)
    $isoInfo = Get-Item -LiteralPath $OutputPath
    $sidecar = [IO.Path]::ChangeExtension($OutputPath, '.manifest.json')
    $manifest = [ordered]@{
        format = 'nitroquake-portable-iso-v1'
        createdUtc = [DateTime]::UtcNow.ToString('o')
        volumeId = 'NQBENCH'
        gameRevision = (& git -C $gameRoot rev-parse HEAD).Trim()
        gameExecutable = [ordered]@{
            bytes = (Get-Item -LiteralPath $NitroExecutable).Length
            sha256 = (Get-FileHash -LiteralPath $NitroExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        iso = [ordered]@{
            path = [IO.Path]::GetFileName($OutputPath)
            bytes = $isoInfo.Length
            sha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        files = $fileManifest
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sidecar -Encoding utf8
    Write-Host "Portable DOS ISO built: $OutputPath"
    Write-Host "Build manifest: $sidecar"
    Write-Host "Menu: $((Get-Item -LiteralPath (Join-Path $nq 'NQMENU.EXE')).Length) bytes; real-mode prep: $((Get-Item -LiteralPath (Join-Path $nq 'NQPREP.COM')).Length) bytes."
} finally {
    # This uniquely named tree belongs to this invocation and contains only
    # reproducible ISO inputs. Clean it on success and failure to avoid leaving
    # PAK-sized staging debris after a compiler or image-writer error.
    if (Test-Path -LiteralPath $stage -PathType Container) {
        $stageFull = [IO.Path]::GetFullPath($stage)
        $allowedPrefix = $benchOut.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $stageFull.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove staging tree outside benchmarks/out: $stageFull"
        }
        $stageItem = Get-Item -LiteralPath $stageFull -Force
        if ($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to remove a redirected ISO staging tree: $stageFull"
        }
        $redirectedChildren = @(Get-ChildItem -LiteralPath $stageFull -Force -Recurse |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($redirectedChildren.Count -gt 0) {
            throw "Refusing to remove ISO staging tree containing a reparse point: $($redirectedChildren[0].FullName)"
        }
        Remove-Item -LiteralPath $stageFull -Recurse -Force
    }
}
