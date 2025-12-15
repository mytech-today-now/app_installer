<#
.SYNOPSIS
    Installs LMMS. 
.DESCRIPTION
    Cross-platform installer for LMMS (Linux MultiMedia Studio).
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : lmms.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "LMMS"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "LMMS.LMMS" `
        -BrewCask "lmms" `
        -AptPackage "lmms" `
        -DnfPackage "lmms" `
        -PacmanPackage "lmms" `
        -SnapPackage "lmms"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
