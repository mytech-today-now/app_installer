# Offline regression coverage for explicit monthly-update scheduling.
# This script uses a child PowerShell process with fake winget and schtasks.exe commands.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] Monthly task integration uses Windows CLI behavior.' -ForegroundColor Yellow
    exit 77
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('winget-task-' + [guid]::NewGuid().ToString('N'))))
$engineExecutableName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$cliEnginePath = Join-Path $PSHOME $engineExecutableName
if (-not (Test-Path -LiteralPath $cliEnginePath -PathType Leaf)) {
    throw "The current PowerShell engine executable could not be resolved at $cliEnginePath."
}
$checkCount = 0

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

function Get-FileDigest {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))
    }
    finally {
        $sha.Dispose()
    }
}

function New-LegacyTaskXml {
    param([Parameter(Mandatory = $true)][string]$UpdateScriptPath)
    $escapedPath = [System.Security.SecurityElement]::Escape($UpdateScriptPath)
    return @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>TestUser</Author><Description>Legacy monthly update task</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>2026-10-15T13:00:00</StartBoundary><ScheduleByMonth><DaysOfMonth><Day>15</Day></DaysOfMonth><Months><October/></Months></ScheduleByMonth></CalendarTrigger></Triggers>
  <Principals><Principal><UserId>TestUser</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><Enabled>true</Enabled><AllowStartOnDemand>true</AllowStartOnDemand></Settings>
  <Actions><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File &quot;$escapedPath&quot;</Arguments></Exec></Actions>
</Task>
"@
}

function New-Scenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$InputText = '',
        [string]$ProfilePath = '',
        [switch]$SeedOldTask,
        [switch]$FailFinalCreate,
        [switch]$OmitUpdateScript,
        [switch]$InvalidSchedulerQuery,
        [switch]$WhatIf,
        [switch]$NonInteractive,
        [switch]$FakeWingetUnavailable,
        [switch]$FakeWingetReportsInstalled,
        [switch]$TraceAllWingetCalls,
        [ValidateSet('cli', 'updater')][string]$Mode = 'cli',
        [string]$PackageIds = '',
        [int]$WingetExitCode = 0
    )

    $scenarioRoot = Join-Path $testRoot $Name
    $checkoutRoot = Join-Path $scenarioRoot 'checkout'
    $userProfile = Join-Path $scenarioRoot 'user'
    $scenarioBinPath = Join-Path $scenarioRoot 'bin'
    New-Item -ItemType Directory -Path $checkoutRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $checkoutRoot 'modules') -Force | Out-Null
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    New-Item -ItemType Directory -Path $scenarioBinPath -Force | Out-Null
    foreach ($fileName in @('app-installer-cli.ps1', 'apps-manifest.json', 'platform-detect.ps1', 'compatibility.json')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $fileName) -Destination $checkoutRoot -Force
    }
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Destination $checkoutRoot -Force
    $sourceManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'apps-manifest.json') -Raw | ConvertFrom-Json
    $packageFixture = @($sourceManifest.apps | Where-Object { $_.packages.winget -ceq 'Box.Box' } | Select-Object -First 1)
    if ($packageFixture.Count -ne 1) {
        throw 'The monthly task fixture package Box.Box was not found in apps-manifest.json.'
    }
    $packageFixture[0].platform = 'Windows'
    $scenarioManifest = [PSCustomObject]@{
        '$schema' = [string]$sourceManifest.'$schema'
        version = [string]$sourceManifest.version
        generated = [string]$sourceManifest.generated
        description = 'Disposable single-package fixture for monthly update scheduling tests.'
        apps = @($packageFixture)
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $checkoutRoot 'apps-manifest.json'),
        ($scenarioManifest | ConvertTo-Json -Depth 10),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $checkoutAppsPath = Join-Path $checkoutRoot 'apps'
    New-Item -ItemType Directory -Path $checkoutAppsPath -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Join-Path $repositoryRoot 'apps') 'winget-update.ps1') -Destination $checkoutAppsPath -Force
    Set-Content -LiteralPath (Join-Path $checkoutAppsPath 'fixture-unused.ps1') -Value '# Harmless offline payload fixture; it is not referenced or invoked.' -Encoding UTF8
    $appScriptName = if ($packageFixture[0].scriptName) { [string]$packageFixture[0].scriptName } else { [string]$packageFixture[0].script }
    if (-not [string]::IsNullOrWhiteSpace($appScriptName)) {
        $sourceAppScriptPath = Join-Path (Join-Path $repositoryRoot 'apps') $appScriptName
        if (-not (Test-Path -LiteralPath $sourceAppScriptPath -PathType Leaf)) {
            throw "The monthly task fixture application script is missing: $appScriptName"
        }
        Copy-Item -LiteralPath $sourceAppScriptPath -Destination $checkoutAppsPath -Force
    }

    $runtimeModuleNames = @(
        'AppInstallerCore.psm1',
        'InstallerCompatibility.psm1',
        'InstallerPayload.psm1',
        'InstallerPrerequisitePlan.psm1',
        'InstallerRuntimeDiscovery.psm1',
        'WingetBootstrap.psm1'
    )
    foreach ($moduleName in $runtimeModuleNames) {
        $sourceModulePath = Join-Path (Join-Path $repositoryRoot 'modules') $moduleName
        $targetModulePath = Join-Path (Join-Path $checkoutRoot 'modules') $moduleName
        Copy-Item -LiteralPath $sourceModulePath -Destination $targetModulePath -Force
    }

    $cliPayloadFiles = @(
        'app-installer-cli.ps1',
        'apps-manifest.json',
        'compatibility.json',
        'modules/AppInstallerCore.psm1',
        'modules/InstallerCompatibility.psm1',
        'modules/InstallerPayload.psm1',
        'modules/InstallerPrerequisitePlan.psm1',
        'modules/InstallerRuntimeDiscovery.psm1',
        'modules/WingetBootstrap.psm1',
        'platform-detect.ps1'
    )
    $payloadFixture = [PSCustomObject]@{
        formatVersion = 1
        productVersionFile = 'VERSION'
        generatedIntegrityFile = 'payload-integrity.json'
        requiredFiles = @($cliPayloadFiles + @('payload-manifest.json', 'VERSION'))
        fileSets = @(
            [PSCustomObject]@{ path = 'apps'; extensions = @('.ps1') },
            [PSCustomObject]@{ path = 'modules'; extensions = @('.ps1', '.psm1') }
        )
        features = [PSCustomObject]@{ cli = $cliPayloadFiles }
        exclusions = [PSCustomObject]@{
            directoryNames = @('.git', 'tests', 'fixtures', 'logs', 'temp', 'tmp')
            fileNamePrefixes = @('.env')
            extensions = @('.log', '.tmp', '.bak', '.exe', '.dll', '.key')
        }
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $checkoutRoot 'payload-manifest.json'),
        ($payloadFixture | ConvertTo-Json -Depth 10),
        (New-Object System.Text.UTF8Encoding($false))
    )
    New-Item -ItemType Directory -Path (Join-Path $checkoutRoot '.git') -Force | Out-Null

    $installedUpdaterPath = Join-Path (Join-Path (Join-Path $userProfile 'myTech.Today\AppInstaller') 'apps') 'winget-update.ps1'
    $statePath = Join-Path $scenarioRoot 'fake-task-state.json'
    $tracePath = Join-Path $scenarioRoot 'fake-schtasks-trace.txt'
    $wingetTracePath = Join-Path $scenarioRoot 'fake-winget-updates.txt'
    $nativeWingetTracePath = Join-Path $scenarioRoot 'fake-native-winget-trace.txt'
    $driverPath = Join-Path $scenarioRoot 'driver.ps1'
    $initialTasks = @()
    if ($SeedOldTask) {
        $initialTasks = @([PSCustomObject]@{
            Path = '\myTech.Today\Monthly Application Updates'
            Xml = New-LegacyTaskXml -UpdateScriptPath $installedUpdaterPath
        })
    }
    $stateJson = ([PSCustomObject]@{ Tasks = $initialTasks } | ConvertTo-Json -Depth 8)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statePath, $stateJson, $utf8)
    [System.IO.File]::WriteAllText($tracePath, '', $utf8)
    [System.IO.File]::WriteAllText($wingetTracePath, '', $utf8)
    [System.IO.File]::WriteAllText($nativeWingetTracePath, '', $utf8)
    $fakeNativeWingetText = @'
