<#
.SYNOPSIS
    Installs WhatsApp Desktop.
.DESCRIPTION
    Cross-platform installer for WhatsApp Desktop.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : whatsapp.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "WhatsApp Desktop"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "WhatsApp.WhatsApp" `
        -BrewCask "whatsapp"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

