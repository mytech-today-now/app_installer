#Requires -Version 5.1

[CmdletBinding()]
param()

Write-Host 'Direct execution of the O&O ShutUp10 app script is disabled.' -ForegroundColor Yellow
Write-Host 'Select O&O ShutUp10 in App Installer to use the pinned trust path.' -ForegroundColor Cyan
Write-Host 'No approved release is currently configured, so that path will fail closed. No download, installation, shortcut, or privacy-setting change was made.' -ForegroundColor Yellow
exit 1
