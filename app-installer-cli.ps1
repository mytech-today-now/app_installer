<#
.SYNOPSIS
    Cross-platform CLI application installer with multi-select capabilities.

.DESCRIPTION
    This script provides a comprehensive command-line interface for installing and managing
    multiple applications across Windows, macOS, and Linux. Features include:

    CROSS-PLATFORM FEATURES:
    - Works on supported Windows clients with Windows PowerShell 5.1 or PowerShell Core 7.6.7
    - Works on supported macOS and Linux platforms with PowerShell Core 7.6.7
    - Automatic package manager detection (winget, brew, apt, dnf, pacman, snap)
    - Platform-aware application filtering
    - Cross-platform path handling

    INTERACTIVE FEATURES:
    - Interactive menu with installation status display
    - Multi-select capability (e.g., "1,3,5-10" to select multiple apps)
    - Category-based selection (e.g., "C:Browsers" to select all browsers)
    - Range selection (e.g., "1-5,10-15" to select ranges)
    - Version detection for installed applications (where supported)
    - Selective installation (individual apps, all apps, or only missing apps)
    - Real-time progress tracking with ETA during batch installations

    PLATFORM-SPECIFIC:
    - Windows: Uses winget, centralized logging to %USERPROFILE%\myTech.Today\logs\
    - macOS: Uses Homebrew, logging to ~/.mytech-today/logs/
    - Linux: Uses apt/dnf/pacman/snap, logging to ~/.mytech-today/logs/

    Supports 271+ applications with cross-platform package mappings

.PARAMETER Action
    The action to perform. Valid values: Menu, InstallAll, InstallMissing, Status,
    InstallProfile, EnableMonthlyUpdates, DisableMonthlyUpdates
    Default: Menu (interactive mode)

.PARAMETER AppName
    Specific application name to install (when not using menu)

.PARAMETER Profile
    Path to a JSON profile file to import and install non-interactively.

.EXAMPLE
    .\install.ps1
    Launches the interactive menu interface

.EXAMPLE
    .\install.ps1 -Action InstallAll
    Installs all applications without prompting

.EXAMPLE
    .\install.ps1 -Action InstallMissing
    Installs only applications that are not currently installed

.EXAMPLE
    .\install.ps1 -Action EnableMonthlyUpdates
    Selects package IDs and asks before enabling monthly updates.

.EXAMPLE
    .\install.ps1 -Action DisableMonthlyUpdates
    Removes only the application-owned monthly update task after confirmation.

.EXAMPLE
    .\install.ps1 -AppName "Chrome"
    Installs only Google Chrome

.EXAMPLE
    .\install.ps1 -Profile "$env:USERPROFILE\myTech.Today\AppInstaller\profiles\profile-home-office.json"
    Imports the given profile and installs all applications defined in that profile.

.EXAMPLE
    Interactive menu: Enter "1,3,5"
    Installs applications #1, #3, and #5

.EXAMPLE
    Interactive menu: Enter "1-10"
    Installs applications #1 through #10

.EXAMPLE
    Interactive menu: Enter "C:Browsers"
    Installs all applications in the Browsers category

.EXAMPLE
    Interactive menu: Enter "1-5,10,15-20"
    Installs applications #1-5, #10, and #15-20

.NOTES
    File Name      : install.ps1
    Author         : myTech.Today
    Prerequisite   : See compatibility.json for the authoritative support contract
                     Windows: Windows 11 25H2 or 26H2, Home or Pro, x64; Windows PowerShell 5.1 or PowerShell Core 7.6.7
                     macOS/Linux: PowerShell Core 7.6.7 on a supported platform
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Version        : 2.0.2

.LINK
    https://github.com/mytech-today-now/PowerShellScripts/app_installer

.EXAMPLE
    .\install.ps1
    Launches interactive menu (works on all platforms)

.EXAMPLE
    .\install.ps1 -Action InstallAll
    Installs all available applications for current platform

.EXAMPLE
    .\install.ps1 -Action InstallMissing
    Installs only missing applications

.EXAMPLE
    .\install.ps1 -Profile ./profiles/profile-developer.json
    Installs applications from a profile
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Menu', 'InstallAll', 'InstallMissing', 'Status', 'InstallProfile', 'EnableMonthlyUpdates', 'DisableMonthlyUpdates')]
    [string]$Action = 'Menu',

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [switch]$ValidatePayloadOnly
)

#Requires -Version 5.1
$script:ScriptVersion = '2.0.2'

$script:PayloadModulePath = Join-Path $PSScriptRoot 'modules\InstallerPayload.psm1'
if (-not (Test-Path -LiteralPath $script:PayloadModulePath -PathType Leaf)) {
    [Console]::Error.WriteLine('[ERROR] Required payload validator module is missing. No installer action was started.')
    exit 2
}
try {
    Import-Module -Name $script:PayloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $script:PayloadValidation = Test-AppInstallerPayload -RootPath $PSScriptRoot
}
catch {
    [Console]::Error.WriteLine("[ERROR] Required App Installer payload validation failed: $($_.Exception.Message)")
    exit 2
}
if ($ValidatePayloadOnly) {
    Write-Output ('Payload valid: mode={0}; version={1}; files={2}; root={3}' -f $script:PayloadValidation.Mode, $script:PayloadValidation.Version, $script:PayloadValidation.FileCount, $script:PayloadValidation.RootPath)
    return
}

$script:CompatibilityModulePath = Join-Path $PSScriptRoot 'modules\InstallerCompatibility.psm1'
if (-not (Test-Path -LiteralPath $script:CompatibilityModulePath -PathType Leaf)) {
    Write-Host '[ERROR] The compatibility contract module is missing. No setup or package operation was started.' -ForegroundColor Red
    exit 1
}
try {
    Import-Module -Name $script:CompatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "[ERROR] The compatibility contract could not be loaded: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '[INFO] No setup or package operation was started.' -ForegroundColor Yellow
    exit 1
}

$script:CompatibilityHostInfo = Get-InstallerHostInfo
$cliComponent = if ($script:CompatibilityHostInfo.Platform -eq 'Windows') { 'WindowsCli' } else { 'CrossPlatformCli' }
if ($cliComponent -eq 'WindowsCli') {
    $runtimeModulePath = Join-Path $PSScriptRoot 'modules\InstallerRuntimeDiscovery.psm1'
    $prerequisiteModulePath = Join-Path $PSScriptRoot 'modules\InstallerPrerequisitePlan.psm1'
    if (-not (Test-Path -LiteralPath $runtimeModulePath -PathType Leaf) -or -not (Test-Path -LiteralPath $prerequisiteModulePath -PathType Leaf)) {
        Write-Host '[ERROR] The shared PowerShell runtime discovery module is missing. No installer action was started.' -ForegroundColor Red
        exit 1
    }
    try {
        Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
        Import-Module -Name $prerequisiteModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
        if ($WhatIfPreference) {
            Write-Host '[INFO] WhatIf keeps the CLI preview in this process and skips runtime probes and launcher handoff.' -ForegroundColor Cyan
        }
        else {
            $runtimeArguments = ConvertTo-InstallerRuntimeArgumentArray -BoundParameters $PSBoundParameters -RemainingArguments $args
            $runtimeFlow = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $PSCommandPath -ScriptArguments $runtimeArguments
        }
    }
    catch {
        Write-Host '[ERROR] PowerShell runtime preflight failed before installer actions. Local paths and environment details were withheld.' -ForegroundColor Red
        exit 1
    }

    if (-not $WhatIfPreference) {
        if ($runtimeFlow.Status -eq 'PlanOnly') {
            Write-Host '[INFO] WhatIf completed. No runtime download, installation, elevation, or application package action was started.' -ForegroundColor Cyan
            exit 0
        }
        if ($runtimeFlow.Status -ne 'Started') {
            Write-Host "[ERROR] No compatible PowerShell engine could start the CLI: $($runtimeFlow.Reason)" -ForegroundColor Red
            exit 1
        }
        $runtimeDecision = $runtimeFlow.RuntimeDecision
        if ($runtimeDecision.Action -eq 'Exit') {
            exit $runtimeDecision.ExitCode
        }
    }
}

$cliCompatibility = Get-InstallerHostPreflight -Component $cliComponent -HostInfo $script:CompatibilityHostInfo
if (-not $cliCompatibility.IsSupported) {
    Write-Host $cliCompatibility.Message -ForegroundColor Red
    exit 1
}

#region Safe-TestPath Helper

function Safe-TestPath {
    <#
    .SYNOPSIS
        Wraps Safe-TestPath in a try/catch to suppress Access Denied errors.
    .DESCRIPTION
        Some paths (e.g. registry hives, protected directories) throw
        UnauthorizedAccessException. This helper returns $false instead of
        terminating or displaying a red error.
    .PARAMETER Path
        The path to test.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )
    try {
        return (Test-Path $Path -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function New-InstallerActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Preview', 'Skipped')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [PSCustomObject]@{
        Status  = $Status
        Success = $false
        Message = $Message
    }
}

function Get-InstallerActionStatus {
    [CmdletBinding()]
    param([AllowNull()]$Result)

    if ($null -ne $Result -and $Result.PSObject.Properties['Status']) {
        return [string]$Result.Status
    }

    if ($Result) {
        return 'Completed'
    }

    return 'Failed'
}

function Test-InstallerShouldProcess {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    try {
        return $PSCmdlet.ShouldProcess($Target, $Action)
    }
    catch {
        Write-Host "[SKIPPED] Could not obtain confirmation. $Action was not performed." -ForegroundColor Yellow
        return $false
    }
}

#endregion Safe-TestPath Helper

# NOTE: Admin/sudo is recommended but not strictly required
# Some package managers can install to user directories without elevation

#region Platform Detection and Module Loading

Write-Host "`n=== myTech.Today Application Installer - CLI Mode ===" -ForegroundColor Cyan
Write-Host "Version: $script:ScriptVersion" -ForegroundColor Gray
Write-Host ""

# Import platform detection module
$platformDetectPath = Join-Path $PSScriptRoot "platform-detect.ps1"
if (Safe-TestPath $platformDetectPath) {
    Write-Verbose "Loading platform detection module..."
    . $platformDetectPath
    Write-Host "[OK] Platform: $Platform | Package Manager: $PackageManager" -ForegroundColor Green
}
else {
    Write-Warning "Platform detection module not found at: $platformDetectPath"
    Write-Warning "Some features may not work correctly"

    # Fallback platform detection
    if ($null -eq $IsWindows) {
        $Platform = "Windows"
    }
    elseif ($IsWindows) {
        $Platform = "Windows"
    }
    elseif ($IsMacOS) {
        $Platform = "macOS"
    }
    elseif ($IsLinux) {
        $Platform = "Linux"
    }
    else {
        $Platform = "Unknown"
    }
}

# Import core module if available
$coreModulePath = Join-Path $PSScriptRoot "modules\AppInstallerCore.psm1"
if (Safe-TestPath $coreModulePath) {
    Write-Verbose "Loading core installer module..."
    Import-Module $coreModulePath -Force -Verbose:$false
    $script:CoreModuleLoaded = $true
}
else {
    Write-Verbose "Core module not found at: $coreModulePath"
    $script:CoreModuleLoaded = $false
}

# PowerShell 7+ Version Check - myTech.Today standard
$script:PS7ContinueOnPS51 = $true  # Allow running on PS 5.1 with warning
$script:PS7Silent = $false
#endregion Platform Detection and Module Loading

#region Load Generic Logging Module

# Logging is implemented in this entrypoint and does not require a startup download.
$script:LoggingModuleLoaded = $false
$script:StartupHelperFallbackRequired = $true
$script:StartupHelperFallbackMessage = 'A required optional helper could not be verified. Installation remains available with built-in behavior.'

#endregion

# Script variables - cross-platform paths
$script:OriginalScriptPath = [System.IO.Path]::GetFullPath($PSScriptRoot)
$script:ResourceRoot = $script:OriginalScriptPath

# Use core module functions if available, otherwise use fallback
if ($script:CoreModuleLoaded) {
    $script:SystemInstallPath = Get-InstallerBasePath
    $script:CentralLogPath = Get-InstallerLogPath
}
else {
    # Fallback: Cross-platform path handling
    if ($null -eq $IsWindows -or $IsWindows) {
        # Windows
        $script:SystemInstallPath = Join-Path $env:USERPROFILE "myTech.Today\AppInstaller"
        $script:CentralLogPath = Join-Path $env:USERPROFILE "myTech.Today\logs\"
    }
    else {
        # macOS/Linux
        $script:SystemInstallPath = Join-Path $HOME ".mytech-today/app-installer"
        $script:CentralLogPath = Join-Path $HOME ".mytech-today/logs/"
    }
}

$script:ScriptPath = $script:SystemInstallPath  # Will be updated after copy
$script:LogPath = $null
$script:AppsPath = Join-Path $script:ScriptPath "apps"
$script:ProfilesPath = Join-Path $script:ScriptPath "profiles"
$script:OOShutUp10TrustModulePath = Join-Path $PSScriptRoot 'modules\OOShutUp10Trust.psm1'

Write-Verbose "Install Path: $script:SystemInstallPath"
Write-Verbose "Log Path: $script:CentralLogPath"

#region Self-Installation to System Location

