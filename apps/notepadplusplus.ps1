<#
.SYNOPSIS
    Installs Notepad++ text editor.

.DESCRIPTION
    This script installs Notepad++ using winget package manager.
    Windows-only: Notepad++ is not available on macOS or Linux.

.NOTES
    File Name      : notepadplusplus.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Notepad++ is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Notepad++..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ? winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }
    
    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow
    
    $result = winget install --id Notepad++.Notepad++ --silent --accept-source-agreements --accept-package-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ? Notepad++ installed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "  ? Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host "Error installing Notepad++: $_" -ForegroundColor Red
    exit 1
}

