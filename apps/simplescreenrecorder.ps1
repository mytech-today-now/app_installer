<#
.SYNOPSIS
    Installs SimpleScreenRecorder. 
.DESCRIPTION
    Cross-platform installer for SimpleScreenRecorder screen recorder.
    Supports Linux (apt/dnf/pacman).
.NOTES
    File Name      : simplescreenrecorder.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "SimpleScreenRecorder"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -AptPackage "simplescreenrecorder" `
        -DnfPackage "simplescreenrecorder" `
        -PacmanPackage "simplescreenrecorder"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
