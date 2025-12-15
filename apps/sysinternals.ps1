<#
.SYNOPSIS
    Installs Sysinternals Suite.

.DESCRIPTION
    This script installs Sysinternals Suite using winget package manager.
    Windows-only: Sysinternals Suite is not available on macOS or Linux.

.NOTES
    File Name      : sysinternals.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Sysinternals Suite is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Sysinternals Suite..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  [X] winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow

    $result = winget install --id Microsoft.Sysinternals.Suite --silent --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Sysinternals Suite installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  [X] Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing Sysinternals Suite: $_" -ForegroundColor Red
    exit 1
}

