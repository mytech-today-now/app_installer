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
        [int]$DotNetFrameworkRelease = 533325
    )

    return [PSCustomObject]@{
        Platform = $Platform
        DisplayVersion = $DisplayVersion
        BuildNumber = $BuildNumber
        ProductType = $ProductType
        InstallationType = $InstallationType
        EditionId = $EditionId
        Architecture = $Architecture
        DotNetFrameworkRelease = $DotNetFrameworkRelease
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
        [PSCustomObject]@{ Name = 'Windows 11 x86'; Host = (New-TestHostInfo -DisplayVersion '25H2' -BuildNumber 26200 -Architecture 'X86'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows 11 ARM64'; Host = (New-TestHostInfo -Architecture 'Arm64'); Date = [datetime]'2026-10-17'; Expected = $false },
        [PSCustomObject]@{ Name = 'Windows Server 2025'; Host = (New-TestHostInfo -ProductType 'LanmanNT' -InstallationType 'Server'); Date = [datetime]'2026-10-17'; Expected = $false },
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
    Assert-Condition -Condition ($readme.Contains('original CLI arguments') -and $readme.Contains('does not install a runtime')) -Message 'README documents single CLI fallback with argument preservation and no runtime provisioning.'
    foreach ($obsoleteClaim in @('Windows 10 (1809+)', 'Windows Server 2016+', 'PowerShell 7.2+')) {
        Assert-Condition -Condition (-not $readme.Contains($obsoleteClaim)) -Message ("README no longer claims unbounded or retired support: {0}" -f $obsoleteClaim)
    }
    Assert-Condition -Condition (-not $manifest.windowsExecutable.bundledPowerShellRuntime -and $manifest.windowsExecutable.entryPoint -eq 'install.bat') -Message 'The EXE contract records its launcher and confirms it does not bundle a PowerShell runtime.'
    Assert-Condition -Condition ($manifest.windowsExecutable.engineSelectionOrder.Count -eq 2 -and $manifest.windowsExecutable.runtimeDiscovery.automaticProvisioning -eq $false -and $manifest.windowsExecutable.runtimeDiscovery.pathSearch -eq $false) -Message 'The EXE candidate order, fixed-path policy, and no-provisioning behavior are sourced from the contract.'
    Assert-Condition -Condition ($manifest.windowsExecutable.runtimeDiscovery.candidateLocations -contains '%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe') -Message 'The runtime contract documents the 64-bit Windows PowerShell path for a 32-bit bootstrap process.'

    $guiSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw
    $cliSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw
    $batchSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'install.bat') -Raw
    $elevatedSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'invoke-elevated-install.ps1') -Raw
    $provisionSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Install-CompatiblePowerShell.ps1') -Raw
    $runtimeSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1') -Raw
    $startSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Start-Installer.ps1') -Raw
    Assert-Condition -Condition ($guiSource.IndexOf('Test-InstallerCompatibility -Component WindowsHost') -lt $guiSource.IndexOf('Test-InstallerGuiCapability -HostInfo')) -Message 'The supported Windows host check runs before GUI capability detection.'
    Assert-Condition -Condition ($guiSource.IndexOf('Test-InstallerGuiCapability -HostInfo') -lt $guiSource.IndexOf('Import-Module -Name $trustModulePath')) -Message 'The full GUI capability gate runs before GUI helper loading.'
    Assert-Condition -Condition ($cliSource.IndexOf('Test-InstallerCompatibility -Component $cliComponent') -lt $cliSource.IndexOf('$platformDetectPath')) -Message 'The CLI gate runs before platform setup and package-manager checks.'
    Assert-Condition -Condition ($batchSource.Contains('tools\Start-Installer.ps1') -and $startSource.Contains('Test-InstallerCompatibility -Component WindowsHost')) -Message 'The executable bootstrap verifies the Windows host before runtime selection or installer startup.'
    Assert-Condition -Condition (-not $batchSource.Contains('Install-CompatiblePowerShell.ps1') -and -not $batchSource.Contains('winget install') -and -not $batchSource.Contains('where pwsh')) -Message 'The executable launcher neither installs PowerShell nor selects an arbitrary PATH command.'
    $runtimeSourceLower = $runtimeSource.ToLowerInvariant()
    Assert-Condition -Condition ($runtimeSourceLower.Contains('get-appxpackage -name ''microsoft.powershell''') -and $runtimeSourceLower.Contains('powershellcore\installedversions') -and $runtimeSourceLower.Contains('app paths\pwsh.exe')) -Message 'Runtime discovery checks registered PowerShell and Microsoft.PowerShell package locations.'
    Assert-Condition -Condition ($runtimeSource.Contains('WaitForExit($TimeoutSeconds * 1000)') -and $runtimeSource.Contains('Application parse preflight failed')) -Message 'Runtime probes use a finite timeout and parse the target entry point before launch.'
    Assert-Condition -Condition ($runtimeSource.Contains('APP_INSTALLER_RUNTIME_HANDOFF_PATH') -and $runtimeSource.Contains('No alternate engine was attempted')) -Message 'The runtime handoff avoids recursion and reports execution policy blocks without trying another engine.'
    $elevationInvocationStart = $elevatedSource.IndexOf("if (`$MyInvocation.InvocationName -ne '.')")
    $elevationInvocation = if ($elevationInvocationStart -ge 0) { $elevatedSource.Substring($elevationInvocationStart) } else { '' }
    Assert-Condition -Condition ($elevationInvocation.IndexOf('Test-InstallerCompatibility -Component WindowsHost') -ge 0 -and $elevationInvocation.IndexOf('Test-InstallerCompatibility -Component WindowsHost') -lt $elevationInvocation.IndexOf('Invoke-ElevatedInstall -Arguments')) -Message 'The elevation helper verifies the host before requesting elevation.'
    Assert-Condition -Condition ($provisionSource.IndexOf('Test-InstallerCompatibility -Component WindowsHost') -lt $provisionSource.IndexOf('& winget install')) -Message 'Runtime provisioning verifies the host before invoking WinGet.'
    Assert-Condition -Condition ($provisionSource.Contains('$manifest.engines.powerShellCore.version')) -Message 'Runtime provisioning reads its version from the compatibility manifest.'

    Write-Host "[OK] Compatibility contract checks passed ($checkCount assertions)." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
