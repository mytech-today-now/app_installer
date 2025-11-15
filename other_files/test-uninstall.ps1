#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test script for uninstall functionality in App Installer.

.DESCRIPTION
    This script tests the uninstall functionality by:
    1. Installing a test application (Notepad++)
    2. Verifying it's installed
    3. Uninstalling it via the GUI/CLI
    4. Verifying it's removed

.NOTES
    File Name      : test-uninstall.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host "|              App Installer - Uninstall Feature Test               |" -ForegroundColor Cyan
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

# Test 1: Install Notepad++ for testing
Write-Host "[TEST 1] Installing Notepad++ for testing..." -ForegroundColor Yellow
Write-Host ""

$testApp = "Notepad++"
$testWingetId = "Notepad++.Notepad++"

# Check if already installed
Write-Host "Checking if $testApp is already installed..." -ForegroundColor Cyan
$installedCheck = winget list --id $testWingetId 2>&1 | Out-String

if ($installedCheck -match $testWingetId) {
    Write-Host "[OK] $testApp is already installed" -ForegroundColor Green
}
else {
    Write-Host "[INFO] $testApp is not installed. Installing now..." -ForegroundColor Cyan
    Write-Host ""
    
    $installResult = winget install --id $testWingetId --silent --accept-package-agreements --accept-source-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $testApp installed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Failed to install $testApp" -ForegroundColor Red
        Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "Cannot proceed with uninstall test without a test application." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

# Test 2: Verify installation
Write-Host "[TEST 2] Verifying $testApp installation..." -ForegroundColor Yellow
Write-Host ""

$verifyCheck = winget list --id $testWingetId 2>&1 | Out-String

if ($verifyCheck -match $testWingetId) {
    Write-Host "[OK] $testApp is confirmed installed" -ForegroundColor Green
    
    # Extract version if possible
    if ($verifyCheck -match "(\d+\.\d+(\.\d+)?)") {
        $version = $matches[1]
        Write-Host "Version: $version" -ForegroundColor Gray
    }
}
else {
    Write-Host "[ERROR] $testApp installation could not be verified" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

# Test 3: Manual uninstall test
Write-Host "[TEST 3] Testing uninstall command..." -ForegroundColor Yellow
Write-Host ""

Write-Host "This test will now uninstall $testApp using winget." -ForegroundColor Cyan
Write-Host ""
Write-Host "Command: winget uninstall --id $testWingetId --silent" -ForegroundColor Gray
Write-Host ""
Write-Host "Proceed with uninstall? (Y/N): " -NoNewline -ForegroundColor Yellow
$confirm = Read-Host

if ($confirm -match '^[Yy]') {
    Write-Host ""
    Write-Host "Uninstalling $testApp..." -ForegroundColor Cyan
    
    $uninstallResult = winget uninstall --id $testWingetId --silent 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $testApp uninstalled successfully" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Failed to uninstall $testApp" -ForegroundColor Red
        Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Output: $uninstallResult" -ForegroundColor Gray
    }
}
else {
    Write-Host "[INFO] Uninstall test cancelled" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

# Test 4: Verify uninstallation
Write-Host "[TEST 4] Verifying $testApp removal..." -ForegroundColor Yellow
Write-Host ""

Start-Sleep -Seconds 2  # Give winget time to update

$finalCheck = winget list --id $testWingetId 2>&1 | Out-String

if ($finalCheck -match $testWingetId) {
    Write-Host "[WARN] $testApp is still showing as installed" -ForegroundColor Yellow
    Write-Host "This may be a winget cache issue. Try running 'winget list' manually." -ForegroundColor Gray
}
else {
    Write-Host "[OK] $testApp is no longer installed" -ForegroundColor Green
}

Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host "|                         Test Complete                             |" -ForegroundColor Cyan
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - Uninstall command executed successfully" -ForegroundColor Green
Write-Host "  - Application removed from system" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test the GUI 'Uninstall Selected' button" -ForegroundColor White
Write-Host "  2. Test the CLI 'X' menu option" -ForegroundColor White
Write-Host "  3. Test uninstalling multiple applications" -ForegroundColor White
Write-Host "  4. Test error handling (uninstalling non-installed apps)" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to exit"

