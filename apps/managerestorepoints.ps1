<#
.SYNOPSIS
    Installs and runs the verified Manage Restore Points helper.

.DESCRIPTION
    The remote helper is unavailable until an immutable release URL and an
    independently reviewed SHA-256 digest are configured. Every invocation
    verifies the downloaded bytes before execution.

.NOTES
    File Name      : managerestorepoints.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

[CmdletBinding()]
param(
    [ValidateSet('List', 'Configure', 'Create', 'Monitor')]
    [string]$Action = 'Configure',

    [string]$ConfigPath,

    [AllowEmptyString()]
    [string]$Description
)

if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host '[INFO] Manage Restore Points is only available for Windows.' -ForegroundColor Yellow
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
    $release = Get-RemotePowerShellHelperRelease -HelperId RestorePoints
    $installPath = 'C:\myTech.Today\ManageRestorePoints'
    $logsPath = 'C:\myTech.Today\logs'
    $scriptPath = Join-Path $installPath 'Manage-RestorePoints.ps1'
    $configPath = if ($PSBoundParameters.ContainsKey('ConfigPath') -and $ConfigPath) {
        $ConfigPath
    }
    else {
        Join-Path $installPath 'ManageRestorePoints.json'
    }
    $moduleInstallPath = Join-Path $installPath 'modules\RemotePowerShellTrust.psm1'
    $sourceWrapperPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $sourceModulePath = [System.IO.Path]::GetFullPath($trustModulePath[0])
    $actionWasSpecified = $PSBoundParameters.ContainsKey('Action')
    $descriptionWasSpecified = $PSBoundParameters.ContainsKey('Description')
    $scriptArguments = @('-Action', $Action)
    if ($PSBoundParameters.ContainsKey('ConfigPath') -and $ConfigPath) {
        $scriptArguments += @('-ConfigPath', $ConfigPath)
    }
    elseif (-not $actionWasSpecified) {
        $scriptArguments += @('-ConfigPath', $configPath)
    }
    if ($descriptionWasSpecified) {
        $scriptArguments += @('-Description', $Description)
    }

    $prepareInstall = {
        param($VerifiedScriptPath)

        if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
            New-Item -Path $installPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        if (-not (Test-Path -LiteralPath $logsPath -PathType Container)) {
            New-Item -Path $logsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
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

        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            $defaultConfig = @{
                RestorePoint = @{
                    DiskSpacePercent = 10
                    MinimumCount = 10
                    MaximumCount = 30
                    CreateOnSchedule = $true
                    ScheduleIntervalMinutes = 1440
                    CreationFrequencyMinutes = 120
                }
                Email = @{
                    Enabled = $false
                    SmtpServer = 'smtp.example.com'
                    SmtpPort = 587
                    UseSsl = $true
                    From = 'restorepoint@example.com'
                    To = @('admin@example.com')
                    Username = ''
                    PasswordEncrypted = ''
                }
                Logging = @{
                    LogPath = 'C:\myTech.Today\logs\ManageRestorePoints.md'
                    MaxLogSizeMB = 10
                    RetentionDays = 30
                }
            }

            $configDirectory = Split-Path -Parent $configPath
            if (-not (Test-Path -LiteralPath $configDirectory -PathType Container)) {
                New-Item -Path $configDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Force -ErrorAction Stop
            Write-Host '  [OK] Default configuration created' -ForegroundColor Green
        }

        try {
            $wshShell = New-Object -ComObject WScript.Shell
            try {
                $desktopPath = [Environment]::GetFolderPath('Desktop')
                $shortcutPath = Join-Path $desktopPath 'Manage Restore Points.lnk'
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = 'powershell.exe'
                $shortcut.Arguments = '-NoProfile -File "' + $scriptPath + '" -Action List'
                $shortcut.WorkingDirectory = $installPath
                $shortcut.Description = 'Manage Windows System Restore Points'
                $shortcut.IconLocation = 'imageres.dll,109'
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

        Write-Host "`n  Script Location: $scriptPath" -ForegroundColor Cyan
        Write-Host "  Config Location: $configPath" -ForegroundColor Cyan
        Write-Host '  Usage Examples:' -ForegroundColor Yellow
        Write-Host "    List restore points:    powershell.exe -NoProfile -File `"$scriptPath`" -Action List" -ForegroundColor Gray
        Write-Host "    Configure:              powershell.exe -NoProfile -File `"$scriptPath`" -Action Configure" -ForegroundColor Gray
        Write-Host "    Create restore point:   powershell.exe -NoProfile -File `"$scriptPath`" -Action Create -Description 'My Backup'" -ForegroundColor Gray
        Write-Host "    Monitor:                powershell.exe -NoProfile -File `"$scriptPath`" -Action Monitor" -ForegroundColor Gray
    }.GetNewClosure()

    Write-Host 'Installing Manage Restore Points script...' -ForegroundColor Cyan
    $result = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId RestorePoints `
        -Uri $release.Uri `
        -ExpectedSha256 $release.Sha256 `
        -ScriptArguments $scriptArguments `
        -BeforeExecuteScript $prepareInstall

    if ($result.Success) {
        if ($Action -eq 'Configure') {
            Write-Host '[OK] Initial configuration complete.' -ForegroundColor Green
        }
        else {
            Write-Host "[OK] Manage Restore Points action $Action completed." -ForegroundColor Green
        }
        exit 0
    }

    if ($result.FailureReason -eq 'release-not-configured') {
        Write-Host '[FAIL] Manage Restore Points has no reviewed immutable source and SHA-256 pin. No request, configuration, shortcut, or restore-point operation occurred.' -ForegroundColor Red
    }
    elseif ($result.VerificationStatus -ne 'verified') {
        Write-Host "[FAIL] The Manage Restore Points helper could not be verified ($($result.FailureReason)). No helper was executed or restore-point state changed." -ForegroundColor Red
    }
    elseif ($result.FailureReason -eq 'pre-execution-setup-failed') {
        Write-Host '[FAIL] Required local setup failed before the Manage Restore Points helper was launched.' -ForegroundColor Red
    }
    elseif ($result.FailureReason -eq 'cleanup-failed') {
        Write-Host '[FAIL] The Manage Restore Points temporary-file cleanup failed. Its result is not confirmed. Review current status before retrying.' -ForegroundColor Red
    }
    elseif ($null -ne $result.ExitCode) {
        Write-Host "[FAIL] Manage Restore Points returned exit code $($result.ExitCode). The restore-point result is not confirmed. Review current status before retrying." -ForegroundColor Red
    }
    else {
        Write-Host '[FAIL] The Manage Restore Points result is unknown. Review current status before retrying.' -ForegroundColor Red
    }

    if ($null -ne $result.ExitCode -and $result.ExitCode -ne 0) {
        exit $result.ExitCode
    }
    exit 1
}
catch {
    Write-Host '[FAIL] Manage Restore Points could not start safely. No success was reported.' -ForegroundColor Red
    exit 1
}
