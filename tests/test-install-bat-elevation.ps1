#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$helperPath = Join-Path $repoRoot 'invoke-elevated-install.ps1'
$batchPath = Join-Path $repoRoot 'install.bat'
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }

    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-TestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Get-TestOutput {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [System.IO.File]::ReadAllText($Path)
    }
    return ''
}

function Invoke-BatchScenario {
    param(
        [Parameter(Mandatory = $true)][string]$TestRoot,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RawArguments,
        [Parameter(Mandatory = $true)][string]$Mode,
        [int]$ExitCode = 0,
        [switch]$Delayed
    )

    $runnerPath = Join-Path $TestRoot ($Name + '.bat')
    $testBatchPath = Join-Path $TestRoot 'install.bat'
    $testHelperPath = Join-Path $TestRoot 'invoke-elevated-install.ps1'
    $outputPath = Join-Path $TestRoot ($Name + '-output.txt')
    $statusPath = Join-Path $TestRoot ($Name + '-status.txt')
    $argumentLogPath = Join-Path $TestRoot ($Name + '-launcher-arguments.txt')
    $wingetLogPath = Join-Path $TestRoot ($Name + '-winget-invoked.txt')
    $argumentSuffix = if ($RawArguments.Length -gt 0) { ' ' + $RawArguments } else { '' }
    $runner = @"
@echo off
call "$testBatchPath"$argumentSuffix >> "$outputPath" 2>&1
exit /b %ERRORLEVEL%
"@
    Write-TestFile -Path $runnerPath -Content $runner

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = '/d /c ""' + $runnerPath + '""'
    $processInfo.WorkingDirectory = $TestRoot
    $processInfo.UseShellExecute = $false
    $processInfo.EnvironmentVariables['PATH'] = $TestRoot + ';' + $env:SystemRoot + '\System32'
    $processInfo.EnvironmentVariables['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'
    $processInfo.EnvironmentVariables['FAKE_MODE'] = $Mode
    $processInfo.EnvironmentVariables['FAKE_EXIT_CODE'] = [string]$ExitCode
    $processInfo.EnvironmentVariables['FAKE_DELAYED'] = [string][int]$Delayed.IsPresent
    $processInfo.EnvironmentVariables['FAKE_ARG_LOG'] = $argumentLogPath
    $processInfo.EnvironmentVariables['FAKE_OUTPUT_LOG'] = $outputPath
    $processInfo.EnvironmentVariables['FAKE_STATUS_LOG'] = $statusPath
    $processInfo.EnvironmentVariables['FAKE_WINGET_LOG'] = $wingetLogPath
    $processInfo.EnvironmentVariables['FAKE_IS_ELEVATED'] = ''
    $processInfo.EnvironmentVariables['TEMP'] = $TestRoot
    $processInfo.EnvironmentVariables['TMP'] = $TestRoot
    $processInfo.EnvironmentVariables['ProgramFiles'] = $TestRoot
    $processInfo.EnvironmentVariables['ProgramFiles(x86)'] = $TestRoot
    $processInfo.EnvironmentVariables['ProgramW6432'] = $TestRoot
    $processInfo.EnvironmentVariables['LocalAppData'] = $TestRoot

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Could not start the isolated cmd.exe scenario '$Name'."
    }

    if ($Delayed) {
        $startDeadline = [DateTime]::UtcNow.AddSeconds(10)
        $statusBeforeExit = ''
        while ([DateTime]::UtcNow -lt $startDeadline) {
            $statusBeforeExit = Get-TestOutput -Path $statusPath
            if ($process.HasExited -or $statusBeforeExit -match '(?i)FAKE CHILD STARTED') {
                break
            }
            Start-Sleep -Milliseconds 50
        }
        if ($process.HasExited -or $statusBeforeExit -match '(?i)Setup complete\.' -or $statusBeforeExit -notmatch '(?i)FAKE CHILD STARTED') {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            throw "The delayed '$Name' scenario returned or announced completion before the fake child finished."
        }
    }

    if (-not $process.WaitForExit(20000)) {
        $outputAtTimeout = Get-TestOutput -Path $outputPath
        $process.Kill()
        throw "The isolated cmd.exe scenario '$Name' did not exit within 20 seconds. Output so far: $($outputAtTimeout.Trim())"
    }

    $argumentLog = @()
    if (Test-Path -LiteralPath $argumentLogPath -PathType Leaf) {
        $argumentLog = [System.IO.File]::ReadAllLines($argumentLogPath)
    }
    $result = [PSCustomObject]@{
        ExitCode       = $process.ExitCode
        Output         = Get-TestOutput -Path $outputPath
        ArgumentLog    = $argumentLog
        WingetInvoked  = Test-Path -LiteralPath $wingetLogPath -PathType Leaf
        RunnerPath     = $runnerPath
        BatchPath      = $testBatchPath
        HelperPath     = $testHelperPath
    }
    $process.Dispose()
    return $result
}

