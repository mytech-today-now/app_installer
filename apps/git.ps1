<#
.SYNOPSIS
    Installs Git version control system.

.DESCRIPTION
    This script installs Git using winget package manager.

.NOTES
    File Name      : git.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Git..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ❌ winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }
    
    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow
    
    $result = winget install --id Git.Git --silent --accept-source-agreements --accept-package-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Git installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  ❌ Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing Git: $_" -ForegroundColor Red
    exit 1
}

