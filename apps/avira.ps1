<#
.SYNOPSIS
    Installs Avira Security.

.DESCRIPTION
    This script installs Avira Security using winget package manager (Microsoft Store version).
    Windows-only: Avira Security is not available on macOS or Linux.

.NOTES
    File Name      : avira.ps1
    Author         : myTech.Today
    Version        : 1.1.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Avira Security is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Avira Security..." -ForegroundColor Cyan

    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ? winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Install using winget (Microsoft Store version)
    Write-Host "  Installing via winget (Microsoft Store)..." -ForegroundColor Yellow

    $result = winget install --id XPFD23M0L795KD --silent --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ? Avira Security installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  ? Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing Avira Security: $_" -ForegroundColor Red
    exit 1
}

