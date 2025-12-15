<#
.SYNOPSIS
    Installs Cinelerra. 
.DESCRIPTION
    Cross-platform installer for Cinelerra professional video editing software.
    Supports Linux (apt/snap).
.NOTES
    File Name      : cinelerra.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Cinelerra"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -AptPackage "cinelerra" `
        -SnapPackage "cinelerra-gg"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
