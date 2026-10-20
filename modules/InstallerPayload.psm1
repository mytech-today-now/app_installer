<#
.SYNOPSIS
    Resolves, validates, stages, and installs the App Installer runtime payload.

.DESCRIPTION
    The checked-in payload-manifest.json is the explicit source allowlist. Package
    builds and self-installs create payload-integrity.json with version, inventory,
    lengths, and SHA-256 values. These hashes detect incomplete or damaged payloads;
    they do not authenticate the unsigned IExpress executable.
#>

Set-StrictMode -Version 2.0

function Get-PayloadFullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'The payload manifest contains an empty relative path.'
    }

    $normalizedRelativePath = $RelativePath.Replace('\', '/')
    if ($normalizedRelativePath.StartsWith('/') -or
        $normalizedRelativePath -match '^[A-Za-z]:' -or
        $normalizedRelativePath -match '(^|/)\.\.?(/|$)' -or
        $normalizedRelativePath.Contains(':') -or
        $normalizedRelativePath.Contains('*') -or
        $normalizedRelativePath.Contains('?')) {
        throw "The payload manifest contains an unsafe path: $RelativePath"
    }

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    $rootWithoutEndingSeparator = $rootFullPath.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    if ([string]::IsNullOrWhiteSpace($rootWithoutEndingSeparator)) {
        $rootWithoutEndingSeparator = [System.IO.Path]::GetPathRoot($rootFullPath).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    }

    $nativeRelativePath = $normalizedRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootFullPath $nativeRelativePath))
    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $rootPrefix = $rootWithoutEndingSeparator + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
        throw "The payload path escapes its root: $RelativePath"
    }

    return $fullPath
}

