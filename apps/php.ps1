<#
.SYNOPSIS
    Installs PHP scripting language.
.DESCRIPTION
    Cross-platform installer for PHP.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : php.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "PHP"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "PHP.PHP" `
        -BrewFormula "php" `
        -AptPackage "php" `
        -DnfPackage "php" `
        -PacmanPackage "php"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

