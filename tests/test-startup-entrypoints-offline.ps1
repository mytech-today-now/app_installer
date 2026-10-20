#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
if (-not ($env:OS -match 'Windows')) {
    Write-Host '[SKIP] GUI entrypoint integration requires Windows Forms.' -ForegroundColor Yellow
    exit 0
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerPayload.psm1') -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-offline-' + [guid]::NewGuid().ToString('N'))))
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$fakeBinPath = Join-Path $tempRoot 'fake-bin'
$wingetLogPath = Join-Path $tempRoot 'fake-winget.log'
$networkLogPath = Join-Path $tempRoot 'blocked-network.log'
$uiTracePath = Join-Path $tempRoot 'gui-ui-trace.log'
$driverPath = Join-Path $tempRoot 'launch-entrypoint.ps1'
$checkCount = 0

if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary test directory is outside the system temporary directory.'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:checkCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Copy-IsolatedInstallerTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [switch]$OmitResponsiveHelper
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($fileName in @('app-installer.ps1', 'app-installer-cli.ps1', 'apps-manifest.json', 'compatibility.json', 'install.bat', 'install.sh', 'invoke-elevated-install.ps1', 'payload-manifest.json', 'platform-detect.ps1', 'README.md', 'VERSION')) {
        $source = Join-Path $repositoryRoot $fileName
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $Destination -Force
        }
    }

    $sourceLauncher = Join-Path $repositoryRoot 'tools\Start-Installer.ps1'
    $destinationTools = Join-Path $Destination 'tools'
    New-Item -ItemType Directory -Path $destinationTools -Force | Out-Null
    Copy-Item -LiteralPath $sourceLauncher -Destination $destinationTools -Force

    foreach ($directoryName in @('modules', 'apps', 'profiles')) {
        $sourceDirectory = Join-Path $repositoryRoot $directoryName
        if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
            Copy-Item -LiteralPath $sourceDirectory -Destination $Destination -Recurse -Force
        }
    }

    # The CLI creates a scheduled task in its finally block when this script exists.
    # Keep the isolated run side-effect-free by omitting that optional script.
    $scheduledUpdateScript = Join-Path $Destination 'apps\winget-update.ps1'
    if (Test-Path -LiteralPath $scheduledUpdateScript -PathType Leaf) {
        Remove-Item -LiteralPath $scheduledUpdateScript -Force
    }

    if ($OmitResponsiveHelper) {
        $helperPath = Join-Path $Destination 'modules\ResponsiveGuiHelper.psm1'
        if (Test-Path -LiteralPath $helperPath -PathType Leaf) {
            Remove-Item -LiteralPath $helperPath -Force
        }
    }

    Write-AppInstallerPayloadIntegrity -RootPath $Destination | Out-Null
}

function Invoke-IsolatedEntrypoint {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('cli', 'gui', 'gui-forced-cli')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$TreeRoot,

        [Parameter(Mandatory = $true)]
        [string]$UserProfile
    )

    $scriptPath = Join-Path $TreeRoot $(if ($Mode -in @('gui', 'gui-forced-cli')) { 'app-installer.ps1' } else { 'app-installer-cli.ps1' })
    $driverText = @'
$ErrorActionPreference = 'Stop'
function global:Invoke-WebRequest {
    Add-Content -LiteralPath $env:STARTUP_NETWORK_LOG -Value 'Invoke-WebRequest blocked'
    throw 'Network disabled by startup regression harness.'
}
function global:Invoke-RestMethod {
    Add-Content -LiteralPath $env:STARTUP_NETWORK_LOG -Value 'Invoke-RestMethod blocked'
    throw 'Network disabled by startup regression harness.'
}

