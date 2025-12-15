<#
.SYNOPSIS 
    Installs 7-Zip.
.DESCRIPTION
    Cross-platform installer for 7-Zip file archiver.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : 7zip.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "7-Zip"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "7zip.7zip" `
        -BrewFormula "p7zip" `
        -AptPackage "p7zip-full" `
        -DnfPackage "p7zip" `
        -PacmanPackage "p7zip" `
        -SnapPackage "p7zip-desktop"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
