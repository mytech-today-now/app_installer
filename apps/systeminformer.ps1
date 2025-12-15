# System Informer Installation Helper Script 
# Part of myTech.Today Application Installer Suite
# Windows-only: System Informer is not available on macOS or Linux.

param(
    [string]$LogPath = (Join-Path $env:USERPROFILE "myTech.Today\logs\AppInstaller.md")
)

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] System Informer is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$AppName    = "System Informer"
$WingetId   = "WinsiderSS.SystemInformer"
$Homepage   = "https://systeminformer.sourceforge.io/"

# Ensure log directory exists (best-effort)
try {
    $logDir = Split-Path -Path $LogPath -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
}
catch {
    # Non-fatal: continue even if log directory can't be created
}

Write-Host "Installing $AppName (successor to Process Hacker)..." -ForegroundColor Cyan
Write-Host "  Automatic installation from this tool is not currently supported." -ForegroundColor Yellow
Write-Host "  Please visit $Homepage to download and install the latest version of $AppName." -ForegroundColor Cyan
Write-Host "  You can also run 'winget show $WingetId' to view available versions and details." -ForegroundColor Gray

try {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp | INFO  | $AppName requires manual installation from $Homepage. Run 'winget show $WingetId' for details." |
        Out-File -FilePath $LogPath -Append -Encoding UTF8
}
catch {
    # Best-effort logging only
}

# Signal to the caller (install.ps1 / install-gui.ps1) that installation did NOT complete
# so the application will not be marked as successfully installed.
$global:LASTEXITCODE = 1

