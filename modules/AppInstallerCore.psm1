<#
.SYNOPSIS
    Core shared module for myTech.Today Application Installer.

.DESCRIPTION
    Provides shared functionality for both GUI and CLI installers including:
    - Application registry management
    - Cross-platform path handling
    - Installation orchestration
    - Profile import/export
    - Common utility functions

.NOTES
    File Name      : AppInstallerCore.psm1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Version        : 1.0.0
#>

#region Module Variables

$script:ModuleVersion = '1.0.0'
$script:ModuleRoot = $PSScriptRoot

#endregion

#region Path Management

function Get-InstallerBasePath {
    <#
    .SYNOPSIS
        Gets the cross-platform base path for the installer.

    .DESCRIPTION
        Returns the appropriate base path based on the current platform:
        - Windows: $env:USERPROFILE\myTech.Today\AppInstaller
        - macOS: $HOME/Library/Application Support/myTech.Today/AppInstaller
        - Linux: $HOME/.local/share/myTech.Today/AppInstaller
    #>
    [CmdletBinding()]
    param()

    if ($IsWindows -or ($null -eq $IsWindows)) {
        # Windows or PowerShell 5.1
        return Join-Path $env:USERPROFILE "myTech.Today\AppInstaller"
    }
    elseif ($IsMacOS) {
        # macOS - use standard Application Support directory
        return Join-Path $HOME "Library/Application Support/myTech.Today/AppInstaller"
    }
    else {
        # Linux - use XDG Base Directory specification
        $xdgDataHome = $env:XDG_DATA_HOME
        if ([string]::IsNullOrWhiteSpace($xdgDataHome)) {
            $xdgDataHome = Join-Path $HOME ".local/share"
        }
        return Join-Path $xdgDataHome "myTech.Today/AppInstaller"
    }
}

function Get-InstallerLogPath {
    <#
    .SYNOPSIS
        Gets the cross-platform log path for the installer.

    .DESCRIPTION
        Returns the appropriate log path based on the current platform:
        - Windows: $env:USERPROFILE\myTech.Today\logs
        - macOS: $HOME/Library/Logs/myTech.Today
        - Linux: $HOME/.local/share/myTech.Today/logs (or $XDG_DATA_HOME/myTech.Today/logs)
    #>
    [CmdletBinding()]
    param()

    if ($IsWindows -or ($null -eq $IsWindows)) {
        # Windows or PowerShell 5.1
        return Join-Path $env:USERPROFILE "myTech.Today\logs"
    }
    elseif ($IsMacOS) {
        # macOS - use standard Logs directory
        return Join-Path $HOME "Library/Logs/myTech.Today"
    }
    else {
        # Linux - use XDG Base Directory specification
        $xdgDataHome = $env:XDG_DATA_HOME
        if ([string]::IsNullOrWhiteSpace($xdgDataHome)) {
            $xdgDataHome = Join-Path $HOME ".local/share"
        }
        return Join-Path $xdgDataHome "myTech.Today/logs"
    }
}

function Get-InstallerAppsPath {
    <#
    .SYNOPSIS
        Gets the path to the apps directory.
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Get-InstallerBasePath) "apps"
}

function Get-InstallerProfilesPath {
    <#
    .SYNOPSIS
        Gets the path to the profiles directory.
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Get-InstallerBasePath) "profiles"
}

