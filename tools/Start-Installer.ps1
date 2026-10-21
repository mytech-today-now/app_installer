#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$ForceCLI,

    [Parameter(ValueFromRemainingArguments = $true)]
    [AllowEmptyCollection()]
    [string[]]$InstallerArguments = @()
)

$ErrorActionPreference = 'Stop'

$startedMarker = [string]$env:APP_INSTALLER_BOOTSTRAP_STARTED_FILE
if (-not $WhatIfPreference -and -not [string]::IsNullOrWhiteSpace($startedMarker)) {
    try {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedMarker = [System.IO.Path]::GetFullPath($startedMarker)
        if ($resolvedMarker.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.IO.File]::WriteAllText($resolvedMarker, 'STARTED')
        }
    }
    catch {
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$guiApplicationPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliApplicationPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$applicationPath = if ($ForceCLI) { $cliApplicationPath } else { $guiApplicationPath }
$compatibilityModulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1'
$runtimeModulePath = Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1'
$prerequisiteModulePath = Join-Path $repositoryRoot 'modules\InstallerPrerequisitePlan.psm1'
foreach ($requiredPath in @($compatibilityModulePath, $runtimeModulePath, $prerequisiteModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        [Console]::Error.WriteLine("[ERROR] Required installer startup file is missing: $requiredPath")
        exit 2
    }
}
if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
    $entryPointName = if ($ForceCLI) { 'CLI' } else { 'GUI' }
    [Console]::Error.WriteLine("[ERROR] The requested $entryPointName application entry script is missing: $applicationPath")
    exit 2
}

try {
    Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    Import-Module -Name $prerequisiteModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $hostInfo = Get-InstallerHostInfo
    $hostDecision = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $hostInfo
    if (-not $hostDecision.IsSupported) {
        [Console]::Error.WriteLine($hostDecision.Message)
        exit 1
    }

    $component = if ($ForceCLI) { 'WindowsCli' } else { 'WindowsGui' }
    $scriptArguments = @($InstallerArguments)
    if ($ForceCLI) {
        $scriptArguments = @($scriptArguments | Where-Object { $_ -notmatch '^(?i)-ForceCLI$' })
    }
    if ($WhatIfPreference -and @($scriptArguments | Where-Object { $_ -match '^(?i)-WhatIf$' }).Count -eq 0) {
        $scriptArguments += '-WhatIf'
    }
    $flowResult = Invoke-InstallerRuntimePrerequisiteFlow -Component $component -ApplicationPath $applicationPath -ScriptArguments $scriptArguments -AllowGuiCliFallback -AlwaysLaunchApplication
    if ($flowResult.Status -eq 'PlanOnly') {
        [Console]::Out.WriteLine('[INFO] WhatIf completed. No runtime download, installation, elevation, or application package action was started.')
        exit 0
    }
    if ($flowResult.Status -ne 'Started') {
        [Console]::Error.WriteLine("[ERROR] The installer could not establish a compatible PowerShell runtime: $($flowResult.Reason)")
        exit 1
    }
    if ($flowResult.RuntimeDecision.Action -eq 'Exit') {
        exit $flowResult.RuntimeDecision.ExitCode
    }
    [Console]::Error.WriteLine('[ERROR] Runtime preflight did not start the App Installer.')
    exit 1
}
catch {
    [Console]::Error.WriteLine('[ERROR] PowerShell runtime preflight failed before installer actions. Local paths and environment details were withheld.')
    exit 1
}