if ($env:STARTUP_MODE -eq 'gui') {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class StartupDialogProbe {
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll", EntryPoint = "EnumWindows", SetLastError = true)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowTextW", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int maxCount);
    [DllImport("user32.dll", EntryPoint = "IsWindowVisible")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", EntryPoint = "PostMessageW", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    public static IntPtr FindVisibleWindowForCurrentProcess(string title) {
        IntPtr found = IntPtr.Zero;
        uint currentProcessId = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        EnumWindows((window, parameter) => {
            uint windowProcessId;
            GetWindowThreadProcessId(window, out windowProcessId);
            if (windowProcessId == currentProcessId && IsWindowVisible(window)) {
                System.Text.StringBuilder text = new System.Text.StringBuilder(256);
                GetWindowText(window, text, text.Capacity);
                if (String.Equals(text.ToString(), title, StringComparison.Ordinal)) {
                    found = window;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static void PressEnter(IntPtr window) {
        PostMessage(window, 0x0100, new IntPtr(0x0D), IntPtr.Zero);
        PostMessage(window, 0x0101, new IntPtr(0x0D), IntPtr.Zero);
    }
}
"@

    function Find-WebBrowserControl {
        param([System.Windows.Forms.Control]$Parent)
        foreach ($child in $Parent.Controls) {
            if ($child -is [System.Windows.Forms.WebBrowser]) {
                return $child
            }
            $nested = Find-WebBrowserControl -Parent $child
            if ($nested) {
                return $nested
            }
        }
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timerState = @{ Ticks = 0; FormSeen = $false; FallbackVisible = $false }
    $tickHandler = {
        $timerState.Ticks++
        $helperDialog = [StartupDialogProbe]::FindVisibleWindowForCurrentProcess('Startup helper verification')
        if ($helperDialog -ne [IntPtr]::Zero) {
            $timerState.FallbackVisible = $true
            [StartupDialogProbe]::PressEnter($helperDialog)
        }
        $openForms = @([System.Windows.Forms.Application]::OpenForms)
        Add-Content -LiteralPath $env:STARTUP_UI_TRACE -Value ('tick={0};fallbackDialog={1};forms={2}' -f $timerState.Ticks, ($helperDialog -ne [IntPtr]::Zero), (($openForms | ForEach-Object { $_.Text }) -join '|'))

        foreach ($openForm in $openForms) {
            if ($openForm.Text -like '*Application Installer*') {
                $timerState.FormSeen = $true
                $browser = Find-WebBrowserControl -Parent $openForm
                if ($browser -and ([string]$browser.DocumentText).Contains('A required optional helper could not be verified. Installation remains available with built-in behavior.')) {
                    $timerState.FallbackVisible = $true
                }
                $openForm.Close()
            }
            elseif ($openForm.Visible) {
                # Dismiss startup dialogs such as a missing-dependency notice in this isolated run.
                $openForm.Close()
            }
        }

        if ($timerState.FormSeen -or $timerState.Ticks -gt 80) {
            $timer.Stop()
        }
    }.GetNewClosure()
    $timer.Add_Tick($tickHandler)
    $timer.Start()

    & $env:STARTUP_SCRIPT_PATH
    $timer.Stop()
    Set-Content -LiteralPath $env:STARTUP_UI_STATUS -Value ('FormSeen={0};FallbackVisible={1}' -f $timerState.FormSeen, $timerState.FallbackVisible)
}
elseif ($env:STARTUP_MODE -eq 'gui-forced-cli') {
    & $env:STARTUP_SCRIPT_PATH -ForceCLI -Action __invalid__
}
else {
    & $env:STARTUP_SCRIPT_PATH -Action Menu
}
'@
    [System.IO.File]::WriteAllText($driverPath, $driverText, [System.Text.Encoding]::UTF8)

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $pwshPath
    $processInfo.Arguments = '-NoLogo -NoProfile -File "' + $driverPath + '"'
    if ($Mode -eq 'gui-forced-cli') {
        $processInfo.Arguments = '-NoLogo -NoProfile -File "' + $scriptPath + '" -ForceCLI -Action __invalid__'
    }
    $processInfo.WorkingDirectory = $TreeRoot
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $processInfo.EnvironmentVariables['USERPROFILE'] = $UserProfile
    $processInfo.EnvironmentVariables['HOME'] = $UserProfile
    $processInfo.EnvironmentVariables['APPDATA'] = Join-Path $UserProfile 'AppData\Roaming'
    $processInfo.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $UserProfile 'AppData\Local'
    $processInfo.EnvironmentVariables['TEMP'] = $tempRoot
    $processInfo.EnvironmentVariables['TMP'] = $tempRoot
    $processInfo.EnvironmentVariables['PATH'] = "$fakeBinPath;$env:SystemRoot\System32"
    $processInfo.EnvironmentVariables['STARTUP_FAKE_WINGET_LOG'] = $wingetLogPath
    $processInfo.EnvironmentVariables['STARTUP_NETWORK_LOG'] = $networkLogPath
    $processInfo.EnvironmentVariables['STARTUP_UI_TRACE'] = $uiTracePath
    $processInfo.EnvironmentVariables['STARTUP_UI_STATUS'] = Join-Path $tempRoot "$Mode-ui-status.txt"
    $processInfo.EnvironmentVariables['STARTUP_SCRIPT_PATH'] = $scriptPath
    $processInfo.EnvironmentVariables['STARTUP_MODE'] = $Mode

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($Mode -in @('cli', 'gui-forced-cli')) {
        $process.StandardInput.WriteLine('Q')
    }
    else {
        foreach ($answer in @('N', 'N', 'N', '')) {
            $process.StandardInput.WriteLine($answer)
        }
    }
    $process.StandardInput.Close()

    $startupWaitLimitSeconds = 120
    if (-not $process.WaitForExit($startupWaitLimitSeconds * 1000)) {
        $process.Kill()
        $process.WaitForExit()
        $trace = if (Test-Path -LiteralPath $uiTracePath -PathType Leaf) { (Get-Content -LiteralPath $uiTracePath -Tail 20) -join '; ' } else { 'no Windows Forms timer events recorded' }
        $childOutput = ($stdoutTask.Result + [Environment]::NewLine + $stderrTask.Result) -split "`r?`n" | Select-Object -Last 25
        throw "$Mode startup did not exit within $startupWaitLimitSeconds seconds. UI trace: $trace. Child output: $($childOutput -join '; ')"
    }

    return [PSCustomObject]@{
        ExitCode     = $process.ExitCode
        Output       = $stdoutTask.Result + [Environment]::NewLine + $stderrTask.Result
        UiStatusPath = $processInfo.EnvironmentVariables['STARTUP_UI_STATUS']
        UserProfile  = $UserProfile
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeBinPath -Force | Out-Null
    $fakeWinget = @'
@echo off
>>"%STARTUP_FAKE_WINGET_LOG%" echo %*
if /I "%~1"=="install" exit /b 91
if /I "%~1"=="upgrade" exit /b 91
if /I "%~1"=="--version" echo v1.0.0
exit /b 0
'@
    [System.IO.File]::WriteAllText((Join-Path $fakeBinPath 'winget.cmd'), $fakeWinget, [System.Text.Encoding]::ASCII)

    $positiveTree = Join-Path $tempRoot 'source-with-helper'
    $fallbackTree = Join-Path $tempRoot 'source-without-helper'
    Copy-IsolatedInstallerTree -Destination $positiveTree
    Copy-IsolatedInstallerTree -Destination $fallbackTree -OmitResponsiveHelper

    $positiveGui = Invoke-IsolatedEntrypoint -Mode gui -TreeRoot $positiveTree -UserProfile (Join-Path $tempRoot 'profile-gui-positive')
    Assert-Condition -Condition ($positiveGui.ExitCode -eq 0) -Message 'GUI starts with the verified bundled helper and exits cleanly'
    Assert-Condition -Condition (Test-Path -LiteralPath $positiveGui.UiStatusPath -PathType Leaf) -Message 'GUI form was reached with the verified helper'
    $installedGuiModules = Join-Path $positiveGui.UserProfile 'myTech.Today\AppInstaller\modules'
    Assert-Condition -Condition ((Test-Path -LiteralPath (Join-Path $installedGuiModules 'StartupHelperTrust.psm1') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $installedGuiModules 'ResponsiveGuiHelper.psm1') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $installedGuiModules 'InstallerPrerequisitePlan.psm1') -PathType Leaf)) -Message 'GUI self-install copies its bundled startup and prerequisite modules'
    Assert-Condition -Condition (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $installedGuiModules) 'compatibility.json') -PathType Leaf) -Message 'GUI self-install copies the compatibility contract for future launches'

    $fallbackGui = Invoke-IsolatedEntrypoint -Mode gui -TreeRoot $fallbackTree -UserProfile (Join-Path $tempRoot 'profile-gui-fallback')
    Assert-Condition -Condition ($fallbackGui.ExitCode -eq 0) -Message 'GUI starts with the helper absent and exits cleanly'
    $fallbackModules = Join-Path $fallbackGui.UserProfile 'myTech.Today\AppInstaller\modules'
    Assert-Condition -Condition ((Test-Path -LiteralPath (Join-Path $fallbackModules 'StartupHelperTrust.psm1') -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $fallbackModules 'ResponsiveGuiHelper.psm1') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $fallbackModules 'InstallerPrerequisitePlan.psm1') -PathType Leaf)) -Message 'GUI self-install preserves the missing-helper fallback and copies the prerequisite planner'
    Assert-Condition -Condition (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $fallbackModules) 'compatibility.json') -PathType Leaf) -Message 'GUI fallback self-install copies the compatibility contract for future launches'
    $guiStatus = if (Test-Path -LiteralPath $fallbackGui.UiStatusPath -PathType Leaf) { Get-Content -LiteralPath $fallbackGui.UiStatusPath -Raw } else { '' }
    Assert-Condition -Condition ($guiStatus -match 'FormSeen=True;FallbackVisible=True') -Message 'GUI visibly reports the fallback status and built-in responsive layout'

    $cli = Invoke-IsolatedEntrypoint -Mode cli -TreeRoot $fallbackTree -UserProfile (Join-Path $tempRoot 'profile-cli')
    Assert-Condition -Condition ($cli.ExitCode -eq 0) -Message 'CLI starts offline with its optional helper absent and exits cleanly'
    Assert-Condition -Condition ($cli.Output.Contains('A required optional helper could not be verified. Installation remains available with built-in behavior.')) -Message 'CLI displays the documented built-in fallback'
    $installedCliRoot = Join-Path $cli.UserProfile 'myTech.Today\AppInstaller'
    Assert-Condition -Condition ((Test-Path -LiteralPath (Join-Path $installedCliRoot 'compatibility.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $installedCliRoot 'modules\InstallerPrerequisitePlan.psm1') -PathType Leaf)) -Message 'CLI self-install copies the compatibility contract and prerequisite planner for future launches'

    $forcedCli = Invoke-IsolatedEntrypoint -Mode gui-forced-cli -TreeRoot $fallbackTree -UserProfile (Join-Path $tempRoot 'profile-gui-forced-cli')
    $forcedCliOutputMatches = $forcedCli.Output.Contains('__invalid__') -and $forcedCli.Output.Contains('does not belong to the set')
    if ($forcedCli.ExitCode -ne 1 -or -not $forcedCliOutputMatches) {
        $forcedCliDiagnostic = ($forcedCli.Output -replace '\s+', ' ').Trim()
        throw "FAIL: Forced CLI fallback forwards original arguments and returns the CLI validation exit code. ExitCode=$($forcedCli.ExitCode); Output=$forcedCliDiagnostic"
    }
    Assert-Condition -Condition $true -Message 'Forced CLI fallback forwards original arguments and returns the CLI validation exit code'

    foreach ($result in @($positiveGui, $fallbackGui, $cli, $forcedCli)) {
        Assert-Condition -Condition ($result.Output -notmatch '(?i)Unhandled exception|uncaught exception|GUI initialization failed|GUI Error:|At .+\.ps1:\d+ char:') -Message 'Entrypoint exits without a startup exception'
        Assert-Condition -Condition ($result.Output -notmatch '(?i)responsive GUI helper loaded successfully|generic logging module loaded successfully|helper initialized successfully') -Message 'Entrypoint makes no claim that an unverified helper initialized'
    }

    Assert-Condition -Condition (-not (Test-Path -LiteralPath $networkLogPath -PathType Leaf)) -Message 'Neither entrypoint attempted a startup network request'

    $packageCommands = if (Test-Path -LiteralPath $wingetLogPath -PathType Leaf) { Get-Content -LiteralPath $wingetLogPath } else { @() }
    $installCommands = @($packageCommands | Where-Object { $_ -match '(^|\s)(install|upgrade)(\s|$)' })
    Assert-Condition -Condition ($installCommands.Count -eq 0) -Message 'Fake package-manager recorded no install or upgrade call'

    foreach ($result in @($positiveGui, $fallbackGui, $cli)) {
        $logDirectory = Join-Path $result.UserProfile 'myTech.Today\logs'
        Assert-Condition -Condition (Test-Path -LiteralPath $logDirectory -PathType Container) -Message "Startup writes logs under an isolated user profile: $(Split-Path $logDirectory -Parent)"
    }

    Write-Host "Offline entrypoint integration checks passed ($checkCount assertions)." -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
