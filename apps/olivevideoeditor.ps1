<#
.SYNOPSIS
    Installs Olive Video Editor.
.DESCRIPTION
    Cross-platform installer for Olive Video Editor.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : olivevideoeditor.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Olive Video Editor"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "OliveTeam.Olive" `
        -BrewCask "olive" `
        -SnapPackage "olive-editor"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
