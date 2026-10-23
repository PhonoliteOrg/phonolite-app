#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'distribution.psm1') -Force
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'package_config.json' }
$config = Get-DistributionConfig $ConfigPath
$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
$directory = Split-Path $PackagePath -Parent
$metadata = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
$version = ConvertTo-PackageVersion $metadata.packageVersion
if ($metadata.format -cne 'nsis' -or $metadata.identityName -cne $config.identityName -or
        $metadata.architecture -cne 'x64' -or $metadata.installer -cne (Split-Path $PackagePath -Leaf) -or
        $metadata.installer -cne "Phonolite_${version}_x64_setup.exe") {
    throw 'Release metadata does not match the NSIS installer.'
}
if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash -ine $metadata.installerSha256) {
    throw 'Installer SHA-256 mismatch.'
}

$checked = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $directory 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$') { throw 'Invalid SHA256SUMS entry.' }
    $hash = $Matches[1]
    $name = $Matches[2]
    if ($checked.ContainsKey($name) -or $name -notin @($metadata.installer, 'release.json')) {
        throw "Unexpected checksum entry: $name"
    }
    if ((Get-FileHash -LiteralPath (Join-Path $directory $name) -Algorithm SHA256).Hash -ine $hash) {
        throw "Release checksum mismatch: $name"
    }
    $checked[$name] = $true
}
if ($checked.Count -ne 2) { throw 'Release checksums must cover the installer and release.json.' }

# NSIS uses a 32-bit bootstrapper to install the validated x64 application bundle.
Assert-PeArchitecture $PackagePath 0x014c
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($PackagePath)
if ($versionInfo.ProductVersion -ne $version -or $versionInfo.FileVersion -ne $version) {
    throw 'Installer version resource does not match release metadata.'
}
$signature = Get-AuthenticodeSignature -LiteralPath $PackagePath
if ($metadata.signed) {
    if (-not $signature.SignerCertificate -or
            $signature.SignerCertificate.Thumbprint -ine $metadata.certificateThumbprint -or
            (Get-CertificateSha256 $signature.SignerCertificate) -ine $metadata.certificateSha256) {
        throw 'Installer signer differs from release metadata.'
    }
    if (-not ('PhonoliteDistribution.SignatureVerifier' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'signature_verification.cs')
    }
    $trust = [PhonoliteDistribution.SignatureVerifier]::Verify($PackagePath)
    $selfSigned = $signature.SignerCertificate.Subject -ceq $signature.SignerCertificate.Issuer
    if ($trust -ne 0 -and -not ($trust -eq 0x800B0109L -and $selfSigned)) {
        throw ('Installer signature verification failed: 0x{0:X8}' -f $trust)
    }
}
elseif ($signature.Status -ne 'NotSigned' -or $metadata.certificateThumbprint -or
        $metadata.certificateSha256 -or $metadata.timestamped) {
    throw 'Unsigned release has unexpected signing information.'
}
Write-Host "Verified NSIS installer $version, PE headers, version resources, SHA-256 checksums and signing state."
