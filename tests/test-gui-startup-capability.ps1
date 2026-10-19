# Deterministic GUI startup capability and CLI fallback checks.
# The injected cases do not load Windows Forms or perform installer actions.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1'
Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop
$script:assertionCount = 0
$script:assemblyLoadCounter = [PSCustomObject]@{ Count = 0 }
$script:cliRunnerCalls = New-Object 'System.Collections.Generic.List[object]'

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

function New-TestHostInfo {
    param(
        [string]$Platform = 'Windows',
        [string]$DisplayVersion = '26H2',
        [int]$BuildNumber = 26300,
        [string]$ProductType = 'WinNT',
        [string]$InstallationType = 'Client',
        [string]$EditionId = 'Core',
        [string]$Architecture = 'X64',
        [int]$DotNetFrameworkRelease = 533325
    )

    return [PSCustomObject]@{
        Platform = $Platform
        DisplayVersion = $DisplayVersion
        BuildNumber = $BuildNumber
        ProductType = $ProductType
        InstallationType = $InstallationType
        EditionId = $EditionId
        Architecture = $Architecture
        DotNetFrameworkRelease = $DotNetFrameworkRelease
    }
}

function New-TestEngineInfo {
    param(
        [string]$Edition = 'Core',
        [string]$Version = '7.6.7'
    )

    return [PSCustomObject]@{ PSEdition = $Edition; PSVersion = [version]$Version }
}

function New-TestFormsLoader {
    param(
        [bool]$Available = $true,
        [int]$FormsMajor = 10,
        [int]$DrawingMajor = 10
    )

    $loadCounter = $script:assemblyLoadCounter
    $availableValue = $Available
    $formsMajorValue = $FormsMajor
    $drawingMajorValue = $DrawingMajor
    return {
        $loadCounter.Count++
        return [PSCustomObject]@{
            IsAvailable = $availableValue
            FormsMajor = $formsMajorValue
            DrawingMajor = $drawingMajorValue
            Reason = if ($availableValue) { '' } else { 'Injected assembly load failure.' }
        }
    }.GetNewClosure()
}

$validHost = New-TestHostInfo
$coreEngine = New-TestEngineInfo
$desktopEngine = New-TestEngineInfo -Edition 'Desktop' -Version '5.1.0'
$supportedDate = [datetime]'2026-10-17'
$formsLoader = New-TestFormsLoader
$unsupportedOs = Test-InstallerGuiCapability -HostInfo (New-TestHostInfo -Platform 'Linux') -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $unsupportedOs.IsSupported -and $unsupportedOs.ReasonCode -eq 'OS_NOT_WINDOWS' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'A non-Windows host is rejected before any GUI assembly probe.'

$unsupportedRelease = Test-InstallerGuiCapability -HostInfo (New-TestHostInfo -DisplayVersion '24H2' -BuildNumber 26100) -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $unsupportedRelease.IsSupported -and $unsupportedRelease.ReasonCode -eq 'WINDOWS_RELEASE_UNSUPPORTED' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'An unsupported Windows release is rejected before any GUI assembly probe.'

$unsupportedEngine = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo (New-TestEngineInfo -Version '7.6.6') -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $unsupportedEngine.IsSupported -and $unsupportedEngine.ReasonCode -eq 'ENGINE_UNSUPPORTED' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'An unsupported PowerShell version is rejected before any GUI assembly probe.'

$unsupportedProcess = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture Arm64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $unsupportedProcess.IsSupported -and $unsupportedProcess.ReasonCode -eq 'GUI_PROCESS_ARCHITECTURE_UNSUPPORTED' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'A non-x64 PowerShell process is rejected before any GUI assembly probe.'

$nonSta = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState MTA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $nonSta.IsSupported -and $nonSta.ReasonCode -eq 'GUI_STA_REQUIRED' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'A non-STA thread is rejected before any GUI assembly probe.'