function Copy-ScriptToSystemLocation {
    [CmdletBinding()]
    param()

    try {
        $result = Copy-AppInstallerPayload -SourceRoot $script:OriginalScriptPath -DestinationRoot $script:SystemInstallPath
        Write-Host ("    [OK] Complete payload {0}: {1} ({2} files, version {3})" -f $result.Status, $result.Path, $result.FileCount, $result.Version) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host ("    [X] Complete payload installation failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

# Copy script to system location before ordinary runs. A dry run leaves the
# user's installed copy and supporting files untouched.
if ($WhatIfPreference) {
    $copiedToSystem = $false
    $script:ScriptPath = $script:OriginalScriptPath
    $script:AppsPath = Join-Path $script:ScriptPath 'apps'
    $script:ProfilesPath = Join-Path $script:ScriptPath 'profiles'
    Write-Host '[PREVIEW] Skipping installer self-copy; no files were changed.' -ForegroundColor Cyan
}
else {
    $copiedToSystem = Copy-ScriptToSystemLocation
    if (-not $copiedToSystem) {
        throw 'The complete application payload could not be installed. No catalog or application action was started.'
    }
}

# Update script paths to use system location
if ($copiedToSystem) {
    $script:ScriptPath = $script:SystemInstallPath
    $script:AppsPath = Join-Path $script:ScriptPath "apps"
    $script:ProfilesPath = Join-Path $script:ScriptPath "profiles"
}
$script:ResourceRoot = $script:ScriptPath
$script:OOShutUp10TrustModulePath = Join-Path $script:ResourceRoot 'modules\OOShutUp10Trust.psm1'
if ($copiedToSystem -and $script:CoreModuleLoaded) {
    $installedCoreModulePath = Join-Path $script:ResourceRoot 'modules\AppInstallerCore.psm1'
    Import-Module -Name $installedCoreModulePath -Force -Verbose:$false -ErrorAction Stop | Out-Null
}

#endregion Self-Installation to System Location

#region Application Registry Loading

# Load application registry - cross-platform aware
Write-Host "[INFO] Loading application registry..." -ForegroundColor Cyan

if ($script:CoreModuleLoaded) {
    # Use core module to load from apps-manifest.json
    Write-Verbose "Loading application registry from core module..."
    try {
        $allApplications = Get-ApplicationRegistry -Verbose:$VerbosePreference

        # Filter by current platform
        $script:Applications = @(Select-ApplicationsByPlatform -Applications $allApplications -CurrentPlatform $Platform)

        Write-Host "[OK] Loaded $($script:Applications.Count) applications for $Platform" -ForegroundColor Green
    }
    catch {
        throw "The complete application catalog could not be loaded. No partial catalog was used. $($_.Exception.Message)"
    }
}
else {
    throw 'The required AppInstallerCore module is not loaded. No partial catalog was used.'
}

#endregion Application Registry Loading

#region Helper Functions

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes the centralized logging system.
    #>
    [CmdletBinding()]
    param()

    try {
        # Create central log directory if it doesn't exist
        if (-not (Safe-TestPath $script:CentralLogPath)) {
            New-Item -Path $script:CentralLogPath -ItemType Directory -Force | Out-Null
        }

        # Use script-specific log file in central location
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        $logFileName = "$scriptName-$(Get-Date -Format 'yyyy-MM').md"
        $script:LogPath = Join-Path $script:CentralLogPath $logFileName

        # Initialize markdown log file if it doesn't exist
        if (-not (Safe-TestPath $script:LogPath)) {
            $logHeader = @"
# $scriptName Log

**Script Version:** $script:ScriptVersion
**Log Started:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Computer:** $env:COMPUTERNAME
**User:** $env:USERNAME

---

## Activity Log

| Timestamp | Level | Message |
|-----------|-------|---------|

"@
            Set-Content -Path $script:LogPath -Value $logHeader -Force
        }

        Write-Log "Logging initialized" -Level INFO
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the log file and console in markdown format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        # Create markdown-formatted log entry
        $icon = switch ($Level) {
            'INFO'    { '[i]' }
            'WARNING' { '[!]' }
            'ERROR'   { '[X]' }
            'SUCCESS' { '[OK]' }
        }

        $logEntry = "| $timestamp | $icon **$Level** | $Message |"

        # Write to log file in markdown table format
        if (-not $WhatIfPreference -and $script:LogPath -and (Safe-TestPath $script:LogPath)) {
            Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
        }

        # Write to console
        switch ($Level) {
            'INFO'    { Write-Host "INFO: $Message" -ForegroundColor Cyan }
            'WARNING' { Write-Warning $Message }
            'ERROR'   { Write-Host "ERROR: $Message" -ForegroundColor Red }
            'SUCCESS' { Write-Host "SUCCESS: $Message" -ForegroundColor Green }
        }
    }
    catch {
        Write-Warning "Failed to write log: $_"
    }
}

function Read-KeySafe {
    <#
    .SYNOPSIS
        Safely reads a key press, handling environments where ReadKey is not supported.

    .DESCRIPTION
        Attempts to read a key using $Host.UI.RawUI.ReadKey().
        If that fails (e.g., in PowerShell ISE or non-interactive sessions),
        falls back to Read-Host or simply returns without waiting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prompt = "Press any key to continue..."
    )

    try {
        if ($Host.UI.RawUI) {
            Write-Host "`n$Prompt" -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        else {
            # Fallback for environments without RawUI
            Read-Host "`n$Prompt (Press Enter)"
        }
    }
    catch {
        # If ReadKey is not implemented, use Read-Host as fallback
        try {
            Read-Host "`n$Prompt (Press Enter)"
        }
        catch {
            # If even Read-Host fails, just continue
            Write-Host "`n$Prompt" -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }
}

function Install-WingetOnWindows10 {
    <#
    .SYNOPSIS
        Installs winget (Windows Package Manager) on Windows 10 systems.

    .DESCRIPTION
        Downloads and installs the latest version of winget from Microsoft's official GitHub repository.
        Also installs required dependencies (VCLibs and UI.Xaml).
        Only runs on Windows 10 systems.
    #>
    [CmdletBinding()]
    param()

    $bootstrapHostInfo = $script:CompatibilityHostInfo
    if (-not $bootstrapHostInfo) {
        $bootstrapHostInfo = Get-InstallerHostInfo
    }
    $bootstrapCapability = Test-InstallerWindows10WinGetBootstrapHost -HostInfo $bootstrapHostInfo
    if (-not $bootstrapCapability.IsSupported) {
        Write-Log "WinGet bootstrap not eligible ($($bootstrapCapability.ReasonCode)); no bootstrap was started" -Level INFO
        return $false
    }

    Write-Host "`n[i] Detected Windows 10. Verifying WinGet setup requirements..." -ForegroundColor Cyan
    Write-Log "Verifying WinGet bootstrap requirements on Windows 10" -Level INFO

    try {
        $bootstrapModulePath = Join-Path $script:ResourceRoot 'modules\WingetBootstrap.psm1'
        if (-not (Safe-TestPath $bootstrapModulePath)) {
            throw 'Bootstrap verifier module is unavailable.'
        }
        Import-Module -Name $bootstrapModulePath -Force -Verbose:$false -ErrorAction Stop | Out-Null
        $bootstrapResult = WingetBootstrap\Invoke-WingetBootstrap -ErrorAction Stop
    }
    catch {
        Write-Log "WinGet setup could not be verified (BootstrapVerifierUnavailable)" -Level ERROR
        Write-Host "  [X] The installer could not verify WinGet setup and made no package changes. Install App Installer manually from Microsoft Store, then retry." -ForegroundColor Red
        return $false
    }

    if ($bootstrapResult.Success -eq $true -and $bootstrapResult.Status -eq 'Complete') {
        Write-Host "  [OK] WinGet installed and detected successfully." -ForegroundColor Green
        Write-Log "WinGet installed and detected successfully on Windows 10" -Level SUCCESS
        return $true
    }

    Write-Log "WinGet setup could not be verified ($($bootstrapResult.ErrorCode)); status $($bootstrapResult.Status)" -Level ERROR
    if ($bootstrapResult.ChangesStarted -eq $true) {
        Write-Host "  [X] The installer could not verify WinGet setup. Package changes were attempted and may have partially completed. Review App Installer and its dependencies before retrying; install App Installer manually from Microsoft Store if needed." -ForegroundColor Red
    }
    else {
        Write-Host "  [X] The installer could not verify WinGet setup and made no package changes. Install App Installer manually from Microsoft Store, then retry." -ForegroundColor Red
    }
    if ($bootstrapResult.CleanupSucceeded -eq $false) {
        Write-Host "  [!] Temporary bootstrap files could not be removed." -ForegroundColor Yellow
    }
    return $false
}

function Test-WingetAvailable {
    <#
    .SYNOPSIS
        Checks if winget is available on the system.
    #>
    [CmdletBinding()]
    param()

    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        return $null -ne $winget
    }
    catch {
        return $false
    }
}

function Assert-WingetAvailable {
    <#
    .SYNOPSIS
        Ensures winget is available, installing it on Windows 10 if necessary.

    .DESCRIPTION
        Checks if winget is available. If not and running on Windows 10,
        automatically downloads and installs winget.

        NOTE: This function is Windows-specific and will return false on other platforms.
    #>
    [CmdletBinding()]
    param()

    # Check if we're on Windows
    if (-not ($null -eq $IsWindows -or $IsWindows)) {
        Write-Verbose "Not on Windows - winget not available"
        return $false
    }

    if (Test-WingetAvailable) {
        return $true
    }

    $bootstrapHostInfo = $script:CompatibilityHostInfo
    if (-not $bootstrapHostInfo) {
        $bootstrapHostInfo = Get-InstallerHostInfo
    }
    $bootstrapCapability = Test-InstallerWindows10WinGetBootstrapHost -HostInfo $bootstrapHostInfo

    if ($bootstrapCapability.IsSupported) {
        Write-Host "`n[i] winget not found. Attempting to install on Windows 10..." -ForegroundColor Yellow
        $installed = Install-WingetOnWindows10

        if ($installed) {
            return $true
        }
        else {
            Write-Host "Automatic WinGet setup did not complete. Follow the recovery instruction above, or install App Installer manually from Microsoft Store and retry." -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "[X] winget not found ($($bootstrapCapability.ReasonCode)). Please install App Installer using a supported Windows method." -ForegroundColor Red
        return $false
    }
}

function Get-InstalledApplications {
    <#
    .SYNOPSIS
        Gets a list of all installed applications with version information.
    #>
    [CmdletBinding()]
    param()

    $installedApps = @{}

    try {
        # Try using winget list first (faster and more accurate)
        if (-not $WhatIfPreference -and (Test-WingetAvailable)) {
            $wingetList = winget list --accept-source-agreements 2>$null | Out-String

            foreach ($app in $script:Applications) {
                if ($app.WingetId) {
                    if ($wingetList -match [regex]::Escape($app.WingetId)) {
                        # Extract version from winget output
                        $lines = $wingetList -split "`n"
                        $matchingLine = $lines | Where-Object { $_ -match [regex]::Escape($app.WingetId) } | Select-Object -First 1

                        if ($matchingLine -match '\s+([\d\.]+)\s+') {
                            $version = $matches[1]
                        }
                        else {
                            $version = "Installed"
                        }

                        $installedApps[$app.Name] = $version
                    }
                }
            }
        }

        # Fallback: Check registry for installed programs
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $registryApps = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion

        foreach ($app in $script:Applications) {
            if (-not $installedApps.ContainsKey($app.Name)) {
                $match = $registryApps | Where-Object { $_.DisplayName -like "*$($app.Name)*" } | Select-Object -First 1
                if ($match) {
                    $version = if ($match.DisplayVersion) { $match.DisplayVersion } else { "Installed" }
                    $installedApps[$app.Name] = $version
                }
            }
        }

        # Special handling: Check for O&O ShutUp10 by executable path
        # O&O ShutUp10 may not register in standard registry locations
        if (-not $installedApps.ContainsKey("O&O ShutUp10")) {
            $ooShutUpPath = "C:\Program Files\OOShutUp10\OOSU10.exe"
            if (Safe-TestPath $ooShutUpPath) {
                try {
                    $fileInfo = Get-Item $ooShutUpPath -ErrorAction SilentlyContinue
                    $version = if ($fileInfo.VersionInfo.FileVersion) {
                        $fileInfo.VersionInfo.FileVersion
                    } else {
                        "Installed"
                    }
                    $installedApps["O&O ShutUp10"] = $version
                    Write-Log "Detected O&O ShutUp10 via executable path: $version" -Level INFO
                }
                catch {
                    $installedApps["O&O ShutUp10"] = "Installed"
                    Write-Log "Detected O&O ShutUp10 via executable path" -Level INFO
                }
            }
        }

        # Special handling: Check for Manage Restore Points script
        if (-not $installedApps.ContainsKey("Manage Restore Points")) {
            $manageRPPath = "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1"
            if (Safe-TestPath $manageRPPath) {
                try {
                    $scriptContent = Get-Content $manageRPPath -Raw -ErrorAction SilentlyContinue
                    if ($scriptContent -match '\$script:ScriptVersion\s*=\s*[''"]([^''"]+)[''"]') {
                        $version = $matches[1]
                    } else {
                        $version = "Installed"
                    }
                    $installedApps["Manage Restore Points"] = $version
                    Write-Log "Detected Manage Restore Points script: $version" -Level INFO
                }
                catch {
                    $installedApps["Manage Restore Points"] = "Installed"
                    Write-Log "Detected Manage Restore Points script" -Level INFO
                }
            }
        }

        # Special handling: Check for Chrome Remote Desktop shortcut
        # If app is installed but shortcut is missing, create it
        if ($installedApps.ContainsKey("Chrome Remote Desktop")) {
            $shortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Chrome Remote Desktop.lnk"
            if (-not (Safe-TestPath $shortcutPath)) {
                if ($WhatIfPreference) {
                    Write-Host '[PREVIEW] Chrome Remote Desktop shortcut repair was skipped.' -ForegroundColor Cyan
                }
                else {
                    Write-Log "Chrome Remote Desktop is installed but shortcut is missing - will create it" -Level INFO
                    $shortcutCreated = New-WebApplicationShortcut `
                        -ShortcutName "Chrome Remote Desktop" `
                        -Url "https://remotedesktop.google.com/access" `
                        -Description "Configure and access Chrome Remote Desktop"

                    if ($shortcutCreated) {
                        Write-Log "Created missing shortcut for Chrome Remote Desktop" -Level SUCCESS
                    }
                }
            }
            elseif (-not $WhatIfPreference) {
                Write-Log "Chrome Remote Desktop shortcut already exists" -Level INFO
            }
        }
    }
    catch {
        Write-Log "Error detecting installed applications: $_" -Level WARNING
    }

    return $installedApps
}

#endregion

#region Profile Export/Import Functions

function Export-InstallationProfile {
    <#
    .SYNOPSIS
        Exports selected applications to a JSON profile file.

    .DESCRIPTION
        Creates a JSON file containing the list of selected applications along with
        metadata such as timestamp, computer name, user name, and installer version.
        Useful for backing up selections or deploying to multiple machines.

    .PARAMETER SelectedApps
        Array of application objects to export.

    .PARAMETER FilePath
        Optional custom file path. If not specified, uses default naming convention
        in %USERPROFILE%\myTech.Today\AppInstaller\profiles\

    .OUTPUTS
        String - Path to the created profile file, or $null if export failed.

    .EXAMPLE
        $apps = @($script:Applications[0], $script:Applications[5])
        Export-InstallationProfile -SelectedApps $apps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SelectedApps,

        [Parameter(Mandatory = $false)]
        [string]$FilePath
    )

    try {
        # Create profiles directory if it doesn't exist
        $profilesDir = $script:ProfilesPath
        if (-not (Safe-TestPath $profilesDir)) {
            New-Item -Path $profilesDir -ItemType Directory -Force | Out-Null
            Write-Log "Created profiles directory: $profilesDir" -Level INFO
        }

        # Generate default filename if not specified
        if ([string]::IsNullOrWhiteSpace($FilePath)) {
            $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
            $computerName = $env:COMPUTERNAME
            $FilePath = Join-Path $profilesDir "profile-$computerName-$timestamp.json"
        }

        # Extract application names from app objects
        $appNames = $SelectedApps | ForEach-Object { $_.Name }

        # Create profile object
        $profile = [PSCustomObject]@{
            Version = "1.0"
            Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            InstallerVersion = $script:ScriptVersion
            Applications = $appNames
        }

        # Export to JSON
        $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8

        Write-Log "Exported installation profile to: $FilePath" -Level SUCCESS
        Write-Log "Profile contains $($appNames.Count) application(s)" -Level INFO

        return $FilePath
    }
    catch {
        Write-Log "Failed to export installation profile: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Import-InstallationProfile {
    <#
    .SYNOPSIS
        Imports application selections from a JSON profile file.

    .DESCRIPTION
        Reads a JSON profile file and returns the list of applications to select.
        Validates the JSON structure and handles missing applications gracefully.

    .PARAMETER FilePath
        Path to the JSON profile file to import.

    .OUTPUTS
        Hashtable with keys: Success (bool), Applications (array), MissingApps (array), Message (string)

    .EXAMPLE
        $result = Import-InstallationProfile -FilePath "$env:USERPROFILE\myTech.Today\AppInstaller\profiles\profile-PC01-2025-11-09-160000.json"
        if ($result.Success) {
            Install-SelectedApplications -Apps $result.Applications
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        # Validate file exists
        if (-not (Safe-TestPath $FilePath)) {
            Write-Log "Profile file not found: $FilePath" -Level ERROR
            return @{
                Success = $false
                Applications = @()
                MissingApps = @()
                Message = "Profile file not found: $FilePath"
            }
        }

        # Read and parse JSON
        $profileContent = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $profile = $profileContent | ConvertFrom-Json

        # Validate JSON structure
        if (-not $profile.Version -or -not $profile.Applications) {
            Write-Log "Invalid profile format: Missing required fields" -Level ERROR
            return @{
                Success = $false
                Applications = @()
                MissingApps = @()
                Message = "Invalid profile format: Missing required fields (Version, Applications)"
            }
        }

        Write-Log "Importing profile from: $FilePath" -Level INFO
        Write-Log "Profile version: $($profile.Version)" -Level INFO
        Write-Log "Profile created: $($profile.Timestamp)" -Level INFO
        Write-Log "Profile computer: $($profile.ComputerName)" -Level INFO
        Write-Log "Profile user: $($profile.UserName)" -Level INFO
        Write-Log "Profile installer version: $($profile.InstallerVersion)" -Level INFO

        # Match application names to application objects
        $validApps = @()
        $missingApps = @()

        foreach ($appName in $profile.Applications) {
            $app = $script:Applications | Where-Object { $_.Name -eq $appName } | Select-Object -First 1
            if ($app) {
                $validApps += $app
            }
            else {
                $missingApps += $appName
                Write-Log "Application not found in current installer: $appName" -Level WARNING
            }
        }

        Write-Log "Profile contains $($profile.Applications.Count) application(s)" -Level INFO
        Write-Log "Found $($validApps.Count) valid application(s)" -Level INFO
        if ($missingApps.Count -gt 0) {
            Write-Log "Missing $($missingApps.Count) application(s) not in current installer" -Level WARNING
        }

        return @{
            Success = $true
            Applications = $validApps
            MissingApps = $missingApps
            Message = "Successfully imported profile with $($validApps.Count) application(s)"
            ProfileInfo = $profile
        }
    }
    catch {
        Write-Log "Failed to import installation profile: $($_.Exception.Message)" -Level ERROR
        return @{
            Success = $false
            Applications = @()
            MissingApps = @()
            Message = "Failed to import profile: $($_.Exception.Message)"
        }
    }
}

#endregion Profile Export/Import Functions

function Show-Menu {
    <#
    .SYNOPSIS
        Displays the interactive menu with application status.
    #>
    [CmdletBinding()]
    param()

    Clear-Host

    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|         myTech.Today Application Installer v$script:ScriptVersion              |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""

    # Get installed applications
    Write-Host "Detecting installed applications..." -ForegroundColor Yellow
    $installedApps = Get-InstalledApplications
    Write-Host ""

    # Group applications by category
    $categories = $script:Applications | Group-Object -Property Category | Sort-Object Name

    $index = 1
    $menuItems = @{}

    foreach ($category in $categories) {
        # Display category header with prominent formatting
        Write-Host ""
        Write-Host "  === " -NoNewline -ForegroundColor Cyan
        Write-Host "$($category.Name.ToUpper())" -NoNewline -ForegroundColor Yellow
        Write-Host " ===" -ForegroundColor Cyan
        Write-Host ""

        foreach ($app in $category.Group | Sort-Object Name) {
            $menuItems[$index] = $app

            $status = if ($installedApps.ContainsKey($app.Name)) {
                "[OK] Installed ($($installedApps[$app.Name]))"
            } else {
                "[ ] Not Installed"
            }

            $statusColor = if ($installedApps.ContainsKey($app.Name)) { "Green" } else { "Red" }

            Write-Host "    $index. " -NoNewline -ForegroundColor White
            Write-Host "$($app.Name)" -NoNewline -ForegroundColor White
            Write-Host " - " -NoNewline
            Write-Host $status -ForegroundColor $statusColor

            $index++
        }
    }

    Write-Host ""
    Write-Host "  [Actions]" -ForegroundColor Magenta
    Write-Host "    1-$($menuItems.Count). Install Specific Application (type number)" -ForegroundColor Cyan
    Write-Host "    Multi-Select: Type numbers separated by commas or spaces (e.g., '1,3,5' or '1 3 5')" -ForegroundColor Cyan
    Write-Host "    Range Select: Type number ranges (e.g., '1-5' or '10-15,20-25')" -ForegroundColor Cyan
    Write-Host "    Category: Type 'C:CategoryName' (e.g., 'C:Browsers' or 'C:Development')" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    A. Install All Applications" -ForegroundColor Yellow
    Write-Host "    M. Install Missing Applications Only" -ForegroundColor Yellow
    Write-Host "    U. Check for Updates" -ForegroundColor Yellow
    Write-Host "    E. Export Selection to Profile" -ForegroundColor Yellow
    Write-Host "    I. Import Selection from Profile" -ForegroundColor Yellow
    Write-Host "    X. Uninstall/Remove Selected Applications" -ForegroundColor Yellow
    Write-Host "    S. Show Status Only" -ForegroundColor Yellow
    Write-Host "    R. Refresh Status" -ForegroundColor Yellow
    Write-Host "    T. Set up monthly updates (explicit opt-in)" -ForegroundColor Yellow
    Write-Host "    D. Disable monthly updates (removes this app's task only)" -ForegroundColor Yellow
    Write-Host "    Q. Quit" -ForegroundColor Yellow
    Write-Host ""

    return @{
        MenuItems = $menuItems
        Categories = $categories
        InstalledApps = $installedApps
    }
}

function Parse-SelectionInput {
    <#
    .SYNOPSIS
        Parses user input for multi-select, range select, or category selection.

    .PARAMETER SelectionText
        The user's input string.

    .PARAMETER MenuItems
        Hashtable of menu items (index -> app object).

    .PARAMETER Categories
        Array of category groups.

    .OUTPUTS
        Array of application objects to install.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Input')]
        [string]$SelectionText,

        [Parameter(Mandatory = $true)]
        [hashtable]$MenuItems,

        [Parameter(Mandatory = $true)]
        [array]$Categories
    )

    $selectedApps = @()

    # Check for category selection (C:CategoryName)
    if ($SelectionText -match '^C:(.+)$') {
        $categoryName = $matches[1].Trim()
        $category = $Categories | Where-Object { $_.Name -like "*$categoryName*" } | Select-Object -First 1

        if ($category) {
            Write-Host "`nSelected category: $($category.Name)" -ForegroundColor Green
            $selectedApps = $category.Group | Sort-Object Name
        }
        else {
            Write-Host "`nCategory '$categoryName' not found." -ForegroundColor Red
            Write-Host "Available categories:" -ForegroundColor Yellow
            $Categories | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
        }
        return $selectedApps
    }

    # Parse comma or space-separated numbers and ranges
    $SelectionText = $SelectionText -replace '\s+', ',' # Replace spaces with commas
    $parts = $SelectionText -split ',' | Where-Object { $_ -ne '' }

    foreach ($part in $parts) {
        $part = $part.Trim()

        # Check for range (e.g., "1-5")
        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]

            if ($start -gt $end) {
                $temp = $start
                $start = $end
                $end = $temp
            }

            for ($i = $start; $i -le $end; $i++) {
                if ($MenuItems.ContainsKey($i)) {
                    $selectedApps += $MenuItems[$i]
                }
            }
        }
        # Check for single number
        elseif ($part -match '^\d+$') {
            $index = [int]$part
            if ($MenuItems.ContainsKey($index)) {
                $selectedApps += $MenuItems[$index]
            }
            else {
                Write-Host "Invalid selection: $index" -ForegroundColor Red
            }
        }
        else {
            Write-Host "Invalid input: $part" -ForegroundColor Red
        }
    }

    # Remove duplicates
    $selectedApps = $selectedApps | Select-Object -Unique

    return $selectedApps
}

function Install-SelectedApplications {
    <#
    .SYNOPSIS
        Installs multiple selected applications with progress tracking.

    .PARAMETER Apps
        Array of application objects to install.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Apps
    )

    if ($Apps.Count -eq 0) {
        Write-Host "`nNo applications selected." -ForegroundColor Yellow
        return
    }

    # Reorder applications to install O&O ShutUp10 first if present
    $appsToInstall = $Apps
    $ooShutUp = $appsToInstall | Where-Object { $_.Name -eq "O&O ShutUp10" }
    if ($ooShutUp) {
        Write-Log "O&O ShutUp10 detected - moving to front of installation queue" -Level INFO
        $otherApps = $appsToInstall | Where-Object { $_.Name -ne "O&O ShutUp10" }
        $appsToInstall = @($ooShutUp) + $otherApps
    }

    Write-Host "`n+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                    Installing Selected Applications                |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Applications to install: $($appsToInstall.Count)" -ForegroundColor Yellow
    if ($ooShutUp) {
        Write-Host "[i] O&O ShutUp10 will be installed first" -ForegroundColor Cyan
    }
    Write-Host ""

    if ($WhatIfPreference) {
        Write-Host '[PREVIEW] Installed-package state was not queried; selected packages are shown as installation candidates.' -ForegroundColor Cyan
    }
    elseif ($ConfirmPreference -ne 'None') {
        Write-Host "Proceed with installation? (Y/N): " -NoNewline -ForegroundColor Yellow
        $confirm = Read-Host

        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host '[SKIPPED] Installation was declined. No package commands were run.' -ForegroundColor Yellow
            return (New-InstallerActionResult -Status Skipped -Message 'Selected installation was declined.')
        }
    }
    else {
        Write-Host '[INFO] Confirmation prompts were disabled; continuing with the selected package list.' -ForegroundColor Cyan
    }

    $installedApps = if ($WhatIfPreference) { @{} } else { Get-InstalledApplications }
    $alreadyInstalled = @()
    $notInstalled = @()
    foreach ($app in $appsToInstall) {
        if ($installedApps.ContainsKey($app.Name)) {
            $alreadyInstalled += $app
        }
        else {
            $notInstalled += $app
        }
    }

    if (-not $WhatIfPreference) {
        if ($notInstalled.Count -gt 0) {
            Write-Host "New installations ($($notInstalled.Count)):" -ForegroundColor Green
            foreach ($app in $notInstalled) {
                Write-Host "  - $($app.Name)" -ForegroundColor White
            }
            Write-Host ""
        }

        if ($alreadyInstalled.Count -gt 0) {
            Write-Host "Already installed - will reinstall ($($alreadyInstalled.Count)):" -ForegroundColor Yellow
            foreach ($app in $alreadyInstalled) {
                $version = $installedApps[$app.Name]
                if ($app.Name -eq "O&O ShutUp10") {
                    Write-Host "  - $($app.Name) ($version) [Will re-run configuration]" -ForegroundColor Cyan
                }
                else {
                    Write-Host "  - $($app.Name) ($version)" -ForegroundColor Yellow
                }
            }
            Write-Host ""
        }
    }

    $currentIndex = 0
    $successCount = 0
    $failCount = 0
    $previewCount = 0
    $skippedCount = 0

    foreach ($app in $appsToInstall) {
        $currentIndex++
        Write-Host ""
        Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "| Installing [$currentIndex/$($appsToInstall.Count)]: $($app.Name)" -ForegroundColor Cyan
        Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Cyan

        $result = Install-Application -App $app
        switch (Get-InstallerActionStatus -Result $result) {
            'Completed' { $successCount++ }
            'Preview' { $previewCount++ }
            'Skipped' { $skippedCount++ }
            default { $failCount++ }
        }
    }

    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                    Installation Summary                           |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Total:     $($appsToInstall.Count)" -ForegroundColor White
    Write-Host "  Success:   $successCount" -ForegroundColor Green
    Write-Host "  Failed:    $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Gray" })
    if ($previewCount -gt 0) {
        Write-Host "  Preview:   $previewCount (not run)" -ForegroundColor Cyan
    }
    if ($skippedCount -gt 0) {
        Write-Host "  Skipped:   $skippedCount (not run)" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Get-WingetErrorMessage {
    <#
    .SYNOPSIS
        Converts winget exit codes to human-readable error messages.

    .PARAMETER ExitCode
        The winget exit code to interpret.

    .OUTPUTS
        String containing the error description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    # Common winget exit codes
    # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
    switch ($ExitCode) {
        0 { return "Success" }
        -1978335189 { return "Package not found in source" }
        -1978335212 { return "No applicable installer found (wrong architecture or installer type)" }
        -1978335191 { return "Package already installed" }
        -1978334975 { return "Installer failed to complete (may require manual intervention)" }
        -1978335192 { return "File not found" }
        -1978335193 { return "Missing dependency" }
        -1978335194 { return "Invalid manifest" }
        -1978335195 { return "Download failed" }
        -1978335196 { return "Installation failed" }
        -1978335197 { return "Installer hash mismatch" }
        -1978335198 { return "User cancelled" }
        -1978335199 { return "Already installed (different version)" }
        -1978335200 { return "Reboot required" }
        -1978335201 { return "Contact support" }
        -1978335202 { return "Invalid parameter" }
        -1978335203 { return "System not supported" }
        -1978335204 { return "Download size exceeded" }
        -1978335205 { return "Invalid license" }
        -1978335206 { return "Package agreement required" }
        -1978335207 { return "Source agreement required" }
        -1978335208 { return "Blocked by policy" }
        -1978335209 { return "Installer failed" }
        -1978335210 { return "Installer timeout" }
        -1978335211 { return "Installer cancelled" }
        -1978335213 { return "Update not applicable" }
        -1978335214 { return "No uninstall string" }
        -1978335215 { return "Uninstaller failed" }
        -1978335216 { return "Package in use" }
        -1978335217 { return "Invalid state" }
        -1978335218 { return "Custom error" }
        -1978335219 { return "Configuration error" }
        -1978335220 { return "Validation failed" }
        -1978335221 { return "Upgrade failed" }
        -1978335222 { return "Downgrade not allowed" }
        -1978335223 { return "Pin exists" }
        -1978335224 { return "Unpin failed" }
        -1978335225 { return "Unknown version" }
        -1978335226 { return "Unsupported source" }
        -1978335227 { return "Unsupported argument" }
        -1978335228 { return "Multiple matches found" }
        -1978335229 { return "Invalid table" }
        -1978335230 { return "Upgrade not available" }
        -1978335231 { return "Not supported" }
        -1978335232 { return "Blocked by group policy" }
        -1978335233 { return "Experimental feature disabled" }
        -1978335234 { return "Repair not supported" }
        -1978335235 { return "Repair failed" }
        -1978335236 { return "Dependencies validation failed" }
        -1978335237 { return "Missing resource" }
        -1978335238 { return "Invalid authentication" }
        -1978335239 { return "Authentication failed" }
        -1978335240 { return "Package streaming failed" }
        -1978335241 { return "Service unavailable" }
        -1978335242 { return "Blocked by meter" }
        -1978335243 { return "Needs admin" }
        -1978335244 { return "App shutdown failed" }
        -1978335245 { return "Install location required" }
        -1978335246 { return "Archive extraction failed" }
        -1978335247 { return "Certificate validation failed" }
        -1978335248 { return "Portable install failed" }
        -1978335249 { return "Portable package already exists" }
        -1978335250 { return "Portable symlink path in use" }
        -1978335251 { return "Portable package not found" }
        -1978335252 { return "Portable reparse point already exists" }
        -1978335253 { return "Portable package in use" }
        -1978335254 { return "Portable data cleanup failed" }
        -1978335255 { return "Portable write access denied" }
        -1978335256 { return "Checksum mismatch" }
        -1978335257 { return "Customization required" }
        -1978335258 { return "Configuration file invalid" }
        -1978335259 { return "Configuration unit not found" }
        -1978335260 { return "Configuration unit failed" }
        -1978335261 { return "Configuration unit multiple matches" }
        -1978335262 { return "Configuration unit invoke failed" }
        -1978335263 { return "Configuration unit settings invalid" }
        -1978335264 { return "Configuration unit import failed" }
        -1978335265 { return "Configuration unit assert failed" }
        -1978335266 { return "Configuration unit test failed" }
        -1978335267 { return "Configuration unit get failed" }
        -1978335268 { return "Configuration unit dependency not found" }
        -1978335269 { return "Configuration unit has unsatisfied dependencies" }
        -1978335270 { return "Configuration unit not supported" }
        -1978335271 { return "Configuration unit multiple instances" }
        -1978335272 { return "Configuration unit timeout" }
        -1978335273 { return "Configuration parse error" }
        -1978335274 { return "Configuration database corrupted" }
        -1978335275 { return "Configuration history database corrupted" }
        -1978335276 { return "Configuration file schema validation failed" }
        -1978335277 { return "Configuration unit returned duplicate identifier" }
        -1978335278 { return "Configuration unit import module failed" }
        -1978335279 { return "Configuration unit invoke get failed" }
        -1978335280 { return "Configuration unit invoke test failed" }
        -1978335281 { return "Configuration unit invoke set failed" }
        -1978335282 { return "Configuration unit module conflict" }
        -1978335283 { return "Configuration unit import security risk" }
        -1978335284 { return "Configuration unit invoke disabled" }
        -1978335285 { return "Configuration processing cancelled" }
        -1978335286 { return "Configuration queue full" }
        -1978335287 { return "Configuration set dependency cycle" }
        -1978335288 { return "Configuration set apply failed" }
        -1978335289 { return "Configuration set prerequisite failed" }
        -1978335290 { return "Configuration set semantic validation failed" }
        -1978335291 { return "Configuration set dependency unsatisfied" }
        -1978335292 { return "Configuration set read only" }
        -1978335293 { return "Configuration set invalid state" }
        default { return "Unknown error (Exit code: $ExitCode)" }
    }
}

function New-UpdateScanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('CompletedWithUpdates', 'CompletedNoUpdates', 'Failed', 'Unknown', 'Cancelled')]
        [string]$Status,

        [AllowEmptyCollection()]
        [object[]]$Updates = @(),

        [AllowNull()]
        [Nullable[int]]$ExitCode = $null,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    return [PSCustomObject]@{
        Status   = $Status
        Updates  = [object[]]@($Updates)
        ExitCode = if ($null -eq $ExitCode) { $null } else { [int]$ExitCode }
        Reason   = $Reason
    }
}

