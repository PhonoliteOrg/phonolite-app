#Requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Password')]
param(
    [string]$BaseUrl,
    [string]$PackageVersion,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CertificatePath,
    [Parameter(ParameterSetName = 'Password')][securestring]$CertificatePassword,
    [Parameter(Mandatory, ParameterSetName = 'PasswordFile')][ValidateNotNullOrEmpty()][string]$CertificatePasswordFile,
    [switch]$SkipBuild,
    [string]$ProjectRoot,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\distribution.psm1') -Force

if (-not $ProjectRoot) { $ProjectRoot = Join-Path $PSScriptRoot '..\..' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'package_config.json' }
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$config = Get-DistributionConfig $ConfigPath
if (-not $PackageVersion) { $PackageVersion = Get-PubspecPackageVersion $projectRoot }
$PackageVersion = ConvertTo-PackageVersion $PackageVersion
$makeappx = Find-WindowsSdkTool 'makeappx'
$signtool = Find-WindowsSdkTool 'signtool'
if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw 'Signing PFX not found. Supply an existing PFX with -CertificatePath.'
}
$CertificatePath = (Resolve-Path -LiteralPath $CertificatePath).ProviderPath
if ($CertificatePath.StartsWith($ProjectRoot.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the signing PFX outside the app directory and pass its external path with -CertificatePath.'
}
if ($PSCmdlet.ParameterSetName -eq 'PasswordFile') {
    $CertificatePassword = Read-DistributionPasswordFile $CertificatePasswordFile $ProjectRoot
}
elseif (-not $CertificatePassword) { $CertificatePassword = Read-Host 'Private-key password' -AsSecureString }
$certificate = Get-DistributionCertificate $CertificatePath $CertificatePassword

try {
    if (-not $certificate.HasPrivateKey -or $certificate.Subject -cne $config.publisher) {
        throw 'The signing certificate needs a private key and a Subject exactly matching package_config.json publisher.'
    }
    if ($certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) {
        throw 'The signing certificate is not currently valid.'
    }

    $output = Join-Path $ProjectRoot "build\windows_distribution\$PackageVersion\x64"
    if (Test-Path -LiteralPath $output) {
        if (-not (Test-Path -LiteralPath $output -PathType Container) -or
                @(Get-ChildItem -LiteralPath $output -Force).Count -gt 0) {
            throw "Output already exists: $output. Increase -PackageVersion or move the old output."
        }
    }

    if (-not $SkipBuild) {
        $flutter = (Get-Command flutter -ErrorAction Stop).Source
        $versionParts = $PackageVersion.Split('.')
        Push-Location $projectRoot
        try {
            Invoke-DistributionTool $flutter @('build', 'windows', '--release',
                '--build-name', ($versionParts[0..2] -join '.'), '--build-number', $versionParts[3])
        }
        finally { Pop-Location }
    }

    $bundle = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    Assert-ReleaseBundle $bundle $config.executable
    $null = New-Item -ItemType Directory -Path $output -Force
    $packageName = "Phonolite_${PackageVersion}_x64.msix"
    if ($BaseUrl) {
        New-AppInstallerFile $config $PackageVersion $BaseUrl $packageName (Join-Path $output 'Phonolite-x64.appinstaller')
    }
    $stage = Join-Path $output 'package'
    $null = New-Item -ItemType Directory -Path $stage
    Get-ChildItem -LiteralPath $bundle -Force | Where-Object { $_.Extension -notin @('.pdb', '.exp', '.lib') } |
        Copy-Item -Destination $stage -Recurse
    Copy-VisualCppRuntime $stage
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
    $assets = Join-Path $stage 'Assets'
    $null = New-Item -ItemType Directory -Path $assets
    New-PackageLogos (Join-Path $projectRoot 'assets\images\phonolite-logo-nobackground.png') $assets
    New-PackageManifest $config $PackageVersion (Join-Path $stage 'AppxManifest.xml')
    $packagePath = Join-Path $output $packageName
    Invoke-DistributionTool $makeappx @('pack', '/d', $stage, '/p', $packagePath, '/h', 'SHA256', '/no')

    # SignTool reads the key from the user Personal store, avoiding /p on its command line.
    # Import only for this signing operation; do not add anything to a trust store.
    $storePath = "Cert:\CurrentUser\My\$($certificate.Thumbprint)"
    $temporaryImport = -not (Test-Path -LiteralPath $storePath)
    try {
        if ($temporaryImport) {
            $null = Import-PfxCertificate -FilePath (Resolve-Path -LiteralPath $CertificatePath).Path `
                -Password $CertificatePassword -CertStoreLocation 'Cert:\CurrentUser\My'
        }
        Invoke-DistributionTool $signtool @('sign', '/fd', 'SHA256', '/s', 'My', '/sha1', $certificate.Thumbprint,
            '/d', $config.displayName, $packagePath)
    }
    finally {
        if ($temporaryImport -and (Test-Path -LiteralPath $storePath)) {
            Remove-Item -LiteralPath $storePath -DeleteKey
        }
    }

    $publicPath = Join-Path $output 'Phonolite-test.cer'
    [System.IO.File]::WriteAllBytes($publicPath,
        $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    $metadata = [ordered]@{
        identityName = $config.identityName
        publisher = $config.publisher
        packageVersion = $PackageVersion
        architecture = 'x64'
        certificateThumbprint = $certificate.Thumbprint
        certificateSha256 = Get-CertificateSha256 $certificate
        certificateExpiresUtc = $certificate.NotAfter.ToUniversalTime().ToString('o')
        timestamped = $false
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'release.json') -Encoding UTF8
    & (Join-Path $PSScriptRoot 'scripts\verify_msix.ps1') -PackagePath $packagePath -CertificatePath $publicPath -ConfigPath $ConfigPath

    $hashes = Get-ChildItem -LiteralPath $output -File | Sort-Object Name | ForEach-Object {
        "$( (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
    }
    $hashes | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
    Write-Host "Distribution created: $output"
    Write-Host 'This test signature is not timestamped; use the package before the certificate expires.'
    if (-not $BaseUrl) { Write-Host 'No BaseUrl supplied: local MSIX only, without a hosted update feed.' }
    Write-Host 'Nothing was installed, trusted, launched, or uploaded. Keep the PFX private.'
}
finally { $certificate.Dispose() }
