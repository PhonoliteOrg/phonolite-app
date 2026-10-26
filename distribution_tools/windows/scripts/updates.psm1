Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UpdatesConfig {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowEmptyKey)

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
            $config.feedAsset -cne 'windows-appcast.xml') {
        throw 'Updates need an owner/repository and the windows-appcast.xml feed asset.'
    }
    if (-not ($AllowEmptyKey -and [string]::IsNullOrEmpty($config.publicKey))) {
        if ($config.publicKey -notmatch '^[A-Za-z0-9+/]{43}=$' -or
                [Convert]::FromBase64String($config.publicKey).Length -ne 32) {
            throw 'Initialize the Windows EdDSA update signing key before building.'
        }
    }
    return $config
}

function Get-WinSparkleSdk {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $dependency = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'winsparkle_dependency.json') -Raw | ConvertFrom-Json
    $cache = Join-Path $ProjectRoot '.dart_tool\winsparkle'
    $archive = Join-Path $cache "WinSparkle-$($dependency.version).zip"
    $expanded = Join-Path $cache $dependency.version
    $sdk = Join-Path $expanded "WinSparkle-$($dependency.version)"
    $null = New-Item -ItemType Directory -Path $cache -Force
    if (-not (Test-Path -LiteralPath $archive)) {
        # Windows PowerShell 5.1 can otherwise negotiate a TLS version GitHub rejects.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $dependency.url -OutFile $archive -TimeoutSec 120
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $dependency.sha256) {
        throw 'WinSparkle SDK checksum mismatch. Remove the cached archive and retry.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sdk 'x64\Release\WinSparkle.dll'))) {
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    }
    foreach ($file in @('include\winsparkle.h', 'x64\Release\WinSparkle.dll',
            'x64\Release\WinSparkle.lib', 'bin\winsparkle-tool.exe', 'COPYING')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sdk $file) -PathType Leaf)) {
            throw "Incomplete WinSparkle SDK: $file"
        }
    }
    return $sdk
}

function Assert-ExternalUpdateKey {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ProjectRoot)

    $resolvedKey = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedKey.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Keep the private update key outside the app repository.'
    }
    return $resolvedKey
}

function Get-UpdatePublicKey {
    param([Parameter(Mandatory)][string]$Tool, [Parameter(Mandatory)][string]$PrivateKeyPath)

    $output = @(& $Tool public-key --private-key-file $PrivateKeyPath)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the EdDSA signing key.' }
    $keys = @([regex]::Matches(($output -join "`n"), '(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])') |
        ForEach-Object { $_.Value } | Select-Object -Unique)
    if ($keys.Count -ne 1) { throw 'The signing tool did not return one valid public key.' }
    return $keys[0]
}

function New-WindowsAppcast {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Installer,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][string]$Signature,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$MinimumWindowsVersion,
        [string]$Notes = ''
    )

    if ($Tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Installer -notmatch '^[A-Za-z0-9_.-]+\.exe$') {
        throw 'Release tags and installer names must contain only letters, digits, periods, underscores or hyphens.'
    }
    if ($Signature -notmatch '^[A-Za-z0-9+/]{86}==$' -or $Length -le 0) {
        throw 'A complete installer and valid EdDSA signature are required.'
    }
    $sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    $document = [xml]'<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>Phonolite for Windows</title><description>Stable Windows x64 updates</description><language>en</language></channel></rss>'
    $document.DocumentElement.SetAttribute('xmlns:sparkle', $sparkle)
    $item = $document.CreateElement('item')
    $null = $document.rss.channel.AppendChild($item)
    foreach ($entry in @(@('title', "Phonolite $Version"), @('description', $Notes),
            @('pubDate', [DateTime]::UtcNow.ToString('r', [Globalization.CultureInfo]::InvariantCulture)))) {
        $node = $document.CreateElement($entry[0])
        $node.InnerText = $entry[1]
        $null = $item.AppendChild($node)
    }
    foreach ($entry in @(@('version', $Version), @('shortVersionString', (($Version.Split('.'))[0..2] -join '.')),
            @('minimumSystemVersion', $MinimumWindowsVersion))) {
        $node = $document.CreateElement('sparkle', $entry[0], $sparkle)
        $node.InnerText = $entry[1]
        $null = $item.AppendChild($node)
    }
    $enclosure = $document.CreateElement('enclosure')
    $enclosure.SetAttribute('url', "https://github.com/$($Config.repository)/releases/download/$Tag/$Installer")
    $enclosure.SetAttribute('length', [string]$Length)
    $enclosure.SetAttribute('type', 'application/octet-stream')
    foreach ($entry in @(@('os', 'windows-x64'), @('edSignature', $Signature), @('installerArguments', '/UPDATE'))) {
        $attribute = $document.CreateAttribute('sparkle', $entry[0], $sparkle)
        $attribute.Value = $entry[1]
        $null = $enclosure.Attributes.Append($attribute)
    }
    $null = $item.AppendChild($enclosure)
    return $document
}
