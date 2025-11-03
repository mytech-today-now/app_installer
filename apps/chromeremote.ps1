<#
.SYNOPSIS
    Installs Chrome Remote Desktop.

.DESCRIPTION
    This script installs Chrome Remote Desktop using winget package manager.

.NOTES
    File Name      : chromeremote.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Chrome Remote Desktop..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  [X] winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow

    $result = winget install --id Google.ChromeRemoteDesktopHost --silent --accept-source-agreements --accept-package-agreements 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "  [OK] Chrome Remote Desktop installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  [X] Installation failed with exit code: $exitCode" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit $exitCode
    }
}
catch {
    Write-Host "Error installing Chrome Remote Desktop: $_" -ForegroundColor Red
    exit 1
}

