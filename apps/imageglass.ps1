<#
.SYNOPSIS
    Installs ImageGlass.
.DESCRIPTION
    Installs ImageGlass using winget.
    Windows-only: ImageGlass is not available on macOS or Linux.
.NOTES
    File Name      : imageglass.ps1
    Author         : myTech.Today
    Version        : 1.0.0
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] ImageGlass is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

$AppName = 'ImageGlass'
$WingetId = 'ImageGlass.ImageGlass'

$logAvailable = $false
try {
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        $logAvailable = $true
    }
}
catch {
    # Logging is optional; ignore errors when probing for Write-Log
}

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan
    if ($logAvailable) { Write-Log "Starting installation for $AppName using winget id '$WingetId'." -Level 'INFO' }

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  [X] winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        if ($logAvailable) { Write-Log "winget not found while installing $AppName." -Level 'ERROR' }
        exit 1
    }

    Write-Host "  Installing via winget..." -ForegroundColor Yellow
    $result = winget install --id $WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $AppName installed successfully!" -ForegroundColor Green
        if ($logAvailable) { Write-Log "$AppName installed successfully." -Level 'SUCCESS' }
        exit 0
    }
    else {
        Write-Host "  [X] Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        if ($logAvailable) { Write-Log "Installation of $AppName failed with exit code $LASTEXITCODE. Output: $result" -Level 'ERROR' }
        exit 1
    }
}
catch {
    Write-Host "Error installing $AppName: $_" -ForegroundColor Red
    if ($logAvailable) { Write-Log "Unhandled error while installing $AppName: $_" -Level 'ERROR' }
    exit 1
}

