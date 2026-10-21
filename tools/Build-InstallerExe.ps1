#Requires -Version 7.6.7
#Requires -PSEdition Core

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
Set-StrictMode -Version 2.0

function Get-InstallerExeSourceRevision {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
    if ($null -eq $gitCommand) { throw 'Git is required to record the source revision in the build manifest.' }

    $revisionOutput = & $gitCommand.Source -C $RepositoryRoot rev-parse --verify HEAD 2>&1
    $revisionExitCode = $LASTEXITCODE
    if ($revisionExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($revisionOutput -join ''))) {
        throw 'The source revision could not be read from Git.'
    }
    $statusOutput = @(& $gitCommand.Source -C $RepositoryRoot status --porcelain=v1 --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'The source worktree status could not be read from Git.' }

    $changes = New-Object System.Collections.Generic.List[object]
    foreach ($lineValue in $statusOutput) {
        $line = [string]$lineValue
        if ($line.Length -ge 4) {
            $changes.Add([PSCustomObject][ordered]@{ status = $line.Substring(0, 2); path = $line.Substring(3) })
        }
    }
    return [PSCustomObject][ordered]@{
        commit = ($revisionOutput -join '').Trim()
        worktreeClean = ($changes.Count -eq 0)
        changedFiles = @($changes.ToArray())
    }
}

function Get-InstallerExeInputInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $inputRecords = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in @($RelativePaths | Sort-Object -Unique)) {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relativePath))
        if (-not (Test-InstallerExeContainedPath -Path $fullPath -RootPath $RepositoryRoot) -or
            -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw ('A required build input is missing or outside the repository: {0}' -f $relativePath)
        }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        $inputRecords.Add([PSCustomObject][ordered]@{
            path = $relativePath.Replace('\', '/')
            length = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        })
    }
    return @($inputRecords.ToArray())
}

function ConvertTo-InstallerExeToolObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][object]$Observation)
    return [PSCustomObject][ordered]@{
        name = $Name
        fileVersion = [string]$Observation.FileVersion
        sha256 = [string]$Observation.Sha256
        signatureStatus = [string]$Observation.SignatureStatus
        signerSubject = [string]$Observation.SignerSubject
    }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$configurationPath = Join-Path $PSScriptRoot 'installer-exe-build.json'
$buildModulePath = Join-Path $PSScriptRoot 'InstallerExecutableBuild.psm1'
$metadataScript = Join-Path $PSScriptRoot 'Set-InstallerExeMetadata.ps1'
$metadataSource = Join-Path $PSScriptRoot 'InstallerExecutableVersionInfo.cs'
$payloadModulePath = Join-Path $repositoryRoot 'modules\InstallerPayload.psm1'
$compatibilityPath = Join-Path $repositoryRoot 'compatibility.json'
$versionPath = Join-Path $repositoryRoot 'VERSION'
$guiScriptPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliScriptPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'

foreach ($requiredPath in @($configurationPath, $buildModulePath, $metadataScript, $metadataSource, $payloadModulePath, $compatibilityPath, $versionPath, $guiScriptPath, $cliScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw ('A required executable build input is missing: {0}' -f [System.IO.Path]::GetFileName($requiredPath))
    }
}
try {
    $configuration = Get-Content -LiteralPath $configurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw ('The executable build configuration is invalid JSON: {0}' -f $_.Exception.Message)
}
Import-Module -Name $buildModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
Import-Module -Name $payloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null

$seedRelativePath = ([string]$configuration.seed.relativePath).Replace('/', '\')
if ([string]::IsNullOrWhiteSpace($SeedPath)) {
    $SeedPath = Join-Path $repositoryRoot $seedRelativePath
}
elseif (-not [System.IO.Path]::IsPathRooted($SeedPath)) {
    $SeedPath = Join-Path $repositoryRoot $SeedPath
}
if (-not (Test-Path -LiteralPath $SeedPath -PathType Leaf)) { throw 'The pinned IExpress seed executable is missing.' }
$seedFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SeedPath -ErrorAction Stop).Path)

