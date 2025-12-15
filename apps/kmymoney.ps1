<#
.SYNOPSIS
    Installs KMyMoney.
.DESCRIPTION
    Cross-platform installer for KMyMoney personal finance manager.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : kmymoney.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "KMyMoney"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "KDE.KMyMoney" `
        -BrewCask "kmymoney" `
        -AptPackage "kmymoney" `
        -DnfPackage "kmymoney" `
        -PacmanPackage "kmymoney"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
