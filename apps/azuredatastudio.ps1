<#
.SYNOPSIS
    Installs Azure Data Studio. 
.DESCRIPTION
    Cross-platform installer for Azure Data Studio.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : azuredatastudio.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Azure Data Studio"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Microsoft.AzureDataStudio" `
        -BrewCask "azure-data-studio"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

