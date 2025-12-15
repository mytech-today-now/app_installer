<#
.SYNOPSIS
    Installs Todoist.
.DESCRIPTION
    Cross-platform installer for Todoist task management.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : todoist.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Todoist"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Doist.Todoist" `
        -BrewCask "todoist" `
        -SnapPackage "todoist"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
