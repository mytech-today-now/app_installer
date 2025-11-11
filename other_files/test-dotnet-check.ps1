#Requires -Version 5.1

<#
.SYNOPSIS
    Test script for .NET Framework detection functionality.

.DESCRIPTION
    Tests the .NET Framework detection and version checking functions
    added to install-gui.ps1 without running the full GUI.

.NOTES
    File Name      : test-dotnet-check.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+
    Version        : 1.0.0
#>

function Get-DotNetFrameworkVersion {
    [CmdletBinding()]
    param()
    
    try {
        $releaseKey = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
        
        if (Test-Path $releaseKey) {
            $release = (Get-ItemProperty -Path $releaseKey -Name Release -ErrorAction SilentlyContinue).Release
            
            if ($release) {
                Write-Host "[CHECK] .NET Framework release number: $release" -ForegroundColor Cyan
                return $release
            }
        }
        
        Write-Host "[WARN] .NET Framework 4.5+ not detected in registry" -ForegroundColor Yellow
        return 0
    }
    catch {
        Write-Host "[ERROR] Failed to check .NET Framework version: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
}

function Get-DotNetFrameworkVersionName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Release
    )
    
    if ($Release -ge 528040) { return "4.8" }
    elseif ($Release -ge 461808) { return "4.7.2" }
    elseif ($Release -ge 461308) { return "4.7.1" }
    elseif ($Release -ge 460798) { return "4.7" }
    elseif ($Release -ge 394802) { return "4.6.2" }
    elseif ($Release -ge 394254) { return "4.6.1" }
    elseif ($Release -ge 393295) { return "4.6" }
    elseif ($Release -ge 379893) { return "4.5.2" }
    elseif ($Release -ge 378675) { return "4.5.1" }
    elseif ($Release -ge 378389) { return "4.5" }
    else { return "Unknown" }
}

# Main test
Write-Host "=== .NET Framework Detection Test ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Testing .NET Framework detection..." -ForegroundColor Cyan
$release = Get-DotNetFrameworkVersion

if ($release -eq 0) {
    Write-Host "[ERROR] .NET Framework not detected" -ForegroundColor Red
    Write-Host "[INFO] .NET Framework 4.7.2 or later is required for install-gui.ps1" -ForegroundColor Yellow
    exit 1
}

$versionName = Get-DotNetFrameworkVersionName -Release $release
Write-Host "[OK] .NET Framework $versionName detected (Release: $release)" -ForegroundColor Green

if ($release -lt 461808) {
    Write-Host "[WARN] .NET Framework $versionName is below the recommended version (4.7.2)" -ForegroundColor Yellow
    Write-Host "[INFO] GUI may not function properly with this version" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "[OK] .NET Framework version is sufficient for GUI (4.7.2+)" -ForegroundColor Green
}

Write-Host ""
Write-Host "[INFO] Testing assembly loading..." -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web
    Write-Host "[OK] All required assemblies loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to load assemblies: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Green
Write-Host "[OK] All .NET Framework checks passed!" -ForegroundColor Green
Write-Host "[INFO] install-gui.ps1 should work correctly on this system" -ForegroundColor Cyan

