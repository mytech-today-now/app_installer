<#
.SYNOPSIS
    Monthly Windows Package Manager (winget) Update Script 

.DESCRIPTION
    This script updates all applications installed via winget on a monthly basis.
    Windows-only: Winget-AutoUpdate is not available on macOS or Linux.
    Installed and managed by myTech.Today to keep your system up-to-date and secure.

.NOTES
    File Name      : winget-update.ps1
    Author         : Kyle C. Rode / myTech.Today
    Version        : 1.0.0
    DateCreated    : 2025-10-31
    LastModified   : 2025-10-31
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Requires       : PowerShell 5.1 or later, winget

.LINK
    https://mytech.today
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Winget-AutoUpdate is only available for Windows." -ForegroundColor Yellow
    exit 0
}

# Script configuration
$script:ScriptName = 'winget-update.ps1'
$script:ScriptVersion = '1.0.0'
$script:LogPath = "C:\mytech.today\logs"

# Ensure log directory exists
if (-not (Test-Path $script:LogPath)) {
    New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
}

# Log file
$script:LogFile = Join-Path $script:LogPath "winget-update-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    # Write to console with color
    $color = switch ($Level) {
        'INFO'    { 'White' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# Display friendly explanation to user
function Show-UserExplanation {
    Clear-Host
    
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|              myTech.Today Monthly Application Updates             |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Hello! This is your monthly application update from myTech.Today," -ForegroundColor White
    Write-Host "  your IT solutions provider." -ForegroundColor White
    Write-Host ""
    Write-Host "  WHAT'S HAPPENING:" -ForegroundColor Yellow
    Write-Host "  We're updating all of your applications to keep your computer" -ForegroundColor Gray
    Write-Host "  secure, stable, and running smoothly. This happens automatically" -ForegroundColor Gray
    Write-Host "  on the 15th of each month at 1:00 PM." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  WHY YOU'RE SEEING THIS:" -ForegroundColor Yellow
    Write-Host "  Microsoft requires administrator permission to update applications." -ForegroundColor Gray
    Write-Host "  Unfortunately, Microsoft makes this process very obvious and" -ForegroundColor Gray
    Write-Host "  sometimes alarming with security prompts. We can't make it silent" -ForegroundColor Gray
    Write-Host "  or invisible - that's a Microsoft security requirement." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  WHAT YOU NEED TO DO:" -ForegroundColor Yellow
    Write-Host "  When Microsoft asks if it's OK to make changes to your device," -ForegroundColor Green
    Write-Host "  please click:" -ForegroundColor Green
    Write-Host ""
    Write-Host "    [OK]  or  [YES]  or  [ALLOW]  or  [CONTINUE]" -ForegroundColor Cyan -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host "  This is normal and expected. We're just updating your apps!" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  At myTech.Today, we explain what's happening because it makes" -ForegroundColor White
    Write-Host "  life easier. No surprises, no confusion - just clear communication." -ForegroundColor White
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Starting updates in 10 seconds..." -ForegroundColor Yellow
    Write-Host "  (Press Ctrl+C to cancel if needed)" -ForegroundColor Gray
    Write-Host ""
    
    # Give user time to read
    Start-Sleep -Seconds 10
}

# Main execution
try {
    Write-Log "=== Starting Monthly winget Update ===" -Level INFO
    Write-Log "Script Version: $script:ScriptVersion" -Level INFO
    
    # Show friendly explanation
    Show-UserExplanation
    
    # Check if winget is available
    Write-Log "Checking for winget availability..." -Level INFO
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    
    if ($null -eq $winget) {
        Write-Log "winget is not available on this system" -Level ERROR
        Write-Host ""
        Write-Host "[ERROR] Windows Package Manager (winget) is not installed." -ForegroundColor Red
        Write-Host "Please install 'App Installer' from the Microsoft Store." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
    
    Write-Log "winget found: $($winget.Source)" -Level SUCCESS
    
    # Run winget update --all
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                    Updating All Applications                      |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Running: winget update --all" -Level INFO
    Write-Host "Running: winget update --all" -ForegroundColor Cyan
    Write-Host ""
    
    # Execute winget update with all necessary flags
    $result = winget update --all --accept-source-agreements --accept-package-agreements 2>&1
    
    # Log the result
    if ($LASTEXITCODE -eq 0) {
        Write-Log "winget update completed successfully" -Level SUCCESS
        Write-Host ""
        Write-Host "[OK] All applications updated successfully!" -ForegroundColor Green
    }
    else {
        Write-Log "winget update completed with exit code: $LASTEXITCODE" -Level WARNING
        Write-Host ""
        Write-Host "[!] Updates completed with some warnings. Check log for details." -ForegroundColor Yellow
    }
    
    # Display completion message
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                      Update Complete!                             |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Your applications have been updated." -ForegroundColor Green
    Write-Host "  Next update: 15th of next month at 1:00 PM" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Log file: $script:LogFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Thank you for using myTech.Today services!" -ForegroundColor Cyan
    Write-Host "  Questions? Contact us at sales@mytech.today or (847) 767-4914" -ForegroundColor White
    Write-Host ""
    Write-Host "  This window will close in 30 seconds..." -ForegroundColor Yellow
    Write-Host "  (Press any key to close now)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Log "=== Monthly winget Update Completed ===" -Level INFO
    
    # Wait before closing
    $timeout = 30
    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
        if ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
            break
        }
        Start-Sleep -Milliseconds 100
    }
    
    exit 0
}
catch {
    Write-Log "Fatal error: $_" -Level ERROR
    Write-Host ""
    Write-Host "[ERROR] An error occurred: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please contact myTech.Today for assistance:" -ForegroundColor Yellow
    Write-Host "  Email: sales@mytech.today" -ForegroundColor White
    Write-Host "  Phone: (847) 767-4914" -ForegroundColor White
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

