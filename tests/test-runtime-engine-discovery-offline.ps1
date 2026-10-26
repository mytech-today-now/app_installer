#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1'
$compatibilityModulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1'
Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking
Import-Module -Name $modulePath -Force -DisableNameChecking

$tempRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('App Installer Runtime Ω ' + [guid]::NewGuid().ToString('N'))))
$assertionCount = 0
$script:probeCallLog = New-Object 'System.Collections.Generic.List[string]'
$script:launchCallLog = New-Object 'System.Collections.Generic.List[string]'
$script:applicationActionCount = 0
$oldHandoffPath = $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH
$oldHandoffComponent = $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT

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
    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-EngineCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Desktop')]
        [string]$Engine
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [System.IO.File]::WriteAllText($Path, 'fake engine candidate')
    }
    return [PSCustomObject]@{ Path = $Path; Engine = $Engine; Source = 'TestFixture' }
}

function New-EngineProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Edition,

        [string]$Architecture = 'X64',
        [bool]$Is64BitOperatingSystem = $true,
        [string]$ApartmentState = 'STA',
        [bool]$FormsAvailable = $true,
        [int]$FormsMajor = 10,
        [int]$DrawingMajor = 10
    )

    $runtimeIsCompatible = $Edition -ne 'Core' -or ($FormsMajor -eq 10 -and $DrawingMajor -eq 10)
    $guiCapabilityIsSupported = $FormsAvailable -and $ApartmentState -eq 'STA' -and $runtimeIsCompatible
    $guiCapabilityReasonCode = if (-not $FormsAvailable) { 'GUI_ASSEMBLY_LOAD_FAILED' } elseif ($ApartmentState -ne 'STA') { 'GUI_STA_REQUIRED' } else { 'COMPATIBILITY_SUPPORTED' }
    if (-not $runtimeIsCompatible) { $guiCapabilityReasonCode = 'GUI_DESKTOP_RUNTIME_VERSION_UNSUPPORTED' }
    $guiCapabilityReason = if (-not $FormsAvailable) { 'The required GUI assemblies did not load.' } elseif ($ApartmentState -ne 'STA') { 'The GUI probe is not STA.' } elseif (-not $runtimeIsCompatible) { 'The GUI assembly major version is unsupported.' } else { '' }

    return [PSCustomObject]@{
        Version = $Version
        Edition = $Edition
        ProcessArchitecture = $Architecture
        Is64BitOperatingSystem = $Is64BitOperatingSystem
        ApartmentState = $ApartmentState
        GuiCapabilityIsSupported = $guiCapabilityIsSupported
        GuiCapabilityReasonCode = $guiCapabilityReasonCode
        GuiCapabilityReason = $guiCapabilityReason
    }
}

function New-SuccessfulProbeResult {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Probe)
    return [PSCustomObject]@{ Success = $true; TimedOut = $false; PolicyBlocked = $false; Reason = ''; Probe = $Probe }
}

