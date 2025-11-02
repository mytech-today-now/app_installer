<#
.SYNOPSIS
    Installs Brave Browser with version detection.

.DESCRIPTION
    This script detects if Brave Browser is already installed and shows version information.
    If not installed, it installs Brave Browser using winget package manager.

.NOTES
    File Name      : brave.ps1
    Author         : myTech.Today
    Version        : 1.1.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-BraveVersion {
    <#
    .SYNOPSIS
        Detects if Brave Browser is installed and returns version information.
    #>
    try {
        # Check using winget list (most reliable for winget-installed apps)
        $wingetList = winget list --id Brave.Brave --accept-source-agreements 2>$null | Out-String

        if ($wingetList -match 'Brave\.Brave') {
            # Extract version from winget output
            $lines = $wingetList -split "`n"
            $matchingLine = $lines | Where-Object { $_ -match 'Brave\.Brave' } | Select-Object -First 1

            if ($matchingLine -match '\s+([\d\.]+)\s+') {
                return $matches[1]
            }
            else {
                return "Installed"
            }
        }

        # Fallback: Check common installation paths
        $bravePaths = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:ProgramFiles(x86)\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe"
        )

        foreach ($path in $bravePaths) {
            if (Test-Path $path) {
                $version = (Get-Item $path).VersionInfo.FileVersion
                if ($version) {
                    return $version
                }
                return "Installed"
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

try {
    Write-Host "Brave Browser Installation Script" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host ""

    # Check if winget is available
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ❌ winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
        exit 1
    }

    # Check if Brave is already installed
    Write-Host "  Checking for existing installation..." -ForegroundColor Yellow
    $currentVersion = Get-BraveVersion

    if ($currentVersion) {
        Write-Host "  ✅ Brave Browser is already installed!" -ForegroundColor Green
        Write-Host "     Version: $currentVersion" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  To upgrade, run: winget upgrade --id Brave.Brave" -ForegroundColor Cyan
        exit 0
    }

    Write-Host "  Brave Browser not detected. Installing..." -ForegroundColor Yellow
    Write-Host ""

    # Install using winget
    Write-Host "  Installing via winget..." -ForegroundColor Yellow

    $result = winget install --id Brave.Brave --silent --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "  ✅ Brave Browser installed successfully!" -ForegroundColor Green

        # Verify installation
        $newVersion = Get-BraveVersion
        if ($newVersion) {
            Write-Host "     Installed Version: $newVersion" -ForegroundColor Gray
        }

        exit 0
    }
    else {
        Write-Host ""
        Write-Host "  ❌ Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Gray
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

