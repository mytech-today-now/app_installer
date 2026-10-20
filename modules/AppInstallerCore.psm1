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
    Prerequisite   : Windows PowerShell Desktop 5.1 or PowerShell Core 7.6.7 per compatibility.json
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
        Loads the complete application registry from apps-manifest.json.
    
    .DESCRIPTION
        Requires the complete apps-manifest.json catalog. Missing or invalid
        catalog data is an error so callers cannot mistake a partial catalog for
        a complete installation.
    
    .OUTPUTS
        Array of PSCustomObject representing available applications.
    #>
    [CmdletBinding()]
    param(
        [string]$ManifestPath
    )

    # Try to load from manifest file
    if (-not $ManifestPath) {
        $ManifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\apps-manifest.json'))
    }

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Required application catalog is missing: $ManifestPath"
    }

    if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
        try {
            Write-Verbose "Loading application registry from: $ManifestPath"
            $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $manifest.apps -or @($manifest.apps).Count -eq 0) {
                throw 'The application catalog does not contain an apps collection.'
            }
            
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
            throw "Failed to load the complete apps-manifest.json catalog. No fallback catalog was used. $($_.Exception.Message)"
        }
    }

    throw 'The complete application catalog became unavailable during loading. No partial catalog was used.'
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

function ConvertTo-AppScriptProcessArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Argument
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0

    for ($index = 0; $index -lt $Argument.Length; $index++) {
        $character = $Argument[$index]
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function New-AppScriptExecutionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShellSuccess', 'NativeProcessSuccess', 'Failure', 'Unknown')]
        [string]$Status,

        [AllowNull()]
        [object]$ExitCode,

        [Parameter(Mandatory = $true)]
        [string]$ResultKind,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [PSCustomObject]@{
        Status = $Status
        ExitCode = if ($null -eq $ExitCode) { $null } else { [int]$ExitCode }
        ResultKind = $ResultKind
        Message = $Message
    }
}

function Invoke-AppScript {
    <#
    .SYNOPSIS
        Runs a custom app script in a fresh PowerShell process and returns an explicit result.

    .DESCRIPTION
        The child process isolates the script from the caller's native exit-code state. A zero
        exit code is successful only when the isolated runner records a result. A script that
        finishes without setting a PowerShell or native process result is Unknown and must not
        be reported as completed.
        The returned object contains Status, ExitCode, ResultKind, and Message. Status is
        PowerShellSuccess for a declared PowerShell result, NativeProcessSuccess for a declared
        native result, Failure for a nonzero process result or parse failure, and Unknown when
        execution or its outcome cannot be confirmed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ScriptArguments = @()
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return New-AppScriptExecutionResult -Status Failure -ExitCode 1 -ResultKind 'None' `
            -Message "App script not found: $ScriptPath"
    }

    $resolvedScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $resolvedScriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $parseMessage = [string]$parseErrors[0].Message
        return New-AppScriptExecutionResult -Status Failure -ExitCode 1 -ResultKind 'None' `
            -Message "App script could not be parsed: $parseMessage"
    }

    $nativeResultMarker = @($scriptAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.VariablePath.UserPath -ieq 'LASTEXITCODE'
            }, $true)).Count -gt 0

    $nativeHelperNames = @('Install-CrossPlatformApp', 'Invoke-PackageManagerProcess')
    if (-not $nativeResultMarker) {
        $nativeResultMarker = @($scriptAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $nativeHelperNames -contains $node.GetCommandName()
                }, $true)).Count -gt 0
    }

    $powerShellName = if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($IsWindows -or $env:OS -match 'Windows') { 'pwsh.exe' } else { 'pwsh' }
    }
    else {
        'powershell.exe'
    }
    $powerShellPath = Join-Path $PSHOME $powerShellName
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        $powerShellCommand = Get-Command -Name $powerShellName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($powerShellCommand) {
            $powerShellPath = if ($powerShellCommand.Path) { $powerShellCommand.Path } else { $powerShellCommand.Source }
        }
        else {
            return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
                -Message 'A PowerShell executable could not be resolved. The app script was not started.'
        }
    }

    $runnerPath = Join-Path $PSScriptRoot 'AppScriptProcessRunner.ps1'
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
        return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
            -Message 'The custom app script runner is missing. The app script was not started.'
    }

    $process = $null
    $resultFilePath = $null
    try {
        $resultFilePath = [System.IO.Path]::GetTempFileName()
        $processArguments = @('-NoProfile', '-File', $runnerPath, $resolvedScriptPath, $resultFilePath) + @($ScriptArguments)
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $powerShellPath
        $processInfo.UseShellExecute = $false
        $argumentListProperty = $processInfo.GetType().GetProperty('ArgumentList')
        if ($argumentListProperty) {
            $argumentList = $argumentListProperty.GetValue($processInfo, $null)
            foreach ($processArgument in $processArguments) {
                [void]$argumentList.Add([string]$processArgument)
            }
        }
        else {
            $processInfo.Arguments = (($processArguments | ForEach-Object {
                        ConvertTo-AppScriptProcessArgument -Argument ([string]$_)
                    }) -join ' ')
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        if (-not $process.Start()) {
            return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
                -Message 'The app script process did not start. Its result is unknown.'
        }

        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $resultMarker = if (Test-Path -LiteralPath $resultFilePath -PathType Leaf) {
            [System.IO.File]::ReadAllText($resultFilePath)
        }
        else {
            $null
        }
        $resultKind = if ($nativeResultMarker) { 'NativeProcess' } else { 'PowerShell' }

        if ($exitCode -ne 0) {
            return New-AppScriptExecutionResult -Status Failure -ExitCode $exitCode -ResultKind $resultKind `
                -Message "The app script returned exit code $exitCode."
        }

        if ($resultMarker -eq 'unknown') {
            return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
                -Message 'The app script completed without declaring an outcome.'
        }

        if ($resultMarker -ne 'declared') {
            return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
                -Message 'The app script process exited without a readable result declaration.'
        }

        $successStatus = if ($nativeResultMarker) { 'NativeProcessSuccess' } else { 'PowerShellSuccess' }
        return New-AppScriptExecutionResult -Status $successStatus -ExitCode 0 -ResultKind $resultKind `
            -Message 'The app script completed successfully.'
    }
    catch {
        return New-AppScriptExecutionResult -Status Unknown -ExitCode $null -ResultKind 'None' `
            -Message "The app script process result could not be confirmed: $($_.Exception.Message)"
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
        if ($resultFilePath -and (Test-Path -LiteralPath $resultFilePath -PathType Leaf)) {
            Remove-Item -LiteralPath $resultFilePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-AppInstallation {
    <#
    .SYNOPSIS
        Invokes installation of an application by running its script.

    .PARAMETER AppScriptName
        Name of the app script file (e.g., "chrome.ps1").

    .PARAMETER AppsPath
        Path to the apps directory.

    .OUTPUTS
        Explicit app script result with Status, ExitCode, ResultKind, and Message properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppScriptName,

        [Parameter(Mandatory)]
        [string]$AppsPath
    )

    $scriptPath = Join-Path $AppsPath $AppScriptName
    Write-Verbose "Executing in an isolated PowerShell process: $scriptPath"
    return Invoke-AppScript -ScriptPath $scriptPath
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
    'Invoke-AppScript',
    'Invoke-AppInstallation',
    'Import-InstallationProfile',
    'Export-InstallationProfile'
)

#endregion


