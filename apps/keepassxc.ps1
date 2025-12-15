<#
.SYNOPSIS
    Installs KeePassXC.
.DESCRIPTION
    Cross-platform installer for KeePassXC password manager.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : keepassxc.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "KeePassXC"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "KeePassXCTeam.KeePassXC" `
        -BrewCask "keepassxc" `
        -AptPackage "keepassxc" `
        -DnfPackage "keepassxc" `
        -PacmanPackage "keepassxc" `
        -SnapPackage "keepassxc"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
