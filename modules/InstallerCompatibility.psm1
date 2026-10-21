function Get-InstallerCompatibilityManifest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'compatibility.json')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The compatibility contract was not found: $Path"
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "The compatibility contract is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-InstallerHostInfo {
    [CmdletBinding()]
    param()

    $platform = 'Unknown'
    if ($null -ne $IsWindows -and $IsWindows) {
        $platform = 'Windows'
    }
    elseif ($null -ne $IsMacOS -and $IsMacOS) {
        $platform = 'macOS'
    }
    elseif ($null -ne $IsLinux -and $IsLinux) {
        $platform = 'Linux'
    }
    elseif ($env:OS -match 'Windows') {
        $platform = 'Windows'
    }

    $architecture = ''
    try {
        $architecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    }
    catch {
        if ($env:PROCESSOR_ARCHITEW6432) {
            $architecture = [string]$env:PROCESSOR_ARCHITEW6432
        }
        elseif ($env:PROCESSOR_ARCHITECTURE) {
            $architecture = [string]$env:PROCESSOR_ARCHITECTURE
        }
    }

    switch -Regex ($architecture.ToUpperInvariant()) {
        '^(AMD64|X64)$' { $architecture = 'X64'; break }
        '^(ARM64|AARCH64)$' { $architecture = 'Arm64'; break }
        '^(X86|I386)$' { $architecture = 'X86'; break }
        default { $architecture = $architecture.ToUpperInvariant() }
    }

    $info = [ordered]@{
        Platform = $platform
        ProductFamily = 'Unknown'
        DisplayVersion = ''
        BuildNumber = 0
        ProductType = ''
        InstallationType = ''
        EditionId = ''
        Architecture = $architecture
        DotNetFrameworkRelease = 0
        MetadataAvailable = ($platform -ne 'Windows')
        MetadataReasonCode = ''
    }

    if ($platform -eq 'Windows') {
        $currentVersionRead = $false
        $productOptionsRead = $false
        try {
            $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $currentVersionRead = $true
            $info.DisplayVersion = [string]$currentVersion.DisplayVersion
            if (-not $info.DisplayVersion) {
                $info.DisplayVersion = [string]$currentVersion.ReleaseId
            }
            $buildValue = $currentVersion.CurrentBuildNumber
            if (-not $buildValue) {
                $buildValue = $currentVersion.CurrentBuild
            }
            $info.BuildNumber = [int]$buildValue
            $info.InstallationType = [string]$currentVersion.InstallationType
            $info.EditionId = [string]$currentVersion.EditionID
        }
        catch {
            $info.DisplayVersion = ''
            $info.BuildNumber = 0
        }

        try {
            $productOptions = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -ErrorAction Stop
            $info.ProductType = [string]$productOptions.ProductType
            $productOptionsRead = $true
        }
        catch {
            $info.ProductType = ''
        }

        try {
            $framework = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop
            $info.DotNetFrameworkRelease = [int]$framework.Release
        }
        catch {
            $info.DotNetFrameworkRelease = 0
        }

        if ($info.ProductType -eq 'WinNT' -and $info.InstallationType -eq 'Client') {
            $info.ProductFamily = 'WindowsClient'
        }
        elseif ($info.ProductType -in @('LanmanNT', 'ServerNT') -and $info.InstallationType -match '^Server') {
            $info.ProductFamily = 'WindowsServer'
        }

        $metadataComplete = $currentVersionRead -and $productOptionsRead -and
            -not [string]::IsNullOrWhiteSpace([string]$info.DisplayVersion) -and
            [int]$info.BuildNumber -gt 0 -and
            -not [string]::IsNullOrWhiteSpace([string]$info.InstallationType) -and
            -not [string]::IsNullOrWhiteSpace([string]$info.EditionId) -and
            -not [string]::IsNullOrWhiteSpace([string]$info.ProductType) -and
            $info.ProductFamily -ne 'Unknown'
        $info.MetadataAvailable = [bool]$metadataComplete
        if (-not $metadataComplete) {
            $info.MetadataReasonCode = 'WINDOWS_METADATA_UNAVAILABLE'
        }
    }

    return [PSCustomObject]$info
}

