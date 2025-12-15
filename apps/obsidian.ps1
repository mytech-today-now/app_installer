<#
.SYNOPSIS
    Installs Obsidian.
.DESCRIPTION
    Cross-platform installer for Obsidian knowledge base and note-taking.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : obsidian.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Obsidian"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Obsidian.Obsidian" `
        -BrewCask "obsidian" `
        -SnapPackage "obsidian"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
