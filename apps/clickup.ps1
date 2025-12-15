<#
.SYNOPSIS
    Installs ClickUp.
.DESCRIPTION
    Cross-platform installer for ClickUp project management and productivity.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : clickup.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "ClickUp"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "ClickUp.ClickUp" `
        -BrewCask "clickup"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
