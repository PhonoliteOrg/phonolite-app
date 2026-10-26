#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [string]$ReleaseTag,
    [string]$ReleaseNotesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\distribution.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts\updates.psm1') -Force
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$PrivateKeyPath = Assert-ExternalUpdateKey $PrivateKeyPath $projectRoot
$config = Get-UpdatesConfig (Join-Path $PSScriptRoot 'scripts\updates_config.json')
$packageConfig = Get-DistributionConfig (Join-Path $PSScriptRoot 'scripts\package_config.json')
$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
& (Join-Path $PSScriptRoot 'scripts\verify_nsis.ps1') -PackagePath $PackagePath
$directory = Split-Path $PackagePath -Parent
$metadata = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
if (-not $ReleaseTag) {
    $pubspecVersion = Get-PubspecPackageVersion $projectRoot
    if ($pubspecVersion -cne $metadata.packageVersion) {
        throw 'The installer version differs from pubspec.yaml. Rebuild it, or pass -ReleaseTag explicitly for an existing package or -PackageVersion override.'
    }
    $ReleaseTag = 'v' + (($pubspecVersion.Split('.'))[0..2] -join '.')
}
$notes = if ($ReleaseNotesPath) { Get-Content -LiteralPath $ReleaseNotesPath -Raw -Encoding UTF8 } else { "Phonolite $($metadata.packageVersion) for Windows." }
$sdk = Get-WinSparkleSdk $projectRoot
$tool = Join-Path $sdk 'bin\winsparkle-tool.exe'
if ((Get-UpdatePublicKey $tool $PrivateKeyPath) -cne $config.publicKey) {
    throw 'This private key differs from the public key embedded in Phonolite.'
}
$signature = (@(& $tool sign --private-key-file $PrivateKeyPath $PackagePath) -join "`n").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not sign the update installer.' }
& $tool verify --public-key $config.publicKey --signature $signature $PackagePath
if ($LASTEXITCODE -ne 0) { throw 'The update signature could not be verified.' }
$minimumVersion = ($packageConfig.minimumWindowsVersion.Split('.'))[0..2] -join '.'
$appcast = New-WindowsAppcast -Config $config -Version $metadata.packageVersion -Installer $metadata.installer `
    -Length (Get-Item -LiteralPath $PackagePath).Length -Signature $signature -Tag $ReleaseTag `
    -MinimumWindowsVersion $minimumVersion -Notes $notes
$destination = Join-Path $directory $config.feedAsset
$settings = [Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.Encoding = [Text.UTF8Encoding]::new($false)
$writer = [Xml.XmlWriter]::Create($destination, $settings)
try { $appcast.Save($writer) } finally { $writer.Dispose() }
Write-Host "Ready for manual upload to GitHub release $ReleaseTag in $($config.repository):"
Write-Host "  $($metadata.installer)"
Write-Host '  release.json'
Write-Host '  SHA256SUMS.txt'
Write-Host "  $($config.feedAsset)"
Write-Host 'Upload all four files to a draft release, then publish it as Latest. Nothing was uploaded.'