@echo off
>>"%FAKE_NATIVE_WINGET_TRACE%" echo %*
if /I "%1"=="show" echo Fake dependency metadata.
exit /b %FAKE_WINGET_EXIT_CODE%
'@
    [System.IO.File]::WriteAllText((Join-Path $scenarioBinPath 'winget.cmd'), $fakeNativeWingetText, [System.Text.Encoding]::ASCII)

    $driverText = @'
$ErrorActionPreference = 'Continue'
$global:FakeFinalCreateFailed = $false
$global:FakeReadHostResponses = New-Object System.Collections.Queue
$inputText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:CLI_INPUT_BASE64))
foreach ($response in ($inputText -split '\r?\n')) {
    if (-not [string]::IsNullOrWhiteSpace($response)) {
        $global:FakeReadHostResponses.Enqueue($response)
    }
}

function global:Read-Host {
    param([string]$Prompt)
    if ($global:FakeReadHostResponses.Count -gt 0) {
        return [string]$global:FakeReadHostResponses.Dequeue()
    }
    return ''
}

function global:Clear-Host {
    return
}

function Read-FakeTaskState {
    return (Get-Content -LiteralPath $env:FAKE_TASK_STATE -Raw | ConvertFrom-Json)
}

function Write-FakeTaskState {
    param([Parameter(Mandatory = $true)]$State)
    $json = $State | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($env:FAKE_TASK_STATE, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-FakeTask {
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = Read-FakeTaskState
    return @($state.Tasks | Where-Object { $_.Path -ceq $Path } | Select-Object -First 1)
}

function Set-FakeTask {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Xml
    )
    $state = Read-FakeTaskState
    $remaining = @($state.Tasks | Where-Object { $_.Path -cne $Path })
    $state.Tasks = @($remaining) + @([PSCustomObject]@{ Path = $Path; Xml = $Xml })
    Write-FakeTaskState -State $state
}

function Remove-FakeTask {
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = Read-FakeTaskState
    $state.Tasks = @($state.Tasks | Where-Object { $_.Path -cne $Path })
    Write-FakeTaskState -State $state
}

function global:schtasks.exe {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$SchedulerArgs)
    [System.IO.File]::AppendAllText($env:FAKE_SCHTASKS_TRACE, (($SchedulerArgs -join '|') + [Environment]::NewLine))
    $verb = $SchedulerArgs[0].ToUpperInvariant()
    $taskIndex = [Array]::IndexOf($SchedulerArgs, '/TN')
    $taskPath = if ($taskIndex -ge 0 -and $taskIndex + 1 -lt $SchedulerArgs.Count) { $SchedulerArgs[$taskIndex + 1] } else { '' }

    if ($verb -eq '/QUERY') {
        if ($taskPath -ceq '\myTech.Today\Monthly Application Updates' -and $env:FAKE_INVALID_SCHEDULER_QUERY -eq '1') {
            Write-Output 'This is not valid task XML.'
            $global:LASTEXITCODE = 0
            return
        }
        $task = @(Get-FakeTask -Path $taskPath)
        if ($task.Count -eq 0) {
            Write-Output 'ERROR: Task not found.'
            $global:LASTEXITCODE = 1
            return
        }
        Write-Output ([string]$task[0].Xml)
        $global:LASTEXITCODE = 0
        return
    }

    if ($verb -eq '/CREATE') {
        $xmlIndex = [Array]::IndexOf($SchedulerArgs, '/XML')
        if ($xmlIndex -lt 0 -or $xmlIndex + 1 -ge $SchedulerArgs.Count) {
            Write-Output 'ERROR: Missing XML task definition.'
            $global:LASTEXITCODE = 2
            return
        }
        $xmlText = [System.IO.File]::ReadAllText($SchedulerArgs[$xmlIndex + 1])
        if ($taskPath -ceq '\myTech.Today\Monthly Application Updates' -and
            $env:FAKE_FAIL_FINAL_CREATE -eq '1' -and -not $global:FakeFinalCreateFailed) {
            Set-FakeTask -Path $taskPath -Xml $xmlText
            $global:FakeFinalCreateFailed = $true
            Write-Output 'ERROR: Injected final task creation failure.'
            $global:LASTEXITCODE = 1
            return
        }
        Set-FakeTask -Path $taskPath -Xml $xmlText
        Write-Output 'SUCCESS: Fake task created.'
        $global:LASTEXITCODE = 0
        return
    }

    if ($verb -eq '/DELETE') {
        if (@(Get-FakeTask -Path $taskPath).Count -eq 0) {
            Write-Output 'ERROR: Task not found.'
            $global:LASTEXITCODE = 1
            return
        }
        Remove-FakeTask -Path $taskPath
        Write-Output 'SUCCESS: Fake task deleted.'
        $global:LASTEXITCODE = 0
        return
    }

    Write-Output 'ERROR: Unsupported fake schtasks command.'
    $global:LASTEXITCODE = 2
}

