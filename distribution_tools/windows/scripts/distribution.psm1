Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DistributionConfig {
    param([Parameter(Mandatory)][string]$Path)

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in @('identityName', 'publisher', 'publisherDisplayName', 'displayName', 'description',
            'executable', 'minimumWindowsVersion', 'maximumWindowsVersionTested')) {
        if (-not $config.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace($config.$name)) {
            throw "Missing package configuration: $name"
        }
    }
    if ($config.identityName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') {
        throw 'identityName must contain 3-50 letters, digits, periods or hyphens.'
    }
    if ($config.executable -notmatch '^[A-Za-z0-9_.-]+\.exe$') {
        throw 'executable must be an EXE filename, without a directory.'
    }
    foreach ($name in @('minimumWindowsVersion', 'maximumWindowsVersionTested')) {
        $null = ConvertTo-PackageVersion $config.$name
    }
    if ([version]$config.minimumWindowsVersion -lt [version]'10.0.19041.0' -or
            [version]$config.maximumWindowsVersionTested -lt [version]$config.minimumWindowsVersion) {
        throw 'Windows versions must satisfy 10.0.19041.0 <= minimum <= maximum tested.'
    }
    return $config
}

function ConvertTo-PackageVersion {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "MSIX version must have four numeric components: $Value"
    }
    $parts = @($Value.Split('.') | ForEach-Object {
        $number = [int]$_
        if ($number -gt 65535) { throw 'MSIX version components must be between 0 and 65535.' }
        $number
    })
    if ($parts[0] -eq 0 -and $parts[1] -eq 0 -and $parts[2] -eq 0 -and $parts[3] -eq 0) {
        throw 'MSIX version must be greater than 0.0.0.0.'
    }
    return $parts -join '.'
}

function Get-PubspecPackageVersion {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $content = Get-Content -LiteralPath (Join-Path $ProjectRoot 'pubspec.yaml') -Raw
    if ($content -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*(?:#.*)?$') {
        throw 'pubspec.yaml needs a numeric major.minor.patch+build version, or pass -PackageVersion.'
    }
    $revision = if ($Matches[4]) { $Matches[4] } else { '0' }
    return ConvertTo-PackageVersion "$($Matches[1]).$($Matches[2]).$($Matches[3]).$revision"
}

function Find-WindowsSdkTool {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $sdkRoot) {
        $versions = Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Where-Object { $_.Name -match '^10\.0\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending
        $hostArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        foreach ($version in $versions) {
            $candidate = Join-Path $version.FullName "$hostArchitecture\$Name.exe"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    throw "Cannot find $Name.exe. Install the Windows 10/11 SDK signing and packaging tools."
}

function Invoke-DistributionTool {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)

    & $Path @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path $Path -Leaf) failed with exit code $LASTEXITCODE."
    }
}

function Read-DistributionPasswordFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ProjectRoot)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Encrypted PFX password file not found. Supply an existing DPAPI file with -CertificatePasswordFile.'
    }
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    if ($Path.StartsWith($ProjectRoot.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Keep the encrypted password file outside the app directory and pass its external path with -CertificatePasswordFile.'
    }
    try {
        # ConvertTo-SecureString decrypts the existing DPAPI file without exposing plaintext.
        $encryptedPassword = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim()
        return ConvertTo-SecureString -String $encryptedPassword -ErrorAction Stop
    }
    catch {
        throw 'Could not decrypt the PFX password file. Use a DPAPI password file created by the same Windows account on this computer.'
    }
}

function Get-DistributionCertificate {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][securestring]$Password)

    # The PFX password is never passed to a child process or written to a file.
    return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path), $Password,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
}

function Get-CertificateSha256 {
    param([Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Certificate.RawData))).Replace('-', '') }
    finally { $hash.Dispose() }
}

function Assert-ReleaseBundle {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Executable)

    foreach ($name in @($Executable, 'flutter_windows.dll', 'phonolite_opus.dll', 'phonolite_quic.dll',
            'phonolite_local_audio.dll', 'flutter_secure_storage_windows_plugin.dll',
            'sqlite3.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets\AssetManifest.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $name) -PathType Leaf)) {
            throw "Release bundle is incomplete; missing $name in $Path"
        }
    }
    $links = Get-ChildItem -LiteralPath $Path -Recurse -Force |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }
    if ($links) { throw 'Release bundle contains symbolic links or junctions; use a self-contained bundle.' }
    $secrets = Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
        Where-Object { $_.Extension -in @('.pfx', '.p12', '.key', '.pem') }
    if ($secrets) { throw 'Release bundle contains private-key file types; remove them before packaging.' }
}

