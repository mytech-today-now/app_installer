#Requires -Version 5.1

$compatibilityModulePath = Join-Path $PSScriptRoot 'InstallerCompatibility.psm1'
if (-not (Get-Command -Name 'Test-InstallerWindows10WinGetBootstrapHost' -ErrorAction SilentlyContinue)) {
    Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
}

function Get-WingetBootstrapHostArchitecture {
    [CmdletBinding()]
    param(
        [string]$Override
    )

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override.Trim().ToLowerInvariant()
    }

    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    switch (($architecture -as [string]).ToUpperInvariant()) {
        { $_ -in @('AMD64', 'X64') } { return 'x64' }
        'ARM64' { return 'arm64' }
        { $_ -in @('X86', 'I386', 'I686') } { return 'x86' }
        default { return 'unknown' }
    }
}

function Test-WingetBootstrapWindows10Client {
    [CmdletBinding()]
    param()

    try {
        $hostInfo = Get-InstallerHostInfo
        $capability = Test-InstallerWindows10WinGetBootstrapHost -HostInfo $hostInfo
        $appPreflight = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $hostInfo
        return [bool]($capability.IsSupported -and $appPreflight.IsSupported)
    }
    catch {
        return $false
    }
}

function Get-WingetPackageMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Appx', 'Bundle')]
        [string]$PackageKind
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

    $archive = [System.IO.Compression.ZipFile]::OpenRead($LiteralPath)
    try {
        if ($PackageKind -eq 'Bundle') {
            $manifestName = 'AppxMetadata/AppxBundleManifest.xml'
        }
        else {
            $manifestName = 'AppxManifest.xml'
        }

        $entry = $archive.Entries |
            Where-Object { [string]::Equals($_.FullName, $manifestName, [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($null -eq $entry -or $entry.Length -le 0 -or $entry.Length -gt 1048576) {
            throw 'Package manifest is missing or exceeds the allowed size.'
        }

        $stream = $entry.Open()
        try {
            $readerSettings = New-Object System.Xml.XmlReaderSettings
            $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $readerSettings.XmlResolver = $null
            $reader = [System.Xml.XmlReader]::Create($stream, $readerSettings)
            try {
                $document = New-Object System.Xml.XmlDocument
                $document.XmlResolver = $null
                $document.Load($reader)
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        $identity = $document.SelectSingleNode("//*[local-name()='Identity']")
        if ($null -eq $identity) {
            throw 'Package identity is missing.'
        }

        $name = $identity.GetAttribute('Name')
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw 'Package identity name is missing.'
        }
        $publisher = $identity.GetAttribute('Publisher')
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            throw 'Package identity publisher is missing.'
        }

        if ($PackageKind -eq 'Appx') {
            $packageArchitecture = $identity.GetAttribute('ProcessorArchitecture')
            return [PSCustomObject]@{
                Name = $name
                Publisher = $publisher
                Architecture = $packageArchitecture
                CompatibleArchitectures = @($packageArchitecture)
            }
        }

        $applicationPackages = @(
            $document.SelectNodes("//*[local-name()='Package']") |
                Where-Object { [string]::Equals($_.GetAttribute('Type'), 'application', [System.StringComparison]::OrdinalIgnoreCase) }
        )
        if ($applicationPackages.Count -eq 0) {
            throw 'Bundle contains no application package entries.'
        }

        $architectures = @(
            $applicationPackages |
                ForEach-Object { $_.GetAttribute('Architecture') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.ToLowerInvariant() }
        )
        return [PSCustomObject]@{
            Name = $name
            Publisher = $publisher
            Architecture = 'bundle'
            CompatibleArchitectures = $architectures
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Find-WingetSignTool {
    [CmdletBinding()]
    param()

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        return $null
    }

    $kitsRoot = Join-Path $programFilesX86 'Windows Kits\10\bin'
    if (-not [System.IO.Directory]::Exists($kitsRoot)) {
        return $null
    }

    $versionDirectories = @(Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue)
    $toolCandidates = @()
    foreach ($versionDirectory in $versionDirectories) {
        $toolPath = Join-Path $versionDirectory.FullName 'x64\signtool.exe'
        if ([System.IO.File]::Exists($toolPath)) {
            $version = [version]'0.0'
            try {
                $version = [version]$versionDirectory.Name
            }
            catch {
                $version = [version]'0.0'
            }

            $toolCandidates += [PSCustomObject]@{
                Version = $version
                Path = $toolPath
            }
        }
    }

    $selectedTool = $toolCandidates |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($null -eq $selectedTool) {
        return $null
    }

    return $selectedTool.Path
}

function Test-WingetPackageSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $signToolPath = Find-WingetSignTool
    if ([string]::IsNullOrWhiteSpace($signToolPath)) {
        return $false
    }

    $previousExitCode = $LASTEXITCODE
    try {
        $null = & $signToolPath verify /pa /all /v $LiteralPath 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $global:LASTEXITCODE = $previousExitCode
    }
}

function Get-WingetReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Release,

        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )

    if ($null -eq $Release -or $Release -is [string]) {
        throw 'Release response is not an object.'
    }

    $tagProperty = $Release.PSObject.Properties['tag_name']
    $draftProperty = $Release.PSObject.Properties['draft']
    $prereleaseProperty = $Release.PSObject.Properties['prerelease']
    $assetsProperty = $Release.PSObject.Properties['assets']
    $htmlUrlProperty = $Release.PSObject.Properties['html_url']
    $apiUrlProperty = $Release.PSObject.Properties['url']

    if ($null -eq $tagProperty -or [string]::IsNullOrWhiteSpace([string]$tagProperty.Value) -or
        $null -eq $draftProperty -or $draftProperty.Value -isnot [bool] -or $draftProperty.Value -or
        $null -eq $prereleaseProperty -or $prereleaseProperty.Value -isnot [bool] -or $prereleaseProperty.Value -or
        $null -eq $assetsProperty -or $null -eq $htmlUrlProperty -or $null -eq $apiUrlProperty) {
        throw 'Release response does not contain validated release metadata.'
    }

    $tagName = [string]$tagProperty.Value
    $htmlUri = $null
    $apiUri = $null
    if (-not [System.Uri]::TryCreate([string]$htmlUrlProperty.Value, [System.UriKind]::Absolute, [ref]$htmlUri) -or
        -not [System.Uri]::TryCreate([string]$apiUrlProperty.Value, [System.UriKind]::Absolute, [ref]$apiUri)) {
        throw 'Release URLs are malformed.'
    }

    $expectedReleasePath = '/microsoft/winget-cli/releases/tag/' + [System.Uri]::EscapeDataString($tagName)
    if ($htmlUri.Scheme -ne 'https' -or $htmlUri.Host -ne 'github.com' -or
        $htmlUri.AbsolutePath -ne $expectedReleasePath -or $htmlUri.Query -or $htmlUri.Fragment -or
        $apiUri.Scheme -ne 'https' -or $apiUri.Host -ne 'api.github.com' -or
        -not $apiUri.AbsolutePath.StartsWith('/repos/microsoft/winget-cli/releases/', [System.StringComparison]::Ordinal) -or
        $apiUri.Query -or $apiUri.Fragment) {
        throw 'Release URLs do not identify the expected GitHub repository.'
    }

    $assets = @($assetsProperty.Value)
    if ($assets.Count -eq 0) {
        throw 'Release response contains no assets.'
    }

    $compatibleAssets = @()
    foreach ($asset in $assets) {
        if ($null -eq $asset) {
            throw 'Release response contains a null asset.'
        }

        $nameProperty = $asset.PSObject.Properties['name']
        if ($null -eq $nameProperty -or [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) {
            throw 'Release response contains an unnamed asset.'
        }

        $assetName = [string]$nameProperty.Value
        if ($assetName -notmatch '(?i)^Microsoft\.DesktopAppInstaller.*\.msixbundle$') {
            continue
        }

        $assetArchitecture = $null
        $architectureMatch = [regex]::Match($assetName, '(?i)(?:^|[._-])(x86|x64|amd64|arm64)(?:[._-]|$)')
        if ($architectureMatch.Success) {
            $assetArchitecture = $architectureMatch.Groups[1].Value.ToLowerInvariant()
            if ($assetArchitecture -eq 'amd64') {
                $assetArchitecture = 'x64'
            }
            if ($assetArchitecture -ne $Architecture) {
                continue
            }
        }

        $stateProperty = $asset.PSObject.Properties['state']
        $urlProperty = $asset.PSObject.Properties['browser_download_url']
        $digestProperty = $asset.PSObject.Properties['digest']
        $sizeProperty = $asset.PSObject.Properties['size']
        if ($null -eq $stateProperty -or [string]$stateProperty.Value -ne 'uploaded' -or
            $null -eq $urlProperty -or $null -eq $digestProperty -or $null -eq $sizeProperty) {
            throw 'Matching release asset is missing verification metadata.'
        }

        $digest = [string]$digestProperty.Value
        if ($digest -notmatch '(?i)^sha256:([0-9a-f]{64})$') {
            throw 'Matching release asset has no valid SHA-256 digest.'
        }

        $assetSize = 0L
        if (-not [long]::TryParse([string]$sizeProperty.Value, [ref]$assetSize) -or $assetSize -le 0) {
            throw 'Matching release asset has an invalid size.'
        }

        $assetUri = $null
        if (-not [System.Uri]::TryCreate([string]$urlProperty.Value, [System.UriKind]::Absolute, [ref]$assetUri)) {
            throw 'Matching release asset download URL is malformed.'
        }

        $pathSegments = $assetUri.AbsolutePath.Trim('/').Split('/')
        if ($assetUri.Scheme -ne 'https' -or $assetUri.Host -ne 'github.com' -or
            $assetUri.Query -or $assetUri.Fragment -or $pathSegments.Count -ne 6 -or
            $pathSegments[0] -ne 'microsoft' -or $pathSegments[1] -ne 'winget-cli' -or
            $pathSegments[2] -ne 'releases' -or $pathSegments[3] -ne 'download' -or
            [System.Uri]::UnescapeDataString($pathSegments[4]) -ne $tagName -or
            [System.Uri]::UnescapeDataString($pathSegments[5]) -ne $assetName) {
            throw 'Matching release asset URL is outside the validated release.'
        }

        $compatibleAssets += [PSCustomObject]@{
            Name = $assetName
            Url = $assetUri.AbsoluteUri
            Digest = $digest.Substring(7).ToLowerInvariant()
            Size = $assetSize
            Architecture = $assetArchitecture
        }
    }

    if ($compatibleAssets.Count -ne 1) {
        if ($compatibleAssets.Count -eq 0) {
            throw 'Release has no single bundle marked for the host architecture.'
        }
        throw 'Release has multiple matching bundles.'
    }

    return $compatibleAssets[0]
}

function Test-WingetPackageArchitecture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $PackageMetadata,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPublisher,

        [Parameter(Mandatory = $true)]
        [string]$Architecture,

        [switch]$Bundle
    )

    if ($PackageMetadata.Name -notin $ExpectedName) {
        return $false
    }
    if (-not [string]::Equals([string]$PackageMetadata.Publisher, $ExpectedPublisher, [System.StringComparison]::Ordinal)) {
        return $false
    }

    if ($Bundle) {
        $compatible = @($PackageMetadata.CompatibleArchitectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $matchingArchitectures = @($compatible | Where-Object { $_ -eq $Architecture -or $_ -eq 'neutral' })
        return ($matchingArchitectures.Count -eq 1)
    }

    return (([string]$PackageMetadata.Architecture).ToLowerInvariant() -eq $Architecture)
}

function Get-WingetNormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $pathRoot.Length) {
        return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $fullPath
}