function Test-InstallerWindowsHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HostInfo,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Manifest,

        [Parameter()]
        [datetime]$Date = [datetime]::Today
    )

    $windows = $Manifest.windowsClient
    if ($HostInfo.Platform -ne 'Windows') {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'OS_NOT_WINDOWS'; Reason = 'This entry point requires Windows.'; Release = $null }
    }
    $metadataProperty = $HostInfo.PSObject.Properties['MetadataAvailable']
    $metadataMissing = [string]::IsNullOrWhiteSpace([string]$HostInfo.DisplayVersion) -or
        [int]$HostInfo.BuildNumber -le 0 -or
        [string]::IsNullOrWhiteSpace([string]$HostInfo.ProductType) -or
        [string]::IsNullOrWhiteSpace([string]$HostInfo.InstallationType) -or
        [string]::IsNullOrWhiteSpace([string]$HostInfo.EditionId)
    if (($null -ne $metadataProperty -and -not [bool]$metadataProperty.Value) -or $metadataMissing) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_METADATA_UNAVAILABLE'; Reason = 'Windows product, release, edition, or build metadata could not be read. The installer cannot verify this host.'; Release = $null }
    }
    if ($HostInfo.ProductType -ne $windows.productType -or $HostInfo.InstallationType -ne $windows.installationType) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_NOT_CLIENT'; Reason = 'Windows Server and non-client installation types are not in the verified support matrix.'; Release = $null }
    }
    $hostArchitecture = ([string]$HostInfo.Architecture).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($hostArchitecture) -or $hostArchitecture -notin @('X64', 'ARM64', 'X86')) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_ARCHITECTURE_UNKNOWN'; Reason = 'The Windows processor architecture could not be determined. The installer cannot select a safe runtime artifact.'; Release = $null }
    }
    if ($HostInfo.Architecture -ne $windows.architecture) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_ARCHITECTURE_UNSUPPORTED'; Reason = "The detected architecture is $($HostInfo.Architecture); this contract supports x64 only."; Release = $null }
    }
    if ($windows.supportedEditionIds -notcontains [string]$HostInfo.EditionId) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_EDITION_UNSUPPORTED'; Reason = "The detected Windows edition '$($HostInfo.EditionId)' is not in the verified Home and Pro matrix."; Release = $null }
    }

    $release = @($windows.releases | Where-Object {
        [string]$_.displayVersion -eq [string]$HostInfo.DisplayVersion -and [int]$_.build -eq [int]$HostInfo.BuildNumber
    } | Select-Object -First 1)
    if ($release.Count -eq 0) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_RELEASE_UNSUPPORTED'; Reason = "Windows release $($HostInfo.DisplayVersion), build $($HostInfo.BuildNumber), is not listed in the supported matrix."; Release = $null }
    }

    $endOfSupport = [datetime]::ParseExact(
        [string]$release[0].consumerEndOfSupport,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    if ($Date.Date -gt $endOfSupport.Date) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_RELEASE_EOL'; Reason = "Windows 11 $($release[0].displayVersion) Home and Pro reached end of servicing on $($endOfSupport.ToString('yyyy-MM-dd')). Update Windows before running the installer."; Release = $release[0] }
    }

    return [PSCustomObject]@{ IsSupported = $true; ReasonCode = 'WINDOWS_HOST_SUPPORTED'; Reason = ''; Release = $release[0] }
}

function Test-InstallerWindows10WinGetBootstrapHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HostInfo
    )

    $metadataProperty = $HostInfo.PSObject.Properties['MetadataAvailable']
    if ($HostInfo.Platform -ne 'Windows' -or
        ($null -ne $metadataProperty -and -not [bool]$metadataProperty.Value) -or
        [string]::IsNullOrWhiteSpace([string]$HostInfo.ProductType) -or
        [string]::IsNullOrWhiteSpace([string]$HostInfo.InstallationType) -or
        [int]$HostInfo.BuildNumber -le 0) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_METADATA_UNAVAILABLE'; Reason = 'Windows host metadata is unavailable for the legacy WinGet bootstrap check.' }
    }
    if ($HostInfo.ProductType -ne 'WinNT' -or $HostInfo.InstallationType -ne 'Client') {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_NOT_CLIENT'; Reason = 'The legacy WinGet bootstrap is limited to Windows client installations.' }
    }
    $hostArchitecture = ([string]$HostInfo.Architecture).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($hostArchitecture) -or $hostArchitecture -notin @('X64', 'ARM64', 'X86')) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_ARCHITECTURE_UNKNOWN'; Reason = 'The host architecture could not be verified for the legacy WinGet bootstrap.' }
    }
    if ($HostInfo.Architecture -ne 'X64') {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS_ARCHITECTURE_UNSUPPORTED'; Reason = 'The legacy WinGet bootstrap only has a verified x64 artifact.' }
    }
    if ([int]$HostInfo.BuildNumber -lt 17763 -or [int]$HostInfo.BuildNumber -ge 22000) {
        return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'WINDOWS10_WINGET_BOOTSTRAP_UNSUPPORTED'; Reason = 'The legacy WinGet bootstrap is limited to Windows 10 client build 17763 or later and below build 22000.' }
    }
    return [PSCustomObject]@{ IsSupported = $true; ReasonCode = 'WINDOWS10_WINGET_BOOTSTRAP_SUPPORTED'; Reason = '' }
}

