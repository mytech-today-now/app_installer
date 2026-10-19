# Offline CLI runtime handoff checks for the supported Windows engines.
# The profile preview uses a disposable path and a fake package manager.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] CLI runtime handoff checks require Windows process and path behavior.' -ForegroundColor Yellow
    exit 0
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$runtimeModulePath = Join-Path (Join-Path $repositoryRoot 'modules') 'InstallerRuntimeDiscovery.psm1'
$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$engineName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$enginePath = Join-Path $PSHOME $engineName
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-cli-handoff 雪 ' + [guid]::NewGuid().ToString('N'))))
$checkCount = 0

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "The current PowerShell engine executable was not found at $enginePath."
}
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

function Invoke-CliScenario {
    param(
        [Parameter(Mandatory = $true)][string[]]$ScriptArguments,
        [Parameter(Mandatory = $true)][string]$UserRoot,
        [Parameter(Mandatory = $true)][string]$TracePath
    )

    $processArguments = @('-NoProfile', '-File', $cliPath) + @($ScriptArguments)
    $quotedArguments = @($processArguments | ForEach-Object {
            ConvertTo-InstallerRuntimeWindowsArgument -Argument ([string]$_)
        })
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $enginePath
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.WorkingDirectory = $testRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $environment = $startInfo.EnvironmentVariables
    $environment['USERPROFILE'] = $UserRoot
    $environment['HOME'] = $UserRoot
    $environment['APPDATA'] = Join-Path $UserRoot 'AppData\Roaming'
    $environment['LOCALAPPDATA'] = Join-Path $UserRoot 'AppData\Local'
    $environment['TEMP'] = $testRoot
    $environment['TMP'] = $testRoot
    $environment['CLI_TRACE'] = $TracePath
    $environment['APP_INSTALLER_RUNTIME_HANDOFF_PATH'] = ''
    $environment['APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT'] = ''
    $environment['PATH'] = (Join-Path $testRoot 'bin') + ';' + (Join-Path $env:SystemRoot 'System32')
    $environment['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'The isolated CLI process did not start.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(90000)) {
            try { $process.Kill() } catch {}
            throw 'The isolated CLI process exceeded 90 seconds.'
        }
        $process.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = [int]$process.ExitCode
            Output = [string]$stdoutTask.GetAwaiter().GetResult()
            Error = [string]$stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop

try {
    $fakeBin = Join-Path $testRoot 'bin'
    $userRoot = Join-Path $testRoot 'user profile 雪'
    $profileDirectory = Join-Path $testRoot 'profiles with spaces 雪'
    $relativeProfilePath = Join-Path 'profiles with spaces 雪' 'preview profile 雪.json'
    $profilePath = Join-Path $testRoot $relativeProfilePath
    $tracePath = Join-Path $testRoot 'fake-winget-trace.txt'
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $profilePath,
        (@{ Version = '1.0'; Applications = @('Google Chrome') } | ConvertTo-Json -Depth 4),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $fakeWinget = @'
@echo off
>>"%CLI_TRACE%" echo winget %*
exit /b 23
'@
    [System.IO.File]::WriteAllLines((Join-Path $fakeBin 'winget.cmd'), [string[]]($fakeWinget -split "`r?`n"), [System.Text.Encoding]::ASCII)

    $valid = Invoke-CliScenario -ScriptArguments @('-Action', 'InstallProfile', '-Profile', $relativeProfilePath, '-WhatIf') -UserRoot $userRoot -TracePath $tracePath
    Assert-Condition -Condition ($valid.ExitCode -eq 0) -Message 'CLI preview returns a clean child process exit code through the runtime path'
    Assert-Condition -Condition ($valid.Output.Contains('Application Installer - CLI Mode')) -Message 'CLI standard output reaches the parent host after runtime handoff'
    Assert-Condition -Condition ($valid.Output -match 'Found 1 valid application\(s\)' -and $valid.Output -notmatch 'Profile file not found') -Message 'CLI opens a Unicode profile path with spaces relative to the inherited working directory'
    Assert-Condition -Condition ($valid.Output -match '\[PREVIEW\] Would install.*Google Chrome \[Google\.Chrome\]') -Message 'CLI preserves the profile selection and WhatIf result across the runtime path'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) -Message 'CLI WhatIf does not launch the fake package manager'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $userRoot 'myTech.Today'))) -Message 'CLI WhatIf does not copy files or create its installed tree'

    $malformedProfilePath = Join-Path $profileDirectory 'malformed profile 雪.json'
    [System.IO.File]::WriteAllText($malformedProfilePath, '{ "Version": "1.0", "Applications": [ }', (New-Object System.Text.UTF8Encoding($false)))
    $malformedRelativePath = Join-Path 'profiles with spaces 雪' 'malformed profile 雪.json'
    $malformed = Invoke-CliScenario -ScriptArguments @('-Action', 'InstallProfile', '-Profile', $malformedRelativePath, '-WhatIf') -UserRoot $userRoot -TracePath $tracePath
    Assert-Condition -Condition ($malformed.Output -match 'Failed to import profile') -Message 'Malformed profile JSON is reported without a cross-engine parser failure'
    Assert-Condition -Condition ($malformed.Output -notmatch '\[PREVIEW\] Would install') -Message 'Malformed profile data does not select or install applications'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) -Message 'Malformed profile handling does not launch the fake package manager'

    $childScriptPath = Join-Path $testRoot 'runtime child 雪.ps1'
    $runtimeDriverPath = Join-Path $testRoot 'runtime driver 雪.ps1'
    $childScript = @'
