# Test syntax of install.ps1 and install-gui.ps1
Write-Host "`n=== Testing PowerShell Syntax ===" -ForegroundColor Cyan

# Test install.ps1
Write-Host "`nTesting install.ps1..." -ForegroundColor Yellow
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    "$PSScriptRoot\install.ps1",
    [ref]$null,
    [ref]$errors
)

if ($errors) {
    Write-Host "Syntax errors found in install.ps1:" -ForegroundColor Red
    $errors | ForEach-Object {
        Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "[OK] No syntax errors found in install.ps1" -ForegroundColor Green
}

# Test install-gui.ps1
Write-Host "`nTesting install-gui.ps1..." -ForegroundColor Yellow
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    "$PSScriptRoot\install-gui.ps1",
    [ref]$null,
    [ref]$errors
)

if ($errors) {
    Write-Host "Syntax errors found in install-gui.ps1:" -ForegroundColor Red
    $errors | ForEach-Object {
        Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "[OK] No syntax errors found in install-gui.ps1" -ForegroundColor Green
}

Write-Host "`n=== Syntax Testing Complete ===" -ForegroundColor Cyan

