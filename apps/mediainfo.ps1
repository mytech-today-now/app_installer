<#
.SYNOPSIS
    Installs MediaInfo. 
.DESCRIPTION
    Cross-platform installer for MediaInfo media file information tool.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : mediainfo.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "MediaInfo"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "MediaArea.MediaInfo" `
        -BrewCask "mediainfo" `
        -AptPackage "mediainfo" `
        -DnfPackage "mediainfo" `
        -PacmanPackage "mediainfo"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
