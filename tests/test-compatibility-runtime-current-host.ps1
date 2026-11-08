# Verifies a supported Windows client's actual host and GUI runtime against the manifest.
# This test reads local metadata and loads assemblies only. It performs no setup or package operation.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1') -Force -DisableNameChecking
$manifest = Get-InstallerCompatibilityManifest
$hostInfo = Get-InstallerHostInfo

if ($hostInfo.Platform -ne 'Windows') {
    Write-Host '[UNAVAILABLE] Client GUI runtime evidence requires a supported Windows client host.' -ForegroundColor Yellow
    exit 77
}

if ($hostInfo.ProductType -ne 'WinNT' -or $hostInfo.InstallationType -ne 'Client') {
    Write-Host ('[UNAVAILABLE] Host product type {0} and installation type {1} are not a Windows client; a Server result cannot count as client GUI validation.' -f $hostInfo.ProductType, $hostInfo.InstallationType) -ForegroundColor Yellow
    exit 77
}

$hostDecision = Test-InstallerCompatibility -Component WindowsHost -HostInfo $hostInfo
if (-not $hostDecision.IsSupported) {
    Write-Host "[UNAVAILABLE] The current Windows client is outside compatibility.json: $($hostDecision.Reason)" -ForegroundColor Yellow
    exit 77
}

$cliDecision = Test-InstallerCompatibility -Component WindowsCli -HostInfo $hostInfo
if (-not $cliDecision.IsSupported) {
    Write-Host "[UNAVAILABLE] The current PowerShell engine is outside compatibility.json: $($cliDecision.Reason)" -ForegroundColor Yellow
    exit 77
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host '[UNAVAILABLE] Run this client GUI capability check with PowerShell -STA.' -ForegroundColor Yellow
    exit 77
}

$guiDecision = Test-InstallerCompatibility -Component WindowsGui -HostInfo $hostInfo
if (-not $guiDecision.IsSupported) {
    throw "The current GUI runtime is outside compatibility.json: $($guiDecision.Reason)"
}

$formsAssembly = [System.Windows.Forms.Form].Assembly.GetName().FullName
$drawingAssembly = [System.Drawing.Bitmap].Assembly.GetName().FullName
$webAssembly = [System.Web.HttpUtility].Assembly.GetName().FullName
$runtimeDescription = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription

$editionName = switch ([string]$hostInfo.EditionId) {
    'Core' { 'Home' }
    'Professional' { 'Pro' }
    default { [string]$hostInfo.EditionId }
}
$productName = if (-not [string]::IsNullOrWhiteSpace([string]$hostDecision.Release.productName)) { [string]$hostDecision.Release.productName } else { 'Windows 11' }
Write-Host ("[HOST] {0} {1}, build {2}, {3}, {4}; product type {5}; installation type {6}." -f $productName, $hostDecision.Release.displayVersion, $hostDecision.Release.build, $editionName, $hostInfo.Architecture, $hostInfo.ProductType, $hostInfo.InstallationType) -ForegroundColor Cyan
Write-Host ("[ENGINE] {0} {1}; process architecture {2}; apartment {3}." -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, (Get-InstallerProcessArchitecture), [Threading.Thread]::CurrentThread.GetApartmentState()) -ForegroundColor Cyan
Write-Host ("[RUNTIME] {0}; .NET Framework release {1}." -f $runtimeDescription, $hostInfo.DotNetFrameworkRelease) -ForegroundColor Cyan
Write-Host ("[ASSEMBLIES] System.Windows.Forms={0}; System.Drawing={1}; System.Web={2}." -f $formsAssembly, $drawingAssembly, $webAssembly) -ForegroundColor Cyan
Write-Host '[OK] Supported Windows client GUI capability and required assemblies passed.' -ForegroundColor Green
