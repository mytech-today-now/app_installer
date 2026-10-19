# Offline version-resource checks for the current unsigned IExpress package.
# No executable is launched and no installation workflow is run.
#Requires -Version 5.1

param(
    [Parameter()]
    [string]$ExecutablePath
)

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] Windows PE version-resource checks require Windows.' -ForegroundColor Yellow
    exit 0
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $repositoryRoot 'builds\install-GUI.exe'
}
elseif (-not [System.IO.Path]::IsPathRooted($ExecutablePath)) {
    $ExecutablePath = Join-Path $repositoryRoot $ExecutablePath
}
$exePath = [System.IO.Path]::GetFullPath($ExecutablePath)
$versionText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw
$versionMatch = [regex]::Match($versionText, '(?m)^\*\*GUI Version:\*\*\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
if (-not $versionMatch.Success) {
    throw 'GUI version was not present in VERSION.'
}

$expectedVersion = $versionMatch.Groups[1].Value + '.0'
$fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
$signature = Get-AuthenticodeSignature -FilePath $exePath
$contract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'compatibility.json') -Raw | ConvertFrom-Json
$releaseNames = @($contract.windowsClient.releases | ForEach-Object { 'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build })

if ($fileVersion.FileVersion -ne $expectedVersion) {
    throw "Executable FileVersion '$($fileVersion.FileVersion)' did not match '$expectedVersion'."
}
if ($fileVersion.ProductName -ne 'myTech.Today App Installer') {
    throw "Unexpected executable ProductName '$($fileVersion.ProductName)'."
}
if ($fileVersion.Comments -notmatch 'compatibility\.json' -or $fileVersion.Comments -notmatch ([regex]::Escape('PowerShell Core ' + $contract.engines.powerShellCore.version))) {
    throw 'Executable comments do not identify the compatibility contract and supported PowerShell version.'
}
$requiredComments = @(
    'Home or Pro',
    'x64',
    'Windows PowerShell 5.1',
    ('.NET Framework ' + $contract.runtimePrerequisites.windowsPowerShellGui.minimumVersion),
    ('Windows Desktop runtime ' + $contract.runtimePrerequisites.powerShellCoreGui.runtimeMajor),
    'System.Windows.Forms',
    'System.Drawing'
)
foreach ($requiredComment in $requiredComments) {
    if (-not $fileVersion.Comments.Contains($requiredComment)) {
        throw "Executable comments omit support prerequisite '$requiredComment'."
    }
}
foreach ($release in $releaseNames) {
    if (-not $fileVersion.Comments.Contains($release)) {
        throw "Executable comments omit supported release '$release'."
    }
}
if ($signature.Status -ne 'NotSigned' -or $signature.SignerCertificate) {
    throw 'The packaged executable must remain unsigned after metadata generation.'
}

$binaryText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exePath))
if (-not $binaryText.Contains('cmd.exe /c .\install.bat')) {
    throw 'The executable does not retain its standalone install.bat launcher.'
}

Add-Type -Path (Join-Path $repositoryRoot 'tools\InstallerExecutableVersionInfo.cs') -ErrorAction Stop
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerExeMetadata-' + [guid]::NewGuid().ToString('N'))))
if (-not $verificationRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The executable metadata verification path is outside the system temporary directory.'
}
New-Item -ItemType Directory -Path $verificationRoot -Force | Out-Null
try {
    $cabinetPath = Join-Path $verificationRoot 'payload.cab'
    $extractPath = Join-Path $verificationRoot 'payload'
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    [System.IO.File]::WriteAllBytes($cabinetPath, [InstallerExecutableVersionInfo]::ReadCabinetResource($exePath))
    $expandPath = Join-Path $env:WINDIR 'System32\expand.exe'
    $expandProcess = Start-Process -FilePath $expandPath -ArgumentList ('-r "' + $cabinetPath + '" -F:* "' + $extractPath + '"') -PassThru -Wait -WindowStyle Hidden
    if ($expandProcess.ExitCode -ne 0) {
        throw "The executable payload cabinet could not be extracted for inspection. Exit code: $($expandProcess.ExitCode)"
    }

    foreach ($relativePath in @('compatibility.json', 'install.bat', 'app-installer.ps1', 'app-installer-cli.ps1', 'modules\InstallerCompatibility.psm1', 'modules\InstallerRuntimeDiscovery.psm1', 'tools\Start-Installer.ps1', 'tools\Test-InstallerCompatibility.ps1', 'tools\Install-CompatiblePowerShell.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $extractPath $relativePath) -PathType Leaf)) {
            throw "The unsigned executable payload omits a required compatibility file: $relativePath"
        }
    }
}
finally {
    $resolvedVerificationRoot = [System.IO.Path]::GetFullPath($verificationRoot)
    if ($resolvedVerificationRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedVerificationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[OK] Unsigned executable $expectedVersion metadata and embedded support contract match compatibility.json." -ForegroundColor Green
