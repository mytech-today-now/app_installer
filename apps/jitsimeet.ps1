<#
.SYNOPSIS
    Installs Jitsi Meet.
.DESCRIPTION
    Cross-platform installer for Jitsi Meet.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : jitsimeet.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Jitsi Meet"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "JitsiMeet.JitsiMeet" `
        -BrewCask "jitsi-meet" `
        -SnapPackage "jitsi"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
