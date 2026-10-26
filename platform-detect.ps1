<#
.SYNOPSIS
    Cross-platform detection module for app installers. 
.DESCRIPTION
    Provides platform detection, package manager abstraction, and helper
    functions for cross-platform PowerShell app installer scripts.
.NOTES
    File Name      : platform-detect.ps1
    Author         : myTech.Today
    Version        : 2.1.0
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

# Keep WinGet package identity and argv rules in the shared core module.
$script:AppInstallerCorePath = Join-Path $PSScriptRoot 'modules\AppInstallerCore.psm1'
if (Test-Path -LiteralPath $script:AppInstallerCorePath -PathType Leaf) {
    Import-Module -Name $script:AppInstallerCorePath -ErrorAction Stop -Verbose:$false | Out-Null
}

#region Platform Detection Variables

# Detect platform - PowerShell 7+ has $IsWindows, $IsMacOS, $IsLinux
# PowerShell 5.1 (Windows only) does not have these
if ($null -eq $IsWindows) {
    # PowerShell 5.1 - must be Windows
    $script:Platform = "Windows"
}
elseif ($IsWindows) {
    $script:Platform = "Windows"
}
elseif ($IsMacOS) {
    $script:Platform = "macOS"
}
elseif ($IsLinux) {
    $script:Platform = "Linux"
}
else {
    # Fallback: check env var
    if ($env:OS -match 'Windows') {
        $script:Platform = "Windows"
    }
    else {
        $script:Platform = "Unknown"
    }
}

# Linux distribution detection
$script:LinuxDistro = $null
if ($script:Platform -eq "Linux") {
    # Check /etc/os-release first (most common)
    if (Test-Path "/etc/os-release") {
        $osRelease = Get-Content "/etc/os-release" -ErrorAction SilentlyContinue
        $idLine = $osRelease | Where-Object { $_ -match '^ID=' }
        if ($idLine) {
            $distroId = ($idLine -replace '^ID=', '').Trim('"').ToLower()
            $script:LinuxDistro = switch ($distroId) {
                'debian' { 'Debian' }
                'ubuntu' { 'Ubuntu' }
                'fedora' { 'Fedora' }
                'rhel' { 'RHEL' }
                'centos' { 'RHEL' }
                'arch' { 'Arch' }
                'manjaro' { 'Arch' }
                default { 'Unknown' }
            }
        }
    }
    # Fallback: check distro-specific files
    elseif (Test-Path "/etc/debian_version") {
        $script:LinuxDistro = "Debian"
    }
    elseif (Test-Path "/etc/redhat-release") {
        $script:LinuxDistro = "RHEL"
    }
    else {
        $script:LinuxDistro = "Unknown"
    }
}

#endregion

#region Package Manager Detection

$script:PackageManager = $null

switch ($script:Platform) {
    "Windows" {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $script:PackageManager = "winget"
        }
    }
    "macOS" {
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            $script:PackageManager = "brew"
        }
    }
    "Linux" {
        # Check in priority order: apt, dnf, pacman, snap
        if (Get-Command apt -ErrorAction SilentlyContinue) {
            $script:PackageManager = "apt"
        }
        elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
            $script:PackageManager = "dnf"
        }
        elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
            $script:PackageManager = "pacman"
        }
        elseif (Get-Command snap -ErrorAction SilentlyContinue) {
            $script:PackageManager = "snap"
        }
    }
}

#endregion

#region Admin/Elevation Detection

$script:IsAdmin = $false

if ($script:Platform -eq "Windows") {
    # Windows: Check if running as Administrator
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    $script:IsAdmin = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}
else {
    # macOS/Linux: Check if running as root (UID 0)
    if ($null -ne $env:EUID) {
        $script:IsAdmin = ($env:EUID -eq "0")
    }
    elseif (Get-Command id -ErrorAction SilentlyContinue) {
        $uid = & id -u 2>$null
        $script:IsAdmin = ($uid -eq "0")
    }
}

#endregion

#region Helper Functions

function Test-Platform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Windows", "macOS", "Linux", "All")]
        [string]$Required
    )

    if ($Required -eq "All") {
        return $true
    }
    return ($script:Platform -eq $Required)
}

function Assert-Platform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Windows", "macOS", "Linux")]
        [string]$Required,

        [string]$AppName = "This application"
    )

    if ($script:Platform -ne $Required) {
        Write-Host "[INFO] $AppName is only available for $Required." -ForegroundColor Yellow
        exit 0
    }
}