param([string]$Value, [string]$ExpectedWorkingDirectory)
$stdinValue = [Console]::In.ReadLine()
$workingDirectoryMatches = [System.StringComparer]::OrdinalIgnoreCase.Equals([System.IO.Directory]::GetCurrentDirectory(), $ExpectedWorkingDirectory)
[Console]::Out.WriteLine(('CHILD_STDOUT=' + $Value))
[Console]::Out.WriteLine(('CHILD_CWD_MATCH=' + $workingDirectoryMatches))
[Console]::Error.WriteLine(('CHILD_STDERR=' + $Value))
[Console]::Out.WriteLine(('CHILD_STDIN=' + $stdinValue))
if (-not $workingDirectoryMatches) { exit 23 }
exit 37
'@
    $runtimeDriver = @'
$ErrorActionPreference = 'Continue'
Import-Module -Name $env:APP_INSTALLER_COMPAT_MODULE -Force -DisableNameChecking
Import-Module -Name $env:APP_INSTALLER_RUNTIME_MODULE -Force -DisableNameChecking
$engineName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$enginePath = Join-Path $PSHOME $engineName
$engineRecord = [PSCustomObject]@{ Engine = [string]$PSVersionTable.PSEdition; Path = $enginePath; Source = 'Test'; Priority = 1 }
$probeResult = [PSCustomObject]@{
    Success = $true
    TimedOut = $false
    PolicyBlocked = $false
    Reason = ''
    Probe = [PSCustomObject]@{
        Version = [string]$PSVersionTable.PSVersion
        Edition = [string]$PSVersionTable.PSEdition
        ProcessArchitecture = 'X64'
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
        ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
        FormsAvailable = $false
        FormsMajor = 0
        DrawingMajor = 0
    }
}
$probeInvoker = { param($Candidate, $Component, $ApplicationPath, $TimeoutSeconds) $probeResult }
$scriptArguments = @('-Value', 'stream value', '-ExpectedWorkingDirectory', [System.IO.Directory]::GetCurrentDirectory())
$result = Invoke-InstallerRuntimeEntry -Component WindowsCli -ApplicationPath $env:APP_INSTALLER_CHILD_SCRIPT -ScriptArguments $scriptArguments -CandidateRecords @($engineRecord) -AllowTestCandidates -AlwaysLaunchApplication -ProbeInvoker $probeInvoker
Write-Output ('RUNTIME_CHILD_EXIT=' + $result.ExitCode)
exit ([int]$result.ExitCode)
'@
    [System.IO.File]::WriteAllText($childScriptPath, $childScript, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($runtimeDriverPath, $runtimeDriver, (New-Object System.Text.UTF8Encoding($false)))
    $runtimeDriverArguments = @('-NoProfile', '-File', $runtimeDriverPath)
    $quotedDriverArguments = @($runtimeDriverArguments | ForEach-Object {
            ConvertTo-InstallerRuntimeWindowsArgument -Argument ([string]$_)
        })
    $runtimeStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $runtimeStartInfo.FileName = $enginePath
    $runtimeStartInfo.Arguments = $quotedDriverArguments -join ' '
    $runtimeStartInfo.WorkingDirectory = $testRoot
    $runtimeStartInfo.UseShellExecute = $false
    $runtimeStartInfo.CreateNoWindow = $true
    $runtimeStartInfo.RedirectStandardInput = $true
    $runtimeStartInfo.RedirectStandardOutput = $true
    $runtimeStartInfo.RedirectStandardError = $true
    $runtimeEnvironment = $runtimeStartInfo.EnvironmentVariables
    $runtimeEnvironment['APP_INSTALLER_COMPAT_MODULE'] = Join-Path (Join-Path $repositoryRoot 'modules') 'InstallerCompatibility.psm1'
    $runtimeEnvironment['APP_INSTALLER_RUNTIME_MODULE'] = $runtimeModulePath
    $runtimeEnvironment['APP_INSTALLER_CHILD_SCRIPT'] = $childScriptPath
    $runtimeEnvironment['APP_INSTALLER_RUNTIME_HANDOFF_PATH'] = ''
    $runtimeEnvironment['APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT'] = ''
    $runtimeProcess = New-Object System.Diagnostics.Process
    $runtimeProcess.StartInfo = $runtimeStartInfo
    try {
        if (-not $runtimeProcess.Start()) {
            throw 'The runtime stream-forwarding process did not start.'
        }
        $runtimeStdoutTask = $runtimeProcess.StandardOutput.ReadToEndAsync()
        $runtimeStderrTask = $runtimeProcess.StandardError.ReadToEndAsync()
        $runtimeProcess.StandardInput.WriteLine('stream input')
        $runtimeProcess.StandardInput.Close()
        if (-not $runtimeProcess.WaitForExit(90000)) {
            try { $runtimeProcess.Kill() } catch {}
            throw 'The runtime stream-forwarding process exceeded 90 seconds.'
        }
        $runtimeProcess.WaitForExit()
        $runtimeStdout = [string]$runtimeStdoutTask.GetAwaiter().GetResult()
        $runtimeStderr = [string]$runtimeStderrTask.GetAwaiter().GetResult()
        Assert-Condition -Condition ($runtimeProcess.ExitCode -eq 37 -and $runtimeStdout.Contains('RUNTIME_CHILD_EXIT=37')) -Message 'Runtime handoff preserves the child process exit code'
        Assert-Condition -Condition ($runtimeStdout.Contains('CHILD_STDOUT=stream value')) -Message 'Runtime handoff forwards the child standard output'
        Assert-Condition -Condition ($runtimeStderr.Contains('CHILD_STDERR=stream value')) -Message 'Runtime handoff forwards the child standard error'
        Assert-Condition -Condition ($runtimeStdout.Contains('CHILD_STDIN=stream input')) -Message 'Runtime handoff forwards standard input to the child'
        Assert-Condition -Condition ($runtimeStdout.Contains('CHILD_CWD_MATCH=True')) -Message 'Runtime handoff preserves the current working directory and spaced child path'
    }
    finally {
        $runtimeProcess.Dispose()
    }

    Write-Host "[OK] CLI runtime handoff checks passed ($checkCount assertions) under PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Green
}
finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
    $tempPrefix = $tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
