<#
.SYNOPSIS
    Installs Vagrant.  
.DESCRIPTION
    Cross-platform installer for Vagrant development environments.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : vagrant.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Vagrant"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Hashicorp.Vagrant" `
        -BrewCask "vagrant" `
        -AptPackage "vagrant" `
        -DnfPackage "vagrant" `
        -PacmanPackage "vagrant"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
