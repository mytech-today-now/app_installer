<#
.SYNOPSIS
    Installs Microsoft OpenJDK 21. 
.DESCRIPTION
    Cross-platform installer for Microsoft OpenJDK 21.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt).
.NOTES
    File Name      : openjdk21.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Microsoft OpenJDK 21"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Microsoft.OpenJDK.21" `
        -BrewCask "temurin21" `
        -AptPackage "openjdk-21-jdk"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
