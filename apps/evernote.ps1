<#
.SYNOPSIS
    Installs Evernote. 
.DESCRIPTION
    Cross-platform installer for Evernote note-taking application.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : evernote.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Evernote"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Evernote.Evernote" `
        -BrewCask "evernote"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
