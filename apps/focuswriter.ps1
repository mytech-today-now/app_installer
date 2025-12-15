<#
.SYNOPSIS
    Installs FocusWriter. 
.DESCRIPTION
    Cross-platform installer for FocusWriter distraction-free writing.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : focuswriter.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "FocusWriter"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GottCode.FocusWriter" `
        -BrewCask "focuswriter" `
        -AptPackage "focuswriter" `
        -DnfPackage "focuswriter" `
        -PacmanPackage "focuswriter"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
