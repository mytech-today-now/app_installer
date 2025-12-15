<#
.SYNOPSIS
    Installs Python programming language.
.DESCRIPTION
    Cross-platform installer for Python.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : python.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Python"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Python.Python.3.12" `
        -BrewFormula "python" `
        -AptPackage "python3" `
        -DnfPackage "python3" `
        -PacmanPackage "python"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

