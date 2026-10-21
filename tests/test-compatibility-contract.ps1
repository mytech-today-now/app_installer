# Offline, table-driven Windows and PowerShell support contract checks.
# No package manager, network request, runtime install, or OS change is performed.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1'
$manifestPath = Join-Path $repositoryRoot 'compatibility.json'
Import-Module -Name $modulePath -Force -DisableNameChecking
$manifest = Get-InstallerCompatibilityManifest -Path $manifestPath
$checkCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:checkCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-TestHostInfo {
    param(
        [string]$Platform = 'Windows',
        [string]$DisplayVersion = '26H2',
        [int]$BuildNumber = 26300,
        [string]$ProductType = 'WinNT',
        [string]$InstallationType = 'Client',
        [string]$EditionId = 'Core',
        [string]$Architecture = 'X64',
        [int]$DotNetFrameworkRelease = 533325,
        [bool]$MetadataAvailable = $true
    )

    $productFamily = if ($ProductType -eq 'WinNT' -and $InstallationType -eq 'Client') {
        'WindowsClient'
    }
    elseif ($ProductType -in @('LanmanNT', 'ServerNT') -and $InstallationType -match '^Server') {
        'WindowsServer'
    }
    else {
        'Unknown'
    }

    return [PSCustomObject]@{
        Platform = $Platform
        ProductFamily = $productFamily
        DisplayVersion = $DisplayVersion
        BuildNumber = $BuildNumber
        ProductType = $ProductType
        InstallationType = $InstallationType
        EditionId = $EditionId
        Architecture = $Architecture
        DotNetFrameworkRelease = $DotNetFrameworkRelease
        MetadataAvailable = $MetadataAvailable
        MetadataReasonCode = if ($MetadataAvailable) { '' } else { 'WINDOWS_METADATA_UNAVAILABLE' }
    }
}

function New-TestEngineInfo {
    param(
        [string]$Edition = 'Core',
        [string]$Version = '7.6.7'
    )

    return [PSCustomObject]@{
        PSEdition = $Edition
        PSVersion = [version]$Version
    }
}