function Copy-VisualCppRuntime {
    param([Parameter(Mandatory)][string]$Destination)

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio vswhere.exe is required to locate redistributable runtimes.' }
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Cannot locate a Visual Studio C++ installation.' }
    $redist = Join-Path $installation 'VC\Redist\MSVC'
    $runtimeDirectory = Get-ChildItem -LiteralPath $redist -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' } |
        Select-Object -First 1
    if (-not $runtimeDirectory) { throw 'Install Visual Studio C++ Redistributable SDK components before packaging.' }
    Get-ChildItem -LiteralPath $runtimeDirectory.FullName -Filter '*.dll' |
        Copy-Item -Destination $Destination -Force
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination $name))) { throw "Missing app-local C++ runtime: $name" }
    }
}

function New-PackageLogos {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($Source)
    try {
        foreach ($size in @(44, 50, 150)) {
            $bitmap = [System.Drawing.Bitmap]::new($size, $size)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $scale = [Math]::Min($size / $image.Width, $size / $image.Height)
                $width = [int][Math]::Max(1, [Math]::Round($image.Width * $scale))
                $height = [int][Math]::Max(1, [Math]::Round($image.Height * $scale))
                $graphics.DrawImage($image, [int](($size - $width) / 2), [int](($size - $height) / 2), $width, $height)
                $bitmap.Save((Join-Path $Destination "Logo$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $graphics.Dispose(); $bitmap.Dispose() }
        }
    }
    finally { $image.Dispose() }
}

function Write-DistributionXml {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][string]$Path)

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Document.Save($writer) } finally { $writer.Dispose() }
}

function New-PackageManifest {
    param($Config, [string]$Version, [string]$Path)

    [xml]$document = @'
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="" Publisher="" Version="" ProcessorArchitecture="x64" />
  <Properties><DisplayName /><PublisherDisplayName /><Description /><Logo>Assets\Logo50.png</Logo></Properties>
  <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="" MaxVersionTested="" /></Dependencies>
  <Resources><Resource Language="en-us" /></Resources>
  <Applications>
    <Application Id="Phonolite" Executable="" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="" Description="" BackgroundColor="transparent"
                          Square150x150Logo="Assets\Logo150.png" Square44x44Logo="Assets\Logo44.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
'@
    $package = $document.DocumentElement
    $package.Identity.SetAttribute('Name', $Config.identityName)
    $package.Identity.SetAttribute('Publisher', $Config.publisher)
    $package.Identity.SetAttribute('Version', $Version)
    $package.Properties.DisplayName = $Config.displayName
    $package.Properties.PublisherDisplayName = $Config.publisherDisplayName
    $package.Properties.Description = $Config.description
    $family = $package.Dependencies.TargetDeviceFamily
    $family.SetAttribute('MinVersion', $Config.minimumWindowsVersion)
    $family.SetAttribute('MaxVersionTested', $Config.maximumWindowsVersionTested)
    $application = $package.Applications.Application
    $application.SetAttribute('Executable', $Config.executable)
    $visuals = $application.GetElementsByTagName('VisualElements', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')[0]
    $visuals.SetAttribute('DisplayName', $Config.displayName)
    $visuals.SetAttribute('Description', $Config.description)
    Write-DistributionXml $document $Path
}

function New-AppInstallerFile {
    param($Config, [string]$Version, [string]$BaseUrl, [string]$PackageName, [string]$Path)

    $uri = $null
    if (-not [uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or
            $uri.Query -or $uri.Fragment -or $uri.UserInfo) {
        throw 'BaseUrl must be an absolute HTTPS directory URL without credentials, query, or fragment.'
    }
    $base = $uri.AbsoluteUri.TrimEnd('/') + '/'
    [xml]$document = @'
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018" Uri="" Version="">
  <MainPackage Name="" Publisher="" Version="" ProcessorArchitecture="x64" Uri="" />
  <UpdateSettings><OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="false" /></UpdateSettings>
</AppInstaller>
'@
    $root = $document.DocumentElement
    $root.SetAttribute('Uri', $base + 'Phonolite-x64.appinstaller')
    $root.SetAttribute('Version', $Version)
    $root.MainPackage.SetAttribute('Name', $Config.identityName)
    $root.MainPackage.SetAttribute('Publisher', $Config.publisher)
    $root.MainPackage.SetAttribute('Version', $Version)
    $root.MainPackage.SetAttribute('Uri', $base + [uri]::EscapeDataString($PackageName))
    Write-DistributionXml $document $Path
}

Export-ModuleMember -Function Get-DistributionConfig, ConvertTo-PackageVersion, Get-PubspecPackageVersion,
    Find-WindowsSdkTool, Invoke-DistributionTool, Read-DistributionPasswordFile, Get-DistributionCertificate, Get-CertificateSha256,
    Assert-ReleaseBundle, Copy-VisualCppRuntime, New-PackageLogos, New-PackageManifest, New-AppInstallerFile
