<#
.SYNOPSIS 
    Downloads and installs Belarc Advisor.

.DESCRIPTION
    This script downloads and installs Belarc Advisor system information tool.
    Windows-only: Belarc Advisor is not available on macOS or Linux.

.NOTES
    File Name      : belarc.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Belarc Advisor is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Belarc Advisor..." -ForegroundColor Cyan
    
    # Define download URL
    $belarcUrl = "https://downloads.belarc.com/advisor/advisorinstaller.exe"
    $installerPath = Join-Path $env:TEMP "BelarcAdvisorInstaller.exe"
    
    # Download Belarc Advisor
    Write-Host "  Downloading Belarc Advisor..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $belarcUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "  ? Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  ? Failed to download: $_" -ForegroundColor Red
        exit 1
    }
    
    # Install Belarc Advisor
    Write-Host "  Installing Belarc Advisor..." -ForegroundColor Yellow
    
    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "  ? Belarc Advisor installed successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "  ??  Installer exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ? Installation failed: $_" -ForegroundColor Red
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
    Write-Host "Error installing Belarc Advisor: $_" -ForegroundColor Red
    exit 1
}

