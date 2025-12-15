<#
.SYNOPSIS
    Installs Chrome Remote Desktop.
.DESCRIPTION
    Cross-platform installer for Chrome Remote Desktop.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : chromeremote.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Chrome Remote Desktop"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Google.ChromeRemoteDesktopHost" `
        -BrewCask "chrome-remote-desktop-host"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
