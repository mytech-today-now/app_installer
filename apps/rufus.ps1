<#
.SYNOPSIS
    Installs Rufus bootable USB creator.

.DESCRIPTION
    This script installs Rufus using winget package manager.
    Windows-only: Rufus is not available on macOS or Linux.

.NOTES
    File Name      : rufus.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Rufus is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Rufus..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  [X] winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow

    $result = winget install --id Rufus.Rufus --silent --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Rufus installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  [X] Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing Rufus: $_" -ForegroundColor Red
    exit 1
}

