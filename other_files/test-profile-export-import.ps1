# Test script for Export/Import Profile functionality
# This script tests the profile export/import functions

#Requires -Version 5.1
#Requires -RunAsAdministrator

Write-Host "=== Testing Profile Export/Import Functionality ===" -ForegroundColor Cyan
Write-Host ""

# Set up test environment
$script:ScriptVersion = '1.3.8'
$script:CentralLogPath = "C:\mytech.today\logs\"
$script:LogPath = Join-Path $script:CentralLogPath "test-profile-$(Get-Date -Format 'yyyy-MM-dd').log"

# Create log directory if it doesn't exist
if (-not (Test-Path $script:CentralLogPath)) {
    New-Item -Path $script:CentralLogPath -ItemType Directory -Force | Out-Null
}

# Simple logging function for testing
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "| $timestamp | $Level | $Message |"
    Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host "[$Level] $Message" -ForegroundColor $(
        switch ($Level) {
            'SUCCESS' { 'Green' }
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'White' }
        }
    )
}

# Sample applications array (subset for testing)
$script:Applications = @(
    [PSCustomObject]@{ Name = "Google Chrome"; ScriptName = "chrome.ps1"; WingetId = "Google.Chrome"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "7-Zip"; ScriptName = "7zip.ps1"; WingetId = "7zip.7zip"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "VLC Media Player"; ScriptName = "vlc.ps1"; WingetId = "VideoLAN.VLC"; Category = "Media" }
    [PSCustomObject]@{ Name = "Visual Studio Code"; ScriptName = "vscode.ps1"; WingetId = "Microsoft.VisualStudioCode"; Category = "Development" }
    [PSCustomObject]@{ Name = "Git"; ScriptName = "git.ps1"; WingetId = "Git.Git"; Category = "Development" }
    [PSCustomObject]@{ Name = "Firefox"; ScriptName = "firefox.ps1"; WingetId = "Mozilla.Firefox"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Notepad++"; ScriptName = "notepadplusplus.ps1"; WingetId = "Notepad++.Notepad++"; Category = "Development" }
    [PSCustomObject]@{ Name = "Adobe Reader"; ScriptName = "adobereader.ps1"; WingetId = "Adobe.Acrobat.Reader.64-bit"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Zoom"; ScriptName = "zoom.ps1"; WingetId = "Zoom.Zoom"; Category = "Communication" }
    [PSCustomObject]@{ Name = "Slack"; ScriptName = "slack.ps1"; WingetId = "SlackTechnologies.Slack"; Category = "Communication" }
)

# Source the export/import functions from install-gui.ps1
Write-Host "Loading Export/Import functions..." -ForegroundColor Yellow

# Extract the functions from install-gui.ps1
$guiScriptPath = Join-Path $PSScriptRoot "install-gui.ps1"
if (-not (Test-Path $guiScriptPath)) {
    Write-Host "[ERROR] install-gui.ps1 not found at: $guiScriptPath" -ForegroundColor Red
    exit 1
}

# Read the script and extract the Export/Import functions
$scriptContent = Get-Content $guiScriptPath -Raw

# Extract Export-InstallationProfile function
if ($scriptContent -match '(?s)function Export-InstallationProfile \{.*?\n\}(?=\n\nfunction|\n\n#endregion)') {
    $exportFunction = $matches[0]
    Invoke-Expression $exportFunction
    Write-Host "[OK] Loaded Export-InstallationProfile function" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Could not extract Export-InstallationProfile function" -ForegroundColor Red
    exit 1
}

# Extract Import-InstallationProfile function
if ($scriptContent -match '(?s)function Import-InstallationProfile \{.*?\n\}(?=\n\n#endregion)') {
    $importFunction = $matches[0]
    Invoke-Expression $importFunction
    Write-Host "[OK] Loaded Import-InstallationProfile function" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Could not extract Import-InstallationProfile function" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 1: Export a selection of 10 apps
Write-Host "=== Test 1: Export 10 Applications ===" -ForegroundColor Cyan
$selectedApps = $script:Applications | Select-Object -First 10
$appNames = $selectedApps | ForEach-Object { $_.Name }

$testProfilePath = "C:\mytech.today\app_installer\profiles\test-profile-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$exportedPath = Export-InstallationProfile -SelectedApps $appNames -FilePath $testProfilePath

if ($exportedPath -and (Test-Path $exportedPath)) {
    Write-Host "[PASS] Export successful: $exportedPath" -ForegroundColor Green
    
    # Verify JSON structure
    $jsonContent = Get-Content $exportedPath -Raw | ConvertFrom-Json
    if ($jsonContent.Version -and $jsonContent.Applications -and $jsonContent.Timestamp) {
        Write-Host "[PASS] JSON structure is valid" -ForegroundColor Green
        Write-Host "  Version: $($jsonContent.Version)" -ForegroundColor Gray
        Write-Host "  Timestamp: $($jsonContent.Timestamp)" -ForegroundColor Gray
        Write-Host "  Computer: $($jsonContent.ComputerName)" -ForegroundColor Gray
        Write-Host "  User: $($jsonContent.UserName)" -ForegroundColor Gray
        Write-Host "  Installer Version: $($jsonContent.InstallerVersion)" -ForegroundColor Gray
        Write-Host "  Applications: $($jsonContent.Applications.Count)" -ForegroundColor Gray
    }
    else {
        Write-Host "[FAIL] JSON structure is invalid" -ForegroundColor Red
    }
}
else {
    Write-Host "[FAIL] Export failed" -ForegroundColor Red
}

Write-Host ""

# Test 2: Import the profile
Write-Host "=== Test 2: Import Profile ===" -ForegroundColor Cyan
$importResult = Import-InstallationProfile -FilePath $exportedPath

if ($importResult.Success) {
    Write-Host "[PASS] Import successful" -ForegroundColor Green
    Write-Host "  Applications found: $($importResult.Applications.Count)" -ForegroundColor Gray
    Write-Host "  Missing apps: $($importResult.MissingApps.Count)" -ForegroundColor Gray
    
    if ($importResult.Applications.Count -eq 10) {
        Write-Host "[PASS] All 10 applications imported correctly" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Expected 10 applications, got $($importResult.Applications.Count)" -ForegroundColor Red
    }
}
else {
    Write-Host "[FAIL] Import failed: $($importResult.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: Test with missing apps
Write-Host "=== Test 3: Import Profile with Missing Apps ===" -ForegroundColor Cyan

# Create a profile with some apps that don't exist
$testProfileWithMissing = @{
    Version = "1.0"
    Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    InstallerVersion = "1.3.8"
    Applications = @(
        "Google Chrome",
        "NonExistentApp1",
        "7-Zip",
        "NonExistentApp2",
        "VLC Media Player"
    )
}

$testMissingPath = "C:\mytech.today\app_installer\profiles\test-missing-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$testProfileWithMissing | ConvertTo-Json | Set-Content -Path $testMissingPath -Encoding UTF8

$importMissingResult = Import-InstallationProfile -FilePath $testMissingPath

if ($importMissingResult.Success) {
    Write-Host "[PASS] Import with missing apps handled correctly" -ForegroundColor Green
    Write-Host "  Valid applications: $($importMissingResult.Applications.Count)" -ForegroundColor Gray
    Write-Host "  Missing applications: $($importMissingResult.MissingApps.Count)" -ForegroundColor Gray
    
    if ($importMissingResult.Applications.Count -eq 3 -and $importMissingResult.MissingApps.Count -eq 2) {
        Write-Host "[PASS] Correctly identified 3 valid and 2 missing apps" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Expected 3 valid and 2 missing, got $($importMissingResult.Applications.Count) valid and $($importMissingResult.MissingApps.Count) missing" -ForegroundColor Red
    }
}
else {
    Write-Host "[FAIL] Import failed: $($importMissingResult.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 4: Test with corrupted JSON
Write-Host "=== Test 4: Import Corrupted JSON ===" -ForegroundColor Cyan

$testCorruptedPath = "C:\mytech.today\app_installer\profiles\test-corrupted-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
Set-Content -Path $testCorruptedPath -Value "{ invalid json content }" -Encoding UTF8

$importCorruptedResult = Import-InstallationProfile -FilePath $testCorruptedPath

if (-not $importCorruptedResult.Success) {
    Write-Host "[PASS] Corrupted JSON handled correctly (import failed as expected)" -ForegroundColor Green
    Write-Host "  Error message: $($importCorruptedResult.Message)" -ForegroundColor Gray
}
else {
    Write-Host "[FAIL] Corrupted JSON should have failed import" -ForegroundColor Red
}

Write-Host ""

# Test 5: Test with missing file
Write-Host "=== Test 5: Import Non-Existent File ===" -ForegroundColor Cyan

$nonExistentPath = "C:\mytech.today\app_installer\profiles\non-existent-file.json"
$importNonExistentResult = Import-InstallationProfile -FilePath $nonExistentPath

if (-not $importNonExistentResult.Success) {
    Write-Host "[PASS] Non-existent file handled correctly (import failed as expected)" -ForegroundColor Green
    Write-Host "  Error message: $($importNonExistentResult.Message)" -ForegroundColor Gray
}
else {
    Write-Host "[FAIL] Non-existent file should have failed import" -ForegroundColor Red
}

Write-Host ""

# Cleanup test files
Write-Host "=== Cleanup ===" -ForegroundColor Cyan
Write-Host "Test files created:" -ForegroundColor Yellow
Write-Host "  $exportedPath" -ForegroundColor Gray
Write-Host "  $testMissingPath" -ForegroundColor Gray
Write-Host "  $testCorruptedPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Do you want to delete these test files? (Y/N): " -NoNewline -ForegroundColor Yellow
$cleanup = Read-Host

if ($cleanup -match '^[Yy]') {
    Remove-Item $exportedPath -ErrorAction SilentlyContinue
    Remove-Item $testMissingPath -ErrorAction SilentlyContinue
    Remove-Item $testCorruptedPath -ErrorAction SilentlyContinue
    Write-Host "[OK] Test files deleted" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Test files kept for review" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host "Check log file: $script:LogPath" -ForegroundColor Gray

