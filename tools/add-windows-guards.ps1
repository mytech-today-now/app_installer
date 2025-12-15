<#
.SYNOPSIS
    Adds Windows-only platform guards to all Windows-only app scripts.

.DESCRIPTION
    Reads the apps-manifest.json, finds all Windows-only apps, and adds platform
    guard code to their scripts so they exit gracefully on non-Windows systems.

.NOTES
    Part of Phase 3 of cross-platform support implementation.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $scriptRoot "apps-manifest.json"
$appsFolder = Join-Path $scriptRoot "apps"

# Load manifest and get Windows-only apps
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$windowsOnlyApps = $manifest.apps | Where-Object { $_.platform -eq "Windows" }

Write-Host "Found $($windowsOnlyApps.Count) Windows-only apps" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$skipCount = 0
$errorCount = 0

foreach ($app in $windowsOnlyApps) {
    $scriptPath = Join-Path $appsFolder "$($app.name).ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[SKIP] $($app.name).ps1 - file not found" -ForegroundColor Yellow
        $skipCount++
        continue
    }
    
    $content = Get-Content $scriptPath -Raw
    
    # Check if already has platform guard
    if ($content -match 'Platform check - this application is Windows-only') {
        Write-Host "[SKIP] $($app.name).ps1 - already has guard" -ForegroundColor Gray
        $skipCount++
        continue
    }
    
    try {
        # Define the guard code
        $guardCode = @"

# Platform check - this application is Windows-only
if (-not (`$IsWindows -or `$env:OS -match 'Windows')) {
    Write-Host "[INFO] $($app.displayName) is only available for Windows." -ForegroundColor Yellow
    exit 0
}

"@

        # Update the description to mention Windows-only
        $descriptionAddition = "    Windows-only: $($app.displayName) is not available on macOS or Linux."
        
        # Pattern: Insert after param() and add to description
        # Find where param() ends - look for param() followed by newlines
        if ($content -match '(param\(\))\r?\n') {
            # Insert guard after param()
            $newContent = $content -replace '(param\(\))\r?\n', "`$1`n$guardCode"
            
            # Update description - add Windows-only note
            # Look for .DESCRIPTION section and add to it
            if ($newContent -match '\.DESCRIPTION\s*\r?\n\s+.*(?:winget|package|installs|downloads).*?\r?\n') {
                # Find the line after .DESCRIPTION content
                $descPattern = '(\.DESCRIPTION\s*\r?\n\s+[^\r\n]+)'
                $newContent = $newContent -replace $descPattern, "`$1`n$descriptionAddition"
            }
            
            # Write back to file
            Set-Content -Path $scriptPath -Value $newContent -NoNewline
            Write-Host "[OK] $($app.name).ps1 updated" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Host "[ERROR] $($app.name).ps1 - could not find param() block" -ForegroundColor Red
            $errorCount++
        }
    }
    catch {
        Write-Host "[ERROR] $($app.name).ps1 - $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Updated: $successCount" -ForegroundColor Green
Write-Host "  Skipped: $skipCount" -ForegroundColor Yellow
Write-Host "  Errors:  $errorCount" -ForegroundColor Red

