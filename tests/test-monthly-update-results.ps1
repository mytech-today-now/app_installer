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
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [switch]$MarkMutationOnSuccess
    )

    $scenarioRoot = Join-Path $testRoot $ScenarioName
    $fakeBin = Join-Path $scenarioRoot 'bin'
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    $tracePath = Join-Path $scenarioRoot 'fake-winget-trace.txt'
    $logPath = Join-Path $scenarioRoot 'fake-update-log.txt'
    $scenarioUpdaterPath = Join-Path $scenarioRoot 'winget-update.ps1'
    $wingetPath = Join-Path $fakeBin 'winget.cmd'

    $catalogPath = Join-Path $testRoot 'apps-manifest.json'
    $modulesPath = Join-Path $testRoot 'modules'
    if (-not [System.IO.File]::Exists($catalogPath)) {
        New-Item -ItemType Directory -Path $modulesPath -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'apps-manifest.json') -Destination $catalogPath -Force
        Copy-Item -LiteralPath (Join-Path (Join-Path $repositoryRoot 'modules') 'AppInstallerCore.psm1') -Destination (Join-Path $modulesPath 'AppInstallerCore.psm1') -Force
        Copy-Item -LiteralPath (Join-Path (Join-Path $repositoryRoot 'modules') 'PackageCommand.psm1') -Destination (Join-Path $modulesPath 'PackageCommand.psm1') -Force
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        foreach ($fixtureId in @('Test.Package', 'Test.Good', 'Test.Failed')) {
            $fixtureName = $fixtureId.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
            $catalog.apps += [PSCustomObject]@{
                name = $fixtureName
                displayName = $fixtureId
                description = 'Offline monthly update fixture.'
                category = 'Testing'
                platform = 'Windows'
                packages = [PSCustomObject]@{ winget = $fixtureId; wingetSource = 'winget' }
            }
        }
        [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 20), $utf8)
    }

    $cmdLines = @(
        '@echo off',
        ('>>"{0}" echo invoked' -f $tracePath),
        ('>>"{0}" echo %*' -f $tracePath)
    )
    if ($ScenarioName -eq 'partial-update') {
        $cmdLines += @(
            'if /I "%3"=="Test.Good" goto UpdateGood',
            'if /I "%3"=="Test.Failed" goto UpdateFailed',
            'exit /b 88',
            ':UpdateGood',
            'echo Found Good Package [Test.Good] Version 2.0',
            'echo Starting package install...',
            'echo Successfully installed',
            'exit /b 0',
            ':UpdateFailed',
            'echo Found Failed Package [Test.Failed] Version 2.0',
            'echo Starting package install...',
            'echo Installer failed with exit code: 23',
            'exit /b 23'
        )
    }
    else {
        foreach ($line in $OutputLines) {
            $cmdLines += ('echo {0}' -f $line)
        }
        if ($MarkMutationOnSuccess -and $ExitCode -eq 0) {
            # A trace-only marker stands in for fake package state; it does not
            # install or alter anything on the test host.
            $cmdLines += ('>>"{0}" echo FAKE_PACKAGE_MUTATION' -f $tracePath)
        }
        $cmdLines += ('exit /b {0}' -f $ExitCode)
    }
    [System.IO.File]::WriteAllLines($wingetPath, [string[]]$cmdLines, [System.Text.Encoding]::ASCII)

    $injectedFunctions = @'
