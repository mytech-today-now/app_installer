# Offline IExpress resource update test. The generated EXE is inspected, never launched.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
if ($env:OS -notmatch 'Windows') {
    Write-Host '[SKIP] Windows executable resource checks require Windows.' -ForegroundColor Yellow
    exit 0
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$seedPath = Join-Path $repositoryRoot 'builds\install-GUI.exe'
$metadataSource = Join-Path $repositoryRoot 'tools\InstallerExecutableVersionInfo.cs'
$makecabPath = Join-Path $env:WINDIR 'System32\makecab.exe'
$expandPath = Join-Path $env:WINDIR 'System32\expand.exe'
foreach ($requiredPath in @($seedPath, $metadataSource, $makecabPath, $expandPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required executable resource test input is missing: $requiredPath"
    }
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerResourceTest-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The executable resource test path is outside the system temporary directory.'
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$testCompleted = $false

try {
    Add-Type -Path $metadataSource -ErrorAction Stop
    $originalCabinet = [InstallerExecutableVersionInfo]::ReadCabinetResource($seedPath)
    $originalVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($seedPath).FileVersion

    $stagePath = Join-Path $testRoot 'stage'
    $extractPath = Join-Path $testRoot 'extracted'
    New-Item -ItemType Directory -Path $stagePath,$extractPath -Force | Out-Null
    $payloadBytes = New-Object byte[] 300000
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
    Copy-Item -LiteralPath $seedPath -Destination $copyPath
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
    Write-Host '[OK] The IExpress cabinet resource can grow, remain byte-identical, preserve version metadata, and stay unsigned.' -ForegroundColor Green
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
