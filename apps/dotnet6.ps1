<#
.SYNOPSIS
    Installs .NET Desktop Runtime 6.
.DESCRIPTION
    Cross-platform installer for .NET Desktop Runtime 6.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt).
.NOTES
    File Name      : dotnet6.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = ".NET Desktop Runtime 6"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Microsoft.DotNet.DesktopRuntime.6" `
        -BrewCask "dotnet" `
        -AptPackage "dotnet-runtime-6.0"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
