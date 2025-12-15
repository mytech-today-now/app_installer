<#
.SYNOPSIS
    Installs Thunderbird.
.DESCRIPTION
    Cross-platform installer for Thunderbird email client.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : thunderbird.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Thunderbird"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Mozilla.Thunderbird" `
        -BrewCask "thunderbird" `
        -AptPackage "thunderbird" `
        -DnfPackage "thunderbird" `
        -PacmanPackage "thunderbird" `
        -SnapPackage "thunderbird"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
