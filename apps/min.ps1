<#
.SYNOPSIS
    Installs Min Browser. 
.DESCRIPTION
    Cross-platform installer for Min minimalist browser.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : min.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Min Browser"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Min.Min" `
        -BrewCask "min" `
        -SnapPackage "min"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
