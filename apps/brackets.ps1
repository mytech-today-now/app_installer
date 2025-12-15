<#
.SYNOPSIS
    Installs Brackets. 
.DESCRIPTION
    Cross-platform installer for Brackets text editor (discontinued).
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
    Note: Brackets is discontinued.
.NOTES
    File Name      : brackets.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Brackets"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Adobe.Brackets" `
        -BrewCask "brackets" `
        -SnapPackage "brackets"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
