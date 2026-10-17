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
$oldArgumentCapture = $env:APP_SCRIPT_TEST_ARGUMENT_CAPTURE
$oldNativePath = $env:APP_SCRIPT_TEST_NATIVE_PATH
$oldNativeCode = $env:APP_SCRIPT_TEST_NATIVE_CODE
$oldNativeTrace = $env:APP_SCRIPT_TEST_NATIVE_TRACE

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

    $appsPath = Join-Path $testRoot 'apps'
    New-Item -ItemType Directory -Path $appsPath -Force | Out-Null
    $wrapperFixturePath = Join-Path $appsPath 'fixture.ps1'
    Write-Fixture -Path $wrapperFixturePath -Content @'
exit 0
'@
    $wrapperResult = Invoke-AppInstallation -AppScriptName 'fixture.ps1' -AppsPath $appsPath
    Assert-Condition ($wrapperResult.Status -eq 'PowerShellSuccess') 'Invoke-AppInstallation returns the shared explicit result contract'

    $afterUnrelatedAppState = ConvertTo-Json -InputObject $script:unrelatedAppState -Depth 5 -Compress
    Assert-Condition ($afterUnrelatedAppState -ceq $beforeUnrelatedAppState) 'unrelated installed-app and queue state remain unchanged'

    $guiSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer.ps1'))
    $cliSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer-cli.ps1'))
    Assert-Condition ($guiSource.Contains('Write-Log "Using custom script: $scriptPath"')) 'GUI custom-script log line remains present'
    Assert-Condition ($cliSource.Contains('Write-Log "Using custom script: $scriptPath"')) 'CLI custom-script log line remains present'
    Assert-Condition ($guiSource.Contains('elseif ($appScriptResult.Status -eq ''Unknown'')') -and $guiSource.Contains('[UNKNOWN] $unknownMessage')) 'GUI reports an unknown result without marking the app installed'
    Assert-Condition ($cliSource.Contains('elseif ($appScriptResult.Status -eq ''Unknown'')') -and $cliSource.Contains('[2/2] [UNKNOWN] $unknownMessage')) 'CLI reports an unknown result without marking the app installed'
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
    Remove-Module -Name AppInstallerCore -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTempTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTempTestRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTempTestRoot -Recurse -Force
        }
    }
}
