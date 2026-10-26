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

    $global:AppInstallerScriptOutcome = [PSCustomObject]@{
        Status = 'ManualActionRequired'
        Message = 'Complete installation from the vendor page and verify the app is installed before retrying. Opening the page does not confirm installation.'
    }

    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | WARNING | $AppName manual action required; vendor page opened" | Out-File -FilePath $LogPath -Append
    }
    catch {
        Write-Host "  [WARN] Could not write the app log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "  [ACTION REQUIRED] Download page opened. Complete installation manually and verify the app is installed." -ForegroundColor Yellow
}
catch {
    Write-Host "  [!] Error: $_" -ForegroundColor Red
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR | $AppName installation error: $_" | Out-File -FilePath $LogPath -Append
    exit 1
}
