<#
.SYNOPSIS
    Uninstalls all McAfee products from the system.

.DESCRIPTION
    This script removes all McAfee products using the official McAfee Consumer Product Removal tool (MCPR).
    It downloads the tool if needed and runs it to completely remove McAfee software.

.NOTES
    File Name      : uninstall-mcafee.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] McAfee Uninstaller is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Uninstalling McAfee products..." -ForegroundColor Cyan
    
    # Check if McAfee is installed
    $mcafeeInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -like "*McAfee*" }
    
    if (-not $mcafeeInstalled) {
        Write-Host "  ??  No McAfee products found on this system." -ForegroundColor Cyan
        exit 0
    }
    
    Write-Host "  Found McAfee products:" -ForegroundColor Yellow
    foreach ($product in $mcafeeInstalled) {
        Write-Host "    - $($product.DisplayName)" -ForegroundColor Gray
    }
    
    # Download McAfee Consumer Product Removal tool (MCPR)
    $mcprUrl = "https://download.mcafee.com/molbin/iss-loc/SupportTools/MCPR/MCPR.exe"
    $mcprPath = Join-Path $env:TEMP "MCPR.exe"
    
    Write-Host "`n  Downloading McAfee removal tool..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $mcprUrl -OutFile $mcprPath -UseBasicParsing
        Write-Host "  ? Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  ? Failed to download MCPR tool: $_" -ForegroundColor Red
        Write-Host "  Please download manually from: $mcprUrl" -ForegroundColor Yellow
        exit 1
    }
    
    # Run MCPR tool
    Write-Host "`n  Running McAfee removal tool..." -ForegroundColor Yellow
    Write-Host "  ??  This may take several minutes. Please wait..." -ForegroundColor Yellow
    
    try {
        # MCPR runs with a GUI but can be automated with -p parameter
        $process = Start-Process -FilePath $mcprPath -ArgumentList "-p" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "  ? McAfee products removed successfully!" -ForegroundColor Green
            Write-Host "  ??  A system restart is recommended." -ForegroundColor Cyan
        }
        else {
            Write-Host "  ??  MCPR exited with code: $($process.ExitCode)" -ForegroundColor Yellow
            Write-Host "  Please check if McAfee was removed successfully." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ? Error running MCPR: $_" -ForegroundColor Red
        exit 1
    }
    finally {
        # Clean up
        if (Test-Path $mcprPath) {
            Remove-Item $mcprPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    exit 0
}
catch {
    Write-Host "Error uninstalling McAfee: $_" -ForegroundColor Red
    exit 1
}

