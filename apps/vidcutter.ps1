<#
.SYNOPSIS
    Installs VidCutter. 
.DESCRIPTION
    Cross-platform installer for VidCutter video cutter.
    Supports Windows (winget) and Linux (snap).
.NOTES
    File Name      : vidcutter.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "VidCutter"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "ozmartian.VidCutter" `
        -SnapPackage "vidcutter"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
