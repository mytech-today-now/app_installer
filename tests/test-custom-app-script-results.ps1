# Offline result-contract tests for custom app scripts.
# Every native executable used here is a temporary fake; no package manager is invoked.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\AppInstallerCore.psm1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-script-results-' + [guid]::NewGuid().ToString('N'))))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:assertionCount = 0
$script:originalLastExitCode = $global:LASTEXITCODE
$script:unrelatedAppState = [ordered]@{
    Installed = @{ 'Unrelated app' = '2.4.1' }
    Queue = @('First app', 'Second app')
}
$beforeUnrelatedAppState = ConvertTo-Json -InputObject $script:unrelatedAppState -Depth 5 -Compress
$argumentCapturePath = Join-Path $testRoot 'captured-app-arguments.json'
$nativeTracePath = Join-Path $testRoot 'fake-native-trace.txt'
$fakeNativePath = Join-Path $testRoot 'fake-native.cmd'
$browserTracePath = Join-Path $testRoot 'fake-browser-trace.txt'
$oldArgumentCapture = $env:APP_SCRIPT_TEST_ARGUMENT_CAPTURE
$oldNativePath = $env:APP_SCRIPT_TEST_NATIVE_PATH
$oldNativeCode = $env:APP_SCRIPT_TEST_NATIVE_CODE
$oldNativeTrace = $env:APP_SCRIPT_TEST_NATIVE_TRACE
$oldBrowserTrace = $env:APP_SCRIPT_TEST_START_PROCESS_TRACE

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
    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-FunctionDefinitionText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "Cannot inspect $Name because $(Split-Path $Path -Leaf) has a parse error."
    }

    $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
        }, $true)
    if (-not $functionAst) {
        throw "Function $Name was not found in $(Split-Path $Path -Leaf)."
    }

    return $functionAst.Extent.Text
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    $purePowerShellPath = Join-Path $testRoot 'pure-powershell.ps1'
    Write-Fixture -Path $purePowerShellPath -Content @'
param([string]$MarkerPath)
[System.IO.File]::WriteAllText($MarkerPath, 'pure PowerShell ran')
exit 0
'@

    $nativeFixturePath = Join-Path $testRoot 'native-child.ps1'
    Write-Fixture -Path $nativeFixturePath -Content @'
& $env:APP_SCRIPT_TEST_NATIVE_PATH
$nativeExitCode = $LASTEXITCODE
exit $nativeExitCode
'@

    $argumentFixturePath = Join-Path $testRoot 'arguments.ps1'
    Write-Fixture -Path $argumentFixturePath -Content @'
param(
    [string]$First,
    [string]$Second,
    [string]$Third
)
$captured = @($First, $Second, $Third)
[System.IO.File]::WriteAllLines($env:APP_SCRIPT_TEST_ARGUMENT_CAPTURE, [string[]]$captured, (New-Object System.Text.UTF8Encoding($false)))
exit 0
'@

    $exceptionFixturePath = Join-Path $testRoot 'throws.ps1'
    Write-Fixture -Path $exceptionFixturePath -Content @'
throw 'injected fixture failure'
'@

    $specialExitFixturePath = Join-Path $testRoot 'already-installed.ps1'
    Write-Fixture -Path $specialExitFixturePath -Content @'
exit -1978335191
'@

    $unknownFixturePath = Join-Path $testRoot 'no-result.ps1'
    Write-Fixture -Path $unknownFixturePath -Content @'
Write-Output 'This script declares no result.'
'@

    $conditionalUnknownFixturePath = Join-Path $testRoot 'conditional-no-result.ps1'
    Write-Fixture -Path $conditionalUnknownFixturePath -Content @'
