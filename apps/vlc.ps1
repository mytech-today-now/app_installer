<#
.SYNOPSIS
    Installs VLC Media Player.
.DESCRIPTION
    Cross-platform installer for VLC Media Player.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : vlc.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "VLC Media Player"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "VideoLAN.VLC" `
        -BrewCask "vlc" `
        -AptPackage "vlc" `
        -DnfPackage "vlc" `
        -PacmanPackage "vlc" `
        -SnapPackage "vlc"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