function Get-InstallerWindowsFormsCapability {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        Add-Type -AssemblyName System.Web -ErrorAction Stop

        $formsType = [System.Windows.Forms.Form]
        $drawingType = [System.Drawing.Bitmap]
        $formsMajor = [int]$formsType.Assembly.GetName().Version.Major
        $drawingMajor = [int]$drawingType.Assembly.GetName().Version.Major
        [void][System.Web.HttpUtility]::HtmlEncode('')
        return [PSCustomObject]@{
            IsAvailable = $true
            FormsMajor = $formsMajor
            DrawingMajor = $drawingMajor
            Reason = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            IsAvailable = $false
            FormsMajor = 0
            DrawingMajor = 0
            Reason = 'The required Windows Forms, System.Drawing, or System.Web assembly could not be loaded.'
        }
    }
}

function Test-InstallerWindowsFormsAssemblies {
    [CmdletBinding()]
    param()

    $capability = Get-InstallerWindowsFormsCapability
    return [bool]$capability.IsAvailable
}

function Test-InstallerPowerShellEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$EngineInfo,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Manifest
    )

    $desktop = $Manifest.engines.windowsPowerShell
    if ([string]$EngineInfo.PSEdition -eq [string]$desktop.edition -and
        [int]$EngineInfo.PSVersion.Major -eq [int]$desktop.major -and
        [int]$EngineInfo.PSVersion.Minor -eq [int]$desktop.minor) {
        return [PSCustomObject]@{ IsSupported = $true; ReasonCode = 'ENGINE_SUPPORTED'; Engine = 'Windows PowerShell 5.1'; Reason = '' }
    }

    $core = $Manifest.engines.powerShellCore
    if ([string]$EngineInfo.PSEdition -eq [string]$core.edition -and
        [string]$EngineInfo.PSVersion.ToString() -eq [string]$core.version) {
        return [PSCustomObject]@{ IsSupported = $true; ReasonCode = 'ENGINE_SUPPORTED'; Engine = "PowerShell Core $($core.version)"; Reason = '' }
    }

    $current = if ($EngineInfo.PSVersion) { [string]$EngineInfo.PSVersion } else { 'unknown' }
    $edition = if ($EngineInfo.PSEdition) { [string]$EngineInfo.PSEdition } else { 'unknown' }
    return [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'ENGINE_UNSUPPORTED'; Engine = ''; Reason = "PowerShell $current ($edition) is outside the supported engine matrix." }
}

