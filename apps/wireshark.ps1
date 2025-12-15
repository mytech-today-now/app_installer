<#
.SYNOPSIS
    Installs Wireshark. 
.DESCRIPTION
    Cross-platform installer for Wireshark network protocol analyzer.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : wireshark.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Wireshark"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "WiresharkFoundation.Wireshark" `
        -BrewCask "wireshark" `
        -AptPackage "wireshark" `
        -DnfPackage "wireshark" `
        -PacmanPackage "wireshark-qt"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