function Test-PayloadPathExcluded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [object]$Exclusions
    )

    $normalizedPath = $RelativePath.Replace('\', '/')
    $segments = @($normalizedPath -split '/')
    foreach ($directoryName in @($Exclusions.directoryNames)) {
        if ($segments -contains [string]$directoryName) {
            return $true
        }
    }

    $fileName = [System.IO.Path]::GetFileName($normalizedPath)
    foreach ($prefix in @($Exclusions.fileNamePrefixes)) {
        if ($fileName.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $extension = [System.IO.Path]::GetExtension($fileName)
    foreach ($excludedExtension in @($Exclusions.extensions)) {
        if ($extension.Equals([string]$excludedExtension, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-AppInstallerPayloadManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $manifestPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath 'payload-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required payload manifest is missing: $manifestPath"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The payload manifest is invalid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $manifest -or [int]$manifest.formatVersion -ne 1) {
        throw 'The payload manifest has an unsupported or missing formatVersion.'
    }
    if ([string]$manifest.productVersionFile -ne 'VERSION' -or
        [string]$manifest.generatedIntegrityFile -ne 'payload-integrity.json') {
        throw 'The payload manifest does not name the required version and integrity metadata files.'
    }
    if (@($manifest.requiredFiles).Count -eq 0 -or @($manifest.fileSets).Count -eq 0) {
        throw 'The payload manifest must define requiredFiles and fileSets.'
    }
    if ($null -eq $manifest.exclusions -or $null -eq $manifest.features) {
        throw 'The payload manifest is missing its exclusion or feature policy.'
    }

    return $manifest
}

function Get-AppInstallerPayloadFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        throw "Payload source root does not exist: $rootFullPath"
    }
    $manifest = Get-AppInstallerPayloadManifest -RootPath $rootFullPath
    $filesByPath = @{}

    foreach ($requiredPath in @($manifest.requiredFiles)) {
        $relativePath = ([string]$requiredPath).Replace('\', '/')
        if (Test-PayloadPathExcluded -RelativePath $relativePath -Exclusions $manifest.exclusions) {
            throw "A required payload file is excluded by policy: $relativePath"
        }
        $fullPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Required payload file is missing: $relativePath"
        }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in the payload: $relativePath"
        }
        $filesByPath[$relativePath.ToLowerInvariant()] = [PSCustomObject]@{
            Path = $relativePath
            Source = $fullPath
        }
    }

    foreach ($featureName in @($manifest.features.PSObject.Properties.Name)) {
        foreach ($featurePathValue in @($manifest.features.$featureName)) {
            $featurePath = ([string]$featurePathValue).Replace('\', '/')
            $featureFullPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $featurePath
            if (-not (Test-Path -LiteralPath $featureFullPath -PathType Leaf)) {
                throw "Required $featureName payload dependency is missing: $featurePath"
            }
            $featureItem = Get-Item -LiteralPath $featureFullPath -Force -ErrorAction Stop
            if (($featureItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not allowed in the payload: $featurePath"
            }
            $filesByPath[$featurePath.ToLowerInvariant()] = [PSCustomObject]@{
                Path = $featurePath
                Source = $featureFullPath
            }
        }
    }

    foreach ($fileSet in @($manifest.fileSets)) {
        $directoryRelativePath = ([string]$fileSet.path).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($directoryRelativePath)) {
            throw 'The payload manifest contains a file set with an empty path.'
        }
        $directoryPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $directoryRelativePath
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
            throw "Required payload directory is missing: $directoryRelativePath"
        }
        $directoryItem = Get-Item -LiteralPath $directoryPath -Force -ErrorAction Stop
        if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in the payload: $directoryRelativePath"
        }

        $extensions = @($fileSet.extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($extensions.Count -eq 0 -or @($extensions | Where-Object { $_ -notmatch '^\.[a-z0-9]+$' }).Count -gt 0) {
            throw "The payload manifest has invalid extensions for file set: $directoryRelativePath"
        }

        $explicitFileNamesProperty = $fileSet.PSObject.Properties['fileNames']
        if ($null -ne $explicitFileNamesProperty) {
            foreach ($fileNameValue in @($explicitFileNamesProperty.Value)) {
                $fileName = [string]$fileNameValue
                if ([System.IO.Path]::GetFileName($fileName) -ne $fileName -or [string]::IsNullOrWhiteSpace($fileName)) {
                    throw "The payload manifest contains an unsafe file name in ${directoryRelativePath}: $fileName"
                }
                $relativePath = $directoryRelativePath.TrimEnd('/') + '/' + $fileName
                if (Test-PayloadPathExcluded -RelativePath $relativePath -Exclusions $manifest.exclusions) {
                    throw "A required payload file is excluded by policy: $relativePath"
                }
                $explicitFilePath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $relativePath
                if (-not (Test-Path -LiteralPath $explicitFilePath -PathType Leaf)) {
                    throw "Required payload file is missing: $relativePath"
                }
                if ($extensions -notcontains [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()) {
                    throw "The payload manifest file extension is not allowed: $relativePath"
                }
                $explicitFileItem = Get-Item -LiteralPath $explicitFilePath -Force -ErrorAction Stop
                if (($explicitFileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Reparse points are not allowed in the payload: $relativePath"
                }
                $filesByPath[$relativePath.ToLowerInvariant()] = [PSCustomObject]@{
                    Path = $relativePath
                    Source = $explicitFilePath
                }
            }
            continue
        }

        $items = @(Get-ChildItem -LiteralPath $directoryPath -File -Recurse -Force -ErrorAction Stop)
        $directoryItems = @(Get-ChildItem -LiteralPath $directoryPath -Directory -Recurse -Force -ErrorAction Stop)
        foreach ($item in @($items) + @($directoryItems)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not allowed in payload file sets: $($item.FullName)"
            }
        }

        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($rootFullPath.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)).Length).TrimStart([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)).Replace('\', '/')
            if (Test-PayloadPathExcluded -RelativePath $relativePath -Exclusions $manifest.exclusions) {
                continue
            }
            $extension = [System.IO.Path]::GetExtension($item.Name).ToLowerInvariant()
            if ($extensions -notcontains $extension) {
                continue
            }
            $safeFullPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $relativePath
            if (-not $safeFullPath.Equals($item.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "The payload inventory resolved an unexpected source path: $relativePath"
            }
            $filesByPath[$relativePath.ToLowerInvariant()] = [PSCustomObject]@{
                Path = $relativePath
                Source = $safeFullPath
            }
        }
    }

    $result = @($filesByPath.Values | Sort-Object -Property Path)
    if ($result.Count -eq 0) {
        throw 'The payload inventory is empty.'
    }

    return $result
}

function Get-AppInstallerPayloadVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $manifest = Get-AppInstallerPayloadManifest -RootPath $RootPath
    $versionPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath ([string]$manifest.productVersionFile)
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw 'The payload version file is missing.'
    }
    $versionText = Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop
    $versionMatch = [regex]::Match($versionText, '(?m)^\*\*GUI Version:\*\*\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
    if (-not $versionMatch.Success) {
        throw 'The GUI payload version could not be read from VERSION.'
    }

    return $versionMatch.Groups[1].Value
}

function Get-AppInstallerCliPayloadVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $versionPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath 'VERSION'
    $versionText = Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop
    $versionMatch = [regex]::Match($versionText, '(?m)^\*\*CLI Version:\*\*\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
    if (-not $versionMatch.Success) {
        throw 'The CLI payload version could not be read from VERSION.'
    }

    return $versionMatch.Groups[1].Value
}