function New-FailedProbeResult {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [switch]$TimedOut,
        [switch]$PolicyBlocked
    )
    return [PSCustomObject]@{ Success = $false; TimedOut = $TimedOut.IsPresent; PolicyBlocked = $PolicyBlocked.IsPresent; Reason = $Reason; Probe = $null }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        Write-Host '[SKIP] PowerShell engine discovery tests require Windows registry and executable paths.' -ForegroundColor Yellow
        exit 77
    }

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $applicationPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
    $corePath = Join-Path $tempRoot 'Core Space Ω\pwsh.exe'
    $desktopPath = Join-Path $tempRoot 'Desktop Space Ω\powershell.exe'
    $core = New-EngineCandidate -Path $corePath -Engine Core
    $desktop = New-EngineCandidate -Path $desktopPath -Engine Desktop
    $coreProbe = New-EngineProbe -Version '7.6.7' -Edition 'Core'
    $desktopProbe = New-EngineProbe -Version '5.1.0' -Edition 'Desktop' -FormsMajor 4 -DrawingMajor 4
    $hostInfo = Get-InstallerHostInfo

    $none = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates
    Assert-Condition -Condition (-not $none.IsSupported -and $none.Attempts.Count -eq 0 -and $none.Reason.Contains('No documented PowerShell executable candidates')) -Message 'No candidates is a deterministic failure with no process probe.'

    $coreOnly = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:probeCallLog.Add($candidate.Engine)
        New-SuccessfulProbeResult -Probe $coreProbe
    }
    Assert-Condition -Condition ($coreOnly.IsSupported -and $coreOnly.Selected.Engine -eq 'Core') -Message 'A single supported PowerShell Core candidate is selected.'

    $desktopOnly = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        New-SuccessfulProbeResult -Probe $desktopProbe
    }
    Assert-Condition -Condition ($desktopOnly.IsSupported -and $desktopOnly.Selected.Engine -eq 'Desktop') -Message 'A Windows PowerShell 5.1 only host is supported.'

    $both = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($desktop, $core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $coreProbe } else { New-SuccessfulProbeResult -Probe $desktopProbe }
    }
    Assert-Condition -Condition ($both.IsSupported -and $both.Selected.Engine -eq 'Core' -and $both.Attempts.Count -eq 2) -Message 'When both engines are present, manifest order selects Core and probes each candidate once.'

    $failedPreferred = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:probeCallLog.Add($candidate.Engine)
        if ($candidate.Engine -eq 'Core') { New-FailedProbeResult -Reason 'The candidate exited with code 19.' }
        else { New-SuccessfulProbeResult -Probe $desktopProbe }
    }
    Assert-Condition -Condition ($failedPreferred.IsSupported -and $failedPreferred.Selected.Engine -eq 'Desktop' -and $failedPreferred.Attempts.Count -eq 2) -Message 'A failed preferred candidate falls back to the next compatible engine before application work.'

    $oldVersion = New-EngineProbe -Version '7.6.6' -Edition 'Core'
    $oldEngine = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        New-SuccessfulProbeResult -Probe $oldVersion
    }
    Assert-Condition -Condition (-not $oldEngine.IsSupported -and $oldEngine.Attempts[0].Reason -match 'outside the supported engine matrix') -Message 'A too-old PowerShell Core version is rejected.'

    $wrongEdition = New-EngineProbe -Version '5.1.0' -Edition 'Desktop'
    $wrongEditionResult = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        New-SuccessfulProbeResult -Probe $wrongEdition
    }
    Assert-Condition -Condition (-not $wrongEditionResult.IsSupported -and $wrongEditionResult.Attempts[0].Reason -match 'identity does not match') -Message 'An executable registered as Core is rejected when its probe reports Desktop edition.'

    $malformedVersion = New-EngineProbe -Version 'not-a-version' -Edition 'Core'
    $malformedResult = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        New-SuccessfulProbeResult -Probe $malformedVersion
    }
    Assert-Condition -Condition (-not $malformedResult.IsSupported -and $malformedResult.Attempts[0].Reason -match 'malformed PowerShell version') -Message 'Malformed version data is rejected with a useful reason.'

    $wrongArchitecture = New-EngineProbe -Version '7.6.7' -Edition 'Core' -Architecture 'X86'
    $architectureResult = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        New-SuccessfulProbeResult -Probe $wrongArchitecture
    }
    Assert-Condition -Condition (-not $architectureResult.IsSupported -and $architectureResult.Attempts[0].Reason -match 'x64 is required') -Message 'A 32-bit PowerShell process is rejected on the x64 support matrix.'

    $coreGuiWithoutForms = New-EngineProbe -Version '7.6.7' -Edition 'Core' -FormsAvailable $false -FormsMajor 0 -DrawingMajor 0
    $desktopGuiWithoutForms = New-EngineProbe -Version '5.1.0' -Edition 'Desktop' -FormsAvailable $false -FormsMajor 4 -DrawingMajor 4
    $guiFallbackArguments = @('-Action', 'InstallProfile', '-Profile', 'C:\Profiles\My Profile.json')
    $script:launchCallLog.Clear()
    $script:applicationActionCount = 0
    $guiFallback = Invoke-InstallerRuntimeEntry -Component WindowsGui -ApplicationPath $applicationPath -ScriptArguments $guiFallbackArguments -CandidateRecords @($core, $desktop) -AllowTestCandidates -AllowGuiCliFallback -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:probeCallLog.Add($candidate.Engine + ':' + $component)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $coreGuiWithoutForms }
        else { New-SuccessfulProbeResult -Probe $desktopGuiWithoutForms }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:launchCallLog.Add(($component + ':' + ($arguments -join '|')))
        $script:applicationActionCount++
        [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
    } -AlwaysLaunchApplication -HostInfo ([PSCustomObject]@{ DotNetFrameworkRelease = 461808; Platform = 'Windows' })
    Assert-Condition -Condition ($guiFallback.Action -eq 'Exit' -and $guiFallback.Component -eq 'WindowsCli' -and $guiFallback.Selected.Engine -eq 'Core' -and $script:applicationActionCount -eq 1) -Message 'A GUI capability failure starts one CLI workflow with the same already-probed engine records.'
    Assert-Condition -Condition ($script:launchCallLog.Count -eq 1 -and $script:launchCallLog[0].Contains('-Action|InstallProfile|-Profile|C:\Profiles\My Profile.json|-ForceCLI')) -Message 'Runtime fallback forwards all original CLI arguments and appends the internal ForceCLI switch.'

    $corruptFallback = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-FailedProbeResult -Reason 'The child returned malformed probe output.' }
        else { New-SuccessfulProbeResult -Probe $desktopProbe }
    }
    Assert-Condition -Condition ($corruptFallback.IsSupported -and $corruptFallback.Selected.Engine -eq 'Desktop' -and $corruptFallback.Attempts[0].Reason.Contains('malformed')) -Message 'A corrupt candidate response is rejected before using the next engine.'

    $timeoutFallback = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-FailedProbeResult -Reason 'The child preflight timed out.' -TimedOut }
        else { New-SuccessfulProbeResult -Probe $desktopProbe }
    }
    Assert-Condition -Condition ($timeoutFallback.IsSupported -and $timeoutFallback.Selected.Engine -eq 'Desktop' -and $timeoutFallback.Attempts[0].Reason.Contains('timed out')) -Message 'A timed-out candidate is rejected and the next compatible engine is selected.'

    $badDirectoryPath = Join-Path $tempRoot 'Directory Candidate\powershell.exe'
    New-Item -ItemType Directory -Path $badDirectoryPath -Force | Out-Null
    $invalidCandidates = @(
        [PSCustomObject]@{ Path = 'pwsh.exe'; Engine = 'Core'; Source = 'TestFixture' },
        [PSCustomObject]@{ Path = (Join-Path $tempRoot 'not-pwsh.exe'); Engine = 'Core'; Source = 'TestFixture' },
        [PSCustomObject]@{ Path = $badDirectoryPath; Engine = 'Desktop'; Source = 'TestFixture' },
        [PSCustomObject]@{ Path = ($corePath + '" -Command whoami'); Engine = 'Core'; Source = 'TestFixture' }
    )
    $script:probeCallLog.Clear()
    $maliciousPaths = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords $invalidCandidates -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:probeCallLog.Add($candidate.Path)
        New-SuccessfulProbeResult -Probe $coreProbe
    }
    Assert-Condition -Condition (-not $maliciousPaths.IsSupported -and $maliciousPaths.Attempts.Count -eq 4 -and $script:probeCallLog.Count -eq 0) -Message 'Relative, wrong-name, directory, and command-shaped paths are rejected before process launch.'

    $allIncompatible = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $oldVersion }
        else { New-FailedProbeResult -Reason 'The child exited with code 7.' }
    }
    Assert-Condition -Condition (-not $allIncompatible.IsSupported -and $allIncompatible.Attempts.Count -eq 2) -Message 'All candidates incompatible produces a closed failure after each candidate is checked once.'

    $policyCallsBefore = $script:probeCallLog.Count
    $policyResult = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:probeCallLog.Add($candidate.Engine)
        New-FailedProbeResult -Reason 'The selected PowerShell script engine is blocked by execution policy.' -PolicyBlocked
    }
    Assert-Condition -Condition (-not $policyResult.IsSupported -and $policyResult.PolicyBlocked -and $policyResult.Attempts.Count -eq 1 -and $script:probeCallLog.Count -eq ($policyCallsBefore + 1)) -Message 'An execution policy block stops selection without trying an alternate engine.'

    $bound = [ordered]@{
        Action = 'InstallProfile'
        Profile = 'C:\Profiles\用户 Home\profile.json'
        WhatIf = $true
    }
    $argumentArray = ConvertTo-InstallerRuntimeArgumentArray -BoundParameters $bound -RemainingArguments @('--raw', 'snow 雪', '')
    Assert-Condition -Condition ($argumentArray -contains '-Action' -and $argumentArray -contains '-Profile' -and $argumentArray -contains 'C:\Profiles\用户 Home\profile.json' -and $argumentArray -contains 'snow 雪' -and $argumentArray -contains '') -Message 'Bound parameters and Unicode, empty, and spaced trailing arguments remain separate array elements.'

    $quotedUnicodePath = ConvertTo-InstallerRuntimeWindowsArgument -Argument 'C:\Profiles\用户 Home\profile.json'
    $quotedTrailingSlash = ConvertTo-InstallerRuntimeWindowsArgument -Argument 'C:\Profiles\user home\'
    Assert-Condition -Condition ($quotedUnicodePath.StartsWith('"') -and $quotedUnicodePath.EndsWith('"') -and $quotedUnicodePath.Contains('用户') -and $quotedTrailingSlash -eq '"C:\Profiles\user home\\"') -Message 'Windows argument quoting protects Unicode paths, spaces, and trailing backslashes.'

    $script:launchCallLog.Clear()
    $script:applicationActionCount = 0
    $nonzeroChild = Invoke-InstallerRuntimeEntry -Component WindowsCli -ApplicationPath $applicationPath -ScriptArguments $argumentArray -CandidateRecords @($desktop, $core) -AllowTestCandidates -AlwaysLaunchApplication -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $coreProbe } else { New-SuccessfulProbeResult -Probe $desktopProbe }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:launchCallLog.Add($candidate.Engine)
        $script:applicationActionCount++
        [PSCustomObject]@{ Started = $true; ExitCode = 37; Reason = '' }
    }
    Assert-Condition -Condition ($nonzeroChild.Action -eq 'Exit' -and $nonzeroChild.ExitCode -eq 37 -and $nonzeroChild.Selected.Engine -eq 'Core' -and $script:launchCallLog.Count -eq 1 -and $script:applicationActionCount -eq 1) -Message 'A nonzero child exit is returned exactly and never starts the installer in another engine.'

    $script:launchCallLog.Clear()
    $script:applicationActionCount = 0
    $startFailureFallback = Invoke-InstallerRuntimeEntry -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($desktop, $core) -AllowTestCandidates -AlwaysLaunchApplication -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $coreProbe } else { New-SuccessfulProbeResult -Probe $desktopProbe }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:launchCallLog.Add($candidate.Engine)
        if ($candidate.Engine -eq 'Core') {
            [PSCustomObject]@{ Started = $false; ExitCode = 1; Reason = 'The child process could not be created.' }
        }
        else {
            $script:applicationActionCount++
            [PSCustomObject]@{ Started = $true; ExitCode = 23; Reason = '' }
        }
    }
    Assert-Condition -Condition ($startFailureFallback.Action -eq 'Exit' -and $startFailureFallback.ExitCode -eq 23 -and $startFailureFallback.Selected.Engine -eq 'Desktop' -and $script:applicationActionCount -eq 1 -and $script:launchCallLog.Count -eq 2) -Message 'A process creation failure uses the next preflighted engine and starts application work once.'

    $script:launchCallLog.Clear()
    $policyAtLaunch = Invoke-InstallerRuntimeEntry -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core, $desktop) -AllowTestCandidates -AlwaysLaunchApplication -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        if ($candidate.Engine -eq 'Core') { New-SuccessfulProbeResult -Probe $coreProbe } else { New-SuccessfulProbeResult -Probe $desktopProbe }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:launchCallLog.Add($candidate.Engine)
        [PSCustomObject]@{ Started = $true; ExitCode = 1; Reason = 'PowerShell policy blocked the selected script.' }
    }
    Assert-Condition -Condition ($policyAtLaunch.Action -eq 'Exit' -and $policyAtLaunch.ExitCode -eq 1 -and $script:launchCallLog.Count -eq 1) -Message 'A launched application returning a policy error is not retried in another engine.'

    $currentExecutable = Get-InstallerRuntimeCurrentExecutablePath
    $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = $currentExecutable
    $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = 'WindowsCli'
    $handoffAccepted = Test-InstallerRuntimeHandoff -Component WindowsCli
    Assert-Condition -Condition ($handoffAccepted -and [string]::IsNullOrEmpty($env:APP_INSTALLER_RUNTIME_HANDOFF_PATH)) -Message 'A matching one-time runtime handoff is accepted and cleared to prevent recursion.'

    $actualCandidate = @(Get-InstallerRuntimeCandidates | Select-Object -First 1)
    Assert-Condition -Condition ($actualCandidate.Count -eq 1) -Message 'The current Windows host exposes at least one documented PowerShell candidate.'
    $actualProbeResult = Invoke-InstallerRuntimeProbe -ExecutablePath $actualCandidate[0].Path -Component WindowsCli -ApplicationPath $applicationPath -TimeoutSeconds 12
    $actualEngineResult = if ($actualProbeResult.Success) { Test-InstallerRuntimeProbe -Candidate $actualCandidate[0] -Probe $actualProbeResult.Probe -Component WindowsCli -HostInfo $hostInfo } else { [PSCustomObject]@{ IsCompatible = $false; Reason = $actualProbeResult.Reason } }
    Assert-Condition -Condition ($actualProbeResult.Success -and $actualEngineResult.IsCompatible) -Message 'The safe child-process probe validates a real installed engine and parses the application entry point.'

    $manifest = Get-InstallerCompatibilityManifest
    $assertedOrder = @($manifest.windowsExecutable.engineSelectionOrder)
    Assert-Condition -Condition ($assertedOrder[0] -eq 'PowerShell Core 7.6.7' -and $assertedOrder[1] -eq 'Windows PowerShell Desktop 5.1' -and $manifest.windowsExecutable.runtimeDiscovery.automaticProvisioning -eq $false -and $manifest.windowsExecutable.runtimeDiscovery.consentRequiredProvisioning -eq $true) -Message 'The manifest publishes Core-first selection and consent-gated runtime provisioning.'

    Write-Host "[OK] Runtime discovery tests passed ($assertionCount assertions)." -ForegroundColor Green
}
finally {
    $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = $oldHandoffPath
    $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = $oldHandoffComponent
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedTempRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