function Initialize-InstallerDirectories {
    <#
    .SYNOPSIS
        Creates all necessary installer directories if they don't exist.
    #>
    [CmdletBinding()]
    param()

    $paths = @(
        (Get-InstallerBasePath),
        (Get-InstallerLogPath),
        (Get-InstallerAppsPath),
        (Get-InstallerProfilesPath)
    )

    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            Write-Verbose "Creating directory: $path"
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

#endregion

#region Application Registry

function Get-ApplicationRegistry {
    <#
    .SYNOPSIS
        Loads the application registry from apps-manifest.json or returns hardcoded list.
    
    .DESCRIPTION
        Attempts to load applications from apps-manifest.json first.
        Falls back to hardcoded application list if manifest is not available.
    
    .OUTPUTS
        Array of PSCustomObject representing available applications.
    #>
    [CmdletBinding()]
    param(
        [string]$ManifestPath
    )

    # Try to load from manifest file
    if (-not $ManifestPath) {
        $ManifestPath = Join-Path $PSScriptRoot "..\apps-manifest.json"
    }

    if (Test-Path $ManifestPath) {
        try {
            Write-Verbose "Loading application registry from: $ManifestPath"
            $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
            
            # Convert manifest apps to PSCustomObject array
            $applications = @()
            foreach ($app in $manifest.apps) {
                $applications += [PSCustomObject]@{
                    Name = $app.displayName
                    ScriptName = "$($app.name).ps1"
                    WingetId = $app.packages.winget
                    Category = $app.category
                    Description = $app.description
                    Platform = $app.platform
                    BrewCask = $app.packages.brewCask
                    BrewFormula = $app.packages.brewFormula
                    AptPackage = $app.packages.apt
                    DnfPackage = $app.packages.dnf
                    PacmanPackage = $app.packages.pacman
                    SnapPackage = $app.packages.snap
                }
            }

            Write-Verbose "Loaded $($applications.Count) applications from manifest"
            return $applications
        }
        catch {
            Write-Warning "Failed to load apps-manifest.json: $_"
            Write-Warning "Falling back to hardcoded application list"
        }
    }

    # Fallback: Return hardcoded application list (subset for demonstration)
    Write-Verbose "Using hardcoded application registry"
    return Get-HardcodedApplicationRegistry
}

function Get-HardcodedApplicationRegistry {
    <#
    .SYNOPSIS
        Returns a hardcoded application registry as fallback.
    #>
    [CmdletBinding()]
    param()

    # This is a subset - the full list would be too large
    # In production, this should match the apps-manifest.json content
    return @(
        [PSCustomObject]@{ Name = "Google Chrome"; ScriptName = "chrome.ps1"; WingetId = "Google.Chrome"; Category = "Browsers"; Description = "Fast, secure web browser by Google"; Platform = "All" }
        [PSCustomObject]@{ Name = "Firefox"; ScriptName = "firefox.ps1"; WingetId = "Mozilla.Firefox"; Category = "Browsers"; Description = "Open-source browser with privacy features"; Platform = "All" }
        [PSCustomObject]@{ Name = "Visual Studio Code"; ScriptName = "vscode.ps1"; WingetId = "Microsoft.VisualStudioCode"; Category = "Development"; Description = "Powerful code editor with extensions"; Platform = "All" }
        [PSCustomObject]@{ Name = "Git"; ScriptName = "git.ps1"; WingetId = "Git.Git"; Category = "Development"; Description = "Distributed version control system"; Platform = "All" }
        [PSCustomObject]@{ Name = "VLC Media Player"; ScriptName = "vlc.ps1"; WingetId = "VideoLAN.VLC"; Category = "Media"; Description = "Versatile media player for all formats"; Platform = "All" }
        [PSCustomObject]@{ Name = "7-Zip"; ScriptName = "7zip.ps1"; WingetId = "7zip.7zip"; Category = "Utilities"; Description = "High-compression file archiver"; Platform = "All" }
    )
}

function Select-ApplicationsByPlatform {
    <#
    .SYNOPSIS
        Filters applications based on current platform.

    .PARAMETER Applications
        Array of application objects to filter.

    .PARAMETER CurrentPlatform
        Current platform (Windows, macOS, Linux).

    .OUTPUTS
        Filtered array of applications available on current platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Applications,

        [Parameter(Mandatory)]
        [string]$CurrentPlatform
    )

    return $Applications | Where-Object {
        $_.Platform -eq "All" -or $_.Platform -eq $CurrentPlatform
    }
}

#endregion

#region Installation Functions

function Invoke-AppInstallation {
    <#
    .SYNOPSIS
        Invokes installation of an application by running its script.

    .PARAMETER AppScriptName
        Name of the app script file (e.g., "chrome.ps1").

    .PARAMETER AppsPath
        Path to the apps directory.

    .OUTPUTS
        Exit code from the installation script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppScriptName,

        [Parameter(Mandatory)]
        [string]$AppsPath
    )

    $scriptPath = Join-Path $AppsPath $AppScriptName

    if (-not (Test-Path $scriptPath)) {
        Write-Error "App script not found: $scriptPath"
        return 1
    }

    try {
        Write-Verbose "Executing: $scriptPath"
        & $scriptPath
        return $LASTEXITCODE
    }
    catch {
        Write-Error "Failed to execute app script: $_"
        return 1
    }
}

#endregion

#region Profile Management

function Import-InstallationProfile {
    <#
    .SYNOPSIS
        Imports an installation profile from JSON file.

    .PARAMETER ProfilePath
        Path to the profile JSON file.

    .OUTPUTS
        Array of application names from the profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        throw "Profile file not found: $ProfilePath"
    }

    try {
        $profileData = Get-Content $ProfilePath -Raw | ConvertFrom-Json

        if ($profileData.applications) {
            return $profileData.applications
        }
        elseif ($profileData.apps) {
            return $profileData.apps
        }
        else {
            throw "Profile does not contain 'applications' or 'apps' property"
        }
    }
    catch {
        throw "Failed to import profile: $_"
    }
}

function Export-InstallationProfile {
    <#
    .SYNOPSIS
        Exports selected applications to a profile JSON file.

    .PARAMETER Applications
        Array of application names to export.

    .PARAMETER ProfilePath
        Path where the profile should be saved.

    .PARAMETER ProfileName
        Name of the profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Applications,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [string]$ProfileName = "Custom Profile"
    )

    $profileData = @{
        name = $ProfileName
        version = "1.0"
        created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        applications = $Applications
    }

    try {
        $profileData | ConvertTo-Json -Depth 10 | Set-Content -Path $ProfilePath -Encoding UTF8
        Write-Verbose "Profile exported to: $ProfilePath"
    }
    catch {
        throw "Failed to export profile: $_"
    }
}

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
    'Get-InstallerBasePath',
    'Get-InstallerLogPath',
    'Get-InstallerAppsPath',
    'Get-InstallerProfilesPath',
    'Initialize-InstallerDirectories',
    'Get-ApplicationRegistry',
    'Select-ApplicationsByPlatform',
    'Invoke-AppInstallation',
    'Import-InstallationProfile',
    'Export-InstallationProfile'
)

#endregion


