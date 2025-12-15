<#
.SYNOPSIS
    Installs Node.js JavaScript runtime.
.DESCRIPTION
    Cross-platform installer for Node.js.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : nodejs.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Node.js"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "OpenJS.NodeJS.LTS" `
        -BrewFormula "node" `
        -AptPackage "nodejs" `
        -DnfPackage "nodejs" `
        -PacmanPackage "nodejs" `
        -SnapPackage "node"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

