<#
.SYNOPSIS
    Installs Scribus.
.DESCRIPTION
    Cross-platform installer for Scribus desktop publishing.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : scribus.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Scribus"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Scribus.Scribus" `
        -BrewCask "scribus" `
        -AptPackage "scribus" `
        -DnfPackage "scribus" `
        -PacmanPackage "scribus" `
        -SnapPackage "scribus"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
