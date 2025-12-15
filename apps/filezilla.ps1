<#
.SYNOPSIS
    Installs FileZilla.
.DESCRIPTION
    Cross-platform installer for FileZilla FTP client.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : filezilla.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "FileZilla"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "TimKosse.FileZilla.Client" `
        -BrewCask "filezilla" `
        -AptPackage "filezilla" `
        -DnfPackage "filezilla" `
        -PacmanPackage "filezilla" `
        -SnapPackage "filezilla"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
