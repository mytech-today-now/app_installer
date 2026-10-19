#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('WindowsHost', 'WindowsGui', 'WindowsCli', 'CrossPlatformCli')]
    [string]$Component = 'WindowsHost'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules\InstallerCompatibility.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    Write-Host '[ERROR] The compatibility contract module is missing. No setup or package operation was started.' -ForegroundColor Red
    exit 11
}

try {
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $hostInfo = Get-InstallerHostInfo
    $decision = Test-InstallerCompatibility -Component $Component -HostInfo $hostInfo
    if (-not $decision.IsSupported) {
        Write-Host $decision.Message -ForegroundColor Red
        exit 10
    }

    Write-Host "[OK] $Component compatibility verified." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[ERROR] Compatibility validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '[INFO] No setup or package operation was started.' -ForegroundColor Yellow
    exit 11
}