function Write-AppInstallerPayloadIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    $manifest = Get-AppInstallerPayloadManifest -RootPath $rootFullPath
    $version = Get-AppInstallerPayloadVersion -RootPath $rootFullPath
    $cliVersion = Get-AppInstallerCliPayloadVersion -RootPath $rootFullPath
    $manifestPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath 'payload-manifest.json'
    $inventory = @(Get-AppInstallerPayloadFiles -RootPath $rootFullPath)
    $fileRecords = New-Object System.Collections.Generic.List[object]

    foreach ($file in $inventory) {
        $item = Get-Item -LiteralPath $file.Source -ErrorAction Stop
        $fileRecords.Add([PSCustomObject]@{
            path = $file.Path
            length = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        })
    }

    $integrity = [PSCustomObject]@{
        formatVersion = 1
        mode = 'packaged'
        version = $version
        cliVersion = $cliVersion
        manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        files = @($fileRecords.ToArray())
    }
    $integrityPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath ([string]$manifest.generatedIntegrityFile)
    $temporaryPath = '{0}.{1}.tmp' -f $integrityPath, [guid]::NewGuid().ToString('N')
    try {
        $json = ConvertTo-Json -InputObject $integrity -Depth 8
        $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $integrityPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $integrity
}

function Test-AppInstallerPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [switch]$RequirePackage
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    $manifest = Get-AppInstallerPayloadManifest -RootPath $rootFullPath
    $inventory = @(Get-AppInstallerPayloadFiles -RootPath $rootFullPath)
    $version = Get-AppInstallerPayloadVersion -RootPath $rootFullPath
    $cliVersion = Get-AppInstallerCliPayloadVersion -RootPath $rootFullPath
    $appManifestPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath 'apps-manifest.json'
    try {
        $appManifest = Get-Content -LiteralPath $appManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The application catalog is missing or invalid: $($_.Exception.Message)"
    }

    $applications = if ($null -ne $appManifest.apps) {
        @($appManifest.apps)
    }
    elseif ($null -ne $appManifest.applications) {
        @($appManifest.applications)
    }
    elseif ($appManifest -is [System.Array]) {
        @($appManifest)
    }
    else {
        throw 'The application catalog has no apps collection.'
    }
    if ($applications.Count -eq 0) {
        throw 'The application catalog contains no application definitions.'
    }

    foreach ($application in $applications) {
        $scriptNameProperty = $application.PSObject.Properties['scriptName']
        $scriptProperty = $application.PSObject.Properties['script']
        $scriptName = if ($null -ne $scriptNameProperty) { [string]$scriptNameProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($scriptName)) {
            $scriptName = if ($null -ne $scriptProperty) { [string]$scriptProperty.Value } else { '' }
        }
        if ([string]::IsNullOrWhiteSpace($scriptName)) {
            continue
        }
        if ([System.IO.Path]::GetFileName($scriptName) -ne $scriptName -or
            [System.IO.Path]::GetExtension($scriptName) -ne '.ps1') {
            throw "The application catalog contains an unsafe script name: $scriptName"
        }
        $scriptRelativePath = 'apps/' + $scriptName
        $scriptPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $scriptRelativePath
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "The application catalog references a missing app script: $scriptRelativePath"
        }
    }

    $integrityPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath ([string]$manifest.generatedIntegrityFile)
    if (-not (Test-Path -LiteralPath $integrityPath -PathType Leaf)) {
        $gitMetadataPath = Join-Path $rootFullPath '.git'
        if ($RequirePackage -or -not (Test-Path -LiteralPath $gitMetadataPath)) {
            throw 'Packaged payload integrity metadata is missing. Rebuild or reinstall the complete payload.'
        }
        return [PSCustomObject]@{
            IsValid = $true
            Mode = 'source'
            Version = $version
            FileCount = $inventory.Count
            ManifestPath = (Get-PayloadFullPath -RootPath $rootFullPath -RelativePath 'payload-manifest.json')
            RootPath = $rootFullPath
        Integrity = $null
        }
    }

    try {
        $integrity = Get-Content -LiteralPath $integrityPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Payload integrity metadata is invalid JSON: $($_.Exception.Message)"
    }
    if ($null -eq $integrity -or [int]$integrity.formatVersion -ne 1 -or [string]$integrity.mode -ne 'packaged') {
        throw 'Payload integrity metadata has an unsupported format or mode.'
    }
    if ([string]$integrity.version -ne $version) {
        throw "Payload version mismatch. VERSION is $version but package metadata is $($integrity.version)."
    }
    if ([string]$integrity.cliVersion -ne $cliVersion) {
        throw "CLI payload version mismatch. VERSION is $cliVersion but package metadata is $($integrity.cliVersion)."
    }

    $manifestPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath 'payload-manifest.json'
    $currentManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if (-not ([string]$integrity.manifestSha256).Equals($currentManifestHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Payload manifest hash does not match the build metadata.'
    }

    $expectedPaths = @{}
    foreach ($file in $inventory) {
        $expectedPaths[$file.Path.ToLowerInvariant()] = $file
    }
    $recordPaths = @{}
    foreach ($record in @($integrity.files)) {
        $relativePath = ([string]$record.path).Replace('\', '/')
        $null = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $relativePath
        $pathKey = $relativePath.ToLowerInvariant()
        if ($recordPaths.ContainsKey($pathKey)) {
            throw "Payload integrity metadata contains a duplicate path: $relativePath"
        }
        if (-not $expectedPaths.ContainsKey($pathKey)) {
            throw "Payload integrity metadata contains an unexpected path: $relativePath"
        }
        $recordPaths[$pathKey] = $record
    }
    if ($recordPaths.Count -ne $expectedPaths.Count) {
        throw 'Payload integrity metadata does not cover the complete required inventory.'
    }

    foreach ($pathKey in @($expectedPaths.Keys)) {
        $file = $expectedPaths[$pathKey]
        $record = $recordPaths[$pathKey]
        if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
            throw "Required packaged file is missing: $($file.Path)"
        }
        $item = Get-Item -LiteralPath $file.Source -ErrorAction Stop
        if ([long]$record.length -ne [long]$item.Length) {
            throw "Packaged file length mismatch: $($file.Path)"
        }
        $actualHash = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not ([string]$record.sha256).Equals($actualHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Packaged file hash mismatch: $($file.Path)"
        }
    }

    return [PSCustomObject]@{
        IsValid = $true
        Mode = 'packaged'
        Version = $version
        FileCount = $inventory.Count
        ManifestPath = $manifestPath
        RootPath = $rootFullPath
        Integrity = $integrity
    }
}

