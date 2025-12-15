<#
.SYNOPSIS
    Installs VirtualBox.
.DESCRIPTION
    Cross-platform installer for Oracle VirtualBox virtualization.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : virtualbox.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "VirtualBox"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Oracle.VirtualBox" `
        -BrewCask "virtualbox" `
        -AptPackage "virtualbox" `
        -DnfPackage "VirtualBox" `
        -PacmanPackage "virtualbox"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