function Invoke-HelperScenario {
    param(
        [Parameter(Mandatory = $true)][string]$TestRoot,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$HelperCopy,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [int]$ChildExitCode = 0,
        [int]$ChildDelaySeconds = 0,
        [string]$StartMode = 'normal',
        [switch]$CheckDelayedWait
    )

    $childLogPath = Join-Path $TestRoot ($Name + '-child-arguments.txt')
    $childOutputPath = Join-Path $TestRoot ($Name + '-child-output.txt')
    $childBatchPath = Join-Path $TestRoot ($Name + '-child.bat')
    $runnerPath = Join-Path $TestRoot ($Name + '-helper-runner.ps1')

    $childBatch = @"
@echo off
setlocal DisableDelayedExpansion
> "$childLogPath" echo(%*
> "$childOutputPath" echo(FAKE CHILD STARTED
if not "%FAKE_CHILD_DELAY_SECONDS%"=="0" timeout /t %FAKE_CHILD_DELAY_SECONDS% /nobreak >nul
if "%FAKE_CHILD_EXIT_CODE%"=="0" >> "$childOutputPath" echo(Setup complete.
if not "%FAKE_CHILD_EXIT_CODE%"=="0" >> "$childOutputPath" echo(FAKE CHILD EXIT CODE %FAKE_CHILD_EXIT_CODE%
>> "$childOutputPath" echo(FAKE CHILD FINISHED
exit /b %FAKE_CHILD_EXIT_CODE%
"@
    Write-TestFile -Path $childBatchPath -Content $childBatch

    $runner = @'
function Start-Process {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$Verb,
        [switch]$PassThru
    )

    if ($Verb -ne 'RunAs' -or -not $PassThru) {
        throw 'The helper did not request a pass-through RunAs process.'
    }
    if ($env:FAKE_START_MODE -eq 'cancel') {
        throw ([System.ComponentModel.Win32Exception]::new(1223))
    }
    if ($env:FAKE_START_MODE -eq 'fail') {
        throw ([System.IO.FileNotFoundException]::new('Simulated elevated child launch failure.'))
    }

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $FilePath
    $processInfo.Arguments = if ($null -eq $ArgumentList) { '' } else { $ArgumentList }
    $processInfo.UseShellExecute = $true
    return [System.Diagnostics.Process]::Start($processInfo)
}

$forwardedArguments = @((ConvertFrom-Json -InputObject $env:FAKE_ARGUMENTS_JSON))
. $env:FAKE_HELPER_PATH
$helperArguments = @($env:FAKE_CHILD_BATCH_PATH) + $forwardedArguments
$helperExitCode = Invoke-ElevatedInstall -Arguments $helperArguments
exit $helperExitCode
'@
    Write-TestFile -Path $runnerPath -Content $runner

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $processInfo.Arguments = '-NoProfile -File "' + $runnerPath + '"'
    $processInfo.WorkingDirectory = $TestRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.EnvironmentVariables['FAKE_HELPER_PATH'] = $HelperCopy
    $processInfo.EnvironmentVariables['FAKE_CHILD_BATCH_PATH'] = $childBatchPath
    $processInfo.EnvironmentVariables['FAKE_ARGUMENTS_JSON'] = ConvertTo-Json -InputObject @($Arguments) -Compress
    $processInfo.EnvironmentVariables['FAKE_CHILD_DELAY_SECONDS'] = [string]$ChildDelaySeconds
    $processInfo.EnvironmentVariables['FAKE_CHILD_EXIT_CODE'] = [string]$ChildExitCode
    $processInfo.EnvironmentVariables['FAKE_CHILD_ARGS_LOG'] = $childLogPath
    $processInfo.EnvironmentVariables['FAKE_CHILD_OUTPUT_LOG'] = $childOutputPath
    $processInfo.EnvironmentVariables['FAKE_START_MODE'] = $StartMode

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Could not start the isolated PowerShell helper scenario '$Name'."
    }

    if ($CheckDelayedWait) {
        $startDeadline = [DateTime]::UtcNow.AddSeconds(10)
        $childOutputBeforeExit = ''
        while ([DateTime]::UtcNow -lt $startDeadline) {
            $childOutputBeforeExit = Get-TestOutput -Path $childOutputPath
            if ($process.HasExited -or $childOutputBeforeExit -match '(?i)FAKE CHILD STARTED') {
                break
            }
            Start-Sleep -Milliseconds 50
        }
        if ($process.HasExited -or $childOutputBeforeExit -match '(?i)Setup complete\.' -or $childOutputBeforeExit -notmatch '(?i)FAKE CHILD STARTED') {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            throw 'The helper returned or announced completion before the delayed child finished.'
        }
    }

    if (-not $process.WaitForExit(20000)) {
        $process.Kill()
        throw "The isolated PowerShell helper scenario '$Name' did not exit within 20 seconds."
    }

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $result = [PSCustomObject]@{
        ExitCode       = $process.ExitCode
        Output         = $standardOutput + $standardError
        ChildArguments = Get-TestOutput -Path $childLogPath
        ChildOutput    = Get-TestOutput -Path $childOutputPath
        RunnerPath     = $runnerPath
    }
    $process.Dispose()
    return $result
}

try {
    if ($env:OS -ne 'Windows_NT' -or -not (Get-Command cmd.exe -ErrorAction SilentlyContinue) -or -not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        Write-Host '[SKIP] Elevation handoff integration requires Windows cmd.exe and pwsh.exe.' -ForegroundColor Yellow
        exit 0
    }

    $batch = Get-Content -Raw -LiteralPath $batchPath
    $helper = Get-Content -Raw -LiteralPath $helperPath
    Assert-Condition -Condition ($batch -match '(?s)powershell\s+-NoProfile\s+-File[^\r\n]*invoke-elevated-install\.ps1[^\r\n]*%\*') -Message 'The elevated wrapper invokes the helper through direct -File and forwards the original argument tail.'
    Assert-Condition -Condition ($batch -match '(?i)exit /b !ELEVATION_RC!' -and $batch -match '(?i)9009') -Message 'The unelevated wrapper returns the helper exit status and reports a missing PowerShell launcher.'
    Assert-Condition -Condition ($helper -match "Verb\s+=\s+'RunAs'" -and $helper -match 'PassThru\s+=\s+\$true' -and $helper -match 'WaitForExit\(\$timeoutMilliseconds\)') -Message 'The helper requests RunAs, retains the process handle, and has a bounded wait.'
    Assert-Condition -Condition ($helper -notmatch '(?i)ExecutionPolicy\s+Bypass|Set-ExecutionPolicy') -Message 'The elevation helper does not weaken execution policy or write policy settings.'

    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app installer elevation test ' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null

    try {
        $testBatchPath = Join-Path $testRoot 'install.bat'
        Copy-Item -LiteralPath $batchPath -Destination $testBatchPath
        Copy-Item -LiteralPath $helperPath -Destination (Join-Path $testRoot 'invoke-elevated-install.ps1')
        Write-TestFile -Path (Join-Path $testRoot 'app-installer.ps1') -Content '# Offline placeholder; the elevation harness never launches this installer.'

        $csharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $csharpCompiler -PathType Leaf)) {
            $csharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
        }
        if (-not (Test-Path -LiteralPath $csharpCompiler -PathType Leaf)) {
            throw 'The offline fake launcher harness requires the installed .NET Framework C# compiler.'
        }

        $fakeLauncherSourcePath = Join-Path $testRoot 'fake-launchers.cs'
        $fakeLauncherOutputPath = Join-Path $testRoot 'fake-launchers.exe'
        $fakeLauncherSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

public static class FakeLaunchers
{
    public static int Main(string[] args)
    {
        string executablePath = Process.GetCurrentProcess().MainModule.FileName;
        string executableName = Path.GetFileNameWithoutExtension(executablePath);
        string mode = Environment.GetEnvironmentVariable("FAKE_MODE") ?? "";

        if (String.Equals(executableName, "net", StringComparison.OrdinalIgnoreCase))
        {
            return Environment.GetEnvironmentVariable("FAKE_IS_ELEVATED") == "1" ? 0 : 1;
        }

        if (String.Equals(executableName, "winget", StringComparison.OrdinalIgnoreCase))
        {
            string logPath = Environment.GetEnvironmentVariable("FAKE_WINGET_LOG");
            if (!String.IsNullOrEmpty(logPath)) File.WriteAllText(logPath, "FAKE_WINGET_ONLY");
            return 23;
        }

        string argumentLog = Environment.GetEnvironmentVariable("FAKE_ARG_LOG");
        if (!String.IsNullOrEmpty(argumentLog)) File.WriteAllLines(argumentLog, args, Encoding.UTF8);

        if (mode == "launcher-missing")
        {
            Console.WriteLine("[ERROR] Simulated missing PowerShell launcher.");
            return 9009;
        }

        if (mode == "missing-pwsh")
        {
            Console.WriteLine("[FAKE] Starting the elevated wrapper with PowerShell 7 still missing.");
            if (args.Length < 4) return 91;

            var childInfo = new ProcessStartInfo();
            childInfo.FileName = Environment.GetEnvironmentVariable("ComSpec");
            childInfo.Arguments = "/d /c \"\"" + args[3] + "\"\"";
            childInfo.WorkingDirectory = Path.GetDirectoryName(args[3]);
            childInfo.UseShellExecute = false;
            childInfo.RedirectStandardInput = true;
            childInfo.EnvironmentVariables["FAKE_IS_ELEVATED"] = "1";

            using (Process child = Process.Start(childInfo))
            {
                child.StandardInput.WriteLine();
                child.StandardInput.Close();
                if (!child.WaitForExit(20000)) return 92;
                return child.ExitCode;
            }
        }

        Console.WriteLine("[FAKE] Elevated installer started.");
        if (mode == "delayed-success")
        {
            string statusLog = Environment.GetEnvironmentVariable("FAKE_STATUS_LOG");
            if (!String.IsNullOrEmpty(statusLog)) File.WriteAllText(statusLog, "FAKE CHILD STARTED");
            Thread.Sleep(5000);
            if (!String.IsNullOrEmpty(statusLog)) File.AppendAllText(statusLog, "\r\nSetup complete.");
        }
        if (mode == "cancel")
        {
            Console.WriteLine("[ERROR] Administrator elevation was declined or canceled.");
            return 1223;
        }
        if (mode == "nonzero")
        {
            Console.WriteLine("[ERROR] Fake elevated installer exited with code 23.");
            return 23;
        }
        if (mode == "success" || mode == "delayed-success")
        {
            Console.WriteLine("Setup complete.");
            return 0;
        }

        return 91;
    }
}
'@
        Write-TestFile -Path $fakeLauncherSourcePath -Content $fakeLauncherSource
        $compilerInfo = New-Object System.Diagnostics.ProcessStartInfo
        $compilerInfo.FileName = $csharpCompiler
        $compilerInfo.Arguments = '/nologo /target:exe /out:"' + $fakeLauncherOutputPath + '" "' + $fakeLauncherSourcePath + '"'
        $compilerInfo.WorkingDirectory = $testRoot
        $compilerInfo.UseShellExecute = $false
        $compilerInfo.RedirectStandardOutput = $true
        $compilerInfo.RedirectStandardError = $true
        $compilerProcess = [System.Diagnostics.Process]::Start($compilerInfo)
        if (-not $compilerProcess.WaitForExit(20000)) {
            $compilerProcess.Kill()
            throw 'The isolated fake-launcher C# compile did not finish within 20 seconds.'
        }
        $compilerOutput = $compilerProcess.StandardOutput.ReadToEnd() + $compilerProcess.StandardError.ReadToEnd()
        if ($compilerProcess.ExitCode -ne 0) {
            throw ("Could not compile the isolated fake launchers: {0}" -f $compilerOutput)
        }
        $compilerProcess.Dispose()

        Copy-Item -LiteralPath $fakeLauncherOutputPath -Destination (Join-Path $testRoot 'powershell.exe')
        Copy-Item -LiteralPath $fakeLauncherOutputPath -Destination (Join-Path $testRoot 'net.exe')
        Copy-Item -LiteralPath $fakeLauncherOutputPath -Destination (Join-Path $testRoot 'winget.exe')

        $scenarioCases = @(
            [PSCustomObject]@{ Name = 'no-arguments'; Arguments = ''; Mode = 'success'; ExitCode = 0; ExpectedExtra = @() },
            [PSCustomObject]@{ Name = 'spaces'; Arguments = '--profile "Design Review"'; Mode = 'success'; ExitCode = 0; ExpectedExtra = @('--profile', 'Design Review') },
            [PSCustomObject]@{ Name = 'quoted-path'; Arguments = '--source "C:\Program Files\Editor Tools\profile.json"'; Mode = 'success'; ExitCode = 0; ExpectedExtra = @('--source', 'C:\Program Files\Editor Tools\profile.json') },
            [PSCustomObject]@{ Name = 'mixed-switches'; Arguments = '/silent --profile "Studio Mode" -Destination "D:\Saved Profiles\Work"'; Mode = 'success'; ExitCode = 0; ExpectedExtra = @('/silent', '--profile', 'Studio Mode', '-Destination', 'D:\Saved Profiles\Work') }
        )

        foreach ($scenarioCase in $scenarioCases) {
            $result = Invoke-BatchScenario -TestRoot $testRoot -Name $scenarioCase.Name -RawArguments $scenarioCase.Arguments -Mode $scenarioCase.Mode -ExitCode $scenarioCase.ExitCode
            $expectedArguments = @('-NoProfile', '-File', $result.HelperPath, $result.BatchPath) + @($scenarioCase.ExpectedExtra)
            $receivedArguments = @($result.ArgumentLog)
            Assert-Condition -Condition ($result.ExitCode -eq 0 -and (($receivedArguments -join '|') -eq ($expectedArguments -join '|'))) -Message ("The {0} case preserves argv boundaries (exit {1}; expected [{2}], received [{3}]; output: {4})." -f $scenarioCase.Name, $result.ExitCode, ($expectedArguments -join '|'), ($receivedArguments -join '|'), $result.Output.Trim())
            Assert-Condition -Condition ($result.Output -match '(?i)Setup complete\.' -and -not $result.WingetInvoked) -Message ("The {0} fake child completed without invoking a real package manager." -f $scenarioCase.Name)
        }

        $delayedResult = Invoke-BatchScenario -TestRoot $testRoot -Name 'delayed-child' -RawArguments '--profile "Slow Setup"' -Mode 'delayed-success' -ExitCode 0 -Delayed
        Assert-Condition -Condition ($delayedResult.ExitCode -eq 0 -and $delayedResult.Output -match '(?i)Setup complete\.') -Message 'The wrapper remains active until a delayed fake elevated child finishes.'

        $nonzeroResult = Invoke-BatchScenario -TestRoot $testRoot -Name 'child-nonzero' -RawArguments '/quiet' -Mode 'nonzero' -ExitCode 23
        Assert-Condition -Condition ($nonzeroResult.ExitCode -eq 23 -and $nonzeroResult.Output -match '(?i)exit code 23' -and $nonzeroResult.Output -notmatch '(?i)Setup complete\.') -Message 'A nonzero elevated child result is visible, propagated exactly, and never reports setup success.'

        $cancelResult = Invoke-BatchScenario -TestRoot $testRoot -Name 'uac-canceled' -RawArguments '' -Mode 'cancel' -ExitCode 1223
        Assert-Condition -Condition ($cancelResult.ExitCode -eq 1223 -and $cancelResult.Output -match '(?i)elevation was declined or canceled' -and $cancelResult.Output -notmatch '(?i)Setup complete\.') -Message 'A declined elevation is visible and returns a nonzero status.'

        $missingLauncherResult = Invoke-BatchScenario -TestRoot $testRoot -Name 'missing-powershell-launcher' -RawArguments '' -Mode 'launcher-missing' -ExitCode 9009
        Assert-Condition -Condition ($missingLauncherResult.ExitCode -eq 9009 -and $missingLauncherResult.Output -match '(?i)Windows PowerShell could not be started' -and $missingLauncherResult.Output -notmatch '(?i)Setup complete\.') -Message 'A missing PowerShell launcher is visible and never returns success.'

        $missingPwshResult = Invoke-BatchScenario -TestRoot $testRoot -Name 'missing-pwsh-after-elevation' -RawArguments '' -Mode 'missing-pwsh' -ExitCode 1
        Assert-Condition -Condition ($missingPwshResult.ExitCode -eq 1 -and $missingPwshResult.Output -match '(?i)Failed to install PowerShell 7' -and $missingPwshResult.WingetInvoked -and $missingPwshResult.Output -notmatch '(?i)Setup complete\.') -Message 'A simulated elevated bootstrap with missing PowerShell 7 reports its failed child result.'

        $testHelperCopy = Join-Path $testRoot 'invoke-elevated-install.ps1'
        Copy-Item -LiteralPath $helperPath -Destination $testHelperCopy

        $helperNoArguments = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-no-arguments' -HelperCopy $testHelperCopy -Arguments @()
        Assert-Condition -Condition ($helperNoArguments.ExitCode -eq 0 -and $helperNoArguments.ChildArguments.TrimEnd("`r", "`n") -eq '') -Message 'The helper preserves an empty argument list and returns the child success code.'

        $helperArgumentCases = @(
            [PSCustomObject]@{ Name = 'helper-spaces'; Arguments = @('--profile', 'Design Review'); Expected = '--profile "Design Review"' },
            [PSCustomObject]@{ Name = 'helper-quoted-path'; Arguments = @('--source', 'C:\Program Files\Editor Tools\profile.json'); Expected = '--source "C:\Program Files\Editor Tools\profile.json"' },
            [PSCustomObject]@{ Name = 'helper-mixed-switches'; Arguments = @('/silent', '--profile', 'Studio Mode', '-Destination', 'D:\Saved Profiles\Work'); Expected = '/silent --profile "Studio Mode" -Destination "D:\Saved Profiles\Work"' }
        )
        foreach ($argumentCase in $helperArgumentCases) {
            $helperResult = Invoke-HelperScenario -TestRoot $testRoot -Name $argumentCase.Name -HelperCopy $testHelperCopy -Arguments $argumentCase.Arguments
            Assert-Condition -Condition ($helperResult.ExitCode -eq 0 -and $helperResult.ChildArguments.TrimEnd("`r", "`n") -eq $argumentCase.Expected) -Message ("The helper reconstructs exact Windows arguments for {0}." -f $argumentCase.Name)
        }

        $helperNonzero = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-child-nonzero' -HelperCopy $testHelperCopy -Arguments @('--profile', 'Failed Setup') -ChildExitCode 23
        Assert-Condition -Condition ($helperNonzero.ExitCode -eq 23 -and $helperNonzero.ChildOutput -match '(?i)exit code 23' -and $helperNonzero.ChildOutput -notmatch '(?i)Setup complete\.') -Message ("The helper returns a nonzero child result (exit {0}; helper output: {1}; child output: {2})." -f $helperNonzero.ExitCode, $helperNonzero.Output.Trim(), $helperNonzero.ChildOutput.Trim())

        $helperCancel = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-uac-cancel' -HelperCopy $testHelperCopy -Arguments @() -StartMode 'cancel'
        Assert-Condition -Condition ($helperCancel.ExitCode -eq 1223 -and $helperCancel.Output -match '(?i)elevation was declined or canceled') -Message 'The helper maps the Windows UAC cancellation code to a visible nonzero result.'

        $helperStartFailure = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-start-failure' -HelperCopy $testHelperCopy -Arguments @() -StartMode 'fail'
        Assert-Condition -Condition ($helperStartFailure.ExitCode -eq 2 -and $helperStartFailure.Output -match '(?i)Could not start the elevated App Installer') -Message 'The helper reports and rejects an elevated child-start failure.'

        $timedHelperCopy = Join-Path $testRoot 'invoke-elevated-install-timeout.ps1'
        $timedHelper = $helper.Replace('$timeoutMilliseconds = 14400000', '$timeoutMilliseconds = 1000')
        $timedHelper = $timedHelper.Replace('The elevated installer exceeded the four-hour wait limit.', 'The elevated installer exceeded the test wait limit.')
        if ($timedHelper -eq $helper) {
            throw 'Could not set the isolated helper timeout for the timeout regression case.'
        }
        Write-TestFile -Path $timedHelperCopy -Content $timedHelper
        $helperDelayed = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-delayed-child' -HelperCopy $testHelperCopy -Arguments @('--profile', 'Slow Setup') -ChildDelaySeconds 5 -CheckDelayedWait
        Assert-Condition -Condition ($helperDelayed.ExitCode -eq 0 -and $helperDelayed.ChildOutput -match '(?i)Setup complete\.') -Message 'The helper waits for delayed child completion before returning success.'

        $helperTimeout = Invoke-HelperScenario -TestRoot $testRoot -Name 'helper-timeout' -HelperCopy $timedHelperCopy -Arguments @('--profile', 'Slow Setup') -ChildDelaySeconds 3
        Assert-Condition -Condition ($helperTimeout.ExitCode -eq 124 -and $helperTimeout.Output -match '(?i)exceeded the test wait limit' -and $helperTimeout.ChildOutput -notmatch '(?i)Setup complete\.') -Message 'A child that exceeds the wait limit is reported as unconfirmed and nonzero.'
        Start-Sleep -Seconds 3
        Assert-Condition -Condition ((Get-TestOutput -Path (Join-Path $testRoot 'helper-timeout-child-output.txt')) -match '(?i)FAKE CHILD FINISHED') -Message 'The fake child was allowed to finish after its unconfirmed timeout, and the harness waits before cleanup.'

        $fakeWingetOutput = Get-TestOutput -Path (Join-Path $testRoot 'missing-pwsh-after-elevation-winget-invoked.txt')
        Assert-Condition -Condition ($fakeWingetOutput.Trim() -eq 'FAKE_WINGET_ONLY') -Message 'The missing-pwsh scenario invoked only the temporary fake winget launcher.'
    }
    finally {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTestRoot.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "[OK] $assertionCount elevated Windows bootstrap assertions passed." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