$frameworkBelowMinimum = Test-InstallerGuiCapability -HostInfo (New-TestHostInfo -DotNetFrameworkRelease 461807) -EngineInfo $desktopEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition (-not $frameworkBelowMinimum.IsSupported -and $frameworkBelowMinimum.ReasonCode -eq 'GUI_DOTNET_FRAMEWORK_BELOW_MINIMUM' -and $script:assemblyLoadCounter.Count -eq 0) -Message 'Windows PowerShell below .NET Framework release 461808 is rejected before GUI assembly loading.'

$unavailableFormsLoader = New-TestFormsLoader -Available $false -FormsMajor 0 -DrawingMajor 0
$unavailableForms = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $unavailableFormsLoader
Assert-Condition -Condition (-not $unavailableForms.IsSupported -and $unavailableForms.ReasonCode -eq 'GUI_ASSEMBLY_LOAD_FAILED' -and $unavailableForms.RecoveryMessage.Contains('CLI')) -Message 'A Windows Forms assembly load failure has a stable code and CLI recovery guidance.'

$wrongRuntimeLoader = New-TestFormsLoader -FormsMajor 9 -DrawingMajor 10
$wrongRuntime = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $wrongRuntimeLoader
Assert-Condition -Condition (-not $wrongRuntime.IsSupported -and $wrongRuntime.ReasonCode -eq 'GUI_DESKTOP_RUNTIME_VERSION_UNSUPPORTED') -Message 'PowerShell Core rejects Forms assemblies from an unsupported Windows Desktop runtime major.'

$validCore = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate -ProcessArchitecture X64 -ApartmentState STA -WindowsFormsLoader $formsLoader
Assert-Condition -Condition ($validCore.IsSupported -and $validCore.ReasonCode -eq 'COMPATIBILITY_SUPPORTED' -and $script:assemblyLoadCounter.Count -eq 3) -Message 'A valid PowerShell Core host passes after one final assembly probe per eligible scenario.'

$validDesktop = Test-InstallerGuiCapability -HostInfo $validHost -EngineInfo $desktopEngine -Date $supportedDate -WindowsFormsAvailable $true -ProcessArchitecture X64 -ApartmentState STA
Assert-Condition -Condition $validDesktop.IsSupported -Message 'A valid Windows PowerShell host passes the .NET Framework, assembly, x64, and STA checks.'

$cliCapability = Test-InstallerCompatibility -Component WindowsCli -HostInfo $validHost -EngineInfo $coreEngine -Date $supportedDate
$guiFailureStartup = Resolve-InstallerGuiStartup -GuiCapability $unavailableForms -CliCapability $cliCapability
Assert-Condition -Condition ($guiFailureStartup.Action -eq 'RunCLI' -and $guiFailureStartup.ReasonCode -eq 'GUI_ASSEMBLY_LOAD_FAILED') -Message 'A GUI capability failure selects the supported CLI fallback with the original reason code.'

$forcedCli = Resolve-InstallerGuiStartup -GuiCapability $validCore -CliCapability $cliCapability -ForceCLI
Assert-Condition -Condition ($forcedCli.Action -eq 'RunCLI' -and $forcedCli.ReasonCode -eq 'CLI_FORCED') -Message 'Forced CLI bypasses the GUI capability result.'

$unsupportedCliCapability = Test-InstallerCompatibility -Component WindowsCli -HostInfo $validHost -EngineInfo (New-TestEngineInfo -Version '7.6.6') -Date $supportedDate
$blockedStartup = Resolve-InstallerGuiStartup -GuiCapability $unavailableForms -CliCapability $unsupportedCliCapability
Assert-Condition -Condition ($blockedStartup.Action -eq 'Failure' -and $blockedStartup.ReasonCode -eq 'ENGINE_UNSUPPORTED') -Message 'An unavailable CLI host stops startup with the compatibility error before installer work.'

