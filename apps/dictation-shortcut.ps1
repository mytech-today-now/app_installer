<#
.SYNOPSIS
    Creates desktop and start menu shortcuts for dictation.io.

.DESCRIPTION
    This script creates shortcuts that open https://dictation.io/speech in Chrome browser
    on the desktop and in the start menu for easy access.

.NOTES
    File Name      : dictation-shortcut.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Dictation Shortcut is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Creating dictation.io shortcuts..." -ForegroundColor Cyan
    
    # Define dictation.io URL
    $dictationUrl = "https://dictation.io/speech"
    $shortcutName = "dictation.io.url"
    
    # Create desktop shortcut
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopShortcut = Join-Path $desktopPath $shortcutName
    
    $urlContent = @"
[InternetShortcut]
URL=$dictationUrl
IconIndex=0
"@
    
    Set-Content -Path $desktopShortcut -Value $urlContent -Force
    Write-Host "  ? Desktop shortcut created: $desktopShortcut" -ForegroundColor Green
    
    # Create start menu shortcut
    $startMenuPath = [Environment]::GetFolderPath("StartMenu")
    $startMenuShortcut = Join-Path $startMenuPath $shortcutName
    
    Set-Content -Path $startMenuShortcut -Value $urlContent -Force
    Write-Host "  ? Start Menu shortcut created: $startMenuShortcut" -ForegroundColor Green
    
    Write-Host "dictation.io shortcuts created successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error creating dictation.io shortcuts: $_" -ForegroundColor Red
    exit 1
}

