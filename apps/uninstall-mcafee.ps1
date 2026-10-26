<#
.SYNOPSIS
    Uninstalls McAfee products using a verified MCPR helper.

.DESCRIPTION
    Runs McAfee Consumer Product Removal only after the shared remote-helper
    boundary verifies an approved digest or Authenticode signer. The production
    identity pin is currently unset, so the selected action fails closed.

.NOTES
    File Name      : uninstall-mcafee.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param()

if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host '[INFO] McAfee Uninstaller is only available for Windows.' -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    $trustModulePath = Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1'
    Import-Module -Name $trustModulePath -Force -DisableNameChecking -ErrorAction Stop
    $release = Get-RemoteExecutableHelperRelease -HelperId McAfee
    $helperArguments = @{
        HelperId = 'McAfee'
        Uri = $release.Uri
        ExpectedSha256 = $release.Sha256
        ExpectedSignerThumbprint = $release.SignerThumbprint
        ProcessArguments = @('-p')
    }

    $hasApprovedIdentity = (-not [string]::IsNullOrWhiteSpace($release.Sha256)) -or
        (-not [string]::IsNullOrWhiteSpace($release.SignerThumbprint))
    if (-not $hasApprovedIdentity) {
        $blockedResult = Invoke-VerifiedRemoteExecutableHelper @helperArguments
        Write-Host '[BLOCKED] MCPR has no approved digest or signer pin. No download or McAfee removal was attempted.' -ForegroundColor Red
        Write-Host "  Verification status: $($blockedResult.VerificationStatus); reason: $($blockedResult.FailureReason)" -ForegroundColor Yellow
        exit 1
    }

    $mcafeeInstalled = Get-ItemProperty @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*McAfee*' }

    if (-not $mcafeeInstalled) {
        Write-Host '[INFO] No McAfee products were found.' -ForegroundColor Cyan
        exit 0
    }

    Write-Host 'Found McAfee products:' -ForegroundColor Yellow
    foreach ($product in $mcafeeInstalled) {
        Write-Host "  - $($product.DisplayName)" -ForegroundColor Gray
    }

    $result = Invoke-VerifiedRemoteExecutableHelper @helperArguments

    if ($result.Success) {
        Write-Host 'McAfee removal tool completed successfully. A system restart is recommended.' -ForegroundColor Green
        exit 0
    }

    Write-Host "MCPR was not reported successful. Status: $($result.ExecutionStatus); verification: $($result.VerificationStatus); reason: $($result.FailureReason)." -ForegroundColor Red
    if ($null -ne $result.ExitCode) {
        Write-Host "  MCPR child exit code: $($result.ExitCode)" -ForegroundColor Yellow
    }

    $scriptExitCode = if ($null -ne $result.ExitCode -and [int]$result.ExitCode -ne 0) {
        [int]$result.ExitCode
    }
    else {
        1
    }
    exit $scriptExitCode
}
catch {
    Write-Host "McAfee uninstaller failed closed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
