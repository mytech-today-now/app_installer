# Cakewalk by BandLab Installation Script
# Part of myTech.Today Application Installer Suite
# Windows-only: Cakewalk is not available on macOS or Linux.

param(
    [string]$LogPath = "C:\myTech.Today\logs\AppInstaller.md"
)

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Cakewalk is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$AppName = "Cakewalk by BandLab"
$WingetId = "BandLab.Cakewalk"

Write-Host "Installing $AppName..." -ForegroundColor Cyan

try {
    # Try winget installation first
    Write-Host "  Attempting installation via winget..." -ForegroundColor Gray
    $result = winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $AppName installed successfully via winget" -ForegroundColor Green
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | INFO | $AppName installed successfully via winget" | Out-File -FilePath $LogPath -Append
        exit 0
    }
    else {
        throw "Winget installation failed"
    }
}
catch {
    Write-Host "  [!] Winget installation failed: $_" -ForegroundColor Yellow
    Write-Host "  [i] Please install $AppName manually from https://www.bandlab.com/products/cakewalk" -ForegroundColor Cyan
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | WARNING | $AppName winget installation failed: $_" | Out-File -FilePath $LogPath -Append
    exit 1
}
