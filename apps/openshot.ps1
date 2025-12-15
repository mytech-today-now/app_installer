<#
.SYNOPSIS
    Installs OpenShot video editor.
.DESCRIPTION
    Cross-platform installer for OpenShot.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : openshot.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "OpenShot"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "OpenShot.OpenShot" `
        -BrewCask "openshot-video-editor" `
        -AptPackage "openshot-qt" `
        -DnfPackage "openshot" `
        -PacmanPackage "openshot" `
        -SnapPackage "openshot-community"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