$arguments = @('-Action', 'InstallProfile', '-Profile', 'C:\Profiles\My Profile.json')
$fakeCliRunner = {
    param($path, $forwardedArguments)
    $script:cliRunnerCalls.Add([PSCustomObject]@{ Path = [string]$path; Arguments = @($forwardedArguments) })
    return [PSCustomObject]@{ ExitCode = 37 }
}.GetNewClosure()
$fallbackResult = Invoke-InstallerCliFallback -StartupDecision $guiFailureStartup -CliScriptPath 'C:\Installer\app-installer-cli.ps1' -Arguments $arguments -Runner $fakeCliRunner
$forwardedArgumentsText = @($script:cliRunnerCalls[0].Arguments) -join '|'
$expectedArgumentsText = @($arguments) -join '|'
Assert-Condition -Condition ($fallbackResult.Action -eq 'Exit' -and $fallbackResult.ExitCode -eq 37 -and $fallbackResult.RunCount -eq 1 -and $script:cliRunnerCalls.Count -eq 1) -Message 'CLI fallback runs exactly once and returns the child process exit code.'
Assert-Condition -Condition ($script:cliRunnerCalls[0].Path -eq 'C:\Installer\app-installer-cli.ps1' -and $forwardedArgumentsText -eq $expectedArgumentsText) -Message 'CLI fallback forwards each original argument as a separate value.'
$blockedFallback = Invoke-InstallerCliFallback -StartupDecision $blockedStartup -CliScriptPath 'C:\Installer\app-installer-cli.ps1' -Arguments $arguments -Runner $fakeCliRunner
Assert-Condition -Condition ($blockedFallback.Action -eq 'Failure' -and $blockedFallback.RunCount -eq 0 -and $script:cliRunnerCalls.Count -eq 1) -Message 'An unavailable CLI host does not invoke the fallback runner.'

$appPath = Join-Path $repositoryRoot 'app-installer.ps1'
$appSource = Get-Content -LiteralPath $appPath -Raw
$guiGatePosition = $appSource.IndexOf('Test-InstallerGuiCapability -HostInfo', [System.StringComparison]::Ordinal)
$forcedCliBranchPosition = $appSource.IndexOf('$guiCapability = if ($ForceCLI)', [System.StringComparison]::Ordinal)
$helperImportPosition = $appSource.IndexOf('Import-Module -Name $trustModulePath', [System.StringComparison]::Ordinal)
$firstFormsReferencePosition = $appSource.IndexOf('[System.Windows.Forms', [System.StringComparison]::Ordinal)
$firstDrawingReferencePosition = $appSource.IndexOf('[System.Drawing', [System.StringComparison]::Ordinal)
$firstGuiReferencePosition = [Math]::Min($firstFormsReferencePosition, $firstDrawingReferencePosition)
$failureExitPosition = $appSource.IndexOf("if (`$guiStartupDecision.Action -eq 'Failure')", [System.StringComparison]::Ordinal)
$mainFormConstructionPosition = $appSource.IndexOf('$form = Create-MainForm', [System.StringComparison]::Ordinal)
Assert-Condition -Condition ($guiGatePosition -ge 0 -and $forcedCliBranchPosition -ge 0 -and $forcedCliBranchPosition -lt $guiGatePosition) -Message 'The entry point skips the GUI gate when CLI mode is forced.'
Assert-Condition -Condition ($guiGatePosition -ge 0 -and $helperImportPosition -gt $guiGatePosition -and $firstGuiReferencePosition -gt $guiGatePosition) -Message 'The entry point gates capability before helper imports and all GUI type references.'
Assert-Condition -Condition ($failureExitPosition -gt $guiGatePosition -and $failureExitPosition -lt $firstGuiReferencePosition -and $failureExitPosition -lt $mainFormConstructionPosition) -Message 'A failed GUI capability decision exits before any form constructor can run.'

Write-Host "[PASS] $script:assertionCount GUI startup capability assertions passed." -ForegroundColor Cyan
