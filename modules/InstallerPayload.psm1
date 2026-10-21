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
$script:AppInstallerLifecycleTestHook = $null

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

    $applications = @(
        if ($null -ne $appManifest.apps) {
            $appManifest.apps
        }
        elseif ($null -ne $appManifest.applications) {
            $appManifest.applications
        }
        elseif ($appManifest -is [System.Array]) {
            $appManifest
        }
        else {
            throw 'The application catalog has no apps collection.'
        }
    )
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

function Get-AppInstallerInstallManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $manifestPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath '.app-installer-install.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The install ownership manifest is invalid JSON: $($_.Exception.Message)"
    }
    if ($null -eq $manifest -or [int]$manifest.formatVersion -ne 1 -or
        [string]$manifest.productId -cne 'mytech.today.app-installer' -or
        [string]::IsNullOrWhiteSpace([string]$manifest.version) -or
        [string]$manifest.state -notin @('installed', 'uninstalled') -or
        (@($manifest.ownedFiles).Count -eq 0 -and [string]$manifest.state -ne 'uninstalled')) {
        throw 'The install ownership manifest has an unsupported format or missing product data.'
    }

    $seenPaths = @{}
    foreach ($record in @($manifest.ownedFiles)) {
        $relativePath = ([string]$record.path).Replace('\', '/')
        $null = Get-PayloadFullPath -RootPath $RootPath -RelativePath $relativePath
        $pathKey = $relativePath.ToLowerInvariant()
        if ($seenPaths.ContainsKey($pathKey) -or
            [long]$record.length -lt 0 -or
            [string]$record.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw "The install ownership manifest contains an invalid file record: $relativePath"
        }
        $seenPaths[$pathKey] = $true
    }

    return $manifest
}

