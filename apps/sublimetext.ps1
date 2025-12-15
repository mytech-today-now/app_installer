<#
.SYNOPSIS
    Installs Sublime Text.
.DESCRIPTION
    Cross-platform installer for Sublime Text.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/pacman/snap).
.NOTES
    File Name      : sublimetext.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Sublime Text"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "SublimeHQ.SublimeText.4" `
        -BrewCask "sublime-text" `
        -AptPackage "sublime-text" `
        -PacmanPackage "sublime-text" `
        -SnapPackage "sublime-text"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

