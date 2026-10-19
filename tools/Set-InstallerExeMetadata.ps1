#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$InputPath,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    throw 'Windows executable version resources can only be built on Windows.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $repoRoot 'builds\install-GUI.exe'
}
elseif (-not [System.IO.Path]::IsPathRooted($InputPath)) {
    $InputPath = Join-Path $repoRoot $InputPath
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'builds\install-GUI.exe'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}
$manifestPath = Join-Path $repoRoot 'compatibility.json'
$versionPath = Join-Path $repoRoot 'VERSION'
$metadataSource = Join-Path $PSScriptRoot 'InstallerExecutableVersionInfo.cs'

foreach ($requiredPath in @($InputPath, $manifestPath, $versionPath, $metadataSource)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required build input is missing: $requiredPath"
    }
}

$versionText = Get-Content -LiteralPath $versionPath -Raw
$versionMatch = [regex]::Match($versionText, '(?m)^\*\*GUI Version:\*\*\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
if (-not $versionMatch.Success) {
    throw 'The GUI version could not be read from VERSION.'
}
$guiVersion = $versionMatch.Groups[1].Value
$contract = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$releaseNames = @($contract.windowsClient.releases | ForEach-Object { 'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build }) -join ' or '
$coreVersion = [string]$contract.engines.powerShellCore.version
$desktop = $contract.engines.windowsPowerShell
$frameworkVersion = [string]$contract.runtimePrerequisites.windowsPowerShellGui.minimumVersion
$desktopRuntimeMajor = [int]$contract.runtimePrerequisites.powerShellCoreGui.runtimeMajor
$comments = "Windows support: $releaseNames, Home or Pro, x64. Windows PowerShell $($desktop.major).$($desktop.minor) GUI and CLI; GUI requires .NET Framework $frameworkVersion. PowerShell Core $coreVersion CLI; GUI requires Windows Desktop runtime $desktopRuntimeMajor and loadable System.Windows.Forms and System.Drawing. See compatibility.json."

$inputFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath).Path)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFullPath

if ($inputFullPath -ne $outputFullPath -and (Test-Path -LiteralPath $outputFullPath -PathType Leaf)) {
    throw "The output file already exists. Choose a new path or remove it deliberately: $outputFullPath"
}

if (-not $PSCmdlet.ShouldProcess($outputFullPath, "Write App Installer version $guiVersion and compatibility metadata")) {
    return
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

if ($inputFullPath -ne $outputFullPath) {
    Copy-Item -LiteralPath $inputFullPath -Destination $outputFullPath
}

$signature = Get-AuthenticodeSignature -FilePath $outputFullPath
if ($signature.SignerCertificate) {
    throw 'The input executable has a signer certificate. Version-resource updates would invalidate its signature.'
}

Add-Type -Path $metadataSource -ErrorAction Stop
[InstallerExecutableVersionInfo]::Apply(
    $outputFullPath,
    'myTech.Today App Installer',
    'myTech.Today',
    'App Installer Windows setup package',
    'install-GUI.exe',
    "$guiVersion.0",
    $comments,
    '(c) 2026 myTech.Today. All rights reserved.'
)

$result = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($outputFullPath)
if ($result.FileVersion -ne "$guiVersion.0" -or $result.ProductName -ne 'myTech.Today App Installer' -or -not $result.Comments.Contains('compatibility.json')) {
    throw 'Executable version metadata did not match the generated compatibility contract.'
}

Write-Host "[OK] Wrote $($result.FileVersion) metadata to $outputFullPath" -ForegroundColor Green
