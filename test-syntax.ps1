# Test syntax of install-gui.ps1
$scriptPath = Join-Path $PSScriptRoot "install-gui.ps1"

Write-Host "Checking syntax of: $scriptPath" -ForegroundColor Cyan

try {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
    
    if ($errors) {
        Write-Host "`n[ERROR] Syntax errors found:" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  Line $($error.Extent.StartLineNumber): $($error.Message)" -ForegroundColor Red
        }
        exit 1
    }
    else {
        Write-Host "`n[OK] No syntax errors found" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Host "`n[ERROR] Failed to parse file: $_" -ForegroundColor Red
    exit 1
}

