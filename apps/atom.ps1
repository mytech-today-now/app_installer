<#
.SYNOPSIS
    Installs Atom.
.DESCRIPTION
    Cross-platform installer for Atom text editor (discontinued).
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
    Note: Atom is discontinued - consider VS Code instead.
.NOTES
    File Name      : atom.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Atom"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GitHub.Atom" `
        -BrewCask "atom" `
        -AptPackage "atom" `
        -SnapPackage "atom"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