function Get-InstallerProcessArchitecture {
    [CmdletBinding()]
    param()

    $architecture = ''
    try {
        $architecture = [string][System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    }
    catch {
        if ([Environment]::Is64BitProcess) {
            $architecture = [string]$env:PROCESSOR_ARCHITECTURE
            if ($architecture -notmatch '(?i)ARM64|AARCH64|AMD64|X64') {
                $architecture = 'X64'
            }
        }
        else {
            $architecture = 'X86'
        }
    }

    switch -Regex ($architecture.ToUpperInvariant()) {
        '^(AMD64|X64)$' { return 'X64' }
        '^(ARM64|AARCH64)$' { return 'Arm64' }
        '^(X86|I386)$' { return 'X86' }
        default { return $architecture.ToUpperInvariant() }
    }
}

function Get-InstallerCompatibilityFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Manifest
    )

    if ($Component -eq 'CrossPlatformCli') {
        $coreVersion = [string]$Manifest.engines.powerShellCore.version
        $recovery = "Install PowerShell Core $coreVersion while it remains within its published support lifecycle. After its end-of-support date, use a PowerShell version listed by a refreshed App Installer compatibility contract."
        return "[ERROR] $Component is not supported: $Reason Supported engine: PowerShell Core $coreVersion on macOS or Linux. Recovery: $recovery Compatibility checks stop before package managers, downloads, elevation, or persistent changes."
    }

    $releaseText = (@($Manifest.windowsClient.releases | ForEach-Object {
        'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build
    }) -join ' or ')
    $engineRecovery = [string]$Manifest.recovery.engine
    if ($Reason -match '(?i)PowerShell Core .+ reached end of support') {
        $engineRecovery = 'The pinned PowerShell Core version has reached end of support. Use Windows PowerShell 5.1 on a supported Windows host or use an App Installer release with a current compatibility contract.'
    }
    $recovery = "$($Manifest.recovery.windows) $engineRecovery"
    if ($Component -eq 'WindowsGui') {
        $recovery += " $($Manifest.recovery.gui)"
    }
    return "[ERROR] $Component is not supported: $Reason Supported Windows: $releaseText, Home or Pro, x64. Supported engines: Windows PowerShell 5.1 or PowerShell $($Manifest.engines.powerShellCore.version). Recovery: $recovery Compatibility checks stop before package managers, downloads, elevation, or persistent changes."
}

