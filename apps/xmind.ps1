<#
.SYNOPSIS
    Installs XMind.  

.DESCRIPTION
    This script installs XMind using winget package manager.

.NOTES
    File Name      : xmind.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing XMind..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  [X] winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow

    . "$PSScriptRoot/../platform-detect.ps1"
    $result = Invoke-WingetPackageCommand -Operation install -PackageId 'XMind.XMind' -AdditionalArguments @('--silent', '--accept-source-agreements', '--accept-package-agreements')

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] XMind installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  [X] Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing XMind: $_" -ForegroundColor Red
    exit 1
}

