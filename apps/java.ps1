<#
.SYNOPSIS
    Installs Java Runtime Environment. 
.DESCRIPTION
    Cross-platform installer for Java Runtime Environment.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : java.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Java Runtime Environment"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Oracle.JavaRuntimeEnvironment" `
        -BrewCask "java" `
        -AptPackage "default-jre" `
        -DnfPackage "java-latest-openjdk" `
        -PacmanPackage "jre-openjdk"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

