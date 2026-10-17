# Offline tests for the Windows 10 WinGet bootstrap trust and failure gates.
# No release request, package download, or Add-AppxPackage operation is performed.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\WingetBootstrap.psm1'
$guiPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-winget-bootstrap-test-' + [guid]::NewGuid().ToString('N'))))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$checkCount = 0
$usedTempDirectories = New-Object 'System.Collections.Generic.List[string]'

if (-not $testRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Test temporary directory is outside the system temporary directory.'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:checkCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-PackageFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Appx', 'Bundle')][string]$PackageKind,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Architecture,
        [string]$Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        if ($PackageKind -eq 'Bundle') {
            $entryName = 'AppxMetadata/AppxBundleManifest.xml'
            $xml = "<Bundle xmlns='http://schemas.microsoft.com/appx/2013/bundle'><Identity Name='$Name' Publisher='$Publisher' Version='1.0.0.0' ProcessorArchitecture='neutral' /><Packages><Package Type='application' Architecture='$Architecture' /></Packages></Bundle>"
        }
        else {
            $entryName = 'AppxManifest.xml'
            $xml = "<Package xmlns='http://schemas.microsoft.com/appx/manifest/foundation/windows10'><Identity Name='$Name' Publisher='$Publisher' Version='1.0.0.0' ProcessorArchitecture='$Architecture' /></Package>"
        }

        $entry = $zip.CreateEntry($entryName)
        $stream = $entry.Open()
        try {
            $encoding = New-Object System.Text.UTF8Encoding($false)
            $writer = New-Object System.IO.StreamWriter($stream, $encoding)
            try {
                $writer.Write($xml)
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Get-Sha256Digest {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function New-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Digest,
        [Parameter(Mandatory = $true)][long]$Size,
        [string]$Tag = 'v1.2.3'
    )

    return [PSCustomObject]@{
        name = $Name
        state = 'uploaded'
        browser_download_url = "https://github.com/microsoft/winget-cli/releases/download/$Tag/$Name"
        digest = "sha256:$Digest"
        size = $Size
    }
}

function New-ReleaseMetadata {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [string]$Tag = 'v1.2.3'
    )

    return [PSCustomObject]@{
        tag_name = $Tag
        draft = $false
        prerelease = $false
        url = "https://api.github.com/repos/microsoft/winget-cli/releases/12345"
        html_url = "https://github.com/microsoft/winget-cli/releases/tag/$Tag"
        assets = $Assets
    }
}

