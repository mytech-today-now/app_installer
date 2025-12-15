<#
.SYNOPSIS
    Creates desktop and start menu shortcuts for Grok AI.

.DESCRIPTION
    This script creates shortcuts to Grok AI (https://grok.x.ai) on the desktop
    and in the start menu for easy access.

.NOTES
    File Name      : grok-shortcuts.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Grok Shortcuts is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Creating Grok AI shortcuts..." -ForegroundColor Cyan
    
    # Define Grok AI URL
    $grokUrl = "https://grok.x.ai"
    $shortcutName = "Grok AI.url"
    
    # Create desktop shortcut
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopShortcut = Join-Path $desktopPath $shortcutName
    
    $urlContent = @"
[InternetShortcut]
URL=$grokUrl
IconIndex=0
"@
    
    Set-Content -Path $desktopShortcut -Value $urlContent -Force
    Write-Host "  ? Desktop shortcut created: $desktopShortcut" -ForegroundColor Green
    
    # Create start menu shortcut
    $startMenuPath = [Environment]::GetFolderPath("StartMenu")
    $startMenuShortcut = Join-Path $startMenuPath $shortcutName
    
    Set-Content -Path $startMenuShortcut -Value $urlContent -Force
    Write-Host "  ? Start Menu shortcut created: $startMenuShortcut" -ForegroundColor Green
    
    Write-Host "Grok AI shortcuts created successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error creating Grok AI shortcuts: $_" -ForegroundColor Red
    exit 1
}