if ($env:FAKE_WINGET_AVAILABLE -ne '0') {
function global:winget {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$PackageArgs)
    if ($PackageArgs -contains 'list') {
        if ($env:FAKE_TRACE_ALL_WINGET -eq '1') {
            [System.IO.File]::AppendAllText($env:FAKE_WINGET_TRACE, (($PackageArgs -join '|') + [Environment]::NewLine))
        }
        if ($env:FAKE_WINGET_INSTALLED -eq '1') {
            Write-Output 'Name Id Version'
            Write-Output 'Box Drive Box.Box 1.0'
        }
        else {
            Write-Output 'No fake winget packages are installed.'
        }
        $global:LASTEXITCODE = 0
        return
    }
    if ($PackageArgs -contains 'upgrade' -or $PackageArgs -contains 'install') {
        [System.IO.File]::AppendAllText($env:FAKE_WINGET_TRACE, (($PackageArgs -join '|') + [Environment]::NewLine))
        if ([int]$env:FAKE_WINGET_EXIT_CODE -eq 0) {
            $packageIdIndex = [Array]::IndexOf($PackageArgs, '--id')
            $packageId = if ($packageIdIndex -ge 0 -and $packageIdIndex + 1 -lt $PackageArgs.Count) { $PackageArgs[$packageIdIndex + 1] } else { 'Fake.Package' }
            Write-Output "Found Fake Package [$packageId] Version 2.0"
            Write-Output 'Starting package install...'
            Write-Output 'Successfully installed'
        }
        else {
            Write-Output 'Found Fake Package [Google.Chrome] Version 2.0'
            Write-Output 'Starting package install...'
            Write-Output 'Installer failed with exit code: 23'
        }
        $global:LASTEXITCODE = [int]$env:FAKE_WINGET_EXIT_CODE
        return
    }
    Write-Output 'Fake winget command.'
    $global:LASTEXITCODE = 0
}
}

if ($env:DRIVER_MODE -eq 'updater') {
    function global:Test-Path {
        param([string]$Path, [string]$LiteralPath, [string]$PathType)
        $candidate = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } else { $Path }
        return ($candidate -eq 'C:\mytech.today\logs') -or [System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate)
    }
    function global:Add-Content {
        param([string]$Path, [string]$Value, [object]$ErrorAction)
        [System.IO.File]::AppendAllText($env:FAKE_UPDATE_LOG, $Value + [Environment]::NewLine)
    }
    & $env:UPDATE_SCRIPT -PackageIds $env:PACKAGE_IDS
    exit $global:LASTEXITCODE
}

if ($env:FAKE_OMIT_UPDATE_SCRIPT -eq '1') {
    $sourceUpdater = Join-Path (Split-Path -Parent $env:CLI_SCRIPT) 'apps\winget-update.ps1'
    if (Test-Path -LiteralPath $sourceUpdater -PathType Leaf) {
        Remove-Item -LiteralPath $sourceUpdater -Force
    }
}

$cliParameters = @{ Action = $env:CLI_ACTION }
if (-not [string]::IsNullOrWhiteSpace($env:CLI_PROFILE)) {
    $cliParameters.Profile = $env:CLI_PROFILE
}
if ($env:CLI_WHATIF -eq '1') {
    $cliParameters.WhatIf = $true
}
if ($env:CLI_NONINTERACTIVE -eq '1') {
    $cliParameters.Confirm = $false
}
& $env:CLI_SCRIPT @cliParameters
'@
    [System.IO.File]::WriteAllText($driverPath, $driverText, $utf8)

    return [PSCustomObject]@{
        Root = $scenarioRoot
        UserProfile = $userProfile
        StatePath = $statePath
        TracePath = $tracePath
        WingetTracePath = $wingetTracePath
        NativeWingetTracePath = $nativeWingetTracePath
        DriverPath = $driverPath
        CliPath = Join-Path $checkoutRoot 'app-installer-cli.ps1'
        InputText = $InputText
        Action = $Action
        ProfilePath = $ProfilePath
        FailFinalCreate = [bool]$FailFinalCreate
        OmitUpdateScript = [bool]$OmitUpdateScript
        InvalidSchedulerQuery = [bool]$InvalidSchedulerQuery
        WhatIf = [bool]$WhatIf
        NonInteractive = [bool]$NonInteractive
        FakeWingetUnavailable = [bool]$FakeWingetUnavailable
        FakeWingetReportsInstalled = [bool]$FakeWingetReportsInstalled
        TraceAllWingetCalls = [bool]$TraceAllWingetCalls
        Mode = $Mode
        PackageIds = $PackageIds
        WingetExitCode = $WingetExitCode
        OldTaskXml = if ($SeedOldTask) { $initialTasks[0].Xml } else { $null }
    }
}

