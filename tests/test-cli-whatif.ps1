#Requires -Version 5.1

# Offline ShouldProcess regression checks. Package commands resolve only to a
# temporary fake winget.cmd, and scheduler calls are handled by trace stubs.
$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] CLI ShouldProcess integration checks require Windows command resolution.' -ForegroundColor Yellow
    exit 77
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-cli-whatif-' + [guid]::NewGuid().ToString('N'))))
$fakeBin = Join-Path $testRoot 'bin'
$tracePath = Join-Path $testRoot 'fake-winget-trace.txt'
$schedulerTracePath = Join-Path $testRoot 'fake-scheduler-trace.txt'
$profileRoot = Join-Path $testRoot 'user-profile'
$profilePath = Join-Path $testRoot 'preview-profile.json'
$installRoot = Join-Path $testRoot 'installer'
$updateScriptPath = Join-Path (Join-Path $installRoot 'apps') 'winget-update.ps1'
$checkCount = 0
$originalEnvironment = @{}
$environmentNames = @('PATH', 'PATHEXT', 'USERPROFILE', 'HOME', 'LOCALAPPDATA', 'APPDATA', 'TEMP', 'TMP', 'CLI_TRACE', 'FAKE_WINGET_EXIT_CODE', 'OS', 'APP_INSTALLER_RUNTIME_HANDOFF_PATH', 'APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT')

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

function Get-FunctionDefinitionText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
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

