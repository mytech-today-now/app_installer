# Verifies the current Windows runner's actual host and runtime against the manifest.
# This test reads local metadata and loads assemblies only. It performs no setup or package operation.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1') -Force -DisableNameChecking
$manifest = Get-InstallerCompatibilityManifest
$hostInfo = Get-InstallerHostInfo

if ($hostInfo.Platform -ne 'Windows') {
    Write-Host '[SKIP] Current-host Windows runtime checks require Windows.' -ForegroundColor Yellow
    exit 0
}

$hostDecision = Test-InstallerCompatibility -Component WindowsHost -HostInfo $hostInfo
if (-not $hostDecision.IsSupported) {
    throw "The current Windows runner is outside compatibility.json: $($hostDecision.Reason)"
}

$cliDecision = Test-InstallerCompatibility -Component WindowsCli -HostInfo $hostInfo
if (-not $cliDecision.IsSupported) {
    throw "The current PowerShell engine is outside compatibility.json: $($cliDecision.Reason)"
}

$guiDecision = Test-InstallerCompatibility -Component WindowsGui -HostInfo $hostInfo
if (-not $guiDecision.IsSupported) {
    throw "The current GUI runtime is outside compatibility.json: $($guiDecision.Reason)"
}

if ([string]$PSVersionTable.PSEdition -eq [string]$manifest.engines.windowsPowerShell.edition) {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Host "[OK] Windows PowerShell $($PSVersionTable.PSVersion) loaded Windows Forms and System.Drawing with .NET release $($hostInfo.DotNetFrameworkRelease)." -ForegroundColor Green
}
else {
    Write-Host "[OK] PowerShell Core $($PSVersionTable.PSVersion) loaded the Windows Desktop runtime assemblies required by the GUI." -ForegroundColor Green
}

$editionName = switch ([string]$hostInfo.EditionId) {
    'Core' { 'Home' }
    'Professional' { 'Pro' }
    default { [string]$hostInfo.EditionId }
}
Write-Host "[OK] Current-host compatibility matches Windows 11 $($hostDecision.Release.displayVersion) build $($hostDecision.Release.build), $editionName, $($hostInfo.Architecture)." -ForegroundColor Green
