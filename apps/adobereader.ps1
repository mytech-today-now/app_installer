<#
.SYNOPSIS
    Installs Adobe Acrobat Reader.
.DESCRIPTION
    Cross-platform installer for Adobe Acrobat Reader PDF viewer.
    Supports Windows (winget) and macOS (Homebrew).
    Note: Linux users should use alternative PDF readers.
.NOTES
    File Name      : adobereader.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Adobe Acrobat Reader"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Adobe.Acrobat.Reader.64-bit" `
        -BrewCask "adobe-acrobat-reader"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
