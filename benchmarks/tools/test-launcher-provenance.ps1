[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'launcher-provenance.ps1')

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition,
          [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetTempPath(),
    'nitroquake-launcher-provenance-' + [Guid]::NewGuid().ToString('N')))
$tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') +
    [IO.Path]::DirectorySeparatorChar
if (-not $tempRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create test fixtures outside the temporary directory: $tempRoot"
}
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $executable = Join-Path $tempRoot 'quake.exe'
    $manifestPath = Join-Path $tempRoot 'build-manifest.json'
    [IO.File]::WriteAllBytes($executable, [byte[]](0x51, 0x55, 0x41, 0x4B, 0x45))
    $executableHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        productBuildId = 'abcd1234-deadbeef'
        productBuildFingerprintSha256 = ('a' * 64)
        sourceCommit = ('b' * 40)
        sourceTreeSha256 = ('c' * 64)
        cpuTarget = 'i486'
        benchmarkBuild = $false
        profileBuild = $false
        optimizationProfile = 'aggressive'
        executableSha256 = $executableHash
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $resolved = Resolve-LauncherBuildManifestPath -ExecutablePath $executable
    Assert-True ($resolved -eq $manifestPath) 'Adjacent manifest discovery failed.'
    $identity = New-LauncherGameBuildIdentity -ManifestPath $resolved `
        -ExecutablePath $executable -GameRoot $tempRoot
    Assert-True ($identity.productBuildId -eq $manifest.productBuildId) 'Build ID was not preserved.'
    Assert-True ($identity.sourceCommit -eq $manifest.sourceCommit) 'Source revision was not preserved.'
    Assert-True ($identity.manifestSha256 -match '^[0-9a-f]{64}$') 'Manifest hash is missing.'
    Assert-True ($identity.executableSha256 -eq $executableHash) 'Executable hash was not preserved.'
    Write-Host 'launcher provenance manifest tests: PASS'

    $manifest.executableSha256 = ('d' * 64)
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $mismatchRejected = $false
    try {
        New-LauncherGameBuildIdentity -ManifestPath $manifestPath `
            -ExecutablePath $executable -GameRoot $tempRoot | Out-Null
    }
    catch { $mismatchRejected = $_.Exception.Message -match 'does not match' }
    Assert-True $mismatchRejected 'Manifest/executable mismatch was accepted.'
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    if (-not $resolvedTempRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolvedTempRoot).StartsWith('nitroquake-launcher-provenance-',
                [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected temporary test path: $resolvedTempRoot"
    }
    if (Test-Path -LiteralPath $resolvedTempRoot -PathType Container) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
