<#
.SYNOPSIS
    Installs Mozilla Firefox browser. 
.DESCRIPTION
    Cross-platform installer for Mozilla Firefox.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : firefox.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Mozilla Firefox"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Mozilla.Firefox" `
        -BrewCask "firefox" `
        -AptPackage "firefox" `
        -DnfPackage "firefox" `
        -PacmanPackage "firefox" `
        -SnapPackage "firefox"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

