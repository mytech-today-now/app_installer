#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'modules\InstallerCompatibility.psm1'
$manifestPath = Join-Path $repoRoot 'compatibility.json'

try {
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $manifest = Get-InstallerCompatibilityManifest -Path $manifestPath
    $hostInfo = Get-InstallerHostInfo
    $hostDecision = Test-InstallerCompatibility -Component WindowsHost -HostInfo $hostInfo
    if (-not $hostDecision.IsSupported) {
        Write-Host $hostDecision.Message -ForegroundColor Red
        exit 1
    }

    $currentEngine = Test-InstallerCompatibility -Component WindowsCli -HostInfo $hostInfo
    if ($currentEngine.IsSupported) {
        Write-Host '[OK] A compatible PowerShell engine is already active. No runtime was installed.' -ForegroundColor Green
        exit 0
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] No compatible PowerShell engine is available and WinGet is not installed. $($manifest.recovery.engine)" -ForegroundColor Red
        exit 1
    }

    $version = [string]$manifest.engines.powerShellCore.version
    if ($PSCmdlet.ShouldProcess("PowerShell $version", 'Install the compatible Windows runtime with WinGet')) {
        Write-Host "[INFO] Installing PowerShell $version after host compatibility was verified." -ForegroundColor Cyan
        & winget install --id Microsoft.PowerShell --source winget --version $version --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
        $installExitCode = $LASTEXITCODE
        if ($installExitCode -ne 0) {
            Write-Host "[ERROR] WinGet could not install PowerShell $version. Exit code: $installExitCode" -ForegroundColor Red
            exit 1
        }
    }

    exit 0
}
catch {
    Write-Host "[ERROR] Compatible PowerShell provisioning failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
