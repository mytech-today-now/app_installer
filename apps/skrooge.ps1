<#
.SYNOPSIS
    Installs Skrooge. 
.DESCRIPTION
    Cross-platform installer for Skrooge personal finance manager.
    Supports Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : skrooge.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Skrooge"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -AptPackage "skrooge" `
        -DnfPackage "skrooge" `
        -PacmanPackage "skrooge" `
        -SnapPackage "skrooge"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