$sourcePayloadStatus = Test-AppInstallerPayload -RootPath $repositoryRoot
if (-not $sourcePayloadStatus.IsValid -or $sourcePayloadStatus.Mode -ne 'source') {
    throw 'The source payload failed validation or contains stale package integrity metadata.'
}
$sourceInventory = @(Get-AppInstallerPayloadFiles -RootPath $repositoryRoot)
if ($sourceInventory.Count -ne $sourcePayloadStatus.FileCount) { throw 'The source inventory changed during validation.' }

$versionText = Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop
$guiSource = Get-Content -LiteralPath $guiScriptPath -Raw -ErrorAction Stop
$cliSource = Get-Content -LiteralPath $cliScriptPath -Raw -ErrorAction Stop
$readmeText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw -ErrorAction Stop
$versionContract = Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText
if (-not $versionContract.IsValid) {
    throw ('Executable versions are inconsistent: {0}' -f ($versionContract.Errors -join ' '))
}
$guiVersion = $versionContract.GuiVersion
$cliVersion = $versionContract.CliVersion

try {
    $compatibility = Get-Content -LiteralPath $compatibilityPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw ('The Windows compatibility contract is invalid JSON: {0}' -f $_.Exception.Message)
}
$compatibilityContract = Test-InstallerExeCompatibilityContract -Compatibility $compatibility -Configuration $configuration
if (-not $compatibilityContract.IsValid) {
    throw ('The executable build configuration is stale: {0}' -f ($compatibilityContract.Errors -join ' '))
}
$context = Get-InstallerExeBuildContext -Configuration $configuration -RepositoryRoot $repositoryRoot -SeedPath $seedFullPath
$contextStatus = Test-InstallerExeBuildContext -Configuration $configuration -Context $context
if (-not $contextStatus.IsValid) {
    throw ('Executable build prerequisites failed:' + [Environment]::NewLine + ' - ' + ($contextStatus.Errors -join ([Environment]::NewLine + ' - ')))
}

foreach ($payloadFile in $sourceInventory) {
    if ($payloadFile.Path -match '[^\x20-\x7E]') {
        throw ('The Windows cabinet payload path must use ASCII characters: {0}' -f $payloadFile.Path)
    }
}
$syntaxFailures = New-Object System.Collections.Generic.List[string]
foreach ($payloadFile in $sourceInventory) {
    if ([System.IO.Path]::GetExtension($payloadFile.Path) -notin @('.ps1', '.psm1')) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($payloadFile.Source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        foreach ($parseError in $parseErrors) {
            $syntaxFailures.Add(('{0}:{1}: {2}' -f $payloadFile.Path, $parseError.Extent.StartLineNumber, $parseError.Message))
        }
    }
}
if ($syntaxFailures.Count -gt 0) {
    throw ('A runtime payload source file failed PowerShell parsing:' + [Environment]::NewLine + ' - ' + ($syntaxFailures -join ([Environment]::NewLine + ' - ')))
}

if ([string]$configuration.artifact.identity -cne 'app-installer-versioned-release-v1') {
    throw 'The build configuration does not identify the current versioned release artifact.'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputName = ([string]$configuration.artifact.outputNamePattern).Replace('{guiVersion}', $guiVersion)
    $OutputPath = Join-Path (Join-Path $repositoryRoot ([string]$configuration.artifact.defaultOutputDirectory)) $outputName
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repositoryRoot $OutputPath }
$expectedOutputName = ([string]$configuration.artifact.outputNamePattern).Replace('{guiVersion}', $guiVersion)
if ([System.IO.Path]::GetFileName($OutputPath) -cne $expectedOutputName) {
    throw ('The build output name must match the current versioned artifact pattern: {0}' -f $expectedOutputName)
}

