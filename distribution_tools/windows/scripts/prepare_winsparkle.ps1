#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'updates.psm1') -Force
Get-WinSparkleSdk -ProjectRoot ([IO.Path]::GetFullPath($ProjectRoot))
