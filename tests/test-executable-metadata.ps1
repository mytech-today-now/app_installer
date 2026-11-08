# Offline version-resource and retired-path checks for the current generated EXE.
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
$buildConfigurationPath = Join-Path $repositoryRoot 'tools\installer-exe-build.json'
$buildConfiguration = Get-Content -LiteralPath $buildConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$metadataScriptPath = Join-Path $repositoryRoot 'tools\Set-InstallerExeMetadata.ps1'
$versionModulePath = Join-Path $repositoryRoot 'tools\InstallerExecutableBuild.psm1'
Import-Module -Name $versionModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$versionContract = Test-InstallerExeVersionContract `
    -VersionText (Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw -ErrorAction Stop) `
    -GuiSource (Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw -ErrorAction Stop) `
    -CliSource (Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw -ErrorAction Stop) `
    -ReadmeText (Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw -ErrorAction Stop)
if (-not $versionContract.IsValid) {
    throw ('Executable version inputs are inconsistent: {0}' -f ($versionContract.Errors -join ' '))
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47)) + '\'
$temporaryRoot = $null
if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $outputName = ([string]$buildConfiguration.artifact.outputNamePattern).Replace('{guiVersion}', [string]$versionContract.GuiVersion)
    $ExecutablePath = Join-Path (Join-Path $repositoryRoot ([string]$buildConfiguration.artifact.defaultOutputDirectory)) $outputName
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        $temporaryRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerExeMetadata-' + [guid]::NewGuid().ToString('N'))))
        if (-not $temporaryRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'The executable metadata build path is outside the system temporary directory.'
        }
        New-Item -ItemType Directory -Path $temporaryRoot -Force -ErrorAction Stop | Out-Null
        $ExecutablePath = Join-Path $temporaryRoot $outputName
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) { $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue }
        if ($null -eq $pwsh) { throw 'PowerShell Core 7.6.9 is required to build the current executable for metadata inspection.' }
        $builderPath = Join-Path $repositoryRoot 'tools\Build-InstallerExe.ps1'
        $buildOutput = @(& $pwsh.Source -NoProfile -File $builderPath -OutputPath $ExecutablePath -Confirm:$false 2>&1)
        $buildExitCode = $LASTEXITCODE
        if ($buildExitCode -ne 0) {
            throw ('The current executable could not be built for metadata inspection. Exit code {0}: {1}' -f $buildExitCode, ($buildOutput -join [Environment]::NewLine))
        }
    }
}
elseif (-not [System.IO.Path]::IsPathRooted($ExecutablePath)) {
    $ExecutablePath = Join-Path $repositoryRoot $ExecutablePath
}
$exePath = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw ('The current versioned executable is missing: {0}' -f $exePath)
}

$metadataHost = if ($PSVersionTable.PSEdition -eq 'Core') {
    (Get-Process -Id $PID -ErrorAction Stop).Path
}
else {
    Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
function Invoke-MetadataToolForGuardTest {
    param([string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $metadataHost @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        return [PSCustomObject]@{ ExitCode = $exitCode; Output = $output }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

try {
    $missingArgumentsAttempt = Invoke-MetadataToolForGuardTest -Arguments @('-NoProfile', '-File', $metadataScriptPath)
    if ($missingArgumentsAttempt.ExitCode -eq 0) {
        throw 'The metadata tool must require explicit input and output paths.'
    }

    foreach ($legacyArtifact in @($buildConfiguration.legacyArtifacts)) {
        $legacyPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ([string]$legacyArtifact.path)))
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            throw ('A retired executable unexpectedly exists: {0}' -f [string]$legacyArtifact.path)
        }
        $blockedOutputAttempt = Invoke-MetadataToolForGuardTest -Arguments @('-NoProfile', '-File', $metadataScriptPath, '-InputPath', $exePath, '-OutputPath', $legacyPath, '-WhatIf')
        if ($blockedOutputAttempt.ExitCode -eq 0 -or (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
            throw ('The metadata tool did not fail closed for retired output {0}.' -f [string]$legacyArtifact.path)
        }
    }

    $expectedVersion = [string]$versionContract.GuiVersion + '.0'
    $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
    $signature = Get-AuthenticodeSignature -FilePath $exePath
    $contract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'compatibility.json') -Raw | ConvertFrom-Json
    $releaseNames = @($contract.windowsClient.releases | ForEach-Object { 'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build })
    $windows10Target = $contract.windowsClient.windows10CompatibilityTarget
    $windows10Text = 'Windows 10 {0} through {1} with exact release/build pairs in compatibility.json' -f $windows10Target.displayVersionMinimum, $windows10Target.displayVersionMaximum
    $coreRange = 'PowerShell Core {0} through {1}' -f [string]$contract.engines.powerShellCore.minimumVersion, [string]$contract.engines.powerShellCore.maximumVersionInclusive

    if ($fileVersion.FileVersion -ne $expectedVersion -or $fileVersion.ProductVersion -ne $expectedVersion) {
        throw "Executable FileVersion '$($fileVersion.FileVersion)' or ProductVersion '$($fileVersion.ProductVersion)' did not match '$expectedVersion'."
    }
    if ($fileVersion.ProductName -ne 'myTech.Today App Installer') {
        throw "Unexpected executable ProductName '$($fileVersion.ProductName)'."
    }
    if ($fileVersion.Comments -notmatch 'compatibility\.json' -or -not $fileVersion.Comments.Contains($coreRange)) {
        throw 'Executable comments do not match the current compatibility contract.'
    }
    $requiredComments = @(
        $windows10Text,
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
    $buildManifestPath = $exePath + '.build.json'
    if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
        throw 'The current executable is missing its adjacent builder provenance.'
    }
    $buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $expectedDigestLimit = 'SHA-256 detects byte changes only when the expected digest is obtained through a trusted release channel. It does not authenticate the publisher or replace a digital signature.'
    $actualExecutableHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if ([int]$buildManifest.schemaVersion -ne 2 -or
        [string]$buildManifest.artifact.authenticodeStatus -cne 'NotSigned' -or
        -not [string]::IsNullOrEmpty([string]$buildManifest.artifact.signerSubject) -or
        [string]$buildManifest.digestLimit -cne $expectedDigestLimit -or
        [string]$buildManifest.artifact.sha256 -cne $actualExecutableHash) {
        throw 'Builder provenance must match the unsigned executable and distinguish its checksum from publisher authentication.'
    }

    $binaryText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exePath))
    if (-not $binaryText.Contains([string]$buildConfiguration.launcherTemplate.launchCommand)) {
        throw 'The executable does not retain its configured install.bat launcher.'
    }

    Add-Type -Path (Join-Path $repositoryRoot 'tools\InstallerExecutableVersionInfo.cs') -ErrorAction Stop
    $verificationRoot = if ($null -ne $temporaryRoot) { Join-Path $temporaryRoot 'payload-check' } else { [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerExePayload-' + [guid]::NewGuid().ToString('N')))) }
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
        if ($null -eq $temporaryRoot) {
            $resolvedVerificationRoot = [System.IO.Path]::GetFullPath($verificationRoot)
            if ($resolvedVerificationRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolvedVerificationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host "[OK] Generated executable metadata $expectedVersion matches the current contract; retired paths remain protected." -ForegroundColor Green
}
finally {
    if ($null -ne $temporaryRoot) {
        $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
        if ($resolvedTemporaryRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
