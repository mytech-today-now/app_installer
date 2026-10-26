# Offline end-to-end regression coverage for winget update result reporting.
# Each child process can resolve only a fake winget.cmd; no real package source is contacted.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] Fake winget command tests require Windows command resolution.' -ForegroundColor Yellow
    exit 77
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-update-results-' + [guid]::NewGuid().ToString('N'))))
$updaterPath = Join-Path $repositoryRoot 'apps\winget-update.ps1'
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$checkCount = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $testRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary test directory is outside the system temporary directory.'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    $script:checkCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-FakeWinget {
    param(
        [Parameter(Mandatory = $true)][string]$ScenarioName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OutputLines,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    $scenarioRoot = Join-Path $testRoot $ScenarioName
    $fakeBin = Join-Path $scenarioRoot 'bin'
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    $tracePath = Join-Path $scenarioRoot 'fake-winget-trace.txt'
    $logPath = Join-Path $scenarioRoot 'fake-update-log.txt'
    $scenarioUpdaterPath = Join-Path $scenarioRoot 'winget-update.ps1'
    $wingetPath = Join-Path $fakeBin 'winget.cmd'

    $cmdLines = @(
        '@echo off',
        ('>>"{0}" echo invoked' -f $tracePath),
        ('>>"{0}" echo %*' -f $tracePath)
    )
    foreach ($line in $OutputLines) {
        $cmdLines += ('echo {0}' -f $line)
    }
    $cmdLines += ('exit /b {0}' -f $ExitCode)
    [System.IO.File]::WriteAllLines($wingetPath, [string[]]$cmdLines, [System.Text.Encoding]::ASCII)

    $injectedFunctions = @'
function Clear-Host { }
function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
}
function Test-Path {
    param([string]$Path)
    return ($Path -eq 'C:\mytech.today\logs')
}
function Add-Content {
    param([string]$Path, [string]$Value, [string]$ErrorAction)
    if ($env:FAIL_LOG_WRITES -eq '1') {
        throw 'Injected log write failure.'
    }
    [System.IO.File]::AppendAllText($env:FAKE_UPDATE_LOG, $Value + [Environment]::NewLine)
}
function Get-Command {
    param([string]$Name, [string]$ErrorAction)
    if ($Name -ne 'winget' -or $env:FAKE_WINGET_MISSING -eq '1') {
        return $null
    }
    $fakePath = Join-Path $env:FAKE_WINGET_BIN 'winget.cmd'
    if (-not [System.IO.File]::Exists($fakePath)) {
        return $null
    }
    return [PSCustomObject]@{ Name = 'winget'; Source = $fakePath }
}
'@
    $sourceText = [System.IO.File]::ReadAllText($updaterPath)
    $platformMarker = '# Platform check - this application is Windows-only'
    if (-not $sourceText.Contains($platformMarker)) {
        throw 'Could not locate the updater injection marker.'
    }
    $sourceText = $sourceText.Replace($platformMarker, ($injectedFunctions + [Environment]::NewLine + $platformMarker))
    [System.IO.File]::WriteAllText($scenarioUpdaterPath, $sourceText, $utf8)

    [PSCustomObject]@{
        Name = $ScenarioName
        Root = $scenarioRoot
        FakeBin = $fakeBin
        TracePath = $tracePath
        LogPath = $logPath
        UpdaterPath = $scenarioUpdaterPath
        WingetPath = $wingetPath
        ExitCode = $ExitCode
    }
}

