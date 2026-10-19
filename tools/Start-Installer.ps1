#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$startedMarker = [string]$env:APP_INSTALLER_BOOTSTRAP_STARTED_FILE
if (-not [string]::IsNullOrWhiteSpace($startedMarker)) {
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
$applicationPath = Join-Path $repositoryRoot 'app-installer.ps1'
$compatibilityModulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1'
$runtimeModulePath = Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1'
foreach ($requiredPath in @($applicationPath, $compatibilityModulePath, $runtimeModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        [Console]::Error.WriteLine("[ERROR] Required installer startup file is missing: $requiredPath")
        exit 2
    }
}

try {
    Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $hostInfo = Get-InstallerHostInfo
    $hostDecision = Test-InstallerCompatibility -Component WindowsHost -HostInfo $hostInfo
    if (-not $hostDecision.IsSupported) {
        [Console]::Error.WriteLine($hostDecision.Message)
        exit 1
    }

    $component = if (@($args | Where-Object { $_ -match '^(?i)-ForceCLI$' }).Count -gt 0) { 'WindowsCli' } else { 'WindowsGui' }
    $decision = Invoke-InstallerRuntimeEntry -Component $component -ApplicationPath $applicationPath -ScriptArguments $args -AllowGuiCliFallback -AlwaysLaunchApplication
    if ($decision.Action -eq 'Failure') {
        [Console]::Error.WriteLine("[ERROR] No compatible PowerShell engine could start the Windows entry point: $($decision.Reason)")
        if ($decision.PolicyBlocked) {
            [Console]::Error.WriteLine('[INFO] Execution policy was not changed and no alternate engine was tried.')
        }
        exit 1
    }
    if ($decision.Action -eq 'Exit') {
        exit $decision.ExitCode
    }
    [Console]::Error.WriteLine('[ERROR] Runtime discovery did not start the App Installer.')
    exit 1
}
catch {
    [Console]::Error.WriteLine("[ERROR] PowerShell runtime discovery failed before installer actions: $($_.Exception.Message)")
    exit 1
}
