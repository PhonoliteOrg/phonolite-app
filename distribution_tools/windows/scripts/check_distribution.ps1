#Requires -Version 5.1
# Compiles packaging fixtures; never installs or runs the payload or installer.
[CmdletBinding()]
param(
    [string]$ReleaseBundlePath,
    [string]$NsisPath,
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'distribution.psm1') -Force

function Assert-Rejected {
    param([string]$Name, [scriptblock]$Action, [string]$ExpectedMessage)

    $rejected = $false
    try { & $Action }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Expected rejection: $Name" }
    Write-Host "PASS: $Name"
}

if (-not $ProjectRoot) { $ProjectRoot = Join-Path $PSScriptRoot '..\..\..' }
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$makensis = Find-NsisCompiler $NsisPath
$fixture = Join-Path $ProjectRoot "build\windows_distribution_checks\$([guid]::NewGuid().ToString('N'))"
$fixtureProject = Join-Path $fixture 'packaging fixture'
$fixtureTools = Join-Path $fixtureProject 'distribution_tools\windows'
$bundle = Join-Path $fixtureProject 'build\windows\x64\runner\Release'
$resources = Join-Path $fixtureProject 'windows\runner\resources'
$null = New-Item -ItemType Directory -Path $fixtureTools, (Join-Path $bundle 'data\flutter_assets'), $resources -Force
$windowsTools = Split-Path -Parent $PSScriptRoot
Copy-Item -LiteralPath (Join-Path $windowsTools 'build_nsis.ps1') -Destination $fixtureTools
Copy-Item -LiteralPath $PSScriptRoot -Destination $fixtureTools -Recurse
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'windows\runner\resources\phonolite-logo-windows.ico') -Destination $resources
'Packaging test fixture. Never install or distribute.' | Set-Content -LiteralPath (Join-Path $fixtureProject 'LICENSE')
'version: 0.0.1+1' | Set-Content -LiteralPath (Join-Path $fixtureProject 'pubspec.yaml')
$configPath = Join-Path $fixtureTools 'scripts\package_config.json'
$config = Get-DistributionConfig $configPath
$config.identityName = 'PhonoliteOrg.PackagingFixture'
$config.displayName = 'Packaging fixture - do not install'
$config.description = 'Packaging fixture with $dollars and "quotes"'
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

if ($ReleaseBundlePath) {
    Assert-ReleaseBundle $ReleaseBundlePath 'Phonolite.exe'
    Get-ChildItem -LiteralPath $ReleaseBundlePath -Force | Copy-Item -Destination $bundle -Recurse -Force
}
else {
    # Copy PE bytes only. None of these fixture binaries is ever executed.
    foreach ($name in @('Phonolite.exe', 'flutter_windows.dll', 'phonolite_opus.dll', 'phonolite_quic.dll',
            'phonolite_local_audio.dll', 'flutter_secure_storage_windows_plugin.dll', 'sqlite3.dll')) {
        Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\cmd.exe') -Destination (Join-Path $bundle $name)
    }
    foreach ($name in @('data\icudtl.dat', 'data\app.so', 'data\flutter_assets\AssetManifest.bin')) {
        [System.IO.File]::WriteAllBytes((Join-Path $bundle $name), [byte[]]::new(150000))
    }
}
$assetDirectory = Join-Path $bundle 'data\flutter_assets\nested folder'
$null = New-Item -ItemType Directory -Path $assetDirectory -Force
'Asset with a literal dollar in its filename.' | Set-Content -LiteralPath (Join-Path $assetDirectory 'price$1.txt')
'Excluded debug information' | Set-Content -LiteralPath (Join-Path $bundle 'Phonolite.pdb')

Assert-Rejected 'invalid version' { ConvertTo-PackageVersion '1.0.65536.0' } 'between 0 and 65535'
Assert-Rejected 'zero version' { ConvertTo-PackageVersion '0.0.0.0' } 'greater than'
Assert-Rejected 'three-part package version' { ConvertTo-PackageVersion '1.0.0' } 'four numeric'
Assert-Rejected 'signing options without a certificate' {
    & (Join-Path $fixtureTools 'build_nsis.ps1') -SkipBuild -NsisPath $makensis -TimestampUrl 'https://example.org/'
} 'require -CertificatePath'

$requiredDll = Join-Path $bundle 'phonolite_quic.dll'
Move-Item -LiteralPath $requiredDll -Destination "$requiredDll.saved"
try {
    Assert-Rejected 'missing native dependency' { Assert-ReleaseBundle $bundle 'Phonolite.exe' } 'missing phonolite_quic.dll'
}
finally { Move-Item -LiteralPath "$requiredDll.saved" -Destination $requiredDll }
$secret = Join-Path $bundle 'accidental.pfx'
'fixture' | Set-Content -LiteralPath $secret
try { Assert-Rejected 'private key in payload' { Assert-ReleaseBundle $bundle 'Phonolite.exe' } 'private-key' }
finally { Remove-Item -LiteralPath $secret }
$wrongArchitecture = Join-Path $bundle 'wrong_arch.dll'
Copy-Item -LiteralPath (Join-Path $env:WINDIR 'SysWOW64\cmd.exe') -Destination $wrongArchitecture
try { Assert-Rejected 'x86 binary in x64 bundle' { Assert-ReleaseBundle $bundle 'Phonolite.exe' } 'architecture' }
finally { Remove-Item -LiteralPath $wrongArchitecture }

$output = Join-Path $fixtureProject 'build\windows_distribution\0.0.1.1\x64'
$null = New-Item -ItemType Directory -Path $output -Force
& (Join-Path $fixtureTools 'build_nsis.ps1') -SkipBuild -NsisPath $makensis
Write-Host 'PASS: unsigned installer compiled without a certificate; empty output directory reused'
Assert-Rejected 'existing release output' {
    & (Join-Path $fixtureTools 'build_nsis.ps1') -SkipBuild -NsisPath $makensis
} 'Output already exists'
if (Test-Path -LiteralPath (Join-Path $output 'package\Phonolite.pdb')) { throw 'Debug symbols leaked into payload.' }
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'LICENSE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $output "package\$name"))) { throw "Missing staged file: $name" }
}
$package = Join-Path $output 'Phonolite_0.0.1.1_x64_setup.exe'
$metadataPath = Join-Path $output 'release.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.signed -or $metadata.certificateThumbprint) { throw 'Fixture should be unsigned.' }
$verifier = Join-Path $fixtureTools 'scripts\verify_nsis.ps1'
$originalMetadata = [System.IO.File]::ReadAllBytes($metadataPath)
$metadata.packageVersion = '0.0.1.2'
$metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding UTF8
try { Assert-Rejected 'metadata version mismatch' { & $verifier -PackagePath $package } 'does not match' }
finally { [System.IO.File]::WriteAllBytes($metadataPath, $originalMetadata) }
$stream = [System.IO.File]::Open($package, [System.IO.FileMode]::Append)
try { $stream.WriteByte(42) } finally { $stream.Dispose() }
Assert-Rejected 'modified installer' { & $verifier -PackagePath $package } 'SHA-256 mismatch'
Write-Host 'Distribution checks passed. Fixtures are under build/windows_distribution_checks; never distribute them.'