if ($false) {
    exit 23
}
Write-Output 'This execution path declares no result.'
'@

    $outcomeFixturePaths = @{}
    foreach ($outcomeStatus in @('Installed', 'Failure', 'Unknown', 'ManualActionRequired')) {
        $outcomeFixturePath = Join-Path $testRoot ("outcome-$outcomeStatus.ps1")
        $outcomeMessage = "Injected $outcomeStatus outcome."
        Write-Fixture -Path $outcomeFixturePath -Content @"
`$global:AppInstallerScriptOutcome = [PSCustomObject]@{
    Status = '$outcomeStatus'
    Message = '$outcomeMessage'
}
"@
        $outcomeFixturePaths[$outcomeStatus] = $outcomeFixturePath
    }

    [System.IO.File]::WriteAllLines($fakeNativePath, [string[]]@(
        '@echo off',
        '>>"%APP_SCRIPT_TEST_NATIVE_TRACE%" echo invoked',
        'exit /b %APP_SCRIPT_TEST_NATIVE_CODE%'
    ), [System.Text.Encoding]::ASCII)
    $env:APP_SCRIPT_TEST_NATIVE_PATH = $fakeNativePath
    $env:APP_SCRIPT_TEST_NATIVE_TRACE = $nativeTracePath

    foreach ($staleExitCode in @(23, 0)) {
        $markerPath = Join-Path $testRoot ('pure-marker-' + $staleExitCode + '.txt')
        $global:LASTEXITCODE = $staleExitCode
        $result = Invoke-AppScript -ScriptPath $purePowerShellPath -ScriptArguments @($markerPath)
        Assert-Condition ($result.Status -eq 'PowerShellSuccess') "pure PowerShell result ignores stale LASTEXITCODE $staleExitCode"
        Assert-Condition ($result.ExitCode -eq 0) "pure PowerShell reports its declared exit code after stale value $staleExitCode"
        Assert-Condition ($global:LASTEXITCODE -eq $staleExitCode) "caller LASTEXITCODE remains unchanged after stale value $staleExitCode"
        Assert-Condition (Test-Path -LiteralPath $markerPath -PathType Leaf) "pure PowerShell fixture ran for stale value $staleExitCode"
    }

    $env:APP_SCRIPT_TEST_ARGUMENT_CAPTURE = $argumentCapturePath
    $expectedArguments = @('value with spaces', 'a"quoted"value', 'C:\path with space\')
    $argumentResult = Invoke-AppScript -ScriptPath $argumentFixturePath -ScriptArguments $expectedArguments
    $capturedArguments = @(Get-Content -LiteralPath $argumentCapturePath)
    Assert-Condition ($argumentResult.Status -eq 'PowerShellSuccess') 'argument fixture reports declared PowerShell success'
    Assert-Condition ($capturedArguments.Count -eq $expectedArguments.Count) 'custom app script receives the exact argument count'
    for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
        Assert-Condition ($capturedArguments[$index] -ceq $expectedArguments[$index]) "custom app script argument $index is forwarded exactly"
    }

    foreach ($nativeExitCode in @(0, 23)) {
        $env:APP_SCRIPT_TEST_NATIVE_CODE = [string]$nativeExitCode
        $nativeResult = Invoke-AppScript -ScriptPath $nativeFixturePath
        Assert-Condition ($nativeResult.ExitCode -eq $nativeExitCode) "native child exit code $nativeExitCode is propagated exactly"
        if ($nativeExitCode -eq 0) {
            Assert-Condition ($nativeResult.Status -eq 'NativeProcessSuccess') 'native child exit zero maps to NativeProcessSuccess'
        }
        else {
            Assert-Condition ($nativeResult.Status -eq 'Failure') 'native child nonzero exit maps to Failure'
        }
    }
    $nativeTrace = @(Get-Content -LiteralPath $nativeTracePath)
    Assert-Condition ($nativeTrace.Count -eq 2) 'both fake native child scenarios executed'

    $exceptionResult = Invoke-AppScript -ScriptPath $exceptionFixturePath
    Assert-Condition ($exceptionResult.Status -eq 'Failure') 'thrown PowerShell exception is a failure'
    Assert-Condition ($exceptionResult.ExitCode -ne 0) 'thrown PowerShell exception retains its process exit code'

    $specialExitResult = Invoke-AppScript -ScriptPath $specialExitFixturePath
    Assert-Condition ($specialExitResult.ExitCode -eq -1978335191) 'already-installed sentinel exit code is preserved exactly'
    Assert-Condition ($specialExitResult.Status -eq 'Failure') 'already-installed sentinel remains available for the GUI compatibility rule'

    $unknownResult = Invoke-AppScript -ScriptPath $unknownFixturePath
    Assert-Condition ($unknownResult.Status -eq 'Unknown') 'clean script completion without a declared result is unknown'
    Assert-Condition ($null -eq $unknownResult.ExitCode) 'unknown script result has no inferred exit code'

    $conditionalUnknownResult = Invoke-AppScript -ScriptPath $conditionalUnknownFixturePath
    Assert-Condition ($conditionalUnknownResult.Status -eq 'Unknown') 'unexecuted exit branches do not turn a missing result into success'
    Assert-Condition ($null -eq $conditionalUnknownResult.ExitCode) 'conditional unknown result has no inferred exit code'

    $installedOutcomeResult = Invoke-AppScript -ScriptPath $outcomeFixturePaths['Installed']
    Assert-Condition ($installedOutcomeResult.Status -eq 'PowerShellSuccess' -and $installedOutcomeResult.ExitCode -eq 0) 'explicit Installed outcome preserves the existing PowerShell success status'

    $failureOutcomeResult = Invoke-AppScript -ScriptPath $outcomeFixturePaths['Failure']
    Assert-Condition ($failureOutcomeResult.Status -eq 'Failure' -and $failureOutcomeResult.ExitCode -eq 1) 'explicit Failure outcome remains a failure'

    $unknownOutcomeResult = Invoke-AppScript -ScriptPath $outcomeFixturePaths['Unknown']
    Assert-Condition ($unknownOutcomeResult.Status -eq 'Unknown' -and $null -eq $unknownOutcomeResult.ExitCode) 'explicit Unknown outcome remains unconfirmed'

    $manualOutcomeResult = Invoke-AppScript -ScriptPath $outcomeFixturePaths['ManualActionRequired']
    Assert-Condition ($manualOutcomeResult.Status -eq 'ManualActionRequired' -and $manualOutcomeResult.ExitCode -eq 0) 'explicit ManualActionRequired outcome stays distinct from installation success'
    Assert-Condition ($manualOutcomeResult.Message -eq 'Injected ManualActionRequired outcome.') 'explicit outcome message is preserved across the child-process boundary'

    $belarcScriptPath = Join-Path $repositoryRoot 'apps\belarc.ps1'
    $belarcResult = Invoke-AppScript -ScriptPath $belarcScriptPath
    Assert-Condition ($belarcResult.Status -eq 'Failure' -and $belarcResult.ExitCode -eq 1) 'Belarc with absent production pins returns a failed custom-app result'
    Assert-Condition ($belarcResult.ResultKind -eq 'NativeProcess') 'Belarc exposes its verified installer child result to the custom-app runner'

    $mcafeeCatalogEntries = @(Get-ApplicationRegistry | Where-Object { $_.ScriptName -ceq 'uninstall-mcafee.ps1' })
    Assert-Condition ($mcafeeCatalogEntries.Count -eq 1 -and $mcafeeCatalogEntries[0].Platform -ceq 'Windows' -and -not $mcafeeCatalogEntries[0].WingetId) 'The McAfee manifest entry maps to one Windows custom script without a package-manager fallback'
    $mcafeeScriptPath = Join-Path $repositoryRoot ('apps\' + $mcafeeCatalogEntries[0].ScriptName)
    $mcafeeResult = Invoke-AppScript -ScriptPath $mcafeeScriptPath
    Assert-Condition ($mcafeeResult.Status -eq 'Failure' -and $mcafeeResult.ExitCode -eq 1) 'McAfee with absent production identity pins maps to a failed custom-app result'
    Assert-Condition ($mcafeeResult.ResultKind -eq 'PowerShell') 'The blocked McAfee helper result is returned through the shared PowerShell app-script contract'

    $appsPath = Join-Path $testRoot 'apps'
    New-Item -ItemType Directory -Path $appsPath -Force | Out-Null
    $wrapperFixturePath = Join-Path $appsPath 'fixture.ps1'
    Write-Fixture -Path $wrapperFixturePath -Content @'
exit 0
'@
    $wrapperResult = Invoke-AppInstallation -AppScriptName 'fixture.ps1' -AppsPath $appsPath
    Assert-Condition ($wrapperResult.Status -eq 'PowerShellSuccess') 'Invoke-AppInstallation returns the shared explicit result contract'

    $browserApps = @(
        @{ Name = 'AceMoney Lite'; ScriptName = 'acemoneylite.ps1'; Uri = 'https://www.mechcad.net/products/acemoney/' },
        @{ Name = 'Akira'; ScriptName = 'akira.ps1'; Uri = 'https://github.com/akiraux/Akira' },
        @{ Name = 'Hemingway Editor'; ScriptName = 'hemingwayeditor.ps1'; Uri = 'https://hemingwayapp.com/' },
        @{ Name = 'Quant-UX'; ScriptName = 'quantux.ps1'; Uri = 'https://quant-ux.com/' }
    )
    $env:APP_SCRIPT_TEST_START_PROCESS_TRACE = $browserTracePath
    $cliAppsPath = Join-Path $testRoot 'cli-apps'
    New-Item -ItemType Directory -Path $cliAppsPath -Force | Out-Null
    $script:cliLogEntries = @()

    foreach ($browserApp in $browserApps) {
        $targetScriptPath = Join-Path $repositoryRoot ('apps\' + $browserApp.ScriptName)
        $wrapperPath = Join-Path $cliAppsPath $browserApp.ScriptName
        $logPath = Join-Path $testRoot ($browserApp.ScriptName + '.log')
        $quotedTargetPath = "'" + $targetScriptPath.Replace("'", "''") + "'"
        $quotedLogPath = "'" + $logPath.Replace("'", "''") + "'"
        $wrapperContent = @'
function Start-Process {
    param([Parameter(Position = 0)][string]$FilePath)
    [System.IO.File]::AppendAllText($env:APP_SCRIPT_TEST_START_PROCESS_TRACE, ($FilePath + [Environment]::NewLine))
}
function Write-Host {
    param([Parameter(Position = 0)][object]$Object, [object]$ForegroundColor, [object]$BackgroundColor, [switch]$NoNewline)
}
. __TARGET_SCRIPT__ -LogPath __LOG_PATH__
'@
        $wrapperContent = $wrapperContent.Replace('__TARGET_SCRIPT__', $quotedTargetPath).Replace('__LOG_PATH__', $quotedLogPath)
        Write-Fixture -Path $wrapperPath -Content $wrapperContent

        $browserResult = Invoke-AppScript -ScriptPath $wrapperPath
        Assert-Condition ($browserResult.Status -eq 'ManualActionRequired') "$($browserApp.Name) browser handoff maps to ManualActionRequired"
        Assert-Condition ($browserResult.Message -match 'Complete installation' -and $browserResult.Message -match 'does not confirm installation') "$($browserApp.Name) outcome tells the caller what remains to be done"
        $appLog = Get-Content -LiteralPath $logPath -Raw
        Assert-Condition ($appLog -match 'WARNING \| .*manual action required' -and $appLog -notmatch 'SUCCESS') "$($browserApp.Name) handoff log does not claim installation success"
    }

    $browserTraceLines = @(Get-Content -LiteralPath $browserTracePath)
    Assert-Condition ($browserTraceLines.Count -eq $browserApps.Count) 'each browser-only script used the fake Start-Process exactly once'
    for ($browserIndex = 0; $browserIndex -lt $browserApps.Count; $browserIndex++) {
        Assert-Condition ($browserTraceLines[$browserIndex] -ceq $browserApps[$browserIndex].Uri) "$($browserApps[$browserIndex].Name) fake browser receives only its vendor URL"
    }

    $guiPath = Join-Path $repositoryRoot 'app-installer.ps1'
    Invoke-Expression (Get-FunctionDefinitionText -Path $guiPath -Name 'Install-Application')
    if (-not ('System.Drawing.Color' -as [type])) {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    $script:guiLogEntries = @()
    $script:guiVisibleOutput = @()
    $script:AppsPath = $cliAppsPath
    $script:AppProgressBar = $null
    $script:StatusLabel = $null
    $script:InstalledApps = @{}
    function Safe-TestPath { param([string]$Path) return (Test-Path -LiteralPath $Path) }
    function Write-Log { param([string]$Message, [string]$Level) $script:guiLogEntries += [PSCustomObject]@{ Message = $Message; Level = $Level } }
    function Write-Output { param([Parameter(Position = 0)][object]$Object, [object]$Color) $script:guiVisibleOutput += [string]$Object }

    $guiApp = [PSCustomObject]@{
        Name = 'AceMoney Lite'
        ScriptName = 'acemoneylite.ps1'
        WingetId = ''
    }
    $guiInstallResult = Install-Application -App $guiApp
    Assert-Condition (-not $guiInstallResult -and $script:LastAppScriptOutcome -eq 'ManualActionRequired') 'GUI caller preserves ManualActionRequired as a non-success result'
    Assert-Condition (-not $script:InstalledApps.ContainsKey($guiApp.Name)) 'GUI caller does not add a manual handoff to installed state'
    Assert-Condition (@($script:guiLogEntries | Where-Object { $_.Level -eq 'SUCCESS' }).Count -eq 0 -and @($script:guiLogEntries | Where-Object { $_.Level -eq 'WARNING' -and $_.Message -match 'Complete installation' }).Count -eq 1) 'GUI caller logs the remaining manual action without a success entry'
    Assert-Condition (($script:guiVisibleOutput -join ' ') -match '\[ACTION REQUIRED\].*Complete installation') 'GUI caller displays what the user must complete'

    $cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
    foreach ($functionName in @('New-InstallerActionResult', 'Get-InstallerActionStatus', 'Install-Application', 'Install-MissingApplications')) {
        Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name $functionName)
    }
    function Test-InstallerShouldProcess { param([string]$Target, [string]$Action) return $true }
    function Write-Log { param([string]$Message, [string]$Level) $script:cliLogEntries += [PSCustomObject]@{ Message = $Message; Level = $Level } }
    function Get-InstalledApplications { $script:installedStateQueryCount++; return @{} }
    function Start-Sleep { param([int]$Seconds) }

    $manualApps = @($browserApps | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                ScriptName = $_.ScriptName
                Platform = 'Windows'
                WingetId = ''
            }
        })
    Assert-Condition ($manualApps.Count -eq $browserApps.Count) 'all four browser-only script entries are represented in the fake CLI selection'
    $script:AppsPath = $cliAppsPath
    $script:Applications = $manualApps
    $script:InstalledApps = @{}
    $script:installedStateQueryCount = 0

    foreach ($browserApp in $browserApps) {
        $app = $manualApps | Where-Object { $_.ScriptName -ceq $browserApp.ScriptName } | Select-Object -First 1
        $installResult = Install-Application -App $app -CurrentIndex 1 -TotalCount $browserApps.Count -Confirm:$false
        Assert-Condition ((Get-InstallerActionStatus -Result $installResult) -eq 'ManualActionRequired' -and -not $installResult.Success) "$($browserApp.Name) CLI caller preserves ManualActionRequired"
        Assert-Condition (-not $script:InstalledApps.ContainsKey($browserApp.Name)) "$($browserApp.Name) CLI caller does not add a manual handoff to installed state"
    }

    $browserTraceBeforeInstallMissing = @(Get-Content -LiteralPath $browserTracePath).Count
    Install-MissingApplications -Confirm:$false
    Assert-Condition ($script:installedStateQueryCount -eq 1) 'Install Missing queries fresh installed state after manual handoffs'
    Assert-Condition ($script:InstalledApps.Count -eq 0) 'Install Missing keeps every unverified manual handoff out of installed state'
    Assert-Condition ((@(Get-Content -LiteralPath $browserTracePath).Count - $browserTraceBeforeInstallMissing) -eq $browserApps.Count) 'a later Install Missing selection retries all four unverified handoffs'
    Assert-Condition (@($script:cliLogEntries | Where-Object { $_.Level -eq 'SUCCESS' }).Count -eq 0) 'CLI handoffs emit no success log entries'
    Assert-Condition (@($script:cliLogEntries | Where-Object { $_.Level -eq 'WARNING' -and $_.Message -match 'Complete installation' }).Count -ge $browserApps.Count) 'CLI tells users that the vendor installation still needs completion'

    $afterUnrelatedAppState = ConvertTo-Json -InputObject $script:unrelatedAppState -Depth 5 -Compress
    Assert-Condition ($afterUnrelatedAppState -ceq $beforeUnrelatedAppState) 'unrelated installed-app and queue state remain unchanged'

    $guiSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer.ps1'))
    $cliSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer-cli.ps1'))
    $guiSuccessContract = 'if ($appScriptResult.Status -in @(''PowerShellSuccess'', ''NativeProcessSuccess'') -or $scriptExitCode -eq -1978335191)'
    $cliSuccessContract = 'if ($appScriptResult.Status -in @(''PowerShellSuccess'', ''NativeProcessSuccess''))'
    Assert-Condition ($guiSource.Contains($guiSuccessContract) -and $cliSource.Contains($cliSuccessContract)) 'GUI and CLI completion mapping accepts only declared success states; the blocked McAfee exit code remains a failure'
    Assert-Condition ($guiSource.Contains('$scriptPath = Join-Path $script:AppsPath $App.ScriptName') -and $guiSource.Contains('AppInstallerCore\Invoke-AppScript -ScriptPath $scriptPath') -and $cliSource.Contains('$scriptPath = Join-Path $script:AppsPath $App.ScriptName') -and $cliSource.Contains('AppInstallerCore\Invoke-AppScript -ScriptPath $scriptPath')) 'GUI and CLI dispatch the McAfee catalog script through the shared custom-app result boundary'
    Assert-Condition ($guiSource.Contains('Write-Log "Using custom script: $scriptPath"')) 'GUI custom-script log line remains present'
    Assert-Condition ($cliSource.Contains('Write-Log "Using custom script: $scriptPath"')) 'CLI custom-script log line remains present'
    Assert-Condition ($guiSource.Contains('elseif ($appScriptResult.Status -eq ''Unknown'')') -and $guiSource.Contains('[UNKNOWN] $unknownMessage')) 'GUI reports an unknown result without marking the app installed'
    Assert-Condition ($cliSource.Contains('elseif ($appScriptResult.Status -eq ''Unknown'')') -and $cliSource.Contains('[2/2] [UNKNOWN] $unknownMessage')) 'CLI reports an unknown result without marking the app installed'
    Assert-Condition ($guiSource.Contains("elseif (`$appScriptResult.Status -eq 'ManualActionRequired')") -and $guiSource.Contains('[ACTION REQUIRED] $manualActionMessage')) 'GUI reports a manual handoff distinctly and leaves it uninstalled'
    Assert-Condition ($cliSource.Contains("elseif (`$appScriptResult.Status -eq 'ManualActionRequired')") -and $cliSource.Contains('[2/2] [ACTION REQUIRED] $manualActionMessage')) 'CLI reports a manual handoff distinctly and leaves it uninstalled'
    Assert-Condition ($guiSource.Contains('=== Installation Run Finished - Manual Action Required ===') -and $guiSource.Contains('$toastTitle = if ($manualActionPending) { ''Manual action required'' }')) 'GUI completion heading and notification title remain action-required when manual work is pending'
    Assert-Condition ($guiSource.Contains('$app = $script:InstallationQueue[$script:CurrentQueueIndex]')) 'GUI installation queue still selects entries in queue order'
    Assert-Condition ($cliSource.Contains('foreach ($app in $appsToInstall)')) 'CLI installation loop still preserves selected app order'

    Write-Host "[PASS] $script:assertionCount custom app script result assertions passed." -ForegroundColor Green
}
finally {
    $global:LASTEXITCODE = $script:originalLastExitCode
    $env:APP_SCRIPT_TEST_ARGUMENT_CAPTURE = $oldArgumentCapture
    $env:APP_SCRIPT_TEST_NATIVE_PATH = $oldNativePath
    $env:APP_SCRIPT_TEST_NATIVE_CODE = $oldNativeCode
    $env:APP_SCRIPT_TEST_NATIVE_TRACE = $oldNativeTrace
    $env:APP_SCRIPT_TEST_START_PROCESS_TRACE = $oldBrowserTrace
    Remove-Module -Name AppInstallerCore -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTempTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTempTestRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTempTestRoot -Recurse -Force
        }
    }
}
