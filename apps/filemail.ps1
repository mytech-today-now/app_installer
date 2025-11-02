<#
.SYNOPSIS
    Downloads and installs FileMail Desktop.

.DESCRIPTION
    This script downloads and installs FileMail Desktop application for large file transfers.

.NOTES
    File Name      : filemail.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing FileMail Desktop..." -ForegroundColor Cyan
    
    # Define download URL
    $filemailUrl = "https://www.filemail.com/api/file/get?fileId=desktop-windows"
    $installerPath = Join-Path $env:TEMP "FileMail-Setup.exe"
    
    # Download FileMail Desktop
    Write-Host "  Downloading FileMail Desktop..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $filemailUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "  ✅ Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  ❌ Failed to download: $_" -ForegroundColor Red
        Write-Host "  Please download manually from: https://www.filemail.com/desktop" -ForegroundColor Yellow
        exit 1
    }
    
    # Install FileMail Desktop
    Write-Host "  Installing FileMail Desktop..." -ForegroundColor Yellow
    
    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "  ✅ FileMail Desktop installed successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠️  Installer exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ Installation failed: $_" -ForegroundColor Red
        exit 1
    }
    finally {
        # Clean up
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    exit 0
}
catch {
    Write-Host "Error installing FileMail Desktop: $_" -ForegroundColor Red
    exit 1
}

