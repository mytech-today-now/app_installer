<#
.SYNOPSIS
    Creates desktop and start menu shortcuts for ChatGPT.

.DESCRIPTION
    This script creates shortcuts to ChatGPT (https://chat.openai.com) on the desktop
    and in the start menu for easy access.

.NOTES
    File Name      : chatgpt-shortcuts.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] ChatGPT Shortcuts is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Creating ChatGPT shortcuts..." -ForegroundColor Cyan
    
    # Define ChatGPT URL
    $chatgptUrl = "https://chat.openai.com"
    $shortcutName = "ChatGPT.url"
    
    # Create desktop shortcut
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopShortcut = Join-Path $desktopPath $shortcutName
    
    $urlContent = @"
[InternetShortcut]
URL=$chatgptUrl
IconIndex=0
"@
    
    Set-Content -Path $desktopShortcut -Value $urlContent -Force
    Write-Host "  ? Desktop shortcut created: $desktopShortcut" -ForegroundColor Green
    
    # Create start menu shortcut
    $startMenuPath = [Environment]::GetFolderPath("StartMenu")
    $startMenuShortcut = Join-Path $startMenuPath $shortcutName
    
    Set-Content -Path $startMenuShortcut -Value $urlContent -Force
    Write-Host "  ? Start Menu shortcut created: $startMenuShortcut" -ForegroundColor Green
    
    Write-Host "ChatGPT shortcuts created successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error creating ChatGPT shortcuts: $_" -ForegroundColor Red
    exit 1
}