function Copy-AppInstallerPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourceRoot)
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
    $separatorCharacters = [char[]]@([char]92, [char]47)
    if ($sourceFullPath.TrimEnd($separatorCharacters) -eq $destinationFullPath.TrimEnd($separatorCharacters)) {
        $status = Test-AppInstallerPayload -RootPath $destinationFullPath
        return [PSCustomObject]@{ Path = $destinationFullPath; Status = 'AlreadyInstalled'; FileCount = $status.FileCount; Version = $status.Version }
    }

    $manifest = Get-AppInstallerPayloadManifest -RootPath $sourceFullPath
    $sourceStatus = Test-AppInstallerPayload -RootPath $sourceFullPath
    $inventory = @(Get-AppInstallerPayloadFiles -RootPath $sourceFullPath)
    $sourceHashes = @{}
    if ($sourceStatus.Mode -eq 'packaged' -and $null -ne $sourceStatus.Integrity) {
        foreach ($record in @($sourceStatus.Integrity.files)) {
            $sourceHashes[[string]$record.path.ToLowerInvariant()] = [PSCustomObject]@{
                Length = [long]$record.length
                Sha256 = [string]$record.sha256
            }
        }
    }
    else {
        foreach ($file in $inventory) {
            $sourceItem = Get-Item -LiteralPath $file.Source -ErrorAction Stop
            $sourceHashes[$file.Path.ToLowerInvariant()] = [PSCustomObject]@{
                Length = [long]$sourceItem.Length
                Sha256 = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash
            }
        }
    }
    $destinationParent = Split-Path -Parent $destinationFullPath
    $destinationLeaf = Split-Path -Leaf $destinationFullPath
    if ([string]::IsNullOrWhiteSpace($destinationParent) -or [string]::IsNullOrWhiteSpace($destinationLeaf)) {
        throw 'The payload destination must be a named directory below an existing parent path.'
    }
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationParent -Force -ErrorAction Stop | Out-Null
    }
    if (Test-Path -LiteralPath $destinationFullPath -PathType Leaf) {
        throw "The payload destination is a file, not a directory: $destinationFullPath"
    }

    $stagePath = Join-Path $destinationParent ('.' + $destinationLeaf + '.staging-' + [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $destinationParent ('.' + $destinationLeaf + '.backup-' + [guid]::NewGuid().ToString('N'))
    $destinationMovedToBackup = $false
    $stageCommitted = $false
    try {
        New-Item -ItemType Directory -Path $stagePath -Force -ErrorAction Stop | Out-Null
        foreach ($file in $inventory) {
            $targetPath = Get-PayloadFullPath -RootPath $stagePath -RelativePath $file.Path
            $targetDirectory = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop | Out-Null
            }
            Copy-Item -LiteralPath $file.Source -Destination $targetPath -Force -ErrorAction Stop
        }

        foreach ($file in $inventory) {
            $targetPath = Get-PayloadFullPath -RootPath $stagePath -RelativePath $file.Path
            $targetItem = Get-Item -LiteralPath $targetPath -ErrorAction Stop
            $sourceHash = $sourceHashes[$file.Path.ToLowerInvariant()]
            if ([long]$targetItem.Length -ne $sourceHash.Length -or
                -not ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash).Equals($sourceHash.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Staged payload file does not match its validated source: $($file.Path)"
            }
        }

        Write-AppInstallerPayloadIntegrity -RootPath $stagePath | Out-Null
        Preserve-AppInstallerUserData -SourceRoot $destinationFullPath -DestinationRoot $stagePath -PayloadFiles $inventory
        $stagedStatus = Test-AppInstallerPayload -RootPath $stagePath -RequirePackage
        if (-not $stagedStatus.IsValid -or $stagedStatus.Version -ne $sourceStatus.Version) {
            throw 'The staged application payload did not pass integrity validation.'
        }

        if (Test-Path -LiteralPath $destinationFullPath -PathType Container) {
            [System.IO.Directory]::Move($destinationFullPath, $backupPath)
            $destinationMovedToBackup = $true
        }
        [System.IO.Directory]::Move($stagePath, $destinationFullPath)
        $stageCommitted = $true
        $installedStatus = Test-AppInstallerPayload -RootPath $destinationFullPath -RequirePackage
        if (-not $installedStatus.IsValid) {
            throw 'The installed application payload did not pass integrity validation.'
        }

        if ($destinationMovedToBackup -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        return [PSCustomObject]@{
            Path = $destinationFullPath
            Status = 'Installed'
            FileCount = $installedStatus.FileCount
            Version = $installedStatus.Version
        }
    }
    catch {
        if ($destinationMovedToBackup -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
            try {
                if (Test-Path -LiteralPath $destinationFullPath -PathType Container) {
                    Remove-Item -LiteralPath $destinationFullPath -Recurse -Force -ErrorAction Stop
                }
                [System.IO.Directory]::Move($backupPath, $destinationFullPath)
            }
            catch {
                throw "Payload installation failed and the previous installation could not be restored. Previous data remains at '$backupPath'. Original failure: $($_.Exception.Message)"
            }
        }
        throw
    }
    finally {
        if (-not $stageCommitted -and (Test-Path -LiteralPath $stagePath -PathType Container)) {
            Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Preserve-AppInstallerUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter(Mandatory = $true)]
        [object[]]$PayloadFiles
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        return
    }
    $payloadPaths = @{}
    foreach ($file in $PayloadFiles) {
        $payloadPaths[([string]$file.Path).ToLowerInvariant()] = $true
    }

    foreach ($relativeStatePath in @('queue-state.json', 'queue-state.json.bak')) {
        $sourcePath = Get-PayloadFullPath -RootPath $SourceRoot -RelativePath $relativeStatePath
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
            if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "User state cannot be a reparse point: $relativeStatePath"
            }
            $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $relativeStatePath
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop
        }
    }

    $sourceProfilesPath = Get-PayloadFullPath -RootPath $SourceRoot -RelativePath 'profiles'
    if (-not (Test-Path -LiteralPath $sourceProfilesPath -PathType Container)) {
        return
    }
    $profileDirectory = Get-Item -LiteralPath $sourceProfilesPath -Force -ErrorAction Stop
    if (($profileDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'User profiles directory cannot be a reparse point.'
    }

    foreach ($profile in @(Get-ChildItem -LiteralPath $sourceProfilesPath -File -Filter '*.json' -Force -ErrorAction Stop)) {
        if (($profile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "User profile cannot be a reparse point: $($profile.Name)"
        }
        $relativePath = 'profiles/' + $profile.Name
        if ($payloadPaths.ContainsKey($relativePath.ToLowerInvariant())) {
            continue
        }
        $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $relativePath
        Copy-Item -LiteralPath $profile.FullName -Destination $targetPath -Force -ErrorAction Stop
    }
}

Export-ModuleMember -Function @(
    'Copy-AppInstallerPayload',
    'Get-AppInstallerPayloadFiles',
    'Get-AppInstallerPayloadManifest',
    'Get-AppInstallerPayloadVersion',
    'Test-AppInstallerPayload',
    'Write-AppInstallerPayloadIntegrity'
)
