<#
.SYNOPSIS
    Installs Actual Budget.
.DESCRIPTION
    Cross-platform installer for Actual Budget privacy-focused budgeting app.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : actualbudget.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Actual Budget"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "ActualBudget.Actual" `
        -BrewCask "actual"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
