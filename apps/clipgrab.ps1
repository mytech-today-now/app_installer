<#
.SYNOPSIS
    Installs ClipGrab video downloader.

.DESCRIPTION
    This script installs ClipGrab using winget package manager.

.NOTES
    File Name      : clipgrab.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing ClipGrab..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ❌ winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }
    
    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow
    
    $result = winget install --id "Philipp Schmieder.ClipGrab" --silent --accept-source-agreements --accept-package-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ ClipGrab installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  ❌ Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing ClipGrab: $_" -ForegroundColor Red
    exit 1
}

