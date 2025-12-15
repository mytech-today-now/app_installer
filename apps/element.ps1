<#
.SYNOPSIS
    Installs Element secure messaging.
.DESCRIPTION
    Cross-platform installer for Element (Matrix client).
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : element.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Element"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Element.Element" `
        -BrewCask "element" `
        -AptPackage "element-desktop" `
        -SnapPackage "element-desktop"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