function Clear-Host { }
function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
}
function Test-Path {
    param([string]$Path, [string]$LiteralPath, [string]$PathType)
    $candidate = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } else { $Path }
    return ($candidate -eq 'C:\mytech.today\logs') -or [System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate)
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

    # Synthetic fake success is not evidence of a real user's agreement.
    $successScenario = New-FakeWinget -ScenarioName 'fake-agreement-accepted' -MarkMutationOnSuccess -OutputLines @(
        'FAKE_WINGET_REVIEW_ACCEPTED_BY_TEST_DOUBLE',
        'Found Test Package [Test.Package] Version 2.0',
        'Starting package install...',
        'Successfully installed'
    ) -ExitCode 0
    $success = Invoke-FakeUpdater -Scenario $successScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $success -Category 'COMPLETED' -LogLevel 'SUCCESS' -ExpectedExitCode 0 -ScenarioName 'Successful update'
    Assert-Condition -Condition ($success.Output.Contains('Your applications have been updated.')) -Message 'Successful update retains the success message'
    Assert-Condition -Condition ($success.Trace -match '(?m)^invoked\s*$') -Message 'Successful update invoked only the fake winget executable'
    Assert-Condition -Condition ($success.Trace -match '(?m)^upgrade --id Test\.Package --exact --source winget --disable-interactivity\s*$') -Message 'Scoped update uses exact catalog identity and disables agreement prompts without accepting terms'
    Assert-Condition -Condition ($success.Trace -match '(?m)^FAKE_PACKAGE_MUTATION\s*$') -Message 'Only the fake success fixture writes its test-only mutation marker'
    Assert-Condition -Condition ($success.Trace -notmatch '--accept-source-agreements|--accept-package-agreements') -Message 'Fake success fixture receives no agreement acceptance switches'

    $packageAgreementScenario = New-FakeWinget -ScenarioName 'new-package-agreement' -OutputLines @('FAKE_PACKAGE_TERMS_DO_NOT_LOG') -ExitCode -1978335206
    $packageAgreement = Invoke-FakeUpdater -Scenario $packageAgreementScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $packageAgreement -Category 'FAILED' -LogLevel 'ERROR' -ExpectedExitCode -1978335206 -ScenarioName 'New package agreement requirement'
    Assert-Condition -Condition ($packageAgreement.Trace -match '(?m)^upgrade --id Test\.Package --exact --source winget --disable-interactivity\s*$' -and $packageAgreement.Trace -notmatch 'FAKE_PACKAGE_MUTATION|--accept-(source|package)-agreements') -Message 'Package agreement requirement fails closed without a fake mutation or acceptance switch'
    Assert-Condition -Condition (@([regex]::Matches($packageAgreement.Trace, '(?m)^invoked\s*$')).Count -eq 1) -Message 'Package agreement requirement is not retried automatically'
    Assert-Condition -Condition ($packageAgreement.Log -notmatch 'FAKE_PACKAGE_TERMS_DO_NOT_LOG') -Message 'Package agreement text is excluded from the scheduled update log'

    $sourceAgreementScenario = New-FakeWinget -ScenarioName 'new-source-agreement' -OutputLines @('FAKE_SOURCE_TERMS_DO_NOT_LOG') -ExitCode -1978335207
    $sourceAgreement = Invoke-FakeUpdater -Scenario $sourceAgreementScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $sourceAgreement -Category 'FAILED' -LogLevel 'ERROR' -ExpectedExitCode -1978335207 -ScenarioName 'New source agreement requirement'
    Assert-Condition -Condition ($sourceAgreement.Trace -notmatch 'FAKE_PACKAGE_MUTATION|--accept-(source|package)-agreements') -Message 'Source agreement requirement fails closed without a fake mutation or acceptance switch'
    Assert-Condition -Condition ($sourceAgreement.Log -notmatch 'FAKE_SOURCE_TERMS_DO_NOT_LOG') -Message 'Source agreement text is excluded from the scheduled update log'

    $declinedAgreementScenario = New-FakeWinget -ScenarioName 'declined-package-agreement' -OutputLines @('FAKE_USER_DECLINED_PACKAGE_TERMS_DO_NOT_LOG') -ExitCode -1978335206
    $declinedAgreement = Invoke-FakeUpdater -Scenario $declinedAgreementScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $declinedAgreement -Category 'FAILED' -LogLevel 'ERROR' -ExpectedExitCode -1978335206 -ScenarioName 'Declined package agreement'
    Assert-Condition -Condition ($declinedAgreement.Trace -notmatch 'FAKE_PACKAGE_MUTATION|--accept-(source|package)-agreements' -and @([regex]::Matches($declinedAgreement.Trace, '(?m)^invoked\s*$')).Count -eq 1) -Message 'A declined agreement causes no fake mutation, acceptance, or retry'
    Assert-Condition -Condition ($declinedAgreement.Log -notmatch 'FAKE_USER_DECLINED_PACKAGE_TERMS_DO_NOT_LOG') -Message 'Declined agreement text is excluded from the scheduled update log'

    $unscoped = Invoke-FakeUpdater -Scenario (New-FakeWinget -ScenarioName 'unscoped-update' -OutputLines @() -ExitCode 0)
    Assert-Condition -Condition ($unscoped.ExitCode -eq 2 -and $unscoped.Output -match 'explicit catalog-backed package scope is required') -Message 'Updater rejects an unscoped all-package action'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace($unscoped.Trace)) -Message 'Unscoped updater does not invoke the fake WinGet process'

    $noUpdatesScenario = New-FakeWinget -ScenarioName 'no-updates' -OutputLines @('No applicable upgrade found.') -ExitCode 0
    $noUpdates = Invoke-FakeUpdater -Scenario $noUpdatesScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $noUpdates -Category 'COMPLETED' -LogLevel 'SUCCESS' -ExpectedExitCode 0 -ScenarioName 'No available updates'
    Assert-Condition -Condition ($noUpdates.Output.Contains('No application updates were available.') -and -not $noUpdates.Output.Contains('Your applications have been updated.')) -Message 'No-update success does not claim an application changed'

    $failureScenario = New-FakeWinget -ScenarioName 'failed-before-change' -OutputLines @('Failed to open one or more sources.') -ExitCode 23
    $failure = Invoke-FakeUpdater -Scenario $failureScenario -PackageIds 'Test.Package'
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
    $partial = Invoke-FakeUpdater -Scenario $partialScenario -PackageIds 'Test.Good,Test.Failed'
    Assert-ScenarioResult -Result $partial -Category 'PARTIALLY COMPLETED' -LogLevel 'WARNING' -ExpectedExitCode 23 -ScenarioName 'Partial update'
    Assert-Condition -Condition ($partial.Output -match 'attempted=2, succeeded=1, failed=1, unknown=0') -Message 'Partial update reports package counts separately'
    Assert-Condition -Condition ($partial.Output -notmatch 'Your applications have been updated\.') -Message 'Partial update does not claim all applications were updated'
    Assert-Condition -Condition ($partial.Log -match 'Package result: Test\.Good = Succeeded' -and $partial.Log -match 'Package result: Test\.Failed = Failed') -Message 'Partial update log contains per-package results'

    $taskActionScenario = New-FakeWinget -ScenarioName 'scheduled-action-failure' -OutputLines @('Failed to open one or more sources.') -ExitCode 23
    $taskAction = Invoke-FakeUpdater -Scenario $taskActionScenario -PackageIds 'Google.Chrome'
    Assert-Condition -Condition ($taskAction.ExitCode -eq 23 -and $taskAction.Output -match '\[FAILED\] Update outcome:' -and $taskAction.Output -match 'winget-exit-code=23' -and $taskAction.Output.Contains($script:incompleteMessage)) -Message 'Scheduled task action receives the failed result and native exit code'
    Assert-Condition -Condition ($taskAction.Trace -match '(?m)^upgrade --id Google\.Chrome --exact --source winget --disable-interactivity\s*$') -Message 'Scheduled task action uses its selected catalog scope without accepting terms'

    $malformedScenario = New-FakeWinget -ScenarioName 'malformed-output' -OutputLines @('unstructured fake winget response') -ExitCode 0
    $malformed = Invoke-FakeUpdater -Scenario $malformedScenario -PackageIds 'Test.Package'
    Assert-ScenarioResult -Result $malformed -Category 'UNKNOWN' -LogLevel 'ERROR' -ExpectedExitCode 1 -ScenarioName 'Malformed output'
    Assert-Condition -Condition (-not $malformed.Output.Contains('Your applications have been updated.')) -Message 'Malformed output never prints the all-updated statement'

    $logFailureScenario = New-FakeWinget -ScenarioName 'log-write-failure' -OutputLines @(
        'Found Test Package [Test.Package] Version 2.0',
        'Starting package install...',
        'Successfully installed'
    ) -ExitCode 0
    $logFailure = Invoke-FakeUpdater -Scenario $logFailureScenario -FailLogWrites -PackageIds 'Test.Package'
    Assert-Condition -Condition ($logFailure.ExitCode -ne 0 -and $logFailure.Output.Contains($script:incompleteMessage)) -Message 'Log write failure returns nonzero with the incomplete-status fallback'
    Assert-Condition -Condition ($logFailure.Output -match '\[UNKNOWN\] Update outcome:' -and -not $logFailure.Output.Contains('Your applications have been updated.')) -Message 'Log write failure does not report successful completion'

    $missingScenario = New-FakeWinget -ScenarioName 'missing-winget' -OutputLines @() -ExitCode 0
    $missing = Invoke-FakeUpdater -Scenario $missingScenario -MissingWinget -PackageIds 'Test.Package'
    Assert-Condition -Condition ($missing.ExitCode -ne 0 -and $missing.Output.Contains($script:incompleteMessage)) -Message 'Missing winget returns nonzero with the incomplete-status fallback'
    Assert-Condition -Condition (-not $missing.Output.Contains('Your applications have been updated.') -and [string]::IsNullOrWhiteSpace($missing.Trace)) -Message 'Missing winget does not report success or invoke a package manager'

    $ambiguousCatalog = Get-Content -LiteralPath (Join-Path $testRoot 'apps-manifest.json') -Raw | ConvertFrom-Json
    $ambiguousCatalog.apps += [PSCustomObject]@{
        name = 'conflicting-test-package'
        displayName = 'Conflicting Test Package'
        description = 'Conflicting source fixture.'
        category = 'Testing'
        platform = 'Windows'
        packages = [PSCustomObject]@{ winget = 'Test.Package'; wingetSource = 'msstore' }
    }
    [System.IO.File]::WriteAllText((Join-Path $testRoot 'apps-manifest.json'), ($ambiguousCatalog | ConvertTo-Json -Depth 20), $utf8)
    $ambiguousScenario = New-FakeWinget -ScenarioName 'ambiguous-scope' -OutputLines @('fake output must not be reached') -ExitCode 0
    $ambiguous = Invoke-FakeUpdater -Scenario $ambiguousScenario -PackageIds 'Google.Chrome,Test.Package'
    Assert-Condition -Condition ($ambiguous.ExitCode -eq 2 -and $ambiguous.Output -match 'missing, invalid, or conflicting catalog source metadata') -Message 'Ambiguous source metadata fails before a scoped update starts'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace($ambiguous.Trace)) -Message 'A later ambiguous package prevents earlier valid package IDs from launching'

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