function Test-InstallerCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsHost', 'WindowsGui', 'WindowsCli', 'CrossPlatformCli')]
        [string]$Component,

        [Parameter()]
        [PSCustomObject]$HostInfo,

        [Parameter()]
        [PSCustomObject]$Manifest,

        [Parameter()]
        [PSCustomObject]$EngineInfo = $PSVersionTable,

        [Parameter()]
        [datetime]$Date = [datetime]::Today,

        [Parameter()]
        [Nullable[bool]]$WindowsFormsAvailable,

        [Parameter()]
        [int]$WindowsFormsMajor = 0,

        [Parameter()]
        [int]$DrawingMajor = 0,

        [Parameter()]
        [string]$ProcessArchitecture = (Get-InstallerProcessArchitecture),

        [Parameter()]
        [string]$ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState(),

        [Parameter()]
        [scriptblock]$WindowsFormsLoader
    )

    if (-not $Manifest) {
        $Manifest = Get-InstallerCompatibilityManifest
    }
    $manifest = $Manifest
    $hostResult = $null
    if (-not $HostInfo) {
        $HostInfo = Get-InstallerHostInfo
    }
    if ($Component -eq 'WindowsHost' -or $Component -like 'Windows*') {
        $hostResult = Test-InstallerWindowsHost -HostInfo $HostInfo -Manifest $manifest -Date $Date
        if (-not $hostResult.IsSupported) {
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $hostResult.Reason -Manifest $manifest
            return [PSCustomObject]@{
                IsSupported = $false
                Component = $Component
                ReasonCode = [string]$hostResult.ReasonCode
                Reason = $hostResult.Reason
                RecoveryMessage = [string]$manifest.recovery.windows
                Message = ('[{0}] {1}' -f $hostResult.ReasonCode, $message)
                Release = $hostResult.Release
            }
        }
        if ($Component -eq 'WindowsHost') {
            return [PSCustomObject]@{ IsSupported = $true; Component = $Component; ReasonCode = 'WINDOWS_HOST_SUPPORTED'; Reason = ''; RecoveryMessage = ''; Message = ''; Release = $hostResult.Release }
        }
    }
    elseif ($Component -eq 'CrossPlatformCli') {
        if ([string]$HostInfo.Platform -notin @('macOS', 'Linux')) {
            $reason = 'The cross-platform CLI requires macOS or Linux. Windows uses the Windows CLI matrix.'
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
            return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'CLI_PLATFORM_UNSUPPORTED'; Reason = $reason; RecoveryMessage = [string]$manifest.recovery.engine; Message = '[CLI_PLATFORM_UNSUPPORTED] ' + $message; Release = $null }
        }
        if ([string]$EngineInfo.PSEdition -ne [string]$manifest.engines.powerShellCore.edition) {
            $reason = 'The cross-platform CLI requires PowerShell Core.'
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
            return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'ENGINE_UNSUPPORTED'; Reason = $reason; RecoveryMessage = [string]$manifest.recovery.engine; Message = '[ENGINE_UNSUPPORTED] ' + $message; Release = $null }
        }
    }

    $engineResult = Test-InstallerPowerShellEngine -EngineInfo $EngineInfo -Manifest $manifest
    if ($engineResult.IsSupported -and [string]$EngineInfo.PSEdition -eq [string]$manifest.engines.powerShellCore.edition) {
        $engineEndOfSupport = [datetime]::ParseExact(
            [string]$manifest.engines.powerShellCore.endOfSupport,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        if ($Date.Date -gt $engineEndOfSupport.Date) {
            $engineResult.IsSupported = $false
            $engineResult.ReasonCode = 'ENGINE_EOL'
            $engineResult.Reason = "PowerShell Core $($manifest.engines.powerShellCore.version) reached end of support on $($engineEndOfSupport.ToString('yyyy-MM-dd')). Install the currently supported PowerShell release before running the installer."
        }
    }
    if (-not $engineResult.IsSupported) {
        $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $engineResult.Reason -Manifest $manifest
        return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = [string]$engineResult.ReasonCode; Reason = $engineResult.Reason; RecoveryMessage = [string]$manifest.recovery.engine; Message = ('[{0}] {1}' -f $engineResult.ReasonCode, $message); Release = $null }
    }

    if ($Component -eq 'WindowsGui') {
        if ([string]$ProcessArchitecture -ne [string]$manifest.windowsClient.architecture) {
            $reason = "The PowerShell process architecture is $ProcessArchitecture; x64 is required for the GUI."
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
            return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'GUI_PROCESS_ARCHITECTURE_UNSUPPORTED'; Reason = $reason; RecoveryMessage = 'Use the supported x64 PowerShell executable on a supported Windows client.'; Message = '[GUI_PROCESS_ARCHITECTURE_UNSUPPORTED] ' + $message; Release = $hostResult.Release }
        }

        if ($ApartmentState -ne 'STA') {
            $reason = "The current PowerShell thread uses $ApartmentState; Windows Forms requires an STA UI thread. Restart through the supported launcher or use the CLI."
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
            return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'GUI_STA_REQUIRED'; Reason = $reason; RecoveryMessage = 'Start the GUI through the launcher, which opens the supported PowerShell process with -STA, or use the CLI.'; Message = '[GUI_STA_REQUIRED] ' + $message; Release = $hostResult.Release }
        }

        $isCore = [string]$EngineInfo.PSEdition -eq [string]$manifest.engines.powerShellCore.edition
        if (-not $isCore) {
            $requiredRelease = [int]$manifest.runtimePrerequisites.windowsPowerShellGui.minimumRelease
            $actualRelease = [int]$HostInfo.DotNetFrameworkRelease
            if ($actualRelease -lt $requiredRelease) {
                $minimumVersion = [string]$manifest.runtimePrerequisites.windowsPowerShellGui.minimumVersion
                $reason = ".NET Framework $minimumVersion or later is required for the Windows PowerShell GUI. Detected release value: $actualRelease."
                $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
                return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'GUI_DOTNET_FRAMEWORK_BELOW_MINIMUM'; Reason = $reason; RecoveryMessage = 'Update .NET Framework using an approved Windows servicing method, then retry, or use the CLI.'; Message = '[GUI_DOTNET_FRAMEWORK_BELOW_MINIMUM] ' + $message; Release = $hostResult.Release }
            }
        }

        $formsCapability = $null
        if ($null -ne $WindowsFormsAvailable) {
            $formsCapability = [PSCustomObject]@{
                IsAvailable = [bool]$WindowsFormsAvailable
                FormsMajor = $WindowsFormsMajor
                DrawingMajor = $DrawingMajor
                Reason = ''
            }
        }
        elseif ($WindowsFormsLoader) {
            $formsCapability = & $WindowsFormsLoader
        }
        else {
            $formsCapability = Get-InstallerWindowsFormsCapability
        }

        if ($null -eq $formsCapability -or -not [bool]$formsCapability.IsAvailable) {
            $reason = if ($null -ne $formsCapability -and $formsCapability.Reason) { [string]$formsCapability.Reason } else { 'The required Windows Forms, System.Drawing, or System.Web assembly could not be loaded.' }
            $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
            return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'GUI_ASSEMBLY_LOAD_FAILED'; Reason = $reason; RecoveryMessage = [string]$manifest.recovery.gui; Message = '[GUI_ASSEMBLY_LOAD_FAILED] ' + $message; Release = $hostResult.Release }
        }

        if ($isCore) {
            $requiredMajor = [int]$manifest.runtimePrerequisites.powerShellCoreGui.runtimeMajor
            if ([int]$formsCapability.FormsMajor -ne $requiredMajor -or [int]$formsCapability.DrawingMajor -ne $requiredMajor) {
                $reason = "The loaded Windows Forms and System.Drawing assemblies do not match Windows Desktop runtime $requiredMajor."
                $message = Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $manifest
                return [PSCustomObject]@{ IsSupported = $false; Component = $Component; ReasonCode = 'GUI_DESKTOP_RUNTIME_VERSION_UNSUPPORTED'; Reason = $reason; RecoveryMessage = [string]$manifest.recovery.gui; Message = '[GUI_DESKTOP_RUNTIME_VERSION_UNSUPPORTED] ' + $message; Release = $hostResult.Release }
            }
        }
    }

    return [PSCustomObject]@{ IsSupported = $true; Component = $Component; ReasonCode = 'COMPATIBILITY_SUPPORTED'; Reason = ''; RecoveryMessage = ''; Message = ''; Release = if ($hostResult) { $hostResult.Release } else { $null } }
}

