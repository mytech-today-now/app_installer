<#
.SYNOPSIS
    Installs and runs the verified Hosts File Manager helper.

.DESCRIPTION
    The remote helper is unavailable until an immutable release URL and an
    independently reviewed SHA-256 digest are configured. Every invocation
    verifies the downloaded bytes before execution.

.NOTES
    File Name      : hosts.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$BackupOnly
)

if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host '[INFO] Hosts File Manager is only available for Windows.' -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'
$trustModuleCandidates = @(
    (Join-Path $PSScriptRoot 'modules\RemotePowerShellTrust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1')
)
$trustModulePath = @($trustModuleCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)

if ($trustModulePath.Count -eq 0) {
    Write-Host '[FAIL] The remote helper trust module is missing. No helper was requested or executed.' -ForegroundColor Red
    exit 1
}

try {
    Import-Module -Name $trustModulePath[0] -Force -ErrorAction Stop
    $release = Get-RemotePowerShellHelperRelease -HelperId Hosts
    $installPath = Join-Path $env:USERPROFILE 'myTech.Today\scripts'
    $scriptPath = Join-Path $installPath 'hosts.ps1'
    $moduleInstallPath = Join-Path $installPath 'modules\RemotePowerShellTrust.psm1'
    $sourceWrapperPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $sourceModulePath = [System.IO.Path]::GetFullPath($trustModulePath[0])
    $scriptArguments = @()
    if ($Force) { $scriptArguments += '-Force' }
    if ($BackupOnly) { $scriptArguments += '-BackupOnly' }

    $prepareInstall = {
        param($VerifiedScriptPath)

        if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
            New-Item -Path $installPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        if (-not [string]::Equals($sourceWrapperPath, [System.IO.Path]::GetFullPath($scriptPath), [System.StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $sourceWrapperPath -Destination $scriptPath -Force -ErrorAction Stop
        }

        $moduleDirectory = Split-Path -Parent $moduleInstallPath
        if (-not (Test-Path -LiteralPath $moduleDirectory -PathType Container)) {
            New-Item -Path $moduleDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        if (-not [string]::Equals($sourceModulePath, [System.IO.Path]::GetFullPath($moduleInstallPath), [System.StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $sourceModulePath -Destination $moduleInstallPath -Force -ErrorAction Stop
        }

        Write-Host "  [OK] Verified launcher saved to: $scriptPath" -ForegroundColor Green
        try {
            $wshShell = New-Object -ComObject WScript.Shell
            try {
                $desktopPath = [Environment]::GetFolderPath('Desktop')
                $shortcutPath = Join-Path $desktopPath 'Hosts File Manager.lnk'
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = 'powershell.exe'
                $shortcut.Arguments = '-NoProfile -File "' + $scriptPath + '"'
                $shortcut.WorkingDirectory = $installPath
                $shortcut.Description = 'Manage Windows hosts file with ad-blocking rules'
                $shortcut.IconLocation = 'shell32.dll,21'
                $shortcut.Save()
                Write-Host '  [OK] Desktop shortcut created' -ForegroundColor Green
            }
            finally {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshShell)
            }
        }
        catch {
            Write-Host "  [WARN] Could not create desktop shortcut: $_" -ForegroundColor Yellow
        }

        Write-Host "`n  Usage:" -ForegroundColor Cyan
        Write-Host '    - Double-click the desktop shortcut to update the hosts file' -ForegroundColor Gray
        Write-Host "    - Or run: powershell.exe -NoProfile -File `"$scriptPath`"" -ForegroundColor Gray
        Write-Host "    - Run with -Force: powershell.exe -NoProfile -File `"$scriptPath`" -Force" -ForegroundColor Gray
        Write-Host "    - Run with -BackupOnly: powershell.exe -NoProfile -File `"$scriptPath`" -BackupOnly" -ForegroundColor Gray
    }.GetNewClosure()

    Write-Host 'Installing Hosts File Manager...' -ForegroundColor Cyan
    $result = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $release.Uri `
        -ExpectedSha256 $release.Sha256 `
        -ScriptArguments $scriptArguments `
        -BeforeExecuteScript $prepareInstall

    if ($result.Success) {
        Write-Host '[OK] Hosts file update completed successfully.' -ForegroundColor Green
        exit 0
    }

    if ($result.FailureReason -eq 'release-not-configured') {
        Write-Host '[FAIL] The Hosts File Manager helper has no reviewed immutable source and SHA-256 pin. No request or helper execution occurred.' -ForegroundColor Red
    }
    elseif ($result.VerificationStatus -ne 'verified') {
        Write-Host "[FAIL] The Hosts File Manager helper could not be verified ($($result.FailureReason)). No helper was executed." -ForegroundColor Red
    }
    elseif ($result.FailureReason -eq 'pre-execution-setup-failed') {
        Write-Host '[FAIL] Required local setup failed before the Hosts File Manager was launched.' -ForegroundColor Red
    }
    elseif ($result.FailureReason -eq 'cleanup-failed') {
        Write-Host '[FAIL] The Hosts File Manager temporary-file cleanup failed. Its result is not confirmed. Inspect the hosts file before retrying.' -ForegroundColor Red
    }
    elseif ($null -ne $result.ExitCode) {
        Write-Host "[FAIL] The Hosts File Manager returned exit code $($result.ExitCode). The hosts-file result is not confirmed. Inspect the hosts file before retrying." -ForegroundColor Red
    }
    else {
        Write-Host '[FAIL] The Hosts File Manager result is unknown. Inspect the hosts file before retrying.' -ForegroundColor Red
    }

    if ($null -ne $result.ExitCode -and $result.ExitCode -ne 0) {
        exit $result.ExitCode
    }
    exit 1
}
catch {
    Write-Host '[FAIL] The Hosts File Manager could not start safely. No success was reported.' -ForegroundColor Red
    exit 1
}
