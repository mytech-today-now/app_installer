# Offline IExpress resource update test. The generated EXE is inspected, never launched.
#Requires -Version 5.1

param(
    [Parameter()]
    [string]$ExecutablePath
)

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] Windows executable resource checks require Windows.' -ForegroundColor Yellow
    exit 0
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$configurationPath = Join-Path $repositoryRoot 'tools\installer-exe-build.json'
$configuration = Get-Content -LiteralPath $configurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$versionModulePath = Join-Path $repositoryRoot 'tools\InstallerExecutableBuild.psm1'
Import-Module -Name $versionModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$versionContract = Test-InstallerExeVersionContract `
    -VersionText (Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw -ErrorAction Stop) `
    -GuiSource (Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw -ErrorAction Stop) `
    -CliSource (Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw -ErrorAction Stop) `
    -ReadmeText (Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw -ErrorAction Stop)
if (-not $versionContract.IsValid) { throw ('Executable version inputs are inconsistent: ' + ($versionContract.Errors -join ' ')) }
$metadataSource = Join-Path $repositoryRoot 'tools\InstallerExecutableVersionInfo.cs'
$makecabPath = Join-Path $env:WINDIR 'System32\makecab.exe'
$expandPath = Join-Path $env:WINDIR 'System32\expand.exe'
foreach ($requiredPath in @($metadataSource, $makecabPath, $expandPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required executable resource test input is missing: $requiredPath"
    }
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47)) + '\'
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerResourceTest-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The executable resource test path is outside the system temporary directory.'
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$testCompleted = $false

