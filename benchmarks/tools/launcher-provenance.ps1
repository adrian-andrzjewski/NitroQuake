Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-LauncherBuildManifestPath {
    [CmdletBinding()]
    param(
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ExecutablePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        $resolved = [IO.Path]::GetFullPath($ManifestPath)
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "Game build manifest does not exist: $resolved"
        }
        return $resolved
    }

    $executable = [IO.Path]::GetFullPath($ExecutablePath)
    $directory = Split-Path -Parent $executable
    $candidates = @(
        'build-manifest.json',
        'build-manifest-bench.json',
        'build-manifest-profile.json'
    ) | ForEach-Object { Join-Path $directory $_ }
    $executableHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        $manifest = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$manifest.executableSha256) -and
                [string]::Equals([string]$manifest.executableSha256, $executableHash,
                    [StringComparison]::OrdinalIgnoreCase)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw "No adjacent game build manifest matches '$executable'. Pass -GameBuildManifest explicitly."
}

function New-LauncherGameBuildIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][string]$GameRoot
    )

    $manifestFile = [IO.Path]::GetFullPath($ManifestPath)
    $executable = [IO.Path]::GetFullPath($ExecutablePath)
    if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
        throw "Game build manifest does not exist: $manifestFile"
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Game executable does not exist: $executable"
    }

    $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
    foreach ($name in @('productBuildId', 'productBuildFingerprintSha256',
                        'sourceCommit', 'sourceTreeSha256', 'cpuTarget',
                        'benchmarkBuild', 'profileBuild', 'executableSha256')) {
        if ($null -eq $manifest.PSObject.Properties[$name] -or
                [string]::IsNullOrWhiteSpace([string]$manifest.$name)) {
            throw "Game build manifest is missing required identity field '$name': $manifestFile"
        }
    }

    $executableHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::Equals([string]$manifest.executableSha256, $executableHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Game build manifest executable hash does not match '$executable'."
    }

    $gameRootFull = [IO.Path]::GetFullPath($GameRoot)
    $manifestPathForReport = [IO.Path]::GetRelativePath($gameRootFull, $manifestFile).Replace('\', '/')
    $manifestHash = (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        manifestPath = $manifestPathForReport
        manifestSha256 = $manifestHash
        productBuildId = [string]$manifest.productBuildId
        productBuildFingerprintSha256 = [string]$manifest.productBuildFingerprintSha256
        sourceCommit = [string]$manifest.sourceCommit
        sourceTreeSha256 = [string]$manifest.sourceTreeSha256
        cpuTarget = [string]$manifest.cpuTarget
        benchmarkBuild = [bool]$manifest.benchmarkBuild
        profileBuild = [bool]$manifest.profileBuild
        optimizationProfile = [string]$manifest.optimizationProfile
        executableSha256 = $executableHash
    }
}
