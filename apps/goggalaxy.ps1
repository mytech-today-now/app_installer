<#
.SYNOPSIS
    Installs GOG Galaxy. 
.DESCRIPTION
    Cross-platform installer for GOG Galaxy game launcher.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : goggalaxy.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "GOG Galaxy"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GOG.Galaxy" `
        -BrewCask "gog-galaxy"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
