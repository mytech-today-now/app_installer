#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$compatibilityModulePath = Join-Path $repoRoot 'modules\InstallerCompatibility.psm1'
$runtimeModulePath = Join-Path $repoRoot 'modules\InstallerRuntimeDiscovery.psm1'
$prerequisiteModulePath = Join-Path $repoRoot 'modules\InstallerPrerequisitePlan.psm1'
$manifestPath = Join-Path $repoRoot 'compatibility.json'

try {
    Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    Import-Module -Name $prerequisiteModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $manifest = Get-InstallerCompatibilityManifest -Path $manifestPath
    $hostInfo = Get-InstallerHostInfo
    $hostDecision = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $hostInfo
    if (-not $hostDecision.IsSupported) {
        Write-Host $hostDecision.Message -ForegroundColor Red
        exit 1
    }

    $flowResult = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $PSCommandPath
    if ($flowResult.Status -eq 'PlanOnly') {
        Write-Host '[INFO] WhatIf completed. No runtime download, installation, or elevation was started.' -ForegroundColor Cyan
        exit 0
    }
    if ($flowResult.Status -ne 'Started') {
        Write-Host "[ERROR] PowerShell runtime preflight did not complete: $($flowResult.Reason)" -ForegroundColor Red
        exit 1
    }
    if ($flowResult.RuntimeDecision.Action -eq 'Exit') {
        exit $flowResult.RuntimeDecision.ExitCode
    }
    Write-Host '[OK] A compatible PowerShell engine was selected and revalidated. No application package action was started.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host '[ERROR] Compatible PowerShell provisioning failed before application package actions. Local paths and environment details were withheld.' -ForegroundColor Red
    exit 1
}
