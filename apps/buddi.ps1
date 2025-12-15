<#
.SYNOPSIS
    Installs Buddi. 
.DESCRIPTION
    Cross-platform installer for Buddi personal budget software.
    Supports macOS (Homebrew). Cross-platform Java app, no winget package.
.NOTES
    File Name      : buddi.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Buddi"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -BrewCask "buddi"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
