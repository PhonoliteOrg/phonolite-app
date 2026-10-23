Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DistributionConfig {
    param([Parameter(Mandatory)][string]$Path)

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in @('identityName', 'publisherDisplayName', 'displayName', 'description',
            'executable', 'minimumWindowsVersion')) {
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
    if ($config.displayName -match '[<>:"/\\|?*\x00-\x1f]' -or $config.displayName.EndsWith('.') -or
            $config.displayName.EndsWith(' ')) {
        throw 'displayName must be a valid Windows directory name.'
    }
    $null = ConvertTo-PackageVersion $config.minimumWindowsVersion
    $minimumVersion = [version]$config.minimumWindowsVersion
    if ($minimumVersion.Major -ne 10 -or $minimumVersion.Minor -ne 0 -or
            $minimumVersion.Build -lt 19041 -or $minimumVersion.Revision -ne 0) {
        throw 'minimumWindowsVersion must use 10.0.build.0 with a build of at least 19041.'
    }
    return $config
}

function ConvertTo-PackageVersion {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Package version must have four numeric components: $Value"
    }
    $parts = @($Value.Split('.') | ForEach-Object {
        $number = [int]$_
        if ($number -gt 65535) { throw 'Package version components must be between 0 and 65535.' }
        $number
    })
    if ($parts[0] -eq 0 -and $parts[1] -eq 0 -and $parts[2] -eq 0 -and $parts[3] -eq 0) {
        throw 'Package version must be greater than 0.0.0.0.'
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
    throw "Cannot find $Name.exe. Install the Windows 10/11 SDK signing tools for optional signing."
}

function Find-NsisCompiler {
    param([string]$Path)

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "NSIS compiler not found: $Path" }
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'NSIS\makensis.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Install NSIS 3, add makensis.exe to PATH, or supply -NsisPath.'
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
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
            Where-Object { $_.Extension -in @('.exe', '.dll') }) {
        Assert-PeArchitecture $file.FullName 0x8664
    }
}

function Assert-PeArchitecture {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$Machine)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Invalid PE binary: $Path" }
        $stream.Position = 60
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt $stream.Length - 6) { throw "Invalid PE header: $Path" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne $Machine) {
            throw "Unexpected PE architecture: $Path"
        }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
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

function ConvertTo-NsisLiteral {
    param([Parameter(Mandatory)][string]$Value)

    return $Value.Replace('$', '$$').Replace('"', '$\"').Replace("`r", '$\r').Replace("`n", '$\n')
}

function New-NsisBuildFiles {
    param($Config, [string]$Version, [string]$Stage, [string]$Output, [string]$Icon, [string]$Directory)

    $defines = [ordered]@{
        APP_ID = $Config.identityName
        APP_NAME = $Config.displayName
        APP_PUBLISHER = $Config.publisherDisplayName
        APP_DESCRIPTION = $Config.description
        APP_EXE = $Config.executable
        APP_VERSION = $Version
        MIN_WINDOWS_VERSION = $Config.minimumWindowsVersion
        MIN_WINDOWS_BUILD = ([version]$Config.minimumWindowsVersion).Build.ToString()
        PAYLOAD_DIR = $Stage
        INSTALLER_PATH = $Output
        APP_ICON = $Icon
    }
    $lines = foreach ($name in $defines.Keys) {
        '!define {0} "{1}"' -f $name, (ConvertTo-NsisLiteral $defines[$name])
    }
    $lines | Set-Content -LiteralPath (Join-Path $Directory 'config.nsh') -Encoding UTF8

    # Embed exact file names; never recursively delete a user-selected install folder.
    $files = @(Get-ChildItem -LiteralPath $Stage -Recurse -File -Force | Sort-Object FullName)
    $uninstall = @(foreach ($file in $files) {
        $relative = $file.FullName.Substring($Stage.TrimEnd('\').Length + 1)
        'Delete "$INSTDIR\{0}"' -f (ConvertTo-NsisLiteral $relative)
    })
    $uninstall += 'IfErrors 0 +4', 'MessageBox MB_OK|MB_ICONSTOP "Close ${APP_NAME} before uninstalling." /SD IDOK',
        'SetErrorLevel 1', 'Abort'
    $uninstall += @(Get-ChildItem -LiteralPath $Stage -Recurse -Directory -Force |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            'RMDir "$INSTDIR\{0}"' -f (ConvertTo-NsisLiteral $_.FullName.Substring($Stage.TrimEnd('\').Length + 1))
        })
    $uninstall | Set-Content -LiteralPath (Join-Path $Directory 'uninstall_files.nsh') -Encoding UTF8
}

Export-ModuleMember -Function Get-DistributionConfig, ConvertTo-PackageVersion, Get-PubspecPackageVersion,
    Find-WindowsSdkTool, Find-NsisCompiler, Invoke-DistributionTool, Read-DistributionPasswordFile,
    Get-DistributionCertificate, Get-CertificateSha256, Assert-ReleaseBundle, Assert-PeArchitecture,
    Copy-VisualCppRuntime, ConvertTo-NsisLiteral, New-NsisBuildFiles
