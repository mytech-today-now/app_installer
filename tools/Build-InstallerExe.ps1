#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$SeedPath,

    [Parameter()]
    [switch]$KeepBuildFilesOnFailure
)

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    throw 'The Windows executable can only be rebuilt on Windows.'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'builds\install-GUI.exe'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}
if ([string]::IsNullOrWhiteSpace($SeedPath)) {
    $SeedPath = Join-Path $repoRoot 'builds\install-GUI.exe'
}
elseif (-not [System.IO.Path]::IsPathRooted($SeedPath)) {
    $SeedPath = Join-Path $repoRoot $SeedPath
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$seedFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SeedPath).Path)
$outputDirectory = Split-Path -Parent $outputFullPath
$metadataScript = Join-Path $PSScriptRoot 'Set-InstallerExeMetadata.ps1'
$metadataSource = Join-Path $PSScriptRoot 'InstallerExecutableVersionInfo.cs'
$payloadModulePath = Join-Path $repoRoot 'modules\InstallerPayload.psm1'
$makecabPath = Join-Path $env:WINDIR 'System32\makecab.exe'
$expandPath = Join-Path $env:WINDIR 'System32\expand.exe'

foreach ($requiredPath in @($seedFullPath, $metadataScript, $metadataSource, $payloadModulePath, $makecabPath, $expandPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required executable build input is missing: $requiredPath"
    }
}

Import-Module -Name $payloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$sourcePayloadStatus = Test-AppInstallerPayload -RootPath $repoRoot
$sourceInventory = @(Get-AppInstallerPayloadFiles -RootPath $repoRoot)
$payloadFiles = New-Object System.Collections.Generic.List[object]
foreach ($file in $sourceInventory) {
    $payloadFiles.Add([PSCustomObject]@{ Source = $file.Source; Relative = $file.Path })
}

foreach ($payloadFile in $payloadFiles) {
    if ($payloadFile.Relative -match '[^\x20-\x7E]') {
        throw "The MakeCab payload path must use ASCII characters: $($payloadFile.Relative)"
    }
}

$seedSignature = Get-AuthenticodeSignature -FilePath $seedFullPath
if ($seedSignature.Status -ne 'NotSigned' -or $seedSignature.SignerCertificate) {
    throw 'The unsigned IExpress launcher template must remain unsigned before packaging.'
}

if ($outputFullPath -ne $seedFullPath -and (Test-Path -LiteralPath $outputFullPath -PathType Leaf)) {
    throw "The output file already exists. Choose a new path or remove it deliberately: $outputFullPath"
}

if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Rebuild the unsigned App Installer cabinet resource and version metadata')) {
    return
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('AppInstallerBuild-' + [guid]::NewGuid().ToString('N'))))
if (-not $buildRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The temporary build path is outside the system temporary directory.'
}