function ConvertFrom-WingetUpgradeTable {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return New-UpdateScanResult -Status Unknown -Reason 'empty-output'
    }

    $cleanText = [regex]::Replace($Text, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $lines = @($cleanText -split '\r?\n')
    $nonEmptyLines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nonEmptyLines.Count -eq 1 -and $nonEmptyLines[0].Trim() -match '^(?i:No applicable upgrade found)\.?$') {
        return New-UpdateScanResult -Status CompletedNoUpdates -Reason 'no-updates-marker'
    }

    $headerIndexes = @()
    $headerFieldsByIndex = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $fields = @($lines[$i].Trim() -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $normalizedHeader = ($fields -join '|').ToLowerInvariant()
        if ($normalizedHeader -eq 'name|id|version|available' -or $normalizedHeader -eq 'name|id|version|available|source') {
            $headerIndexes += $i
            $headerFieldsByIndex[$i] = $fields
        }
    }

    if ($headerIndexes.Count -eq 0) {
        return New-UpdateScanResult -Status Unknown -Reason 'missing-header'
    }
    if ($headerIndexes.Count -ne 1) {
        return New-UpdateScanResult -Status Unknown -Reason 'ambiguous-header'
    }

    $headerIndex = [int]$headerIndexes[0]
    $separatorIndex = $headerIndex + 1
    if ($separatorIndex -ge $lines.Count -or $lines[$separatorIndex].Trim() -notmatch '^-{3,}$') {
        return New-UpdateScanResult -Status Unknown -Reason 'missing-separator'
    }

    $expectedFieldCount = $headerFieldsByIndex[$headerIndex].Count
    $updates = @()
    $summaryCount = $null
    for ($i = $separatorIndex + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^([0-9]+)\s+upgrades?\s+available\.?$') {
            if ($null -ne $summaryCount) {
                return New-UpdateScanResult -Status Unknown -Reason 'duplicate-summary'
            }
            $summaryCount = [int]$matches[1]
            continue
        }

        if ($null -ne $summaryCount) {
            return New-UpdateScanResult -Status Unknown -Reason 'malformed-row'
        }

        $parts = @($line -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        if ($parts.Count -ne $expectedFieldCount -or $parts.Count -lt 4 -or $parts[1] -match '\s' -or
            @($parts | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            return New-UpdateScanResult -Status Unknown -Reason 'malformed-row'
        }

        $updates += [PSCustomObject]@{
            Name             = $parts[0]
            Id               = $parts[1]
            CurrentVersion   = $parts[2]
            AvailableVersion = $parts[3]
            Source           = if ($parts.Count -ge 5) { $parts[4] } else { 'winget' }
        }
    }

    if ($null -eq $summaryCount) {
        return New-UpdateScanResult -Status Unknown -Reason 'missing-summary'
    }
    if ($summaryCount -ne $updates.Count) {
        return New-UpdateScanResult -Status Unknown -Reason 'summary-count-mismatch'
    }

    $status = if ($updates.Count -eq 0) { 'CompletedNoUpdates' } else { 'CompletedWithUpdates' }
    return New-UpdateScanResult -Status $status -Updates $updates -Reason 'table-validated'
}

function Get-AvailableUpdates {
    [CmdletBinding()]
    param()

    Write-Log 'Checking for available updates using winget upgrade' -Level INFO
    $result = $null

    try {
        $commandResult = Invoke-WingetDependencyCommand -Arguments @('upgrade')
        if ($null -eq $commandResult -or -not $commandResult.PSObject.Properties['Status']) {
            $result = New-UpdateScanResult -Status Unknown -Reason 'command-result-missing'
        }
        elseif ($commandResult.Status -eq 'Unavailable') {
            $result = New-UpdateScanResult -Status Failed -ExitCode $commandResult.ExitCode -Reason 'command-unavailable'
        }
        elseif ($commandResult.Status -eq 'Cancelled') {
            $result = New-UpdateScanResult -Status Cancelled -ExitCode $commandResult.ExitCode -Reason 'command-cancelled'
        }
        elseif ($commandResult.Status -eq 'Failed' -or ($null -ne $commandResult.ExitCode -and [int]$commandResult.ExitCode -ne 0)) {
            $result = New-UpdateScanResult -Status Failed -ExitCode $commandResult.ExitCode -Reason 'command-failed'
        }
        elseif ($commandResult.Status -ne 'Succeeded' -or $null -eq $commandResult.ExitCode) {
            $result = New-UpdateScanResult -Status Unknown -ExitCode $commandResult.ExitCode -Reason 'command-outcome-unknown'
        }
        else {
            $outputText = (@($commandResult.Output) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
            $result = ConvertFrom-WingetUpgradeTable -Text $outputText
            $result.ExitCode = [int]$commandResult.ExitCode
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        $result = New-UpdateScanResult -Status Cancelled -Reason 'command-cancelled'
    }
    catch [System.OperationCanceledException] {
        $result = New-UpdateScanResult -Status Cancelled -Reason 'command-cancelled'
    }
    catch {
        $result = New-UpdateScanResult -Status Unknown -Reason 'command-outcome-unknown'
    }

    $logLevel = switch ($result.Status) {
        'CompletedWithUpdates' { 'INFO' }
        'CompletedNoUpdates' { 'INFO' }
        'Cancelled' { 'WARNING' }
        default { 'ERROR' }
    }
    $exitCodeText = if ($null -eq $result.ExitCode) { 'unknown' } else { [string]$result.ExitCode }
    Write-Log "Update discovery status=$($result.Status); reason=$($result.Reason); exitCode=$exitCodeText" -Level $logLevel
    foreach ($update in $result.Updates) {
        Write-Log "Found update: $($update.Name) ($($update.CurrentVersion) -> $($update.AvailableVersion))" -Level INFO
    }
    return $result
}
function Invoke-WingetDependencyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $processHelper = Get-Command -Name 'Invoke-PackageManagerProcess' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($processHelper) {
        return Invoke-PackageManagerProcess -Executable 'winget' -Arguments $Arguments
    }

    $application = Get-Command -Name 'winget' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $application) {
        return [PSCustomObject]@{
            Status = 'Unavailable'
            ExitCode = $null
            Output = [object[]]@()
            Diagnostic = 'The WinGet executable is unavailable.'
        }
    }

    $executablePath = if ($application.Path) { $application.Path } else { $application.Source }
    try {
        if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $processOutput = @(& $executablePath @Arguments 2>&1)
        $processExitCode = $LASTEXITCODE
        if ($null -eq $processExitCode) {
            return [PSCustomObject]@{
                Status = 'Unknown'
                ExitCode = $null
                Output = [object[]]$processOutput
                Diagnostic = 'WinGet did not return a process exit code.'
            }
        }

        return [PSCustomObject]@{
            Status = if ($processExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
            ExitCode = [int]$processExitCode
            Output = [object[]]$processOutput
            Diagnostic = if ($processExitCode -eq 0) { $null } else { 'WinGet returned a nonzero process exit code.' }
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        throw
    }
    catch [System.OperationCanceledException] {
        throw
    }
    catch {
        return [PSCustomObject]@{
            Status = 'Unknown'
            ExitCode = $null
            Output = [object[]]@()
            Diagnostic = 'The WinGet process outcome could not be confirmed.'
        }
    }
}

function Write-PackageDependencyMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('info', 'succeeded', 'skipped', 'warning')]
        [string]$Status
    )

    $outputFunction = Get-Command -Name 'Write-Output' -CommandType Function -ErrorAction SilentlyContinue
    if ($outputFunction) {
        $color = switch ($Status) {
            'succeeded' { [System.Drawing.Color]::Green }
            'skipped' { [System.Drawing.Color]::Green }
            'warning' { [System.Drawing.Color]::Orange }
            default { [System.Drawing.Color]::Gray }
        }
        Write-Output $Message -Color $color
        return
    }

    $hostColor = switch ($Status) {
        'succeeded' { 'Green' }
        'skipped' { 'Green' }
        'warning' { 'Yellow' }
        default { 'Gray' }
    }
    Write-Host $Message -ForegroundColor $hostColor
}