try {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        $outputName = ([string]$configuration.artifact.outputNamePattern).Replace('{guiVersion}', [string]$versionContract.GuiVersion)
        $ExecutablePath = Join-Path (Join-Path $repositoryRoot ([string]$configuration.artifact.defaultOutputDirectory)) $outputName
        if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
            $ExecutablePath = Join-Path $testRoot $outputName
            $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($null -eq $pwsh) { $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue }
            if ($null -eq $pwsh) { throw 'PowerShell Core 7.6.9 is required to build the current executable for resource inspection.' }
            $builderPath = Join-Path $repositoryRoot 'tools\Build-InstallerExe.ps1'
            $buildOutput = @(& $pwsh.Source -NoProfile -File $builderPath -OutputPath $ExecutablePath -Confirm:$false 2>&1)
            $buildExitCode = $LASTEXITCODE
            if ($buildExitCode -ne 0) {
                throw ('The current executable could not be built for resource inspection. Exit code {0}: {1}' -f $buildExitCode, ($buildOutput -join [Environment]::NewLine))
            }
        }
    }
    elseif (-not [System.IO.Path]::IsPathRooted($ExecutablePath)) {
        $ExecutablePath = Join-Path $repositoryRoot $ExecutablePath
    }
    $executablePath = [System.IO.Path]::GetFullPath($ExecutablePath)
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw ('The current versioned executable is missing: {0}' -f $executablePath)
    }
    Add-Type -Path $metadataSource -ErrorAction Stop
    $originalCabinet = [InstallerExecutableVersionInfo]::ReadCabinetResource($executablePath)
    $originalVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executablePath).FileVersion

    $stagePath = Join-Path $testRoot 'stage'
    $extractPath = Join-Path $testRoot 'extracted'
    New-Item -ItemType Directory -Path $stagePath,$extractPath -Force | Out-Null
    $payloadLength = [int]([Math]::Max(300000, [long]$originalCabinet.Length + 65536))
    $payloadBytes = New-Object byte[] $payloadLength
    $random = New-Object System.Random(23)
    $random.NextBytes($payloadBytes)
    [System.IO.File]::WriteAllBytes((Join-Path $stagePath 'payload.bin'), $payloadBytes)

    $ddfPath = Join-Path $stagePath 'payload.ddf'
    $ddfLines = @(
        '.OPTION EXPLICIT',
        '.Set CabinetNameTemplate=replacement.cab',
        '.Set DiskDirectory1=.',
        '.Set MaxDiskFileCount=1000',
        '.Set CompressionType=MSZIP',
        '.Set Cabinet=on',
        '.Set Compress=on',
        '"payload.bin" "payload.bin"'
    )
    [System.IO.File]::WriteAllLines($ddfPath, $ddfLines, [System.Text.Encoding]::ASCII)
    $makecabOutputPath = Join-Path $testRoot 'makecab.out'
    $makecabErrorPath = Join-Path $testRoot 'makecab.err'
    $makecab = Start-Process -FilePath $makecabPath -ArgumentList ('/F "' + $ddfPath + '"') -WorkingDirectory $stagePath -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $makecabOutputPath -RedirectStandardError $makecabErrorPath
    $replacementPath = Join-Path $stagePath 'replacement.cab'
    if ($makecab.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $replacementPath -PathType Leaf)) {
        throw "MakeCab could not create the replacement fixture. Exit code: $($makecab.ExitCode)"
    }
    $replacementCabinet = [System.IO.File]::ReadAllBytes($replacementPath)
    if ($replacementCabinet.Length -le $originalCabinet.Length) {
        throw 'The replacement fixture must be larger than the seed cabinet to cover resource growth.'
    }

    $copyPath = Join-Path $testRoot 'copy.exe'
    Copy-Item -LiteralPath $executablePath -Destination $copyPath
    [InstallerExecutableVersionInfo]::ReplaceCabinetResource($copyPath, $replacementCabinet)
    $writtenCabinet = [InstallerExecutableVersionInfo]::ReadCabinetResource($copyPath)
    if ($writtenCabinet.Length -ne $replacementCabinet.Length) {
        throw 'The updated executable cabinet resource has the wrong size.'
    }
    for ($index = 0; $index -lt $replacementCabinet.Length; $index++) {
        if ($writtenCabinet[$index] -ne $replacementCabinet[$index]) {
            throw 'The updated executable cabinet resource differs from the replacement cabinet.'
        }
    }

    $versionAfterUpdate = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($copyPath).FileVersion
    if ($versionAfterUpdate -ne $originalVersion) {
        throw 'Replacing the cabinet resource changed the executable version metadata.'
    }
    $signature = Get-AuthenticodeSignature -FilePath $copyPath
    if ($signature.Status -ne 'NotSigned' -or $signature.SignerCertificate) {
        throw 'The updated executable must remain unsigned.'
    }

    $expandOutputPath = Join-Path $testRoot 'expand.out'
    $expandErrorPath = Join-Path $testRoot 'expand.err'
    $expand = Start-Process -FilePath $expandPath -ArgumentList ('-r "' + $replacementPath + '" -F:* "' + $extractPath + '"') -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $expandOutputPath -RedirectStandardError $expandErrorPath
    if ($expand.ExitCode -ne 0) {
        $expandDetails = (Get-Content -LiteralPath $expandOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $expandErrorPath -Raw -ErrorAction SilentlyContinue)
        throw "Expand could not inspect the replacement cabinet. Exit code: $($expand.ExitCode). $expandDetails"
    }
    $extractedPayload = Join-Path $extractPath 'payload.bin'
    if (-not (Test-Path -LiteralPath $extractedPayload -PathType Leaf)) {
        $expandedFiles = @(Get-ChildItem -LiteralPath $extractPath -File -Recurse | ForEach-Object FullName)
        $expandDetails = (Get-Content -LiteralPath $expandOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $expandErrorPath -Raw -ErrorAction SilentlyContinue)
        throw "The replacement cabinet did not extract its test payload. Files: $($expandedFiles -join ', '). Output: $expandDetails"
    }
    $expectedHash = (Get-FileHash -LiteralPath (Join-Path $stagePath 'payload.bin') -Algorithm SHA256).Hash
    $actualHash = (Get-FileHash -LiteralPath $extractedPayload -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw 'The replacement cabinet changed its payload bytes.'
    }

    $testCompleted = $true
    Write-Host '[OK] The current versioned IExpress cabinet resource can grow, remain byte-identical, preserve version metadata, and stay unsigned.' -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($testCompleted) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Warning "Executable resource test files retained for inspection: $resolvedTestRoot"
        }
    }
}
