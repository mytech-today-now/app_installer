<#
.SYNOPSIS
    Installs IntelliJ IDEA Community.
.DESCRIPTION
    Cross-platform installer for IntelliJ IDEA Community.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : intellij.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "IntelliJ IDEA Community"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "JetBrains.IntelliJIDEA.Community" `
        -BrewCask "intellij-idea-ce" `
        -SnapPackage "intellij-idea-community"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

