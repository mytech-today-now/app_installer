<#
.SYNOPSIS 
    Downloads and installs Belarc Advisor.

.DESCRIPTION
    This script downloads and installs Belarc Advisor system information tool.
    Windows-only: Belarc Advisor is not available on macOS or Linux.

.NOTES
    File Name      : belarc.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] Belarc Advisor is only available for Windows." -ForegroundColor Yellow
    $global:LASTEXITCODE = 0
    return
}

$ErrorActionPreference = 'Stop'

try {
    $trustModulePath = Join-Path $PSScriptRoot '..\modules\BelarcInstallerTrust.psm1'
    Import-Module -Name $trustModulePath -Force -DisableNameChecking -ErrorAction Stop

    $release = Get-BelarcInstallerPinnedRelease
    $installerResult = Invoke-VerifiedBelarcInstaller `
        -Uri $release.Uri `
        -ExpectedSha256 $release.Sha256 `
        -ExpectedSignerThumbprint $release.SignerThumbprint

    if ($installerResult.Success) {
        Write-Host '[OK] Belarc Advisor installer completed.' -ForegroundColor Green
        $global:LASTEXITCODE = [int]$installerResult.ExitCode
    }
    else {
        Write-Host ("[ERROR] {0}" -f $installerResult.Message) -ForegroundColor Red
        $global:LASTEXITCODE = if ($null -ne $installerResult.ExitCode -and [int]$installerResult.ExitCode -ne 0) {
            [int]$installerResult.ExitCode
        }
        else {
            1
        }
    }
}
catch {
    Write-Host ("[ERROR] Belarc installer could not be verified or run: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $global:LASTEXITCODE = 1
}

