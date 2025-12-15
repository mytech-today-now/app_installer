<#
.SYNOPSIS
    Installs PyCharm Community Edition.
.DESCRIPTION
    Cross-platform installer for PyCharm Community.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : pycharm.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "PyCharm Community"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "JetBrains.PyCharm.Community" `
        -BrewCask "pycharm-ce" `
        -SnapPackage "pycharm-community"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