function Invoke-FixtureScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][hashtable]$Payloads,
        [string]$DownloadFailureUri,
        [string]$TruncateUri,
        [string]$SignatureMismatchSuffix,
        [string]$InstallFailureSuffix,
        [ValidateSet('Success', 'Missing', 'Unknown')][string]$Detection = 'Success',
        [string]$Architecture = 'x64',
        [bool]$HostVerified = $true
    )

    $installCalls = New-Object 'System.Collections.Generic.List[string]'
    $downloadPaths = New-Object 'System.Collections.Generic.List[string]'
    $verifiedPaths = New-Object 'System.Collections.Generic.List[string]'
    $releaseProvider = { return $Release }.GetNewClosure()
    $downloadProvider = {
        param($Uri, $Path)
        if ($DownloadFailureUri -and $Uri -eq $DownloadFailureUri) {
            throw 'Injected download failure.'
        }
        if (-not $Payloads.ContainsKey($Uri)) {
            throw 'No injected byte stream exists for this URI.'
        }

        $bytes = [byte[]]$Payloads[$Uri]
        $downloadedLength = $bytes.Length
        if ($TruncateUri -and $Uri -eq $TruncateUri -and $downloadedLength -gt 1) {
            $downloadedLength--
        }

        $memory = New-Object System.IO.MemoryStream
        $file = $null
        try {
            $memory.Write($bytes, 0, $downloadedLength)
            $memory.Position = 0
            $file = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $memory.CopyTo($file)
            $downloadPaths.Add($Path)
        }
        finally {
            if ($null -ne $file) { $file.Dispose() }
            $memory.Dispose()
        }
    }.GetNewClosure()
    $signatureVerifier = {
        param($Path)
        $verifiedPaths.Add($Path)
        if ($SignatureMismatchSuffix -and $Path.EndsWith($SignatureMismatchSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return $true
    }.GetNewClosure()
    $packageInstaller = {
        param($Path)
        $installCalls.Add($Path)
        if ($InstallFailureSuffix -and $Path.EndsWith($InstallFailureSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Injected Add-AppxPackage failure.'
        }
        return $true
    }.GetNewClosure()
    $commandDiscovery = {
        if ($Detection -eq 'Success') { return $true }
        if ($Detection -eq 'Missing') { return $false }
        return $null
    }.GetNewClosure()
    $hostVerifier = { return $HostVerified }.GetNewClosure()

    $result = Invoke-WingetBootstrap `
        -Architecture $Architecture `
        -GetReleaseMetadata $releaseProvider `
        -DownloadFile $downloadProvider `
        -VerifyPackageSignature $signatureVerifier `
        -InstallPackage $packageInstaller `
        -DetectWinget $commandDiscovery `
        -VerifyHost $hostVerifier `
        -TempRoot $testRoot

    foreach ($path in $downloadPaths) {
        $parent = [System.IO.Path]::GetDirectoryName($path)
        if (-not $script:usedTempDirectories.Contains($parent)) {
            $script:usedTempDirectories.Add($parent)
        }
        Assert-Condition -Condition (-not [System.IO.Directory]::Exists($parent)) -Message "$Name removes its unique download directory during cleanup"
    }

    return [PSCustomObject]@{
        Name = $Name
        Result = $result
        InstallCalls = @($installCalls.ToArray())
        DownloadPaths = @($downloadPaths.ToArray())
        VerifiedPaths = @($verifiedPaths.ToArray())
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    $vcLibsUri = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
    $uiXamlUri = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'
    $bundleUri = 'https://github.com/microsoft/winget-cli/releases/download/v1.2.3/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    $fixtureVCLibsPath = Join-Path $fixtureRoot 'VCLibs.appx'
    $fixtureUIXamlPath = Join-Path $fixtureRoot 'UI.Xaml.appx'
    $fixtureBundlePath = Join-Path $fixtureRoot 'WinGet.msixbundle'
    $fixtureWrongArchBundlePath = Join-Path $fixtureRoot 'WinGet-x86.msixbundle'
    $fixtureWrongPublisherBundlePath = Join-Path $fixtureRoot 'WinGet-untrusted-publisher.msixbundle'
    $fixtureWrongPublisherDependencyPath = Join-Path $fixtureRoot 'VCLibs-untrusted-publisher.appx'
    New-PackageFixture -Path $fixtureVCLibsPath -PackageKind Appx -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -Architecture x64
    New-PackageFixture -Path $fixtureUIXamlPath -PackageKind Appx -Name 'Microsoft.UI.Xaml.2.8' -Architecture x64
    New-PackageFixture -Path $fixtureBundlePath -PackageKind Bundle -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -Architecture x64
    New-PackageFixture -Path $fixtureWrongArchBundlePath -PackageKind Bundle -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -Architecture x86
    New-PackageFixture -Path $fixtureWrongPublisherBundlePath -PackageKind Bundle -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -Architecture x64 -Publisher 'CN=Untrusted Publisher'
    New-PackageFixture -Path $fixtureWrongPublisherDependencyPath -PackageKind Appx -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -Architecture x64 -Publisher 'CN=Untrusted Publisher'

    $payloads = @{
        $vcLibsUri = [System.IO.File]::ReadAllBytes($fixtureVCLibsPath)
        $uiXamlUri = [System.IO.File]::ReadAllBytes($fixtureUIXamlPath)
        $bundleUri = [System.IO.File]::ReadAllBytes($fixtureBundlePath)
    }
    $bundleDigest = Get-Sha256Digest -Path $fixtureBundlePath
    $bundleLength = [System.IO.FileInfo]::new($fixtureBundlePath).Length
    $validAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Digest $bundleDigest -Size $bundleLength
    $validRelease = New-ReleaseMetadata -Assets @($validAsset)

    $missingAssets = Invoke-FixtureScenario -Name 'missing assets' -Release (New-ReleaseMetadata -Assets @()) -Payloads $payloads
    Assert-Condition -Condition (-not $missingAssets.Result.Success -and $missingAssets.InstallCalls.Count -eq 0 -and $missingAssets.DownloadPaths.Count -eq 0) -Message 'Missing release bundle fails before downloads or package changes'

    $multipleAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_x64.msixbundle' -Digest $bundleDigest -Size $bundleLength
    $multipleAssets = Invoke-FixtureScenario -Name 'multiple bundles' -Release (New-ReleaseMetadata -Assets @($validAsset, $multipleAsset)) -Payloads $payloads
    Assert-Condition -Condition (-not $multipleAssets.Result.Success -and $multipleAssets.InstallCalls.Count -eq 0 -and $multipleAssets.DownloadPaths.Count -eq 0) -Message 'Multiple compatible bundles are rejected without choosing by ordering'

    $wrongArchitectureAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_arm64.msixbundle' -Digest $bundleDigest -Size $bundleLength
    $wrongArchitecturePayloads = @{}
    foreach ($key in $payloads.Keys) { $wrongArchitecturePayloads[$key] = $payloads[$key] }
    $wrongArchitecturePayloads[$wrongArchitectureAsset.browser_download_url] = [System.IO.File]::ReadAllBytes($fixtureBundlePath)
    $wrongArchitecture = Invoke-FixtureScenario -Name 'release asset architecture mismatch' -Release (New-ReleaseMetadata -Assets @($wrongArchitectureAsset)) -Payloads $wrongArchitecturePayloads
    Assert-Condition -Condition (-not $wrongArchitecture.Result.Success -and $wrongArchitecture.InstallCalls.Count -eq 0 -and $wrongArchitecture.DownloadPaths.Count -eq 0) -Message 'A release asset marked for another architecture is rejected before download'

    $malformedResponse = Invoke-FixtureScenario -Name 'malformed release response' -Release ([PSCustomObject]@{ tag_name = 'v1.2.3'; assets = 'not-an-array' }) -Payloads $payloads
    Assert-Condition -Condition (-not $malformedResponse.Result.Success -and $malformedResponse.InstallCalls.Count -eq 0 -and $malformedResponse.DownloadPaths.Count -eq 0) -Message 'Malformed release response is rejected without package changes'

    $failedDownload = Invoke-FixtureScenario -Name 'download failure' -Release $validRelease -Payloads $payloads -DownloadFailureUri $bundleUri
    Assert-Condition -Condition (-not $failedDownload.Result.Success -and $failedDownload.InstallCalls.Count -eq 0) -Message 'Release bundle download failure prevents all package commands'

    $incompleteDownload = Invoke-FixtureScenario -Name 'incomplete download' -Release $validRelease -Payloads $payloads -TruncateUri $bundleUri
    Assert-Condition -Condition (-not $incompleteDownload.Result.Success -and $incompleteDownload.InstallCalls.Count -eq 0) -Message 'Incomplete release bundle download is rejected before package changes'

    $badDigestAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Digest ('0' * 64) -Size $bundleLength
    $badDigest = Invoke-FixtureScenario -Name 'digest mismatch' -Release (New-ReleaseMetadata -Assets @($badDigestAsset)) -Payloads $payloads
    Assert-Condition -Condition (-not $badDigest.Result.Success -and $badDigest.InstallCalls.Count -eq 0) -Message 'Release digest mismatch prevents all package commands'

    $badSignature = Invoke-FixtureScenario -Name 'signature mismatch' -Release $validRelease -Payloads $payloads -SignatureMismatchSuffix '.msixbundle'
    Assert-Condition -Condition (-not $badSignature.Result.Success -and $badSignature.InstallCalls.Count -eq 0) -Message 'Release signature mismatch prevents all package commands'

    $badDependencySignature = Invoke-FixtureScenario -Name 'dependency signature mismatch' -Release $validRelease -Payloads $payloads -SignatureMismatchSuffix 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
    Assert-Condition -Condition (-not $badDependencySignature.Result.Success -and $badDependencySignature.InstallCalls.Count -eq 0) -Message 'Dependency signature mismatch prevents all package changes'

    $wrongPublisherPayloads = @{}
    foreach ($key in $payloads.Keys) { $wrongPublisherPayloads[$key] = $payloads[$key] }
    $wrongPublisherPayloads[$bundleUri] = [System.IO.File]::ReadAllBytes($fixtureWrongPublisherBundlePath)
    $wrongPublisherDigest = Get-Sha256Digest -Path $fixtureWrongPublisherBundlePath
    $wrongPublisherSize = [System.IO.FileInfo]::new($fixtureWrongPublisherBundlePath).Length
    $wrongPublisherAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Digest $wrongPublisherDigest -Size $wrongPublisherSize
    $wrongPublisher = Invoke-FixtureScenario -Name 'bundle publisher mismatch' -Release (New-ReleaseMetadata -Assets @($wrongPublisherAsset)) -Payloads $wrongPublisherPayloads
    Assert-Condition -Condition (-not $wrongPublisher.Result.Success -and $wrongPublisher.InstallCalls.Count -eq 0) -Message 'A package with the expected name and architecture but an unapproved publisher is rejected before all package changes'

    $wrongDependencyPublisherPayloads = @{}
    foreach ($key in $payloads.Keys) { $wrongDependencyPublisherPayloads[$key] = $payloads[$key] }
    $wrongDependencyPublisherPayloads[$vcLibsUri] = [System.IO.File]::ReadAllBytes($fixtureWrongPublisherDependencyPath)
    $wrongDependencyPublisher = Invoke-FixtureScenario -Name 'dependency publisher mismatch' -Release $validRelease -Payloads $wrongDependencyPublisherPayloads
    Assert-Condition -Condition (-not $wrongDependencyPublisher.Result.Success -and $wrongDependencyPublisher.InstallCalls.Count -eq 0) -Message 'A dependency with the expected name and architecture but an unapproved publisher is rejected before package changes'

    $wrongArchitecturePayloads = @{}
    foreach ($key in $payloads.Keys) { $wrongArchitecturePayloads[$key] = $payloads[$key] }
    $wrongArchitecturePayloads[$bundleUri] = [System.IO.File]::ReadAllBytes($fixtureWrongArchBundlePath)
    $wrongArchitectureManifestAsset = New-ReleaseAsset -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Digest (Get-Sha256Digest -Path $fixtureWrongArchBundlePath) -Size ([System.IO.FileInfo]::new($fixtureWrongArchBundlePath).Length)
    $wrongArchitectureManifest = Invoke-FixtureScenario -Name 'bundle manifest architecture mismatch' -Release (New-ReleaseMetadata -Assets @($wrongArchitectureManifestAsset)) -Payloads $wrongArchitecturePayloads
    Assert-Condition -Condition (-not $wrongArchitectureManifest.Result.Success -and $wrongArchitectureManifest.InstallCalls.Count -eq 0) -Message 'A verified bundle without a host-compatible application package is rejected'

    $unsupportedHost = Invoke-FixtureScenario -Name 'unsupported host architecture' -Release $validRelease -Payloads $payloads -Architecture arm64
    Assert-Condition -Condition (-not $unsupportedHost.Result.Success -and $unsupportedHost.InstallCalls.Count -eq 0 -and $unsupportedHost.DownloadPaths.Count -eq 0) -Message 'Unsupported host architecture fails before download or package changes'

    $unverifiedHost = Invoke-FixtureScenario -Name 'unverified operating system' -Release $validRelease -Payloads $payloads -HostVerified $false
    Assert-Condition -Condition (-not $unverifiedHost.Result.Success -and $unverifiedHost.InstallCalls.Count -eq 0 -and $unverifiedHost.DownloadPaths.Count -eq 0) -Message 'Non-Windows or non-Windows-10 host is rejected before download or package changes'

    $vclibsInstallFailure = Invoke-FixtureScenario -Name 'VCLibs installation failure' -Release $validRelease -Payloads $payloads -InstallFailureSuffix 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
    Assert-Condition -Condition (-not $vclibsInstallFailure.Result.Success -and $vclibsInstallFailure.InstallCalls.Count -eq 1 -and $vclibsInstallFailure.InstallCalls[0] -notlike '*.msixbundle') -Message 'VCLibs installation failure prevents UI.Xaml and WinGet package commands'

    $xamlInstallFailure = Invoke-FixtureScenario -Name 'UI.Xaml installation failure' -Release $validRelease -Payloads $payloads -InstallFailureSuffix 'Microsoft.UI.Xaml.2.8.x64.appx'
    Assert-Condition -Condition (-not $xamlInstallFailure.Result.Success -and $xamlInstallFailure.InstallCalls.Count -eq 2 -and $xamlInstallFailure.InstallCalls[-1] -notlike '*.msixbundle') -Message 'UI.Xaml installation failure prevents the WinGet package command'

    $successfulSetup = Invoke-FixtureScenario -Name 'valid signatures and package detection' -Release $validRelease -Payloads $payloads
    Assert-Condition -Condition ($successfulSetup.Result.Success -and $successfulSetup.Result.Status -eq 'Complete' -and $successfulSetup.Result.WingetDetected -and $successfulSetup.InstallCalls.Count -eq 3) -Message 'Valid package signatures, digest, architecture, dependencies, and WinGet detection complete bootstrap'
    Assert-Condition -Condition ($successfulSetup.VerifiedPaths.Count -eq 3) -Message 'Signature verifier was called for both dependencies and the release bundle'

    $missingCommand = Invoke-FixtureScenario -Name 'WinGet command absent' -Release $validRelease -Payloads $payloads -Detection Missing
    Assert-Condition -Condition (-not $missingCommand.Result.Success -and $missingCommand.Result.Status -eq 'Failed' -and -not $missingCommand.Result.WingetDetected) -Message 'Explicit missing WinGet command is not success'

    $unknownCommand = Invoke-FixtureScenario -Name 'WinGet command result unknown' -Release $validRelease -Payloads $payloads -Detection Unknown
    Assert-Condition -Condition (-not $unknownCommand.Result.Success -and $unknownCommand.Result.Status -eq 'Unknown') -Message 'Unknown WinGet command discovery is not treated as success'

    $moduleText = [System.IO.File]::ReadAllText($modulePath)
    $signToolFinder = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$null).FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-WingetSignTool' }, $true) | Select-Object -First 1
    Assert-Condition -Condition ($null -ne $signToolFinder -and -not $signToolFinder.Extent.Text.Contains('Get-Command -Name ''signtool.exe''')) -Message 'The signature verifier cannot resolve an arbitrary signtool.exe from PATH'

    $allDownloads = @(
        $missingAssets.DownloadPaths + $multipleAssets.DownloadPaths + $wrongArchitecture.DownloadPaths +
        $malformedResponse.DownloadPaths + $failedDownload.DownloadPaths + $incompleteDownload.DownloadPaths +
        $badDigest.DownloadPaths + $badSignature.DownloadPaths + $badDependencySignature.DownloadPaths + $wrongPublisher.DownloadPaths + $wrongDependencyPublisher.DownloadPaths + $wrongArchitectureManifest.DownloadPaths +
        $unsupportedHost.DownloadPaths + $unverifiedHost.DownloadPaths + $vclibsInstallFailure.DownloadPaths + $xamlInstallFailure.DownloadPaths +
        $successfulSetup.DownloadPaths + $missingCommand.DownloadPaths + $unknownCommand.DownloadPaths
    )
    $uniqueDownloadDirectories = @($usedTempDirectories.ToArray() | Select-Object -Unique)
    Assert-Condition -Condition ($uniqueDownloadDirectories.Count -eq $usedTempDirectories.Count) -Message 'Each scenario received a distinct GUID-named contained temporary directory'
    Assert-Condition -Condition ($allDownloads.Count -gt 0 -and $uniqueDownloadDirectories.Count -eq 13) -Message 'Offline byte-stream cases exercised temporary downloads and cleanup'

    $guiText = [System.IO.File]::ReadAllText($guiPath)
    $cliText = [System.IO.File]::ReadAllText($cliPath)
    $guiAst = [System.Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$null, [ref]$null)
    $cliAst = [System.Management.Automation.Language.Parser]::ParseFile($cliPath, [ref]$null, [ref]$null)
    $guiBootstrap = $guiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-WingetOnWindows10' }, $true) | Select-Object -First 1
    $cliBootstrap = $cliAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-WingetOnWindows10' }, $true) | Select-Object -First 1
    Assert-Condition -Condition ($null -ne $guiBootstrap -and $guiBootstrap.Extent.Text.Contains('if (-not $isWindows10)') -and $guiBootstrap.Extent.Text.Contains('WingetBootstrap\Invoke-WingetBootstrap')) -Message 'GUI keeps the non-Windows-10 no-op guard and delegates to the verifier'
    Assert-Condition -Condition ($null -ne $cliBootstrap -and $cliBootstrap.Extent.Text.Contains('if (-not $isWindows10)') -and $cliBootstrap.Extent.Text.Contains('WingetBootstrap\Invoke-WingetBootstrap')) -Message 'CLI keeps the non-Windows-10 no-op guard and delegates to the verifier'
    Assert-Condition -Condition ($cliText.Contains('if (-not ($null -eq $IsWindows -or $IsWindows))') -and $guiText.Contains('function Test-WingetAvailable')) -Message 'Existing CLI non-Windows guard and GUI WinGet detection remain present'
    Assert-Condition -Condition ($guiText.Contains('The installer could not verify WinGet setup and made no package changes.') -and $cliText.Contains('The installer could not verify WinGet setup and made no package changes.')) -Message 'Both entrypoints provide truthful no-change manual-install recovery text'
    Assert-Condition -Condition (-not $guiBootstrap.Extent.Text.Contains('Add-AppxPackage') -and -not $cliBootstrap.Extent.Text.Contains('Add-AppxPackage') -and -not $guiBootstrap.Extent.Text.Contains('ErrorAction SilentlyContinue') -and -not $cliBootstrap.Extent.Text.Contains('ErrorAction SilentlyContinue')) -Message 'Both entrypoints avoid direct package calls and suppressed dependency errors'

    Write-Host "[OK] Winget bootstrap offline checks passed ($checkCount assertions)." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
