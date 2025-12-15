<#
.SYNOPSIS
    Installs itch.io.
.DESCRIPTION
    Cross-platform installer for itch.io indie game marketplace.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : itchio.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "itch.io"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "ItchIo.Itch" `
        -BrewCask "itch"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