function Test-InstallerGuiCapability {
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$HostInfo,

        [Parameter()]
        [PSCustomObject]$EngineInfo = $PSVersionTable,

        [Parameter()]
        [datetime]$Date = [datetime]::Today,

        [Parameter()]
        [Nullable[bool]]$WindowsFormsAvailable,

        [Parameter()]
        [int]$WindowsFormsMajor = 0,

        [Parameter()]
        [int]$DrawingMajor = 0,

        [Parameter()]
        [string]$ProcessArchitecture = (Get-InstallerProcessArchitecture),

        [Parameter()]
        [string]$ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState(),

        [Parameter()]
        [scriptblock]$WindowsFormsLoader
    )

    return (Test-InstallerCompatibility -Component WindowsGui -HostInfo $HostInfo -EngineInfo $EngineInfo -Date $Date -WindowsFormsAvailable $WindowsFormsAvailable -WindowsFormsMajor $WindowsFormsMajor -DrawingMajor $DrawingMajor -ProcessArchitecture $ProcessArchitecture -ApartmentState $ApartmentState -WindowsFormsLoader $WindowsFormsLoader)
}

function Resolve-InstallerGuiStartup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GuiCapability,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CliCapability,

        [Parameter()]
        [switch]$ForceCLI
    )

    if ($ForceCLI) {
        if (-not $CliCapability.IsSupported) {
            return [PSCustomObject]@{ Action = 'Failure'; ReasonCode = [string]$CliCapability.ReasonCode; Reason = [string]$CliCapability.Reason; Message = [string]$CliCapability.Message }
        }
        return [PSCustomObject]@{ Action = 'RunCLI'; ReasonCode = 'CLI_FORCED'; Reason = 'CLI mode was requested.'; Message = '' }
    }

    if ($GuiCapability.IsSupported) {
        return [PSCustomObject]@{ Action = 'ContinueGUI'; ReasonCode = 'GUI_CAPABILITIES_VALID'; Reason = ''; Message = '' }
    }

    if (-not $CliCapability.IsSupported) {
        return [PSCustomObject]@{ Action = 'Failure'; ReasonCode = [string]$CliCapability.ReasonCode; Reason = [string]$CliCapability.Reason; Message = [string]$CliCapability.Message }
    }

    return [PSCustomObject]@{ Action = 'RunCLI'; ReasonCode = [string]$GuiCapability.ReasonCode; Reason = [string]$GuiCapability.Reason; Message = [string]$GuiCapability.Message }
}

