#Requires -Version 5.1
# Offline fixture verification only: never starts WinSparkle, an app or an installer.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'updates.psm1') -Force
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$sdk = Get-WinSparkleSdk $projectRoot
$tool = Join-Path $sdk 'bin\winsparkle-tool.exe'
$fixture = Join-Path $projectRoot ".dart_tool\update_checks\$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $fixture
$key = Join-Path $fixture 'fixture.key'
$null = & $tool generate-key --file $key
if ($LASTEXITCODE -ne 0) { throw 'Fixture signing key generation failed.' }
$publicKey = Get-UpdatePublicKey $tool $key
$payload = Join-Path $fixture 'Phonolite_0.0.1.2_x64_setup.exe'
[IO.File]::WriteAllText($payload, 'Not an executable. Never install this fixture.')
$signature = (@(& $tool sign --private-key-file $key $payload) -join "`n").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Fixture signing failed.' }
& $tool verify --public-key $publicKey --signature $signature $payload
if ($LASTEXITCODE -ne 0) { throw 'An intact update must verify.' }
$config = [pscustomobject]@{repository = 'PhonoliteOrg/phonolite-app'; feedAsset = 'windows-appcast.xml'; publicKey = $publicKey}
$appcast = New-WindowsAppcast -Config $config -Version '0.0.1.2' -Installer (Split-Path $payload -Leaf) `
    -Length (Get-Item -LiteralPath $payload).Length -Signature $signature -Tag 'v0.0.1.2' `
    -MinimumWindowsVersion '10.0.19041' -Notes 'Music & playback <improvements> "verified".'
$namespaces = [Xml.XmlNamespaceManager]::new($appcast.NameTable)
$namespaces.AddNamespace('sparkle', 'http://www.andymatuschak.org/xml-namespaces/sparkle')
$version = $appcast.SelectSingleNode('/rss/channel/item/sparkle:version', $namespaces).InnerText
$enclosure = $appcast.rss.channel.item.enclosure
if ($version -cne '0.0.1.2' -or $appcast.rss.channel.item.description -cne 'Music & playback <improvements> "verified".' -or
        $enclosure.url -cne 'https://github.com/PhonoliteOrg/phonolite-app/releases/download/v0.0.1.2/Phonolite_0.0.1.2_x64_setup.exe' -or
        $enclosure.GetAttribute('edSignature', $namespaces.LookupNamespace('sparkle')) -cne $signature -or
        $enclosure.GetAttribute('installerArguments', $namespaces.LookupNamespace('sparkle')) -cne '/UPDATE') {
    throw 'The appcast did not preserve authenticated versioned assets and escaped release notes.'
}
[IO.File]::AppendAllText($payload, 'tampered')
$null = & $tool verify --public-key $publicKey --signature $signature $payload 2>&1
if ($LASTEXITCODE -eq 0) { throw 'A modified installer must fail verification.' }
$rejected = $false
try { $null = Assert-ExternalUpdateKey (Join-Path $projectRoot 'accidental.key') $projectRoot }
catch { $rejected = $true }
if (-not $rejected) { throw 'Private signing keys inside the app repository must be rejected.' }
Write-Host 'Update checks passed: signing, tamper rejection, XML escaping, versioned URLs and private-key isolation.'