function Get-PackageDependencies {
    <#
    .SYNOPSIS
        Retrieves WinGet package dependencies with an explicit discovery status.

    .OUTPUTS
        A result with Status, Success, Dependencies, ExitCode, and Message.
        A failed query is unknown because the dependency list could not be verified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    try {
        Write-Log "Checking dependencies for package: $PackageId" -Level INFO
        $showResult = Invoke-WingetDependencyCommand -Arguments @('show', '--id', $PackageId, '--exact')
        if ($null -eq $showResult -or $showResult.Status -ne 'Succeeded' -or $null -eq $showResult.ExitCode -or $showResult.ExitCode -ne 0) {
            $exitCode = if ($showResult -and $showResult.PSObject.Properties['ExitCode']) { $showResult.ExitCode } else { $null }
            Write-Log "Dependency discovery is unknown for $PackageId (exit code: $exitCode)" -Level WARNING
            return [PSCustomObject]@{
                Status = 'unknown'
                Success = $false
                PackageId = $PackageId
                Dependencies = [string[]]@()
                ExitCode = $exitCode
                Message = 'WinGet could not verify the package dependency list.'
            }
        }

        $outputText = (@($showResult.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        $dependencies = @()
        if ($outputText -match "Dependencies:[\s\S]*?Package Dependencies:\s*\r?\n([\s\S]*?)(?:\r?\n\s*\r?\n|\r?\n[A-Z]|\z)") {
            $dependencySection = $matches[1]
            foreach ($line in ($dependencySection -split "\r?\n")) {
                $dependencyId = $line.Trim()
                if ($dependencyId -and $dependencyId -notmatch '^\s*-' -and $dependencyId -match '^[A-Za-z0-9.+]+$') {
                    $dependencies += $dependencyId
                    Write-Log "Found dependency: $dependencyId" -Level INFO
                }
            }
        }

        Write-Log "Dependency discovery succeeded for $PackageId with $($dependencies.Count) package dependency(ies)" -Level INFO
        return [PSCustomObject]@{
            Status = 'succeeded'
            Success = $true
            PackageId = $PackageId
            Dependencies = [string[]]$dependencies
            ExitCode = [int]$showResult.ExitCode
            Message = $null
        }
    }
    catch {
        Write-Log "Dependency discovery is unknown for $PackageId" -Level WARNING
        return [PSCustomObject]@{
            Status = 'unknown'
            Success = $false
            PackageId = $PackageId
            Dependencies = [string[]]@()
            ExitCode = $null
            Message = 'WinGet could not verify the package dependency list.'
        }
    }
}

function Install-PackageDependencies {
    <#
    .SYNOPSIS
        Checks and installs package dependencies, returning one outcome per dependency.

    .OUTPUTS
        A result with Status, Success, and ordered per-dependency Outcomes.
        Per-dependency states are succeeded, failed, skipped, or unknown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Dependencies,

        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    if ($Dependencies.Count -eq 0) {
        return [PSCustomObject]@{
            Status = 'succeeded'
            Success = $true
            PackageName = $PackageName
            Outcomes = [object[]]@()
        }
    }

    Write-Log "Installing dependencies for $PackageName" -Level INFO
    Write-PackageDependencyMessage -Message "  [DEPS] Checking $($Dependencies.Count) dependencies for $PackageName..." -Status info
    $outcomes = @()

    foreach ($dependency in $Dependencies) {
        $dependencyId = [string]$dependency
        $status = 'unknown'
        $message = 'The dependency state could not be confirmed.'
        $checkExitCode = $null
        $installExitCode = $null

        try {
            Write-Log "Checking dependency: $dependencyId" -Level INFO
            $checkResult = Invoke-WingetDependencyCommand -Arguments @('list', '--id', $dependencyId, '--exact')
            if ($checkResult -and $checkResult.PSObject.Properties['ExitCode']) {
                $checkExitCode = $checkResult.ExitCode
            }

            if ($null -eq $checkResult -or $checkResult.Status -ne 'Succeeded' -or $null -eq $checkExitCode -or $checkExitCode -ne 0) {
                $status = 'unknown'
                $message = 'WinGet could not confirm whether the dependency is installed.'
            }
            else {
                $checkText = (@($checkResult.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
                if ($checkText -match [regex]::Escape($dependencyId)) {
                    $status = 'skipped'
                    $message = 'Already installed.'
                }
                else {
                    Write-Log "Installing dependency: $dependencyId" -Level INFO
                    $installResult = Invoke-WingetDependencyCommand -Arguments @(
                        'install', '--id', $dependencyId, '--exact', '--silent',
                        '--accept-source-agreements', '--accept-package-agreements'
                    )
                    if ($installResult -and $installResult.PSObject.Properties['ExitCode']) {
                        $installExitCode = $installResult.ExitCode
                    }

                    if ($installResult -and $installResult.Status -eq 'Succeeded' -and $installExitCode -eq 0) {
                        $status = 'succeeded'
                        $message = 'WinGet reported the dependency install succeeded.'
                    }
                    elseif ($null -ne $installExitCode) {
                        $status = 'failed'
                        $message = "WinGet returned exit code $installExitCode."
                    }
                    else {
                        $status = 'unknown'
                        $message = 'The dependency install outcome could not be confirmed.'
                    }
                }
            }
        }
        catch {
            $status = 'unknown'
            $message = 'The dependency command outcome could not be confirmed.'
        }

        $outcomes += [PSCustomObject]@{
            PackageId = $dependencyId
            Status = $status
            CheckExitCode = $checkExitCode
            InstallExitCode = $installExitCode
            Message = $message
        }

        $logLevel = if ($status -eq 'succeeded' -or $status -eq 'skipped') { 'INFO' } elseif ($status -eq 'failed') { 'WARNING' } else { 'ERROR' }
        Write-Log "Dependency outcome: $dependencyId is $status" -Level $logLevel
        switch ($status) {
            'succeeded' {
                Write-PackageDependencyMessage -Message "  [OK] $dependencyId installed successfully" -Status succeeded
            }
            'skipped' {
                Write-PackageDependencyMessage -Message "  [OK] $dependencyId is already installed" -Status skipped
            }
            'failed' {
                Write-PackageDependencyMessage -Message "  [WARN] $dependencyId did not install (exit code $installExitCode). WinGet will process manifest dependencies during the main operation." -Status warning
            }
            default {
                Write-PackageDependencyMessage -Message "  [WARN] $dependencyId has an unknown preflight result. WinGet will process manifest dependencies during the main operation." -Status warning
            }
        }
    }

    $failedCount = @($outcomes | Where-Object { $_.Status -eq 'failed' }).Count
    $unknownCount = @($outcomes | Where-Object { $_.Status -eq 'unknown' }).Count
    $aggregateStatus = if ($failedCount -gt 0) { 'failed' } elseif ($unknownCount -gt 0) { 'unknown' } else { 'succeeded' }

    return [PSCustomObject]@{
        Status = $aggregateStatus
        Success = $aggregateStatus -eq 'succeeded'
        PackageName = $PackageName
        Outcomes = [object[]]$outcomes
    }
}

function Write-PackageDependencyFallbackNotice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [AllowNull()]
        [object]$DiscoveryResult,

        [AllowNull()]
        [object]$InstallResult
    )

    if ($null -eq $DiscoveryResult -or $DiscoveryResult.Status -ne 'succeeded') {
        $message = "Could not verify dependencies for $PackageName. Continuing to WinGet, which processes manifest dependencies by default. If it fails, check WinGet and retry."
        Write-Log $message -Level WARNING
        Write-PackageDependencyMessage -Message "  [WARN] $message" -Status warning
        return
    }

    if ($null -eq $InstallResult -or $InstallResult.Success) {
        return
    }

    $unresolved = @($InstallResult.Outcomes | Where-Object { $_.Status -eq 'failed' -or $_.Status -eq 'unknown' })
    if ($unresolved.Count -eq 0) {
        return
    }

    $dependencySummary = ($unresolved | ForEach-Object { "$($_.PackageId) ($($_.Status))" }) -join ', '
    $firstDependencyId = [string]$unresolved[0].PackageId
    $message = "Dependency preflight for $PackageName was incomplete: $dependencySummary. Continuing to WinGet, which processes manifest dependencies by default. If it fails, run: winget install --id $firstDependencyId --exact, then retry."
    Write-Log $message -Level WARNING
    Write-PackageDependencyMessage -Message "  [WARN] $message" -Status warning
}

function Update-Applications {
    <#
    .SYNOPSIS
        Updates selected applications using winget upgrade.

    .DESCRIPTION
        Updates one or more applications using 'winget upgrade --id {WingetId}'.
        Shows progress and logs all operations.

    .PARAMETER Updates
        Array of update objects (from Get-AvailableUpdates) to install.

    .OUTPUTS
        Hashtable with keys: SuccessCount, FailCount, Results (array of result objects)

    .EXAMPLE
        $updates = Get-AvailableUpdates
        $result = Update-Applications -Updates $updates[0..2]
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Updates
    )

    Write-Log "Starting update process for $($Updates.Count) application(s)" -Level INFO
    Write-Host "`n=== Starting Updates ===" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0
    $previewCount = 0
    $skippedCount = 0
    $results = @()

    foreach ($update in $Updates) {
        $updateTarget = if ($update.Id) { "{0} [{1}]" -f $update.Name, $update.Id } else { [string]$update.Name }
        $updateAction = "Upgrade $($update.Name) from $($update.CurrentVersion) to $($update.AvailableVersion)"
        if (-not (Test-InstallerShouldProcess -Target $updateTarget -Action $updateAction)) {
            $status = if ($WhatIfPreference) { 'Preview' } else { 'Skipped' }
            $message = if ($WhatIfPreference) {
                "Would $($updateAction.ToLowerInvariant()) for $updateTarget. No package-manager or dependency commands were run."
            }
            else {
                "Update confirmation was declined. $($update.Name) was not changed."
            }
            Write-Host "[$($status.ToUpperInvariant())] $message" -ForegroundColor $(if ($status -eq 'Preview') { 'Cyan' } else { 'Yellow' })
            if ($status -eq 'Preview') { $previewCount++ } else { $skippedCount++ }
            $results += [PSCustomObject]@{
                Name = $update.Name
                Success = $false
                Status = $status
                Message = $message
            }
            continue
        }

        Write-Log "Updating $($update.Name) from $($update.CurrentVersion) to $($update.AvailableVersion)" -Level INFO
        Write-Host "`n[UPDATE] Updating $($update.Name)..." -ForegroundColor Blue
        Write-Host "  Current Version: $($update.CurrentVersion)" -ForegroundColor Gray
        Write-Host "  New Version: $($update.AvailableVersion)" -ForegroundColor Gray

        try {
            $dependencyDiscovery = Get-PackageDependencies -PackageId $update.Id
            $dependencyResult = $null
            if ($dependencyDiscovery.Status -eq 'succeeded') {
                $dependencyResult = Install-PackageDependencies -Dependencies $dependencyDiscovery.Dependencies -PackageName $update.Name
            }
            Write-PackageDependencyFallbackNotice -PackageName $update.Name -DiscoveryResult $dependencyDiscovery -InstallResult $dependencyResult

            # Run winget upgrade for this specific app with retry logic
            $maxRetries = 3
            $retryCount = 0
            $updateSucceeded = $false
            $lastError = ""
            $lastExitCode = 0

            while ($retryCount -lt $maxRetries -and -not $updateSucceeded) {
                if ($retryCount -gt 0) {
                    Write-Log "Retry attempt $retryCount for $($update.Name)" -Level INFO
                    Write-Host "  [RETRY] Attempt $($retryCount + 1) of $maxRetries..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }

                # Build winget command with appropriate flags
                $wingetCmd = "winget upgrade --id `"$($update.Id)`" --silent --accept-source-agreements --accept-package-agreements"

                # For architecture-specific errors, try with --force flag
                if ($retryCount -gt 0 -and $lastExitCode -eq -1978335212) {
                    $wingetCmd += " --force"
                    Write-Log "Adding --force flag due to installer type mismatch" -Level INFO
                }

                # For source errors, try with explicit source
                if ($retryCount -gt 0 -and $lastExitCode -eq -1978335226) {
                    $wingetCmd = "winget upgrade --id `"$($update.Id)`" --source winget --silent --accept-source-agreements --accept-package-agreements"
                    Write-Log "Specifying explicit source due to unsupported source error" -Level INFO
                }

                Write-Log "Executing: $wingetCmd" -Level INFO

                # Execute winget and capture output
                $output = & cmd /c "$wingetCmd 2>&1"
                $exitCode = $LASTEXITCODE
                $lastExitCode = $exitCode

                # Log the output for debugging
                if ($output) {
                    $outputStr = $output | Out-String
                    Write-Log "Winget output: $outputStr" -Level INFO
                }

                # Check for success
                if ($exitCode -eq 0) {
                    $updateSucceeded = $true
                }
                else {
                    # Check if the output indicates success despite non-zero exit code
                    $outputStr = $output | Out-String
                    if ($outputStr -match "Successfully installed" -or
                        $outputStr -match "successfully upgraded" -or
                        $outputStr -match "No applicable update found" -or
                        $outputStr -match "No newer package versions are available") {
                        $updateSucceeded = $true
                        Write-Log "Update appears successful or already current despite exit code $exitCode" -Level INFO
                    }
                    else {
                        $lastError = Get-WingetErrorMessage -ExitCode $exitCode
                        $retryCount++
                    }
                }
            }

            # Process final result
            if ($updateSucceeded) {
                Write-Log "Successfully updated $($update.Name)" -Level INFO
                Write-Host "[OK] $($update.Name) updated successfully" -ForegroundColor Green
                $successCount++

                $results += [PSCustomObject]@{
                    Name = $update.Name
                    Success = $true
                    Status = 'Completed'
                    Message = "Updated to version $($update.AvailableVersion)"
                }
            }
            else {
                Write-Log "Failed to update $($update.Name) after $retryCount attempts: $lastError (Exit code: $lastExitCode)" -Level ERROR
                Write-Host "[ERROR] Failed to update $($update.Name): $lastError" -ForegroundColor Red

                # Provide helpful suggestions based on error type
                if ($lastExitCode -eq -1978335212) {
                    Write-Host "  [HINT] Try updating manually with: winget upgrade --id `"$($update.Id)`" --interactive" -ForegroundColor Cyan
                }
                elseif ($lastExitCode -eq -1978335226) {
                    Write-Host "  [HINT] Package may need to be updated from a different source" -ForegroundColor Cyan
                }
                elseif ($lastExitCode -eq -1978334975) {
                    Write-Host "  [HINT] Try running: winget upgrade --id `"$($update.Id)`" --interactive" -ForegroundColor Cyan
                }

                $failCount++

                $results += [PSCustomObject]@{
                    Name = $update.Name
                    Success = $false
                    Status = 'Failed'
                    Message = $lastError
                }
            }
        }
        catch {
            Write-Log "Exception updating $($update.Name): $($_.Exception.Message)" -Level ERROR
            Write-Host "[ERROR] Exception updating $($update.Name): $($_.Exception.Message)" -ForegroundColor Red
            $failCount++

            $results += [PSCustomObject]@{
                Name = $update.Name
                Success = $false
                Status = 'Failed'
                Message = $_.Exception.Message
            }
        }
    }

    Write-Log "Update process completed: $successCount succeeded, $failCount failed" -Level INFO
    Write-Host "`n=== Updates Complete ===" -ForegroundColor Cyan
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
    if ($previewCount -gt 0) {
        Write-Host "Preview: $previewCount (not run)" -ForegroundColor Cyan
    }
    if ($skippedCount -gt 0) {
        Write-Host "Skipped: $skippedCount (not run)" -ForegroundColor Yellow
    }

    return @{
        SuccessCount = $successCount
        FailCount = $failCount
        PreviewCount = $previewCount
        SkippedCount = $skippedCount
        Results = $results
    }
}

function Check-ForUpdates {
    <#
    .SYNOPSIS
        Main function to check for updates and handle the update process (CLI mode).

    .DESCRIPTION
        Checks for available updates, displays them in a table, prompts for selection,
        and processes selected updates.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($WhatIfPreference) {
        $target = 'all installed applications managed by winget'
        $action = 'Check for available upgrades and apply selected updates'
        [void](Test-InstallerShouldProcess -Target $target -Action $action)
        $message = "Would check for and apply available updates to $target. No winget query, network request, or package command was run."
        Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
        return [PSCustomObject]@{ Status = 'Preview'; Success = $false; Message = $message }
    }

    Write-Log "User initiated update check (CLI mode)" -Level INFO

    # Get available updates
    $scanResult = Get-AvailableUpdates
    $validStatuses = @('CompletedWithUpdates', 'CompletedNoUpdates', 'Failed', 'Unknown', 'Cancelled')
    if ($null -eq $scanResult -or $scanResult.Status -notin $validStatuses -or $null -eq $scanResult.PSObject.Properties['Updates']) {
        Write-Log 'Update discovery status=Unknown; reason=invalid-result; exitCode=unknown' -Level ERROR
        $scanResult = New-UpdateScanResult -Status Unknown -Reason 'invalid-result'
    }

    $updates = [object[]]@($scanResult.Updates)
    if (($scanResult.Status -eq 'CompletedNoUpdates' -and $updates.Count -ne 0) -or
        ($scanResult.Status -eq 'CompletedWithUpdates' -and $updates.Count -eq 0)) {
        Write-Log 'Update discovery status=Unknown; reason=status-count-mismatch; exitCode=unknown' -Level ERROR
        $scanResult = New-UpdateScanResult -Status Unknown -Reason 'status-count-mismatch'
    }

    if ($scanResult.Status -in @('Failed', 'Unknown', 'Cancelled')) {
        Write-Host 'Update availability could not be verified. No packages were changed. Retry the check or use winget upgrade manually.' -ForegroundColor Yellow
        return
    }

    if ($scanResult.Status -eq 'CompletedNoUpdates') {
        Write-Host "`n[INFO] All applications are up to date!" -ForegroundColor Green
        return
    }

    # Display updates in a table
    Write-Host "`n=== Available Updates ===" -ForegroundColor Cyan
    Write-Host ""

    $index = 1
    $updateMap = @{}

    # Display header
    Write-Host "  #  " -NoNewline -ForegroundColor White
    Write-Host "Application".PadRight(35) -NoNewline -ForegroundColor White
    Write-Host "Current".PadRight(15) -NoNewline -ForegroundColor White
    Write-Host "Available".PadRight(15) -NoNewline -ForegroundColor White
    Write-Host "Source" -ForegroundColor White
    Write-Host "  " + ("-" * 85) -ForegroundColor Gray

    # Display each update
    foreach ($update in $updates) {
        $updateMap[$index] = $update

        Write-Host "  $index. " -NoNewline -ForegroundColor Cyan
        Write-Host $update.Name.PadRight(33) -NoNewline -ForegroundColor White
        Write-Host $update.CurrentVersion.PadRight(15) -NoNewline -ForegroundColor Yellow
        Write-Host $update.AvailableVersion.PadRight(15) -NoNewline -ForegroundColor Green
        Write-Host $update.Source -ForegroundColor Gray

        $index++
    }

    Write-Host ""
    Write-Host "  [Options]" -ForegroundColor Magenta
    Write-Host "    1-$($updates.Count). Update specific application (type number)" -ForegroundColor Cyan
    Write-Host "    Multi-Select: Type numbers separated by commas or spaces (e.g., '1,3,5' or '1 3 5')" -ForegroundColor Cyan
    Write-Host "    Range Select: Type number ranges (e.g., '1-5')" -ForegroundColor Cyan
    Write-Host "    A. Update All" -ForegroundColor Yellow
    Write-Host "    Q. Cancel" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Enter your choice: " -NoNewline -ForegroundColor White
    $choice = Read-Host

    # Parse selection
    $selectedUpdates = @()

    if ($choice -eq 'A') {
        # Update all
        $selectedUpdates = $updates
        Write-Host "`n[INFO] Selected all $($updates.Count) updates" -ForegroundColor Green
    }
    elseif ($choice -eq 'Q') {
        Write-Log "User cancelled update check" -Level INFO
        return
    }
    elseif ($choice -match '^\d+$') {
        # Single number
        $num = [int]$choice
        if ($updateMap.ContainsKey($num)) {
            $selectedUpdates = @($updateMap[$num])
        }
        else {
            Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
            return
        }
    }
    elseif ($choice -match '[\d,\-\s]') {
        # Multi-select or range
        $numbers = @()

        # Split by comma or space
        $parts = $choice -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($part in $parts) {
            if ($part -match '^(\d+)-(\d+)$') {
                # Range
                $start = [int]$matches[1]
                $end = [int]$matches[2]
                $numbers += $start..$end
            }
            elseif ($part -match '^\d+$') {
                # Single number
                $numbers += [int]$part
            }
        }

        # Get unique numbers and map to updates
        $numbers = $numbers | Select-Object -Unique | Sort-Object
        foreach ($num in $numbers) {
            if ($updateMap.ContainsKey($num)) {
                $selectedUpdates += $updateMap[$num]
            }
        }

        if ($selectedUpdates.Count -eq 0) {
            Write-Host "[ERROR] No valid updates selected" -ForegroundColor Red
            return
        }

        Write-Host "`n[INFO] Selected $($selectedUpdates.Count) update(s)" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Invalid choice" -ForegroundColor Red
        return
    }

    # Confirm update
    Write-Host "`nUpdate $($selectedUpdates.Count) application(s)? This may take several minutes." -ForegroundColor Yellow
    Write-Host "Continue? (Y/N): " -NoNewline -ForegroundColor White
    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Log "User cancelled update confirmation" -Level INFO
        Write-Host "[SKIPPED] Update was declined. No package update command was run." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'Skipped'; Success = $false; Message = 'Update was declined.' }
    }

    # Perform updates
    $result = Update-Applications -Updates $selectedUpdates

    # Display summary
    Write-Host "`n=== Update Summary ===" -ForegroundColor Cyan
    Write-Host "Total: $($selectedUpdates.Count)" -ForegroundColor White
    Write-Host "Successful: $($result.SuccessCount)" -ForegroundColor Green
    Write-Host "Failed: $($result.FailCount)" -ForegroundColor Red
    if ($result.PreviewCount -gt 0) {
        Write-Host "Preview: $($result.PreviewCount) (not run)" -ForegroundColor Cyan
    }
    if ($result.SkippedCount -gt 0) {
        Write-Host "Skipped: $($result.SkippedCount) (not run)" -ForegroundColor Yellow
    }

    if ($result.FailCount -gt 0) {
        Write-Host "`nFailed Updates:" -ForegroundColor Red
        foreach ($failedResult in ($result.Results | Where-Object { -not $_.Success })) {
            Write-Host "  - $($failedResult.Name): $($failedResult.Message)" -ForegroundColor Red
        }
    }
}

