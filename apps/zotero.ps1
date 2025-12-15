<#
.SYNOPSIS
    Installs Zotero.
.DESCRIPTION
    Cross-platform installer for Zotero reference manager.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : zotero.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Zotero"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Zotero.Zotero" `
        -BrewCask "zotero" `
        -AptPackage "zotero" `
        -SnapPackage "zotero-snap"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