function Get-PackageManagerCommand {
    [CmdletBinding()]
    param(
        [object]$WingetId,
        [object]$WingetSource,
        [object]$BrewCask,
        [object]$BrewFormula,
        [object]$AptPackage,
        [object]$DnfPackage,
        [object]$PacmanPackage,
        [object]$SnapPackage
    )

    $packageValues = [ordered]@{
        WingetId      = $WingetId
        BrewCask      = $BrewCask
        BrewFormula   = $BrewFormula
        AptPackage    = $AptPackage
        DnfPackage    = $DnfPackage
        PacmanPackage = $PacmanPackage
        SnapPackage   = $SnapPackage
    }

    # These manager-specific token grammars accept the package IDs in the
    # manifest while excluding whitespace and shell/option metacharacters.
    $packagePatterns = @{
        WingetId      = '\A[A-Za-z0-9][A-Za-z0-9._+-]*\z'
        BrewCask      = '\A[A-Za-z0-9][A-Za-z0-9._+@-]*\z'
        BrewFormula   = '\A[A-Za-z0-9][A-Za-z0-9._+@-]*\z'
        AptPackage    = '\A[a-z0-9][a-z0-9+.:~-]*\z'
        DnfPackage    = '\A[A-Za-z0-9][A-Za-z0-9._+-]*\z'
        PacmanPackage = '\A[A-Za-z0-9][A-Za-z0-9._+-]*\z'
        SnapPackage   = '\A[a-z0-9][a-z0-9.-]*\z'
    }

    foreach ($fieldName in $packageValues.Keys) {
        $value = $packageValues[$fieldName]
        if ($null -eq $value) {
            continue
        }

        if (($value -isnot [string]) -or
            (($value.Length -gt 0) -and -not [regex]::IsMatch(
                    $value,
                    $packagePatterns[$fieldName],
                    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                ))) {
            return [pscustomobject]@{
                Status       = 'InvalidMapping'
                Available    = $false
                IsValid      = $false
                Executable   = $null
                Arguments    = [string[]]@()
                ExitCode     = $null
                Output       = [object[]]@()
                Diagnostic   = "Package field $fieldName does not match its package identifier format."
                UserMessage  = 'This package entry is invalid. No package command was run.'
            }
        }
    }

    $executable = $null
    $arguments = @()

    switch ($script:PackageManager) {
        "winget" {
            if ($WingetId) {
                try {
                    if ($null -ne $WingetSource -and
                        (($WingetSource -isnot [string]) -or $WingetSource -cnotin @('winget', 'msstore'))) {
                        throw 'Unsupported WinGet source metadata.'
                    }
                    $WingetSource = Resolve-WingetPackageSource `
                        -PackageId $WingetId `
                        -DeclaredSource $WingetSource
                    $executable = 'winget'
                    $arguments = New-WingetArgumentList `
                        -Operation install `
                        -PackageId $WingetId `
                        -Source $WingetSource `
                        -AdditionalArguments @('--silent', '--accept-source-agreements', '--accept-package-agreements', '--force')
                }
                catch {
                    return [pscustomobject]@{
                        Status       = 'InvalidMapping'
                        Available    = $false
                        IsValid      = $false
                        Executable   = $null
                        Arguments    = [string[]]@()
                        ExitCode     = $null
                        Output       = [object[]]@()
                        Diagnostic   = 'WinGet source or package identity is invalid.'
                        UserMessage  = 'This package entry is invalid. No package command was run.'
                    }
                }
            }
            elseif ($null -ne $WingetSource) {
                return [pscustomobject]@{
                    Status       = 'InvalidMapping'
                    Available    = $false
                    IsValid      = $false
                    Executable   = $null
                    Arguments    = [string[]]@()
                    ExitCode     = $null
                    Output       = [object[]]@()
                    Diagnostic   = 'WinGet source metadata was supplied without a package ID.'
                    UserMessage  = 'This package entry is invalid. No package command was run.'
                }
            }
        }
        "brew" {
            if ($BrewCask) {
                $executable = 'brew'
                $arguments = @('install', '--cask', $BrewCask)
            }
            elseif ($BrewFormula) {
                $executable = 'brew'
                $arguments = @('install', $BrewFormula)
            }
        }
        "apt" {
            if ($AptPackage) {
                $executable = 'sudo'
                $arguments = @('apt', 'install', '-y', $AptPackage)
            }
        }
        "dnf" {
            if ($DnfPackage) {
                $executable = 'sudo'
                $arguments = @('dnf', 'install', '-y', $DnfPackage)
            }
        }
        "pacman" {
            if ($PacmanPackage) {
                $executable = 'sudo'
                $arguments = @('pacman', '-S', '--noconfirm', $PacmanPackage)
            }
        }
        "snap" {
            if ($SnapPackage) {
                $executable = 'sudo'
                $arguments = @('snap', 'install', $SnapPackage)
            }
        }
    }

    if (-not $executable) {
        return [pscustomobject]@{
            Status       = 'Unavailable'
            Available    = $false
            IsValid      = $true
            Executable   = $null
            Arguments    = [string[]]@()
            ExitCode     = $null
            Output       = [object[]]@()
            Diagnostic   = 'No package mapping is available for the selected package manager.'
            UserMessage  = $null
        }
    }

    return [pscustomobject]@{
        Status       = 'Ready'
        Available    = $true
        IsValid      = $true
        Executable   = $executable
        Arguments    = [string[]]$arguments
        ExitCode     = $null
        Output       = [object[]]@()
        Diagnostic   = $null
        UserMessage  = $null
    }
}