$protectedLegacyPaths = New-Object 'System.Collections.Generic.List[string]'
$legacyPathsSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$legacyArtifactRecords = @($configuration.legacyArtifacts)
if ($legacyArtifactRecords.Count -eq 0) { throw 'The build configuration must identify and protect tracked legacy executable paths.' }
foreach ($legacyArtifact in $legacyArtifactRecords) {
    $legacyRelativePath = ([string]$legacyArtifact.path).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($legacyRelativePath) -or
        [System.IO.Path]::IsPathRooted($legacyRelativePath) -or
        $legacyRelativePath.Split([char[]]@('\', '/')) -contains '..' -or
        [bool]$legacyArtifact.releaseEligible -or
        [string]$legacyArtifact.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'The legacy artifact inventory contains an invalid, unsafe, or release-eligible record.'
    }
    $legacyFullPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $legacyRelativePath))
    if (-not (Test-InstallerExeContainedPath -Path $legacyFullPath -RootPath $repositoryRoot) -or
        -not $legacyPathsSeen.Add($legacyFullPath)) {
        throw 'The legacy artifact inventory contains a duplicate path or a path outside the repository.'
    }
    $protectedLegacyPaths.Add($legacyFullPath)
}

$output = Assert-InstallerExeBuildOutputPath `
    -OutputPath $OutputPath `
    -SeedPath $seedFullPath `
    -ProtectedOutputPaths @($protectedLegacyPaths.ToArray())
$outputFullPath = $output.OutputPath
$outputManifestPath = $output.ManifestPath
$outputDirectory = $output.OutputDirectory
if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Build the pinned unsigned x64 IExpress package and provenance manifest')) { return }
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('InstallerExeBuild-' + [guid]::NewGuid().ToString('N'))))
if (-not (Test-InstallerExeContainedPath -Path $buildRoot -RootPath $tempBase)) {
    throw 'The temporary build path resolved outside the operating system temporary directory.'
}
if ($buildRoot -match '[^\x20-\x7E]') {
    throw 'The temporary build path must use ASCII characters because Expand.exe does not preserve Unicode command-line paths.'
}

$makeCabPath = Join-Path $env:WINDIR ([string]$configuration.packager.makeCab.relativePath.Replace('/', '\'))
$expandPath = Join-Path $env:WINDIR ([string]$configuration.packager.expand.relativePath.Replace('/', '\'))
$fixedCabinetTimestamp = [System.DateTime]::SpecifyKind([System.DateTime]::new(2000, 1, 1, 12, 0, 0), [System.DateTimeKind]::Local)
$outputTempPath = $null
$manifestTempPath = $null
$publishedArtifact = $false
$publishedManifest = $false
$stagedManifestHash = $null
$buildCompleted = $false

try {
    $stagePath = Join-Path $buildRoot 'payload'
    New-Item -ItemType Directory -Path $stagePath -Force -ErrorAction Stop | Out-Null
    $inventory = @(New-InstallerExeBuildInventory -Files $sourceInventory)
    $sourceByPath = @{}
    foreach ($payloadFile in $sourceInventory) { $sourceByPath[$payloadFile.Path.ToLowerInvariant()] = $payloadFile }

    $fileMap = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($record in $inventory) {
        $index++
        $payloadFile = $sourceByPath[$record.path.ToLowerInvariant()]
        $stageName = 'P{0:D5}{1}' -f $index, [System.IO.Path]::GetExtension($record.path)
        $stagedFile = Join-Path $stagePath $stageName
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $stagePath ($record.path.Replace('/', '\'))))
        if (-not (Test-InstallerExeContainedPath -Path $destinationPath -RootPath $stagePath)) {
            throw ('A runtime payload path escapes the staging directory: {0}' -f $record.path)
        }
        $destinationDirectory = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
        }
        Copy-Item -LiteralPath $payloadFile.Source -Destination $stagedFile -Force -ErrorAction Stop
        Copy-Item -LiteralPath $stagedFile -Destination $destinationPath -Force -ErrorAction Stop
        [System.IO.File]::SetLastWriteTime($stagedFile, $fixedCabinetTimestamp)
        [System.IO.File]::SetLastWriteTime($destinationPath, $fixedCabinetTimestamp)
        $fileMap.Add([PSCustomObject]@{ StageName = $stageName; Relative = $record.path; Source = $destinationPath })
    }

    Write-AppInstallerPayloadIntegrity -RootPath $stagePath | Out-Null
    $stagedPayloadStatus = Test-AppInstallerPayload -RootPath $stagePath -RequirePackage
    if (-not $stagedPayloadStatus.IsValid -or
        $stagedPayloadStatus.Version -ne $sourcePayloadStatus.Version -or
        [string]$stagedPayloadStatus.Integrity.cliVersion -ne $cliVersion) {
        throw 'The staged payload did not match the validated GUI and CLI versions or failed integrity validation.'
    }
    $generatedIntegrityPath = Join-Path $stagePath 'payload-integrity.json'
    $integrityStageName = 'P{0:D5}.json' -f ($fileMap.Count + 1)
    $integrityStagedFile = Join-Path $stagePath $integrityStageName
    Copy-Item -LiteralPath $generatedIntegrityPath -Destination $integrityStagedFile -Force -ErrorAction Stop
    [System.IO.File]::SetLastWriteTime($integrityStagedFile, $fixedCabinetTimestamp)
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
    $ddfText = ($ddfLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($ddfPath, $ddfText, [System.Text.Encoding]::ASCII)
    $makeCabOutputPath = Join-Path $buildRoot 'makecab.out'
    $makeCabErrorPath = Join-Path $buildRoot 'makecab.err'
    $makeCabProcess = Start-Process -FilePath $makeCabPath -ArgumentList ('/F "{0}"' -f $ddfPath) -WorkingDirectory $stagePath -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $makeCabOutputPath -RedirectStandardError $makeCabErrorPath
    if ($makeCabProcess.ExitCode -ne 0) {
        $makeCabDetails = (Get-Content -LiteralPath $makeCabOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $makeCabErrorPath -Raw -ErrorAction SilentlyContinue)
        throw ('MakeCab failed to create the payload. Exit code: {0}. {1}' -f $makeCabProcess.ExitCode, $makeCabDetails)
    }

    $cabPath = Join-Path $stagePath 'payload.cab'
    if (-not (Test-Path -LiteralPath $cabPath -PathType Leaf)) { throw 'MakeCab returned success without creating the payload cabinet.' }
    $verificationPath = Join-Path $buildRoot 'verified-payload'
    New-Item -ItemType Directory -Path $verificationPath -Force -ErrorAction Stop | Out-Null
    $expandOutputPath = Join-Path $buildRoot 'expand.out'
    $expandErrorPath = Join-Path $buildRoot 'expand.err'
    $expandProcess = Start-Process -FilePath $expandPath -ArgumentList ('-r "{0}" -F:* "{1}"' -f $cabPath, $verificationPath) -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $expandOutputPath -RedirectStandardError $expandErrorPath
    if ($expandProcess.ExitCode -ne 0) {
        $expandDetails = (Get-Content -LiteralPath $expandOutputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $expandErrorPath -Raw -ErrorAction SilentlyContinue)
        throw ('The generated cabinet could not be inspected. Expand exit code: {0}. {1}' -f $expandProcess.ExitCode, $expandDetails)
    }
    foreach ($mapItem in $fileMap) {
        $extractedPath = Join-Path $verificationPath $mapItem.Relative
        if (-not (Test-Path -LiteralPath $extractedPath -PathType Leaf)) {
            throw ('The payload cabinet omitted a required file: {0}' -f $mapItem.Relative)
        }
        $sourceHash = (Get-FileHash -LiteralPath $mapItem.Source -Algorithm SHA256).Hash
        $extractedHash = (Get-FileHash -LiteralPath $extractedPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $extractedHash) { throw ('The payload cabinet changed file contents: {0}' -f $mapItem.Relative) }
    }
    $extractedFiles = @(Get-ChildItem -LiteralPath $verificationPath -File -Recurse -Force -ErrorAction Stop | ForEach-Object {
        $_.FullName.Substring($verificationPath.TrimEnd([char[]]@([char]92, [char]47)).Length).TrimStart([char[]]@([char]92, [char]47)).Replace('\', '/')
    })
    $expectedCabinetPaths = @($fileMap | ForEach-Object { $_.Relative } | Sort-Object)
    $actualCabinetPaths = @($extractedFiles | Sort-Object)
    $cabinetDifferences = @(Compare-Object -ReferenceObject $expectedCabinetPaths -DifferenceObject $actualCabinetPaths)
    if ($cabinetDifferences.Count -gt 0) {
        throw ('The cabinet inventory differs from the explicit payload allowlist: {0}' -f (($cabinetDifferences | ForEach-Object { $_.InputObject }) -join ', '))
    }

    Add-Type -Path $metadataSource -ErrorAction Stop
    $seedBytes = [System.IO.File]::ReadAllBytes($seedFullPath)
    $seedText = [System.Text.Encoding]::ASCII.GetString($seedBytes)
    if (-not $seedText.Contains('cmd.exe /c .\install.bat')) { throw 'The pinned IExpress seed does not launch install.bat.' }
    if (-not $seedText.Contains('myTech.Today_Install-GUI')) { throw 'The pinned IExpress seed does not identify the current product package.' }
    $buildExePath = Join-Path $buildRoot 'AppInstaller.exe'
    Copy-Item -LiteralPath $seedFullPath -Destination $buildExePath -Force -ErrorAction Stop
    $cabinetBytes = [System.IO.File]::ReadAllBytes($cabPath)
    [InstallerExecutableVersionInfo]::ReplaceCabinetResource($buildExePath, $cabinetBytes)

    $hostExecutable = (Get-Process -Id $PID -ErrorAction Stop).Path
    $metadataArguments = '-NoProfile -File "{0}" -InputPath "{1}" -OutputPath "{1}"' -f $metadataScript, $buildExePath
    $metadataProcess = Start-Process -FilePath $hostExecutable -ArgumentList $metadataArguments -PassThru -Wait -WindowStyle Hidden
    if ($metadataProcess.ExitCode -ne 0) { throw ('The executable metadata step failed. Exit code: {0}' -f $metadataProcess.ExitCode) }

    $embeddedCabinet = [InstallerExecutableVersionInfo]::ReadCabinetResource($buildExePath)
    if ($embeddedCabinet.Length -ne $cabinetBytes.Length) { throw 'The executable metadata update changed the embedded cabinet length.' }
    for ($byteIndex = 0; $byteIndex -lt $cabinetBytes.Length; $byteIndex++) {
        if ($embeddedCabinet[$byteIndex] -ne $cabinetBytes[$byteIndex]) { throw 'The executable metadata update changed the embedded cabinet contents.' }
    }
    $buildArchitecture = Get-InstallerExeMachineArchitecture -Path $buildExePath
    if ($buildArchitecture -ne [string]$configuration.artifact.architecture) {
        throw ('The generated executable architecture is {0}, expected {1}.' -f $buildArchitecture, $configuration.artifact.architecture)
    }
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($buildExePath)
    if ($versionInfo.FileVersion -ne ($guiVersion + '.0') -or
        $versionInfo.ProductName -ne 'myTech.Today App Installer' -or
        -not $versionInfo.Comments.Contains('compatibility.json')) {
        throw 'The executable version metadata does not match VERSION and compatibility.json.'
    }
    $buildSignature = Get-AuthenticodeSignature -FilePath $buildExePath
    $buildSignerSubject = if ($null -ne $buildSignature.SignerCertificate) { [string]$buildSignature.SignerCertificate.Subject } else { '' }
    Assert-InstallerExeUnsignedArtifact -SignatureStatus ([string]$buildSignature.Status) -SignerSubject $buildSignerSubject

    $buildInputs = @(Get-InstallerExeInputInventory -RepositoryRoot $repositoryRoot -RelativePaths @(
        'tools/Build-InstallerExe.ps1',
        'tools/InstallerExecutableBuild.psm1',
        'tools/InstallerExecutableVersionInfo.cs',
        'tools/Set-InstallerExeMetadata.ps1',
        'tools/installer-exe-build.json'
    ))
    $sourceRevision = Get-InstallerExeSourceRevision -RepositoryRoot $repositoryRoot
    $payloadManifestPath = Join-Path $repositoryRoot 'payload-manifest.json'
    $payloadManifestHash = (Get-FileHash -LiteralPath $payloadManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventoryHash = Get-InstallerExeBuildInventorySha256 -Inventory $inventory
    $buildArtifact = Get-InstallerExeBuildFileObservation -Path $buildExePath

    $provenance = [PSCustomObject][ordered]@{
        schemaVersion = 1
        artifact = [PSCustomObject][ordered]@{
            identity = [string]$configuration.artifact.identity
            fileName = [System.IO.Path]::GetFileName($outputFullPath)
            format = [string]$configuration.artifact.format
            architecture = $buildArchitecture
            fileVersion = [string]$versionInfo.FileVersion
            byteLength = [long](Get-Item -LiteralPath $buildExePath).Length
            sha256 = [string]$buildArtifact.Sha256.ToLowerInvariant()
            authenticodeStatus = [string]$buildSignature.Status
            signerSubject = ''
        }
        source = [PSCustomObject][ordered]@{
            revision = $sourceRevision.commit
            worktreeClean = [bool]$sourceRevision.worktreeClean
            changedFiles = @($sourceRevision.changedFiles)
            buildInputs = $buildInputs
        }
        toolchain = [PSCustomObject][ordered]@{
            windowsBuild = [int]$context.Host.WindowsBuild
            architecture = [string]$context.Host.ProcessArchitecture
            powerShell = [PSCustomObject][ordered]@{
                edition = [string]$context.PowerShell.Edition
                version = [string]$context.PowerShell.Version
                fileVersion = [string]$context.PowerShell.File.FileVersion
                sha256 = [string]$context.PowerShell.File.Sha256.ToLowerInvariant()
                signerSubject = [string]$context.PowerShell.File.SignerSubject
            }
            dotnetRuntime = [PSCustomObject][ordered]@{
                version = [string]$context.DotNetRuntime.Version
                files = @($context.DotNetRuntime.Files | ForEach-Object {
                    [PSCustomObject][ordered]@{ path = [string]$_.Path; fileVersion = [string]$_.FileVersion; sha256 = [string]$_.Sha256.ToLowerInvariant(); signerSubject = [string]$_.SignerSubject }
                })
            }
            compiler = [PSCustomObject][ordered]@{
                name = [string]$context.Compiler.Name
                version = [string]$context.Compiler.Version
                dotnetSdkRequired = [bool]$configuration.host.compiler.dotnetSdkRequired
                assemblies = @($context.Compiler.Assemblies | ForEach-Object {
                    [PSCustomObject][ordered]@{ name = [string]$_.Name; fileVersion = [string]$_.FileVersion; sha256 = [string]$_.Sha256.ToLowerInvariant(); signerSubject = [string]$_.SignerSubject }
                })
            }
            makeCab = ConvertTo-InstallerExeToolObservation -Name 'MakeCab' -Observation $context.Packager.MakeCab
            expand = ConvertTo-InstallerExeToolObservation -Name 'Expand' -Observation $context.Packager.Expand
            seed = [PSCustomObject][ordered]@{
                relativePath = $seedRelativePath.Replace('\', '/')
                fileVersion = [string]$context.Seed.File.FileVersion
                sha256 = [string]$context.Seed.File.Sha256.ToLowerInvariant()
                architecture = [string]$context.Seed.Architecture
                authenticodeStatus = [string]$context.Seed.File.SignatureStatus
            }
        }
        payload = [PSCustomObject][ordered]@{
            manifestPath = 'payload-manifest.json'
            manifestSha256 = $payloadManifestHash
            inventorySha256 = $inventoryHash
            fileCount = $inventory.Count
            files = $inventory
        }
        reproducibility = [PSCustomObject][ordered]@{
            buildTimestampRecorded = $false
            cabinetFileTimestamp = [string]$configuration.reproducibility.cabinetFileTimestamp
            normalizedPayloadInventory = 'SHA-256 over ordinal-ignore-case sorted path, byteLength, and SHA-256 records'
            binaryComparison = 'Compare artifact.sha256 across clean builds with identical source revision and toolchain pins.'
        }
    }

    $manifestJson = ConvertTo-Json -InputObject $provenance -Depth 16
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $outputTempPath = Join-Path $outputDirectory ('.AppInstaller-' + [guid]::NewGuid().ToString('N') + '.tmp.exe')
    $manifestTempPath = Join-Path $outputDirectory ('.AppInstaller-' + [guid]::NewGuid().ToString('N') + '.tmp.json')
    if (-not (Test-InstallerExeContainedPath -Path $outputTempPath -RootPath $outputDirectory) -or
        -not (Test-InstallerExeContainedPath -Path $manifestTempPath -RootPath $outputDirectory)) {
        throw 'The staged executable outputs resolved outside the requested output directory.'
    }
    Copy-Item -LiteralPath $buildExePath -Destination $outputTempPath -Force -ErrorAction Stop
    [System.IO.File]::WriteAllText($manifestTempPath, $manifestJson + [Environment]::NewLine, $utf8NoBom)
    $stagedManifestHash = (Get-FileHash -LiteralPath $manifestTempPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $stagedHash = (Get-FileHash -LiteralPath $outputTempPath -Algorithm SHA256).Hash
    if ($stagedHash -ne [string]$buildArtifact.Sha256) { throw 'The staged executable changed after provenance was recorded.' }
    $stagedSignature = Get-AuthenticodeSignature -FilePath $outputTempPath
    $stagedSignerSubject = if ($null -ne $stagedSignature.SignerCertificate) { [string]$stagedSignature.SignerCertificate.Subject } else { '' }
    Assert-InstallerExeUnsignedArtifact -SignatureStatus ([string]$stagedSignature.Status) -SignerSubject $stagedSignerSubject

    [System.IO.File]::Move($outputTempPath, $outputFullPath)
    $outputTempPath = $null
    $publishedArtifact = $true
    [System.IO.File]::Move($manifestTempPath, $outputManifestPath)
    $manifestTempPath = $null
    $publishedManifest = $true
    $publishedArtifactHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
    $publishedManifest = Get-Content -LiteralPath $outputManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $publishedSignature = Get-AuthenticodeSignature -FilePath $outputFullPath
    if ($publishedArtifactHash -ne [string]$buildArtifact.Sha256 -or
        [string]$publishedManifest.artifact.sha256 -ne [string]$publishedArtifactHash.ToLowerInvariant() -or
        [string]$publishedSignature.Status -ne 'NotSigned') {
        throw 'The published executable or provenance manifest failed final validation.'
    }

    $buildCompleted = $true
    Write-Output ('[OK] Built unsigned {0} {1} ({2})' -f [string]$configuration.artifact.format, $versionInfo.FileVersion, $buildArchitecture)
    Write-Output ('[OK] Artifact SHA-256: {0}' -f $publishedArtifactHash)
    Write-Output ('[OK] Provenance manifest: {0}' -f $outputManifestPath)
}
finally {
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
    if ($KeepBuildFilesOnFailure -and -not $buildCompleted) {
        Write-Warning ('Build files retained for inspection: {0}' -f $resolvedBuildRoot)
    }
    elseif (Test-InstallerExeContainedPath -Path $resolvedBuildRoot -RootPath $tempBase) {
        Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($outputTempPath -and (Test-InstallerExeContainedPath -Path ([System.IO.Path]::GetFullPath($outputTempPath)) -RootPath $outputDirectory)) {
        Remove-Item -LiteralPath $outputTempPath -Force -ErrorAction SilentlyContinue
    }
    if ($manifestTempPath -and (Test-InstallerExeContainedPath -Path ([System.IO.Path]::GetFullPath($manifestTempPath)) -RootPath $outputDirectory)) {
        Remove-Item -LiteralPath $manifestTempPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $buildCompleted -and $publishedArtifact -and
        (Test-InstallerExeContainedPath -Path $outputFullPath -RootPath $outputDirectory) -and
        (Test-Path -LiteralPath $outputFullPath -PathType Leaf)) {
        $publishedHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        if ($publishedHash -eq [string]$buildArtifact.Sha256) { Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue }
    }
    if (-not $buildCompleted -and $publishedManifest -and
        (Test-InstallerExeContainedPath -Path $outputManifestPath -RootPath $outputDirectory) -and
        (Test-Path -LiteralPath $outputManifestPath -PathType Leaf)) {
        $publishedManifestHash = (Get-FileHash -LiteralPath $outputManifestPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        if ($publishedManifestHash -eq $stagedManifestHash) { Remove-Item -LiteralPath $outputManifestPath -Force -ErrorAction SilentlyContinue }
    }
}
