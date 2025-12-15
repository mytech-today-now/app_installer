# AceMoney Lite Installation Script 
# Part of myTech.Today Application Installer Suite
# Windows-only: AceMoney Lite is not available on macOS or Linux.

param(
    [string]$LogPath = "C:\myTech.Today\logs\AppInstaller.md"
)

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] AceMoney Lite is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$AppName = "AceMoney Lite"
$WingetId = ""

Write-Host "Installing $AppName..." -ForegroundColor Cyan

try {
    # This application is not available via winget
    Write-Host "  [i] $AppName is not available via winget" -ForegroundColor Yellow
    Write-Host "  [i] Please download and install manually from: https://www.mechcad.net/products/acemoney/" -ForegroundColor Cyan
    Write-Host "  [i] Opening download page in browser..." -ForegroundColor Gray
    
    Start-Process "https://www.mechcad.net/products/acemoney/"
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | INFO | $AppName manual installation initiated" | Out-File -FilePath $LogPath -Append
    Write-Host "  [OK] Download page opened. Please complete installation manually." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "  [!] Error: $_" -ForegroundColor Red
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR | $AppName installation error: $_" | Out-File -FilePath $LogPath -Append
    exit 1
}