function Test-WingetContainedTempDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    $normalizedRoot = Get-WingetNormalizedPath -Path $Root
    $normalizedCandidate = Get-WingetNormalizedPath -Path $Candidate
    if ([string]::Equals($normalizedRoot, $normalizedCandidate, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $expectedParent = [System.IO.Path]::GetDirectoryName($normalizedCandidate)
    $expectedName = [System.IO.Path]::GetFileName($normalizedCandidate)
    return ([string]::Equals($expectedParent, $normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        $expectedName -match '(?i)^app-installer-winget-[0-9a-f]{32}$')
}

function Invoke-WingetBootstrap {
    [CmdletBinding()]
    param(
        [string]$Architecture,

        [scriptblock]$GetReleaseMetadata = {
            Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing -ErrorAction Stop
        },

        [scriptblock]$DownloadFile = {
            param($Uri, $Path)
            Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -ErrorAction Stop
        },

        [scriptblock]$VerifyPackageSignature = {
            param($Path)
            Test-WingetPackageSignature -LiteralPath $Path
        },

        [scriptblock]$InstallPackage = {
            param($Path)
            Add-AppxPackage -Path $Path -ErrorAction Stop
        },

        [scriptblock]$DetectWinget = {
            Start-Sleep -Seconds 2
            try {
                $command = Get-Command -Name 'winget' -ErrorAction Stop
                return ($null -ne $command)
            }
            catch [System.Management.Automation.CommandNotFoundException] {
                $false
            }
        },

        [scriptblock]$VerifyHost = {
            Test-WingetBootstrapWindows10Client
        },

        [string]$TempRoot
    )

    $result = [PSCustomObject]@{
        Success = $false
        Status = 'Failed'
        ErrorCode = 'NotStarted'
        ChangesStarted = $false
        CleanupSucceeded = $true
        WingetDetected = $false
    }
    $tempDirectory = $null
    $tempDirectoryCreated = $false
    $rootDirectory = $null
    $failureCode = 'ArchitectureUnverified'
    $failurePhase = 'Preflight'
    $priorErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    try {
        $failureCode = 'OperatingSystemUnverified'
        $hostVerified = & $VerifyHost
        if ($hostVerified -isnot [bool] -or -not $hostVerified) {
            throw 'Windows 10 client host could not be verified.'
        }

        $failureCode = 'ArchitectureUnverified'
        $Architecture = Get-WingetBootstrapHostArchitecture -Override $Architecture
        if ($Architecture -ne 'x64') {
            throw 'This bootstrap only has verified x64 dependencies.'
        }

        if ([string]::IsNullOrWhiteSpace($TempRoot)) {
            $TempRoot = [System.IO.Path]::GetTempPath()
        }
        $rootDirectory = Get-WingetNormalizedPath -Path $TempRoot
        if (-not [System.IO.Directory]::Exists($rootDirectory)) {
            throw 'Temporary root is unavailable.'
        }
        $rootItem = Get-Item -LiteralPath $rootDirectory -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Temporary root is a reparse point.'
        }

        $tempDirectory = Join-Path $rootDirectory ('app-installer-winget-' + [guid]::NewGuid().ToString('N'))
        if ([System.IO.Directory]::Exists($tempDirectory) -or [System.IO.File]::Exists($tempDirectory)) {
            throw 'Unique temporary directory could not be allocated.'
        }
        [void][System.IO.Directory]::CreateDirectory($tempDirectory)
        $tempDirectoryCreated = $true
        if (-not (Test-WingetContainedTempDirectory -Root $rootDirectory -Candidate $tempDirectory)) {
            throw 'Temporary directory is outside its expected root.'
        }

        $failureCode = 'ReleaseMetadataInvalid'
        $release = & $GetReleaseMetadata
        $asset = Get-WingetReleaseAsset -Release $release -Architecture $Architecture

        $packageSpecs = @(
            [PSCustomObject]@{
                Name = 'VCLibs'
                Uri = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
                FileName = 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
                PackageKind = 'Appx'
                Identity = 'Microsoft.VCLibs.140.00.UWPDesktop'
                Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                IsReleaseAsset = $false
            },
            [PSCustomObject]@{
                Name = 'UI.Xaml'
                Uri = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'
                FileName = 'Microsoft.UI.Xaml.2.8.x64.appx'
                PackageKind = 'Appx'
                Identity = 'Microsoft.UI.Xaml.2.8'
                Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                IsReleaseAsset = $false
            },
            [PSCustomObject]@{
                Name = 'WinGet'
                Uri = $asset.Url
                FileName = 'Microsoft.DesktopAppInstaller.msixbundle'
                PackageKind = 'Bundle'
                Identity = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
                Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                IsReleaseAsset = $true
            }
        )

        foreach ($packageSpec in $packageSpecs) {
            $packageSpec | Add-Member -NotePropertyName Path -NotePropertyValue (Join-Path $tempDirectory $packageSpec.FileName)
            $failureCode = if ($packageSpec.IsReleaseAsset) { 'ReleaseAssetDownloadFailed' } else { 'DependencyDownloadFailed' }
            $null = & $DownloadFile $packageSpec.Uri $packageSpec.Path
            if (-not [System.IO.File]::Exists($packageSpec.Path)) {
                throw 'Downloaded package file is missing.'
            }

            $packageInfo = Get-Item -LiteralPath $packageSpec.Path -Force -ErrorAction Stop
            if ($packageInfo.Length -le 0) {
                throw 'Downloaded package file is empty.'
            }

            if ($packageSpec.IsReleaseAsset -and $packageInfo.Length -ne $asset.Size) {
                $failureCode = 'ReleaseAssetIncomplete'
                throw 'Downloaded release asset size does not match release metadata.'
            }

            if ($packageSpec.IsReleaseAsset) {
                $failureCode = 'ReleaseDigestMismatch'
                $actualDigest = (Get-FileHash -LiteralPath $packageSpec.Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                if (-not [string]::Equals($actualDigest, $asset.Digest, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Downloaded release asset does not match its SHA-256 digest.'
                }
            }

            $failureCode = if ($packageSpec.IsReleaseAsset) { 'ReleaseSignatureInvalid' } else { 'DependencySignatureInvalid' }
            $signatureVerified = & $VerifyPackageSignature $packageSpec.Path
            if ($signatureVerified -isnot [bool] -or -not $signatureVerified) {
                throw 'Package signature could not be verified.'
            }

            $failureCode = if ($packageSpec.IsReleaseAsset) { 'ReleasePackageInvalid' } else { 'DependencyPackageInvalid' }
            $packageMetadata = Get-WingetPackageMetadata -LiteralPath $packageSpec.Path -PackageKind $packageSpec.PackageKind
            if (-not (Test-WingetPackageArchitecture -PackageMetadata $packageMetadata -ExpectedName $packageSpec.Identity -ExpectedPublisher $packageSpec.Publisher -Architecture $Architecture -Bundle:$packageSpec.IsReleaseAsset)) {
                throw 'Package identity or architecture does not match the host.'
            }
        }

        $failurePhase = 'Install'
        foreach ($packageSpec in @($packageSpecs | Where-Object { -not $_.IsReleaseAsset })) {
            $failureCode = 'DependencyInstallFailed'
            $result.ChangesStarted = $true
            $installOutput = @(& $InstallPackage $packageSpec.Path)
            if ($installOutput.Count -gt 0 -and $installOutput[-1] -is [bool] -and -not $installOutput[-1]) {
                throw 'Dependency package installation returned failure.'
            }
        }

        $failureCode = 'WingetPackageInstallFailed'
        $result.ChangesStarted = $true
        $installOutput = @(& $InstallPackage $packageSpecs[2].Path)
        if ($installOutput.Count -gt 0 -and $installOutput[-1] -is [bool] -and -not $installOutput[-1]) {
            throw 'WinGet package installation returned failure.'
        }

        $failurePhase = 'Detection'
        $failureCode = 'WingetDetectionUnknown'
        $detectionResult = & $DetectWinget
        if ($detectionResult -is [System.Management.Automation.CommandInfo]) {
            $result.WingetDetected = $true
        }
        elseif ($detectionResult -is [bool]) {
            $result.WingetDetected = $detectionResult
            if (-not $detectionResult) {
                $failureCode = 'WingetNotDetected'
                throw 'WinGet command was not found after installation.'
            }
        }
        else {
            throw 'WinGet command discovery returned an unknown result.'
        }

        $result.Success = $true
        $result.Status = 'Complete'
        $result.ErrorCode = 'None'
    }
    catch {
        $result.Success = $false
        $result.Status = if ($failurePhase -eq 'Detection' -and $failureCode -eq 'WingetDetectionUnknown') { 'Unknown' } else { 'Failed' }
        $result.ErrorCode = $failureCode
    }
    finally {
        if ($tempDirectoryCreated) {
            try {
                if (-not (Test-WingetContainedTempDirectory -Root $rootDirectory -Candidate $tempDirectory)) {
                    throw 'Temporary cleanup target is outside its expected root.'
                }
                $tempItem = Get-Item -LiteralPath $tempDirectory -Force -ErrorAction Stop
                if ($tempItem.PSIsContainer -ne $true -or ($tempItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'Temporary cleanup target is not a normal directory.'
                }
                Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction Stop
            }
            catch {
                $result.CleanupSucceeded = $false
                if ($result.Success) {
                    $result.Success = $false
                    $result.Status = 'CleanupFailed'
                    $result.ErrorCode = 'TemporaryCleanupFailed'
                }
            }
        }

        $ErrorActionPreference = $priorErrorActionPreference
    }

    return $result
}

Export-ModuleMember -Function @(
    'Invoke-WingetBootstrap'
)
