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
    throw 'InputPath is required. Supply the executable to inspect or stage explicitly.'
}
elseif (-not [System.IO.Path]::IsPathRooted($InputPath)) {
    $InputPath = Join-Path $repoRoot $InputPath
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    throw 'OutputPath is required. Supply a new staged executable path explicitly.'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}
$buildConfigurationPath = Join-Path $PSScriptRoot 'installer-exe-build.json'
$manifestPath = Join-Path $repoRoot 'compatibility.json'
$versionPath = Join-Path $repoRoot 'VERSION'
$guiScriptPath = Join-Path $repoRoot 'app-installer.ps1'
$cliScriptPath = Join-Path $repoRoot 'app-installer-cli.ps1'
$readmePath = Join-Path $repoRoot 'README.md'
$versionModulePath = Join-Path $PSScriptRoot 'InstallerExecutableBuild.psm1'
$metadataSource = Join-Path $PSScriptRoot 'InstallerExecutableVersionInfo.cs'

foreach ($requiredPath in @($InputPath, $buildConfigurationPath, $manifestPath, $versionPath, $guiScriptPath, $cliScriptPath, $readmePath, $versionModulePath, $metadataSource)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required build input is missing: $requiredPath"
    }
}

$buildConfiguration = Get-Content -LiteralPath $buildConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$legacyArtifacts = @($buildConfiguration.legacyArtifacts)
if ($legacyArtifacts.Count -eq 0) {
    throw 'The build configuration must identify legacy executable paths before metadata can be written.'
}

$inputFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath).Path)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$resolvedOutputPath = $outputFullPath
if (Test-Path -LiteralPath $outputFullPath -PathType Leaf) {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $outputFullPath).Path)
}
foreach ($legacyArtifact in $legacyArtifacts) {
    $legacyPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$legacyArtifact.path)))
    if ([string]::Equals($outputFullPath, $legacyPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($resolvedOutputPath, $legacyPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ('Metadata output cannot target a tracked legacy executable: {0}' -f [string]$legacyArtifact.path)
    }
}

$versionText = Get-Content -LiteralPath $versionPath -Raw
Import-Module -Name $versionModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$versionContract = Test-InstallerExeVersionContract -VersionText $versionText -GuiSource (Get-Content -LiteralPath $guiScriptPath -Raw -ErrorAction Stop) -CliSource (Get-Content -LiteralPath $cliScriptPath -Raw -ErrorAction Stop) -ReadmeText (Get-Content -LiteralPath $readmePath -Raw -ErrorAction Stop)
if (-not $versionContract.IsValid) {
    throw ('The executable version contract is invalid: {0}' -f ($versionContract.Errors -join ' '))
}
$guiVersion = [string]$versionContract.GuiVersion
$contract = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$releaseNames = @($contract.windowsClient.releases | ForEach-Object { 'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build }) -join ' or '
$coreVersion = [string]$contract.engines.powerShellCore.version
$desktop = $contract.engines.windowsPowerShell
$frameworkVersion = [string]$contract.runtimePrerequisites.windowsPowerShellGui.minimumVersion
$desktopRuntimeMajor = [int]$contract.runtimePrerequisites.powerShellCoreGui.runtimeMajor
$comments = "Windows support: $releaseNames, Home or Pro, x64. Windows PowerShell $($desktop.major).$($desktop.minor) GUI and CLI; GUI requires .NET Framework $frameworkVersion. PowerShell Core $coreVersion CLI; GUI requires Windows Desktop runtime $desktopRuntimeMajor and loadable System.Windows.Forms and System.Drawing. See compatibility.json."

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
    ([string]$buildConfiguration.artifact.outputNamePattern).Replace('{guiVersion}', $guiVersion),
    "$guiVersion.0",
    $comments,
    '(c) 2026 myTech.Today. All rights reserved.'
)

$result = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($outputFullPath)
if ($result.FileVersion -ne "$guiVersion.0" -or $result.ProductName -ne 'myTech.Today App Installer' -or -not $result.Comments.Contains('compatibility.json')) {
    throw 'Executable version metadata did not match the generated compatibility contract.'
}

Write-Host "[OK] Wrote $($result.FileVersion) metadata to $outputFullPath" -ForegroundColor Green