function Invoke-PackageManagerProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $application = Get-Command -Name $Executable -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $application) {
        return [pscustomobject]@{
            Status         = 'Unavailable'
            Available      = $false
            ExecutablePath = $null
            Arguments      = [string[]]$Arguments
            ExitCode       = $null
            Output         = [object[]]@()
            Diagnostic     = 'The package manager executable is unavailable.'
        }
    }

    $executablePath = if ($application.Path) { $application.Path } else { $application.Source }
    if (-not $executablePath) {
        return [pscustomobject]@{
            Status         = 'Unavailable'
            Available      = $false
            ExecutablePath = $null
            Arguments      = [string[]]$Arguments
            ExitCode       = $null
            Output         = [object[]]@()
            Diagnostic     = 'The package manager executable is unavailable.'
        }
    }

    try {
        # Preserve native exit codes even when the caller opts into treating
        # nonzero native statuses as PowerShell errors.
        if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $processOutput = @(& $executablePath @Arguments 2>&1)
        $processExitCode = $LASTEXITCODE

        if ($null -eq $processExitCode) {
            return [pscustomobject]@{
                Status         = 'Failed'
                Available      = $true
                ExecutablePath = $executablePath
                Arguments      = [string[]]$Arguments
                ExitCode       = $null
                Output         = [object[]]$processOutput
                Diagnostic     = 'The package manager did not return a process exit code.'
            }
        }

        return [pscustomobject]@{
            Status         = if ($processExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
            Available      = $true
            ExecutablePath = $executablePath
            Arguments      = [string[]]$Arguments
            ExitCode       = [int]$processExitCode
            Output         = [object[]]$processOutput
            Diagnostic     = if ($processExitCode -eq 0) { $null } else { 'The package manager returned a nonzero process exit code.' }
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        throw
    }
    catch [System.OperationCanceledException] {
        throw
    }
    catch {
        return [pscustomobject]@{
            Status         = 'Failed'
            Available      = $true
            ExecutablePath = $executablePath
            Arguments      = [string[]]$Arguments
            ExitCode       = $null
            Output         = [object[]]@()
            Diagnostic     = 'The package manager process could not be started or completed.'
        }
    }
}

function Install-CrossPlatformApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [object]$WingetId,
        [object]$WingetSource,
        [object]$BrewCask,
        [object]$BrewFormula,
        [object]$AptPackage,
        [object]$DnfPackage,
        [object]$PacmanPackage,
        [object]$SnapPackage
    )

    # Get the install command for current platform
    $pkgInfo = Get-PackageManagerCommand `
        -WingetId $WingetId `
        -WingetSource $WingetSource `
        -BrewCask $BrewCask `
        -BrewFormula $BrewFormula `
        -AptPackage $AptPackage `
        -DnfPackage $DnfPackage `
        -PacmanPackage $PacmanPackage `
        -SnapPackage $SnapPackage

    if ($pkgInfo.Status -eq 'InvalidMapping') {
        Write-Host $pkgInfo.UserMessage -ForegroundColor Red
        Write-Host "[ERROR] $($pkgInfo.Diagnostic)" -ForegroundColor Red
        return 1
    }

    # Check if any package manager is available after validating supplied data.
    if (-not $script:PackageManager) {
        Write-Host "[ERROR] No supported package manager found on this system." -ForegroundColor Red
        return 1
    }

    if ($pkgInfo.Status -eq 'Unavailable') {
        Write-Host "[INFO] $AppName is not available for $script:Platform via $script:PackageManager." -ForegroundColor Yellow
        return 0
    }

    Write-Host "[INFO] Installing $AppName via $script:PackageManager..." -ForegroundColor Cyan

    try {
        $processResult = Invoke-PackageManagerProcess `
            -Executable $pkgInfo.Executable `
            -Arguments $pkgInfo.Arguments
        $installExitCode = $processResult.ExitCode
        $outputStr = if ($processResult.Output.Count -gt 0) {
            $processResult.Output | Out-String
        }
        else {
            ''
        }

        # Log output for diagnostics
        if ($outputStr) {
            Write-Host "[DEBUG] Installer output: $outputStr" -ForegroundColor Gray
        }

        if ($processResult.Status -eq 'Unavailable') {
            Write-Host "[ERROR] $($processResult.Diagnostic) No success was reported." -ForegroundColor Red
            return 1
        }

        if ($null -eq $installExitCode) {
            Write-Host "[ERROR] $($processResult.Diagnostic) No success was reported." -ForegroundColor Red
            return 1
        }

        if ($installExitCode -eq 0) {
            Write-Host "[OK] $AppName installed successfully!" -ForegroundColor Green
            return 0
        }
        else {
            # Check if output indicates success despite non-zero exit code
            # Winget sometimes returns non-zero but the install actually succeeded
            if ($outputStr -match "Successfully installed" -or
                $outputStr -match "already installed" -or
                $outputStr -match "No applicable update found" -or
                $outputStr -match "No newer package versions are available") {
                Write-Host "[OK] $AppName installed successfully (output indicates success despite exit code $installExitCode)" -ForegroundColor Green
                return 0
            }

            # Known non-fatal winget exit codes
            # -1978335191 = Package already installed
            if ($installExitCode -eq -1978335191) {
                Write-Host "[OK] $AppName is already installed." -ForegroundColor Green
                return 0
            }

            Write-Host "[ERROR] Failed to install $AppName (exit code: $installExitCode)" -ForegroundColor Red
            if ($outputStr) {
                Write-Host "       $outputStr" -ForegroundColor Gray
            }
            # Return the actual exit code so the caller can interpret it
            return $installExitCode
        }
    }
    catch {
        Write-Host "[ERROR] Package manager execution failed. No success was reported." -ForegroundColor Red
        return 1
    }
}