function New-WebApplicationShortcut {
    <#
    .SYNOPSIS
        Creates a Start Menu shortcut that opens a URL in the default browser.

    .DESCRIPTION
        Creates a .lnk shortcut file in the Start Menu that opens a specified URL.
        Attempts to use Chrome browser if available, otherwise falls back to default browser.

    .PARAMETER ShortcutName
        The name of the shortcut (without .lnk extension).

    .PARAMETER Url
        The URL to open when the shortcut is clicked.

    .PARAMETER Description
        Optional description for the shortcut.

    .PARAMETER IconPath
        Optional path to an icon file. If not specified, uses the browser's icon.

    .OUTPUTS
        Boolean indicating success or failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutName,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$IconPath = ""
    )

    try {
        # Create shortcut in Start Menu (all users)
        $startMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        $shortcutPath = Join-Path $startMenuPath "$ShortcutName.lnk"

        # Check if shortcut already exists
        if (Safe-TestPath $shortcutPath) {
            Write-Log "Shortcut already exists: $shortcutPath" -Level INFO
            return $true
        }

        # Find Chrome browser installation
        $chromePaths = @(
            "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "${env:LocalAppData}\Google\Chrome\Application\chrome.exe"
        )

        $chromePath = $null
        foreach ($path in $chromePaths) {
            if (Safe-TestPath $path) {
                $chromePath = $path
                break
            }
        }

        # If Chrome not found, use default browser (via URL protocol)
        if (-not $chromePath) {
            Write-Log "Chrome not found, shortcut will use default browser" -Level WARN
            $targetPath = "explorer.exe"
            $arguments = $Url
            $iconLocation = "$env:SystemRoot\System32\SHELL32.dll,14"  # Internet icon
        }
        else {
            $targetPath = $chromePath
            $arguments = "--new-window `"$Url`""
            $iconLocation = if ($IconPath -and (Safe-TestPath $IconPath)) { $IconPath } else { $chromePath }
        }

        # Create WScript.Shell COM object
        $shell = $null
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $targetPath
            $shortcut.Arguments = $arguments
            $shortcut.Description = if ($Description) { $Description } else { "Open $ShortcutName" }
            $shortcut.IconLocation = $iconLocation
            $shortcut.WorkingDirectory = Split-Path $targetPath -Parent
            $shortcut.Save()

            Write-Log "Created Start Menu shortcut: $shortcutPath" -Level SUCCESS
            return $true
        }
        finally {
            # Always release COM object, even if there's an error
            if ($shell) {
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                $shell = $null
            }
        }
    }
    catch {
        Write-Log "Failed to create shortcut for ${ShortcutName}: ${_}" -Level ERROR
        return $false
    }
}

function Install-OOShutUp10FromRemote {
    <#
    .SYNOPSIS
        Executes the O&O ShutUp10 installation script only when its release is pinned and verified.

    .DESCRIPTION
        The current external helper is disabled until an immutable source and reviewed digest
        or signer are configured in OOShutUp10Trust.psm1.

    .OUTPUTS
        Returns separate download, verification, installation, and cleanup statuses.
    #>
    [CmdletBinding()]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        DownloadStatus = 'not-attempted'
        VerificationStatus = 'unverified'
        InstallationStatus = 'not-started'
        ExitCode = $null
        FailureReason = 'trust-module-unavailable'
        CleanupStatus = 'not-required'
        TempDirectory = $null
    }
    $release = $null

    try {
        if (-not (Test-Path -LiteralPath $script:OOShutUp10TrustModulePath -PathType Leaf)) {
            throw 'trust-module-unavailable'
        }

        $loadedModule = Get-Module -Name OOShutUp10Trust |
            Where-Object { $_.Path -eq $script:OOShutUp10TrustModulePath } |
            Select-Object -First 1
        if (-not $loadedModule) {
            Import-Module -Name $script:OOShutUp10TrustModulePath -DisableNameChecking -ErrorAction Stop | Out-Null
        }

        $release = Get-OOShutUp10PinnedRelease
        $result = Invoke-VerifiedOOShutUp10Script `
            -Uri $release.Uri `
            -ExpectedSha256 $release.Sha256 `
            -ExpectedSignerThumbprint $release.SignerThumbprint
    }
    catch {
        # Keep diagnostics sanitized and installation status separate from transfer status.
        $result.FailureReason = 'trust-check-unavailable'
    }

    $releaseVersion = if ($release -and $release.Version) { $release.Version } else { 'unconfigured' }
    Write-Log ("O&O release={0}; download={1}; verification={2}; installation={3}; exit={4}; reason={5}" -f `
        $releaseVersion, $result.DownloadStatus, $result.VerificationStatus, $result.InstallationStatus, $result.ExitCode, $result.FailureReason) -Level INFO

    if ($result.Success) {
        Write-Host "  [OK] O&O ShutUp10 installation completed." -ForegroundColor Green
    }
    elseif ($result.FailureReason -eq 'cancelled') {
        Write-Host 'O&O installer verification was cancelled. No O&O changes were made.' -ForegroundColor Yellow
    }
    elseif ($result.FailureReason -eq 'execution-policy-blocked') {
        Write-Host $result.RecoveryMessage -ForegroundColor Red
    }
    elseif ($result.InstallationStatus -eq 'not-started') {
        Write-Host 'The O&O installer could not be verified. No O&O changes were made. Review the local installer or retry after the release source is verified.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'O&O installation failed or its result is unknown. Review O&O status before retrying.' -ForegroundColor Red
    }

    return $result
}

function Install-Application {
    <#
    .SYNOPSIS
        Installs a specific application.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$App,

        [Parameter(Mandatory = $false)]
        [int]$CurrentIndex = 0,

        [Parameter(Mandatory = $false)]
        [int]$TotalCount = 0
    )

    $installTarget = if ($App.WingetId) {
        "{0} [{1}]" -f $App.Name, $App.WingetId
    }
    elseif ($App.ScriptName) {
        "{0} (script {1})" -f $App.Name, $App.ScriptName
    }
    else {
        [string]$App.Name
    }
    $installAction = switch -CaseSensitive -Exact ($App.Name) {
        'O&O ShutUp10' { 'Download and install the approved O&O release' }
        default { 'Install or configure the selected application' }
    }

    if (-not (Test-InstallerShouldProcess -Target $installTarget -Action $installAction)) {
        if ($WhatIfPreference) {
            $message = "Would $($installAction.ToLowerInvariant()) for $installTarget. No package, network, or local installer action was performed."
            Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
            return (New-InstallerActionResult -Status Preview -Message $message)
        }

        $message = "$installAction was declined for $installTarget. No installation was performed."
        Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        return (New-InstallerActionResult -Status Skipped -Message $message)
    }

    Write-Log "Installing $($App.Name)..." -Level INFO

    # Show overall progress if index and total are provided
    if ($TotalCount -gt 0) {
        $percentComplete = [Math]::Round(($CurrentIndex / $TotalCount) * 100, 1)
        Write-Progress -Activity "Installing Applications" `
            -Status "Installing $($App.Name) ($CurrentIndex of $TotalCount - $percentComplete%)" `
            -PercentComplete $percentComplete `
            -Id 1
    }

    Write-Host "`n+====================================================================+" -ForegroundColor Cyan
    Write-Host "|  Installing: $($App.Name)" -ForegroundColor Cyan
    if ($TotalCount -gt 0) {
        Write-Host "|  Progress: $CurrentIndex of $TotalCount ($percentComplete%)" -ForegroundColor Cyan
    }
    Write-Host "+====================================================================+" -ForegroundColor Cyan

    try {
        # Special handling for O&O ShutUp10 uses only the pinned-release trust gate.
        if ($App.Name -eq "O&O ShutUp10") {
            Write-Log "Using special installation method for O&O ShutUp10" -Level INFO
            Write-Host "  [i] Checking the approved O&O installer release..." -ForegroundColor Cyan

            # A missing or rejected pin fails this selected item without using another source.
            $remoteResult = Install-OOShutUp10FromRemote

            if ($remoteResult.Success) {
                # Register O&O ShutUp10 as installed
                $ooShutUpPath = "C:\Program Files\OOShutUp10\OOSU10.exe"
                if (Safe-TestPath $ooShutUpPath) {
                    try {
                        $fileInfo = Get-Item $ooShutUpPath -ErrorAction SilentlyContinue
                        $version = if ($fileInfo.VersionInfo.FileVersion) {
                            $fileInfo.VersionInfo.FileVersion
                        } else {
                            "Installed"
                        }
                        $script:InstalledApps["O&O ShutUp10"] = $version
                        Write-Log "Registered O&O ShutUp10 as installed: $version" -Level INFO
                    }
                    catch {
                        $script:InstalledApps["O&O ShutUp10"] = "Installed"
                        Write-Log "Registered O&O ShutUp10 as installed" -Level INFO
                    }
                }
                return $true
            }

            # Do not run the local script or any other source without its own approved trust pin.
            return $false
        }

        # Check if custom script exists
        $scriptPath = Join-Path $script:AppsPath $App.ScriptName

        if (Safe-TestPath $scriptPath) {
            # Use custom installation script
            Write-Log "Using custom script: $scriptPath" -Level INFO
            Write-Verbose "Using custom installation script: $scriptPath"

            # Update progress for individual app
            if ($TotalCount -gt 0) {
                Write-Progress -Activity "Installing $($App.Name)" `
                    -Status "Running custom installation script..." `
                    -PercentComplete 50 `
                    -ParentId 1 `
                    -Id 2
            }

            Write-Host "  [1/2] [CHECK] Using custom installation script..." -ForegroundColor Gray
            Write-Verbose "Executing script in an isolated PowerShell process: $scriptPath"
            $appScriptResult = AppInstallerCore\Invoke-AppScript -ScriptPath $scriptPath -ScriptArguments @()
            $scriptExitCode = $appScriptResult.ExitCode
            Write-Verbose "Custom script result: $($appScriptResult.Status); exit code: $scriptExitCode"

            if ($TotalCount -gt 0) {
                $progressStatus = if ($appScriptResult.Status -in @('PowerShellSuccess', 'NativeProcessSuccess')) { 'Complete' } `
                    elseif ($appScriptResult.Status -eq 'Unknown') { 'Result unknown' } else { 'Failed' }
                Write-Progress -Activity "Installing $($App.Name)" `
                    -Status $progressStatus `
                    -PercentComplete 100 `
                    -ParentId 1 `
                    -Id 2 `
                    -Completed
            }

            if ($appScriptResult.Status -in @('PowerShellSuccess', 'NativeProcessSuccess')) {
                Write-Log "$($App.Name) installed successfully via custom script" -Level SUCCESS
                Write-Host "  [2/2] [OK] Installation complete!" -ForegroundColor Green

                # Create Start Menu shortcut for Chrome Remote Desktop
                if ($App.Name -eq "Chrome Remote Desktop") {
                    Write-Log "Creating Start Menu shortcut for Chrome Remote Desktop..." -Level INFO
                    Write-Host "  [i] Creating Start Menu shortcut..." -ForegroundColor Cyan
                    $shortcutCreated = New-WebApplicationShortcut `
                        -ShortcutName "Chrome Remote Desktop" `
                        -Url "https://remotedesktop.google.com/access" `
                        -Description "Configure and access Chrome Remote Desktop"

                    if ($shortcutCreated) {
                        Write-Host "  [OK] Start Menu shortcut created" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [WARN] Could not create Start Menu shortcut" -ForegroundColor Yellow
                    }
                }

                return $true
            }
            elseif ($appScriptResult.Status -eq 'Unknown') {
                $unknownMessage = "$($App.Name) custom installer result is unknown. The app was not marked installed. Review its status before retrying."
                Write-Log $unknownMessage -Level ERROR
                Write-Host "  [2/2] [UNKNOWN] $unknownMessage" -ForegroundColor Yellow
                return $false
            }
            else {
                $errorMessage = Get-WingetErrorMessage -ExitCode $scriptExitCode
                Write-Log "$($App.Name) installation failed via custom script: $errorMessage (Exit code: $scriptExitCode)" -Level ERROR
                Write-Host "  [2/2] [FAIL] Installation failed: $errorMessage" -ForegroundColor Red
                Write-Host "         Exit code: $scriptExitCode" -ForegroundColor Red
                return $false
            }
        }
        elseif ($App.WingetId) {
            # Use winget for installation
            if (Test-WingetAvailable) {
                Write-Log "Installing via winget: $($App.WingetId)" -Level INFO
                Write-Verbose "Installing $($App.Name) using winget ID: $($App.WingetId)"

                $dependencyDiscovery = Get-PackageDependencies -PackageId $App.WingetId
                $dependencyResult = $null
                if ($dependencyDiscovery.Status -eq 'succeeded') {
                    $dependencyResult = Install-PackageDependencies -Dependencies $dependencyDiscovery.Dependencies -PackageName $App.Name
                }
                Write-PackageDependencyFallbackNotice -PackageName $App.Name -DiscoveryResult $dependencyDiscovery -InstallResult $dependencyResult

                # Phase 1: Checking
                if ($TotalCount -gt 0) {
                    Write-Progress -Activity "Installing $($App.Name)" `
                        -Status "Checking for existing installation..." `
                        -PercentComplete 10 `
                        -ParentId 1 `
                        -Id 2
                }
                Write-Host "  [1/3] [CHECK] Checking for existing installation..." -ForegroundColor Gray
                Write-Verbose "Checking if $($App.Name) is already installed..."
                Start-Sleep -Milliseconds 500

                # Phase 2: Downloading/Installing
                if ($TotalCount -gt 0) {
                    Write-Progress -Activity "Installing $($App.Name)" `
                        -Status "Downloading and installing package..." `
                        -PercentComplete 50 `
                        -ParentId 1 `
                        -Id 2
                }
                Write-Host "  [2/3] [INSTALL] Downloading and installing package..." -ForegroundColor Yellow
                Write-Verbose "Executing: winget install --id $($App.WingetId) --silent --accept-source-agreements --accept-package-agreements"

                $result = winget install --id $App.WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1

                Write-Verbose "winget exit code: $LASTEXITCODE"
                if ($result) {
                    Write-Verbose "winget output: $result"
                }

                if ($LASTEXITCODE -eq 0) {
                    # Phase 3: Complete
                    if ($TotalCount -gt 0) {
                        Write-Progress -Activity "Installing $($App.Name)" `
                            -Status "Complete" `
                            -PercentComplete 100 `
                            -ParentId 1 `
                            -Id 2 `
                            -Completed
                    }

                    Write-Log "$($App.Name) installed successfully" -Level SUCCESS
                    Write-Host "  [3/3] [OK] $($App.Name) installed successfully!" -ForegroundColor Green

                    # Create Start Menu shortcut for Chrome Remote Desktop
                    if ($App.Name -eq "Chrome Remote Desktop") {
                        Write-Log "Creating Start Menu shortcut for Chrome Remote Desktop..." -Level INFO
                        Write-Host "  [i] Creating Start Menu shortcut..." -ForegroundColor Cyan
                        $shortcutCreated = New-WebApplicationShortcut `
                            -ShortcutName "Chrome Remote Desktop" `
                            -Url "https://remotedesktop.google.com/access" `
                            -Description "Configure and access Chrome Remote Desktop"

                        if ($shortcutCreated) {
                            Write-Host "  [OK] Start Menu shortcut created" -ForegroundColor Green
                        }
                        else {
                            Write-Host "  [WARN] Could not create Start Menu shortcut" -ForegroundColor Yellow
                        }
                    }

                    return $true
                }
                else {
                    if ($TotalCount -gt 0) {
                        Write-Progress -Activity "Installing $($App.Name)" `
                            -Status "Failed" `
                            -PercentComplete 100 `
                            -ParentId 1 `
                            -Id 2 `
                            -Completed
                    }

                    $errorMessage = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
                    Write-Log "$($App.Name) installation failed: $errorMessage (Exit code: $LASTEXITCODE)" -Level ERROR
                    Write-Host "  [3/3] [FAIL] Installation failed: $errorMessage" -ForegroundColor Red
                    Write-Host "         Exit code: $LASTEXITCODE" -ForegroundColor Red
                    if ($result) {
                        Write-Host "         Details: $result" -ForegroundColor Red
                    }
                    return $false
                }
            }
            else {
                Write-Log "winget not available, cannot install $($App.Name)" -Level ERROR
                Write-Host "  [ERROR] winget not available. Please install App Installer from Microsoft Store." -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Log "No installation method available for $($App.Name)" -Level WARNING
            Write-Host "  [WARN] No installation method configured for $($App.Name)" -ForegroundColor Yellow
            Write-Host "  Custom script required: $scriptPath" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        if ($TotalCount -gt 0) {
            Write-Progress -Activity "Installing $($App.Name)" `
                -Status "Error" `
                -PercentComplete 100 `
                -ParentId 1 `
                -Id 2 `
                -Completed
        }

        Write-Log "Error installing $($App.Name): $_" -Level ERROR
        Write-Host "  [ERROR] Error: $_" -ForegroundColor Red
        return $false
    }
}

function Uninstall-Application {
    <#
    .SYNOPSIS
        Uninstalls a specific application using winget.

    .DESCRIPTION
        Uninstalls an application using 'winget uninstall --id {WingetId} --silent'.
        Logs all operations and shows progress.

    .PARAMETER App
        The application hashtable to uninstall (must have WingetId property).

    .PARAMETER CurrentIndex
        Current index in the uninstall queue (for progress tracking).

    .PARAMETER TotalCount
        Total number of applications to uninstall (for progress tracking).

    .OUTPUTS
        Boolean - $true if uninstall succeeded, $false otherwise.

    .EXAMPLE
        $app = $script:Applications | Where-Object { $_.Name -eq "Google Chrome" }
        Uninstall-Application -App $app
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$App,

        [Parameter(Mandatory = $false)]
        [int]$CurrentIndex = 0,

        [Parameter(Mandatory = $false)]
        [int]$TotalCount = 0
    )

    $uninstallTarget = if ($App.WingetId) { "{0} [{1}]" -f $App.Name, $App.WingetId } else { [string]$App.Name }
    if (-not $App.WingetId) {
        Write-Host "[SKIPPED] Cannot uninstall $($App.Name): no winget package ID is configured." -ForegroundColor Yellow
        return (New-InstallerActionResult -Status Skipped -Message 'No winget package ID is configured.')
    }

    $uninstallAction = "Uninstall $($App.Name)"
    if (-not (Test-InstallerShouldProcess -Target $uninstallTarget -Action $uninstallAction)) {
        if ($WhatIfPreference) {
            $message = "Would uninstall $uninstallTarget. No installed-state query or package command was run."
            Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
            return (New-InstallerActionResult -Status Preview -Message $message)
        }

        $message = "$uninstallTarget was not uninstalled because confirmation was declined."
        Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        return (New-InstallerActionResult -Status Skipped -Message $message)
    }

    Write-Log "Uninstalling $($App.Name)..." -Level INFO

    # Show overall progress if index and total are provided
    if ($TotalCount -gt 0) {
        $percentComplete = [Math]::Round(($CurrentIndex / $TotalCount) * 100, 1)
        Write-Progress -Activity "Uninstalling Applications" `
            -Status "Uninstalling $($App.Name) ($CurrentIndex of $TotalCount - $percentComplete%)" `
            -PercentComplete $percentComplete `
            -Id 1
    }

    Write-Host "`n+====================================================================+" -ForegroundColor Cyan
    Write-Host "|  Uninstalling: $($App.Name)" -ForegroundColor Cyan
    if ($TotalCount -gt 0) {
        Write-Host "|  Progress: $CurrentIndex of $TotalCount ($percentComplete%)" -ForegroundColor Cyan
    }
    Write-Host "+====================================================================+" -ForegroundColor Cyan

    try {
        # Check if app is actually installed
        if (-not $script:InstalledApps.ContainsKey($App.Name)) {
            $detectedApps = Get-InstalledApplications
            if ($detectedApps.ContainsKey($App.Name)) {
                $script:InstalledApps[$App.Name] = $detectedApps[$App.Name]
            }
            else {
                Write-Log "$($App.Name) is not installed - skipping uninstall" -Level INFO
                Write-Host "[SKIPPED] $($App.Name) is not installed." -ForegroundColor Cyan
                return (New-InstallerActionResult -Status Skipped -Message 'Application is not installed.')
            }
        }

        # Update progress for individual app
        if ($TotalCount -gt 0) {
            Write-Progress -Activity "Uninstalling $($App.Name)" `
                -Status "Removing application..." `
                -PercentComplete 50 `
                -ParentId 1 `
                -Id 2
        }

        Write-Host "  [UNINSTALL] Removing $($App.Name)..." -ForegroundColor Yellow
        Write-Log "Executing: winget uninstall --id $($App.WingetId) --silent" -Level INFO

        $result = winget uninstall --id $App.WingetId --silent 2>&1

        if ($TotalCount -gt 0) {
            Write-Progress -Activity "Uninstalling $($App.Name)" `
                -Status "Complete" `
                -PercentComplete 100 `
                -ParentId 1 `
                -Id 2 `
                -Completed
        }

        # Check exit code
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($App.Name) uninstalled successfully" -Level SUCCESS
            Write-Host "  [OK] $($App.Name) uninstalled successfully" -ForegroundColor Green

            # Remove from installed apps hashtable
            if ($script:InstalledApps.ContainsKey($App.Name)) {
                $script:InstalledApps.Remove($App.Name)
                Write-Log "Removed $($App.Name) from installed apps cache" -Level INFO
            }

            return $true
        }
        else {
            # Uninstall failed
            $errorMsg = $result | Out-String
            $errorMessage = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
            Write-Log "Failed to uninstall $($App.Name): $errorMessage (Exit code: $LASTEXITCODE)" -Level ERROR
            Write-Log "Winget output: $errorMsg" -Level ERROR
            Write-Host "  [ERROR] Failed to uninstall $($App.Name): $errorMessage" -ForegroundColor Red
            Write-Host "         Exit code: $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
    }
    catch {
        if ($TotalCount -gt 0) {
            Write-Progress -Activity "Uninstalling $($App.Name)" `
                -Status "Error" `
                -PercentComplete 100 `
                -ParentId 1 `
                -Id 2 `
                -Completed
        }

        Write-Log "Error uninstalling $($App.Name): $_" -Level ERROR
        Write-Host "  [ERROR] Error: $_" -ForegroundColor Red
        return $false
    }
}

function Install-AllApplications {
    <#
    .SYNOPSIS
        Installs all applications.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Write-Log "Installing all applications..." -Level INFO
    Write-Verbose "Starting installation of all $($script:Applications.Count) applications"
    Write-Host "`n+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                    Installing All Applications                    |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0
    $previewCount = 0
    $skippedCount = 0
    $totalCount = $script:Applications.Count
    $currentIndex = 0
    $startTime = Get-Date
    $installationTimes = @()  # Track individual installation times for ETA

    Write-Verbose "Total applications to install: $totalCount"

    # Reorder applications to install O&O ShutUp10 first if present
    $appsToInstall = $script:Applications
    $ooShutUp = $appsToInstall | Where-Object { $_.Name -eq "O&O ShutUp10" }
    if ($ooShutUp) {
        Write-Log "O&O ShutUp10 detected - moving to front of installation queue" -Level INFO
        Write-Host "[i] O&O ShutUp10 will be installed first" -ForegroundColor Cyan
        $otherApps = $appsToInstall | Where-Object { $_.Name -ne "O&O ShutUp10" }
        $appsToInstall = @($ooShutUp) + $otherApps
    }

    foreach ($app in $appsToInstall) {
        $currentIndex++
        $appStartTime = Get-Date

        Write-Verbose "[$currentIndex/$totalCount] Starting installation of $($app.Name)"

        $result = Install-Application -App $app -CurrentIndex $currentIndex -TotalCount $totalCount

        # Track installation time
        $appEndTime = Get-Date
        $appDuration = ($appEndTime - $appStartTime).TotalSeconds
        $installationTimes += $appDuration

        # Calculate ETA
        if ($installationTimes.Count -gt 0) {
            $avgTime = ($installationTimes | Measure-Object -Average).Average
            $remainingApps = $totalCount - $currentIndex
            $etaSeconds = $avgTime * $remainingApps
            $etaMinutes = [Math]::Round($etaSeconds / 60, 1)

            if ($remainingApps -gt 0) {
                Write-Host "  [TIME] Estimated time remaining: $etaMinutes minutes ($remainingApps apps left)" -ForegroundColor DarkGray
            }
        }

        switch (Get-InstallerActionStatus -Result $result) {
            'Completed' { $successCount++ }
            'Preview' { $previewCount++ }
            'Skipped' { $skippedCount++ }
            default { $failCount++ }
        }
        if (-not $WhatIfPreference) {
            Start-Sleep -Seconds 1
        }
    }

    # Complete the overall progress
    Write-Progress -Activity "Installing Applications" -Completed -Id 1

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    Write-Verbose "Installation batch completed in $totalMinutes minutes"
    Write-Verbose "Success rate: $([Math]::Round(($successCount / $totalCount) * 100, 1))%"

    # Installation Summary
    Write-Host "`n+====================================================================+" -ForegroundColor Cyan
    Write-Host "|                     INSTALLATION SUMMARY                           |" -ForegroundColor Cyan
    Write-Host "+====================================================================+" -ForegroundColor Cyan
    Write-Host "|  Total Applications: $totalCount" -ForegroundColor White
    Write-Host "|  [OK] Successful: $successCount" -ForegroundColor Green
    Write-Host "|  [FAIL] Failed: $failCount" -ForegroundColor Red
    if ($previewCount -gt 0) {
        Write-Host "|  [PREVIEW] Not run: $previewCount" -ForegroundColor Cyan
    }
    if ($skippedCount -gt 0) {
        Write-Host "|  [SKIP] Not run: $skippedCount" -ForegroundColor Yellow
    }
    Write-Host "|  [TIME] Total Time: $totalMinutes minutes" -ForegroundColor White
    Write-Host "+====================================================================+" -ForegroundColor Cyan

    Write-Log "Installation complete. Success: $successCount, Failed: $failCount, Duration: $totalMinutes minutes" -Level INFO
    Write-Verbose "Installation summary logged to: $script:LogFile"
}

function Install-MissingApplications {
    <#
    .SYNOPSIS
        Installs only applications that are not currently installed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Write-Log "Installing missing applications..." -Level INFO
    Write-Host "`n+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                Installing Missing Applications Only               |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    $previewCount = 0
    $totalCount = $script:Applications.Count
    $currentIndex = 0
    $startTime = Get-Date
    $installationTimes = @()  # Track individual installation times for ETA

    # Reorder applications to install O&O ShutUp10 first if present
    $appsToInstall = $script:Applications
    $ooShutUp = $appsToInstall | Where-Object { $_.Name -eq "O&O ShutUp10" }
    if ($ooShutUp) {
        Write-Log "O&O ShutUp10 detected - moving to front of installation queue" -Level INFO
        Write-Host "[i] O&O ShutUp10 will be installed first (if missing)" -ForegroundColor Cyan
        $otherApps = $appsToInstall | Where-Object { $_.Name -ne "O&O ShutUp10" }
        $appsToInstall = @($ooShutUp) + $otherApps
    }

    if ($WhatIfPreference) {
        Write-Host '[PREVIEW] Installed-package state was not queried. Each configured package is a candidate that would be installed only if still missing.' -ForegroundColor Cyan
        foreach ($app in $appsToInstall) {
            $result = Install-Application -App $app -CurrentIndex 0 -TotalCount $totalCount
            if ((Get-InstallerActionStatus -Result $result) -eq 'Preview') {
                $previewCount++
            }
        }
        Write-Host "[PREVIEW] $previewCount package action(s) shown; no installation or status query was performed." -ForegroundColor Cyan
        return
    }

    $installedApps = Get-InstalledApplications

    foreach ($app in $appsToInstall) {
        $currentIndex++

        if ($installedApps.ContainsKey($app.Name)) {
            # Special handling for O&O ShutUp10: Always allow re-running
            if ($app.Name -eq "O&O ShutUp10") {
                Write-Host "`n[INFO] O&O ShutUp10 is already installed ($($installedApps[$app.Name]))" -ForegroundColor Cyan
                Write-Host "[INFO] Re-running O&O ShutUp10 configuration script..." -ForegroundColor Cyan
                Write-Log "O&O ShutUp10 already installed - re-running remote script as requested" -Level INFO

                $appStartTime = Get-Date
                $result = Install-Application -App $app -CurrentIndex $currentIndex -TotalCount $totalCount

                # Track installation time
                $appEndTime = Get-Date
                $appDuration = ($appEndTime - $appStartTime).TotalSeconds
                $installationTimes += $appDuration

                switch (Get-InstallerActionStatus -Result $result) {
                    'Completed' { $successCount++ }
                    'Preview' { $previewCount++ }
                    'Skipped' { $skippedCount++ }
                    default { $failCount++ }
                }
            }
            else {
                # For other applications, prompt user for re-installation
                Write-Host "`n[INFO] $($app.Name) is already installed ($($installedApps[$app.Name]))" -ForegroundColor Yellow
                if ($ConfirmPreference -eq 'None') {
                    $response = 'N'
                    Write-Host "[SKIPPED] $($app.Name) is already installed; noninteractive mode will not reinstall it." -ForegroundColor Gray
                }
                else {
                    $response = Read-Host "Would you like to reinstall $($app.Name)? (Y/N)"
                }

                if ($response -match '^[Yy]') {
                    Write-Log "User chose to reinstall $($app.Name)" -Level INFO
                    Write-Host "[INFO] Reinstalling $($app.Name)..." -ForegroundColor Cyan

                    $appStartTime = Get-Date
                    $result = Install-Application -App $app -CurrentIndex $currentIndex -TotalCount $totalCount

                    # Track installation time
                    $appEndTime = Get-Date
                    $appDuration = ($appEndTime - $appStartTime).TotalSeconds
                    $installationTimes += $appDuration

                    switch (Get-InstallerActionStatus -Result $result) {
                        'Completed' { $successCount++ }
                        'Preview' { $previewCount++ }
                        'Skipped' { $skippedCount++ }
                        default { $failCount++ }
                    }
                }
                else {
                    Write-Host "[SKIP] Skipping $($app.Name) - User declined reinstallation" -ForegroundColor Gray
                    Write-Log "User declined to reinstall $($app.Name)" -Level INFO
                    $skippedCount++

                    # Update progress for skipped apps
                    $percentComplete = [Math]::Round(($currentIndex / $totalCount) * 100, 1)
                    Write-Progress -Activity "Installing Missing Applications" `
                        -Status "Skipped $($app.Name) ($currentIndex of $totalCount - $percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -Id 1
                }
            }
        }
        else {
            $appStartTime = Get-Date

            $result = Install-Application -App $app -CurrentIndex $currentIndex -TotalCount $totalCount

            # Track installation time
            $appEndTime = Get-Date
            $appDuration = ($appEndTime - $appStartTime).TotalSeconds
            $installationTimes += $appDuration

            # Calculate ETA
            if ($installationTimes.Count -gt 0) {
                $avgTime = ($installationTimes | Measure-Object -Average).Average
                $remainingApps = $totalCount - $currentIndex
                $etaSeconds = $avgTime * $remainingApps
                $etaMinutes = [Math]::Round($etaSeconds / 60, 1)

                if ($remainingApps -gt 0) {
                    Write-Host "  [TIME] Estimated time remaining: $etaMinutes minutes ($remainingApps apps left)" -ForegroundColor DarkGray
                }
            }

            switch (Get-InstallerActionStatus -Result $result) {
                'Completed' { $successCount++ }
                'Preview' { $previewCount++ }
                'Skipped' { $skippedCount++ }
                default { $failCount++ }
            }
        }
        if (-not $WhatIfPreference) {
            Start-Sleep -Seconds 1
        }
    }

    # Complete the overall progress
    Write-Progress -Activity "Installing Missing Applications" -Completed -Id 1

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    Write-Verbose "Installation batch completed in $totalMinutes minutes"
    Write-Verbose "Installed: $successCount, Skipped: $skippedCount, Failed: $failCount"

    # Installation Summary
    Write-Host "`n+====================================================================+" -ForegroundColor Cyan
    Write-Host "|                     INSTALLATION SUMMARY                           |" -ForegroundColor Cyan
    Write-Host "+====================================================================+" -ForegroundColor Cyan
    Write-Host "|  Total Applications: $totalCount" -ForegroundColor White
    Write-Host "|  [OK] Installed: $successCount" -ForegroundColor Green
    Write-Host "|  [SKIP] Skipped: $skippedCount" -ForegroundColor Gray
    Write-Host "|  [FAIL] Failed: $failCount" -ForegroundColor Red
    if ($previewCount -gt 0) {
        Write-Host "|  [PREVIEW] Not run: $previewCount" -ForegroundColor Cyan
    }
    Write-Host "|  [TIME] Total Time: $totalMinutes minutes" -ForegroundColor White
    Write-Host "+====================================================================+" -ForegroundColor Cyan

    Write-Log "Installation complete. Installed: $successCount, Skipped: $skippedCount, Failed: $failCount, Duration: $totalMinutes minutes" -Level INFO
    Write-Verbose "Installation summary logged to: $script:LogFile"
}

function Install-MonthlyUpdateTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$MenuData
    )

    if (-not ($env:OS -match 'Windows')) {
        Write-Host 'Monthly scheduled updates are available only on Windows. No task was created.' -ForegroundColor Yellow
        return $false
    }

    $taskFullPath = '\myTech.Today\Monthly Application Updates'
    Write-Host ''
    Write-Host 'Select the applications to include in monthly updates.' -ForegroundColor Cyan
    Write-Host 'Enter app numbers, ranges, or C:CategoryName. Press Enter or Q to cancel.' -ForegroundColor Gray
    Write-Host 'Selection: ' -NoNewline -ForegroundColor White
    $selection = Read-Host
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq 'Q') {
        if ($WhatIfPreference) {
            $action = 'Enable the monthly update task after package selection'
            [void](Test-InstallerShouldProcess -Target $taskFullPath -Action $action)
            $message = "Would enable the monthly update task at $taskFullPath after package selection. No package scope or scheduler changes were applied."
            Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
            return (New-InstallerActionResult -Status Preview -Message $message)
        }
        if ($ConfirmPreference -eq 'None') {
            Write-Host '[SKIPPED] Monthly task setup needs a package selection in noninteractive mode. No task changes were made.' -ForegroundColor Yellow
            return (New-InstallerActionResult -Status Skipped -Message 'Package selection was unavailable in noninteractive mode.')
        }
        Write-Host 'Monthly update setup cancelled. No task changes were made.' -ForegroundColor Yellow
        return $false
    }

    $selectedApps = @(Parse-SelectionInput -SelectionText $selection -MenuItems $MenuData.MenuItems -Categories $MenuData.Categories)
    if ($selectedApps.Count -eq 0) {
        Write-Host ("No valid applications were selected from the {0} displayed entries. No task changes were made." -f $MenuData.MenuItems.Count) -ForegroundColor Yellow
        return $false
    }

    $unsupportedApps = @($selectedApps | Where-Object { [string]::IsNullOrWhiteSpace($_.WingetId) })
    if ($unsupportedApps.Count -gt 0) {
        $unsupportedNames = ($unsupportedApps | ForEach-Object { $_.Name }) -join ', '
        Write-Host "These selections do not have a winget package ID and cannot be scheduled: $unsupportedNames" -ForegroundColor Red
        Write-Host 'No task changes were made.' -ForegroundColor Yellow
        return $false
    }

    $packageIds = @($selectedApps | ForEach-Object { ([string]$_.WingetId).Trim() } | Select-Object -Unique)
    $invalidIds = @($packageIds | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._ +()\-]*$' })
    if ($invalidIds.Count -gt 0) {
        Write-Host 'A selected package ID contains unsupported characters. No task changes were made.' -ForegroundColor Red
        return $false
    }

    $taskFullPath = '\myTech.Today\Monthly Application Updates'
    $packageIdList = ($packageIds | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    if ($WhatIfPreference) {
        $scope = $packageIds -join ', '
        $action = "Enable monthly updates for package IDs: $scope"
        [void](Test-InstallerShouldProcess -Target $taskFullPath -Action $action)
        $message = "Would enable monthly updates for package IDs $scope at $taskFullPath. No updater validation, file writes, or scheduler commands were run."
        Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
        return (New-InstallerActionResult -Status Preview -Message $message)
    }

    $systemAppsPath = Join-Path $script:SystemInstallPath 'apps'
    $updateScriptPath = Join-Path $systemAppsPath 'winget-update.ps1'
    if (-not (Test-Path -LiteralPath $updateScriptPath -PathType Leaf)) {
        Write-Host "Monthly update script is missing: $updateScriptPath. No task changes were made." -ForegroundColor Red
        Write-Log 'Monthly update script missing at the selected path.' -Level ERROR
        return $false
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host ''
    Write-Host 'Monthly update task details:' -ForegroundColor Cyan
    Write-Host '  Cadence: 15th of each month at 1:00 PM (local time)' -ForegroundColor White
    Write-Host ("  Package scope: {0} selected winget package(s)" -f $packageIds.Count) -ForegroundColor White
    Write-Host $packageIdList -ForegroundColor Gray
    Write-Host "  Account: $identity; run only while this user is logged in" -ForegroundColor White
    Write-Host '  Requested privilege: Highest available for this account' -ForegroundColor White
    Write-Host "  Updater script: $updateScriptPath" -ForegroundColor White
    Write-Host "  Task path: $taskFullPath" -ForegroundColor White
    Write-Host ('  Remove later: schtasks.exe /Delete /TN "{0}" /F' -f $taskFullPath) -ForegroundColor Gray

    if ($ConfirmPreference -ne 'None') {
        Write-Host 'Enable or replace the application-owned monthly task for these packages? (Y/N): ' -NoNewline -ForegroundColor Yellow
        $confirmation = Read-Host
        if ($confirmation -notmatch '^[Yy]$') {
            Write-Host '[SKIPPED] Monthly update setup declined. No scheduler commands were run.' -ForegroundColor Yellow
            return (New-InstallerActionResult -Status Skipped -Message 'Monthly task setup was declined.')
        }
    }

    $taskAction = "Enable monthly updates for package IDs: $($packageIds -join ', ')"
    if (-not (Test-InstallerShouldProcess -Target $taskFullPath -Action $taskAction)) {
        Write-Host "[SKIPPED] Monthly task setup was not approved. No scheduler commands were run." -ForegroundColor Yellow
        return (New-InstallerActionResult -Status Skipped -Message 'ShouldProcess confirmation was declined.')
    }

    $taskQuery = Get-MonthlyUpdateTaskQuery -TaskPath $taskFullPath
    if (-not $taskQuery.Success) {
        Write-Host "Could not safely inspect the scheduled task. Scheduler error: $($taskQuery.Output)" -ForegroundColor Red
        Write-Log 'Could not safely inspect the monthly update task.' -Level ERROR
        return $false
    }

    if ($taskQuery.Exists -and -not (Test-MonthlyUpdateTaskOwnership -XmlText $taskQuery.XmlText -UpdateScriptPath $updateScriptPath)) {
        Write-Host "A task already exists at $taskFullPath, but it is not recognized as owned by this installer. It was left unchanged." -ForegroundColor Red
        return $false
    }

    $taskXmlPath = $null
    $stagingTaskPath = '\Monthly Application Updates.pending-' + [guid]::NewGuid().ToString('N')
    $stagingCreated = $false
    $previousXmlPath = $null
    $temporaryFiles = @()
    $taskChanged = $false
    $failureMessage = $null

    try {
        $taskXmlPath = New-MonthlyUpdateTaskXmlFile -UpdateScriptPath $updateScriptPath -PackageIds $packageIds -Identity $identity -Enabled $true
        $temporaryFiles += $taskXmlPath
        if ($taskQuery.Exists) {
            $previousXmlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('monthly-update-previous-' + [guid]::NewGuid().ToString('N') + '.xml')
            [System.IO.File]::WriteAllText($previousXmlPath, $taskQuery.XmlText, [System.Text.Encoding]::UTF8)
            $temporaryFiles += $previousXmlPath
        }

        $stagingXmlPath = New-MonthlyUpdateTaskXmlFile -UpdateScriptPath $updateScriptPath -PackageIds $packageIds -Identity $identity -Enabled $false
        $temporaryFiles += $stagingXmlPath
        $stagePreflight = Get-MonthlyUpdateTaskQuery -TaskPath $stagingTaskPath
        if (-not $stagePreflight.Success -or $stagePreflight.Exists) {
            $failureMessage = "Could not reserve an unused disabled staging task path. Scheduler output: $($stagePreflight.Output)"
            throw 'stage-path-unavailable'
        }
        $stageCreate = Invoke-TaskSchedulerCommand -Arguments @('/Create', '/TN', $stagingTaskPath, '/XML', $stagingXmlPath)
        if ($stageCreate.ExitCode -ne 0) {
            $failureMessage = "Scheduler error while validating a disabled staging task: $($stageCreate.Output)"
            $stageAfterFailure = Get-MonthlyUpdateTaskQuery -TaskPath $stagingTaskPath
            $stagingCreated = (-not $stageAfterFailure.Success) -or $stageAfterFailure.Exists
            throw 'stage-create-failed'
        }
        $stagingCreated = $true

        $stageQuery = Get-MonthlyUpdateTaskQuery -TaskPath $stagingTaskPath
        if (-not $stageQuery.Success -or -not (Test-MonthlyUpdateTaskDefinition -XmlText $stageQuery.XmlText -UpdateScriptPath $updateScriptPath -PackageIds $packageIds -Identity $identity -Enabled $false)) {
            $failureMessage = "The disabled staging task did not match the confirmed schedule. Scheduler output: $($stageQuery.Output)"
            throw 'stage-validation-failed'
        }

        $stageDelete = Invoke-TaskSchedulerCommand -Arguments @('/Delete', '/TN', $stagingTaskPath, '/F')
        if ($stageDelete.ExitCode -ne 0) {
            $failureMessage = "Scheduler error removing the disabled staging task: $($stageDelete.Output)"
            throw 'stage-cleanup-failed'
        }
        $stagingCreated = $false

        $targetPreflight = Get-MonthlyUpdateTaskQuery -TaskPath $taskFullPath
        if (-not $targetPreflight.Success) {
            $failureMessage = "Could not revalidate the existing task before replacement. Scheduler output: $($targetPreflight.Output)"
            throw 'target-revalidation-failed'
        }
        if ($taskQuery.Exists) {
            if (-not $targetPreflight.Exists -or -not (Test-MonthlyUpdateTaskDefinitionEqual -ExpectedXml $taskQuery.XmlText -ActualXml $targetPreflight.XmlText)) {
                $failureMessage = 'The existing task changed while setup was in progress. It was left untouched; review it before retrying.'
                throw 'target-changed-before-replacement'
            }
        }
        elseif ($targetPreflight.Exists) {
            $failureMessage = 'A task appeared at the application task path while setup was in progress. It was left untouched.'
            throw 'target-appeared-before-replacement'
        }

        $finalCreateArguments = @('/Create', '/TN', $taskFullPath, '/XML', $taskXmlPath)
        if ($taskQuery.Exists) {
            $finalCreateArguments += '/F'
        }
        $finalCreate = Invoke-TaskSchedulerCommand -Arguments $finalCreateArguments
        if ($finalCreate.ExitCode -ne 0) {
            $failureMessage = "Scheduler error creating the monthly update task: $($finalCreate.Output)"
            throw 'final-create-failed'
        }
        $taskChanged = $true

        $finalQuery = Get-MonthlyUpdateTaskQuery -TaskPath $taskFullPath
        if (-not $finalQuery.Success -or -not (Test-MonthlyUpdateTaskDefinition -XmlText $finalQuery.XmlText -UpdateScriptPath $updateScriptPath -PackageIds $packageIds -Identity $identity -Enabled $true)) {
            $failureMessage = "The registered task did not match the confirmed schedule. Scheduler output: $($finalQuery.Output)"
            throw 'final-validation-failed'
        }

        $script:MonthlyUpdateTaskEnabled = $true
        Write-Log "Validated monthly update task at $taskFullPath for $($packageIds.Count) selected package(s)." -Level SUCCESS
        Write-Host "Monthly updates are enabled for the selected packages at $taskFullPath." -ForegroundColor Green
        return $true
    }
    catch {
        if ($taskChanged -or $_.Exception.Message -eq 'final-create-failed') {
            if ($taskQuery.Exists -and $previousXmlPath -and (Test-Path -LiteralPath $previousXmlPath -PathType Leaf)) {
                $restore = Invoke-TaskSchedulerCommand -Arguments @('/Create', '/TN', $taskFullPath, '/XML', $previousXmlPath, '/F')
                if ($restore.ExitCode -eq 0) {
                    $restoredQuery = Get-MonthlyUpdateTaskQuery -TaskPath $taskFullPath
                    if ($restoredQuery.Success -and (Test-MonthlyUpdateTaskDefinitionEqual -ExpectedXml $taskQuery.XmlText -ActualXml $restoredQuery.XmlText)) {
                        Write-Host 'The previous application-owned task was restored and verified.' -ForegroundColor Yellow
                    }
                    else {
                        $failureMessage += " Previous task restoration could not be verified. Scheduler output: $($restoredQuery.Output)"
                    }
                }
                else {
                    $failureMessage += " Previous task restoration failed. Scheduler output: $($restore.Output)"
                }
            }
            elseif (-not $taskQuery.Exists) {
                $removeNewTask = Invoke-TaskSchedulerCommand -Arguments @('/Delete', '/TN', $taskFullPath, '/F')
                if ($removeNewTask.ExitCode -ne 0) {
                    $failureMessage += " Cleanup of the unvalidated new task failed. Scheduler output: $($removeNewTask.Output)"
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($failureMessage)) {
            $failureMessage = "Unexpected scheduler error ($($_.Exception.GetType().Name)). No success is claimed."
        }
        Write-Log 'Monthly update task setup failed; no success was reported.' -Level ERROR
        Write-Host "Monthly update task setup failed. $failureMessage" -ForegroundColor Red
        return $false
    }
    finally {
        if ($stagingCreated) {
            $cleanupStage = Invoke-TaskSchedulerCommand -Arguments @('/Delete', '/TN', $stagingTaskPath, '/F')
            if ($cleanupStage.ExitCode -ne 0) {
                Write-Host "The disabled staging task may remain at $stagingTaskPath. Scheduler error: $($cleanupStage.Output)" -ForegroundColor Red
            }
        }
        foreach ($temporaryFile in $temporaryFiles) {
            if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile -PathType Leaf)) {
                Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Disable-MonthlyUpdateTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not ($env:OS -match 'Windows')) {
        Write-Host 'Monthly scheduled updates are available only on Windows. No task was changed.' -ForegroundColor Yellow
        return $false
    }

    $taskFullPath = '\myTech.Today\Monthly Application Updates'
    $updateScriptPath = Join-Path (Join-Path $script:SystemInstallPath 'apps') 'winget-update.ps1'

    if ($WhatIfPreference) {
        $action = 'Remove the application-owned monthly update task'
        [void](Test-InstallerShouldProcess -Target $taskFullPath -Action $action)
        $message = "Would remove the application-owned task at $taskFullPath after ownership validation. No scheduler command was run."
        Write-Host "[PREVIEW] $message" -ForegroundColor Cyan
        return (New-InstallerActionResult -Status Preview -Message $message)
    }

    if ($ConfirmPreference -ne 'None') {
        Write-Host "This removes only the application-owned task at $taskFullPath." -ForegroundColor Yellow
        Write-Host 'Remove monthly updates? (Y/N): ' -NoNewline -ForegroundColor Yellow
        if ((Read-Host) -notmatch '^[Yy]$') {
            Write-Host '[SKIPPED] Removal was declined. No scheduler commands were run.' -ForegroundColor Yellow
            return (New-InstallerActionResult -Status Skipped -Message 'Monthly task removal was declined.')
        }
    }

    if (-not (Test-InstallerShouldProcess -Target $taskFullPath -Action 'Remove the application-owned monthly update task after ownership validation')) {
        Write-Host "[SKIPPED] Removal was not approved. No scheduler commands were run." -ForegroundColor Yellow
        return (New-InstallerActionResult -Status Skipped -Message 'ShouldProcess confirmation was declined.')
    }

    $taskQuery = Get-MonthlyUpdateTaskQuery -TaskPath $taskFullPath
    if (-not $taskQuery.Success) {
        Write-Host "Could not safely inspect the scheduled task. Scheduler error: $($taskQuery.Output)" -ForegroundColor Red
        return $false
    }
    if (-not $taskQuery.Exists) {
        Write-Host "No task exists at $taskFullPath." -ForegroundColor Yellow
        return $true
    }
    if (-not (Test-MonthlyUpdateTaskOwnership -XmlText $taskQuery.XmlText -UpdateScriptPath $updateScriptPath)) {
        Write-Host "The task at $taskFullPath is not recognized as owned by this installer. It was left unchanged." -ForegroundColor Red
        return $false
    }

    $deleteResult = Invoke-TaskSchedulerCommand -Arguments @('/Delete', '/TN', $taskFullPath, '/F')
    if ($deleteResult.ExitCode -ne 0) {
        Write-Host "Could not remove $taskFullPath. Scheduler error: $($deleteResult.Output)" -ForegroundColor Red
        return $false
    }

    Write-Host "Removed the application-owned task at $taskFullPath." -ForegroundColor Green
    return $true
}

function Invoke-TaskSchedulerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        if (-not (Get-Command schtasks.exe -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ ExitCode = 9009; Output = 'schtasks.exe was not found.' }
        }
        $outputLines = @(& schtasks.exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
        return [PSCustomObject]@{
            ExitCode = [int]$exitCode
            Output = ($outputLines -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output = "Scheduler command failed unexpectedly ($($_.Exception.GetType().Name))."
        }
    }
}

function Get-MonthlyUpdateTaskQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskPath
    )

    $result = Invoke-TaskSchedulerCommand -Arguments @('/Query', '/TN', $TaskPath, '/XML')
    if ($result.ExitCode -eq 0) {
        try {
            $document = New-Object System.Xml.XmlDocument
            $document.LoadXml($result.Output)
            return [PSCustomObject]@{ Success = $true; Exists = $true; XmlText = $result.Output; Output = $result.Output }
        }
        catch {
            return [PSCustomObject]@{ Success = $false; Exists = $false; XmlText = $null; Output = 'Task Scheduler returned invalid XML.' }
        }
    }

    if ($result.Output -match '(?i)(cannot find|could not be found|does not exist|task not found)') {
        return [PSCustomObject]@{ Success = $true; Exists = $false; XmlText = $null; Output = $result.Output }
    }

    return [PSCustomObject]@{ Success = $false; Exists = $false; XmlText = $null; Output = $result.Output }
}

function Test-MonthlyUpdateTaskOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlText,
        [Parameter(Mandatory = $true)]
        [string]$UpdateScriptPath
    )

    try {
        $document = New-Object System.Xml.XmlDocument
        $document.LoadXml($XmlText)
        $descriptionNode = $document.SelectSingleNode("//*[local-name()='Description']")
        $commandNode = $document.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Command']")
        $argumentsNode = $document.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Arguments']")
        if (-not $commandNode -or -not $argumentsNode) {
            return $false
        }
        $isPowerShell = $commandNode.InnerText -match '(?i)(^|[\\/])powershell(?:\.exe)?$|^powershell(?:\.exe)?$'
        $targetsUpdater = $argumentsNode.InnerText.IndexOf($UpdateScriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $hasFileArgument = $argumentsNode.InnerText -match '(?i)(^|\s)-File(\s|$)'
        $hasOwnerMarker = $descriptionNode -and $descriptionNode.InnerText.Contains('myTech.Today App Installer monthly update task; ownership=v1')
        return ($isPowerShell -and $targetsUpdater -and $hasFileArgument -and ($hasOwnerMarker -or $targetsUpdater))
    }
    catch {
        return $false
    }
}

function Test-MonthlyUpdateTaskDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlText,
        [Parameter(Mandatory = $true)]
        [string]$UpdateScriptPath,
        [Parameter(Mandatory = $true)]
        [string[]]$PackageIds,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    try {
        $document = New-Object System.Xml.XmlDocument
        $document.LoadXml($XmlText)
        $description = $document.SelectSingleNode("//*[local-name()='Description']").InnerText
        $command = $document.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Command']").InnerText
        $arguments = $document.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Arguments']").InnerText
        $runLevel = $document.SelectSingleNode("//*[local-name()='RunLevel']").InnerText
        $userId = $document.SelectSingleNode("//*[local-name()='UserId']").InnerText
        $logonType = $document.SelectSingleNode("//*[local-name()='LogonType']").InnerText
        $taskEnabledText = $document.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']").InnerText
        $day = $document.SelectSingleNode("//*[local-name()='ScheduleByMonth']/*[local-name()='DaysOfMonth']/*[local-name()='Day']").InnerText
        $scope = ($PackageIds -join ',')
        $hasExpectedAction = $arguments.IndexOf($UpdateScriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $arguments.IndexOf(('-PackageIds "{0}"' -f $scope), [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        return (
            $description.Contains('myTech.Today App Installer monthly update task; ownership=v1') -and
            $command -match '(?i)(^|[\\/])powershell(?:\.exe)?$|^powershell(?:\.exe)?$' -and
            $hasExpectedAction -and
            $runLevel -eq 'HighestAvailable' -and
            $userId -eq $Identity -and
            $logonType -eq 'InteractiveToken' -and
            $taskEnabledText -eq ([string]$Enabled).ToLowerInvariant() -and
            $day -eq '15'
        )
    }
    catch {
        return $false
    }
}

function Test-MonthlyUpdateTaskDefinitionEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedXml,
        [Parameter(Mandatory = $true)][string]$ActualXml
    )
    try {
        $expectedDocument = New-Object System.Xml.XmlDocument
        $actualDocument = New-Object System.Xml.XmlDocument
        $expectedDocument.LoadXml($ExpectedXml)
        $actualDocument.LoadXml($ActualXml)
        return $expectedDocument.OuterXml -ceq $actualDocument.OuterXml
    }
    catch {
        return $false
    }
}

function New-MonthlyUpdateTaskXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdateScriptPath,
        [Parameter(Mandatory = $true)]
        [string[]]$PackageIds,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $enabledText = if ($Enabled) { 'true' } else { 'false' }
    $packageScope = ($PackageIds -join ',')
    $descriptionText = "myTech.Today App Installer monthly update task; ownership=v1. Runs monthly on day 15 at 1:00 PM for selected winget package IDs: $packageScope"
    $actionArguments = '-NoProfile -File "{0}" -PackageIds "{1}"' -f $UpdateScriptPath, $packageScope
    $escapedDescription = [System.Security.SecurityElement]::Escape($descriptionText)
    $escapedIdentity = [System.Security.SecurityElement]::Escape($Identity)
    $escapedArguments = [System.Security.SecurityElement]::Escape($actionArguments)
    $escapedScriptDirectory = [System.Security.SecurityElement]::Escape((Split-Path -Parent $UpdateScriptPath))
    $startBoundary = (Get-Date).Date.AddHours(13).ToString("yyyy-MM-dd'T'HH:mm:ss")

    $xmlText = @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>$escapedIdentity</Author>
    <Description>$escapedDescription</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByMonth>
        <DaysOfMonth><Day>15</Day></DaysOfMonth>
        <Months><January/><February/><March/><April/><May/><June/><July/><August/><September/><October/><November/><December/></Months>
      </ScheduleByMonth>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$escapedIdentity</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>$enabledText</Enabled>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <AllowHardTerminate>true</AllowHardTerminate>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$escapedArguments</Arguments>
      <WorkingDirectory>$escapedScriptDirectory</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    $xmlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('monthly-update-' + [guid]::NewGuid().ToString('N') + '.xml')
    [System.IO.File]::WriteAllText($xmlPath, $xmlText, [System.Text.Encoding]::UTF8)
    return $xmlPath
}

$script:MonthlyUpdateTaskEnabled = $false

#endregion
#endregion

# If -Profile is supplied (and -Action is not explicitly set), use InstallProfile mode
if ($PSBoundParameters.ContainsKey('Profile') -and -not $PSBoundParameters.ContainsKey('Action')) {
    $Action = 'InstallProfile'
}


# Suppress Write-Progress output to prevent spinner graphics from being logged
# Write-Progress uses the progress stream which can be captured in transcripts
$script:OriginalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

# Initialize logging. Preview runs write no log files.
if ($WhatIfPreference) {
    $script:LogPath = $null
    Write-Host '[PREVIEW] File logging is disabled for this dry run.' -ForegroundColor Cyan
}
elseif ($script:LoggingModuleLoaded) {
    # Use generic logging module
    $logPath = Initialize-Log -ScriptName "AppInstaller-CLI" -ScriptVersion $script:ScriptVersion
    if ($logPath) {
        Write-Log "=== App Installer v$script:ScriptVersion Started ===" -Level INFO
        Write-Log "Action: $Action" -Level INFO
        if ($Profile) {
            Write-Log "Profile: $Profile" -Level INFO
        }
        Write-Host "[OK] Logging initialized with generic module" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Generic logging module failed to initialize" -ForegroundColor Yellow
    }
}
else {
    # Fallback to old logging method
    Initialize-Logging
    Write-Log "=== App Installer v$script:ScriptVersion Started ===" -Level INFO
    Write-Log "Action: $Action" -Level INFO
    if ($Profile) {
        Write-Log "Profile: $Profile" -Level INFO
    }
    Write-Host "[OK] Logging initialized with fallback method" -ForegroundColor Green
}

if ($script:StartupHelperFallbackRequired) {
    Write-Log $script:StartupHelperFallbackMessage -Level WARNING
}

# Check for package manager availability
Write-Host "`n[i] Checking for package manager availability..." -ForegroundColor Cyan

# On Windows, check for winget (install on Windows 10 if needed).
# WhatIf may inspect command availability, but it must never bootstrap winget.
# On other platforms, platform-detect.ps1 already set $PackageManager
if ($null -eq $IsWindows -or $IsWindows) {
    if ($WhatIfPreference) {
        $wingetAvailable = Test-WingetAvailable
    }
    else {
        $wingetAvailable = Assert-WingetAvailable
    }
}
else {
    # On non-Windows, we rely on platform-detect.ps1
    $wingetAvailable = $false
    if ($PackageManager -and $PackageManager -ne "none") {
        Write-Host "[OK] Package manager detected: $PackageManager" -ForegroundColor Green
    }
    else {
        Write-Warning "No package manager detected. Some installations may fail."
    }
}

if (-not $wingetAvailable -and ($null -eq $IsWindows -or $IsWindows)) {
    Write-Log "winget is not available on this system" -Level WARNING
    Write-Host "`n[WARN] WARNING: winget (Windows Package Manager) is not available." -ForegroundColor Yellow
    Write-Host "   Many applications require winget for installation." -ForegroundColor Yellow
    Write-Host ""

    if ($WhatIfPreference) {
        Write-Host '[PREVIEW] winget bootstrap was not attempted. The selected package action can still be previewed.' -ForegroundColor Cyan
    }
    else {
        $continue = Read-Host "Continue anyway? (Y/N)"
        if ($continue -ne 'Y') {
            Write-Log "User cancelled due to missing winget" -Level INFO
            exit 0
        }
    }
}
else {
    Write-Host "[OK] winget is available" -ForegroundColor Green
}

# Main execution
try {
    if ($Action -eq 'Menu' -and [Console]::IsInputRedirected -and ($WhatIfPreference -or $ConfirmPreference -eq 'None')) {
        if ($WhatIfPreference) {
            Write-Host '[PREVIEW] The interactive menu needs an application selection. No package, file, network, or scheduler action was performed.' -ForegroundColor Cyan
        }
        else {
            Write-Host '[SKIPPED] The interactive menu needs an explicit action in noninteractive mode. No operation was performed.' -ForegroundColor Yellow
        }
    }
    else {
    switch ($Action) {
        'Menu' {
            # Interactive menu mode
            do {
                $menuData = Show-Menu
                Write-Host "Enter your choice: " -NoNewline -ForegroundColor White
                $choice = Read-Host

                # Handle single letter commands
                if ($choice -eq 'A') {
                    Install-AllApplications
                    Read-KeySafe
                }
                elseif ($choice -eq 'M') {
                    Install-MissingApplications
                    Read-KeySafe
                }
                elseif ($choice -eq 'U') {
                    Check-ForUpdates
                    Read-KeySafe
                }
                elseif ($choice -eq 'T') {
                    Install-MonthlyUpdateTask -MenuData $menuData
                }
                elseif ($choice -eq 'D') {
                    Disable-MonthlyUpdateTask
                }
                elseif ($choice -eq 'E') {
                    # Export Selection
                    Write-Host ""
                    Write-Host "=== Export Installation Profile ===" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Enter application numbers to export (e.g., '1,3,5' or '1-10'):" -ForegroundColor Yellow
                    Write-Host "Or press Enter to cancel" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "Selection: " -NoNewline -ForegroundColor White
                    $exportChoice = Read-Host

                    if ([string]::IsNullOrWhiteSpace($exportChoice)) {
                        Write-Host "[INFO] Export cancelled" -ForegroundColor Cyan
                        Read-KeySafe
                        continue
                    }

                    $selectedApps = Parse-SelectionInput -Input $exportChoice -MenuItems $menuData.MenuItems -Categories $menuData.Categories

                    if ($selectedApps.Count -eq 0) {
                        Write-Host "[ERROR] No valid applications selected" -ForegroundColor Red
                        Read-KeySafe
                        continue
                    }

                    # Create profiles directory if it doesn't exist
                    $profilesDir = $script:ProfilesPath
                    if (-not (Safe-TestPath $profilesDir)) {
                        New-Item -Path $profilesDir -ItemType Directory -Force | Out-Null
                    }

                    # Generate default filename
                    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
                    $computerName = $env:COMPUTERNAME
                    $defaultFileName = "profile-$computerName-$timestamp.json"

                    Write-Host ""
                    Write-Host "Enter filename (or press Enter for default: $defaultFileName):" -ForegroundColor Yellow
                    Write-Host "Filename: " -NoNewline -ForegroundColor White
                    $fileName = Read-Host

                    if ([string]::IsNullOrWhiteSpace($fileName)) {
                        $fileName = $defaultFileName
                    }
                    elseif (-not $fileName.EndsWith('.json')) {
                        $fileName += '.json'
                    }

                    $filePath = Join-Path $profilesDir $fileName

                    $exportedPath = Export-InstallationProfile -SelectedApps $selectedApps -FilePath $filePath

                    if ($exportedPath) {
                        Write-Host ""
                        Write-Host "[SUCCESS] Exported $($selectedApps.Count) application(s) to:" -ForegroundColor Green
                        Write-Host "  $exportedPath" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host ""
                        Write-Host "[ERROR] Failed to export profile. Check the log for details." -ForegroundColor Red
                    }

                    Read-KeySafe
                }
                elseif ($choice -eq 'I') {
                    # Import Selection
                    Write-Host ""
                    Write-Host "=== Import Installation Profile ===" -ForegroundColor Cyan
                    Write-Host ""

                    # List available profiles
                    $profilesDir = $script:ProfilesPath
                    if (Safe-TestPath $profilesDir) {
                        $profiles = Get-ChildItem -Path $profilesDir -Filter "*.json" | Sort-Object LastWriteTime -Descending

                        if ($profiles.Count -gt 0) {
                            Write-Host "Available profiles:" -ForegroundColor Yellow
                            for ($i = 0; $i -lt $profiles.Count; $i++) {
                                $profile = $profiles[$i]
                                Write-Host "  $($i + 1). $($profile.Name) ($(Get-Date $profile.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
                            }
                            Write-Host ""
                            Write-Host "Enter profile number, full path, or press Enter to cancel:" -ForegroundColor Yellow
                            Write-Host "Selection: " -NoNewline -ForegroundColor White
                            $importChoice = Read-Host

                            if ([string]::IsNullOrWhiteSpace($importChoice)) {
                                Write-Host "[INFO] Import cancelled" -ForegroundColor Cyan
                                Read-KeySafe
                                continue
                            }

                            # Check if it's a number
                            if ($importChoice -match '^\d+$') {
                                $profileIndex = [int]$importChoice - 1
                                if ($profileIndex -ge 0 -and $profileIndex -lt $profiles.Count) {
                                    $filePath = $profiles[$profileIndex].FullName
                                }
                                else {
                                    Write-Host "[ERROR] Invalid profile number" -ForegroundColor Red
                                    Read-KeySafe
                                    continue
                                }
                            }
                            else {
                                $filePath = $importChoice
                            }
                        }
                        else {
                            Write-Host "No profiles found in $profilesDir" -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Enter full path to profile file, or press Enter to cancel:" -ForegroundColor Yellow
                            Write-Host "Path: " -NoNewline -ForegroundColor White
                            $filePath = Read-Host

                            if ([string]::IsNullOrWhiteSpace($filePath)) {
                                Write-Host "[INFO] Import cancelled" -ForegroundColor Cyan
                                Read-KeySafe
                                continue
                            }
                        }
                    }
                    else {
                        Write-Host "Profiles directory not found: $profilesDir" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Enter full path to profile file, or press Enter to cancel:" -ForegroundColor Yellow
                        Write-Host "Path: " -NoNewline -ForegroundColor White
                        $filePath = Read-Host

                        if ([string]::IsNullOrWhiteSpace($filePath)) {
                            Write-Host "[INFO] Import cancelled" -ForegroundColor Cyan
                            Read-KeySafe
                            continue
                        }
                    }

                    $result = Import-InstallationProfile -FilePath $filePath

                    if ($result.Success) {
                        Write-Host ""
                        Write-Host "[SUCCESS] Profile imported successfully" -ForegroundColor Green
                        Write-Host "  Found $($result.Applications.Count) application(s)" -ForegroundColor Cyan

                        if ($result.MissingApps.Count -gt 0) {
                            Write-Host ""
                            Write-Host "[WARNING] $($result.MissingApps.Count) application(s) from profile not found in current installer:" -ForegroundColor Yellow
                            foreach ($missingApp in $result.MissingApps) {
                                Write-Host "  - $missingApp" -ForegroundColor Gray
                            }
                        }

                        Write-Host ""
                        Write-Host "Do you want to install these $($result.Applications.Count) application(s)? (Y/N): " -NoNewline -ForegroundColor Yellow
                        $confirmChoice = Read-Host

                        if ($confirmChoice -match '^[Yy]') {
                            Install-SelectedApplications -Apps $result.Applications
                        }
                        else {
                            Write-Host "[INFO] Installation cancelled" -ForegroundColor Cyan
                        }
                    }
                    else {
                        Write-Host ""
                        Write-Host "[ERROR] Failed to import profile:" -ForegroundColor Red
                        Write-Host "  $($result.Message)" -ForegroundColor Gray
                    }

                    Read-KeySafe
                }
                elseif ($choice -eq 'X') {
                    # Uninstall Selected Applications
                    Write-Host ""
                    Write-Host "=== Uninstall Applications ===" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Enter application numbers to uninstall (e.g., '1,3,5' or '1-10'):" -ForegroundColor Yellow
                    Write-Host "Or press Enter to cancel" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "Selection: " -NoNewline -ForegroundColor White
                    $uninstallChoice = Read-Host

                    if ([string]::IsNullOrWhiteSpace($uninstallChoice)) {
                        Write-Host "[INFO] Uninstall cancelled" -ForegroundColor Cyan
                        Read-KeySafe
                        continue
                    }

                    $selectedApps = Parse-SelectionInput -Input $uninstallChoice -MenuItems $menuData.MenuItems -Categories $menuData.Categories

                    if ($selectedApps.Count -eq 0) {
                        Write-Host "[ERROR] No valid applications selected" -ForegroundColor Red
                        Read-KeySafe
                        continue
                    }

                    $appsToUninstall = @($selectedApps)
                    $notInstalledApps = @()

                    # Confirm the selected targets before querying the package manager.
                    Write-Host ""
                    Write-Host "You selected $($appsToUninstall.Count) application(s) to uninstall if installed:" -ForegroundColor Yellow
                    Write-Host ""
                    foreach ($app in $appsToUninstall) {
                        Write-Host "  - $($app.Name)" -ForegroundColor White
                    }

                    $confirmUninstall = 'Y'
                    if ($WhatIfPreference) {
                        Write-Host '[PREVIEW] Installed-package state was not queried.' -ForegroundColor Cyan
                    }
                    elseif ($ConfirmPreference -ne 'None') {
                        Write-Host ""
                        Write-Host "This action cannot be undone. Proceed with uninstall? (Y/N): " -NoNewline -ForegroundColor Yellow
                        $confirmUninstall = Read-Host
                    }

                    if ($confirmUninstall -match '^[Yy]') {
                        if (-not $WhatIfPreference) {
                            $installedApps = Get-InstalledApplications
                            $script:InstalledApps = $installedApps
                            $appsToUninstall = @()
                            foreach ($app in $selectedApps) {
                                if ($installedApps.ContainsKey($app.Name)) {
                                    $appsToUninstall += $app
                                }
                                else {
                                    $notInstalledApps += $app
                                }
                            }
                            if ($notInstalledApps.Count -gt 0) {
                                Write-Host "Not installed - will skip ($($notInstalledApps.Count)):" -ForegroundColor Gray
                                foreach ($app in $notInstalledApps) {
                                    Write-Host "  - $($app.Name)" -ForegroundColor DarkGray
                                }
                            }
                        }

                        if ($appsToUninstall.Count -eq 0) {
                            Write-Host '[SKIPPED] None of the selected applications are installed.' -ForegroundColor Cyan
                            Read-KeySafe
                            continue
                        }

                        # Uninstall applications
                        $successCount = 0
                        $failCount = 0
                        $previewCount = 0
                        $skippedCount = 0
                        $currentIndex = 0

                        Write-Host ""
                        Write-Host "+===================================================================+" -ForegroundColor Cyan
                        Write-Host "|                    Uninstalling Applications                      |" -ForegroundColor Cyan
                        Write-Host "+===================================================================+" -ForegroundColor Cyan
                        Write-Host ""

                        foreach ($app in $appsToUninstall) {
                            $currentIndex++
                            $result = Uninstall-Application -App $app -CurrentIndex $currentIndex -TotalCount $appsToUninstall.Count
                            switch (Get-InstallerActionStatus -Result $result) {
                                'Completed' { $successCount++ }
                                'Preview' { $previewCount++ }
                                'Skipped' { $skippedCount++ }
                                default { $failCount++ }
                            }
                        }

                        Write-Host ""
                        Write-Host "+===================================================================+" -ForegroundColor Cyan
                        Write-Host "|                    Uninstall Complete                             |" -ForegroundColor Cyan
                        Write-Host "+===================================================================+" -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host "Successful: $successCount" -ForegroundColor Green
                        Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
                        if ($previewCount -gt 0) {
                            Write-Host "Preview: $previewCount (not run)" -ForegroundColor Cyan
                        }
                        if ($skippedCount -gt 0) {
                            Write-Host "Skipped: $skippedCount (not run)" -ForegroundColor Yellow
                        }
                        Write-Host ""
                    }
                    else {
                        Write-Host "[SKIPPED] Uninstall was declined. No package-manager command was run." -ForegroundColor Cyan
                    }

                    Read-KeySafe
                }
                elseif ($choice -eq 'S' -or $choice -eq 'R') {
                    # Refresh will happen automatically on next loop
                    continue
                }
                elseif ($choice -eq 'Q') {
                    Write-Log "User exited application" -Level INFO
                    break
                }
                # Handle single number (backward compatibility)
                elseif ($choice -match '^\d+$') {
                    $index = [int]$choice
                    if ($menuData.MenuItems.ContainsKey($index)) {
                        Install-Application -App $menuData.MenuItems[$index]
                        Read-KeySafe
                    }
                    else {
                        Write-Host "Invalid selection." -ForegroundColor Red
                        Read-KeySafe
                    }
                }
                # Handle multi-select, range, or category selection
                elseif ($choice -match '[\d,\-\s]|^C:') {
                    $selectedApps = Parse-SelectionInput -Input $choice -MenuItems $menuData.MenuItems -Categories $menuData.Categories

                    if ($selectedApps.Count -gt 0) {
                        Install-SelectedApplications -Apps $selectedApps
                        Read-KeySafe
                    }
                    else {
                        Write-Host "No valid applications selected." -ForegroundColor Red
                        Read-KeySafe
                    }
                }
                else {
                    Write-Host "Invalid choice." -ForegroundColor Red
                    Read-KeySafe
                }
            } while ($true)
        }

        'InstallAll' {
            Install-AllApplications
        }

        'InstallMissing' {
            Install-MissingApplications
        }

        'EnableMonthlyUpdates' {
            $menuData = Show-Menu
            Install-MonthlyUpdateTask -MenuData $menuData
        }

        'DisableMonthlyUpdates' {
            Disable-MonthlyUpdateTask
        }

        'InstallProfile' {
            if (-not $Profile) {
                Write-Host "`n[ERROR] -Profile parameter is required when using Action 'InstallProfile'." -ForegroundColor Red
                Write-Log "InstallProfile action requested but -Profile parameter was not supplied." -Level ERROR
                break
            }

            Write-Host "`n+===================================================================+" -ForegroundColor Cyan
            Write-Host "|                 Installing from Profile Selection                 |" -ForegroundColor Cyan
            Write-Host "+===================================================================+" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "[INFO] Importing profile from: $Profile" -ForegroundColor Cyan
            Write-Log "Starting profile-based installation from: $Profile" -Level INFO

            $result = Import-InstallationProfile -FilePath $Profile

            if (-not $result.Success) {
                Write-Host "`n[ERROR] Failed to import profile:" -ForegroundColor Red
                Write-Host "  $($result.Message)" -ForegroundColor Gray
                Write-Log "Profile import failed: $($result.Message)" -Level ERROR
                break
            }

            Write-Host ""
            Write-Host "[SUCCESS] Profile imported successfully" -ForegroundColor Green
            Write-Host "  Found $($result.Applications.Count) valid application(s)" -ForegroundColor Cyan

            if ($result.MissingApps.Count -gt 0) {
                Write-Host ""
                Write-Host "[WARNING] $($result.MissingApps.Count) application(s) from profile not found in current installer:" -ForegroundColor Yellow
                foreach ($missingApp in $result.MissingApps) {
                    Write-Host "  - $missingApp" -ForegroundColor DarkYellow
                    Write-Log "Profile references application not present in installer list: $missingApp" -Level WARNING
                }
            }

            if ($result.Applications.Count -eq 0) {
                Write-Host ""
                Write-Host "[INFO] Profile contains no applications to install." -ForegroundColor Yellow
                Write-Log "Profile import resulted in zero valid applications to install." -Level WARNING
                break
            }

            Install-SelectedApplications -Apps $result.Applications
        }

        'Status' {
            $menuItems = Show-Menu
            Write-Host "`nStatus display complete." -ForegroundColor Green
        }
    }
    }
}
catch {
    Write-Log "Fatal error: $_" -Level ERROR
    Write-Host "`n[ERROR] Fatal error: $_" -ForegroundColor Red
    exit 1
}
finally {
    Write-Log "=== App Installer Completed ===" -Level INFO

    if (-not $script:MonthlyUpdateTaskEnabled) {
        Write-Host 'Automatic monthly updates are not enabled. You can run updates manually from the installer.' -ForegroundColor Gray
    }
}

# Display marketing/contact information
Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host "|          Thank you for using myTech.Today App Installer!         |" -ForegroundColor Cyan
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Need IT Support? We're Here to Help!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  myTech.Today is a full-service Managed Service Provider (MSP)" -ForegroundColor White
Write-Host "  serving businesses and individuals in the Barrington, IL area" -ForegroundColor White
Write-Host "  and throughout Chicagoland." -ForegroundColor White
Write-Host ""
Write-Host "  We specialize in:" -ForegroundColor Green
Write-Host "    - IT Consulting and Support" -ForegroundColor Gray
Write-Host "    - Custom PowerShell Automation" -ForegroundColor Gray
Write-Host "    - Infrastructure Optimization" -ForegroundColor Gray
Write-Host "    - Cloud Integration (Azure, AWS, Microsoft 365)" -ForegroundColor Gray
Write-Host "    - System Administration and Security" -ForegroundColor Gray
Write-Host "    - Database Management and Custom Development" -ForegroundColor Gray
Write-Host ""
Write-Host "  Contact Us:" -ForegroundColor Yellow
Write-Host "    Email:   sales@mytech.today" -ForegroundColor White
Write-Host "    Phone:   (847) 767-4914" -ForegroundColor White
Write-Host "    Web:     https://mytech.today" -ForegroundColor Cyan

Write-Host ""
Write-Host "  Serving Chicagoland with 20+ years of IT expertise!" -ForegroundColor Green
Write-Host ""
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host ""

# Cleanup: Clear large script-level variables to free memory
$script:Applications = @()
$script:InstalledApps = @{}
$script:SelectedApps = @()

# Force garbage collection to free memory
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

exit 0

<#
.NOTES
    CROSS-PLATFORM TESTING GUIDANCE
    ================================

    This script has been refactored for cross-platform compatibility.
    Please test on all supported platforms:

    WINDOWS TESTING:
    ----------------
    1. Windows PowerShell Desktop 5.1:
       - Run as Administrator
       - Test winget installation and app installation
       - Verify paths: %USERPROFILE%\myTech.Today\AppInstaller
       - Test GUI fallback: .\install-gui.ps1

    2. PowerShell Core 7.6.7:
       - Run as Administrator
       - Test all features
       - Verify cross-platform variables work

    macOS TESTING:
    --------------
    1. Install PowerShell 7.6.7:
       brew install --cask powershell

    2. Run the installer:
       pwsh ./install.ps1

    3. Verify:
       - Homebrew detection works
       - Paths: ~/.mytech-today/app-installer
       - Application filtering shows macOS apps
       - Brew cask/formula installations work

    4. Test GUI script graceful degradation:
       pwsh ./app-installer.ps1
       (Should offer CLI fallback if the Windows Desktop runtime is unavailable)

    LINUX TESTING:
    --------------
    1. Install PowerShell 7.6.7:
       - Follow Microsoft's PowerShell 7.6 installation instructions for your distribution
       - Arch: yay -S powershell-bin

    2. Run the installer:
       pwsh ./install.ps1

    3. Verify:
       - Package manager detection (apt/dnf/pacman/snap)
       - Paths: ~/.mytech-today/app-installer
       - Application filtering shows Linux apps
       - Package installations work

    4. Test GUI script graceful degradation:
       pwsh ./app-installer.ps1
       (Should offer CLI fallback)

    COMMON TESTS (All Platforms):
    ------------------------------
    1. Interactive menu navigation
    2. Multi-select (e.g., "1,3,5-10")
    3. Category selection (e.g., "C:Browsers")
    4. Profile import/export
    5. Status display
    6. Logging functionality
    7. Error handling

    KNOWN PLATFORM LIMITATIONS:
    ---------------------------
    - GUI (install-gui.ps1): Windows only (requires Windows Forms)
    - Some apps may not be available on all platforms
    - Version detection may vary by package manager
    - Admin/sudo requirements vary by package manager

    TROUBLESHOOTING:
    ----------------
    - If platform-detect.ps1 not found: Ensure it's in the same directory
    - If apps-manifest.json is missing or invalid: stop before application actions
    - If core module not found: Basic functionality still works
    - Package manager not detected: Install manually (winget/brew/apt/etc.)
#>
