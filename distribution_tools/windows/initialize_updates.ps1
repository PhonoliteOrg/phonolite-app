#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [string]$Repository = 'PhonoliteOrg/phonolite-app'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\updates.psm1') -Force
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$PrivateKeyPath = Assert-ExternalUpdateKey $PrivateKeyPath $projectRoot
$configPath = Join-Path $PSScriptRoot 'scripts\updates_config.json'
$config = Get-UpdatesConfig $configPath -AllowEmptyKey
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Use an owner/repository GitHub repository name.' }
if (-not (Test-Path -LiteralPath $PrivateKeyPath) -and $config.publicKey) {
    throw 'The public key is already configured. Restore its private key; do not replace it for a new release.'
}
$sdk = Get-WinSparkleSdk $projectRoot
$tool = Join-Path $sdk 'bin\winsparkle-tool.exe'
if (-not (Test-Path -LiteralPath $PrivateKeyPath)) {
    $keyDirectory = Split-Path $PrivateKeyPath -Parent
    if (-not (Test-Path -LiteralPath $keyDirectory)) {
        $null = New-Item -ItemType Directory -Path $keyDirectory
        $acl = Get-Acl -LiteralPath $keyDirectory
        $acl.SetAccessRuleProtection($true, $false)
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $keyDirectory -AclObject $acl
    }
    $null = & $tool generate-key --file $PrivateKeyPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the update signing key.' }
}
$publicKey = Get-UpdatePublicKey $tool $PrivateKeyPath
if ($config.publicKey -and $config.publicKey -cne $publicKey) { throw 'This private key differs from the configured update key.' }
$config.repository = $Repository
$config.publicKey = $publicKey
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host 'Windows update signing configured. Back up the private key securely; never upload it.'
Write-Host "Feed: https://github.com/$Repository/releases/latest/download/$($config.feedAsset)"
