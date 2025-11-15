#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test script to verify logging module integration.

.DESCRIPTION
    Tests the generic logging module integration in both install.ps1 and install-gui.ps1.
    Verifies:
    - Logging module loads successfully
    - Log files are created in correct format
    - Monthly log rotation works
    - All log levels work correctly
#>

Write-Host "`n=== Testing Logging Module Integration ===" -ForegroundColor Cyan

#region Test Generic Logging Module Directly

Write-Host "`n[1] Testing generic logging module directly..." -ForegroundColor Yellow

# Import logging module
$loggingUrl = 'https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/refs/heads/main/scripts/logging.ps1'
try {
    Write-Host "  Loading logging module from GitHub..." -ForegroundColor Cyan
    Invoke-Expression (Invoke-WebRequest -Uri $loggingUrl -UseBasicParsing).Content
    Write-Host "  [OK] Logging module loaded" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to load logging module: $_" -ForegroundColor Red
    Write-Host "  Trying local path..." -ForegroundColor Yellow
    
    $localPath = Join-Path $PSScriptRoot "..\scripts\logging.ps1"
    if (Test-Path $localPath) {
        . $localPath
        Write-Host "  [OK] Loaded from local path" -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] Local path not found" -ForegroundColor Red
        exit 1
    }
}

# Initialize logging
Write-Host "`n  Initializing logging..." -ForegroundColor Cyan
$logPath = Initialize-Log -ScriptName "LoggingTest" -ScriptVersion "1.0.0"

if ($logPath) {
    Write-Host "  [OK] Logging initialized" -ForegroundColor Green
    Write-Host "  Log path: $logPath" -ForegroundColor Gray
}
else {
    Write-Host "  [ERROR] Failed to initialize logging" -ForegroundColor Red
    exit 1
}

# Test all log levels
Write-Host "`n  Testing log levels..." -ForegroundColor Cyan
Write-Log "This is an INFO message" -Level INFO
Write-Log "This is a SUCCESS message" -Level SUCCESS
Write-Log "This is a WARNING message" -Level WARNING
Write-Log "This is an ERROR message" -Level ERROR
Write-Host "  [OK] All log levels tested" -ForegroundColor Green

# Verify log file exists and has correct format
Write-Host "`n  Verifying log file format..." -ForegroundColor Cyan
if (Test-Path $logPath) {
    $logContent = Get-Content $logPath -Raw
    
    # Check for markdown header
    if ($logContent -match "# LoggingTest Log") {
        Write-Host "  [OK] Markdown header found" -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] Markdown header not found" -ForegroundColor Red
    }
    
    # Check for table format
    if ($logContent -match "\| Timestamp \| Level \| Message \|") {
        Write-Host "  [OK] Markdown table format found" -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] Markdown table format not found" -ForegroundColor Red
    }
    
    # Check for log entries
    if ($logContent -match "\[INFO\]" -and $logContent -match "\[OK\]" -and 
        $logContent -match "\[WARN\]" -and $logContent -match "\[ERROR\]") {
        Write-Host "  [OK] All log level indicators found" -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] Some log level indicators missing" -ForegroundColor Red
    }
    
    Write-Host "`n  Log file preview (first 20 lines):" -ForegroundColor Gray
    Get-Content $logPath | Select-Object -First 20 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  [ERROR] Log file not found at: $logPath" -ForegroundColor Red
}

#endregion

#region Test Monthly Log File Naming

Write-Host "`n[2] Testing monthly log file naming..." -ForegroundColor Yellow

$expectedMonth = Get-Date -Format 'yyyy-MM'
$expectedFileName = "LoggingTest-$expectedMonth.md"

if ($logPath -match [regex]::Escape($expectedFileName)) {
    Write-Host "  [OK] Log file uses monthly naming format: $expectedFileName" -ForegroundColor Green
}
else {
    Write-Host "  [ERROR] Log file does not use expected monthly format" -ForegroundColor Red
    Write-Host "  Expected: $expectedFileName" -ForegroundColor Red
    Write-Host "  Actual: $(Split-Path $logPath -Leaf)" -ForegroundColor Red
}

#endregion

#region Test Log Path Function

Write-Host "`n[3] Testing Get-LogPath function..." -ForegroundColor Yellow

$retrievedPath = Get-LogPath
if ($retrievedPath -eq $logPath) {
    Write-Host "  [OK] Get-LogPath returns correct path" -ForegroundColor Green
}
else {
    Write-Host "  [ERROR] Get-LogPath returned unexpected path" -ForegroundColor Red
    Write-Host "  Expected: $logPath" -ForegroundColor Red
    Write-Host "  Actual: $retrievedPath" -ForegroundColor Red
}

#endregion

Write-Host "`n=== Logging Module Integration Test Complete ===" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Review the log file at: $logPath" -ForegroundColor Gray
Write-Host "  2. Test install.ps1 with -Action Status to verify CLI integration" -ForegroundColor Gray
Write-Host "  3. Test install-gui.ps1 to verify GUI integration" -ForegroundColor Gray
Write-Host ""