function Get-AppInstallerExistingInstallState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $installManifest = Get-AppInstallerInstallManifest -RootPath $RootPath
    if ($null -ne $installManifest) {
        return [PSCustomObject]@{
            Manifest = $installManifest
            Version = [string]$installManifest.version
            OwnedFiles = @($installManifest.ownedFiles)
            TrustLevel = 'install-manifest'
            HasProductMarkers = $true
        }
    }

    $ownedFiles = New-Object System.Collections.Generic.List[object]
    $version = ''
    $trustLevel = 'none'
    try {
        $status = Test-AppInstallerPayload -RootPath $RootPath -RequirePackage
        $version = [string]$status.Version
        foreach ($record in @($status.Integrity.files)) {
            $ownedFiles.Add([PSCustomObject]@{
                path = ([string]$record.path).Replace('\', '/')
                length = [long]$record.length
                sha256 = ([string]$record.sha256).ToLowerInvariant()
            })
        }
        $integrityPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath 'payload-integrity.json'
        $integrityItem = Get-Item -LiteralPath $integrityPath -ErrorAction Stop
        $ownedFiles.Add([PSCustomObject]@{
            path = 'payload-integrity.json'
            length = [long]$integrityItem.Length
            sha256 = (Get-FileHash -LiteralPath $integrityPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        })
        $trustLevel = 'payload-integrity'
    }
    catch {
        try {
            $legacyInventory = @(Get-AppInstallerPayloadFiles -RootPath $RootPath)
            $version = Get-AppInstallerPayloadVersion -RootPath $RootPath
            foreach ($file in $legacyInventory) {
                if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) { continue }
                $item = Get-Item -LiteralPath $file.Source -ErrorAction Stop
                $ownedFiles.Add([PSCustomObject]@{
                    path = ([string]$file.Path).Replace('\', '/')
                    length = [long]$item.Length
                    sha256 = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                })
            }
            $integrityPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath 'payload-integrity.json'
            if (Test-Path -LiteralPath $integrityPath -PathType Leaf) {
                $integrityItem = Get-Item -LiteralPath $integrityPath -ErrorAction Stop
                $ownedFiles.Add([PSCustomObject]@{
                    path = 'payload-integrity.json'
                    length = [long]$integrityItem.Length
                    sha256 = (Get-FileHash -LiteralPath $integrityPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                })
            }
            if ($ownedFiles.Count -gt 0) { $trustLevel = 'legacy-unverified' }
        }
        catch {
            $ownedFiles.Clear()
        }
    }

    $markerPresent = $ownedFiles.Count -gt 0 -and
        @($ownedFiles | Where-Object { ([string]$_.path).Equals('app-installer.ps1', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and
        @($ownedFiles | Where-Object { ([string]$_.path).Equals('modules/InstallerPayload.psm1', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    return [PSCustomObject]@{
        Manifest = $null
        Version = $version
        OwnedFiles = @($ownedFiles.ToArray())
        TrustLevel = $trustLevel
        HasProductMarkers = $markerPresent
    }
}

function Get-AppInstallerTreeInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        return [PSCustomObject]@{ Directories = @(); Files = @(); RootAcl = $null }
    }
    $rootItem = Get-Item -LiteralPath $rootFullPath -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The install root cannot be a reparse point.'
    }

    $separatorCharacters = [char[]]@([char]92, [char]47)
    $rootPrefix = $rootFullPath.TrimEnd($separatorCharacters) + [System.IO.Path]::DirectorySeparatorChar
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($rootFullPath)
    $directories = New-Object System.Collections.Generic.List[object]
    $files = New-Object System.Collections.Generic.List[object]
    while ($pending.Count -gt 0) {
        $currentDirectory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Install state cannot contain reparse points: $($item.FullName)"
            }
            $relativePath = $item.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            if ($item.PSIsContainer) {
                $directories.Add([PSCustomObject]@{ Path = $relativePath; FullPath = $item.FullName; Acl = $null })
                $pending.Push($item.FullName)
            }
            else {
                $files.Add([PSCustomObject]@{
                    Path = $relativePath
                    FullPath = $item.FullName
                    Length = [long]$item.Length
                    Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    Acl = $null
                })
            }
        }
    }

    $rootAcl = $null
    if ($env:OS -eq 'Windows_NT') {
        $rootAcl = Get-Acl -LiteralPath $rootFullPath -ErrorAction Stop
        foreach ($directory in $directories) {
            $directory.Acl = Get-Acl -LiteralPath $directory.FullPath -ErrorAction Stop
        }
        foreach ($file in $files) {
            $file.Acl = Get-Acl -LiteralPath $file.FullPath -ErrorAction Stop
        }
    }
    return [PSCustomObject]@{
        Directories = @($directories.ToArray())
        Files = @($files.ToArray())
        RootAcl = $rootAcl
    }
}

function Copy-AppInstallerFilePreservingMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter()]
        [switch]$PreserveAcl
    )

    $sourceItem = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Install state cannot contain reparse points: $SourcePath"
    }
    $sourceAcl = $null
    if ($PreserveAcl -and $env:OS -eq 'Windows_NT') {
        $sourceAcl = Get-Acl -LiteralPath $SourcePath -ErrorAction Stop
    }
    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
    }
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    if ($null -ne $sourceAcl) {
        $destinationAcl = Get-Acl -LiteralPath $DestinationPath -ErrorAction Stop
        if (-not $destinationAcl.Sddl.Equals($sourceAcl.Sddl, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The staged file would not inherit the existing ACL. The original was retained: $SourcePath"
        }
    }
    $destinationItem = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction Stop
    $destinationItem.Attributes = $sourceItem.Attributes
    $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not $destinationHash.Equals($sourceHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Preserved file copy did not match its source: $SourcePath"
    }
}

