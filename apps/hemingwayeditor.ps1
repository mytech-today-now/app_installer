# Hemingway Editor Installation Script
# Part of myTech.Today Application Installer Suite

param(
    [string]$LogPath = "C:\myTech.Today\logs\AppInstaller.md"
)

$AppName = "Hemingway Editor"
$WingetId = ""

Write-Host "Installing $AppName..." -ForegroundColor Cyan

try {
    # This application is not available via winget
    Write-Host "  [i] $AppName is not available via winget" -ForegroundColor Yellow
    Write-Host "  [i] Please download and install manually from: https://hemingwayapp.com/" -ForegroundColor Cyan
    Write-Host "  [i] Opening download page in browser..." -ForegroundColor Gray
    
    Start-Process "https://hemingwayapp.com/"
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | INFO | $AppName manual installation initiated" | Out-File -FilePath $LogPath -Append
    Write-Host "  [OK] Download page opened. Please complete installation manually." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "  [!] Error: $_" -ForegroundColor Red
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR | $AppName installation error: $_" | Out-File -FilePath $LogPath -Append
    exit 1
}
