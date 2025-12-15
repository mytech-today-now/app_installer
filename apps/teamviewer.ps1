<#
.SYNOPSIS
    Installs TeamViewer. 
.DESCRIPTION
    Cross-platform installer for TeamViewer remote desktop.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt).
.NOTES
    File Name      : teamviewer.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "TeamViewer"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "TeamViewer.TeamViewer" `
        -BrewCask "teamviewer" `
        -AptPackage "teamviewer"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