function Write-AppInstallerInstallManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string[]]$OwnedPaths
    )

    $pathMap = @{}
    foreach ($path in $OwnedPaths) { $pathMap[([string]$path).ToLowerInvariant()] = ([string]$path).Replace('\', '/') }
    $ownedRecords = New-Object System.Collections.Generic.List[object]
    foreach ($pathKey in @($pathMap.Keys | Sort-Object)) {
        $relativePath = $pathMap[$pathKey]
        $fullPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath $relativePath
        $item = Get-Item -LiteralPath $fullPath -ErrorAction Stop
        $ownedRecords.Add([PSCustomObject]@{
            path = $relativePath
            length = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        })
    }
    $manifest = [PSCustomObject]@{
        formatVersion = 1
        productId = 'mytech.today.app-installer'
        installScope = 'current-user'
        state = 'installed'
        version = $Version
        installedUtc = [DateTime]::UtcNow.ToString('o')
        ownedFiles = @($ownedRecords.ToArray())
    }
    $manifestPath = Get-PayloadFullPath -RootPath $RootPath -RelativePath '.app-installer-install.json'
    $temporaryPath = '{0}.{1}.tmp' -f $manifestPath, [guid]::NewGuid().ToString('N')
    try {
        $json = ConvertTo-Json -InputObject $manifest -Depth 8
        $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
    }
}

function Preserve-AppInstallerTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter(Mandatory = $true)]
        [object]$ExistingState,

        [Parameter(Mandatory = $true)]
        [hashtable]$IncomingFiles,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    $snapshot = Get-AppInstallerTreeInventory -RootPath $SourceRoot
    $ownedMap = @{}
    foreach ($record in @($ExistingState.OwnedFiles)) {
        $ownedMap[([string]$record.path).Replace('\', '/').ToLowerInvariant()] = $record
    }
    foreach ($directory in $snapshot.Directories) {
        $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $directory.Path
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            throw "An existing directory conflicts with a packaged file and was preserved: $($directory.Path)"
        }
        if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
            New-Item -ItemType Directory -Path $targetPath -Force -ErrorAction Stop | Out-Null
        }
    }

    $preservedFiles = New-Object System.Collections.Generic.List[object]
    $preservationId = [guid]::NewGuid().ToString('N')
    foreach ($file in $snapshot.Files) {
        $pathKey = $file.Path.ToLowerInvariant()
        $isInstallManifest = $pathKey -eq '.app-installer-install.json'
        if ($isInstallManifest -and $null -ne $ExistingState.Manifest) {
            continue
        }

        if ($ownedMap.ContainsKey($pathKey)) {
            $oldRecord = $ownedMap[$pathKey]
            $matchesOwnership = [long]$oldRecord.length -eq $file.Length -and
                ([string]$oldRecord.sha256).Equals($file.Sha256, [System.StringComparison]::OrdinalIgnoreCase)
            $matchesIncoming = $false
            if ($IncomingFiles.ContainsKey($pathKey)) {
                $matchesIncoming = $IncomingFiles[$pathKey].Sha256.Equals($file.Sha256, [System.StringComparison]::OrdinalIgnoreCase)
            }
            if ($ExistingState.TrustLevel -eq 'legacy-unverified' -and -not $IncomingFiles.ContainsKey($pathKey)) {
                $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $file.Path
                Copy-AppInstallerFilePreservingMetadata -SourcePath $file.FullPath -DestinationPath $targetPath -PreserveAcl
                $preservedFiles.Add([PSCustomObject]@{
                    originalPath = $file.Path
                    preservedPath = $file.Path
                    sha256 = $file.Sha256
                    reason = 'legacy-file-not-in-current-payload'
                })
                continue
            }
            if ($file.Path.StartsWith('profiles/', [System.StringComparison]::OrdinalIgnoreCase) -and
                $IncomingFiles.ContainsKey($pathKey) -and -not $matchesIncoming) {
                $profilePath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $file.Path
                Copy-AppInstallerFilePreservingMetadata -SourcePath $file.FullPath -DestinationPath $profilePath -PreserveAcl
                $preservedFiles.Add([PSCustomObject]@{
                    originalPath = $file.Path
                    preservedPath = $file.Path
                    sha256 = $file.Sha256
                    reason = 'user-profile-retained-at-original-path'
                })
                continue
            }
            if ($IncomingFiles.ContainsKey($pathKey) -and $env:OS -eq 'Windows_NT') {
                $incomingPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $file.Path
                $incomingAcl = Get-Acl -LiteralPath $incomingPath -ErrorAction Stop
                if (-not $file.Acl.Sddl.Equals($incomingAcl.Sddl, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "The packaged file would not inherit the existing ACL. The original install was retained: $($file.Path)"
                }
            }
            $isLegacyDifference = $ExistingState.TrustLevel -eq 'legacy-unverified' -and
                $IncomingFiles.ContainsKey($pathKey) -and -not $matchesIncoming
            if (-not $matchesOwnership -or $isLegacyDifference) {
                if ($Operation -eq 'Auto' -and $ExistingState.TrustLevel -ne 'legacy-unverified') {
                    throw "An owned file has local changes and was not replaced: $($file.Path). Run an explicit repair or upgrade to preserve a copy and continue."
                }
                $preservedRelativePath = '.app-installer-preserved/' + $preservationId + '/' + $file.Path
                $preservedPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $preservedRelativePath
                Copy-AppInstallerFilePreservingMetadata -SourcePath $file.FullPath -DestinationPath $preservedPath -PreserveAcl
                $preservedFiles.Add([PSCustomObject]@{
                    originalPath = $file.Path
                    preservedPath = $preservedRelativePath
                    sha256 = $file.Sha256
                    reason = 'local-change-to-owned-file'
                })
            }
            continue
        }

        if ($IncomingFiles.ContainsKey($pathKey)) {
            throw "An unowned file blocks a packaged path and was not overwritten: $($file.Path)"
        }
        $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $file.Path
        if (Test-Path -LiteralPath $targetPath) {
            throw "An unowned file conflicts with a packaged path and was preserved: $($file.Path)"
        }
        Copy-AppInstallerFilePreservingMetadata -SourcePath $file.FullPath -DestinationPath $targetPath -PreserveAcl
    }

    if (@($preservedFiles | Where-Object { ([string]$_.preservedPath).StartsWith('.app-installer-preserved/', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        $preservationDirectory = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath ('.app-installer-preserved/' + $preservationId)
        New-Item -ItemType Directory -Path $preservationDirectory -Force -ErrorAction Stop | Out-Null
        $preservationManifestPath = Join-Path $preservationDirectory 'preservation-manifest.json'
        $preservationManifest = [PSCustomObject]@{
            formatVersion = 1
            createdUtc = [DateTime]::UtcNow.ToString('o')
            files = @($preservedFiles.ToArray())
        }
        $json = ConvertTo-Json -InputObject $preservationManifest -Depth 8
        $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText($preservationManifestPath, $json + [Environment]::NewLine, $utf8NoBom)
    }

    if ($env:OS -eq 'Windows_NT') {
        foreach ($directory in $snapshot.Directories) {
            $targetPath = Get-PayloadFullPath -RootPath $DestinationRoot -RelativePath $directory.Path
            $targetAcl = Get-Acl -LiteralPath $targetPath -ErrorAction Stop
            if (-not $targetAcl.Sddl.Equals($directory.Acl.Sddl, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "The staged directory would not inherit the existing ACL. The original was retained: $($directory.Path)"
            }
        }
        if ($null -ne $snapshot.RootAcl) {
            $targetRootAcl = Get-Acl -LiteralPath $DestinationRoot -ErrorAction Stop
            if (-not $targetRootAcl.Sddl.Equals($snapshot.RootAcl.Sddl, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "The staged install root would not inherit the existing ACL. The original was retained: $SourceRoot"
            }
        }
    }

    return [PSCustomObject]@{
        Snapshot = $snapshot
        PreservedFiles = @($preservedFiles.ToArray())
    }
}

function Invoke-AppInstallerLifecycleTestHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Point,

        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    if ($null -ne $script:AppInstallerLifecycleTestHook) {
        & $script:AppInstallerLifecycleTestHook $Point $Context
    }
}

function Test-AppInstallerTreeSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [object]$Snapshot
    )

    $current = Get-AppInstallerTreeInventory -RootPath $RootPath
    $expectedMap = @{}
    $currentMap = @{}
    foreach ($file in $Snapshot.Files) { $expectedMap[$file.Path.ToLowerInvariant()] = $file }
    foreach ($file in $current.Files) { $currentMap[$file.Path.ToLowerInvariant()] = $file }
    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($pathKey in @($expectedMap.Keys)) {
        if (-not $currentMap.ContainsKey($pathKey)) {
            $changed.Add($expectedMap[$pathKey].Path)
            continue
        }
        $before = $expectedMap[$pathKey]
        $after = $currentMap[$pathKey]
        if ([long]$before.Length -ne [long]$after.Length -or
            -not $before.Sha256.Equals($after.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            $changed.Add($after.Path)
        }
    }
    foreach ($pathKey in @($currentMap.Keys)) {
        if (-not $expectedMap.ContainsKey($pathKey)) { $changed.Add($currentMap[$pathKey].Path) }
    }
    return [PSCustomObject]@{ IsUnchanged = ($changed.Count -eq 0); ChangedPaths = @($changed.ToArray()) }
}

function Copy-AppInstallerPayload {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter()]
        [ValidateSet('Auto', 'Install', 'Upgrade', 'Repair')]
        [string]$Operation = 'Auto'
    )

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourceRoot)
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
    $separatorCharacters = [char[]]@([char]92, [char]47)
    if ($sourceFullPath.TrimEnd($separatorCharacters).Equals($destinationFullPath.TrimEnd($separatorCharacters), [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            $status = Test-AppInstallerPayload -RootPath $destinationFullPath
        }
        catch {
            if ($Operation -in @('Upgrade', 'Repair')) {
                throw "The source and install roots are the same, and the installed payload did not validate. Provide a separate verified package source to $Operation it. $($_.Exception.Message)"
            }
            throw
        }
        return [PSCustomObject]@{ Path = $destinationFullPath; Status = 'AlreadyCurrent'; FileCount = $status.FileCount; Version = $status.Version; PreservedFiles = @(); CleanupStatus = 'NotRequired'; BackupPath = $null }
    }

    $sourceManifest = Get-AppInstallerPayloadManifest -RootPath $sourceFullPath
    $sourceStatus = Test-AppInstallerPayload -RootPath $sourceFullPath
    $inventory = @(Get-AppInstallerPayloadFiles -RootPath $sourceFullPath)
    $sourceHashes = @{}
    foreach ($file in $inventory) {
        if ($sourceStatus.Mode -eq 'packaged' -and $null -ne $sourceStatus.Integrity) {
            $sourceRecord = @($sourceStatus.Integrity.files | Where-Object { ([string]$_.path).Replace('\', '/').Equals($file.Path, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
            if ($null -eq $sourceRecord) { throw "The source integrity manifest omitted a payload file: $($file.Path)" }
            $sourceHashes[$file.Path.ToLowerInvariant()] = [PSCustomObject]@{ Length = [long]$sourceRecord.length; Sha256 = ([string]$sourceRecord.sha256).ToLowerInvariant() }
        }
        else {
            $sourceItem = Get-Item -LiteralPath $file.Source -ErrorAction Stop
            $sourceHashes[$file.Path.ToLowerInvariant()] = [PSCustomObject]@{
                Length = [long]$sourceItem.Length
                Sha256 = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            }
        }
    }

    $destinationParent = Split-Path -Parent $destinationFullPath
    $destinationLeaf = Split-Path -Leaf $destinationFullPath
    if ([string]::IsNullOrWhiteSpace($destinationParent) -or [string]::IsNullOrWhiteSpace($destinationLeaf)) {
        throw 'The payload destination must be a named directory below an existing parent path.'
    }
    if (Test-Path -LiteralPath $destinationFullPath -PathType Leaf) {
        throw "The payload destination is a file, not a directory: $destinationFullPath"
    }

    $destinationExists = Test-Path -LiteralPath $destinationFullPath -PathType Container
    $existingState = if ($destinationExists) { Get-AppInstallerExistingInstallState -RootPath $destinationFullPath } else {
        [PSCustomObject]@{ Manifest = $null; Version = ''; OwnedFiles = @(); TrustLevel = 'none'; HasProductMarkers = $false }
    }
    $existingStatus = $null
    if ($destinationExists) {
        try { $existingStatus = Test-AppInstallerPayload -RootPath $destinationFullPath -RequirePackage } catch { $existingStatus = $null }
    }
    if ($Operation -eq 'Install' -and $existingStatus -and $existingStatus.IsValid -and $existingStatus.Version -ne $sourceStatus.Version) {
        throw 'Install found a different existing product version. Use Upgrade to replace it.'
    }
    if ($Operation -eq 'Upgrade' -and -not $existingState.HasProductMarkers) {
        throw 'Upgrade requires a detected App Installer installation. Use Install for a fresh destination.'
    }
    if ($Operation -eq 'Repair' -and $destinationExists -and -not $existingState.HasProductMarkers) {
        throw 'Repair requires a detected App Installer installation and a separate verified package source.'
    }
    if ($existingStatus -and $existingStatus.IsValid -and $existingStatus.Version -eq $sourceStatus.Version -and
        $null -ne $existingState.Manifest -and $Operation -ne 'Upgrade') {
        return [PSCustomObject]@{ Path = $destinationFullPath; Status = 'AlreadyCurrent'; FileCount = $existingStatus.FileCount; Version = $existingStatus.Version; PreservedFiles = @(); CleanupStatus = 'NotRequired'; BackupPath = $null }
    }
    if (-not $PSCmdlet.ShouldProcess($destinationFullPath, ("{0} App Installer payload version {1}" -f $Operation, $sourceStatus.Version))) {
        return [PSCustomObject]@{ Path = $destinationFullPath; Status = 'WhatIf'; FileCount = $inventory.Count; Version = $sourceStatus.Version; PreservedFiles = @(); CleanupStatus = 'NotRequired'; BackupPath = $null }
    }
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationParent -Force -ErrorAction Stop | Out-Null
    }

    $stagePath = Join-Path $destinationParent ('.' + $destinationLeaf + '.staging-' + [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $destinationParent ('.' + $destinationLeaf + '.backup-' + [guid]::NewGuid().ToString('N'))
    $failedPath = Join-Path $destinationParent ('.' + $destinationLeaf + '.failed-' + [guid]::NewGuid().ToString('N'))
    $destinationMovedToBackup = $false
    $stageCommitted = $false
    $snapshot = $null
    $preservedFiles = @()
    $operationStatus = if (-not $destinationExists) { 'Installed' } elseif ($Operation -eq 'Repair') { 'Repaired' } elseif ($null -ne $existingState.Manifest -and [string]$existingState.Manifest.state -eq 'uninstalled') { 'Installed' } elseif ($existingStatus -and $existingStatus.Version -eq $sourceStatus.Version) { 'Repaired' } elseif ($existingState.HasProductMarkers) { 'Upgraded' } else { 'Installed' }
    try {
        if ($destinationExists) { $snapshot = Get-AppInstallerTreeInventory -RootPath $destinationFullPath }
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
            $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ([long]$targetItem.Length -ne $sourceHash.Length -or
                -not $targetHash.Equals($sourceHash.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Staged payload file does not match its validated source: $($file.Path)"
            }
        }

        Write-AppInstallerPayloadIntegrity -RootPath $stagePath | Out-Null
        $productPaths = @($inventory | ForEach-Object { [string]$_.Path }) + @('payload-integrity.json')
        $incomingFiles = @{}
        foreach ($path in $productPaths) {
            $fullPath = Get-PayloadFullPath -RootPath $stagePath -RelativePath $path
            $item = Get-Item -LiteralPath $fullPath -ErrorAction Stop
            $incomingFiles[$path.ToLowerInvariant()] = [PSCustomObject]@{
                Path = $path
                Length = [long]$item.Length
                Sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            }
        }
        if ($destinationExists) {
            $preservation = Preserve-AppInstallerTree -SourceRoot $destinationFullPath -DestinationRoot $stagePath -ExistingState $existingState -IncomingFiles $incomingFiles -Operation $Operation
            $snapshot = $preservation.Snapshot
            $preservedFiles = @($preservation.PreservedFiles)
            Write-AppInstallerPayloadIntegrity -RootPath $stagePath | Out-Null
            foreach ($path in $productPaths) {
                $fullPath = Get-PayloadFullPath -RootPath $stagePath -RelativePath $path
                $item = Get-Item -LiteralPath $fullPath -ErrorAction Stop
                $incomingFiles[$path.ToLowerInvariant()] = [PSCustomObject]@{
                    Path = $path
                    Length = [long]$item.Length
                    Sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                }
            }
        }
        $stagedStatus = Test-AppInstallerPayload -RootPath $stagePath -RequirePackage
        if (-not $stagedStatus.IsValid -or $stagedStatus.Version -ne $sourceStatus.Version) {
            throw 'The staged application payload did not pass integrity validation.'
        }
        Write-AppInstallerInstallManifest -RootPath $stagePath -Version $sourceStatus.Version -OwnedPaths $productPaths
        $installManifest = Get-AppInstallerInstallManifest -RootPath $stagePath
        if ([string]$installManifest.version -ne $sourceStatus.Version -or @($installManifest.ownedFiles).Count -ne $productPaths.Count) {
            throw 'The staged install ownership manifest did not match the validated payload.'
        }
        if ($destinationExists -and $env:OS -eq 'Windows_NT') {
            $oldInstallManifest = @($snapshot.Files | Where-Object { $_.Path -eq '.app-installer-install.json' }) | Select-Object -First 1
            if ($null -ne $oldInstallManifest) {
                $oldManifestAcl = Get-Acl -LiteralPath $oldInstallManifest.FullPath -ErrorAction Stop
                $stagedManifestAcl = Get-Acl -LiteralPath (Get-PayloadFullPath -RootPath $stagePath -RelativePath '.app-installer-install.json') -ErrorAction Stop
                if (-not $oldManifestAcl.Sddl.Equals($stagedManifestAcl.Sddl, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'The staged ownership manifest would not inherit the existing ACL. The original install was retained.'
                }
            }
        }
        Invoke-AppInstallerLifecycleTestHook -Point 'AfterStageValidated' -Context ([PSCustomObject]@{ SourceRoot = $sourceFullPath; DestinationRoot = $destinationFullPath; StagePath = $stagePath; BackupPath = $backupPath; Version = $sourceStatus.Version })

        if ($destinationExists) {
            [System.IO.Directory]::Move($destinationFullPath, $backupPath)
            $destinationMovedToBackup = $true
            Invoke-AppInstallerLifecycleTestHook -Point 'AfterPreviousMoved' -Context ([PSCustomObject]@{ SourceRoot = $sourceFullPath; DestinationRoot = $destinationFullPath; StagePath = $stagePath; BackupPath = $backupPath; Version = $sourceStatus.Version })
            $movedSnapshot = Test-AppInstallerTreeSnapshot -RootPath $backupPath -Snapshot $snapshot
            if (-not $movedSnapshot.IsUnchanged) {
                throw ('The existing installation changed while staging. Retry after closing App Installer. Changed paths: {0}' -f ($movedSnapshot.ChangedPaths -join ', '))
            }
        }
        [System.IO.Directory]::Move($stagePath, $destinationFullPath)
        $stageCommitted = $true
        $installedStatus = Test-AppInstallerPayload -RootPath $destinationFullPath -RequirePackage
        $installedManifest = Get-AppInstallerInstallManifest -RootPath $destinationFullPath
        if (-not $installedStatus.IsValid -or $installedStatus.Version -ne $sourceStatus.Version -or [string]$installedManifest.version -ne $sourceStatus.Version) {
            throw 'The activated application payload did not pass integrity and ownership validation.'
        }
        Invoke-AppInstallerLifecycleTestHook -Point 'AfterActivation' -Context ([PSCustomObject]@{ SourceRoot = $sourceFullPath; DestinationRoot = $destinationFullPath; StagePath = $stagePath; BackupPath = $backupPath; Version = $sourceStatus.Version })
        if ($destinationMovedToBackup) {
            $finalSnapshot = Test-AppInstallerTreeSnapshot -RootPath $backupPath -Snapshot $snapshot
            if (-not $finalSnapshot.IsUnchanged) {
                throw ('The previous installation changed during activation. It will be restored without overwriting those files. Changed paths: {0}' -f ($finalSnapshot.ChangedPaths -join ', '))
            }
        }

        $cleanupStatus = 'NotRequired'
        $reportedBackupPath = $null
        $cleanupError = $null
        if ($destinationMovedToBackup -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
            try {
                Invoke-AppInstallerLifecycleTestHook -Point 'BeforeBackupCleanup' -Context ([PSCustomObject]@{ SourceRoot = $sourceFullPath; DestinationRoot = $destinationFullPath; StagePath = $stagePath; BackupPath = $backupPath; Version = $sourceStatus.Version })
                Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
                $cleanupStatus = 'Complete'
            }
            catch {
                $cleanupError = $_.Exception.Message
                if (Test-Path -LiteralPath $backupPath -PathType Container) {
                    $cleanupStatus = 'Retained'
                    $reportedBackupPath = $backupPath
                }
                else {
                    $cleanupStatus = 'Complete'
                }
            }
        }
        return [PSCustomObject]@{
            Path = $destinationFullPath
            Status = $operationStatus
            FileCount = $installedStatus.FileCount
            Version = $installedStatus.Version
            PreservedFiles = $preservedFiles
            CleanupStatus = $cleanupStatus
            BackupPath = $reportedBackupPath
            CleanupError = $cleanupError
        }
    }
    catch {
        $originalFailure = $_.Exception.Message
        $recoveryNotes = New-Object System.Collections.Generic.List[string]
        if ($stageCommitted -and (Test-Path -LiteralPath $destinationFullPath -PathType Container)) {
            try {
                [System.IO.Directory]::Move($destinationFullPath, $failedPath)
                $recoveryNotes.Add("The failed new payload, including files written after activation, remains at '$failedPath'.")
            }
            catch {
                $recoveryNotes.Add("The new payload remains at '$destinationFullPath' because it could not be moved aside: $($_.Exception.Message)")
            }
        }
        if ($destinationMovedToBackup -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
            try {
                if (-not (Test-Path -LiteralPath $destinationFullPath)) {
                    [System.IO.Directory]::Move($backupPath, $destinationFullPath)
                    $recoveryNotes.Add("The previous installation was restored at '$destinationFullPath'.")
                }
                else {
                    $recoveryNotes.Add("The previous installation remains at '$backupPath' because the install path is occupied.")
                }
            }
            catch {
                $recoveryNotes.Add("The previous installation remains at '$backupPath'; automatic rollback failed: $($_.Exception.Message)")
            }
        }
        elseif (-not $destinationExists) {
            $recoveryNotes.Add("No previous installation existed. The install path '$destinationFullPath' is unchanged.")
        }
        if (Test-Path -LiteralPath $stagePath -PathType Container) {
            try {
                Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction Stop
            }
            catch {
                $recoveryNotes.Add("The incomplete staging directory remains at '$stagePath': $($_.Exception.Message)")
            }
        }
        $recoveryText = if ($recoveryNotes.Count -gt 0) { ' ' + ($recoveryNotes -join ' ') } else { ' The existing install path was not changed.' }
        throw "App Installer payload operation failed: $originalFailure.$recoveryText"
    }
}

function Uninstall-AppInstallerPayload {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot,

        [Parameter(Mandatory = $true)]
        [switch]$KeepData,

        [Parameter()]
        [switch]$RemoveOwnedFiles
    )

    if (-not $KeepData) {
        throw 'The supported uninstall policy always keeps user data. Pass -KeepData to confirm that policy.'
    }
    $rootFullPath = [System.IO.Path]::GetFullPath($InstallRoot)
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        return [PSCustomObject]@{ Path = $rootFullPath; Status = 'AlreadyUninstalled'; RemovedFiles = @(); RetainedFiles = @(); UserDataRetained = $true }
    }
    $state = Get-AppInstallerExistingInstallState -RootPath $rootFullPath
    if (-not $state.HasProductMarkers) {
        throw 'No validated App Installer ownership manifest or script installation was found. No files were removed.'
    }
    if ($state.TrustLevel -eq 'legacy-unverified') {
        throw 'This legacy installation has no valid ownership or payload-integrity baseline. Upgrade or repair it from a verified payload before removing product files. No files were removed.'
    }
    if (-not $RemoveOwnedFiles) {
        return [PSCustomObject]@{
            Path = $rootFullPath
            Status = 'PreviewOnly'
            OwnedFileCount = @($state.OwnedFiles).Count
            UserDataRetained = $true
            NextStep = 'Repeat with -KeepData -RemoveOwnedFiles to remove unchanged product files.'
        }
    }
    if (-not $PSCmdlet.ShouldProcess($rootFullPath, 'Remove unchanged App Installer owned files and retain user data')) {
        return [PSCustomObject]@{ Path = $rootFullPath; Status = 'WhatIf'; RemovedFiles = @(); RetainedFiles = @(); UserDataRetained = $true }
    }

    $removedFiles = New-Object System.Collections.Generic.List[string]
    $retainedFiles = New-Object System.Collections.Generic.List[string]
    $remainingOwned = New-Object System.Collections.Generic.List[object]
    foreach ($record in @($state.OwnedFiles)) {
        $relativePath = ([string]$record.path).Replace('\', '/')
        $protectedData = $relativePath.Equals('queue-state.json', [System.StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.Equals('queue-state.json.bak', [System.StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.StartsWith('profiles/', [System.StringComparison]::OrdinalIgnoreCase)
        $filePath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath $relativePath
        if ($protectedData -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            if ($protectedData -and (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                $remainingOwned.Add($record)
                $retainedFiles.Add($relativePath)
            }
            continue
        }
        $item = Get-Item -LiteralPath $filePath -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $remainingOwned.Add($record)
            $retainedFiles.Add($relativePath)
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction Stop).Hash
        if ([long]$item.Length -ne [long]$record.length -or
            -not $actualHash.Equals([string]$record.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            $remainingOwned.Add($record)
            $retainedFiles.Add($relativePath)
            continue
        }
        try {
            Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop
            $removedFiles.Add($relativePath)
        }
        catch {
            $remainingOwned.Add($record)
            $retainedFiles.Add($relativePath)
        }
    }

    $updatedManifest = [PSCustomObject]@{
        formatVersion = 1
        productId = 'mytech.today.app-installer'
        installScope = 'current-user'
        state = 'uninstalled'
        version = [string]$state.Version
        installedUtc = if ($null -ne $state.Manifest) { [string]$state.Manifest.installedUtc } else { [DateTime]::UtcNow.ToString('o') }
        uninstalledUtc = [DateTime]::UtcNow.ToString('o')
        ownedFiles = @($remainingOwned.ToArray())
    }
    $manifestPath = Get-PayloadFullPath -RootPath $rootFullPath -RelativePath '.app-installer-install.json'
    $temporaryPath = '{0}.{1}.tmp' -f $manifestPath, [guid]::NewGuid().ToString('N')
    $temporaryCleanupError = $null
    try {
        $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText($temporaryPath, (ConvertTo-Json -InputObject $updatedManifest -Depth 8) + [Environment]::NewLine, $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force -ErrorAction Stop
    }
    catch {
        throw "Uninstall removed $($removedFiles.Count) owned files, but could not update the ownership manifest at '$manifestPath'. Remaining files and user data are still at '$rootFullPath'. Retry after resolving the manifest write error. $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop } catch { $temporaryCleanupError = $_.Exception.Message }
        }
    }
    if ($temporaryCleanupError) {
        throw "Uninstall updated the ownership manifest but could not remove its temporary file at '$temporaryPath': $temporaryCleanupError"
    }
    return [PSCustomObject]@{
        Path = $rootFullPath
        Status = 'Uninstalled'
        RemovedFiles = @($removedFiles.ToArray())
        RetainedFiles = @($retainedFiles.ToArray())
        UserDataRetained = $true
    }
}

Export-ModuleMember -Function @(
    'Copy-AppInstallerPayload',
    'Get-AppInstallerInstallManifest',
    'Get-AppInstallerPayloadFiles',
    'Get-AppInstallerPayloadManifest',
    'Get-AppInstallerPayloadVersion',
    'Test-AppInstallerPayload',
    'Uninstall-AppInstallerPayload',
    'Write-AppInstallerPayloadIntegrity'
)
