<#
.SYNOPSIS
    Installs Telegram Desktop.
.DESCRIPTION
    Cross-platform installer for Telegram Desktop.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : telegram.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Telegram Desktop"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Telegram.TelegramDesktop" `
        -BrewCask "telegram" `
        -AptPackage "telegram-desktop" `
        -SnapPackage "telegram-desktop"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

