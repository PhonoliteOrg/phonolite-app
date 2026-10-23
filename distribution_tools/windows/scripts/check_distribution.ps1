#Requires -Version 5.1
# Exercises packaging with a supplied signing identity; never installs or runs the payload.
[CmdletBinding(DefaultParameterSetName = 'Password')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CertificatePath,
    [Parameter(ParameterSetName = 'Password')][securestring]$CertificatePassword,
    [Parameter(Mandatory, ParameterSetName = 'PasswordFile')][ValidateNotNullOrEmpty()][string]$CertificatePasswordFile,
    [string]$ReleaseBundlePath,
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'distribution.psm1') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem

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
if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) { throw 'Supply an existing PFX with -CertificatePath.' }
$CertificatePath = (Resolve-Path -LiteralPath $CertificatePath).ProviderPath
if ($CertificatePath.StartsWith($ProjectRoot.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The signing PFX must be outside the app directory.'
}
if ($PSCmdlet.ParameterSetName -eq 'PasswordFile') {
    $CertificatePassword = Read-DistributionPasswordFile $CertificatePasswordFile $ProjectRoot
    $CertificatePasswordFile = (Resolve-Path -LiteralPath $CertificatePasswordFile).ProviderPath
}
elseif (-not $CertificatePassword) { $CertificatePassword = Read-Host 'Private-key password' -AsSecureString }
$signingArguments = @{ CertificatePath = $CertificatePath }
if ($CertificatePasswordFile) { $signingArguments.CertificatePasswordFile = $CertificatePasswordFile }
else { $signingArguments.CertificatePassword = $CertificatePassword }
$fixture = Join-Path $ProjectRoot "build\windows_distribution_checks\$([guid]::NewGuid().ToString('N'))"
$fixtureProject = Join-Path $fixture 'phonolite-app'
$fixtureTools = Join-Path $fixtureProject 'distribution_tools\windows'
$fixtureScripts = Join-Path $fixtureTools 'scripts'
$bundle = Join-Path $fixtureProject 'build\windows\x64\runner\Release'
$null = New-Item -ItemType Directory -Path $fixtureTools, (Join-Path $bundle 'data\flutter_assets'),
    (Join-Path $fixtureProject 'assets\images') -Force
$windowsTools = Split-Path -Parent $PSScriptRoot
foreach ($name in @('build_msix.ps1', 'package_config.json')) {
    Copy-Item -LiteralPath (Join-Path $windowsTools $name) -Destination $fixtureTools
}
Copy-Item -LiteralPath $PSScriptRoot -Destination $fixtureTools -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\images\phonolite-logo-nobackground.png') `
    -Destination (Join-Path $fixtureProject 'assets\images\phonolite-logo-nobackground.png')
'Packaging test fixture. Never install or distribute.' | Set-Content -LiteralPath (Join-Path $fixtureProject 'LICENSE')
'version: 0.0.1+1' | Set-Content -LiteralPath (Join-Path $fixtureProject 'pubspec.yaml')
$configPath = Join-Path $fixtureTools 'package_config.json'
$config = Get-DistributionConfig $configPath
$config.identityName = 'PhonoliteOrg.PackagingFixture'
$config.displayName = 'Packaging fixture - do not install'
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

if ($ReleaseBundlePath) {
    Assert-ReleaseBundle $ReleaseBundlePath 'Phonolite.exe'
    Get-ChildItem -LiteralPath $ReleaseBundlePath -Force | Copy-Item -Destination $bundle -Recurse -Force
}
else {
    # Copy PE bytes only; none of these fixture binaries is ever executed.
    foreach ($name in @('Phonolite.exe', 'flutter_windows.dll', 'phonolite_opus.dll', 'phonolite_quic.dll',
            'phonolite_local_audio.dll', 'flutter_secure_storage_windows_plugin.dll', 'sqlite3.dll')) {
        Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\cmd.exe') -Destination (Join-Path $bundle $name)
    }
    foreach ($name in @('data\icudtl.dat', 'data\app.so', 'data\flutter_assets\AssetManifest.bin')) {
        [System.IO.File]::WriteAllBytes((Join-Path $bundle $name), [byte[]]::new(150000))
    }
}
$certificate = $null
try {
    $certificate = Get-DistributionCertificate $CertificatePath $CertificatePassword
    $thumbprint = $certificate.Thumbprint
    $config.publisher = $certificate.Subject
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    $personalWasPresent = Test-Path -LiteralPath "Cert:\CurrentUser\My\$thumbprint"
    $trustWasPresent = @{}
    foreach ($store in @('CurrentUser\TrustedPeople', 'CurrentUser\Root', 'LocalMachine\TrustedPeople', 'LocalMachine\Root')) {
        $trustWasPresent[$store] = Test-Path -LiteralPath "Cert:\$store\$thumbprint"
    }
    Assert-Rejected 'invalid version' { ConvertTo-PackageVersion '1.0.65536.0' } 'between 0 and 65535'
    Assert-Rejected 'missing password file' {
        Read-DistributionPasswordFile (Join-Path $fixture 'missing.dpapi') $fixtureProject
    } 'password file not found'
    $invalidPasswordFile = Join-Path $fixture 'invalid.dpapi'
    'Not a DPAPI password' | Set-Content -LiteralPath $invalidPasswordFile
    Assert-Rejected 'invalid encrypted password file' {
        Read-DistributionPasswordFile $invalidPasswordFile $fixtureProject
    } 'Could not decrypt'
    Assert-Rejected 'conflicting password arguments' {
        & (Join-Path $fixtureTools 'build_msix.ps1') -SkipBuild -CertificatePath $CertificatePath `
            -CertificatePassword $CertificatePassword -CertificatePasswordFile $invalidPasswordFile
    } 'Parameter set cannot be resolved'
    $inProjectPasswordFile = Join-Path $fixtureProject 'invalid.dpapi'
    Copy-Item -LiteralPath $invalidPasswordFile -Destination $inProjectPasswordFile
    Assert-Rejected 'in-project password file' {
        & (Join-Path $fixtureTools 'build_msix.ps1') -SkipBuild -CertificatePath $CertificatePath `
            -CertificatePasswordFile $inProjectPasswordFile
    } 'outside the app directory'
    Remove-Item -LiteralPath $inProjectPasswordFile
    Assert-Rejected 'insecure feed URL' {
        New-AppInstallerFile $config '0.0.1.1' 'http://example.org/' 'test.msix' (Join-Path $fixture 'invalid.appinstaller')
    } 'absolute HTTPS'
    $secret = Join-Path $bundle 'accidental.pfx'
    'fixture' | Set-Content -LiteralPath $secret
    Assert-Rejected 'private key in payload' { Assert-ReleaseBundle $bundle 'Phonolite.exe' } 'private-key'
    Assert-Rejected 'in-project signing file' {
        & (Join-Path $fixtureTools 'build_msix.ps1') -SkipBuild -CertificatePath $secret -CertificatePassword $CertificatePassword
    } 'outside the app directory'
    Remove-Item -LiteralPath $secret

    $output = Join-Path $fixtureProject 'build\windows_distribution\0.0.1.1\x64'
    $null = New-Item -ItemType Directory -Path $output -Force
    & (Join-Path $fixtureTools 'build_msix.ps1') -SkipBuild @signingArguments `
        -BaseUrl 'https://example.org/phonolite/testing/x64/'
    Write-Host 'PASS: empty output directory can be reused'
    Assert-Rejected 'existing release output' {
        & (Join-Path $fixtureTools 'build_msix.ps1') -SkipBuild @signingArguments
    } 'Output already exists'
    if (Test-Path -LiteralPath (Join-Path $fixtureProject 'distribution_tools\build')) {
        throw 'Packaging created a build directory inside distribution_tools.'
    }
    $package = Join-Path $output 'Phonolite_0.0.1.1_x64.msix'
    $cer = Join-Path $output 'Phonolite-test.cer'
    if (@(Get-ChildItem -LiteralPath $output -Recurse -Filter '*.pfx').Count) { throw 'Private key leaked into output.' }
    if ((Test-Path -LiteralPath "Cert:\CurrentUser\My\$thumbprint") -ne $personalWasPresent) {
        throw 'Signing changed the pre-existing Personal certificate store state.'
    }
    foreach ($store in @('CurrentUser\TrustedPeople', 'CurrentUser\Root', 'LocalMachine\TrustedPeople', 'LocalMachine\Root')) {
        if ((Test-Path -LiteralPath "Cert:\$store\$thumbprint") -ne $trustWasPresent[$store]) {
            throw 'Signing modified a trust store.'
        }
    }
    Write-Host 'PASS: signed package, feed, multi-block hashes, and certificate/key isolation'

    $feedPath = Join-Path $output 'Phonolite-x64.appinstaller'
    [xml]$feed = Get-Content -LiteralPath $feedPath -Raw
    $feed.DocumentElement.MainPackage.SetAttribute('Version', '0.0.1.2')
    $feed.Save($feedPath)
    Assert-Rejected 'feed version mismatch' {
        & (Join-Path $fixtureScripts 'verify_msix.ps1') -PackagePath $package -CertificatePath $cer
    } 'do not match'

    $tampered = Join-Path $fixture 'tampered.msix'
    Copy-Item -LiteralPath $package -Destination $tampered
    $archive = [System.IO.Compression.ZipFile]::Open($tampered, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $stream = $archive.GetEntry('data/app.so').Open()
        try { $stream.WriteByte(42) } finally { $stream.Dispose() }
    }
    finally { $archive.Dispose() }
    $rejected = $false
    try { & (Join-Path $fixtureScripts 'verify_msix.ps1') -PackagePath $tampered -CertificatePath $cer }
    catch { $rejected = $true; Write-Host "PASS: modified payload rejected ($($_.Exception.Message))" }
    if (-not $rejected) { throw 'Modified package was accepted.' }
    Write-Host 'Distribution checks passed. Test fixtures remain under build/windows_distribution_checks; never distribute them.'
}
finally {
    if ($certificate) { $certificate.Dispose() }
}