try {
    $hostCases = @(
        [PSCustomObject]@{ Name = 'Windows 11 25H2 Home x64'; Host = (New-TestHostInfo -DisplayVersion '25H2' -BuildNumber 26200); Date = [datetime]'2026-10-17'; Expected = $true },
        [PSCustomObject]@{ Name = 'Windows 11 26H2 Pro x64'; Host = (New-TestHostInfo -EditionId 'Professional'); Date = [datetime]'2026-10-17'; Expected = $true },
        [PSCustomObject]@{ Name = 'Windows 11 24H2'; Host = (New-TestHostInfo -DisplayVersion '24H2' -BuildNumber 26100); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 10 22H2'; Host = (New-TestHostInfo -DisplayVersion '22H2' -BuildNumber 19045); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 10 1809 WinGet minimum'; Host = (New-TestHostInfo -DisplayVersion '1809' -BuildNumber 17763); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 10 build before WinGet minimum'; Host = (New-TestHostInfo -DisplayVersion '1803' -BuildNumber 17134); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 x86'; Host = (New-TestHostInfo -DisplayVersion '25H2' -BuildNumber 26200 -Architecture 'X86'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 ARM64'; Host = (New-TestHostInfo -Architecture 'Arm64'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 unknown architecture'; Host = (New-TestHostInfo -Architecture 'Unknown'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows metadata unavailable'; Host = (New-TestHostInfo -MetadataAvailable $false); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows Server 2025 Desktop Experience'; Host = (New-TestHostInfo -DisplayVersion '24H2' -BuildNumber 26100 -ProductType 'LanmanNT' -InstallationType 'Server' -EditionId 'ServerDatacenter'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows Server 2025 Server Core'; Host = (New-TestHostInfo -DisplayVersion '24H2' -BuildNumber 26100 -ProductType 'ServerNT' -InstallationType 'Server Core' -EditionId 'ServerStandardCore'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows Server 2022'; Host = (New-TestHostInfo -DisplayVersion '21H2' -BuildNumber 20348 -ProductType 'LanmanNT' -InstallationType 'Server' -EditionId 'ServerStandard'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 Enterprise edition'; Host = (New-TestHostInfo -EditionId 'Enterprise'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 26H1'; Host = (New-TestHostInfo -DisplayVersion '26H1' -BuildNumber 28000); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 future release'; Host = (New-TestHostInfo -DisplayVersion '27H2' -BuildNumber 26400); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 25H2 on its final supported date'; Host = (New-TestHostInfo -DisplayVersion '25H2' -BuildNumber 26200); Date = [datetime]'2027-10-12'; Expected = $true },
        [PSCustomObject]@{ Name = 'Windows 11 25H2 after end of servicing'; Host = (New-TestHostInfo -DisplayVersion '25H2' -BuildNumber 26200); Date = [datetime]'2027-10-13'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 26H2 on its final supported date'; Host = (New-TestHostInfo); Date = [datetime]'2028-10-10'; Expected = $true },
        [PSCustomObject]@{ Name = 'Windows 11 26H2 after end of servicing'; Host = (New-TestHostInfo); Date = [datetime]'2028-10-11'; Expected = $false }
    )

    foreach ($case in $hostCases) {
        $actual = Test-InstallerCompatibility -Component WindowsHost -HostInfo $case.Host -Date $case.Date
        Assert-Condition -Condition ($actual.IsSupported -eq $case.Expected) -Message ("Windows host boundary: {0}" -f $case.Name)
    }

    $unknownArchitecture = Test-InstallerCompatibility -Component WindowsHost -HostInfo (New-TestHostInfo -Architecture 'Unknown') -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $unknownArchitecture.IsSupported -and $unknownArchitecture.ReasonCode -eq 'WINDOWS_ARCHITECTURE_UNKNOWN') -Message 'Unknown Windows architecture has a stable fail-closed reason.'
    $missingMetadata = Test-InstallerCompatibility -Component WindowsHost -HostInfo (New-TestHostInfo -MetadataAvailable $false) -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $missingMetadata.IsSupported -and $missingMetadata.ReasonCode -eq 'WINDOWS_METADATA_UNAVAILABLE') -Message 'Unavailable Windows release or product metadata has a stable fail-closed reason.'

    $legacyWinGetHost = New-TestHostInfo -DisplayVersion '22H2' -BuildNumber 19045
    $legacyWinGetCapability = Test-InstallerWindows10WinGetBootstrapHost -HostInfo $legacyWinGetHost
    $legacyHostPreflight = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $legacyWinGetHost -Date ([datetime]'2026-10-17') -WingetAvailabilityProbe { throw 'Unsupported Windows 10 must not probe WinGet.' }
    Assert-Condition -Condition ($legacyWinGetCapability.IsSupported -and -not $legacyHostPreflight.IsSupported -and $legacyHostPreflight.ReasonCode -eq 'WINDOWS_RELEASE_UNSUPPORTED') -Message 'WinGet bootstrap eligibility remains separate from App Installer OS support.'
    $legacyWinGetBelowMinimum = Test-InstallerWindows10WinGetBootstrapHost -HostInfo (New-TestHostInfo -DisplayVersion '1803' -BuildNumber 17134)
    Assert-Condition -Condition (-not $legacyWinGetBelowMinimum.IsSupported -and $legacyWinGetBelowMinimum.ReasonCode -eq 'WINDOWS10_WINGET_BOOTSTRAP_UNSUPPORTED') -Message 'The legacy WinGet bootstrap rejects Windows 10 builds before 17763.'
    $legacyWinGetArm64 = Test-InstallerWindows10WinGetBootstrapHost -HostInfo (New-TestHostInfo -DisplayVersion '22H2' -BuildNumber 19045 -Architecture 'Arm64')
    Assert-Condition -Condition (-not $legacyWinGetArm64.IsSupported -and $legacyWinGetArm64.ReasonCode -eq 'WINDOWS_ARCHITECTURE_UNSUPPORTED') -Message 'The legacy WinGet bootstrap rejects ARM64 instead of selecting x64 dependencies.'
    $currentWindows11Bootstrap = Test-InstallerWindows10WinGetBootstrapHost -HostInfo (New-TestHostInfo)
    Assert-Condition -Condition (-not $currentWindows11Bootstrap.IsSupported -and $currentWindows11Bootstrap.ReasonCode -eq 'WINDOWS10_WINGET_BOOTSTRAP_UNSUPPORTED') -Message 'The legacy Windows 10 WinGet bootstrap is not selected on supported Windows 11.'

    $wingetProbeCount = 0
    $supportedPreflight = Get-InstallerHostPreflight -Component WindowsHost -HostInfo (New-TestHostInfo) -Date ([datetime]'2026-10-17') -WingetAvailabilityProbe {
        $script:wingetProbeCount++
        return $false
    }
    Assert-Condition -Condition ($supportedPreflight.IsSupported -and $supportedPreflight.ProductFamily -eq 'WindowsClient' -and $supportedPreflight.DisplayVersion -eq '26H2' -and $supportedPreflight.BuildNumber -eq 26300 -and $supportedPreflight.SelectedPackageArchitecture -eq 'X64') -Message 'A supported preflight records the client release, build, family, and selected x64 runtime artifact.'
    Assert-Condition -Condition ($supportedPreflight.RuntimeRequirements.Gui.WindowsPowerShell.minimumRelease -eq 461808 -and $supportedPreflight.RuntimeRequirements.Gui.PowerShellCore.runtimeMajor -eq 10) -Message 'The host preflight records the required .NET Framework and Windows Desktop runtime capabilities.'
    Assert-Condition -Condition ($wingetProbeCount -eq 1 -and $supportedPreflight.WinGet.Status -eq 'Unavailable' -and $supportedPreflight.WinGet.RequiredForHostSupport -eq $false) -Message 'Missing optional WinGet is reported without rejecting a supported Windows host.'

    $mismatchedPreflight = Get-InstallerHostPreflight -Component WindowsHost -HostInfo (New-TestHostInfo) -Date ([datetime]'2026-10-17') -RuntimeArtifactArchitecture 'Arm64' -WingetAvailabilityProbe {
        $script:wingetProbeCount++
        return $true
    }
    Assert-Condition -Condition (-not $mismatchedPreflight.IsSupported -and $mismatchedPreflight.ReasonCode -eq 'PACKAGE_ARCHITECTURE_MISMATCH' -and $null -eq $mismatchedPreflight.SelectedPackageArchitecture -and $wingetProbeCount -eq 1) -Message 'A mismatched runtime artifact is rejected before optional package-manager discovery.'

    $preflightBlockCases = @(
        [PSCustomObject]@{ Name = 'Windows 10'; Host = $legacyWinGetHost; ReasonCode = 'WINDOWS_RELEASE_UNSUPPORTED' },
        [PSCustomObject]@{ Name = 'Windows Server'; Host = (New-TestHostInfo -ProductType 'LanmanNT' -InstallationType 'Server' -EditionId 'ServerDatacenter'); ReasonCode = 'WINDOWS_NOT_CLIENT' },
        [PSCustomObject]@{ Name = 'x86 host'; Host = (New-TestHostInfo -Architecture 'X86'); ReasonCode = 'WINDOWS_ARCHITECTURE_UNSUPPORTED' },
        [PSCustomObject]@{ Name = 'ARM64 host'; Host = (New-TestHostInfo -Architecture 'Arm64'); ReasonCode = 'WINDOWS_ARCHITECTURE_UNSUPPORTED' },
        [PSCustomObject]@{ Name = 'unknown architecture'; Host = (New-TestHostInfo -Architecture 'Unknown'); ReasonCode = 'WINDOWS_ARCHITECTURE_UNKNOWN' },
        [PSCustomObject]@{ Name = 'OS metadata failure'; Host = (New-TestHostInfo -MetadataAvailable $false); ReasonCode = 'WINDOWS_METADATA_UNAVAILABLE' }
    )
    foreach ($case in $preflightBlockCases) {
        $probeCountBefore = $wingetProbeCount
        $blockedPreflight = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $case.Host -Date ([datetime]'2026-10-17') -WingetAvailabilityProbe {
            $script:wingetProbeCount++
            return $true
        }
        Assert-Condition -Condition (-not $blockedPreflight.IsSupported -and $blockedPreflight.ReasonCode -eq $case.ReasonCode -and $blockedPreflight.WinGet.Status -eq 'NotChecked' -and $null -eq $blockedPreflight.SelectedPackageArchitecture -and $wingetProbeCount -eq $probeCountBefore) -Message ("Unsupported preflight blocks WinGet probing and artifact selection: {0}" -f $case.Name)
    }

    $engineCases = @(
        [PSCustomObject]@{ Name = 'Windows PowerShell 5.1 Desktop'; Engine = (New-TestEngineInfo -Edition 'Desktop' -Version '5.1.0'); Expected = $true },
        [PSCustomObject]@{ Name = 'Windows PowerShell below 5.1'; Engine = (New-TestEngineInfo -Edition 'Desktop' -Version '5.0.0'); Expected = $false },
        [PSCustomObject]@{ Name = 'PowerShell Core 7.6.7'; Engine = (New-TestEngineInfo -Edition 'Core' -Version '7.6.7'); Expected = $true },
        [PSCustomObject]@{ Name = 'PowerShell Core below 7.6.7'; Engine = (New-TestEngineInfo -Edition 'Core' -Version '7.6.6'); Expected = $false },
        [PSCustomObject]@{ Name = 'PowerShell Core above pinned version'; Engine = (New-TestEngineInfo -Edition 'Core' -Version '7.6.8'); Expected = $false },
        [PSCustomObject]@{ Name = 'PowerShell Core retired 7.5 line'; Engine = (New-TestEngineInfo -Edition 'Core' -Version '7.5.12'); Expected = $false }
    )

    foreach ($case in $engineCases) {
        $actual = Test-InstallerPowerShellEngine -EngineInfo $case.Engine -Manifest $manifest
        Assert-Condition -Condition ($actual.IsSupported -eq $case.Expected) -Message ("PowerShell engine boundary: {0}" -f $case.Name)
    }

    $desktopOnLinux = Test-InstallerCompatibility -Component CrossPlatformCli -HostInfo (New-TestHostInfo -Platform 'Linux') -EngineInfo (New-TestEngineInfo -Edition 'Desktop' -Version '5.1.0') -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $desktopOnLinux.IsSupported) -Message 'Windows PowerShell is rejected for the macOS and Linux CLI.'

    $windowsHost = New-TestHostInfo
    $desktopEngine = New-TestEngineInfo -Edition 'Desktop' -Version '5.1.0'
    $coreEngine = New-TestEngineInfo -Edition 'Core' -Version '7.6.7'
    $oldCoreEngine = New-TestEngineInfo -Edition 'Core' -Version '7.6.6'

    $linuxPreflight = Get-InstallerHostPreflight -Component CrossPlatformCli -HostInfo (New-TestHostInfo -Platform 'Linux') -EngineInfo $coreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition ($linuxPreflight.IsSupported -and $linuxPreflight.Requirement -eq 'PowerShell Core 7.6.7 on an operating system supported by that PowerShell release.' -and $null -eq $linuxPreflight.SelectedPackageArchitecture -and $null -eq $linuxPreflight.RuntimeArtifactArchitecture -and $linuxPreflight.WinGet.Status -eq 'NotApplicable') -Message 'The cross-platform CLI preflight reports its PowerShell requirement without Windows artifact or WinGet fields.'

    $desktopGui = Test-InstallerCompatibility -Component WindowsGui -HostInfo $windowsHost -EngineInfo $desktopEngine -Date ([datetime]'2026-10-17') -WindowsFormsAvailable $true -ProcessArchitecture X64 -ApartmentState STA
    Assert-Condition -Condition ($desktopGui.IsSupported -and $desktopGui.ReasonCode -eq 'COMPATIBILITY_SUPPORTED') -Message 'Windows PowerShell 5.1 enables the GUI only after its full capability contract passes.'
    $desktopGuiBelowFramework = Test-InstallerCompatibility -Component WindowsGui -HostInfo (New-TestHostInfo -DotNetFrameworkRelease 461807) -EngineInfo $desktopEngine -Date ([datetime]'2026-10-17') -ProcessArchitecture X64 -ApartmentState STA
    Assert-Condition -Condition (-not $desktopGuiBelowFramework.IsSupported -and $desktopGuiBelowFramework.Reason.Contains('.NET Framework 4.7.2') -and $desktopGuiBelowFramework.ReasonCode -eq 'GUI_DOTNET_FRAMEWORK_BELOW_MINIMUM') -Message 'The Windows PowerShell GUI rejects .NET Framework below release 461808 before loading GUI assemblies.'
    $desktopGuiAtFramework = Test-InstallerCompatibility -Component WindowsGui -HostInfo (New-TestHostInfo -DotNetFrameworkRelease 461808) -EngineInfo $desktopEngine -Date ([datetime]'2026-10-17') -WindowsFormsAvailable $true -ProcessArchitecture X64 -ApartmentState STA
    Assert-Condition -Condition $desktopGuiAtFramework.IsSupported -Message 'The Windows PowerShell GUI accepts the .NET Framework 4.7.2 minimum release after assembly and STA checks.'
    $desktopGuiNoForms = Test-InstallerCompatibility -Component WindowsGui -HostInfo $windowsHost -EngineInfo $desktopEngine -Date ([datetime]'2026-10-17') -WindowsFormsAvailable $false -ProcessArchitecture X64 -ApartmentState STA
    Assert-Condition -Condition (-not $desktopGuiNoForms.IsSupported -and $desktopGuiNoForms.ReasonCode -eq 'GUI_ASSEMBLY_LOAD_FAILED') -Message 'Windows PowerShell GUI assembly load failure returns a stable reason code.'
    $desktopCli = Test-InstallerCompatibility -Component WindowsCli -HostInfo $windowsHost -EngineInfo $desktopEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition $desktopCli.IsSupported -Message 'Windows PowerShell 5.1 enables the Windows CLI on a supported client.'

    $coreCli = Test-InstallerCompatibility -Component WindowsCli -HostInfo $windowsHost -EngineInfo $coreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition $coreCli.IsSupported -Message 'PowerShell Core 7.6.7 enables the Windows CLI.'
    $coreGui = Test-InstallerCompatibility -Component WindowsGui -HostInfo $windowsHost -EngineInfo $coreEngine -WindowsFormsAvailable $true -WindowsFormsMajor 10 -DrawingMajor 10 -ProcessArchitecture X64 -ApartmentState STA -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition $coreGui.IsSupported -Message 'PowerShell Core 7.6.7 enables the GUI when the Windows Desktop runtime assemblies load.'
    $coreWrongRuntime = Test-InstallerCompatibility -Component WindowsGui -HostInfo $windowsHost -EngineInfo $coreEngine -WindowsFormsAvailable $true -WindowsFormsMajor 9 -DrawingMajor 10 -ProcessArchitecture X64 -ApartmentState STA -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $coreWrongRuntime.IsSupported -and $coreWrongRuntime.ReasonCode -eq 'GUI_DESKTOP_RUNTIME_VERSION_UNSUPPORTED') -Message 'PowerShell Core rejects a loaded Forms assembly from a different Windows Desktop runtime major.'
    $coreNoGui = Test-InstallerCompatibility -Component WindowsGui -HostInfo $windowsHost -EngineInfo $coreEngine -WindowsFormsAvailable $false -ProcessArchitecture X64 -ApartmentState STA -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $coreNoGui.IsSupported -and $coreNoGui.ReasonCode -eq 'GUI_ASSEMBLY_LOAD_FAILED' -and $coreNoGui.Message.Contains($manifest.recovery.gui)) -Message 'PowerShell Core without Windows Forms reports a stable reason and CLI recovery path.'
    $oldCoreCli = Test-InstallerCompatibility -Component WindowsCli -HostInfo $windowsHost -EngineInfo $oldCoreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition (-not $oldCoreCli.IsSupported) -Message 'PowerShell Core 7.6.6 is rejected before Windows CLI setup.'
    $expiredCore = Test-InstallerCompatibility -Component CrossPlatformCli -HostInfo (New-TestHostInfo -Platform 'Linux') -EngineInfo $coreEngine -Date ([datetime]'2028-11-15')
    Assert-Condition -Condition (-not $expiredCore.IsSupported -and $expiredCore.Reason.Contains('end of support') -and $expiredCore.Message.Contains('refreshed App Installer compatibility contract')) -Message 'PowerShell Core is rejected after its end-of-support date with a current-contract recovery path.'

    $linuxCli = Test-InstallerCompatibility -Component CrossPlatformCli -HostInfo (New-TestHostInfo -Platform 'Linux') -EngineInfo $coreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition $linuxCli.IsSupported -Message 'The cross-platform CLI keeps the detected Linux package-manager path.'
    $macCli = Test-InstallerCompatibility -Component CrossPlatformCli -HostInfo (New-TestHostInfo -Platform 'macOS') -EngineInfo $coreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition $macCli.IsSupported -Message 'The cross-platform CLI keeps the detected macOS package-manager path.'

    $unsupportedWindows = Test-InstallerCompatibility -Component WindowsCli -HostInfo (New-TestHostInfo -DisplayVersion '24H2' -BuildNumber 26100) -EngineInfo $coreEngine -Date ([datetime]'2026-10-17')
    Assert-Condition -Condition ($unsupportedWindows.Message.Contains('Windows 11 25H2 build 26200') -and $unsupportedWindows.Message.Contains('before package managers')) -Message 'Unsupported-host diagnostics state the minimum matrix and fail-closed boundary.'

    $readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    foreach ($release in @($manifest.windowsClient.releases)) {
        $releaseText = 'Windows 11 {0} build {1}' -f $release.displayVersion, $release.build
        Assert-Condition -Condition $readme.Contains($releaseText) -Message ("README publishes manifest release: {0}" -f $releaseText)
    }
    $coreVersionText = 'PowerShell Core {0}' -f $manifest.engines.powerShellCore.version
    foreach ($requiredText in @('compatibility.json', 'Home or Pro', 'x64', 'Windows PowerShell 5.1', $coreVersionText, '.NET Framework 4.7.2')) {
        Assert-Condition -Condition $readme.Contains($requiredText) -Message ("README publishes manifest value: {0}" -f $requiredText)
    }
    foreach ($guiPrerequisite in @($manifest.runtimePrerequisites.windowsPowerShellGui, $manifest.runtimePrerequisites.powerShellCoreGui)) {
        foreach ($assemblyName in @('System.Windows.Forms', 'System.Drawing', 'System.Web')) {
            Assert-Condition -Condition ($guiPrerequisite.requiredAssemblies -contains $assemblyName) -Message ("GUI runtime contract requires {0}." -f $assemblyName)
        }
        Assert-Condition -Condition ($guiPrerequisite.threadApartment -eq 'STA') -Message 'Both GUI engines require an STA UI thread.'
    }
    Assert-Condition -Condition ($readme.Contains('original CLI arguments') -and $readme.Contains('explicit consent') -and $readme.Contains('does not change PATH')) -Message 'README documents the CLI fallback and the consent-gated current-user runtime plan.'
    Assert-Condition -Condition ($readme.Contains('Optional for host support') -and $readme.Contains('every Server SKU remains outside the support matrix') -and $readme.Contains('If WinGet is missing')) -Message 'README separates optional WinGet availability from Windows host support and documents unverified Server package workflows.'
    foreach ($obsoleteClaim in @('Windows 10 (1809+)', 'Windows Server 2016+', 'PowerShell 7.2+')) {
        Assert-Condition -Condition (-not $readme.Contains($obsoleteClaim)) -Message ("README no longer claims unbounded or retired support: {0}" -f $obsoleteClaim)
    }
    Assert-Condition -Condition (-not $manifest.windowsExecutable.bundledPowerShellRuntime -and $manifest.windowsExecutable.entryPoint -eq 'install.bat') -Message 'The EXE contract records its launcher and confirms it does not bundle a PowerShell runtime.'
    Assert-Condition -Condition ($manifest.windowsExecutable.engineSelectionOrder.Count -eq 2 -and $manifest.windowsExecutable.runtimeDiscovery.automaticProvisioning -eq $false -and $manifest.windowsExecutable.runtimeDiscovery.consentRequiredProvisioning -eq $true -and $manifest.windowsExecutable.runtimeDiscovery.pathSearch -eq $false) -Message 'The EXE candidate order, fixed-path policy, and consent-gated provisioning behavior are sourced from the contract.'
    Assert-Condition -Condition ($manifest.windowsExecutable.runtimeDiscovery.candidateLocations -contains '%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe') -Message 'The runtime contract documents the 64-bit Windows PowerShell path for a 32-bit bootstrap process.'
    Assert-Condition -Condition ($manifest.windowsExecutable.runtimeDiscovery.candidateLocations -contains '%LOCALAPPDATA%\Programs\myTech.Today\AppInstaller\PowerShell\7.6.7\pwsh.exe') -Message 'The runtime contract documents the version-pinned current-user PowerShell location.'
    $runtimeProvisioning = $manifest.windowsExecutable.runtimeDiscovery.provisioning
    Assert-Condition -Condition ($runtimeProvisioning.version -eq $manifest.engines.powerShellCore.version -and $runtimeProvisioning.architecture -eq $manifest.windowsClient.architecture -and $runtimeProvisioning.artifactName -eq 'PowerShell-7.6.7-win-x64.zip' -and $runtimeProvisioning.source -eq 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.7/PowerShell-7.6.7-win-x64.zip' -and $runtimeProvisioning.sha256 -eq 'D2F952EBDBF24386CB8923553AA58E41A846DB35A6155EA04C58142A4B16DBB7') -Message 'Runtime provisioning selects the matching contract x64 artifact and published SHA-256 digest.'
    Assert-Condition -Condition ($runtimeProvisioning.installScope -eq 'current-user' -and $runtimeProvisioning.requiresAdministrator -eq $false -and $runtimeProvisioning.modifiesPath -eq $false -and $runtimeProvisioning.modifiesDefaultEngine -eq $false -and $runtimeProvisioning.signer -eq 'Microsoft Corporation') -Message 'The runtime plan uses a signed current-user install without changing PATH or the default engine.'
    Assert-Condition -Condition (-not $manifest.optionalPackageManagers.winget.requiredForHostSupport -and $manifest.optionalPackageManagers.winget.legacyBootstrap.currentMatrixReachable -eq $false -and $manifest.optionalPackageManagers.winget.legacyBootstrap.architecture -eq 'X64') -Message 'WinGet remains optional, and the legacy bootstrap target cannot bypass the current Windows support matrix.'
    foreach ($sourceName in @('lifecycleSource', 'dotNetFrameworkSource', 'windowsPowerShellSource', 'powerShellSource', 'powerShellReleaseSource', 'winGetSource')) {
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$manifest.windowsClient.verification.$sourceName)) -Message ("The compatibility contract records an official source for {0}." -f $sourceName)
    }

    $guiSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw
    $cliSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw
    $batchSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'install.bat') -Raw
    $elevatedSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'invoke-elevated-install.ps1') -Raw
    $provisionSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Install-CompatiblePowerShell.ps1') -Raw
    $runtimeSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1') -Raw
    $prerequisitePlanSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'modules\InstallerPrerequisitePlan.psm1') -Raw
    $wingetBootstrapSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'modules\WingetBootstrap.psm1') -Raw
    $startSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Start-Installer.ps1') -Raw
    Assert-Condition -Condition ($guiSource.IndexOf('Get-InstallerHostPreflight -Component WindowsHost') -lt $guiSource.IndexOf('Test-InstallerGuiCapability -HostInfo')) -Message 'The supported Windows host preflight runs before GUI capability detection.'
    Assert-Condition -Condition ($guiSource.IndexOf('Test-InstallerGuiCapability -HostInfo') -lt $guiSource.IndexOf('Import-Module -Name $trustModulePath')) -Message 'The full GUI capability gate runs before GUI helper loading.'
    Assert-Condition -Condition ($cliSource.IndexOf('Get-InstallerHostPreflight -Component $cliComponent') -lt $cliSource.IndexOf('$platformDetectPath')) -Message 'The CLI host preflight runs before platform setup and package-manager checks.'
    Assert-Condition -Condition ($batchSource.Contains('tools\Start-Installer.ps1') -and $startSource.Contains('Get-InstallerHostPreflight -Component WindowsHost')) -Message 'The executable bootstrap verifies the Windows host before runtime selection or installer startup.'
    Assert-Condition -Condition (-not $batchSource.Contains('Install-CompatiblePowerShell.ps1') -and -not $batchSource.Contains('winget install') -and -not $batchSource.Contains('where pwsh')) -Message 'The executable launcher neither installs PowerShell nor selects an arbitrary PATH command.'
    Assert-Condition -Condition ($batchSource.IndexOf('set "APP_INSTALLER_WHATIF="') -ge 0 -and $batchSource.IndexOf('set "APP_INSTALLER_WHATIF="') -lt $batchSource.IndexOf('type nul > "%BOOTSTRAP_STATUS_FILE%"')) -Message 'The batch launcher routes WhatIf before creating temporary bootstrap files.'
    Assert-Condition -Condition ($startSource.Contains('if (-not $WhatIfPreference -and -not [string]::IsNullOrWhiteSpace($startedMarker))') -and $startSource.Contains('Invoke-InstallerRuntimePrerequisiteFlow')) -Message 'The shared launcher suppresses its startup marker during WhatIf.'
    $runtimeSourceLower = $runtimeSource.ToLowerInvariant()
    Assert-Condition -Condition ($runtimeSourceLower.Contains('get-appxpackage -name ''microsoft.powershell''') -and $runtimeSourceLower.Contains('powershellcore\installedversions') -and $runtimeSourceLower.Contains('app paths\pwsh.exe')) -Message 'Runtime discovery checks registered PowerShell and Microsoft.PowerShell package locations.'
    Assert-Condition -Condition ($runtimeSource.Contains('WaitForExit($TimeoutSeconds * 1000)') -and $runtimeSource.Contains('Application parse preflight failed')) -Message 'Runtime probes use a finite timeout and parse the target entry point before launch.'
    Assert-Condition -Condition ($runtimeSource.Contains('APP_INSTALLER_RUNTIME_HANDOFF_PATH') -and $runtimeSource.Contains('No alternate engine was attempted')) -Message 'The runtime handoff avoids recursion and reports execution policy blocks without trying another engine.'
    $elevationInvocationStart = $elevatedSource.IndexOf("if (`$MyInvocation.InvocationName -ne '.')")
    $elevationInvocation = if ($elevationInvocationStart -ge 0) { $elevatedSource.Substring($elevationInvocationStart) } else { '' }
    Assert-Condition -Condition ($elevationInvocation.IndexOf('Get-InstallerHostPreflight -Component WindowsHost') -ge 0 -and $elevationInvocation.IndexOf('Get-InstallerHostPreflight -Component WindowsHost') -lt $elevationInvocation.IndexOf('Invoke-ElevatedInstall -Arguments')) -Message 'The elevation helper verifies the host before requesting elevation.'
    Assert-Condition -Condition ($provisionSource.IndexOf('Get-InstallerHostPreflight -Component WindowsHost') -lt $provisionSource.IndexOf('Invoke-InstallerRuntimePrerequisiteFlow') -and $provisionSource.Contains('Invoke-InstallerRuntimePrerequisiteFlow')) -Message 'Runtime provisioning delegates to the shared compatibility preflight and consent flow.'
    Assert-Condition -Condition ($provisionSource.Contains('No application package action was started') -and -not $provisionSource.Contains('& winget install')) -Message 'The optional runtime helper stops before application actions and does not bypass the pinned provisioning path.'
    Assert-Condition -Condition ($prerequisitePlanSource.IndexOf('Get-InstallerHostPreflight -Component WindowsHost') -lt $prerequisitePlanSource.IndexOf('Resolve-InstallerRuntime -Component $Component') -and $prerequisitePlanSource.Contains('$provisioning.architecture -ceq $selectedArchitecture')) -Message 'Runtime candidate probing and artifact planning follow host and artifact architecture validation.'
    Assert-Condition -Condition (-not $guiSource.Contains('[System.Environment]::OSVersion') -and -not $cliSource.Contains('[System.Environment]::OSVersion') -and -not $wingetBootstrapSource.Contains('[System.Environment]::OSVersion')) -Message 'Windows and legacy WinGet bootstrap gates use shared registry metadata instead of Environment.OSVersion.'

    Write-Host "[OK] Compatibility contract checks passed ($checkCount assertions)." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