function Invoke-FakeUpdater {
    param(
        [Parameter(Mandatory = $true)]$Scenario,
        [switch]$MissingWinget,
        [switch]$FailLogWrites,
        [string]$PackageIds = ''
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $pwshPath
    $startInfo.Arguments = '-NoProfile -File "{0}"' -f $Scenario.UpdaterPath
    if (-not [string]::IsNullOrWhiteSpace($PackageIds)) {
        $startInfo.Arguments += (' -PackageIds "{0}"' -f $PackageIds)
    }
    $startInfo.WorkingDirectory = $Scenario.Root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $environment = $startInfo.EnvironmentVariables
    $systemRoot = $environment['SystemRoot']
    $environment['PATH'] = if ($MissingWinget) { Join-Path $systemRoot 'System32' } else { $Scenario.FakeBin + ';' + (Join-Path $systemRoot 'System32') }
    $environment['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'
    $environment['FAKE_WINGET_BIN'] = $Scenario.FakeBin
    $environment['FAKE_WINGET_TRACE'] = $Scenario.TracePath
    $environment['FAKE_UPDATE_LOG'] = $Scenario.LogPath
    $environment['FAIL_LOG_WRITES'] = if ($FailLogWrites) { '1' } else { '0' }
    $environment['FAKE_WINGET_MISSING'] = if ($MissingWinget) { '1' } else { '0' }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start the fake updater process for scenario $($Scenario.Name)."
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        throw "Fake updater timed out for scenario $($Scenario.Name)."
    }
    $process.WaitForExit()

    [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output = $stdoutTask.GetAwaiter().GetResult()
        Error = $stderrTask.GetAwaiter().GetResult()
        Log = if (Test-Path -LiteralPath $Scenario.LogPath -PathType Leaf) { Get-Content -LiteralPath $Scenario.LogPath -Raw } else { '' }
        Trace = if (Test-Path -LiteralPath $Scenario.TracePath -PathType Leaf) { Get-Content -LiteralPath $Scenario.TracePath -Raw } else { '' }
    }
}

function Assert-ScenarioResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$LogLevel,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][string]$ScenarioName
    )

    Assert-Condition -Condition ($Result.ExitCode -eq $ExpectedExitCode) -Message "$ScenarioName process exit code is $ExpectedExitCode (observed $($Result.ExitCode))"
    Assert-Condition -Condition ($Result.Output -match ("\[{0}\] Update outcome:" -f [regex]::Escape($Category))) -Message "$ScenarioName displays the $Category result category"
    $logCategory = $Category.Replace(' ', '')
    Assert-Condition -Condition ($Result.Log -match ("\] \[{0}\] Update result: {1};" -f $LogLevel, [regex]::Escape($logCategory))) -Message "$ScenarioName log level and category are $LogLevel/$logCategory"
    Assert-Condition -Condition ($Result.Output.Contains($script:incompleteMessage) -or $Category -eq 'COMPLETED') -Message "$ScenarioName shows the incomplete-status fallback when the result is not complete"
}