function Invoke-InstallerCliFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$StartupDecision,

        [Parameter(Mandatory = $true)]
        [string]$CliScriptPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [scriptblock]$Runner
    )

    if ($StartupDecision.Action -ne 'RunCLI') {
        return [PSCustomObject]@{ Action = [string]$StartupDecision.Action; ExitCode = $null; RunCount = 0; Reason = [string]$StartupDecision.Reason }
    }

    try {
        $runResult = & $Runner $CliScriptPath $Arguments
        $exitCode = if ($null -ne $runResult.PSObject.Properties['ExitCode']) { [int]$runResult.ExitCode } else { [int]$runResult }
        return [PSCustomObject]@{ Action = 'Exit'; ExitCode = $exitCode; RunCount = 1; Reason = '' }
    }
    catch {
        return [PSCustomObject]@{ Action = 'Failure'; ExitCode = 1; RunCount = 1; Reason = 'The CLI fallback could not be started.' }
    }
}

function Get-InstallerHostPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsHost', 'WindowsGui', 'WindowsCli', 'CrossPlatformCli')]
        [string]$Component,

        [Parameter()]
        [PSCustomObject]$HostInfo,

        [Parameter()]
        [PSCustomObject]$EngineInfo = $PSVersionTable,

        [Parameter()]
        [datetime]$Date = [datetime]::Today,

        [Parameter()]
        [Nullable[bool]]$WindowsFormsAvailable,

        [Parameter()]
        [int]$WindowsFormsMajor = 0,

        [Parameter()]
        [int]$DrawingMajor = 0,

        [Parameter()]
        [string]$ProcessArchitecture = (Get-InstallerProcessArchitecture),

        [Parameter()]
        [string]$ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState(),

        [Parameter()]
        [scriptblock]$WindowsFormsLoader,

        [Parameter()]
        [scriptblock]$WingetAvailabilityProbe,

        [Parameter()]
        [string]$RuntimeArtifactArchitecture,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    if (-not $Manifest) {
        $Manifest = Get-InstallerCompatibilityManifest
    }
    if (-not $HostInfo) {
        $HostInfo = Get-InstallerHostInfo
    }
    $isWindowsComponent = $Component -like 'Windows*'

    $compatibilityParameters = @{
        Component = $Component
        HostInfo = $HostInfo
        EngineInfo = $EngineInfo
        Date = $Date
        Manifest = $Manifest
        ProcessArchitecture = $ProcessArchitecture
        ApartmentState = $ApartmentState
    }
    if ($null -ne $WindowsFormsAvailable) {
        $compatibilityParameters.WindowsFormsAvailable = $WindowsFormsAvailable
    }
    if ($PSBoundParameters.ContainsKey('WindowsFormsMajor')) {
        $compatibilityParameters.WindowsFormsMajor = $WindowsFormsMajor
    }
    if ($PSBoundParameters.ContainsKey('DrawingMajor')) {
        $compatibilityParameters.DrawingMajor = $DrawingMajor
    }
    if ($WindowsFormsLoader) {
        $compatibilityParameters.WindowsFormsLoader = $WindowsFormsLoader
    }

    $capability = Test-InstallerCompatibility @compatibilityParameters
    $packageArchitecture = $null
    $artifactArchitecture = $null
    if ($isWindowsComponent) {
        $artifactArchitecture = if (-not [string]::IsNullOrWhiteSpace($RuntimeArtifactArchitecture)) {
            [string]$RuntimeArtifactArchitecture
        }
        else {
            [string]$Manifest.windowsExecutable.runtimeDiscovery.provisioning.architecture
        }
    }
    $reasonCode = [string]$capability.ReasonCode
    $reason = [string]$capability.Reason
    $message = [string]$capability.Message
    $isSupported = [bool]$capability.IsSupported
    $recoveryOption = if ($isSupported) {
        ''
    }
    elseif ($Component -eq 'CrossPlatformCli') {
        'Use PowerShell Core {0} on an operating system supported by that PowerShell release.' -f $Manifest.engines.powerShellCore.version
    }
    else {
        [string]$Manifest.recovery.windows
    }

    if ($isSupported -and $isWindowsComponent) {
        $hostArchitecture = ([string]$HostInfo.Architecture).ToUpperInvariant()
        $artifactArchitecture = $artifactArchitecture.ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($hostArchitecture) -or $hostArchitecture -notin @('X64', 'ARM64', 'X86')) {
            $isSupported = $false
            $reasonCode = 'WINDOWS_ARCHITECTURE_UNKNOWN'
            $reason = 'The Windows processor architecture could not be determined. The installer cannot select a safe runtime artifact.'
        }
        elseif ([string]::IsNullOrWhiteSpace($artifactArchitecture) -or $artifactArchitecture -ne $hostArchitecture) {
            $isSupported = $false
            $reasonCode = 'PACKAGE_ARCHITECTURE_MISMATCH'
            $reason = "The pinned runtime artifact architecture '$artifactArchitecture' does not match host architecture '$hostArchitecture'. No runtime artifact was selected."
        }
        else {
            $packageArchitecture = $artifactArchitecture
        }

        if (-not $isSupported -and $reasonCode -eq 'PACKAGE_ARCHITECTURE_MISMATCH') {
            $message = '[PACKAGE_ARCHITECTURE_MISMATCH] ' + (Get-InstallerCompatibilityFailureMessage -Component $Component -Reason $reason -Manifest $Manifest)
            $recoveryOption = [string]$Manifest.recovery.windows
        }
    }

    if ($isWindowsComponent) {
        $releaseRequirement = @($Manifest.windowsClient.releases | ForEach-Object {
            'Windows 11 {0} build {1}' -f $_.displayVersion, $_.build
        }) -join ' or '
        $hostRequirement = '{0}, Home or Pro, x64.' -f $releaseRequirement
    }
    else {
        $hostRequirement = '{0} on an operating system supported by that PowerShell release.' -f $Manifest.nonWindowsCli.engine
    }
    $packageManagerStatus = 'NotApplicable'
    $wingetAvailable = $null
    $wingetRequired = $false
    if ($isWindowsComponent) {
        $packageManagerStatus = 'NotChecked'
        if ($isSupported) {
            try {
                if ($WingetAvailabilityProbe) {
                    $wingetAvailable = [bool](& $WingetAvailabilityProbe)
                }
                else {
                    $wingetCommand = Get-Command -Name 'winget' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                    $wingetAvailable = ($null -ne $wingetCommand)
                }
                $packageManagerStatus = if ($wingetAvailable) { 'Available' } else { 'Unavailable' }
            }
            catch {
                $wingetAvailable = $null
                $packageManagerStatus = 'Unknown'
            }
        }
    }

    return [PSCustomObject]@{
        IsSupported = $isSupported
        Component = $Component
        ReasonCode = $reasonCode
        Reason = $reason
        Message = $message
        Requirement = $hostRequirement
        RecoveryOption = $recoveryOption
        ProductFamily = [string]$HostInfo.ProductFamily
        DisplayVersion = [string]$HostInfo.DisplayVersion
        BuildNumber = [int]$HostInfo.BuildNumber
        EditionId = [string]$HostInfo.EditionId
        Architecture = [string]$HostInfo.Architecture
        MetadataAvailable = [bool]$HostInfo.MetadataAvailable
        RuntimeRequirements = [PSCustomObject]@{
            Cli = [PSCustomObject]@{
                WindowsPowerShell = '{0}.{1}' -f $Manifest.engines.windowsPowerShell.major, $Manifest.engines.windowsPowerShell.minor
                PowerShellCore = [string]$Manifest.engines.powerShellCore.version
                AdditionalRuntime = [string]$Manifest.runtimePrerequisites.cli
            }
            Gui = [PSCustomObject]@{
                WindowsPowerShell = $Manifest.runtimePrerequisites.windowsPowerShellGui
                PowerShellCore = $Manifest.runtimePrerequisites.powerShellCoreGui
            }
        }
        WinGet = [PSCustomObject]@{
            Available = $wingetAvailable
            Status = $packageManagerStatus
            RequiredForHostSupport = $wingetRequired
        }
        SelectedPackageArchitecture = $packageArchitecture
        RuntimeArtifactArchitecture = $artifactArchitecture
        Capability = $capability
        Release = $capability.Release
    }
}

Export-ModuleMember -Function Get-InstallerCompatibilityManifest, Get-InstallerHostInfo, Get-InstallerProcessArchitecture, Test-InstallerCompatibility, Get-InstallerHostPreflight, Test-InstallerWindows10WinGetBootstrapHost, Test-InstallerGuiCapability, Resolve-InstallerGuiStartup, Invoke-InstallerCliFallback, Test-InstallerWindowsFormsAssemblies, Get-InstallerWindowsFormsCapability, Get-InstallerCompatibilityFailureMessage, Test-InstallerPowerShellEngine
