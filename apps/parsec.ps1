<#
.SYNOPSIS
    Installs Parsec. 
.DESCRIPTION
    Cross-platform installer for Parsec remote desktop for gaming.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : parsec.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Parsec"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Parsec.Parsec" `
        -BrewCask "parsec"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
