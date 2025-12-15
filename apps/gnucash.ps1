<#
.SYNOPSIS
    Installs GnuCash.
.DESCRIPTION
    Cross-platform installer for GnuCash personal finance software.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : gnucash.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "GnuCash"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GnuCash.GnuCash" `
        -BrewCask "gnucash" `
        -AptPackage "gnucash" `
        -DnfPackage "gnucash" `
        -PacmanPackage "gnucash"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