$script:incompleteMessage = 'Update status is incomplete. Some applications may remain out of date. Review the log and run a manual update check.'
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    $successScenario = New-FakeWinget -ScenarioName 'success' -OutputLines @(
        'Found Test Package [Test.Package] Version 2.0',
        'Starting package install...',
        'Successfully installed'
    ) -ExitCode 0
    $success = Invoke-FakeUpdater -Scenario $successScenario
    Assert-ScenarioResult -Result $success -Category 'COMPLETED' -LogLevel 'SUCCESS' -ExpectedExitCode 0 -ScenarioName 'Successful update'
    Assert-Condition -Condition ($success.Output.Contains('Your applications have been updated.')) -Message 'Successful update retains the success message'
    Assert-Condition -Condition ($success.Trace -match '(?m)^invoked\s*$') -Message 'Successful update invoked only the fake winget executable'
    Assert-Condition -Condition ($success.Trace -match '(?m)^update --all --accept-source-agreements --accept-package-agreements\s*$') -Message 'Manual update keeps the documented update alias and agreement flags'

    $noUpdatesScenario = New-FakeWinget -ScenarioName 'no-updates' -OutputLines @('No applicable upgrade found.') -ExitCode 0
    $noUpdates = Invoke-FakeUpdater -Scenario $noUpdatesScenario
    Assert-ScenarioResult -Result $noUpdates -Category 'COMPLETED' -LogLevel 'SUCCESS' -ExpectedExitCode 0 -ScenarioName 'No available updates'
    Assert-Condition -Condition ($noUpdates.Output.Contains('No application updates were available.') -and -not $noUpdates.Output.Contains('Your applications have been updated.')) -Message 'No-update success does not claim an application changed'

    $failureScenario = New-FakeWinget -ScenarioName 'failed-before-change' -OutputLines @('Failed to open one or more sources.') -ExitCode 23
    $failure = Invoke-FakeUpdater -Scenario $failureScenario
    Assert-ScenarioResult -Result $failure -Category 'FAILED' -LogLevel 'ERROR' -ExpectedExitCode 23 -ScenarioName 'Failure before package changes'
    Assert-Condition -Condition (-not $failure.Output.Contains('Your applications have been updated.')) -Message 'Failed command never prints the all-updated statement'
    Assert-Condition -Condition ($failure.Log -match 'winget-exit-code=23') -Message 'Failed command log preserves the winget exit code'

    $partialScenario = New-FakeWinget -ScenarioName 'partial-update' -OutputLines @(
        'Found Good Package [Test.Good] Version 2.0',
        'Starting package install...',
        'Successfully installed',
        'Found Failed Package [Test.Failed] Version 2.0',
        'Starting package install...',
        'Installer failed with exit code: 23'
    ) -ExitCode 23
    $partial = Invoke-FakeUpdater -Scenario $partialScenario
    Assert-ScenarioResult -Result $partial -Category 'PARTIALLY COMPLETED' -LogLevel 'WARNING' -ExpectedExitCode 23 -ScenarioName 'Partial update'
    Assert-Condition -Condition ($partial.Output -match 'attempted=2, succeeded=1, failed=1, unknown=0') -Message 'Partial update reports package counts separately'
    Assert-Condition -Condition ($partial.Output -notmatch 'Your applications have been updated\.') -Message 'Partial update does not claim all applications were updated'
    Assert-Condition -Condition ($partial.Log -match 'Package result: Test\.Good = Succeeded' -and $partial.Log -match 'Package result: Test\.Failed = Failed') -Message 'Partial update log contains per-package results'

    $taskActionScenario = New-FakeWinget -ScenarioName 'scheduled-action-failure' -OutputLines @('Failed to open one or more sources.') -ExitCode 23
    $taskAction = Invoke-FakeUpdater -Scenario $taskActionScenario -PackageIds 'Google.Chrome'
    Assert-Condition -Condition ($taskAction.ExitCode -eq 23 -and $taskAction.Output -match '\[FAILED\] Update outcome:' -and $taskAction.Output -match 'winget-exit-code=23' -and $taskAction.Output.Contains($script:incompleteMessage)) -Message 'Scheduled task action receives the failed result and native exit code'
    Assert-Condition -Condition ($taskAction.Trace -match '(?m)^update --id Google\.Chrome --exact --accept-source-agreements --accept-package-agreements\s*$') -Message 'Scheduled task action uses its selected package scope with the fake winget command'

    $malformedScenario = New-FakeWinget -ScenarioName 'malformed-output' -OutputLines @('unstructured fake winget response') -ExitCode 0
    $malformed = Invoke-FakeUpdater -Scenario $malformedScenario
    Assert-ScenarioResult -Result $malformed -Category 'UNKNOWN' -LogLevel 'ERROR' -ExpectedExitCode 1 -ScenarioName 'Malformed output'
    Assert-Condition -Condition (-not $malformed.Output.Contains('Your applications have been updated.')) -Message 'Malformed output never prints the all-updated statement'

    $logFailureScenario = New-FakeWinget -ScenarioName 'log-write-failure' -OutputLines @(
        'Found Test Package [Test.Package] Version 2.0',
        'Starting package install...',
        'Successfully installed'
    ) -ExitCode 0
    $logFailure = Invoke-FakeUpdater -Scenario $logFailureScenario -FailLogWrites
    Assert-Condition -Condition ($logFailure.ExitCode -ne 0 -and $logFailure.Output.Contains($script:incompleteMessage)) -Message 'Log write failure returns nonzero with the incomplete-status fallback'
    Assert-Condition -Condition ($logFailure.Output -match '\[UNKNOWN\] Update outcome:' -and -not $logFailure.Output.Contains('Your applications have been updated.')) -Message 'Log write failure does not report successful completion'

    $missingScenario = New-FakeWinget -ScenarioName 'missing-winget' -OutputLines @() -ExitCode 0
    $missing = Invoke-FakeUpdater -Scenario $missingScenario -MissingWinget
    Assert-Condition -Condition ($missing.ExitCode -ne 0 -and $missing.Output.Contains($script:incompleteMessage)) -Message 'Missing winget returns nonzero with the incomplete-status fallback'
    Assert-Condition -Condition (-not $missing.Output.Contains('Your applications have been updated.') -and [string]::IsNullOrWhiteSpace($missing.Trace)) -Message 'Missing winget does not report success or invoke a package manager'

    Write-Host "`n[OK] Fake winget result regression checks passed ($checkCount assertions)." -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $tempPrefix = $tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedTestRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