function Invoke-Scenario {
    param([Parameter(Mandatory = $true)]$Scenario)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $cliEnginePath
    $startInfo.Arguments = '-NoProfile -File "{0}"' -f $Scenario.DriverPath
    $startInfo.WorkingDirectory = $Scenario.Root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $environment = $startInfo.EnvironmentVariables
    $environment['USERPROFILE'] = $Scenario.UserProfile
    $environment['HOME'] = $Scenario.UserProfile
    $environment['APPDATA'] = Join-Path $Scenario.UserProfile 'AppData\Roaming'
    $environment['LOCALAPPDATA'] = Join-Path $Scenario.UserProfile 'AppData\Local'
    $environment['PATH'] = Join-Path $env:SystemRoot 'System32'
    if (-not $Scenario.FakeWingetUnavailable) {
        $environment['PATH'] = (Join-Path $Scenario.Root 'bin') + ';' + $environment['PATH']
    }
    $environment['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'
    $environment['TEMP'] = $Scenario.Root
    $environment['TMP'] = $Scenario.Root
    $environment['FAKE_TASK_STATE'] = $Scenario.StatePath
    $environment['FAKE_SCHTASKS_TRACE'] = $Scenario.TracePath
    $environment['FAKE_WINGET_TRACE'] = $Scenario.WingetTracePath
    $environment['FAKE_NATIVE_WINGET_TRACE'] = $Scenario.NativeWingetTracePath
    $environment['FAKE_WINGET_EXIT_CODE'] = [string]$Scenario.WingetExitCode
    $environment['FAKE_FAIL_FINAL_CREATE'] = if ($Scenario.FailFinalCreate) { '1' } else { '0' }
    $environment['FAKE_OMIT_UPDATE_SCRIPT'] = if ($Scenario.OmitUpdateScript) { '1' } else { '0' }
    $environment['FAKE_INVALID_SCHEDULER_QUERY'] = if ($Scenario.InvalidSchedulerQuery) { '1' } else { '0' }
    $environment['FAKE_WINGET_AVAILABLE'] = if ($Scenario.FakeWingetUnavailable) { '0' } else { '1' }
    $environment['FAKE_WINGET_INSTALLED'] = if ($Scenario.FakeWingetReportsInstalled) { '1' } else { '0' }
    $environment['FAKE_TRACE_ALL_WINGET'] = if ($Scenario.TraceAllWingetCalls) { '1' } else { '0' }
    $environment['CLI_SCRIPT'] = $Scenario.CliPath
    $environment['APP_INSTALLER_RUNTIME_HANDOFF_PATH'] = $cliEnginePath
    $environment['APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT'] = 'WindowsCli'
    $environment['CLI_ACTION'] = $Scenario.Action
    $environment['CLI_PROFILE'] = $Scenario.ProfilePath
    $environment['CLI_INPUT_BASE64'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Scenario.InputText))
    $environment['CLI_WHATIF'] = if ($Scenario.WhatIf) { '1' } else { '0' }
    $environment['CLI_NONINTERACTIVE'] = if ($Scenario.NonInteractive) { '1' } else { '0' }
    $environment['DRIVER_MODE'] = $Scenario.Mode
    $environment['UPDATE_SCRIPT'] = Join-Path $repositoryRoot 'apps\winget-update.ps1'
    $environment['PACKAGE_IDS'] = $Scenario.PackageIds
    $environment['FAKE_UPDATE_LOG'] = Join-Path $Scenario.Root 'fake-update-log.txt'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start isolated PowerShell for scenario $($Scenario.Action)."
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($Scenario.InputText) {
        $process.StandardInput.Write($Scenario.InputText)
    }
    $process.StandardInput.Close()

    if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        throw "Isolated PowerShell timed out for scenario $($Scenario.Action)."
    }
    $process.WaitForExit()
    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output = $stdoutTask.GetAwaiter().GetResult()
        Error = $stderrTask.GetAwaiter().GetResult()
        Scenario = $Scenario
    }
}

function Read-TaskState {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Assert-NoTaskMutation {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$BeforeDigest
    )
    $trace = Get-Content -LiteralPath $Result.Scenario.TracePath -Raw
    $mutationCommands = @($trace -split '\r?\n' | Where-Object { $_ -match '(?i)^/(Create|Delete)\|' })
    Assert-Condition -Condition ($mutationCommands.Count -eq 0) -Message "$Description issues no task create or delete command"
    Assert-Condition -Condition ((Get-FileDigest -Path $Result.Scenario.StatePath) -eq $BeforeDigest) -Message "$Description leaves task state unchanged"
    Assert-Condition -Condition ($Result.Output.Contains('Automatic monthly updates are not enabled. You can run updates manually from the installer.')) -Message "$Description shows the manual-update fallback"
}

function Initialize-TestTree {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
}

