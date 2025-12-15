<#
.SYNOPSIS
    Downloads and installs the Hosts File Manager script. 

.DESCRIPTION
    This script downloads the Hosts File Manager from GitHub, saves it to a standard
    Windows-only: Hosts File Manager is not available on macOS or Linux.
    location, and executes it to update the Windows hosts file with ad-blocking rules.

.NOTES
    File Name      : hosts.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Hosts File Manager is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
    Write-Host "Installing Hosts File Manager..." -ForegroundColor Cyan
    
    # Define download URL and installation path
    $hostsScriptUrl = "https://raw.githubusercontent.com/mytech-today-now/hosts/refs/heads/main/hosts.ps1"
    $installPath = "$env:USERPROFILE\myTech.Today\scripts"
    $scriptPath = Join-Path $installPath "hosts.ps1"
    
    # Create installation directory
    if (-not (Test-Path $installPath)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        Write-Host "  [INFO] Created directory: $installPath" -ForegroundColor Gray
    }
    
    # Download Hosts File Manager script
    Write-Host "  [1/3] Downloading Hosts File Manager from GitHub..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $hostsScriptUrl -OutFile $scriptPath -UseBasicParsing
        Write-Host "  [OK] Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FAIL] Failed to download: $_" -ForegroundColor Red
        exit 1
    }
    
    # Verify the downloaded file
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  [FAIL] Downloaded file not found at: $scriptPath" -ForegroundColor Red
        exit 1
    }
    
    $fileSize = (Get-Item $scriptPath).Length
    if ($fileSize -lt 1000) {
        Write-Host "  [FAIL] Downloaded file appears to be invalid (size: $fileSize bytes)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  [OK] Script saved to: $scriptPath" -ForegroundColor Green
    
    # Execute the Hosts File Manager to update the hosts file
    Write-Host "  [2/3] Executing Hosts File Manager to update hosts file..." -ForegroundColor Yellow
    Write-Host "  [INFO] This will download ad-blocking rules and update your hosts file" -ForegroundColor Cyan
    
    try {
        # Execute the script with PowerShell
        # Note: The script requires administrator privileges, which should already be granted
        # since the installer runs as administrator
        & powershell.exe -ExecutionPolicy Bypass -File $scriptPath
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "  [OK] Hosts file updated successfully" -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] Hosts file update completed with exit code: $exitCode" -ForegroundColor Yellow
            Write-Host "  [INFO] You can run the script manually later: $scriptPath" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Host "  [WARN] Error executing Hosts File Manager: $_" -ForegroundColor Yellow
        Write-Host "  [INFO] Script installed but not executed. Run manually: $scriptPath" -ForegroundColor Cyan
    }
    
    # Create desktop shortcut for easy access
    Write-Host "  [3/3] Creating desktop shortcut..." -ForegroundColor Yellow
    
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Hosts File Manager.lnk"
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.WorkingDirectory = $installPath
        $shortcut.Description = "Manage Windows hosts file with ad-blocking rules"
        $shortcut.IconLocation = "shell32.dll,21"
        $shortcut.Save()
        
        Write-Host "  [OK] Desktop shortcut created" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not create desktop shortcut: $_" -ForegroundColor Yellow
    }
    
    Write-Host "`n[OK] Hosts File Manager installed successfully!" -ForegroundColor Green
    Write-Host "  Location: $scriptPath" -ForegroundColor Cyan
    Write-Host "  Desktop shortcut created for easy access" -ForegroundColor Cyan
    Write-Host "`n  Usage:" -ForegroundColor Cyan
    Write-Host "    - Double-click the desktop shortcut to update hosts file" -ForegroundColor Gray
    Write-Host "    - Or run: powershell -ExecutionPolicy Bypass -File `"$scriptPath`"" -ForegroundColor Gray
    Write-Host "    - Run with -Force to force update even if already current" -ForegroundColor Gray
    Write-Host "    - Run with -BackupOnly to create a backup without updating" -ForegroundColor Gray
    
    exit 0
}
catch {
    Write-Host "[FAIL] Error installing Hosts File Manager: $_" -ForegroundColor Red
    exit 1
}