function Read-TraceLines {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    return @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

foreach ($name in $environmentNames) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $updateScriptPath) -Force | Out-Null
    [System.IO.File]::WriteAllText($tracePath, '', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($schedulerTracePath, '', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($updateScriptPath, '# test fixture only', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($profilePath, (@{ Version = '1.0'; Applications = @('Google Chrome') } | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

    $fakeWinget = @'
@echo off
if "%FAKE_WINGET_EXIT_CODE%"=="" set "FAKE_WINGET_EXIT_CODE=0"
>>"%CLI_TRACE%" echo winget %*
if "%FAKE_WINGET_EXIT_CODE%"=="0" (
  echo Successfully installed
) else (
  echo Installer failed with exit code %FAKE_WINGET_EXIT_CODE%
)
exit /b %FAKE_WINGET_EXIT_CODE%
'@
    [System.IO.File]::WriteAllLines((Join-Path $fakeBin 'winget.cmd'), [string[]]($fakeWinget -split "`r?`n"), [System.Text.Encoding]::ASCII)

    $env:PATH = $fakeBin + ';' + (Join-Path $env:SystemRoot 'System32')
    $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:LOCALAPPDATA = Join-Path $profileRoot 'AppData\Local'
    $env:APPDATA = Join-Path $profileRoot 'AppData\Roaming'
    $env:TEMP = $testRoot
    $env:TMP = $testRoot
    $env:CLI_TRACE = $tracePath
    $env:OS = 'Windows_NT'
    $env:FAKE_WINGET_EXIT_CODE = '0'

    # Run the real entrypoint in preview mode with an isolated user profile.
    # Mark this process as the validated runtime handoff so the test exercises
    # the requested engine instead of launching a second engine without mocks.
    $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = (Get-Process -Id $PID -ErrorAction Stop).Path
    $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = 'WindowsCli'
    $global:AppInstallerCliWhatIfOutput = @()
    function global:Write-Host {
        param([object]$Object, [object]$ForegroundColor, [object]$BackgroundColor, [switch]$NoNewline)
        $global:AppInstallerCliWhatIfOutput += [string]$Object
    }
    . $cliPath -Action InstallProfile -Profile $profilePath -WhatIf
    Remove-Item -LiteralPath 'Function:\Write-Host' -ErrorAction SilentlyContinue
    $entrypointOutput = $global:AppInstallerCliWhatIfOutput -join [Environment]::NewLine
    Remove-Variable -Name AppInstallerCliWhatIfOutput -Scope Global -ErrorAction SilentlyContinue
    Assert-Condition -Condition ($entrypointOutput -notmatch 'Fatal error' -and $entrypointOutput -match '\[PREVIEW\] Would install.*Google Chrome \[Google\.Chrome\]') -Message ("Profile -WhatIf reaches the CLI preview without an execution claim or fatal error. Output: {0}" -f $entrypointOutput)
    Assert-Condition -Condition ((Read-TraceLines -Path $tracePath).Count -eq 0) -Message 'CLI startup and profile preview made no package-manager calls.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $profileRoot 'myTech.Today'))) -Message 'CLI preview created no installed copy or log directory.'

    $app = @{ Name = 'Test Application'; ScriptName = 'missing-test-app.ps1'; WingetId = 'Example.TestApplication' }
    $testCategories = @([PSCustomObject]@{ Name = 'Test'; Group = @($app) })
    $update = [PSCustomObject]@{ Name = 'Test Application'; Id = 'Example.TestApplication'; CurrentVersion = '1.0'; AvailableVersion = '2.0' }
    $script:SystemInstallPath = $installRoot
    $script:AppsPath = Join-Path $repositoryRoot 'apps'
    $script:LogPath = $null
    $script:InstalledApps = @{ 'Test Application' = '1.0' }
    $script:ReadHostResponses = New-Object System.Collections.Queue
    $script:ReadHostCallCount = 0
    $script:DependencyCallCount = 0
    $script:SchedulerCallCount = 0
    $script:FakeTaskExists = $true
    $script:SchedulerTracePath = $schedulerTracePath

    function Read-Host {
        param([string]$Prompt)
        $script:ReadHostCallCount++
        if ($script:ReadHostResponses.Count -gt 0) {
            return [string]$script:ReadHostResponses.Dequeue()
        }
        return ''
    }
    function Read-KeySafe { }
    function Write-Log { param([string]$Message, [string]$Level) }
    function Test-WingetAvailable { return $true }
    function Safe-TestPath { param([string]$Path) return $false }
    function Get-PackageDependencies {
        param([string]$PackageId)
        $script:DependencyCallCount++
        return @()
    }
    function Get-InstalledApplications { return @{} }
    function Get-MonthlyUpdateTaskQuery {
        param([string]$TaskPath)
        $script:SchedulerCallCount++
        [System.IO.File]::AppendAllText($script:SchedulerTracePath, "query|$TaskPath`r`n")
        return [PSCustomObject]@{ Success = $true; Exists = $script:FakeTaskExists; XmlText = '<owned />'; Output = '' }
    }
    function Test-MonthlyUpdateTaskOwnership {
        param([string]$XmlText, [string]$UpdateScriptPath)
        return $true
    }
    function Invoke-TaskSchedulerCommand {
        param([string[]]$Arguments)
        $script:SchedulerCallCount++
        [System.IO.File]::AppendAllText($script:SchedulerTracePath, (($Arguments -join '|') + "`r`n"))
        if ($Arguments -contains '/Delete') { $script:FakeTaskExists = $false }
        return [PSCustomObject]@{ ExitCode = 0; Output = 'Fake scheduler success.' }
    }

    $installPreview = Install-Application -App $app -WhatIf
    $updatePreview = Update-Applications -Updates @($update) -WhatIf
    $uninstallPreview = Uninstall-Application -App $app -WhatIf
    $checkPreview = Check-ForUpdates -WhatIf
    $script:ReadHostResponses = New-Object System.Collections.Queue
    $script:ReadHostResponses.Enqueue('1')
    $enablePreview = Install-MonthlyUpdateTask -MenuData @{ MenuItems = @{ 1 = $app }; Categories = $testCategories } -WhatIf
    $disablePreview = Disable-MonthlyUpdateTask -WhatIf

    Assert-Condition -Condition ($installPreview.Status -eq 'Preview' -and $installPreview.Message -match 'Example\.TestApplication') -Message 'Install WhatIf identifies the package and returns Preview.'
    Assert-Condition -Condition ($updatePreview.PreviewCount -eq 1 -and $updatePreview.Results[0].Status -eq 'Preview' -and $updatePreview.Results[0].Message -match 'Example\.TestApplication') -Message 'Update WhatIf identifies the package and returns Preview.'
    Assert-Condition -Condition ($uninstallPreview.Status -eq 'Preview' -and $uninstallPreview.Message -match 'Example\.TestApplication') -Message 'Uninstall WhatIf identifies the package and returns Preview.'
    Assert-Condition -Condition ($checkPreview.Status -eq 'Preview') -Message 'Update discovery WhatIf returns Preview without querying winget.'
    Assert-Condition -Condition ($enablePreview.Status -eq 'Preview' -and $enablePreview.Message -match 'Example\.TestApplication' -and $enablePreview.Message -match '\\myTech\.Today\\Monthly Application Updates') -Message 'Enable-task WhatIf identifies its selected package scope and task target.'
    Assert-Condition -Condition ($disablePreview.Status -eq 'Preview' -and $disablePreview.Message -match '\\myTech\.Today\\Monthly Application Updates') -Message 'Disable-task WhatIf identifies the task target and returns Preview.'
    Assert-Condition -Condition ((Read-TraceLines -Path $tracePath).Count -eq 0 -and (Read-TraceLines -Path $schedulerTracePath).Count -eq 0 -and $script:DependencyCallCount -eq 0) -Message 'All dry-run package, dependency, and scheduler traces remain empty.'

    # Simulate ShouldProcess declining a request, then verify each mutation
    # function returns Skipped before asking the fake package manager to run.
    function Test-InstallerShouldProcess { param([string]$Target, [string]$Action) return $false }
    $declinedInstall = Install-Application -App $app
    $declinedUpdate = Update-Applications -Updates @($update)
    $declinedUninstall = Uninstall-Application -App $app
    Assert-Condition -Condition ($declinedInstall.Status -eq 'Skipped') -Message 'Declined install reports Skipped.'
    Assert-Condition -Condition ($declinedUpdate.SkippedCount -eq 1 -and $declinedUpdate.Results[0].Status -eq 'Skipped') -Message 'Declined update reports Skipped.'
    Assert-Condition -Condition ($declinedUninstall.Status -eq 'Skipped') -Message 'Declined uninstall reports Skipped.'
    Assert-Condition -Condition ((Read-TraceLines -Path $tracePath).Count -eq 0 -and $script:DependencyCallCount -eq 0) -Message 'Declined package actions made no package or dependency calls.'
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Test-InstallerShouldProcess')

    # Existing Y/N prompts remain in place. A decline returns before manager or
    # scheduler queries, and the fake prompts make the checks noninteractive.
    $script:ReadHostResponses = New-Object System.Collections.Queue
    $script:ReadHostResponses.Enqueue('N')
    $declinedSelectedInstall = Install-SelectedApplications -Apps @($app)
    Assert-Condition -Condition ($declinedSelectedInstall.Status -eq 'Skipped' -and (Read-TraceLines -Path $tracePath).Count -eq 0) -Message 'Declined selected install is skipped before package-manager status checks.'

    $script:ReadHostResponses = New-Object System.Collections.Queue
    $script:ReadHostResponses.Enqueue('1')
    $script:ReadHostResponses.Enqueue('N')
    $declinedEnable = Install-MonthlyUpdateTask -MenuData @{ MenuItems = @{ 1 = $app }; Categories = $testCategories }
    $script:ReadHostResponses = New-Object System.Collections.Queue
    $script:ReadHostResponses.Enqueue('N')
    $declinedDisable = Disable-MonthlyUpdateTask
    Assert-Condition -Condition ($declinedEnable.Status -eq 'Skipped' -and $declinedDisable.Status -eq 'Skipped') -Message 'Declined task enable and disable return Skipped.'
    Assert-Condition -Condition ((Read-TraceLines -Path $schedulerTracePath).Count -eq 0 -and $script:SchedulerCallCount -eq 0) -Message 'Declined task actions made no scheduler calls.'

    # Explicit -Confirm:$false is the noninteractive opt-in to perform an
    # action. It suppresses confirmation prompts while retaining fake-command
    # coverage for the selected package and scheduler targets.
    $script:ReadHostCallCount = 0
    $installCompleted = Install-Application -App $app -Confirm:$false
    $updateCompleted = Update-Applications -Updates @($update) -Confirm:$false
    $script:InstalledApps = @{ 'Test Application' = '1.0' }
    $uninstallCompleted = Uninstall-Application -App $app -Confirm:$false
    $disableCompleted = Disable-MonthlyUpdateTask -Confirm:$false
    $packageTrace = Read-TraceLines -Path $tracePath
    $schedulerTrace = Read-TraceLines -Path $schedulerTracePath
    Assert-Condition -Condition ($installCompleted -and $updateCompleted.SuccessCount -eq 1 -and $updateCompleted.Results[0].Status -eq 'Completed' -and $uninstallCompleted) -Message 'Noninteractive -Confirm:$false completes install, update, and uninstall through fake winget.'
    Assert-Condition -Condition (($packageTrace -match '^winget install ') -and ($packageTrace -match '^winget upgrade ') -and ($packageTrace -match '^winget uninstall ')) -Message 'Fake winget trace records the selected install, update, and uninstall commands.'
    Assert-Condition -Condition ($disableCompleted -and ($schedulerTrace -match '^query\|') -and ($schedulerTrace -match '^/Delete\|')) -Message 'Noninteractive -Confirm:$false disables only through the fake scheduler trace.'
    Assert-Condition -Condition ($script:ReadHostCallCount -eq 0) -Message 'Explicit noninteractive execution made no Read-Host confirmation calls.'

    $env:FAKE_WINGET_EXIT_CODE = '23'
    $failedInstall = Install-Application -App $app -Confirm:$false
    Assert-Condition -Condition ((Get-InstallerActionStatus -Result $failedInstall) -eq 'Failed') -Message 'A failed fake package command is reported as Failed, not Completed.'

    Write-Host "[OK] CLI WhatIf checks passed: $checkCount assertions." -ForegroundColor Green
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
