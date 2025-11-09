<#
.SYNOPSIS
    Installs Manage Restore Points script.

.DESCRIPTION
    This script downloads and installs the Manage-RestorePoints.ps1 script from GitHub,
    which provides comprehensive management of Windows System Restore Points including
    automated creation, monitoring, and notification.

.NOTES
    File Name      : managerestorepoints.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Manage Restore Points script..." -ForegroundColor Cyan
    
    # Define download URL and installation paths
    $scriptUrl = "https://raw.githubusercontent.com/mytech-today-now/RestorePoints/main/Manage-RestorePoints.ps1"
    $installPath = "C:\myTech.Today\ManageRestorePoints"
    $logsPath = "C:\myTech.Today\logs"
    $scriptPath = Join-Path $installPath "Manage-RestorePoints.ps1"
    $configPath = Join-Path $installPath "ManageRestorePoints.json"

    # Create installation directory
    if (-not (Test-Path $installPath)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        Write-Host "  Created directory: $installPath" -ForegroundColor Gray
    }

    # Create logs directory
    if (-not (Test-Path $logsPath)) {
        New-Item -Path $logsPath -ItemType Directory -Force | Out-Null
        Write-Host "  Created logs directory: $logsPath" -ForegroundColor Gray
    }
    
    # Download Manage-RestorePoints.ps1
    Write-Host "  Downloading Manage-RestorePoints.ps1..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing
        Write-Host "  [OK] Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  [X] Failed to download: $_" -ForegroundColor Red
        exit 1
    }
    
    # Create default ManageRestorePoints.json if it doesn't exist
    if (-not (Test-Path $configPath)) {
        Write-Host "  Creating default configuration..." -ForegroundColor Yellow

        $defaultConfig = @{
            RestorePoint = @{
                DiskSpacePercent = 10
                MinimumCount = 10
                MaximumCount = 30
                CreateOnSchedule = $true
                ScheduleIntervalMinutes = 1440
                CreationFrequencyMinutes = 120
            }
            Email = @{
                Enabled = $false
                SmtpServer = 'smtp.example.com'
                SmtpPort = 587
                UseSsl = $true
                From = 'restorepoint@example.com'
                To = @('admin@example.com')
                Username = ''
                PasswordEncrypted = ''
            }
            Logging = @{
                LogPath = "C:\myTech.Today\logs\ManageRestorePoints.md"
                MaxLogSizeMB = 10
                RetentionDays = 30
            }
        }

        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force
        Write-Host "  [OK] Default configuration created" -ForegroundColor Green
    }
    
    # Create desktop shortcut
    Write-Host "  Creating desktop shortcut..." -ForegroundColor Yellow
    
    $WshShell = New-Object -ComObject WScript.Shell
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Manage Restore Points.lnk"
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" -Action List"
    $shortcut.WorkingDirectory = $installPath
    $shortcut.Description = "Manage Windows System Restore Points"
    $shortcut.IconLocation = "imageres.dll,109"
    $shortcut.Save()
    
    # Release COM object
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null

    Write-Host "  [OK] Desktop shortcut created" -ForegroundColor Green

    # Run the script to configure System Restore
    Write-Host "`n  Running initial configuration..." -ForegroundColor Yellow
    Write-Host "  This will enable System Restore and configure settings..." -ForegroundColor Gray

    try {
        & $scriptPath -Action Configure -ConfigPath $configPath
        Write-Host "  [OK] Initial configuration complete" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!] Warning: Initial configuration failed: $_" -ForegroundColor Yellow
        Write-Host "  You can run the configuration manually later." -ForegroundColor Gray
    }

    Write-Host "`n[OK] Manage Restore Points installed successfully!" -ForegroundColor Green
    Write-Host "  Script Location: $scriptPath" -ForegroundColor Cyan
    Write-Host "  Config Location: $configPath" -ForegroundColor Cyan
    Write-Host "  Desktop shortcut created" -ForegroundColor Cyan
    Write-Host "`nUsage Examples:" -ForegroundColor Yellow
    Write-Host "  List restore points:    powershell -ExecutionPolicy Bypass -File `"$scriptPath`" -Action List" -ForegroundColor Gray
    Write-Host "  Configure:              powershell -ExecutionPolicy Bypass -File `"$scriptPath`" -Action Configure" -ForegroundColor Gray
    Write-Host "  Create restore point:   powershell -ExecutionPolicy Bypass -File `"$scriptPath`" -Action Create -Description 'My Backup'" -ForegroundColor Gray
    Write-Host "  Monitor:                powershell -ExecutionPolicy Bypass -File `"$scriptPath`" -Action Monitor" -ForegroundColor Gray

    exit 0
}
catch {
    Write-Host "Error installing Manage Restore Points: $_" -ForegroundColor Red
    exit 1
}

