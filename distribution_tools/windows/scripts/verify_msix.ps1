#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$CertificatePath,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'distribution.psm1') -Force
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\package_config.json' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -AssemblyName System.Security.Cryptography.Pkcs }
else { Add-Type -AssemblyName System.Security }
if (-not ('PhonoliteDistribution.SignatureVerifier' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'signature_verification.cs')
}

function Read-PackageXml {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 16777216
    $stream = $Entry.Open()
    $reader = [System.Xml.XmlReader]::Create($stream, $settings)
    try {
        $document = [System.Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

$config = Get-DistributionConfig $ConfigPath
$expected = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CertificatePath).Path))
$archive = $null
try {
    if ($expected.Subject -cne $config.publisher) { throw 'Certificate Subject does not match the configured publisher.' }
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
    $entries = @{}
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($entries.ContainsKey($name) -or $name -match '(^/|(^|/)\.\.(/|$)|:)' -or
                [System.IO.Path]::GetExtension($name) -in @('.pfx', '.p12', '.key', '.pem')) {
            throw "Unsafe or duplicate package entry: $name"
        }
        $entries[$name] = $entry
    }
    $required = @('AppxManifest.xml', 'AppxBlockMap.xml', 'AppxSignature.p7x', 'LICENSE.txt', $config.executable,
        'flutter_windows.dll', 'phonolite_opus.dll', 'phonolite_quic.dll', 'phonolite_local_audio.dll',
        'flutter_secure_storage_windows_plugin.dll', 'sqlite3.dll', 'data/icudtl.dat', 'data/app.so',
        'data/flutter_assets/AssetManifest.bin', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
        'Assets/Logo44.png', 'Assets/Logo50.png', 'Assets/Logo150.png')
    foreach ($name in $required) {
        if (-not $entries.ContainsKey($name)) { throw "Missing package entry: $name" }
    }
    $stream = $entries['AppxSignature.p7x'].Open()
    $memory = [System.IO.MemoryStream]::new()
    try {
        if ($entries['AppxSignature.p7x'].Length -gt 16777216) { throw 'Oversized package signature.' }
        $stream.CopyTo($memory)
        $signatureBytes = $memory.ToArray()
        if ($signatureBytes.Length -lt 5 -or [BitConverter]::ToUInt32($signatureBytes, 0) -ne 0x58434B50) {
            throw 'Invalid MSIX signature header.'
        }
        $cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
        $cms.Decode([byte[]]$signatureBytes[4..($signatureBytes.Length - 1)])
        $cms.CheckSignature($true)
        if ($cms.SignerInfos.Count -ne 1 -or -not $cms.SignerInfos[0].Certificate -or
                (Get-CertificateSha256 $cms.SignerInfos[0].Certificate) -cne (Get-CertificateSha256 $expected)) {
            throw 'Package signer differs from the supplied public certificate.'
        }
    }
    finally { $memory.Dispose(); $stream.Dispose() }
    # Verify Windows' package digests too, with no UI or network retrieval. Accept
    # only CERT_E_UNTRUSTEDROOT for the precise self-issued certificate above.
    $trustResult = [PhonoliteDistribution.SignatureVerifier]::Verify((Resolve-Path -LiteralPath $PackagePath).Path)
    $untrustedTestCertificate = $trustResult -eq 0x800B0109L -and $expected.Subject -ceq $expected.Issuer
    if ($trustResult -ne 0 -and -not $untrustedTestCertificate) {
        throw ('Package signature verification failed: 0x{0:X8}' -f $trustResult)
    }
    $manifest = Read-PackageXml $entries['AppxManifest.xml']
    $identity = $manifest.DocumentElement.Identity
    if ($identity.Name -cne $config.identityName -or $identity.Publisher -cne $config.publisher -or
            $identity.ProcessorArchitecture -ne 'x64') { throw 'Incorrect MSIX package identity or architecture.' }
    $null = ConvertTo-PackageVersion $identity.Version
    if ($manifest.DocumentElement.Applications.Application.Executable -cne $config.executable) {
        throw 'Manifest executable does not match the configured Windows runner.'
    }

    # Inspect the PE headers without loading or executing any packaged binary.
    foreach ($name in @($config.executable, 'flutter_windows.dll', 'phonolite_opus.dll', 'phonolite_quic.dll',
            'phonolite_local_audio.dll', 'sqlite3.dll', 'vcruntime140.dll')) {
        $stream = $entries[$name].Open()
        $memory = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
            if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw "Invalid PE binary: $name" }
            $offset = [BitConverter]::ToInt32($bytes, 60)
            if ($offset -lt 64 -or $offset -gt $bytes.Length - 6 -or
                    [BitConverter]::ToUInt32($bytes, $offset) -ne 0x4550 -or
                    [BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x8664) { throw "Expected an x64 PE binary: $name" }
        }
        finally { $memory.Dispose(); $stream.Dispose() }
    }

    $blockMap = Read-PackageXml $entries['AppxBlockMap.xml']
    if ($blockMap.DocumentElement.HashMethod -ne 'http://www.w3.org/2001/04/xmlenc#sha256') {
        throw 'Expected a SHA-256 package block map.'
    }
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $checkedFiles = @{}
    try {
        foreach ($file in $blockMap.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'File' }) {
            $name = $file.GetAttribute('Name').Replace('\', '/')
            if (-not $entries.ContainsKey($name) -or $checkedFiles.ContainsKey($name) -or
                    $entries[$name].Length -ne [long]$file.GetAttribute('Size')) { throw "Invalid block map entry: $name" }
            $checkedFiles[$name] = $true
            $stream = $entries[$name].Open()
            try {
                $buffer = [byte[]]::new(65536)
                foreach ($block in $file.ChildNodes | Where-Object { $_.LocalName -eq 'Block' }) {
                    $count = 0
                    while ($count -lt $buffer.Length) {
                        $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                        if ($read -eq 0) { break }
                        $count += $read
                    }
                    if ([Convert]::ToBase64String($hash.ComputeHash($buffer, 0, $count)) -cne $block.GetAttribute('Hash')) {
                        throw "Package payload hash mismatch: $name"
                    }
                }
                if ($stream.ReadByte() -ne -1) { throw "Incomplete block map: $name" }
            }
            finally { $stream.Dispose() }
        }
        foreach ($name in $entries.Keys) {
            if (-not $checkedFiles.ContainsKey($name) -and $name -notin @('[Content_Types].xml', 'AppxManifest.xml',
                    'AppxBlockMap.xml', 'AppxSignature.p7x', 'AppxMetadata/CodeIntegrity.cat')) {
                throw "Payload is absent from the block map: $name"
            }
        }
    }
    finally { $hash.Dispose() }

    $feedPath = Join-Path (Split-Path ([System.IO.Path]::GetFullPath($PackagePath)) -Parent) 'Phonolite-x64.appinstaller'
    if (Test-Path -LiteralPath $feedPath) {
        [xml]$feed = Get-Content -LiteralPath $feedPath -Raw
        $main = $feed.DocumentElement.MainPackage
        if ($main.Name -cne $identity.Name -or $main.Publisher -cne $identity.Publisher -or
                $main.Version -ne $identity.Version -or $main.ProcessorArchitecture -ne 'x64' -or
                ([uri]$main.Uri).Scheme -ne 'https' -or ([uri]$feed.DocumentElement.Uri).Scheme -ne 'https' -or
                [uri]::UnescapeDataString(([uri]$main.Uri).Segments[-1]) -cne (Split-Path $PackagePath -Leaf)) {
            throw 'App Installer identity, version, architecture or URLs do not match the package.'
        }
    }
    Write-Host "Verified $($identity.Name) $($identity.Version), $($checkedFiles.Count) payload files, x64 PE headers, and expected signer."
    Write-Host "Certificate SHA-256: $(Get-CertificateSha256 $expected)"
    $trustDescription = if ($untrustedTestCertificate) { 'Expected self-signed certificate is not trusted' } else { 'Trusted' }
    Write-Host "Windows trust status: $trustDescription. No app was installed or launched."
}
finally {
    if ($archive) { $archive.Dispose() }
    $expected.Dispose()
}