try {
    Initialize-TestTree

    $status = New-Scenario -Name 'status' -Action 'Status' -InputText ('Q' + [Environment]::NewLine)
    $statusDigest = Get-FileDigest -Path $status.StatePath
    $statusResult = Invoke-Scenario -Scenario $status
    Assert-Condition -Condition ($statusResult.ExitCode -eq 0) -Message 'Status action exits successfully'
    Assert-NoTaskMutation -Result $statusResult -Description 'Status action' -BeforeDigest $statusDigest

    $menuExit = New-Scenario -Name 'menu-exit' -Action 'Menu' -InputText ('Q' + [Environment]::NewLine)
    $menuDigest = Get-FileDigest -Path $menuExit.StatePath
    $menuResult = Invoke-Scenario -Scenario $menuExit
    Assert-Condition -Condition ($menuResult.ExitCode -eq 0) -Message 'Menu exit completes successfully'
    Assert-NoTaskMutation -Result $menuResult -Description 'Menu exit' -BeforeDigest $menuDigest

    $installAll = New-Scenario -Name 'install-all-success' -Action 'InstallAll' -TraceAllWingetCalls
    $installAllResult = Invoke-Scenario -Scenario $installAll
    $installAllCalls = [string](Get-Content -LiteralPath $installAll.NativeWingetTracePath -Raw)
    Assert-Condition -Condition ($installAllResult.Output -match 'Loaded 1 applications for Windows') -Message 'Single-app registry remains an array in both PowerShell engines'
    Assert-Condition -Condition ($installAllResult.Output -match 'Successful: 1' -and $installAllResult.Output -match 'Failed: 0') -Message 'InstallAll classifies a successful fake package operation'
    Assert-Condition -Condition ($installAllCalls -match '(?m)^install --id Box\.Box --exact --source winget --silent --accept-source-agreements --accept-package-agreements') -Message 'InstallAll invokes the fake manager with exact catalog ID and source'

    $installAllFailure = New-Scenario -Name 'install-all-failure' -Action 'InstallAll' -WingetExitCode 23
    $installAllFailureResult = Invoke-Scenario -Scenario $installAllFailure
    Assert-Condition -Condition ($installAllFailureResult.Output -match 'Installation failed:.*Exit code: 23' -and $installAllFailureResult.Output -match 'Failed: 1') -Message 'InstallAll reports a nonzero fake package result as failure'

    $installAllPreview = New-Scenario -Name 'install-all-whatif' -Action 'InstallAll' -WhatIf -TraceAllWingetCalls
    $installAllPreviewResult = Invoke-Scenario -Scenario $installAllPreview
    Assert-Condition -Condition ($installAllPreviewResult.Output -match '\[PREVIEW\].*Box Drive \[Box\.Box\]') -Message 'InstallAll WhatIf previews the selected app'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $installAllPreview.WingetTracePath -Raw)) -and [string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $installAllPreview.NativeWingetTracePath -Raw))) -Message 'InstallAll WhatIf does not query or invoke the fake package manager'

    $installMissing = New-Scenario -Name 'install-missing-success' -Action 'InstallMissing' -TraceAllWingetCalls
    $installMissingResult = Invoke-Scenario -Scenario $installMissing
    $installMissingCalls = @(([string](Get-Content -LiteralPath $installMissing.WingetTracePath -Raw)) -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition -Condition ($installMissingResult.Output -match 'Installed: 1' -and $installMissingResult.Output -match 'Skipped: 0' -and $installMissingResult.Output -match 'Failed: 0') -Message 'InstallMissing installs an absent app through the fake manager'
    $installMissingNativeCalls = [string](Get-Content -LiteralPath $installMissing.NativeWingetTracePath -Raw)
    Assert-Condition -Condition ($installMissingCalls.Count -eq 1 -and $installMissingCalls[0] -match '^list\|' -and $installMissingNativeCalls -match '(?m)^install --id Box\.Box --exact --source winget --silent --accept-source-agreements --accept-package-agreements') -Message 'InstallMissing queries installed state and installs with exact catalog ID and source'

    $installMissingInstalled = New-Scenario -Name 'install-missing-already-installed' -Action 'InstallMissing' -NonInteractive -FakeWingetReportsInstalled -TraceAllWingetCalls
    $installMissingInstalledResult = Invoke-Scenario -Scenario $installMissingInstalled
    $installMissingInstalledCalls = @(([string](Get-Content -LiteralPath $installMissingInstalled.WingetTracePath -Raw)) -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition -Condition ($installMissingInstalledResult.Output -match 'already installed' -and $installMissingInstalledResult.Output -match 'Skipped: 1') -Message 'Noninteractive InstallMissing skips an already installed app'
    Assert-Condition -Condition ($installMissingInstalledCalls.Count -eq 1 -and $installMissingInstalledCalls[0] -match '^list\|' -and $installMissingInstalledCalls -notmatch '^install\|') -Message 'InstallMissing does not reinstall an already installed app without confirmation'

    $installMissingPreview = New-Scenario -Name 'install-missing-whatif' -Action 'InstallMissing' -WhatIf -TraceAllWingetCalls
    $installMissingPreviewResult = Invoke-Scenario -Scenario $installMissingPreview
    Assert-Condition -Condition ($installMissingPreviewResult.Output -match 'Installed-package state was not queried') -Message 'InstallMissing WhatIf does not query installed state'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $installMissingPreview.WingetTracePath -Raw)) -and [string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $installMissingPreview.NativeWingetTracePath -Raw))) -Message 'InstallMissing WhatIf does not launch the fake package manager'

    $missingWinget = New-Scenario -Name 'missing-winget' -Action 'InstallAll' -InputText ('N' + [Environment]::NewLine) -FakeWingetUnavailable
    $missingWingetResult = Invoke-Scenario -Scenario $missingWinget
    Assert-Condition -Condition ($missingWingetResult.ExitCode -eq 0 -and $missingWingetResult.Output -match 'winget.*not available|not available.*winget') -Message 'Missing WinGet is reported and safely declined'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $missingWinget.WingetTracePath -Raw))) -Message 'Missing WinGet does not launch a package process'

    $invalidAction = New-Scenario -Name 'invalid-action' -Action 'NotARealAction'
    $invalidActionResult = Invoke-Scenario -Scenario $invalidAction
    Assert-Condition -Condition (($invalidActionResult.Output + $invalidActionResult.Error) -match "Cannot validate argument on parameter 'Action'") -Message 'Unsupported CLI actions fail explicitly during parameter binding'
    Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $invalidAction.WingetTracePath -Raw))) -Message 'An invalid action launches no package process'

    $missingProfile = Join-Path $testRoot 'failed-action\missing-profile.json'
    $failedAction = New-Scenario -Name 'failed-action' -Action 'InstallProfile' -ProfilePath $missingProfile
    $failedDigest = Get-FileDigest -Path $failedAction.StatePath
    $failedResult = Invoke-Scenario -Scenario $failedAction
    Assert-Condition -Condition ($failedResult.Output -match 'Failed to import profile') -Message 'Failed installation action reports its failure'
    Assert-NoTaskMutation -Result $failedResult -Description 'Failed action' -BeforeDigest $failedDigest

    $declined = New-Scenario -Name 'declined-opt-in' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine + 'N' + [Environment]::NewLine)
    $declinedDigest = Get-FileDigest -Path $declined.StatePath
    $declinedResult = Invoke-Scenario -Scenario $declined
    Assert-Condition -Condition ($declinedResult.Output -match 'Monthly update setup declined') -Message 'Declined scheduling is reported as cancelled'
    Assert-NoTaskMutation -Result $declinedResult -Description 'Declined opt-in' -BeforeDigest $declinedDigest

    $cancelledSelection = New-Scenario -Name 'cancelled-selection' -Action 'EnableMonthlyUpdates'
    $cancelledDigest = Get-FileDigest -Path $cancelledSelection.StatePath
    $cancelledResult = Invoke-Scenario -Scenario $cancelledSelection
    Assert-Condition -Condition ($cancelledResult.Output -match 'Monthly update setup cancelled') -Message 'Blank selection cancels setup before consent'
    Assert-NoTaskMutation -Result $cancelledResult -Description 'Cancelled selection' -BeforeDigest $cancelledDigest

    $missingUpdater = New-Scenario -Name 'missing-updater' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine) -OmitUpdateScript
    $missingUpdaterDigest = Get-FileDigest -Path $missingUpdater.StatePath
    $missingUpdaterResult = Invoke-Scenario -Scenario $missingUpdater
    Assert-Condition -Condition ($missingUpdaterResult.Output -match 'Monthly update script is missing') -Message 'Missing updater file fails before scheduler changes'
    Assert-NoTaskMutation -Result $missingUpdaterResult -Description 'Missing updater file' -BeforeDigest $missingUpdaterDigest

    $invalidQuery = New-Scenario -Name 'invalid-scheduler-output' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine + 'Y' + [Environment]::NewLine) -InvalidSchedulerQuery
    $invalidQueryDigest = Get-FileDigest -Path $invalidQuery.StatePath
    $invalidQueryResult = Invoke-Scenario -Scenario $invalidQuery
    Assert-Condition -Condition ($invalidQueryResult.Output -match 'Task Scheduler returned invalid XML') -Message 'Invalid scheduler output fails closed'
    Assert-NoTaskMutation -Result $invalidQueryResult -Description 'Invalid scheduler output' -BeforeDigest $invalidQueryDigest

    $sourceCliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
    $cliTokens = $null
    $cliParseErrors = $null
    $cliAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceCliPath, [ref]$cliTokens, [ref]$cliParseErrors)
    if ($cliParseErrors.Count -gt 0) {
        throw "Cannot inspect Disable-MonthlyUpdateTask because app-installer-cli.ps1 has a parse error: $($cliParseErrors[0].Message)"
    }
    $disableTaskFunction = $cliAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Disable-MonthlyUpdateTask'
        }, $true)
    if (-not $disableTaskFunction) {
        throw 'Disable-MonthlyUpdateTask was not found in the CLI source.'
    }

    $originalOs = [Environment]::GetEnvironmentVariable('OS', 'Process')
    $global:NonWindowsGuardOutput = @()
    $global:NonWindowsSchedulerQueryCount = 0
    function global:Write-Host {
        param([object]$Object, [object]$ForegroundColor, [object]$BackgroundColor, [switch]$NoNewline)
        $global:NonWindowsGuardOutput += [string]$Object
    }
    function global:Get-MonthlyUpdateTaskQuery {
        $global:NonWindowsSchedulerQueryCount++
        throw 'The non-Windows scheduling guard reached the scheduler query.'
    }
    try {
        $env:OS = 'TestOS'
        . ([scriptblock]::Create($disableTaskFunction.Extent.Text))
        $nonWindowsResult = Disable-MonthlyUpdateTask
    }
    finally {
        [Environment]::SetEnvironmentVariable('OS', $originalOs, 'Process')
        Remove-Item -LiteralPath 'Function:\Write-Host' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Function:\Get-MonthlyUpdateTaskQuery' -ErrorAction SilentlyContinue
    }
    Assert-Condition -Condition ($nonWindowsResult -eq $false) -Message 'Non-Windows scheduling returns refusal before scheduler access'
    Assert-Condition -Condition (($global:NonWindowsGuardOutput -join [Environment]::NewLine) -match 'available only on Windows') -Message 'Non-Windows scheduling explains that it is unavailable'
    Assert-Condition -Condition ($global:NonWindowsSchedulerQueryCount -eq 0) -Message 'Non-Windows scheduling never queries or changes task state'
    Remove-Variable -Name NonWindowsGuardOutput, NonWindowsSchedulerQueryCount -Scope Global -ErrorAction SilentlyContinue

    $enabled = New-Scenario -Name 'confirmed-opt-in' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine + 'Y' + [Environment]::NewLine)
    $enabledResult = Invoke-Scenario -Scenario $enabled
    $enabledState = Read-TaskState -Path $enabled.StatePath
    $enabledTask = @($enabledState.Tasks | Where-Object { $_.Path -ceq '\myTech.Today\Monthly Application Updates' })
    Assert-Condition -Condition ($enabledResult.ExitCode -eq 0 -and $enabledTask.Count -eq 1) -Message 'Explicit confirmation creates one task at the compatible task path'
    Assert-Condition -Condition ($enabledResult.Output -match '15th of each month at 1:00 PM' -and $enabledResult.Output -match 'Requested privilege: Highest available') -Message 'Consent summary shows cadence and requested privilege'
    Assert-Condition -Condition ($enabledResult.Output.Contains('Remove later: schtasks.exe /Delete /TN')) -Message 'Consent summary shows the exact task removal path'
    if ($enabledTask.Count -eq 1) {
        $taskDocument = New-Object System.Xml.XmlDocument
        $taskDocument.LoadXml([string]$enabledTask[0].Xml)
        $taskArgs = $taskDocument.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Arguments']").InnerText
        $taskAuthor = $taskDocument.SelectSingleNode("//*[local-name()='RegistrationInfo']/*[local-name()='Author']").InnerText
        $taskDescription = $taskDocument.SelectSingleNode("//*[local-name()='RegistrationInfo']/*[local-name()='Description']").InnerText
        $actionsContext = $taskDocument.SelectSingleNode("//*[local-name()='Actions']").GetAttribute('Context')
        $principalId = $taskDocument.SelectSingleNode("//*[local-name()='Principal']").GetAttribute('id')
        $taskRunLevel = $taskDocument.SelectSingleNode("//*[local-name()='RunLevel']").InnerText
        $taskIdentity = $taskDocument.SelectSingleNode("//*[local-name()='UserId']").InnerText
        $taskDay = $taskDocument.SelectSingleNode("//*[local-name()='ScheduleByMonth']/*[local-name()='DaysOfMonth']/*[local-name()='Day']").InnerText
        $taskScope = [regex]::Match($taskArgs, '-PackageIds "([^"]+)"').Groups[1].Value
        $taskScriptPath = Join-Path (Join-Path (Join-Path $enabled.UserProfile 'myTech.Today\AppInstaller') 'apps') 'winget-update.ps1'
        $expectedIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Assert-Condition -Condition ($enabledResult.Output.Contains("Updater script: $taskScriptPath")) -Message 'Consent summary shows the installed updater script path'
        Assert-Condition -Condition ($taskScope -ceq 'Box.Box' -and $taskArgs -notmatch '--all') -Message 'Task action preserves the exact selected winget package ID'
        Assert-Condition -Condition ($taskArgs -match '(?i)(^|\s)-NoProfile\s+-File\b' -and $taskArgs -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'Scheduled task honors the configured PowerShell execution policy'
        Assert-Condition -Condition ($enabledResult.Output.Contains($taskScope)) -Message 'The displayed package scope matches the task action'
        Assert-Condition -Condition ($taskArgs.Contains($taskScriptPath)) -Message 'Task action targets the installed updater script'
        Assert-Condition -Condition ($taskAuthor -eq $expectedIdentity -and $actionsContext -eq 'Author' -and $principalId -eq 'Author' -and $taskIdentity -eq $expectedIdentity -and $taskRunLevel -eq 'HighestAvailable' -and $taskDay -eq '15') -Message 'Task identity, principal metadata, privilege, and monthly date match the consent'
        Assert-Condition -Condition ($taskDescription -match 'myTech\.Today App Installer monthly update task; ownership=v1' -and $taskDescription.Contains($taskScope)) -Message 'Task ownership marker and selected scope remain in the task description'
        Assert-Condition -Condition ((Get-Content -LiteralPath $enabled.TracePath -Raw) -notmatch '(?i)winget update|winget install') -Message 'Scheduling does not start a package-manager update'
        Assert-Condition -Condition (@($enabledState.Tasks | Where-Object { $_.Path -match '\.pending-' }).Count -eq 0) -Message 'Validated staging task is removed after registration'
    }
    Assert-Condition -Condition (-not $enabledResult.Output.Contains('Automatic monthly updates are not enabled. You can run updates manually from the installer.')) -Message 'Successful opt-in does not display the disabled-state fallback'

    $replacement = New-Scenario -Name 'failed-replacement' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine + 'Y' + [Environment]::NewLine) -SeedOldTask -FailFinalCreate
    $replacementResult = Invoke-Scenario -Scenario $replacement
    $replacementState = Read-TaskState -Path $replacement.StatePath
    $restoredTask = @($replacementState.Tasks | Where-Object { $_.Path -ceq '\myTech.Today\Monthly Application Updates' })
    Assert-Condition -Condition ($replacementResult.Output.Contains('ERROR: Injected final task creation failure.')) -Message 'Scheduler creation failure is shown exactly'
    Assert-Condition -Condition ($restoredTask.Count -eq 1 -and $restoredTask[0].Xml -ceq $replacement.OldTaskXml) -Message 'Failed replacement restores the previous task definition intact'
    Assert-Condition -Condition ($replacementResult.Output -match 'previous application-owned task was restored and verified') -Message 'Replacement failure reports verified rollback'
    $replacementUpdateCalls = @(([string](Get-Content -LiteralPath $replacement.WingetTracePath -Raw)) -split '\r?\n' | Where-Object { $_ -match '(?i)update|install' })
    Assert-Condition -Condition ($replacementUpdateCalls.Count -eq 0) -Message 'Failed replacement does not start the update action'
    Assert-Condition -Condition (@($replacementState.Tasks | Where-Object { $_.Path -match '\.pending-' }).Count -eq 0) -Message 'Failed replacement leaves no staging task'

    $repeatSetup = New-Scenario -Name 'repeat-explicit-setup' -Action 'EnableMonthlyUpdates' -InputText ('1' + [Environment]::NewLine + 'Y' + [Environment]::NewLine) -SeedOldTask
    $repeatState = Read-TaskState -Path $repeatSetup.StatePath
    $repeatState.Tasks = @($repeatState.Tasks) + @([PSCustomObject]@{
        Path = '\OtherVendor\Unrelated Task'
        Xml = '<Task><RegistrationInfo><Description>Unrelated</Description></RegistrationInfo></Task>'
    })
    [System.IO.File]::WriteAllText($repeatSetup.StatePath, ($repeatState | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    $repeatResult = Invoke-Scenario -Scenario $repeatSetup
    $repeatAfter = Read-TaskState -Path $repeatSetup.StatePath
    Assert-Condition -Condition ($repeatResult.Output -match 'Monthly updates are enabled') -Message 'Repeated setup replaces the owned task only after confirmation'
    Assert-Condition -Condition (@($repeatAfter.Tasks | Where-Object { $_.Path -ceq '\OtherVendor\Unrelated Task' }).Count -eq 1) -Message 'Repeated setup preserves unrelated scheduled tasks'

    $removeTask = New-Scenario -Name 'remove-owned-task' -Action 'DisableMonthlyUpdates' -InputText ('Y' + [Environment]::NewLine) -SeedOldTask
    $removeState = Read-TaskState -Path $removeTask.StatePath
    $removeState.Tasks = @($removeState.Tasks) + @([PSCustomObject]@{
        Path = '\OtherVendor\Unrelated Task'
        Xml = '<Task><RegistrationInfo><Description>Unrelated</Description></RegistrationInfo></Task>'
    })
    [System.IO.File]::WriteAllText($removeTask.StatePath, ($removeState | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    $removeResult = Invoke-Scenario -Scenario $removeTask
    $removeAfter = Read-TaskState -Path $removeTask.StatePath
    Assert-Condition -Condition ($removeResult.Output -match 'Removed the application-owned task') -Message 'Disable action removes the owned task after confirmation'
    Assert-Condition -Condition (@($removeAfter.Tasks | Where-Object { $_.Path -ceq '\myTech.Today\Monthly Application Updates' }).Count -eq 0) -Message 'Disable action removes the exact compatibility task path'
    Assert-Condition -Condition (@($removeAfter.Tasks | Where-Object { $_.Path -ceq '\OtherVendor\Unrelated Task' }).Count -eq 1) -Message 'Disable action preserves unrelated scheduled tasks'

    $scopedUpdate = New-Scenario -Name 'scoped-update' -Action 'Updater' -Mode updater -PackageIds 'Google.Chrome'
    $scopedUpdateResult = Invoke-Scenario -Scenario $scopedUpdate
    $scopedUpdateCalls = @(([string](Get-Content -LiteralPath $scopedUpdate.WingetTracePath -Raw)) -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition -Condition ($scopedUpdateResult.ExitCode -eq 0 -and $scopedUpdateCalls.Count -eq 1) -Message 'Scoped updater returns success for the selected package'
    Assert-Condition -Condition ($scopedUpdateCalls[0] -ceq 'upgrade|--id|Google.Chrome|--exact|--source|winget|--accept-source-agreements|--accept-package-agreements') -Message 'Scoped updater uses exact catalog identity and source argument ordering'

    $failedUpdate = New-Scenario -Name 'scoped-update-network-failure' -Action 'Updater' -Mode updater -PackageIds 'Google.Chrome' -WingetExitCode 23
    $failedUpdateResult = Invoke-Scenario -Scenario $failedUpdate
    Assert-Condition -Condition ($failedUpdateResult.ExitCode -eq 23 -and $failedUpdateResult.Output -match '\[FAILED\] Update outcome:' -and $failedUpdateResult.Output -match 'winget-exit-code=23' -and $failedUpdateResult.Output.Contains('Update status is incomplete. Some applications may remain out of date. Review the log and run a manual update check.')) -Message 'Scheduled updater preserves winget failure status in its outcome and process code'
    Assert-Condition -Condition ((Get-Content -LiteralPath $failedUpdate.WingetTracePath -Raw) -match '^upgrade\|--id\|Google\.Chrome\|--exact\|--source\|winget') -Message 'Network or package-manager failure does not widen the update scope'

    $invalidScope = New-Scenario -Name 'invalid-update-scope' -Action 'Updater' -Mode updater -PackageIds '--all'
    $invalidScopeResult = Invoke-Scenario -Scenario $invalidScope
    $invalidScopeCalls = @(([string](Get-Content -LiteralPath $invalidScope.WingetTracePath -Raw)) -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition -Condition ($invalidScopeResult.ExitCode -eq 2 -and $invalidScopeResult.Output -match 'No updates were started') -Message 'Invalid scoped input fails before package-manager execution'
    Assert-Condition -Condition ($invalidScopeCalls.Count -eq 0) -Message 'Invalid scope does not invoke winget'

    $cliText = Get-Content (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw
    $updaterText = Get-Content (Join-Path $repositoryRoot 'apps\winget-update.ps1') -Raw
    Assert-Condition -Condition ($cliText -notmatch '(?s)finally\s*\{[^}]*Install-MonthlyUpdateTask') -Message 'Task installation is not called from a finally block'
    Assert-Condition -Condition ($updaterText.Contains('New-WingetArgumentList') -and $updaterText -notmatch '(?im)winget\s+(update|upgrade)\s+--all') -Message 'Updater builds scoped arguments and has no unscoped all-package action'
    Write-Host (' ' + [Environment]::NewLine + "[OK] Monthly scheduling regression checks passed ($checkCount assertions).") -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $tempPrefix = $tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedTestRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