$outputTempPath = $null
$buildCompleted = $false
try {
    $stagePath = Join-Path $buildRoot 'payload'
    New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
    $fileMap = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($payloadFile in @($payloadFiles | Sort-Object Relative)) {
        $index++
        $stageName = 'P{0:D5}{1}' -f $index, [System.IO.Path]::GetExtension($payloadFile.Relative)
        $stagedFile = Join-Path $stagePath $stageName
        $destinationPath = Join-Path $stagePath ($payloadFile.Relative.Replace('/', '\'))
        $destinationDirectory = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $payloadFile.Source -Destination $stagedFile -Force
        Copy-Item -LiteralPath $stagedFile -Destination $destinationPath -Force
        $fileMap.Add([PSCustomObject]@{ StageName = $stageName; Relative = $payloadFile.Relative; Source = $destinationPath })
    }

    Write-AppInstallerPayloadIntegrity -RootPath $stagePath | Out-Null
    $stagedPayloadStatus = Test-AppInstallerPayload -RootPath $stagePath -RequirePackage
    if (-not $stagedPayloadStatus.IsValid -or $stagedPayloadStatus.Version -ne $sourcePayloadStatus.Version) {
        throw 'The staged executable payload did not match the source version or failed integrity validation.'
    }
    $generatedIntegrityPath = Join-Path $stagePath 'payload-integrity.json'
    $integrityStageName = 'P{0:D5}.json' -f ($fileMap.Count + 1)
    $integrityStagedFile = Join-Path $stagePath $integrityStageName
    Copy-Item -LiteralPath $generatedIntegrityPath -Destination $integrityStagedFile -Force
    $fileMap.Add([PSCustomObject]@{ StageName = $integrityStageName; Relative = 'payload-integrity.json'; Source = $generatedIntegrityPath })

    $ddfLines = New-Object System.Collections.Generic.List[string]
    $ddfLines.Add('.OPTION EXPLICIT')
    $ddfLines.Add('.Set CabinetNameTemplate=payload.cab')
    $ddfLines.Add('.Set DiskDirectory1=.')
    $ddfLines.Add('.Set MaxDiskFileCount=1000')
    $ddfLines.Add('.Set CompressionType=MSZIP')
    $ddfLines.Add('.Set Cabinet=on')
    $ddfLines.Add('.Set Compress=on')
    foreach ($mapItem in $fileMap) {
        $destination = $mapItem.Relative.Replace('/', '\')
        $ddfLines.Add(('"{0}" "{1}"' -f $mapItem.StageName, $destination))
    }

    $ddfPath = Join-Path $stagePath 'payload.ddf'
    [System.IO.File]::WriteAllText($ddfPath, (($ddfLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    $makecabOutputPath = Join-Path $buildRoot 'makecab.out'
    $makecabErrorPath = Join-Path $buildRoot 'makecab.err'
    $makecabProcess = Start-Process -FilePath $makecabPath -ArgumentList ('/F "' + $ddfPath + '"') -WorkingDirectory $stagePath -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $makecabOutputPath -RedirectStandardError $makecabErrorPath
    if ($makecabProcess.ExitCode -ne 0) {
        $makecabDetails = (Get-Content -LiteralPath $makecabOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $makecabErrorPath -Raw -ErrorAction SilentlyContinue)
        throw "MakeCab failed to create the payload. Exit code: $($makecabProcess.ExitCode). $makecabDetails"
    }

    $cabPath = Join-Path $stagePath 'payload.cab'
    if (-not (Test-Path -LiteralPath $cabPath -PathType Leaf)) {
        throw 'MakeCab returned success without creating the payload cabinet.'
    }

    $verificationPath = Join-Path $buildRoot 'verified-payload'
    New-Item -ItemType Directory -Path $verificationPath -Force | Out-Null
    $expandOutputPath = Join-Path $buildRoot 'expand.out'
    $expandErrorPath = Join-Path $buildRoot 'expand.err'
    $expandProcess = Start-Process -FilePath $expandPath -ArgumentList ('-r "' + $cabPath + '" -F:* "' + $verificationPath + '"') -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $expandOutputPath -RedirectStandardError $expandErrorPath
    if ($expandProcess.ExitCode -ne 0) {
        $expandDetails = (Get-Content -LiteralPath $expandOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $expandErrorPath -Raw -ErrorAction SilentlyContinue)
        throw "The generated payload cabinet could not be inspected. Expand exit code: $($expandProcess.ExitCode). $expandDetails"
    }

    foreach ($mapItem in $fileMap) {
        $extractedPath = Join-Path $verificationPath $mapItem.Relative
        if (-not (Test-Path -LiteralPath $extractedPath -PathType Leaf)) {
            throw "The payload cabinet omitted a required file: $($mapItem.Relative)"
        }
        $sourceHash = (Get-FileHash -LiteralPath $mapItem.Source -Algorithm SHA256).Hash
        $extractedHash = (Get-FileHash -LiteralPath $extractedPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $extractedHash) {
            throw "The payload cabinet changed file contents: $($mapItem.Relative)"
        }
    }

    Add-Type -Path $metadataSource -ErrorAction Stop
    $seedBytes = [System.IO.File]::ReadAllBytes($seedFullPath)
    $seedText = [System.Text.Encoding]::ASCII.GetString($seedBytes)
    if (-not $seedText.Contains('cmd.exe /c .\install.bat')) {
        throw 'The unsigned IExpress launcher template does not launch install.bat.'
    }
    $buildExePath = Join-Path $buildRoot 'install-GUI.exe'
    Copy-Item -LiteralPath $seedFullPath -Destination $buildExePath -Force
    $cabinetBytes = [System.IO.File]::ReadAllBytes($cabPath)
    [InstallerExecutableVersionInfo]::ReplaceCabinetResource($buildExePath, $cabinetBytes)

    if (-not $seedText.Contains('myTech.Today_Install-GUI')) {
        throw 'The unsigned IExpress launcher template does not identify the existing product package.'
    }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        $hostExecutable = (Get-Process -Id $PID).Path
    }
    else {
        $hostExecutable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    $metadataArguments = '-NoProfile -File "{0}" -InputPath "{1}" -OutputPath "{1}"' -f $metadataScript, $buildExePath
    $metadataProcess = Start-Process -FilePath $hostExecutable -ArgumentList $metadataArguments -PassThru -Wait -WindowStyle Hidden
    if ($metadataProcess.ExitCode -ne 0) {
        throw "The executable metadata step failed. Exit code: $($metadataProcess.ExitCode)"
    }

    $embeddedCabinet = [InstallerExecutableVersionInfo]::ReadCabinetResource($buildExePath)
    if ($embeddedCabinet.Length -ne $cabinetBytes.Length) {
        throw 'The executable metadata update changed the embedded cabinet length.'
    }
    for ($byteIndex = 0; $byteIndex -lt $cabinetBytes.Length; $byteIndex++) {
        if ($embeddedCabinet[$byteIndex] -ne $cabinetBytes[$byteIndex]) {
            throw 'The executable metadata update changed the embedded cabinet contents.'
        }
    }

    $buildText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($buildExePath))
    if (-not $buildText.Contains('cmd.exe /c .\install.bat')) {
        throw 'The generated executable no longer contains its standalone install.bat launch command.'
    }
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($buildExePath)
    if ($versionInfo.ProductName -ne 'myTech.Today App Installer' -or -not $versionInfo.Comments.Contains('compatibility.json')) {
        throw 'The package executable metadata did not identify the product and compatibility contract.'
    }
    $signature = Get-AuthenticodeSignature -FilePath $buildExePath
    if ($signature.Status -ne 'NotSigned' -or $signature.SignerCertificate) {
        throw 'The generated IExpress executable was expected to remain unsigned.'
    }

    $outputTempPath = Join-Path $outputDirectory ('.install-GUI-' + [guid]::NewGuid().ToString('N') + '.tmp.exe')
    Copy-Item -LiteralPath $buildExePath -Destination $outputTempPath -Force
    $resolvedOutputTemp = [System.IO.Path]::GetFullPath($outputTempPath)
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($outputDirectory).TrimEnd('\') + '\'
    if (-not $resolvedOutputTemp.StartsWith($resolvedOutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The temporary output file is outside the requested output directory.'
    }
    Move-Item -LiteralPath $outputTempPath -Destination $outputFullPath -Force

    $writtenVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($outputFullPath)
    $writtenSignature = Get-AuthenticodeSignature -FilePath $outputFullPath
    if ($writtenVersion.FileVersion -ne $versionInfo.FileVersion -or $writtenSignature.Status -ne 'NotSigned') {
        throw 'The published executable did not preserve its validated version or unsigned status.'
    }
    $buildCompleted = $true
    Write-Host "[OK] Rebuilt unsigned App Installer $($writtenVersion.FileVersion) with $($fileMap.Count) verified payload files: $outputFullPath" -ForegroundColor Green
}
finally {
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
    if ($KeepBuildFilesOnFailure -and -not $buildCompleted) {
        Write-Warning "Build files retained for inspection: $resolvedBuildRoot"
    }
    elseif ($resolvedBuildRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($outputTempPath) {
        $resolvedOutputTemp = [System.IO.Path]::GetFullPath($outputTempPath)
        $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($outputDirectory).TrimEnd('\') + '\'
        if ($resolvedOutputTemp.StartsWith($resolvedOutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedOutputTemp -Force -ErrorAction SilentlyContinue
        }
    }
}
