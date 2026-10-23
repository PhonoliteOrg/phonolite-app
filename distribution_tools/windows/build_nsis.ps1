#Requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Password')]
param(
    [string]$PackageVersion,
    [string]$CertificatePath,
    [Parameter(ParameterSetName = 'Password')][securestring]$CertificatePassword,
    [Parameter(Mandatory, ParameterSetName = 'PasswordFile')][ValidateNotNullOrEmpty()][string]$CertificatePasswordFile,
    [string]$TimestampUrl,
    [switch]$SkipBuild,
    [string]$NsisPath,
    [string]$ProjectRoot,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\distribution.psm1') -Force

if (-not $ProjectRoot) { $ProjectRoot = Join-Path $PSScriptRoot '..\..' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'scripts\package_config.json' }
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$config = Get-DistributionConfig $ConfigPath
if (-not $PackageVersion) { $PackageVersion = Get-PubspecPackageVersion $ProjectRoot }
$PackageVersion = ConvertTo-PackageVersion $PackageVersion
$makensis = Find-NsisCompiler $NsisPath
if (-not $CertificatePath -and ($CertificatePassword -or $CertificatePasswordFile -or $TimestampUrl)) {
    throw 'Signing options require -CertificatePath. Omit all signing options to build unsigned.'
}
if ($TimestampUrl) {
    $uri = $null
    if (-not [uri]::TryCreate($TimestampUrl, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'TimestampUrl must be an absolute HTTPS URL without credentials or a fragment.'
    }
}

$certificate = $null
try {
    if ($CertificatePath) {
        $signtool = Find-WindowsSdkTool 'signtool'
        if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) { throw 'Signing PFX not found.' }
        $CertificatePath = (Resolve-Path -LiteralPath $CertificatePath).ProviderPath
        if ($CertificatePath.StartsWith($ProjectRoot.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Keep the signing PFX outside the app directory.'
        }
        if ($PSCmdlet.ParameterSetName -eq 'PasswordFile') {
            $CertificatePassword = Read-DistributionPasswordFile $CertificatePasswordFile $ProjectRoot
        }
        elseif (-not $CertificatePassword) { $CertificatePassword = Read-Host 'Private-key password' -AsSecureString }
        $certificate = Get-DistributionCertificate $CertificatePath $CertificatePassword
        if (-not $certificate.HasPrivateKey -or $certificate.NotBefore -gt (Get-Date) -or
                $certificate.NotAfter -le (Get-Date)) {
            throw 'Signing requires a currently valid certificate with a private key.'
        }
    }

    $output = Join-Path $ProjectRoot "build\windows_distribution\$PackageVersion\x64"
    if ((Test-Path -LiteralPath $output) -and
            (-not (Test-Path -LiteralPath $output -PathType Container) -or
                @(Get-ChildItem -LiteralPath $output -Force).Count -gt 0)) {
        throw "Output already exists: $output. Increase -PackageVersion or move the old output."
    }
    if (-not $SkipBuild) {
        $flutter = (Get-Command flutter -ErrorAction Stop).Source
        $versionParts = $PackageVersion.Split('.')
        Push-Location $ProjectRoot
        try {
            Invoke-DistributionTool $flutter @('build', 'windows', '--release',
                '--build-name', ($versionParts[0..2] -join '.'), '--build-number', $versionParts[3])
        }
        finally { Pop-Location }
    }

    $bundle = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    Assert-ReleaseBundle $bundle $config.executable
    $stage = Join-Path $output 'package'
    $compilerDirectory = Join-Path $output 'nsis'
    $null = New-Item -ItemType Directory -Path $stage, $compilerDirectory -Force
    Get-ChildItem -LiteralPath $bundle -Force | Where-Object { $_.Extension -notin @('.pdb', '.exp', '.lib') } |
        Copy-Item -Destination $stage -Recurse
    Copy-VisualCppRuntime $stage
    Assert-ReleaseBundle $stage $config.executable
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
    $packageName = "Phonolite_${PackageVersion}_x64_setup.exe"
    $packagePath = Join-Path $output $packageName
    $icon = Join-Path $ProjectRoot 'windows\runner\resources\phonolite-logo-windows.ico'
    New-NsisBuildFiles $config $PackageVersion $stage $packagePath $icon $compilerDirectory
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\installer.nsi') -Destination $compilerDirectory
    # /WX rejects compiler warnings. This compiles only; the installer is never executed.
    Invoke-DistributionTool $makensis @('/V2', '/WX', (Join-Path $compilerDirectory 'installer.nsi'))

    if ($certificate) {
        # Use the Personal store temporarily so a password never appears on a command line.
        $storePath = "Cert:\CurrentUser\My\$($certificate.Thumbprint)"
        $temporaryImport = -not (Test-Path -LiteralPath $storePath)
        try {
            if ($temporaryImport) {
                $null = Import-PfxCertificate -FilePath $CertificatePath -Password $CertificatePassword `
                    -CertStoreLocation 'Cert:\CurrentUser\My'
            }
            $signArguments = @('sign', '/fd', 'SHA256', '/s', 'My', '/sha1', $certificate.Thumbprint,
                '/d', $config.displayName)
            if ($TimestampUrl) { $signArguments += @('/tr', $TimestampUrl, '/td', 'SHA256') }
            Invoke-DistributionTool $signtool ($signArguments + @($packagePath))
        }
        finally {
            if ($temporaryImport -and (Test-Path -LiteralPath $storePath)) {
                Remove-Item -LiteralPath $storePath -DeleteKey
            }
        }
    }

    $metadata = [ordered]@{
        format = 'nsis'
        identityName = $config.identityName
        packageVersion = $PackageVersion
        architecture = 'x64'
        installer = $packageName
        installerSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        signed = [bool]$certificate
        certificateThumbprint = if ($certificate) { $certificate.Thumbprint } else { $null }
        certificateSha256 = if ($certificate) { Get-CertificateSha256 $certificate } else { $null }
        timestamped = [bool]$TimestampUrl
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'release.json') -Encoding UTF8
    $hashes = Get-ChildItem -LiteralPath $output -File | Sort-Object Name | ForEach-Object {
        "$( (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
    }
    $hashes | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
    & (Join-Path $PSScriptRoot 'scripts\verify_nsis.ps1') -PackagePath $packagePath -ConfigPath $ConfigPath
    Write-Host "Distribution created: $output"
    if (-not $certificate) { Write-Host 'Unsigned installer created; Windows may display a SmartScreen warning.' }
}
finally {
    if ($certificate) { $certificate.Dispose() }
}
