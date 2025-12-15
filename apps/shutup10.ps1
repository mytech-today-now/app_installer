<#
.SYNOPSIS
    Downloads and installs O&O ShutUp10++.

.DESCRIPTION
    This script downloads the latest version of O&O ShutUp10++ privacy tool
    Windows-only: ShutUp10++ is not available on macOS or Linux.
    and places it in a convenient location for use.

.NOTES
    File Name      : shutup10.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] ShutUp10++ is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing O&O ShutUp10++..." -ForegroundColor Cyan
    
    # Define download URL and installation path
    $shutupUrl = "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe"
    $installPath = "C:\Program Files\OOShutUp10"
    $exePath = Join-Path $installPath "OOSU10.exe"
    
    # Create installation directory
    if (-not (Test-Path $installPath)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        Write-Host "  Created directory: $installPath" -ForegroundColor Gray
    }
    
    # Download O&O ShutUp10++
    Write-Host "  Downloading O&O ShutUp10++..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $shutupUrl -OutFile $exePath -UseBasicParsing
        Write-Host "  ? Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  ? Failed to download: $_" -ForegroundColor Red
        exit 1
    }
    
    # Create desktop shortcut
    $WshShell = New-Object -ComObject WScript.Shell
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "O&O ShutUp10++.lnk"
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $installPath
    $shortcut.Description = "O&O ShutUp10++ Privacy Tool"
    $shortcut.Save()
    
    Write-Host "  ? Desktop shortcut created" -ForegroundColor Green
    
    Write-Host "`n? O&O ShutUp10++ installed successfully!" -ForegroundColor Green
    Write-Host "  Location: $exePath" -ForegroundColor Cyan
    Write-Host "  Desktop shortcut created" -ForegroundColor Cyan
    
    exit 0
}
catch {
    Write-Host "Error installing O&O ShutUp10++: $_" -ForegroundColor Red
    exit 1
}