function Invoke-WingetPackageCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'upgrade', 'uninstall', 'show', 'list')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [AllowNull()]
        [string]$Source,

        [ValidateSet('--silent', '--accept-source-agreements', '--accept-package-agreements', '--force', '--disable-interactivity', '--interactive')]
        [string[]]$AdditionalArguments = @(),

        [string]$ManifestPath
    )

    $resolvedSource = Resolve-WingetPackageSource -PackageId $PackageId -DeclaredSource $Source -ManifestPath $ManifestPath
    $arguments = New-WingetArgumentList `
        -Operation $Operation `
        -PackageId $PackageId `
        -Source $resolvedSource `
        -AdditionalArguments $AdditionalArguments
    $processResult = Invoke-PackageManagerProcess -Executable 'winget' -Arguments $arguments
    $global:LASTEXITCODE = if ($null -eq $processResult.ExitCode) { 1 } else { [int]$processResult.ExitCode }
    return [object[]]$processResult.Output
}

#endregion

#region Export Variables for Caller Scope

# When dot-sourced, also set variables in caller's scope for direct access
$Platform = $script:Platform
$LinuxDistro = $script:LinuxDistro
$PackageManager = $script:PackageManager
$IsAdmin = $script:IsAdmin

# Export summary when dot-sourced (for debugging)
Write-Verbose "Platform Detection Module Loaded:"
Write-Verbose "  Platform: $Platform"
Write-Verbose "  LinuxDistro: $LinuxDistro"
Write-Verbose "  PackageManager: $PackageManager"
Write-Verbose "  IsAdmin: $IsAdmin"

#endregion

