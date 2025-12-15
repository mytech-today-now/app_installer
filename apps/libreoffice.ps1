<#
.SYNOPSIS
    Installs LibreOffice. 
.DESCRIPTION
    Cross-platform installer for LibreOffice office suite.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : libreoffice.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "LibreOffice"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "TheDocumentFoundation.LibreOffice" `
        -BrewCask "libreoffice" `
        -AptPackage "libreoffice" `
        -DnfPackage "libreoffice" `
        -PacmanPackage "libreoffice-fresh" `
        -SnapPackage "libreoffice"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
