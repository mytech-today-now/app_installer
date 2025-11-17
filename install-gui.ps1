<#
.SYNOPSIS
    GUI-based application installer for automated Windows setup.

.DESCRIPTION
    This script provides a comprehensive graphical user interface for installing and managing
    multiple applications on Windows systems. Features include:
    - Modern Windows Forms GUI with category grouping
    - Real-time installation status display
    - Version detection for installed applications
    - Selective installation (individual apps, all apps, or only missing apps)
    - Progress tracking with detailed logging
    - Centralized logging to C:\mytech.today\logs\
    - Support for 271 applications via winget and custom installers

.NOTES
    File Name      : install-gui.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Version        : 1.4.5

.LINK
    https://github.com/mytech-today-now/app_installer
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

#region Load Responsive GUI Helper

# Import responsive GUI helper (prefer local copy, fall back to GitHub) for improved DPI scaling and multi-monitor support
$script:ResponsiveHelperLoaded = $false

# First, try to load from local path
$localResponsivePath = Join-Path $PSScriptRoot "..\scripts\responsive.ps1"
if (Test-Path $localResponsivePath) {
    try {
        Write-Host "Loading responsive GUI helper from local path..." -ForegroundColor Cyan
        . $localResponsivePath
        $script:ResponsiveHelperLoaded = $true
        Write-Host "[OK] Loaded responsive helper from local path" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to load local responsive helper: $_" -ForegroundColor Red
    }
}

# If local load failed, fall back to GitHub version
if (-not $script:ResponsiveHelperLoaded) {
    $responsiveUrl = 'https://raw.githubusercontent.com/mytech-today-now/scripts/main/responsive.ps1'
    try {
        Write-Host "Loading responsive GUI helper from GitHub..." -ForegroundColor Cyan
        Invoke-Expression (Invoke-WebRequest -Uri $responsiveUrl -UseBasicParsing).Content
        $script:ResponsiveHelperLoaded = $true
        Write-Host "[OK] Responsive GUI helper loaded successfully from GitHub" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to load responsive GUI helper from GitHub: $_" -ForegroundColor Red
    }
}

#endregion

#region Load Generic Logging Module

# Import generic logging module from GitHub for centralized logging
$loggingUrl = 'https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1'
$script:LoggingModuleLoaded = $false

try {
    Write-Host "Loading generic logging module..." -ForegroundColor Cyan
    Invoke-Expression (Invoke-WebRequest -Uri $loggingUrl -UseBasicParsing).Content
    $script:LoggingModuleLoaded = $true
    Write-Host "[OK] Generic logging module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to load generic logging module: $_" -ForegroundColor Red
    Write-Host "[INFO] Falling back to local logging implementation" -ForegroundColor Yellow

    # Try to load from local path as fallback
    $localLoggingPath = Join-Path $PSScriptRoot "..\scripts\logging.ps1"
    if (Test-Path $localLoggingPath) {
        try {
            . $localLoggingPath
            $script:LoggingModuleLoaded = $true
            Write-Host "[OK] Loaded logging module from local path" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to load local logging module: $_" -ForegroundColor Red
        }
    }
}

#endregion

#region .NET Framework Prerequisites

#region Dynamic Sizing Helper Functions

function Measure-TextWidth {
    <#
    .SYNOPSIS
        Measures the width of text in pixels for a given font.

    .PARAMETER Text
        The text to measure.

    .PARAMETER Font
        The font to use for measurement.

    .OUTPUTS
        System.Int32 - The width in pixels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [System.Drawing.Font]$Font
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
        $size = $graphics.MeasureString($Text, $Font)
        $graphics.Dispose()
        return [int]([Math]::Ceiling($size.Width))
    }
    catch {
        # Fallback: approximate based on character count
        return [int]($Text.Length * $Font.Size * 0.6)
    }
}

function Get-DynamicButtonWidth {
    <#
    .SYNOPSIS
        Calculates button width based on text content.

    .PARAMETER Text
        The button text.

    .PARAMETER Font
        The font to use.

    .PARAMETER MinWidth
        Minimum button width.

    .PARAMETER Padding
        Additional padding to add.

    .OUTPUTS
        System.Int32 - The calculated button width.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [System.Drawing.Font]$Font,

        [int]$MinWidth = 80,

        [int]$Padding = 30
    )

    $textWidth = Measure-TextWidth -Text $Text -Font $Font
    $calculatedWidth = $textWidth + $Padding
    return [Math]::Max($calculatedWidth, $MinWidth)
}

function Get-LongestTextLength {
    <#
    .SYNOPSIS
        Finds the longest text in an array of strings.

    .PARAMETER TextArray
        Array of strings to analyze.

    .OUTPUTS
        System.String - The longest string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$TextArray
    )

    $longest = ""
    foreach ($text in $TextArray) {
        if ($text.Length -gt $longest.Length) {
            $longest = $text
        }
    }
    return $longest
}

function Get-DynamicColumnWidth {
    <#
    .SYNOPSIS
        Calculates optimal column width based on content and header text.

    .PARAMETER Items
        Array of items to measure.

    .PARAMETER PropertyName
        Property name to measure.

    .PARAMETER HeaderText
        Column header text to also measure (optional).

    .PARAMETER Font
        Font to use for measurement.

    .PARAMETER MinWidth
        Minimum column width.

    .PARAMETER Padding
        Additional padding.

    .OUTPUTS
        System.Int32 - The calculated column width.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$Items,

        [Parameter(Mandatory = $false)]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [string]$HeaderText,

        [Parameter(Mandatory = $true)]
        [System.Drawing.Font]$Font,

        [int]$MinWidth = 100,

        [int]$Padding = 20
    )

    $maxWidth = 0

    # Measure header text if provided
    if ($HeaderText) {
        $headerWidth = Measure-TextWidth -Text $HeaderText -Font $Font
        if ($headerWidth -gt $maxWidth) {
            $maxWidth = $headerWidth
        }
    }

    # Measure data values if items and property name provided
    if ($Items -and $PropertyName) {
        foreach ($item in $Items) {
            $text = $item.$PropertyName
            if ($text) {
                $width = Measure-TextWidth -Text $text.ToString() -Font $Font
                if ($width -gt $maxWidth) {
                    $maxWidth = $width
                }
            }
        }
    }

    $calculatedWidth = $maxWidth + $Padding
    return [Math]::Max($calculatedWidth, $MinWidth)
}

#endregion Dynamic Sizing Helper Functions

function New-InstallerPoint {
    <#
    .SYNOPSIS
    Wrapper around System.Drawing.Point that defensively normalizes X/Y inputs
    so that only two integer arguments are ever passed to the constructor.

    .DESCRIPTION
    This helps avoid intermittent "Cannot find an overload for 'Point' and the
    argument count: '4'" errors that can occur when values are expanded in
    unexpected ways (e.g., array values, splatting, or mis-bound parameters).
    It also handles the common call style New-InstallerPoint($x, $y) by
    unpacking the array PowerShell creates for the arguments.
    #>
    param(
        [Parameter(Position = 0)]
        [object]$X,
        [Parameter(Position = 1)]
        [object]$Y
    )

    # Preserve raw values for logging.
    $rawX = $X
    $rawY = $Y

    # If called as New-InstallerPoint($x, $y), PowerShell passes a single
    # array argument. When Y is not explicitly provided, unpack X into X/Y.
    if ($null -eq $Y -and $X -is [System.Array] -and $X.Count -ge 2) {
        $Y = $X[1]
        $X = $X[0]
    }

    # Flatten any remaining arrays and coerce to integers.
    if ($X -is [System.Array] -and $X.Count -gt 0) { $X = $X[0] }
    if ($Y -is [System.Array] -and $Y.Count -gt 0) { $Y = $Y[0] }

    try {
        $intX = [int]$X
        $intY = [int]$Y

        return New-Object System.Drawing.Point($intX, $intY)
    }
    catch {
        $message = "New-InstallerPoint failed to construct System.Drawing.Point. RawX='$rawX', RawY='$rawY', X='$X', Y='$Y'. Error: $($_.Exception.Message)"
        $writeLog = Get-Command -Name Write-Log -ErrorAction SilentlyContinue
        if ($writeLog) {
            & $writeLog -Message $message -Level ERROR
        }
        else {
            Write-Warning $message
        }

        throw
    }
}


#region ListView Click-to-Select Helper Functions

function Add-ListViewClickToSelect {
    <#
    .SYNOPSIS
        Adds click-to-select and drag-to-multi-select functionality to a ListView with checkboxes.

    .DESCRIPTION
        Enables users to check/uncheck items by clicking anywhere on the row.
        Also supports click-and-drag to multi-select items.
        Follows Microsoft Professional Design Standards for Enterprise software.

    .PARAMETER ListView
        The ListView control to enhance.

    .EXAMPLE
        Add-ListViewClickToSelect -ListView $myListView
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListView]$ListView
    )

    # Track drag selection state
    $dragState = @{
        IsDragging = $false
        StartIndex = -1
        LastIndex = -1
        InitialCheckState = $false
    }

    # MouseDown event - Start drag selection
    $ListView.Add_MouseDown({
        param($sender, $e)

        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $hitTest = $sender.HitTest($e.Location)

            if ($hitTest.Item -ne $null) {
                $index = $hitTest.Item.Index

                # Don't interfere with checkbox clicks
                if ($hitTest.Location -ne [System.Windows.Forms.ListViewHitTestLocations]::StateImage) {
                    # Toggle the checkbox
                    $hitTest.Item.Checked = -not $hitTest.Item.Checked

                    # Initialize drag state
                    $dragState.IsDragging = $true
                    $dragState.StartIndex = $index
                    $dragState.LastIndex = $index
                    $dragState.InitialCheckState = $hitTest.Item.Checked
                }
            }
        }
    }.GetNewClosure())

    # MouseMove event - Continue drag selection
    $ListView.Add_MouseMove({
        param($sender, $e)

        if ($dragState.IsDragging -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $hitTest = $sender.HitTest($e.Location)

            if ($hitTest.Item -ne $null) {
                $currentIndex = $hitTest.Item.Index

                # Only process if we've moved to a different item
                if ($currentIndex -ne $dragState.LastIndex) {
                    # Determine range to update
                    $startRange = [Math]::Min($dragState.StartIndex, $currentIndex)
                    $endRange = [Math]::Max($dragState.StartIndex, $currentIndex)

                    # Update all items in the range
                    for ($i = $startRange; $i -le $endRange; $i++) {
                        if ($i -lt $sender.Items.Count) {
                            $sender.Items[$i].Checked = $dragState.InitialCheckState
                        }
                    }

                    $dragState.LastIndex = $currentIndex
                }
            }
        }
    }.GetNewClosure())

    # MouseUp event - End drag selection
    $ListView.Add_MouseUp({
        param($sender, $e)

        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $dragState.IsDragging = $false
            $dragState.StartIndex = -1
            $dragState.LastIndex = -1
        }
    }.GetNewClosure())

    # MouseLeave event - Cancel drag if mouse leaves control
    $ListView.Add_MouseLeave({
        $dragState.IsDragging = $false
        $dragState.StartIndex = -1
        $dragState.LastIndex = -1
    }.GetNewClosure())
}

#endregion ListView Click-to-Select Helper Functions

#region Dynamic Form Resizing Helper Functions

function Add-MainFormResizeHandler {
    <#
    .SYNOPSIS
        Adds dynamic resize handling to the main application form.

    .DESCRIPTION
        Implements Microsoft Professional Design Standards for responsive window resizing.
        Dynamically adjusts ListView column widths when the form is resized.

    .PARAMETER Form
        The main form to add resize handling to.

    .PARAMETER ListView
        The main ListView control.

    .PARAMETER WebBrowser
        The WebBrowser control for output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListView]$ListView,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.WebBrowser]$WebBrowser
    )

    # Store original proportions
    $resizeState = @{
        LastWidth = $Form.ClientSize.Width
        LastHeight = $Form.ClientSize.Height
        IsResizing = $false
    }

    $Form.Add_Resize({
        # Prevent recursive calls and ignore minimized state
        if ($resizeState.IsResizing -or $Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            return
        }

        $resizeState.IsResizing = $true

        try {
            # Get current form dimensions
            $currentWidth = $Form.ClientSize.Width
            $currentHeight = $Form.ClientSize.Height

            # Only resize if dimensions actually changed
            if ($currentWidth -ne $resizeState.LastWidth -or $currentHeight -ne $resizeState.LastHeight) {
                # Get form info from Tag
                $formInfo = $Form.Tag
                $margin = $formInfo.Margin

                # Calculate new ListView width (anchoring handles position automatically)
                $listViewWidth = $ListView.Width
                $outputWidth = $WebBrowser.Width

                # Adjust Description column (last column) to fill remaining space
                if ($ListView.Columns.Count -ge 5) {
                    $usedWidth = 0
                    for ($i = 0; $i -lt 4; $i++) {
                        $usedWidth += $ListView.Columns[$i].Width
                    }
                    $scrollbarWidth = 25
                    $newDescWidth = [Math]::Max($listViewWidth - $usedWidth - $scrollbarWidth, 200)
                    $ListView.Columns[4].Width = $newDescWidth
                }

                # Update stored dimensions
                $resizeState.LastWidth = $currentWidth
                $resizeState.LastHeight = $currentHeight
            }
        }
        catch {
            # Silently ignore resize errors
        }
        finally {
            $resizeState.IsResizing = $false
        }
    }.GetNewClosure())
}

function Add-UpdatesFormResizeHandler {
    <#
    .SYNOPSIS
        Adds dynamic resize handling to the Updates dialog form.

    .DESCRIPTION
        Implements Microsoft Professional Design Standards for responsive window resizing.
        Dynamically adjusts ListView column widths when the form is resized.

    .PARAMETER Form
        The updates form to add resize handling to.

    .PARAMETER ListView
        The updates ListView control.

    .PARAMETER TitleLabel
        The title label control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListView]$ListView,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Label]$TitleLabel
    )

    # Store original proportions
    $resizeState = @{
        LastWidth = $Form.ClientSize.Width
        LastHeight = $Form.ClientSize.Height
        IsResizing = $false
    }

    $Form.Add_Resize({
        # Prevent recursive calls and ignore minimized state
        if ($resizeState.IsResizing -or $Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            return
        }

        $resizeState.IsResizing = $true

        try {
            # Get current form dimensions
            $currentWidth = $Form.ClientSize.Width
            $currentHeight = $Form.ClientSize.Height

            # Only resize if dimensions actually changed
            if ($currentWidth -ne $resizeState.LastWidth -or $currentHeight -ne $resizeState.LastHeight) {
                # Columns are already anchored and will resize automatically
                # No additional adjustments needed for this simple layout

                # Update stored dimensions
                $resizeState.LastWidth = $currentWidth
                $resizeState.LastHeight = $currentHeight
            }
        }
        catch {
            # Silently ignore resize errors
        }
        finally {
            $resizeState.IsResizing = $false
        }
    }.GetNewClosure())
}

function Add-QueueFormResizeHandler {
    <#
    .SYNOPSIS
        Adds dynamic resize handling to the Queue Management dialog form.

    .DESCRIPTION
        Implements Microsoft Professional Design Standards for responsive window resizing.
        Dynamically adjusts ListView and button positions when the form is resized.

    .PARAMETER Form
        The queue form to add resize handling to.

    .PARAMETER ListView
        The queue ListView control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListView]$ListView
    )

    # Store original proportions
    $resizeState = @{
        LastWidth = $Form.ClientSize.Width
        LastHeight = $Form.ClientSize.Height
        IsResizing = $false
    }

    $Form.Add_Resize({
        # Prevent recursive calls and ignore minimized state
        if ($resizeState.IsResizing -or $Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            return
        }

        $resizeState.IsResizing = $true

        try {
            # Get current form dimensions
            $currentWidth = $Form.ClientSize.Width
            $currentHeight = $Form.ClientSize.Height

            # Only resize if dimensions actually changed
            if ($currentWidth -ne $resizeState.LastWidth -or $currentHeight -ne $resizeState.LastHeight) {
                # Columns and buttons are already anchored and will resize automatically
                # No additional adjustments needed

                # Update stored dimensions
                $resizeState.LastWidth = $currentWidth
                $resizeState.LastHeight = $currentHeight
            }
        }
        catch {
            # Silently ignore resize errors
        }
        finally {
            $resizeState.IsResizing = $false
        }
    }.GetNewClosure())
}

#endregion Dynamic Form Resizing Helper Functions

function Get-DotNetFrameworkVersion {
    <#
    .SYNOPSIS
        Gets the installed .NET Framework version.

    .DESCRIPTION
        Checks the registry to determine the highest installed .NET Framework version.
        Returns the version number or 0 if not found.

    .OUTPUTS
        System.Int32 - The .NET Framework release number
    #>
    [CmdletBinding()]
    param()

    try {
        # Check for .NET Framework 4.5+ using Release registry value
        $releaseKey = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'

        if (Test-Path $releaseKey) {
            $release = (Get-ItemProperty -Path $releaseKey -Name Release -ErrorAction SilentlyContinue).Release

            if ($release) {
                Write-Host "[CHECK] .NET Framework release number: $release" -ForegroundColor Cyan
                return $release
            }
        }

        Write-Host "[WARN] .NET Framework 4.5+ not detected in registry" -ForegroundColor Yellow
        return 0
    }
    catch {
        Write-Host "[ERROR] Failed to check .NET Framework version: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
}

function Get-DotNetFrameworkVersionName {
    <#
    .SYNOPSIS
        Converts .NET Framework release number to version name.

    .PARAMETER Release
        The release number from the registry.

    .OUTPUTS
        System.String - The version name (e.g., "4.8")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Release
    )

    # .NET Framework version mapping
    # Reference: https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
    if ($Release -ge 528040) { return "4.8" }
    elseif ($Release -ge 461808) { return "4.7.2" }
    elseif ($Release -ge 461308) { return "4.7.1" }
    elseif ($Release -ge 460798) { return "4.7" }
    elseif ($Release -ge 394802) { return "4.6.2" }
    elseif ($Release -ge 394254) { return "4.6.1" }
    elseif ($Release -ge 393295) { return "4.6" }
    elseif ($Release -ge 379893) { return "4.5.2" }
    elseif ($Release -ge 378675) { return "4.5.1" }
    elseif ($Release -ge 378389) { return "4.5" }
    else { return "Unknown" }
}

function Install-DotNetFramework {
    <#
    .SYNOPSIS
        Installs .NET Framework 4.8 using winget.

    .DESCRIPTION
        Downloads and installs .NET Framework 4.8 which is required for Windows Forms GUI.
        Uses winget package manager for installation.

    .OUTPUTS
        System.Boolean - True if installation succeeded, False otherwise
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Host "`n[INSTALL] Installing .NET Framework 4.8..." -ForegroundColor Yellow
        Write-Host "[INFO] This is required for the GUI to function properly" -ForegroundColor Cyan
        Write-Host "[INFO] Installation may take several minutes and require a restart" -ForegroundColor Cyan

        # Check if winget is available
        $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        if (-not $wingetAvailable) {
            Write-Host "[ERROR] winget not available - cannot install .NET Framework automatically" -ForegroundColor Red
            Write-Host "[INFO] Please install .NET Framework 4.8 manually from:" -ForegroundColor Yellow
            Write-Host "       https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor Yellow
            return $false
        }

        # Install .NET Framework 4.8 using winget
        Write-Host "[DOWNLOAD] Downloading .NET Framework 4.8..." -ForegroundColor Yellow
        $result = winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-source-agreements --accept-package-agreements 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] .NET Framework 4.8 installed successfully!" -ForegroundColor Green
            Write-Host "[WARN] A system restart may be required for changes to take effect" -ForegroundColor Yellow
            Write-Host "[INFO] Please restart your computer and run this script again" -ForegroundColor Cyan

            # Prompt user to restart
            $restart = Read-Host "`nWould you like to restart now? (Y/N)"
            if ($restart -eq 'Y' -or $restart -eq 'y') {
                Write-Host "[INFO] Restarting computer in 10 seconds..." -ForegroundColor Yellow
                Write-Host "[INFO] Press Ctrl+C to cancel" -ForegroundColor Cyan
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            }
            else {
                Write-Host "[INFO] Please restart your computer manually before running this script again" -ForegroundColor Yellow
                exit 0
            }

            return $true
        }
        else {
            Write-Host "[ERROR] .NET Framework installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "[INFO] Please install .NET Framework 4.8 manually from:" -ForegroundColor Yellow
            Write-Host "       https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Failed to install .NET Framework: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[INFO] Please install .NET Framework 4.8 manually from:" -ForegroundColor Yellow
        Write-Host "       https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor Yellow
        return $false
    }
}

function Ensure-DotNetFramework {
    <#
    .SYNOPSIS
        Ensures .NET Framework 4.7.2 or later is installed.

    .DESCRIPTION
        Checks for .NET Framework 4.7.2+ and installs 4.8 if not present.
        This is required for Windows Forms GUI to function properly.

    .OUTPUTS
        System.Boolean - True if .NET Framework is available, False otherwise
    #>
    [CmdletBinding()]
    param()

    Write-Host "`n[CHECK] Checking .NET Framework version..." -ForegroundColor Cyan

    $release = Get-DotNetFrameworkVersion

    if ($release -eq 0) {
        Write-Host "[ERROR] .NET Framework not detected" -ForegroundColor Red
        Write-Host "[INFO] .NET Framework 4.7.2 or later is required for this GUI" -ForegroundColor Yellow

        $install = Read-Host "`nWould you like to install .NET Framework 4.8 now? (Y/N)"
        if ($install -eq 'Y' -or $install -eq 'y') {
            return Install-DotNetFramework
        }
        else {
            Write-Host "[ERROR] Cannot continue without .NET Framework" -ForegroundColor Red
            return $false
        }
    }

    $versionName = Get-DotNetFrameworkVersionName -Release $release
    Write-Host "[OK] .NET Framework $versionName detected (Release: $release)" -ForegroundColor Green

    # Check if version is 4.7.2 or later (release >= 461808)
    if ($release -lt 461808) {
        Write-Host "[WARN] .NET Framework $versionName is installed, but 4.7.2 or later is recommended" -ForegroundColor Yellow
        Write-Host "[INFO] Current version may not support all GUI features" -ForegroundColor Yellow

        $upgrade = Read-Host "`nWould you like to upgrade to .NET Framework 4.8? (Y/N)"
        if ($upgrade -eq 'Y' -or $upgrade -eq 'y') {
            return Install-DotNetFramework
        }
        else {
            Write-Host "[WARN] Continuing with .NET Framework $versionName - some features may not work" -ForegroundColor Yellow
            return $true
        }
    }

    Write-Host "[OK] .NET Framework version is sufficient for GUI" -ForegroundColor Green
    return $true
}

# Check and install .NET Framework before loading assemblies
Write-Host "=== myTech.Today Application Installer - GUI Mode ===" -ForegroundColor Cyan
Write-Host "Version: 1.4.5" -ForegroundColor Gray
Write-Host ""

if (-not (Ensure-DotNetFramework)) {
    Write-Host "`n[ERROR] .NET Framework prerequisites not met" -ForegroundColor Red
    Write-Host "[INFO] Please install .NET Framework 4.8 and try again" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}

#endregion .NET Framework Prerequisites

# Add required assemblies
Write-Host "`n[INFO] Loading GUI assemblies..." -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web
    Write-Host "[OK] GUI assemblies loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to load GUI assemblies: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[INFO] This usually indicates a .NET Framework issue" -ForegroundColor Yellow
    Write-Host "[INFO] Please ensure .NET Framework 4.8 is properly installed" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}

# Script variables
$script:ScriptVersion = '1.4.5'
$script:OriginalScriptPath = $PSScriptRoot
$script:SystemInstallPath = "$env:SystemDrive\mytech.today\app_installer"
$script:ScriptPath = $script:SystemInstallPath
$script:CentralLogPath = "$env:USERPROFILE\myTech.Today\"
$script:LogPath = $null
$script:AppsPath = Join-Path $script:ScriptPath "apps"
$script:ProfilesPath = Join-Path $script:ScriptPath "profiles"
$script:InstalledApps = @{}
$script:SelectedApps = @()
$script:IsClosing = $false  # Flag to prevent event handlers during form closing
$script:IsInstalling = $false  # Flag to track if installation is in progress
$script:SearchTerm = ""  # Current search filter term
$script:FilteredApplications = @()  # Filtered application list

# Queue management variables
$script:InstallationQueue = @()  # Array of apps in installation queue
$script:QueueStatePath = "$env:USERPROFILE\myTech.Today\app_installer\queue-state.json"  # Queue state file
$script:IsPaused = $false  # Flag to track if installation is paused
$script:SkipCurrent = $false  # Flag to skip current installation
$script:CurrentQueueIndex = 0  # Current position in queue

# Application registry - defines all supported applications
# Using PSCustomObject for proper property access with Group-Object
$script:Applications = @(
    # Browsers
    [PSCustomObject]@{ Name = "Google Chrome"; ScriptName = "chrome.ps1"; WingetId = "Google.Chrome"; Category = "Browsers"; Description = "Fast, secure web browser by Google" }
    [PSCustomObject]@{ Name = "Brave Browser"; ScriptName = "brave.ps1"; WingetId = "Brave.Brave"; Category = "Browsers"; Description = "Privacy-focused browser with ad blocking" }
    [PSCustomObject]@{ Name = "Firefox"; ScriptName = "firefox.ps1"; WingetId = "Mozilla.Firefox"; Category = "Browsers"; Description = "Open-source browser with privacy features" }
    [PSCustomObject]@{ Name = "Microsoft Edge"; ScriptName = "edge.ps1"; WingetId = "Microsoft.Edge"; Category = "Browsers"; Description = "Chromium-based browser by Microsoft" }
    [PSCustomObject]@{ Name = "Vivaldi"; ScriptName = "vivaldi.ps1"; WingetId = "Vivaldi.Vivaldi"; Category = "Browsers"; Description = "Highly customizable browser for power users" }
    [PSCustomObject]@{ Name = "Opera"; ScriptName = "opera.ps1"; WingetId = "Opera.Opera"; Category = "Browsers"; Description = "Feature-rich browser with built-in VPN" }
    [PSCustomObject]@{ Name = "Opera GX"; ScriptName = "operagx.ps1"; WingetId = "Opera.OperaGX"; Category = "Browsers"; Description = "Gaming browser with resource limiter" }
    [PSCustomObject]@{ Name = "LibreWolf"; ScriptName = "librewolf.ps1"; WingetId = "LibreWolf.LibreWolf"; Category = "Browsers"; Description = "Privacy-hardened Firefox fork" }
    [PSCustomObject]@{ Name = "Tor Browser"; ScriptName = "torbrowser.ps1"; WingetId = "TorProject.TorBrowser"; Category = "Browsers"; Description = "Anonymous browsing via Tor network" }
    [PSCustomObject]@{ Name = "Waterfox"; ScriptName = "waterfox.ps1"; WingetId = "Waterfox.Waterfox"; Category = "Browsers"; Description = "Privacy-focused Firefox-based browser" }
    [PSCustomObject]@{ Name = "Chromium"; ScriptName = "chromium.ps1"; WingetId = "Hibbiki.Chromium"; Category = "Browsers"; Description = "Open-source base for Chrome" }
    [PSCustomObject]@{ Name = "Pale Moon"; ScriptName = "palemoon.ps1"; WingetId = "MoonchildProductions.PaleMoon"; Category = "Browsers"; Description = "Lightweight Firefox-based browser" }
    [PSCustomObject]@{ Name = "Ungoogled Chromium"; ScriptName = "ungoogledchromium.ps1"; WingetId = "eloston.ungoogled-chromium"; Category = "Browsers"; Description = "Chrome without Google integration" }
    [PSCustomObject]@{ Name = "Midori Browser"; ScriptName = "midori.ps1"; WingetId = "AstianInc.Midori"; Category = "Browsers"; Description = "Lightweight and fast web browser" }
    [PSCustomObject]@{ Name = "Min Browser"; ScriptName = "min.ps1"; WingetId = "Min.Min"; Category = "Browsers"; Description = "Minimal, fast web browser" }
    # Development Tools
    [PSCustomObject]@{ Name = "Visual Studio Code"; ScriptName = "vscode.ps1"; WingetId = "Microsoft.VisualStudioCode"; Category = "Development"; Description = "Powerful code editor with extensions" }
    [PSCustomObject]@{ Name = "Notepad++"; ScriptName = "notepadplusplus.ps1"; WingetId = "Notepad++.Notepad++"; Category = "Development"; Description = "Lightweight text and code editor" }
    [PSCustomObject]@{ Name = "Git"; ScriptName = "git.ps1"; WingetId = "Git.Git"; Category = "Development"; Description = "Distributed version control system" }
    [PSCustomObject]@{ Name = "GitHub Desktop"; ScriptName = "githubdesktop.ps1"; WingetId = "GitHub.GitHubDesktop"; Category = "Development"; Description = "GUI for Git and GitHub workflows" }
    [PSCustomObject]@{ Name = "Python"; ScriptName = "python.ps1"; WingetId = "Python.Python.3.12"; Category = "Development"; Description = "Popular programming language runtime" }
    [PSCustomObject]@{ Name = "Node.js"; ScriptName = "nodejs.ps1"; WingetId = "OpenJS.NodeJS.LTS"; Category = "Development"; Description = "JavaScript runtime for server-side apps" }
    [PSCustomObject]@{ Name = "Docker Desktop"; ScriptName = "docker.ps1"; WingetId = "Docker.DockerDesktop"; Category = "Development"; Description = "Container platform for development" }
    [PSCustomObject]@{ Name = "Postman"; ScriptName = "postman.ps1"; WingetId = "Postman.Postman"; Category = "Development"; Description = "API development and testing tool" }
    [PSCustomObject]@{ Name = "Insomnia"; ScriptName = "insomnia.ps1"; WingetId = "Insomnia.Insomnia"; Category = "Development"; Description = "REST and GraphQL API client" }
    [PSCustomObject]@{ Name = "Sublime Text"; ScriptName = "sublimetext.ps1"; WingetId = "SublimeHQ.SublimeText.4"; Category = "Development"; Description = "Fast, sophisticated text editor" }
    [PSCustomObject]@{ Name = "Geany"; ScriptName = "geany.ps1"; WingetId = "Geany.Geany"; Category = "Development"; Description = "Lightweight IDE with GTK toolkit" }
    [PSCustomObject]@{ Name = "NetBeans IDE"; ScriptName = "netbeans.ps1"; WingetId = "Apache.NetBeans"; Category = "Development"; Description = "IDE for Java and web development" }
    [PSCustomObject]@{ Name = "IntelliJ IDEA Community"; ScriptName = "intellij.ps1"; WingetId = "JetBrains.IntelliJIDEA.Community"; Category = "Development"; Description = "Java IDE by JetBrains" }
    [PSCustomObject]@{ Name = "PyCharm Community"; ScriptName = "pycharm.ps1"; WingetId = "JetBrains.PyCharm.Community"; Category = "Development"; Description = "Python IDE by JetBrains" }
    [PSCustomObject]@{ Name = "Eclipse IDE"; ScriptName = "eclipse.ps1"; WingetId = "EclipseAdoptium.Temurin.17.JRE"; Category = "Development"; Description = "Popular Java development environment" }
    [PSCustomObject]@{ Name = "Atom Editor"; ScriptName = "atom.ps1"; WingetId = "GitHub.Atom"; Category = "Development"; Description = "Hackable text editor by GitHub" }
    [PSCustomObject]@{ Name = "Brackets"; ScriptName = "brackets.ps1"; WingetId = "Adobe.Brackets"; Category = "Development"; Description = "Modern editor for web design" }
    [PSCustomObject]@{ Name = "WinSCP"; ScriptName = "winscp.ps1"; WingetId = "WinSCP.WinSCP"; Category = "Development"; Description = "SFTP and FTP client for Windows" }
    [PSCustomObject]@{ Name = "FileZilla"; ScriptName = "filezilla.ps1"; WingetId = "TimKosse.FileZilla.Client"; Category = "Development"; Description = "Fast and reliable FTP client" }
    [PSCustomObject]@{ Name = "DBeaver"; ScriptName = "dbeaver.ps1"; WingetId = "dbeaver.dbeaver"; Category = "Development"; Description = "Universal database management tool" }
    [PSCustomObject]@{ Name = "HeidiSQL"; ScriptName = "heidisql.ps1"; WingetId = "HeidiSQL.HeidiSQL"; Category = "Development"; Description = "Lightweight MySQL/MariaDB client" }
    [PSCustomObject]@{ Name = "Vagrant"; ScriptName = "vagrant.ps1"; WingetId = "Hashicorp.Vagrant"; Category = "Development"; Description = "Development environment manager" }
    [PSCustomObject]@{ Name = "Windows Terminal"; ScriptName = "windowsterminal.ps1"; WingetId = "Microsoft.WindowsTerminal"; Category = "Development"; Description = "Modern terminal with tabs and themes" }
    [PSCustomObject]@{ Name = "Vim"; ScriptName = "vim.ps1"; WingetId = "vim.vim"; Category = "Development"; Description = "Highly configurable text editor" }
    [PSCustomObject]@{ Name = "CMake"; ScriptName = "cmake.ps1"; WingetId = "Kitware.CMake"; Category = "Development"; Description = "Cross-platform build system generator" }
    [PSCustomObject]@{ Name = "Lazygit"; ScriptName = "lazygit.ps1"; WingetId = "JesseDuffield.lazygit"; Category = "Development"; Description = "Terminal UI for git commands" }
    # Productivity
    [PSCustomObject]@{ Name = "LibreOffice"; ScriptName = "libreoffice.ps1"; WingetId = "TheDocumentFoundation.LibreOffice"; Category = "Productivity"; Description = "Free office suite with Writer, Calc, Impress" }
    [PSCustomObject]@{ Name = "Apache OpenOffice"; ScriptName = "openoffice.ps1"; WingetId = "Apache.OpenOffice"; Category = "Productivity"; Description = "Open-source office productivity suite" }
    [PSCustomObject]@{ Name = "7-Zip"; ScriptName = "7zip.ps1"; WingetId = "7zip.7zip"; Category = "Productivity"; Description = "High-compression file archiver" }
    [PSCustomObject]@{ Name = "Adobe Acrobat Reader"; ScriptName = "adobereader.ps1"; WingetId = "Adobe.Acrobat.Reader.64-bit"; Category = "Productivity"; Description = "PDF viewer and form filler" }
    [PSCustomObject]@{ Name = "Foxit PDF Reader"; ScriptName = "foxitreader.ps1"; WingetId = "Foxit.FoxitReader"; Category = "Productivity"; Description = "Fast, lightweight PDF reader" }
    [PSCustomObject]@{ Name = "Sumatra PDF"; ScriptName = "sumatrapdf.ps1"; WingetId = "SumatraPDF.SumatraPDF"; Category = "Productivity"; Description = "Minimalist PDF and eBook reader" }
    [PSCustomObject]@{ Name = "Obsidian"; ScriptName = "obsidian.ps1"; WingetId = "Obsidian.Obsidian"; Category = "Productivity"; Description = "Knowledge base with markdown linking" }
    [PSCustomObject]@{ Name = "Joplin"; ScriptName = "joplin.ps1"; WingetId = "Joplin.Joplin"; Category = "Productivity"; Description = "Open-source note-taking app" }
    [PSCustomObject]@{ Name = "Notion"; ScriptName = "notion.ps1"; WingetId = "Notion.Notion"; Category = "Productivity"; Description = "All-in-one workspace for notes and docs" }
    [PSCustomObject]@{ Name = "Calibre"; ScriptName = "calibre.ps1"; WingetId = "calibre.calibre"; Category = "Productivity"; Description = "eBook library management and conversion" }
    [PSCustomObject]@{ Name = "Zotero"; ScriptName = "zotero.ps1"; WingetId = "DigitalScholar.Zotero"; Category = "Productivity"; Description = "Research citation and bibliography manager" }
    [PSCustomObject]@{ Name = "FreeMind"; ScriptName = "freemind.ps1"; WingetId = "FreeMind.FreeMind"; Category = "Productivity"; Description = "Mind mapping and brainstorming tool" }
    [PSCustomObject]@{ Name = "XMind"; ScriptName = "xmind.ps1"; WingetId = "XMind.XMind"; Category = "Productivity"; Description = "Professional mind mapping software" }
    [PSCustomObject]@{ Name = "WPS Office"; ScriptName = "wpsoffice.ps1"; WingetId = "Kingsoft.WPSOffice"; Category = "Productivity"; Description = "Free office suite alternative" }
    [PSCustomObject]@{ Name = "PDF24 Creator"; ScriptName = "pdf24.ps1"; WingetId = "geeksoftwareGmbH.PDF24Creator"; Category = "Productivity"; Description = "PDF creation and editing tools" }
    [PSCustomObject]@{ Name = "Typora"; ScriptName = "typora.ps1"; WingetId = "Typora.Typora"; Category = "Productivity"; Description = "Minimalist markdown editor" }
    [PSCustomObject]@{ Name = "Toggl Track"; ScriptName = "toggltrack.ps1"; WingetId = "Toggl.TogglTrack"; Category = "Productivity"; Description = "Time tracking and productivity tool" }
    [PSCustomObject]@{ Name = "Clockify"; ScriptName = "clockify.ps1"; WingetId = "Clockify.Clockify"; Category = "Productivity"; Description = "Free time tracking software" }
    [PSCustomObject]@{ Name = "Evernote"; ScriptName = "evernote.ps1"; WingetId = "Evernote.Evernote"; Category = "Productivity"; Description = "Note-taking and organization app" }
    [PSCustomObject]@{ Name = "Simplenote"; ScriptName = "simplenote.ps1"; WingetId = "Automattic.Simplenote"; Category = "Productivity"; Description = "Simple, lightweight note-taking" }
    [PSCustomObject]@{ Name = "Trello"; ScriptName = "trello.ps1"; WingetId = "Trello.Trello"; Category = "Productivity"; Description = "Visual project management boards" }
    [PSCustomObject]@{ Name = "ClickUp"; ScriptName = "clickup.ps1"; WingetId = "ClickUp.ClickUp"; Category = "Productivity"; Description = "All-in-one productivity platform" }
    [PSCustomObject]@{ Name = "Todoist"; ScriptName = "todoist.ps1"; WingetId = "Doist.Todoist"; Category = "Productivity"; Description = "Task management and to-do lists" }
    # Media & Creative
    [PSCustomObject]@{ Name = "VLC Media Player"; ScriptName = "vlc.ps1"; WingetId = "VideoLAN.VLC"; Category = "Media"; Description = "Versatile media player for all formats" }
    [PSCustomObject]@{ Name = "OBS Studio"; ScriptName = "obs.ps1"; WingetId = "OBSProject.OBSStudio"; Category = "Media"; Description = "Live streaming and screen recording" }
    [PSCustomObject]@{ Name = "GIMP"; ScriptName = "gimp.ps1"; WingetId = "GIMP.GIMP"; Category = "Media"; Description = "Advanced image editing and manipulation" }
    [PSCustomObject]@{ Name = "Audacity"; ScriptName = "audacity.ps1"; WingetId = "Audacity.Audacity"; Category = "Media"; Description = "Multi-track audio editor and recorder" }
    [PSCustomObject]@{ Name = "Handbrake"; ScriptName = "handbrake.ps1"; WingetId = "HandBrake.HandBrake"; Category = "Media"; Description = "Video transcoder and converter" }
    [PSCustomObject]@{ Name = "OpenShot"; ScriptName = "openshot.ps1"; WingetId = "OpenShot.OpenShot"; Category = "Media"; Description = "Easy-to-use video editor" }
    [PSCustomObject]@{ Name = "Kdenlive"; ScriptName = "kdenlive.ps1"; WingetId = "KDE.Kdenlive"; Category = "Media"; Description = "Professional video editing suite" }
    [PSCustomObject]@{ Name = "Shotcut"; ScriptName = "shotcut.ps1"; WingetId = "Meltytech.Shotcut"; Category = "Media"; Description = "Cross-platform video editor" }
    [PSCustomObject]@{ Name = "ClipGrab"; ScriptName = "clipgrab.ps1"; WingetId = "Philipp Schmieder.ClipGrab"; Category = "Media"; Description = "Video downloader and converter" }
    [PSCustomObject]@{ Name = "Inkscape"; ScriptName = "inkscape.ps1"; WingetId = "Inkscape.Inkscape"; Category = "Media"; Description = "Vector graphics editor" }
    [PSCustomObject]@{ Name = "Paint.NET"; ScriptName = "paintdotnet.ps1"; WingetId = "dotPDN.PaintDotNet"; Category = "Media"; Description = "Simple yet powerful image editor" }
    [PSCustomObject]@{ Name = "Krita"; ScriptName = "krita.ps1"; WingetId = "KDE.Krita"; Category = "Media"; Description = "Digital painting and illustration tool" }
    [PSCustomObject]@{ Name = "Avidemux"; ScriptName = "avidemux.ps1"; WingetId = "Avidemux.Avidemux"; Category = "Media"; Description = "Simple video editing and filtering" }
    [PSCustomObject]@{ Name = "MPC-HC"; ScriptName = "mpchc.ps1"; WingetId = "clsid2.mpc-hc"; Category = "Media"; Description = "Lightweight media player" }
    [PSCustomObject]@{ Name = "Foobar2000"; ScriptName = "foobar2000.ps1"; WingetId = "PeterPawlowski.foobar2000"; Category = "Media"; Description = "Advanced audio player and organizer" }
    [PSCustomObject]@{ Name = "FFmpeg"; ScriptName = "ffmpeg.ps1"; WingetId = "Gyan.FFmpeg"; Category = "Media"; Description = "Multimedia framework for conversion" }
    [PSCustomObject]@{ Name = "OpenToonz"; ScriptName = "opentoonz.ps1"; WingetId = "OpenToonz.OpenToonz"; Category = "Media"; Description = "2D animation production software" }
    [PSCustomObject]@{ Name = "darktable"; ScriptName = "darktable.ps1"; WingetId = "darktable.darktable"; Category = "Media"; Description = "Photography workflow and RAW editor" }
    [PSCustomObject]@{ Name = "RawTherapee"; ScriptName = "rawtherapee.ps1"; WingetId = "RawTherapee.RawTherapee"; Category = "Media"; Description = "RAW image processing program" }
    [PSCustomObject]@{ Name = "Spotify"; ScriptName = "spotify.ps1"; WingetId = "Spotify.Spotify"; Category = "Media"; Description = "Music streaming service" }
    [PSCustomObject]@{ Name = "iTunes"; ScriptName = "itunes.ps1"; WingetId = "Apple.iTunes"; Category = "Media"; Description = "Media player and library manager" }
    [PSCustomObject]@{ Name = "MediaInfo"; ScriptName = "mediainfo.ps1"; WingetId = "MediaArea.MediaInfo"; Category = "Media"; Description = "Technical metadata viewer for media files" }
    [PSCustomObject]@{ Name = "MKVToolNix"; ScriptName = "mkvtoolnix.ps1"; WingetId = "MoritzBunkus.MKVToolNix"; Category = "Media"; Description = "Matroska video file editor" }
    [PSCustomObject]@{ Name = "DaVinci Resolve"; ScriptName = "davinciresolve.ps1"; WingetId = "Blackmagic.DaVinciResolve"; Category = "Media"; Description = "Professional video editing software" }
    [PSCustomObject]@{ Name = "Tenacity"; ScriptName = "tenacity.ps1"; WingetId = "Tenacity.Tenacity"; Category = "Media"; Description = "Multi-track audio editor fork of Audacity" }
    [PSCustomObject]@{ Name = "Blender"; ScriptName = "blender-media.ps1"; WingetId = "BlenderFoundation.Blender"; Category = "Media"; Description = "3D creation suite with video editing" }
    # Utilities
    [PSCustomObject]@{ Name = "PowerToys"; ScriptName = "powertoys.ps1"; WingetId = "Microsoft.PowerToys"; Category = "Utilities"; Description = "Windows system utilities by Microsoft" }
    [PSCustomObject]@{ Name = "Everything"; ScriptName = "everything.ps1"; WingetId = "voidtools.Everything"; Category = "Utilities"; Description = "Instant file search engine" }
    [PSCustomObject]@{ Name = "WinDirStat"; ScriptName = "windirstat.ps1"; WingetId = "WinDirStat.WinDirStat"; Category = "Utilities"; Description = "Disk usage statistics viewer" }
    [PSCustomObject]@{ Name = "TreeSize Free"; ScriptName = "treesizefree.ps1"; WingetId = "JAMSoftware.TreeSize.Free"; Category = "Utilities"; Description = "Disk space manager and analyzer" }
    [PSCustomObject]@{ Name = "CCleaner"; ScriptName = "ccleaner.ps1"; WingetId = "Piriform.CCleaner"; Category = "Utilities"; Description = "System cleaner and optimizer" }
    [PSCustomObject]@{ Name = "Greenshot"; ScriptName = "greenshot.ps1"; WingetId = "Greenshot.Greenshot"; Category = "Utilities"; Description = "Screenshot tool with annotations" }
    [PSCustomObject]@{ Name = "ShareX"; ScriptName = "sharex.ps1"; WingetId = "ShareX.ShareX"; Category = "Utilities"; Description = "Screen capture and file sharing" }
    [PSCustomObject]@{ Name = "Bulk Rename Utility"; ScriptName = "bulkrename.ps1"; WingetId = "TGRMNSoftware.BulkRenameUtility"; Category = "Utilities"; Description = "Advanced file renaming tool" }
    [PSCustomObject]@{ Name = "Revo Uninstaller"; ScriptName = "revouninstaller.ps1"; WingetId = "RevoUninstaller.RevoUninstaller"; Category = "Utilities"; Description = "Complete software removal tool" }
    [PSCustomObject]@{ Name = "Recuva"; ScriptName = "recuva.ps1"; WingetId = "Piriform.Recuva"; Category = "Utilities"; Description = "File recovery and undelete utility" }
    [PSCustomObject]@{ Name = "Speccy"; ScriptName = "speccy.ps1"; WingetId = "Piriform.Speccy"; Category = "Utilities"; Description = "System information and diagnostics" }
    [PSCustomObject]@{ Name = "HWiNFO"; ScriptName = "hwinfo.ps1"; WingetId = "REALiX.HWiNFO"; Category = "Utilities"; Description = "Hardware analysis and monitoring" }
    [PSCustomObject]@{ Name = "Core Temp"; ScriptName = "coretemp.ps1"; WingetId = "ALCPU.CoreTemp"; Category = "Utilities"; Description = "CPU temperature monitor" }
    [PSCustomObject]@{ Name = "GPU-Z"; ScriptName = "gpuz.ps1"; WingetId = "TechPowerUp.GPU-Z"; Category = "Utilities"; Description = "Graphics card information tool" }
    [PSCustomObject]@{ Name = "CrystalDiskInfo"; ScriptName = "crystaldiskinfo.ps1"; WingetId = "CrystalDewWorld.CrystalDiskInfo"; Category = "Utilities"; Description = "Hard drive health monitor" }
    [PSCustomObject]@{ Name = "Sysinternals Suite"; ScriptName = "sysinternals.ps1"; WingetId = "Microsoft.Sysinternals.Suite"; Category = "Utilities"; Description = "Advanced Windows troubleshooting tools" }
    [PSCustomObject]@{ Name = "AngryIP Scanner"; ScriptName = "angryip.ps1"; WingetId = "angryziber.AngryIPScanner"; Category = "Utilities"; Description = "Fast network IP scanner" }
    [PSCustomObject]@{ Name = "Bitvise SSH Client"; ScriptName = "bitvise.ps1"; WingetId = "Bitvise.SSH.Client"; Category = "Utilities"; Description = "SSH and SFTP client for Windows" }
    [PSCustomObject]@{ Name = "Belarc Advisor"; ScriptName = "belarc.ps1"; WingetId = $null; Category = "Utilities"; Description = "System profile and security status" }
    [PSCustomObject]@{ Name = "O&O ShutUp10"; ScriptName = "shutup10.ps1"; WingetId = $null; Category = "Utilities"; Description = "Windows privacy settings manager" }
    [PSCustomObject]@{ Name = "FileMail Desktop"; ScriptName = "filemail.ps1"; WingetId = $null; Category = "Utilities"; Description = "Large file transfer service" }
    [PSCustomObject]@{ Name = "BleachBit"; ScriptName = "bleachbit.ps1"; WingetId = "BleachBit.BleachBit"; Category = "Utilities"; Description = "System cleaner and privacy tool" }
    [PSCustomObject]@{ Name = "Rufus"; ScriptName = "rufus.ps1"; WingetId = "Rufus.Rufus"; Category = "Utilities"; Description = "Bootable USB drive creator" }
    [PSCustomObject]@{ Name = "Ventoy"; ScriptName = "ventoy.ps1"; WingetId = "Ventoy.Ventoy"; Category = "Utilities"; Description = "Multiboot USB solution" }
    [PSCustomObject]@{ Name = "Balena Etcher"; ScriptName = "balenaetcher.ps1"; WingetId = "Balena.Etcher"; Category = "Utilities"; Description = "Flash OS images to SD cards and USB drives" }
    [PSCustomObject]@{ Name = "CPU-Z"; ScriptName = "cpuz.ps1"; WingetId = "CPUID.CPU-Z"; Category = "Utilities"; Description = "CPU and system information utility" }
    [PSCustomObject]@{ Name = "CrystalDiskMark"; ScriptName = "crystaldiskmark.ps1"; WingetId = "CrystalDewWorld.CrystalDiskMark"; Category = "Utilities"; Description = "Disk benchmark utility" }
    [PSCustomObject]@{ Name = "HWMonitor"; ScriptName = "hwmonitor.ps1"; WingetId = "CPUID.HWMonitor"; Category = "Utilities"; Description = "Hardware monitoring program" }
    [PSCustomObject]@{ Name = "MSI Afterburner"; ScriptName = "msiafterburner.ps1"; WingetId = "Guru3D.Afterburner"; Category = "Utilities"; Description = "Graphics card overclocking utility" }
    [PSCustomObject]@{ Name = "Lightshot"; ScriptName = "lightshot.ps1"; WingetId = "Skillbrains.Lightshot"; Category = "Utilities"; Description = "Screenshot tool with instant sharing" }
    [PSCustomObject]@{ Name = "Process Hacker"; ScriptName = "processhacker.ps1"; WingetId = "ProcessHacker.ProcessHacker"; Category = "Utilities"; Description = "Advanced task manager alternative" }
    # Security
    [PSCustomObject]@{ Name = "Bitwarden"; ScriptName = "bitwarden.ps1"; WingetId = "Bitwarden.Bitwarden"; Category = "Security"; Description = "Open-source password manager" }
    [PSCustomObject]@{ Name = "KeePass"; ScriptName = "keepass.ps1"; WingetId = "DominikReichl.KeePass"; Category = "Security"; Description = "Secure password database manager" }
    [PSCustomObject]@{ Name = "VeraCrypt"; ScriptName = "veracrypt.ps1"; WingetId = "IDRIX.VeraCrypt"; Category = "Security"; Description = "Disk encryption software" }
    [PSCustomObject]@{ Name = "Malwarebytes"; ScriptName = "malwarebytes.ps1"; WingetId = "Malwarebytes.Malwarebytes"; Category = "Security"; Description = "Anti-malware and threat protection" }
    [PSCustomObject]@{ Name = "Avira Security"; ScriptName = "avira.ps1"; WingetId = "XPFD23M0L795KD"; Category = "Security"; Description = "Antivirus and security suite" }
    [PSCustomObject]@{ Name = "Kaspersky Security Cloud"; ScriptName = "kaspersky.ps1"; WingetId = "Kaspersky.KasperskySecurityCloud"; Category = "Security"; Description = "Cloud-based antivirus protection" }
    [PSCustomObject]@{ Name = "AVG AntiVirus Free"; ScriptName = "avg.ps1"; WingetId = "AVG.AVG"; Category = "Security"; Description = "Free antivirus protection" }
    [PSCustomObject]@{ Name = "Avast Free Antivirus"; ScriptName = "avast.ps1"; WingetId = "Avast.Avast.Free"; Category = "Security"; Description = "Comprehensive free antivirus" }
    [PSCustomObject]@{ Name = "Sophos Home"; ScriptName = "sophos.ps1"; WingetId = "Sophos.SophosHome"; Category = "Security"; Description = "Enterprise-grade home security" }
    [PSCustomObject]@{ Name = "KeePassXC"; ScriptName = "keepassxc.ps1"; WingetId = "KeePassXCTeam.KeePassXC"; Category = "Security"; Description = "Cross-platform password manager" }
    [PSCustomObject]@{ Name = "NordPass"; ScriptName = "nordpass.ps1"; WingetId = "NordSecurity.NordPass"; Category = "Security"; Description = "Secure password manager by NordVPN" }
    [PSCustomObject]@{ Name = "Proton Pass"; ScriptName = "protonpass.ps1"; WingetId = "Proton.ProtonPass"; Category = "Security"; Description = "Encrypted password manager by Proton" }
    # Communication
    [PSCustomObject]@{ Name = "Discord"; ScriptName = "discord.ps1"; WingetId = "Discord.Discord"; Category = "Communication"; Description = "Voice, video, and text chat platform" }
    [PSCustomObject]@{ Name = "Zoom"; ScriptName = "zoom.ps1"; WingetId = "Zoom.Zoom"; Category = "Communication"; Description = "Video conferencing and meetings" }
    [PSCustomObject]@{ Name = "Microsoft Teams"; ScriptName = "teams.ps1"; WingetId = "Microsoft.Teams"; Category = "Communication"; Description = "Collaboration and communication hub" }
    [PSCustomObject]@{ Name = "Skype"; ScriptName = "skype.ps1"; WingetId = "Microsoft.Skype"; Category = "Communication"; Description = "Video calls and instant messaging" }
    [PSCustomObject]@{ Name = "Slack"; ScriptName = "slack.ps1"; WingetId = "SlackTechnologies.Slack"; Category = "Communication"; Description = "Team collaboration and messaging" }
    [PSCustomObject]@{ Name = "Telegram Desktop"; ScriptName = "telegram.ps1"; WingetId = "Telegram.TelegramDesktop"; Category = "Communication"; Description = "Fast, secure messaging app" }
    [PSCustomObject]@{ Name = "Signal"; ScriptName = "signal.ps1"; WingetId = "OpenWhisperSystems.Signal"; Category = "Communication"; Description = "Privacy-focused encrypted messaging" }
    [PSCustomObject]@{ Name = "Thunderbird"; ScriptName = "thunderbird.ps1"; WingetId = "Mozilla.Thunderbird"; Category = "Communication"; Description = "Open-source email client" }
    [PSCustomObject]@{ Name = "WhatsApp Desktop"; ScriptName = "whatsapp.ps1"; WingetId = "WhatsApp.WhatsApp"; Category = "Communication"; Description = "Desktop messaging application" }
    [PSCustomObject]@{ Name = "Viber"; ScriptName = "viber.ps1"; WingetId = "Viber.Viber"; Category = "Communication"; Description = "Free calls and messages" }
    [PSCustomObject]@{ Name = "Element"; ScriptName = "element.ps1"; WingetId = "Element.Element"; Category = "Communication"; Description = "Secure decentralized messaging" }
    [PSCustomObject]@{ Name = "Jitsi Meet"; ScriptName = "jitsimeet.ps1"; WingetId = "Jitsi.Meet"; Category = "Communication"; Description = "Secure video conferencing" }
    [PSCustomObject]@{ Name = "Rocket.Chat"; ScriptName = "rocketchat.ps1"; WingetId = "RocketChat.RocketChat"; Category = "Communication"; Description = "Open-source team communication" }
    [PSCustomObject]@{ Name = "Mattermost Desktop"; ScriptName = "mattermost.ps1"; WingetId = "Mattermost.MattermostDesktop"; Category = "Communication"; Description = "Secure team collaboration platform" }
    # 3D & CAD
    [PSCustomObject]@{ Name = "Blender"; ScriptName = "blender.ps1"; WingetId = "BlenderFoundation.Blender"; Category = "3D & CAD"; Description = "3D modeling, animation, and rendering" }
    [PSCustomObject]@{ Name = "FreeCAD"; ScriptName = "freecad.ps1"; WingetId = "FreeCAD.FreeCAD"; Category = "3D & CAD"; Description = "Parametric 3D CAD modeler" }
    [PSCustomObject]@{ Name = "LibreCAD"; ScriptName = "librecad.ps1"; WingetId = "LibreCAD.LibreCAD"; Category = "3D & CAD"; Description = "2D CAD drafting application" }
    [PSCustomObject]@{ Name = "KiCad"; ScriptName = "kicad.ps1"; WingetId = "KiCad.KiCad"; Category = "3D & CAD"; Description = "Electronic design automation suite" }
    [PSCustomObject]@{ Name = "OpenSCAD"; ScriptName = "openscad.ps1"; WingetId = "OpenSCAD.OpenSCAD"; Category = "3D & CAD"; Description = "Script-based 3D CAD modeler" }
    [PSCustomObject]@{ Name = "Wings 3D"; ScriptName = "wings3d.ps1"; WingetId = "Wings3D.Wings3D"; Category = "3D & CAD"; Description = "Polygon mesh modeling tool" }
    [PSCustomObject]@{ Name = "Sweet Home 3D"; ScriptName = "sweethome3d.ps1"; WingetId = "eTeks.SweetHome3D"; Category = "3D & CAD"; Description = "Interior design and floor planning" }
    [PSCustomObject]@{ Name = "Dust3D"; ScriptName = "dust3d.ps1"; WingetId = "Dust3D.Dust3D"; Category = "3D & CAD"; Description = "3D modeling software" }
    [PSCustomObject]@{ Name = "MeshLab"; ScriptName = "meshlab.ps1"; WingetId = "ISTI.MeshLab"; Category = "3D & CAD"; Description = "3D mesh processing system" }
    [PSCustomObject]@{ Name = "Slic3r"; ScriptName = "slic3r.ps1"; WingetId = "Slic3r.Slic3r"; Category = "3D & CAD"; Description = "3D printing toolbox" }
    # Networking
    [PSCustomObject]@{ Name = "Wireshark"; ScriptName = "wireshark.ps1"; WingetId = "WiresharkFoundation.Wireshark"; Category = "Networking"; Description = "Network protocol analyzer" }
    [PSCustomObject]@{ Name = "Nmap"; ScriptName = "nmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking"; Description = "Network discovery and security scanner" }
    [PSCustomObject]@{ Name = "Zenmap"; ScriptName = "zenmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking"; Description = "GUI for Nmap security scanner" }
    [PSCustomObject]@{ Name = "PuTTY"; ScriptName = "putty.ps1"; WingetId = "PuTTY.PuTTY"; Category = "Networking"; Description = "SSH and telnet client" }
    [PSCustomObject]@{ Name = "Advanced IP Scanner"; ScriptName = "advancedipscanner.ps1"; WingetId = "Famatech.AdvancedIPScanner"; Category = "Networking"; Description = "Fast network scanner for Windows" }
    [PSCustomObject]@{ Name = "Fing CLI"; ScriptName = "fing.ps1"; WingetId = "Fing.Fing"; Category = "Networking"; Description = "Network scanning and troubleshooting" }
    [PSCustomObject]@{ Name = "GlassWire"; ScriptName = "glasswire.ps1"; WingetId = "GlassWire.GlassWire"; Category = "Networking"; Description = "Network security monitor and firewall" }
    [PSCustomObject]@{ Name = "NetLimiter"; ScriptName = "netlimiter.ps1"; WingetId = "Locktime.NetLimiter"; Category = "Networking"; Description = "Internet traffic control tool" }
    [PSCustomObject]@{ Name = "TCPView"; ScriptName = "tcpview.ps1"; WingetId = "Microsoft.Sysinternals.TCPView"; Category = "Networking"; Description = "Network connection viewer" }
    [PSCustomObject]@{ Name = "Fiddler Classic"; ScriptName = "fiddlerclassic.ps1"; WingetId = "Telerik.Fiddler.Classic"; Category = "Networking"; Description = "Web debugging proxy tool" }
    [PSCustomObject]@{ Name = "SoftPerfect Network Scanner"; ScriptName = "softperfectscanner.ps1"; WingetId = "SoftPerfect.NetworkScanner"; Category = "Networking"; Description = "Multi-threaded IP and NetBIOS scanner" }
    [PSCustomObject]@{ Name = "NetSetMan"; ScriptName = "netsetman.ps1"; WingetId = "NetSetMan.NetSetMan"; Category = "Networking"; Description = "Network settings manager" }
    [PSCustomObject]@{ Name = "Npcap"; ScriptName = "npcap.ps1"; WingetId = "Nmap.Npcap"; Category = "Networking"; Description = "Packet capture library for Windows" }
    [PSCustomObject]@{ Name = "Charles Proxy"; ScriptName = "charlesproxy.ps1"; WingetId = "XK72.Charles"; Category = "Networking"; Description = "HTTP proxy and monitor" }
    # Runtime Environments
    [PSCustomObject]@{ Name = "Java Runtime Environment"; ScriptName = "java.ps1"; WingetId = "Oracle.JavaRuntimeEnvironment"; Category = "Runtime"; Description = "Java application runtime" }
    [PSCustomObject]@{ Name = ".NET Desktop Runtime 6"; ScriptName = "dotnet6.ps1"; WingetId = "Microsoft.DotNet.DesktopRuntime.6"; Category = "Runtime"; Description = ".NET 6 desktop application runtime" }
    [PSCustomObject]@{ Name = ".NET Desktop Runtime 8"; ScriptName = "dotnet8.ps1"; WingetId = "Microsoft.DotNet.DesktopRuntime.8"; Category = "Runtime"; Description = ".NET 8 desktop application runtime" }
    [PSCustomObject]@{ Name = "Visual C++ Redistributable"; ScriptName = "vcredist.ps1"; WingetId = "Microsoft.VCRedist.2015+.x64"; Category = "Runtime"; Description = "Microsoft C++ runtime libraries" }
    [PSCustomObject]@{ Name = "Go Programming Language"; ScriptName = "golang.ps1"; WingetId = "GoLang.Go"; Category = "Runtime"; Description = "Go programming language runtime" }
    [PSCustomObject]@{ Name = "Rust"; ScriptName = "rust.ps1"; WingetId = "Rustlang.Rust.MSVC"; Category = "Runtime"; Description = "Rust programming language toolchain" }
    [PSCustomObject]@{ Name = "PHP"; ScriptName = "php.ps1"; WingetId = "PHP.PHP"; Category = "Runtime"; Description = "PHP scripting language runtime" }
    [PSCustomObject]@{ Name = "Microsoft OpenJDK 17"; ScriptName = "openjdk17.ps1"; WingetId = "Microsoft.OpenJDK.17"; Category = "Runtime"; Description = "Microsoft build of OpenJDK 17" }
    [PSCustomObject]@{ Name = "Microsoft OpenJDK 21"; ScriptName = "openjdk21.ps1"; WingetId = "Microsoft.OpenJDK.21"; Category = "Runtime"; Description = "Microsoft build of OpenJDK 21" }
    # Writing & Screenwriting
    [PSCustomObject]@{ Name = "Trelby"; ScriptName = "trelby.ps1"; WingetId = $null; Category = "Writing"; Description = "Screenplay writing software" }
    [PSCustomObject]@{ Name = "KIT Scenarist"; ScriptName = "kitscenarist.ps1"; WingetId = $null; Category = "Writing"; Description = "Screenwriting and story development" }
    [PSCustomObject]@{ Name = "Storyboarder"; ScriptName = "storyboarder.ps1"; WingetId = "Wonderunit.Storyboarder"; Category = "Writing"; Description = "Storyboard creation tool" }
    [PSCustomObject]@{ Name = "FocusWriter"; ScriptName = "focuswriter.ps1"; WingetId = "GottCode.FocusWriter"; Category = "Writing"; Description = "Distraction-free writing environment" }
    [PSCustomObject]@{ Name = "Manuskript"; ScriptName = "manuskript.ps1"; WingetId = "TheologicalElucidations.Manuskript"; Category = "Writing"; Description = "Novel writing and organization tool" }
    [PSCustomObject]@{ Name = "yWriter"; ScriptName = "ywriter.ps1"; WingetId = "Spacejock.yWriter"; Category = "Writing"; Description = "Word processor for novelists" }
    [PSCustomObject]@{ Name = "Celtx"; ScriptName = "celtx.ps1"; WingetId = "Celtx.Celtx"; Category = "Writing"; Description = "Screenwriting and production software" }
    [PSCustomObject]@{ Name = "bibisco"; ScriptName = "bibisco.ps1"; WingetId = "bibisco.bibisco"; Category = "Writing"; Description = "Novel writing software" }
    [PSCustomObject]@{ Name = "Scribus"; ScriptName = "scribus.ps1"; WingetId = "Scribus.Scribus"; Category = "Writing"; Description = "Desktop publishing software" }
    [PSCustomObject]@{ Name = "Grammarly"; ScriptName = "grammarly.ps1"; WingetId = "Grammarly.Grammarly"; Category = "Writing"; Description = "Writing assistant and grammar checker" }
    [PSCustomObject]@{ Name = "Hemingway Editor"; ScriptName = "hemingwayeditor.ps1"; WingetId = $null; Category = "Writing"; Description = "Writing improvement and readability tool" }
    # Gaming
    [PSCustomObject]@{ Name = "Steam"; ScriptName = "steam.ps1"; WingetId = "Valve.Steam"; Category = "Gaming"; Description = "Digital game distribution platform" }
    [PSCustomObject]@{ Name = "Epic Games Launcher"; ScriptName = "epicgames.ps1"; WingetId = "EpicGames.EpicGamesLauncher"; Category = "Gaming"; Description = "Epic Games store and launcher" }
    [PSCustomObject]@{ Name = "GOG Galaxy"; ScriptName = "goggalaxy.ps1"; WingetId = "GOG.Galaxy"; Category = "Gaming"; Description = "DRM-free game launcher" }
    [PSCustomObject]@{ Name = "EA App"; ScriptName = "eaapp.ps1"; WingetId = "ElectronicArts.EADesktop"; Category = "Gaming"; Description = "Electronic Arts game platform" }
    [PSCustomObject]@{ Name = "Ubisoft Connect"; ScriptName = "ubisoftconnect.ps1"; WingetId = "Ubisoft.Connect"; Category = "Gaming"; Description = "Ubisoft game launcher and store" }
    [PSCustomObject]@{ Name = "Battle.net"; ScriptName = "battlenet.ps1"; WingetId = "Blizzard.BattleNet"; Category = "Gaming"; Description = "Blizzard game launcher" }
    [PSCustomObject]@{ Name = "Itch.io"; ScriptName = "itchio.ps1"; WingetId = "ItchIo.Itch"; Category = "Gaming"; Description = "Indie game marketplace and launcher" }
    # Cloud Storage
    [PSCustomObject]@{ Name = "Google Drive"; ScriptName = "googledrive.ps1"; WingetId = "Google.GoogleDrive"; Category = "Cloud Storage"; Description = "Cloud storage and file sync by Google" }
    [PSCustomObject]@{ Name = "Dropbox"; ScriptName = "dropbox.ps1"; WingetId = "Dropbox.Dropbox"; Category = "Cloud Storage"; Description = "Cloud file storage and sharing" }
    [PSCustomObject]@{ Name = "OneDrive"; ScriptName = "onedrive.ps1"; WingetId = "Microsoft.OneDrive"; Category = "Cloud Storage"; Description = "Microsoft cloud storage service" }
    [PSCustomObject]@{ Name = "MEGA"; ScriptName = "mega.ps1"; WingetId = "Mega.MEGASync"; Category = "Cloud Storage"; Description = "Secure cloud storage with encryption" }
    [PSCustomObject]@{ Name = "pCloud"; ScriptName = "pcloud.ps1"; WingetId = "pCloud.pCloudDrive"; Category = "Cloud Storage"; Description = "Secure cloud storage solution" }
    [PSCustomObject]@{ Name = "Sync.com"; ScriptName = "sync.ps1"; WingetId = "Sync.Sync"; Category = "Cloud Storage"; Description = "Zero-knowledge encrypted cloud storage" }
    [PSCustomObject]@{ Name = "Box"; ScriptName = "box.ps1"; WingetId = "Box.Box"; Category = "Cloud Storage"; Description = "Cloud content management and file sharing" }
    # Remote Desktop
    [PSCustomObject]@{ Name = "TeamViewer"; ScriptName = "teamviewer.ps1"; WingetId = "TeamViewer.TeamViewer"; Category = "Remote Desktop"; Description = "Remote access and support software" }
    [PSCustomObject]@{ Name = "AnyDesk"; ScriptName = "anydesk.ps1"; WingetId = "AnyDeskSoftwareGmbH.AnyDesk"; Category = "Remote Desktop"; Description = "Fast remote desktop application" }
    [PSCustomObject]@{ Name = "Chrome Remote Desktop"; ScriptName = "chromeremote.ps1"; WingetId = "Google.ChromeRemoteDesktopHost"; Category = "Remote Desktop"; Description = "Remote access via Chrome browser" }
    [PSCustomObject]@{ Name = "TightVNC"; ScriptName = "tightvnc.ps1"; WingetId = "GlavSoft.TightVNC"; Category = "Remote Desktop"; Description = "Remote desktop control software" }
    [PSCustomObject]@{ Name = "RustDesk"; ScriptName = "rustdesk.ps1"; WingetId = "RustDesk.RustDesk"; Category = "Remote Desktop"; Description = "Open-source remote desktop software" }
    [PSCustomObject]@{ Name = "UltraVNC"; ScriptName = "ultravnc.ps1"; WingetId = "uvncbvba.UltraVnc"; Category = "Remote Desktop"; Description = "Powerful remote PC access software" }
    [PSCustomObject]@{ Name = "Parsec"; ScriptName = "parsec.ps1"; WingetId = "Parsec.Parsec"; Category = "Remote Desktop"; Description = "Low-latency remote desktop for gaming" }
    # Backup & Recovery
    [PSCustomObject]@{ Name = "Veeam Agent FREE"; ScriptName = "veeam.ps1"; WingetId = "Veeam.Agent.Windows"; Category = "Backup"; Description = "Free backup and recovery solution" }
    [PSCustomObject]@{ Name = "Macrium Reflect Free"; ScriptName = "macrium.ps1"; WingetId = "Macrium.ReflectFree"; Category = "Backup"; Description = "Disk imaging and cloning tool" }
    [PSCustomObject]@{ Name = "EaseUS Todo Backup Free"; ScriptName = "easeus.ps1"; WingetId = "EASEUSAG.EaseUSTodoBackupFree"; Category = "Backup"; Description = "Backup and disaster recovery" }
    [PSCustomObject]@{ Name = "Duplicati"; ScriptName = "duplicati.ps1"; WingetId = "Duplicati.Duplicati"; Category = "Backup"; Description = "Encrypted backup to cloud storage" }
    [PSCustomObject]@{ Name = "Cobian Backup"; ScriptName = "cobianbackup.ps1"; WingetId = "CobianSoft.CobianBackup"; Category = "Backup"; Description = "Multi-threaded backup application" }
    [PSCustomObject]@{ Name = "FreeFileSync"; ScriptName = "freefilesync.ps1"; WingetId = "FreeFileSync.FreeFileSync"; Category = "Backup"; Description = "File synchronization and backup" }
    [PSCustomObject]@{ Name = "Syncthing"; ScriptName = "syncthing.ps1"; WingetId = "Syncthing.Syncthing"; Category = "Backup"; Description = "Continuous file synchronization" }
    # Education
    [PSCustomObject]@{ Name = "Anki"; ScriptName = "anki.ps1"; WingetId = "Anki.Anki"; Category = "Education"; Description = "Flashcard-based learning system" }
    [PSCustomObject]@{ Name = "GeoGebra"; ScriptName = "geogebra.ps1"; WingetId = "GeoGebra.Classic"; Category = "Education"; Description = "Interactive math and geometry software" }
    [PSCustomObject]@{ Name = "Stellarium"; ScriptName = "stellarium.ps1"; WingetId = "Stellarium.Stellarium"; Category = "Education"; Description = "Planetarium and astronomy software" }
    [PSCustomObject]@{ Name = "MuseScore"; ScriptName = "musescore.ps1"; WingetId = "Musescore.Musescore"; Category = "Education"; Description = "Music notation and composition" }
    [PSCustomObject]@{ Name = "Moodle Desktop"; ScriptName = "moodle.ps1"; WingetId = "Moodle.MoodleDesktop"; Category = "Education"; Description = "Learning management system client" }
    [PSCustomObject]@{ Name = "Scratch Desktop"; ScriptName = "scratch.ps1"; WingetId = "MIT.Scratch"; Category = "Education"; Description = "Visual programming for kids" }
    [PSCustomObject]@{ Name = "Celestia"; ScriptName = "celestia.ps1"; WingetId = "CelestiaProject.Celestia"; Category = "Education"; Description = "3D space simulation software" }
    # Finance
    [PSCustomObject]@{ Name = "GnuCash"; ScriptName = "gnucash.ps1"; WingetId = "GnuCash.GnuCash"; Category = "Finance"; Description = "Personal and small business accounting" }
    [PSCustomObject]@{ Name = "HomeBank"; ScriptName = "homebank.ps1"; WingetId = "HomeBank.HomeBank"; Category = "Finance"; Description = "Personal finance management" }
    [PSCustomObject]@{ Name = "Money Manager Ex"; ScriptName = "moneymanagerex.ps1"; WingetId = "MoneyManagerEx.MoneyManagerEx"; Category = "Finance"; Description = "Easy-to-use finance tracker" }
    [PSCustomObject]@{ Name = "KMyMoney"; ScriptName = "kmymoney.ps1"; WingetId = "KDE.KMyMoney"; Category = "Finance"; Description = "Personal finance manager" }
    [PSCustomObject]@{ Name = "Skrooge"; ScriptName = "skrooge.ps1"; WingetId = "KDE.Skrooge"; Category = "Finance"; Description = "Personal finances manager" }
    [PSCustomObject]@{ Name = "Firefly III Desktop"; ScriptName = "fireflyiii.ps1"; WingetId = "mtoensing.FireflyIIIDesktop"; Category = "Finance"; Description = "Personal finance manager desktop client" }
    [PSCustomObject]@{ Name = "Buddi"; ScriptName = "buddi.ps1"; WingetId = $null; Category = "Finance"; Description = "Personal finance and budgeting software" }
    [PSCustomObject]@{ Name = "AceMoney Lite"; ScriptName = "acemoneylite.ps1"; WingetId = $null; Category = "Finance"; Description = "Personal finance management tool" }
    [PSCustomObject]@{ Name = "Actual Budget"; ScriptName = "actualbudget.ps1"; WingetId = "ActualBudget.ActualBudget"; Category = "Finance"; Description = "Local-first personal finance tool" }
    # Shortcuts & Maintenance
    [PSCustomObject]@{ Name = "Grok AI Shortcuts"; ScriptName = "grok-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Quick access to Grok AI assistant" }
    [PSCustomObject]@{ Name = "ChatGPT Shortcuts"; ScriptName = "chatgpt-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Quick access to ChatGPT" }
    [PSCustomObject]@{ Name = "dictation.io Shortcut"; ScriptName = "dictation-shortcut.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Web-based voice dictation tool" }
    [PSCustomObject]@{ Name = "Uninstall McAfee"; ScriptName = "uninstall-mcafee.ps1"; WingetId = $null; Category = "Maintenance"; Description = "Remove McAfee software completely" }
    [PSCustomObject]@{ Name = "PowerToys"; ScriptName = "powertoys.ps1"; WingetId = "Microsoft.PowerToys"; Category = "Shortcuts"; Description = "Windows system utilities and productivity tools" }
    [PSCustomObject]@{ Name = "Manage Restore Points"; ScriptName = "managerestorepoints.ps1"; WingetId = $null; Category = "Maintenance"; Description = "Automated Windows System Restore Point management" }
    [PSCustomObject]@{ Name = "AutoHotkey"; ScriptName = "autohotkey.ps1"; WingetId = "AutoHotkey.AutoHotkey"; Category = "Shortcuts"; Description = "Automation scripting language for Windows" }
    [PSCustomObject]@{ Name = "Everything"; ScriptName = "everything.ps1"; WingetId = "voidtools.Everything"; Category = "Shortcuts"; Description = "Instant file search utility" }
    # Mockups & Wireframe
    [PSCustomObject]@{ Name = "Figma"; ScriptName = "figma.ps1"; WingetId = "Figma.Figma"; Category = "Mockups & Wireframe"; Description = "Collaborative interface design tool" }
    [PSCustomObject]@{ Name = "Penpot"; ScriptName = "penpot.ps1"; WingetId = "Penpot.Penpot"; Category = "Mockups & Wireframe"; Description = "Open-source design and prototyping platform" }
    [PSCustomObject]@{ Name = "Draw.io Desktop"; ScriptName = "drawio.ps1"; WingetId = "JGraph.Draw"; Category = "Mockups & Wireframe"; Description = "Diagramming and wireframing tool" }
    [PSCustomObject]@{ Name = "Lunacy"; ScriptName = "lunacy.ps1"; WingetId = "Icons8.Lunacy"; Category = "Mockups & Wireframe"; Description = "Free graphic design software" }
    [PSCustomObject]@{ Name = "Pencil Project"; ScriptName = "pencilproject.ps1"; WingetId = "Pencil.Pencil"; Category = "Mockups & Wireframe"; Description = "GUI prototyping tool" }
    [PSCustomObject]@{ Name = "Akira"; ScriptName = "akira.ps1"; WingetId = $null; Category = "Mockups & Wireframe"; Description = "Native Linux design tool" }
    [PSCustomObject]@{ Name = "Quant-UX"; ScriptName = "quantux.ps1"; WingetId = $null; Category = "Mockups & Wireframe"; Description = "Prototyping and usability testing" }
    # Video Editing
    [PSCustomObject]@{ Name = "Lightworks"; ScriptName = "lightworks.ps1"; WingetId = "LWKS.Lightworks"; Category = "Video Editing"; Description = "Professional video editing software" }
    [PSCustomObject]@{ Name = "VSDC Free Video Editor"; ScriptName = "vsdcvideoeditor.ps1"; WingetId = "FlashIntegro.VSDCFreeVideoEditor"; Category = "Video Editing"; Description = "Non-linear video editing suite" }
    [PSCustomObject]@{ Name = "Olive Video Editor"; ScriptName = "olivevideoeditor.ps1"; WingetId = "OliveTeam.OliveVideoEditor"; Category = "Video Editing"; Description = "Free non-linear video editor" }
    [PSCustomObject]@{ Name = "VidCutter"; ScriptName = "vidcutter.ps1"; WingetId = "OzmosisGames.VidCutter"; Category = "Video Editing"; Description = "Simple video trimming and cutting" }
    [PSCustomObject]@{ Name = "LosslessCut"; ScriptName = "losslesscut.ps1"; WingetId = "mifi.losslesscut"; Category = "Video Editing"; Description = "Lossless video and audio trimmer" }
    [PSCustomObject]@{ Name = "Flowblade"; ScriptName = "flowblade.ps1"; WingetId = $null; Category = "Video Editing"; Description = "Multitrack non-linear video editor" }
    [PSCustomObject]@{ Name = "Cinelerra"; ScriptName = "cinelerra.ps1"; WingetId = $null; Category = "Video Editing"; Description = "Advanced video editing and compositing" }
    # Audio Production
    [PSCustomObject]@{ Name = "Cakewalk by BandLab"; ScriptName = "cakewalk.ps1"; WingetId = "BandLab.Cakewalk"; Category = "Audio Production"; Description = "Professional digital audio workstation" }
    [PSCustomObject]@{ Name = "LMMS"; ScriptName = "lmms.ps1"; WingetId = "LMMS.LMMS"; Category = "Audio Production"; Description = "Free music production software" }
    [PSCustomObject]@{ Name = "Ardour"; ScriptName = "ardour.ps1"; WingetId = "Ardour.Ardour"; Category = "Audio Production"; Description = "Professional DAW for recording and editing" }
    [PSCustomObject]@{ Name = "Ocenaudio"; ScriptName = "ocenaudio.ps1"; WingetId = "Ocenaudio.Ocenaudio"; Category = "Audio Production"; Description = "Easy-to-use audio editor" }
    [PSCustomObject]@{ Name = "Reaper"; ScriptName = "reaper.ps1"; WingetId = "Cockos.REAPER"; Category = "Audio Production"; Description = "Digital audio production application" }
    [PSCustomObject]@{ Name = "Mixxx"; ScriptName = "mixxx.ps1"; WingetId = "Mixxx.Mixxx"; Category = "Audio Production"; Description = "Free DJ mixing software" }
    [PSCustomObject]@{ Name = "Hydrogen"; ScriptName = "hydrogen.ps1"; WingetId = "Hydrogen.Hydrogen"; Category = "Audio Production"; Description = "Advanced drum machine and sequencer" }
    # Screen Recording & Streaming
    [PSCustomObject]@{ Name = "Streamlabs Desktop"; ScriptName = "streamlabsdesktop.ps1"; WingetId = "Streamlabs.StreamlabsOBS"; Category = "Screen Recording"; Description = "Live streaming software for content creators" }
    [PSCustomObject]@{ Name = "FlashBack Express"; ScriptName = "flashbackexpress.ps1"; WingetId = "Blueberry.FlashbackExpress"; Category = "Screen Recording"; Description = "Free screen recorder" }
    [PSCustomObject]@{ Name = "ScreenToGif"; ScriptName = "screentogif.ps1"; WingetId = "NickeManarin.ScreenToGif"; Category = "Screen Recording"; Description = "Screen, webcam and sketch recorder" }
    [PSCustomObject]@{ Name = "Flameshot"; ScriptName = "flameshot.ps1"; WingetId = "Flameshot.Flameshot"; Category = "Screen Recording"; Description = "Powerful screenshot and annotation tool" }
    [PSCustomObject]@{ Name = "Kap"; ScriptName = "kap.ps1"; WingetId = $null; Category = "Screen Recording"; Description = "Open-source screen recorder" }
    [PSCustomObject]@{ Name = "Peek"; ScriptName = "peek.ps1"; WingetId = $null; Category = "Screen Recording"; Description = "Simple animated GIF screen recorder" }
    [PSCustomObject]@{ Name = "SimpleScreenRecorder"; ScriptName = "simplescreenrecorder.ps1"; WingetId = $null; Category = "Screen Recording"; Description = "Feature-rich screen recorder" }

    # Photography
    [PSCustomObject]@{ Name = "digiKam"; ScriptName = "digikam.ps1"; WingetId = "KDE.digiKam"; Category = "Photography"; Description = "Photo management and RAW processing" }
    [PSCustomObject]@{ Name = "ImageGlass"; ScriptName = "imageglass.ps1"; WingetId = "DuongDieuPhap.ImageGlass"; Category = "Photography"; Description = "Fast, lightweight image viewer" }
    [PSCustomObject]@{ Name = "XnView MP"; ScriptName = "xnviewmp.ps1"; WingetId = "XnSoft.XnViewMP"; Category = "Photography"; Description = "Image viewer and organizer" }

    # Virtualization
    [PSCustomObject]@{ Name = "Oracle VM VirtualBox"; ScriptName = "virtualbox.ps1"; WingetId = "Oracle.VirtualBox"; Category = "Virtualization"; Description = "General-purpose x86 virtualization platform" }
    [PSCustomObject]@{ Name = "VMware Workstation Player"; ScriptName = "vmwareplayer.ps1"; WingetId = "VMware.WorkstationPlayer"; Category = "Virtualization"; Description = "Free virtual machine player for Windows" }
    [PSCustomObject]@{ Name = "Multipass"; ScriptName = "multipass.ps1"; WingetId = "Canonical.Multipass"; Category = "Virtualization"; Description = "Lightweight VM manager for Ubuntu instances" }

    # Database Tools
    [PSCustomObject]@{ Name = "SQL Server Management Studio"; ScriptName = "ssms.ps1"; WingetId = "Microsoft.SQLServerManagementStudio"; Category = "Database Tools"; Description = "SQL Server administration and query tool" }
    [PSCustomObject]@{ Name = "Azure Data Studio"; ScriptName = "azuredatastudio.ps1"; WingetId = "Microsoft.AzureDataStudio"; Category = "Database Tools"; Description = "Cross-platform database development tool" }
    [PSCustomObject]@{ Name = "MongoDB Compass"; ScriptName = "mongodbcompass.ps1"; WingetId = "MongoDB.Compass"; Category = "Database Tools"; Description = "GUI for MongoDB databases" }

    # System Monitoring
    [PSCustomObject]@{ Name = "Open Hardware Monitor"; ScriptName = "openhardwaremonitor.ps1"; WingetId = "OpenHardwareMonitor.OpenHardwareMonitor"; Category = "System Monitoring"; Description = "Hardware temperature and load monitoring" }
    [PSCustomObject]@{ Name = "Rainmeter"; ScriptName = "rainmeter.ps1"; WingetId = "Rainmeter.Rainmeter"; Category = "System Monitoring"; Description = "Customizable desktop system monitoring widgets" }
    [PSCustomObject]@{ Name = "NetWorx"; ScriptName = "networx.ps1"; WingetId = "SoftPerfect.NetWorx"; Category = "System Monitoring"; Description = "Network bandwidth usage monitor" }

    # Streaming Tools
    [PSCustomObject]@{ Name = "Twitch Studio"; ScriptName = "twitchstudio.ps1"; WingetId = "Twitch.TwitchStudio"; Category = "Streaming Tools"; Description = "Streaming studio for Twitch creators" }
    [PSCustomObject]@{ Name = "Voicemeeter Banana"; ScriptName = "voicemeeterbanana.ps1"; WingetId = "VB-Audio.VoicemeeterBanana"; Category = "Streaming Tools"; Description = "Virtual audio mixer for streaming setups" }
    [PSCustomObject]@{ Name = "Streamlink"; ScriptName = "streamlink.ps1"; WingetId = "Streamlink.Streamlink"; Category = "Streaming Tools"; Description = "Command-line utility to pipe online streams to media players" }
)

#region Self-Installation to System Location

function Copy-ScriptToSystemLocation {
    <#
    .SYNOPSIS
        Copies the installer script and all dependent files to the system location.

    .DESCRIPTION
        Ensures the installer is always available in a known system location:
        %SystemDrive%\mytech.today\app_installer\

        This allows scheduled tasks and other automation to reliably find the script
        regardless of where it was originally run from.
    #>
    [CmdletBinding()]
    param()

    try {
        # Define paths
        $systemPath = $script:SystemInstallPath
        $systemAppsPath = Join-Path $systemPath "apps"
        $systemProfilesPath = Join-Path $systemPath "profiles"
        $sourcePath = $script:OriginalScriptPath
        $sourceAppsPath = Join-Path $sourcePath "apps"
        $sourceProfilesPath = Join-Path $sourcePath "profiles"

        # Check if we're already running from the system location
        if ($sourcePath -eq $systemPath) {
            Write-Host "[i] Already running from system location: $systemPath" -ForegroundColor Cyan
            return $true
        }

        Write-Host "`n[i] Installing to system location..." -ForegroundColor Cyan
        Write-Host "    Source: $sourcePath" -ForegroundColor Gray
        Write-Host "    Target: $systemPath" -ForegroundColor Gray

        # Create system directories if they don't exist
        if (-not (Test-Path $systemPath)) {
            Write-Host "    [>>] Creating directory: $systemPath" -ForegroundColor Yellow
            New-Item -Path $systemPath -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $systemAppsPath)) {
            Write-Host "    [>>] Creating directory: $systemAppsPath" -ForegroundColor Yellow
            New-Item -Path $systemAppsPath -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $systemProfilesPath)) {
            Write-Host "    [>>] Creating directory: $systemProfilesPath" -ForegroundColor Yellow
            New-Item -Path $systemProfilesPath -ItemType Directory -Force | Out-Null
        }

        # Copy main install.ps1 script
        $sourceInstallScript = Join-Path $sourcePath "install.ps1"
        $targetInstallScript = Join-Path $systemPath "install.ps1"

        if (Test-Path $sourceInstallScript) {
            Write-Host "    [>>] Copying install.ps1..." -ForegroundColor Yellow
            Copy-Item -Path $sourceInstallScript -Destination $targetInstallScript -Force -ErrorAction Stop
        }

        # Copy install-gui.ps1 script
        $sourceGuiScript = Join-Path $sourcePath "install-gui.ps1"
        $targetGuiScript = Join-Path $systemPath "install-gui.ps1"

        if (Test-Path $sourceGuiScript) {
            Write-Host "    [>>] Copying install-gui.ps1..." -ForegroundColor Yellow
            Copy-Item -Path $sourceGuiScript -Destination $targetGuiScript -Force -ErrorAction Stop
        }

        # Copy all app scripts from apps\ folder
        if (Test-Path $sourceAppsPath) {
            Write-Host "    [>>] Copying app scripts..." -ForegroundColor Yellow
            $appScripts = Get-ChildItem -Path $sourceAppsPath -Filter "*.ps1" -File

            foreach ($script in $appScripts) {
                $targetScript = Join-Path $systemAppsPath $script.Name
                Copy-Item -Path $script.FullName -Destination $targetScript -Force -ErrorAction Stop
            }

            Write-Host "    [OK] Copied $($appScripts.Count) app scripts" -ForegroundColor Green
        }

        # Copy documentation files (optional but helpful)
        $docFiles = @("CHANGELOG.md", "README.md")
        foreach ($docFile in $docFiles) {
            $sourceDoc = Join-Path $sourcePath $docFile
            $targetDoc = Join-Path $systemPath $docFile

            if (Test-Path $sourceDoc) {
                Copy-Item -Path $sourceDoc -Destination $targetDoc -Force -ErrorAction SilentlyContinue
            }
        }

        # Copy profiles directory (if it exists)
        if (Test-Path $sourceProfilesPath) {
            Write-Host "    [>>] Copying profiles directory..." -ForegroundColor Yellow

            if (-not (Test-Path $systemProfilesPath)) {
                New-Item -Path $systemProfilesPath -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path (Join-Path $sourceProfilesPath '*') -Destination $systemProfilesPath -Recurse -Force -ErrorAction Stop
            Write-Host "    [OK] Copied profiles directory" -ForegroundColor Green
        }
        else {
            Write-Host "    [i] No profiles directory found at source: $sourceProfilesPath" -ForegroundColor DarkGray
        }

        Write-Host "    [OK] Installation to system location complete!" -ForegroundColor Green
        Write-Host "    Location: $systemPath" -ForegroundColor Gray

        return $true
    }
    catch {
        Write-Host "    [X] Failed to copy to system location: $_" -ForegroundColor Red
        Write-Host "    [i] Continuing with current location..." -ForegroundColor Yellow

        # Fall back to original location
        $script:ScriptPath = $script:OriginalScriptPath
        $script:AppsPath = Join-Path $script:ScriptPath "apps"
        $script:ProfilesPath = Join-Path $script:ScriptPath "profiles"

        return $false
    }
}

# Copy script to system location (first thing the script does)
Write-Host "+===================================================================+" -ForegroundColor Cyan
Write-Host "|         myTech.Today Application Installer GUI v$script:ScriptVersion          |" -ForegroundColor Cyan
Write-Host "+===================================================================+" -ForegroundColor Cyan

$copiedToSystem = Copy-ScriptToSystemLocation
Write-Host ""  # Blank line for spacing

# Update script paths to use system location
if ($copiedToSystem) {
    $script:ScriptPath = $script:SystemInstallPath
    $script:AppsPath = Join-Path $script:ScriptPath "apps"
    $script:ProfilesPath = Join-Path $script:ScriptPath "profiles"
}

#endregion Self-Installation to System Location

#region Helper Functions

function Initialize-Logging {
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path $script:CentralLogPath)) {
            New-Item -ItemType Directory -Path $script:CentralLogPath -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $script:LogPath = Join-Path $script:CentralLogPath "app_installer_gui_$timestamp.log"

        Write-Log "=== myTech.Today Application Installer GUI v$script:ScriptVersion ===" -Level INFO
        Write-Log "Log initialized at: $script:LogPath" -Level INFO

        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to initialize logging: $($_.Exception.Message)",
            "Logging Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue
    }
}

function Write-Output {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Black
    )

    if ($script:WebBrowser -and $script:WebBrowser.Document) {
        # Map System.Drawing.Color to WCAG AAA compliant colors for dark background
        # These colors meet accessibility standards with 7:1+ contrast ratio on #1e1e1e background
        $accessibleColor = switch ($Color.Name) {
            "Blue"      { "#4fc1ff" }  # Light cyan-blue (was #0000FF - poor contrast)
            "Green"     { "#4ec9b0" }  # Teal-green (accessible)
            "Red"       { "#f48771" }  # Light salmon-red (accessible)
            "Yellow"    { "#dcdcaa" }  # Light yellow (accessible)
            "Orange"    { "#ce9178" }  # Light orange (accessible)
            "Cyan"      { "#4fc1ff" }  # Light cyan (accessible)
            "Gray"      { "#808080" }  # Medium gray (accessible)
            "White"     { "#d4d4d4" }  # Off-white (accessible)
            "Black"     { "#d4d4d4" }  # Map black to off-white for visibility
            default {
                # For any other color, convert to hex and use as-is
                # (assuming custom colors are already chosen for accessibility)
                "#{0:X2}{1:X2}{2:X2}" -f $Color.R, $Color.G, $Color.B
            }
        }

        # Escape HTML special characters
        $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($Message)

        # Replace newlines with <br> tags
        $escapedMessage = $escapedMessage -replace "`r`n", "<br>" -replace "`n", "<br>"

        # Append to HTML content with console styling (monospace font)
        $htmlLine = "<div class='console-line' style='color: $accessibleColor;'>$escapedMessage</div>"

        try {
            $contentDiv = $script:WebBrowser.Document.GetElementById("content")
            if ($contentDiv) {
                $contentDiv.InnerHtml += $htmlLine
                # Scroll to bottom
                $script:WebBrowser.Document.Window.ScrollTo(0, $script:WebBrowser.Document.Body.ScrollRectangle.Height)
            }
        }
        catch {
            # Silently ignore errors during HTML append
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

    try {
        # Check if running on Windows 10
        $osVersion = [System.Environment]::OSVersion.Version
        $isWindows10 = $osVersion.Major -eq 10 -and $osVersion.Build -lt 22000

        if (-not $isWindows10) {
            Write-Log "Not running on Windows 10, skipping winget installation" -Level INFO
            return $false
        }

        Write-Output "Detected Windows 10. Installing winget (Windows Package Manager)..." -Color ([System.Drawing.Color]::Cyan)
        Write-Log "Installing winget on Windows 10" -Level INFO

        $tempDir = Join-Path $env:TEMP "winget_install"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Install VCLibs dependency
        Write-Output "  Downloading VCLibs dependency..." -Color ([System.Drawing.Color]::Gray)
        $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vcLibsPath = Join-Path $tempDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Invoke-WebRequest -Uri $vcLibsUrl -OutFile $vcLibsPath -UseBasicParsing
        Write-Output "  Installing VCLibs..." -Color ([System.Drawing.Color]::Gray)
        Add-AppxPackage -Path $vcLibsPath -ErrorAction SilentlyContinue

        # Install UI.Xaml dependency
        Write-Output "  Downloading UI.Xaml dependency..." -Color ([System.Drawing.Color]::Gray)
        $uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        $uiXamlPath = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.x64.appx"
        Invoke-WebRequest -Uri $uiXamlUrl -OutFile $uiXamlPath -UseBasicParsing
        Write-Output "  Installing UI.Xaml..." -Color ([System.Drawing.Color]::Gray)
        Add-AppxPackage -Path $uiXamlPath -ErrorAction SilentlyContinue

        # Get latest winget release
        Write-Output "  Fetching latest winget release information..." -Color ([System.Drawing.Color]::Gray)
        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $msixBundleUrl = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url

        if (-not $msixBundleUrl) {
            Write-Log "Failed to find winget msixbundle in latest release" -Level ERROR
            Write-Output "  [X] Failed to find winget download URL" -Color ([System.Drawing.Color]::Red)
            return $false
        }

        # Download and install winget
        Write-Output "  Downloading winget..." -Color ([System.Drawing.Color]::Gray)
        $wingetPath = Join-Path $tempDir "Microsoft.DesktopAppInstaller.msixbundle"
        Invoke-WebRequest -Uri $msixBundleUrl -OutFile $wingetPath -UseBasicParsing

        Write-Output "  Installing winget..." -Color ([System.Drawing.Color]::Gray)
        Add-AppxPackage -Path $wingetPath

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        # Verify installation
        Start-Sleep -Seconds 2
        $wingetInstalled = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        if ($wingetInstalled) {
            Write-Output "  [OK] winget installed successfully!" -Color ([System.Drawing.Color]::Green)
            Write-Log "winget installed successfully on Windows 10" -Level SUCCESS
            return $true
        }
        else {
            Write-Output "  [X] winget installation completed but command not found" -Color ([System.Drawing.Color]::Red)
            Write-Log "winget installation completed but command not available" -Level WARNING
            return $false
        }
    }
    catch {
        Write-Log "Failed to install winget: $($_.Exception.Message)" -Level ERROR
        Write-Output "  [X] Failed to install winget: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red)
        return $false
    }
}

function Test-WingetAvailable {
    [CmdletBinding()]
    param()

    try {
        $wingetPath = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Winget is not available on this system" -Level WARNING
        return $false
    }
}

function Ensure-WingetAvailable {
    <#
    .SYNOPSIS
        Ensures winget is available, installing it on Windows 10 if necessary.

    .DESCRIPTION
        Checks if winget is available. If not and running on Windows 10,
        automatically downloads and installs winget.
    #>
    [CmdletBinding()]
    param()

    if (Test-WingetAvailable) {
        return $true
    }

    # Check if running on Windows 10
    $osVersion = [System.Environment]::OSVersion.Version
    $isWindows10 = $osVersion.Major -eq 10 -and $osVersion.Build -lt 22000

    if ($isWindows10) {
        Write-Output "winget not found. Attempting to install on Windows 10..." -Color ([System.Drawing.Color]::Yellow)
        $installed = Install-WingetOnWindows10

        if ($installed) {
            return $true
        }
        else {
            Write-Output "Failed to install winget automatically. Please install 'App Installer' from Microsoft Store." -Color ([System.Drawing.Color]::Red)
            return $false
        }
    }
    else {
        Write-Output "winget not found. Please install 'App Installer' from Microsoft Store." -Color ([System.Drawing.Color]::Red)
        return $false
    }
}

function Get-InstalledApplications {
    [CmdletBinding()]
    param()

    Write-Output "Detecting installed applications..." -Color ([System.Drawing.Color]::Blue)
    Write-Log "Starting application detection" -Level INFO

    $installedApps = @{}

    try {
        # Try using winget list first (faster and more accurate for winget-installed apps)
        if (Test-WingetAvailable) {
            Write-Log "Using winget list for application detection" -Level INFO
            $wingetList = winget list --accept-source-agreements 2>$null | Out-String

            foreach ($app in $script:Applications) {
                if ($app.WingetId) {
                    # Check if the winget ID is in the list
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
                        Write-Log "Detected via winget: $($app.Name) - $version" -Level INFO
                    }
                }
            }
        }

        # Fallback: Check registry for installed programs (catches apps not in winget)
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $registryApps = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion

        foreach ($app in $script:Applications) {
            # Only check registry if not already found via winget
            if (-not $installedApps.ContainsKey($app.Name)) {
                $match = $registryApps | Where-Object { $_.DisplayName -like "*$($app.Name)*" } | Select-Object -First 1
                if ($match) {
                    $version = if ($match.DisplayVersion) { $match.DisplayVersion } else { "Installed" }
                    $installedApps[$app.Name] = $version
                    Write-Log "Detected via registry: $($app.Name) - $version" -Level INFO
                }
            }
        }

        # Special handling: Check for O&O ShutUp10 by executable path
        # O&O ShutUp10 may not register in standard registry locations
        if (-not $installedApps.ContainsKey("O&O ShutUp10")) {
            $ooShutUpPath = "C:\Program Files\OOShutUp10\OOSU10.exe"
            if (Test-Path $ooShutUpPath) {
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
            $manageRPPath = "$env:USERPROFILE\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1"
            if (Test-Path $manageRPPath) {
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
            if (-not (Test-Path $shortcutPath)) {
                Write-Log "Chrome Remote Desktop is installed but shortcut is missing - will create it" -Level INFO
                $shortcutCreated = New-WebApplicationShortcut `
                    -ShortcutName "Chrome Remote Desktop" `
                    -Url "https://remotedesktop.google.com/access" `
                    -Description "Configure and access Chrome Remote Desktop"

                if ($shortcutCreated) {
                    Write-Log "Created missing shortcut for Chrome Remote Desktop" -Level SUCCESS
                }
            }
            else {
                Write-Log "Chrome Remote Desktop shortcut already exists" -Level INFO
            }
        }
    }
    catch {
        Write-Log "Error detecting installed applications: $($_.Exception.Message)" -Level WARNING
    }

    Write-Log "Found $($installedApps.Count) installed applications" -Level INFO
    Write-Output "Found $($installedApps.Count) installed applications" -Color ([System.Drawing.Color]::Green)

    return $installedApps
}

function Show-ToastNotification {
    <#
    .SYNOPSIS
        Shows a Windows Toast notification using native Windows.UI.Notifications API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    try {
        # Load required assemblies for Toast notifications
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        # Define the app ID (use PowerShell's app ID)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

        # Create the toast XML
        $toastXml = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$([System.Security.SecurityElement]::Escape($Title))</text>
            <text>$([System.Security.SecurityElement]::Escape($Message))</text>
        </binding>
    </visual>
    <audio silent="false"/>
</toast>
"@

        # Load the XML
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($toastXml)

        # Create and show the toast
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)

        Write-Log "Toast notification shown: $Title - $Message" -Level INFO
    }
    catch {
        # Silently fail if toast notifications aren't available
        Write-Log "Failed to show toast notification: $($_.Exception.Message)" -Level WARNING
    }
}

#endregion Helper Functions

#region Installation Functions

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

function Get-AvailableUpdates {
    <#
    .SYNOPSIS
        Checks for available updates for installed applications using winget.

    .DESCRIPTION
        Runs 'winget upgrade' to detect applications with available updates.
        Parses the output and returns an array of update objects with app details.

    .OUTPUTS
        Array of PSCustomObject with properties: Name, Id, CurrentVersion, AvailableVersion, Source

    .EXAMPLE
        $updates = Get-AvailableUpdates
        Write-Host "Found $($updates.Count) updates available"
    #>
    [CmdletBinding()]
    param()

    Write-Log "Checking for available updates using winget upgrade" -Level INFO

    try {
        # Run winget upgrade to get list of available updates
        $wingetOutput = winget upgrade 2>&1 | Out-String

        Write-Log "Winget upgrade command completed" -Level INFO

        # Parse the output
        $updates = @()
        $lines = $wingetOutput -split "`r?`n"

        # Find the header line (contains "Name", "Id", "Version", "Available")
        $headerIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "Name.*Id.*Version.*Available") {
                $headerIndex = $i
                break
            }
        }

        if ($headerIndex -eq -1) {
            Write-Log "No updates available or unable to parse winget output" -Level INFO
            return @()
        }

        # Find the separator line (dashes)
        $separatorIndex = $headerIndex + 1
        if ($separatorIndex -ge $lines.Count -or $lines[$separatorIndex] -notmatch "^-+") {
            Write-Log "Unable to find separator line in winget output" -Level WARNING
            return @()
        }

        # Parse each update line
        for ($i = $separatorIndex + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()

            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            # Stop at summary line (e.g., "2 upgrades available")
            if ($line -match "^\d+\s+upgrade") {
                break
            }

            # Parse the line - winget output is space-separated with variable spacing
            # Format: Name  Id  Version  Available  Source
            $parts = $line -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($parts.Count -ge 4) {
                $updateObj = [PSCustomObject]@{
                    Name = $parts[0].Trim()
                    Id = $parts[1].Trim()
                    CurrentVersion = $parts[2].Trim()
                    AvailableVersion = $parts[3].Trim()
                    Source = if ($parts.Count -ge 5) { $parts[4].Trim() } else { "winget" }
                }

                $updates += $updateObj
                Write-Log "Found update: $($updateObj.Name) ($($updateObj.CurrentVersion) -> $($updateObj.AvailableVersion))" -Level INFO
            }
        }

        Write-Log "Found $($updates.Count) application(s) with available updates" -Level INFO
        return $updates
    }
    catch {
        Write-Log "Error checking for updates: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Get-PackageDependencies {
    <#
    .SYNOPSIS
        Retrieves package dependencies from winget.

    .DESCRIPTION
        Queries winget to get the list of dependencies for a specific package.
        Parses the output to extract package dependencies.

    .PARAMETER PackageId
        The winget package ID to check for dependencies.

    .OUTPUTS
        Array of dependency package IDs, or empty array if none found.

    .EXAMPLE
        $deps = Get-PackageDependencies -PackageId "TheDocumentFoundation.LibreOffice"
        # Returns: @("Microsoft.VCRedist.2015+.x64")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    try {
        Write-Log "Checking dependencies for package: $PackageId" -Level INFO

        # Run winget show to get package details including dependencies
        $output = & cmd /c "winget show --id `"$PackageId`" 2>&1"

        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to get package info for $PackageId (exit code: $LASTEXITCODE)" -Level WARNING
            return @()
        }

        $outputStr = $output | Out-String
        $dependencies = @()

        # Parse dependencies section
        # Look for "Dependencies:" followed by "Package Dependencies:"
        if ($outputStr -match "Dependencies:[\s\S]*?Package Dependencies:\s*\n([\s\S]*?)(?:\n\s*\n|\n[A-Z]|\z)") {
            $depsSection = $matches[1]

            # Extract package IDs (they typically don't have leading spaces or are indented)
            $lines = $depsSection -split "`r?`n"
            foreach ($line in $lines) {
                $line = $line.Trim()
                if ($line -and $line -notmatch "^\s*-" -and $line -match "^[A-Za-z0-9\.\+]+") {
                    $dependencies += $line
                    Write-Log "Found dependency: $line" -Level INFO
                }
            }
        }

        if ($dependencies.Count -gt 0) {
            Write-Log "Package $PackageId has $($dependencies.Count) package dependencies" -Level INFO
        }
        else {
            Write-Log "Package $PackageId has no package dependencies" -Level INFO
        }

        return $dependencies
    }
    catch {
        Write-Log "Error checking dependencies for $PackageId : $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Install-PackageDependencies {
    <#
    .SYNOPSIS
        Installs missing package dependencies automatically.

    .DESCRIPTION
        Checks if dependencies are installed and installs missing ones.
        Logs all operations and handles errors gracefully.

    .PARAMETER Dependencies
        Array of dependency package IDs to install.

    .PARAMETER PackageName
        Name of the main package (for logging purposes).

    .OUTPUTS
        Boolean - True if all dependencies are satisfied, False otherwise.

    .EXAMPLE
        $success = Install-PackageDependencies -Dependencies @("Microsoft.VCRedist.2015+.x64") -PackageName "LibreOffice"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Dependencies,

        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    if ($Dependencies.Count -eq 0) {
        return $true
    }

    Write-Log "Installing dependencies for $PackageName..." -Level INFO
    Write-Output "  [DEPS] Checking $($Dependencies.Count) dependencies..." -Color ([System.Drawing.Color]::Gray)

    $allSuccess = $true

    foreach ($depId in $Dependencies) {
        try {
            Write-Log "Checking dependency: $depId" -Level INFO

            # Check if dependency is already installed
            $checkOutput = & cmd /c "winget list --id `"$depId`" --exact 2>&1"
            $isInstalled = $LASTEXITCODE -eq 0 -and ($checkOutput | Out-String) -match $depId

            if ($isInstalled) {
                Write-Log "Dependency $depId is already installed" -Level INFO
                Write-Output "  [OK] $depId (already installed)" -Color ([System.Drawing.Color]::Green)
                continue
            }

            # Install the dependency
            Write-Log "Installing dependency: $depId" -Level INFO
            Write-Output "  [INSTALL] Installing $depId..." -Color ([System.Drawing.Color]::Cyan)

            $installCmd = "winget install --id `"$depId`" --silent --accept-source-agreements --accept-package-agreements"
            $installOutput = & cmd /c "$installCmd 2>&1"
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0 -or ($installOutput | Out-String) -match "Successfully installed") {
                Write-Log "Successfully installed dependency: $depId" -Level SUCCESS
                Write-Output "  [OK] $depId installed successfully" -Color ([System.Drawing.Color]::Green)
            }
            else {
                Write-Log "Failed to install dependency $depId (exit code: $exitCode)" -Level WARNING
                Write-Output "  [WARN] $depId installation failed (continuing anyway)" -Color ([System.Drawing.Color]::Orange)
                # Don't fail the whole process - winget will try to install it again with the main package
            }
        }
        catch {
            Write-Log "Exception installing dependency $depId : $($_.Exception.Message)" -Level WARNING
            Write-Output "  [WARN] $depId error (continuing anyway)" -Color ([System.Drawing.Color]::Orange)
            # Don't fail - let winget handle it
        }

        # Process Windows messages to keep UI responsive
        if ($script:ListView) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    return $allSuccess
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Updates
    )

    Write-Log "Starting update process for $($Updates.Count) application(s)" -Level INFO

    $successCount = 0
    $failCount = 0
    $results = @()

    foreach ($update in $Updates) {
        Write-Log "Updating $($update.Name) from $($update.CurrentVersion) to $($update.AvailableVersion)" -Level INFO
        Write-Output "[UPDATE] Updating $($update.Name)..." -Color ([System.Drawing.Color]::Blue)

        try {
            # Check and install dependencies first
            $dependencies = Get-PackageDependencies -PackageId $update.Id
            if ($dependencies.Count -gt 0) {
                Write-Log "Package $($update.Name) has $($dependencies.Count) dependencies" -Level INFO
                Install-PackageDependencies -Dependencies $dependencies -PackageName $update.Name | Out-Null
            }

            # Run winget upgrade for this specific app with retry logic
            $maxRetries = 3
            $retryCount = 0
            $updateSucceeded = $false
            $lastError = ""
            $lastExitCode = 0

            while ($retryCount -lt $maxRetries -and -not $updateSucceeded) {
                if ($retryCount -gt 0) {
                    Write-Log "Retry attempt $retryCount for $($update.Name)" -Level INFO
                    Write-Output "  [RETRY] Attempt $($retryCount + 1) of $maxRetries..." -Color ([System.Drawing.Color]::Yellow)
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
                Write-Output "[OK] $($update.Name) updated successfully" -Color ([System.Drawing.Color]::Green)
                $successCount++

                $results += [PSCustomObject]@{
                    Name = $update.Name
                    Success = $true
                    Message = "Updated to version $($update.AvailableVersion)"
                }
            }
            else {
                Write-Log "Failed to update $($update.Name) after $retryCount attempts: $lastError (Exit code: $lastExitCode)" -Level ERROR
                Write-Output "[ERROR] Failed to update $($update.Name): $lastError" -Color ([System.Drawing.Color]::Red)

                # Provide helpful suggestions based on error type
                if ($lastExitCode -eq -1978335212) {
                    Write-Output "  [HINT] Try updating manually with: winget upgrade --id `"$($update.Id)`" --interactive" -Color ([System.Drawing.Color]::Cyan)
                }
                elseif ($lastExitCode -eq -1978335226) {
                    Write-Output "  [HINT] Package may need to be updated from a different source" -Color ([System.Drawing.Color]::Cyan)
                }
                elseif ($lastExitCode -eq -1978334975) {
                    Write-Output "  [HINT] Try running: winget upgrade --id `"$($update.Id)`" --interactive" -Color ([System.Drawing.Color]::Cyan)
                }

                $failCount++

                $results += [PSCustomObject]@{
                    Name = $update.Name
                    Success = $false
                    Message = $lastError
                }
            }
        }
        catch {
            Write-Log "Exception updating $($update.Name): $($_.Exception.Message)" -Level ERROR
            Write-Output "[ERROR] Exception updating $($update.Name): $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red)
            $failCount++

            $results += [PSCustomObject]@{
                Name = $update.Name
                Success = $false
                Message = $_.Exception.Message
            }
        }

        # Process Windows messages to keep UI responsive
        if ($script:ListView) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    Write-Log "Update process completed: $successCount succeeded, $failCount failed" -Level INFO

    return @{
        SuccessCount = $successCount
        FailCount = $failCount
        Results = $results
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
        if (Test-Path $shortcutPath) {
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
            if (Test-Path $path) {
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
            $iconLocation = if ($IconPath -and (Test-Path $IconPath)) { $IconPath } else { $chromePath }
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
        Downloads and executes the O&O ShutUp10 installation script from GitHub.

    .DESCRIPTION
        Downloads the Install-OOShutUp10.ps1 script from the mytech-today-now/OO repository
        and executes it. This is the preferred installation method for O&O ShutUp10.

    .OUTPUTS
        Returns $true if successful, $false otherwise.
    #>
    [CmdletBinding()]
    param()

    try {
        $remoteScriptUrl = "https://raw.githubusercontent.com/mytech-today-now/OO/main/Install-OOShutUp10.ps1"
        $tempScriptPath = Join-Path $env:TEMP "Install-OOShutUp10.ps1"

        Write-Log "Downloading O&O ShutUp10 script from GitHub..." -Level INFO
        Write-Output "  [DOWNLOAD] Downloading installation script from GitHub..." -Color ([System.Drawing.Color]::Orange)

        # Update status
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "[DOWNLOAD] Downloading O&O ShutUp10 script from GitHub..."
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Orange
            [System.Windows.Forms.Application]::DoEvents()
        }

        # Download the script
        Invoke-WebRequest -Uri $remoteScriptUrl -OutFile $tempScriptPath -UseBasicParsing -ErrorAction Stop

        Write-Log "Downloaded O&O ShutUp10 script to: $tempScriptPath" -Level INFO
        Write-Output "  [EXECUTE] Running installation script..." -Color ([System.Drawing.Color]::Yellow)

        # Update status
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "[INSTALL] Running O&O ShutUp10 installation script..."
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Yellow
            [System.Windows.Forms.Application]::DoEvents()
        }

        # Execute the script
        & $tempScriptPath
        $exitCode = $LASTEXITCODE

        # Clean up
        if (Test-Path $tempScriptPath) {
            Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
        }

        if ($exitCode -eq 0) {
            Write-Log "O&O ShutUp10 installed successfully via remote script" -Level SUCCESS
            Write-Output "  [OK] Installation complete!" -Color ([System.Drawing.Color]::Green)
            return $true
        }
        else {
            Write-Log "O&O ShutUp10 remote script failed with exit code: $exitCode" -Level ERROR
            Write-Output "  [FAIL] Installation failed with exit code: $exitCode" -Color ([System.Drawing.Color]::Red)
            return $false
        }
    }
    catch {
        Write-Log "Failed to download or execute O&O ShutUp10 remote script: $_" -Level ERROR
        Write-Output "  [FAIL] Failed to download or execute remote script: $_" -Color ([System.Drawing.Color]::Red)
        return $false
    }
}

function Install-Application {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$App
    )

    Write-Log "Installing $($App.Name)..." -Level INFO
    Write-Output "`r`nInstalling $($App.Name)..." -Color ([System.Drawing.Color]::Blue)

    # Show secondary progress bar and update status label
    if ($script:AppProgressBar) {
        $script:AppProgressBar.Visible = $true
        [System.Windows.Forms.Application]::DoEvents()
    }

    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "[PREP] Preparing to install $($App.Name)..."
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::DodgerBlue
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        # Special handling for O&O ShutUp10: Try remote script first
        if ($App.Name -eq "O&O ShutUp10") {
            Write-Log "Using special installation method for O&O ShutUp10" -Level INFO
            Write-Output "  [i] Using remote installation script from GitHub..." -Color ([System.Drawing.Color]::Cyan)

            # Try remote script first
            $remoteSuccess = Install-OOShutUp10FromRemote

            if ($remoteSuccess) {
                # Register O&O ShutUp10 as installed
                $ooShutUpPath = "C:\Program Files\OOShutUp10\OOSU10.exe"
                if (Test-Path $ooShutUpPath) {
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

                # Hide secondary progress bar
                if ($script:AppProgressBar) {
                    $script:AppProgressBar.Visible = $false
                }

                # Update status - success
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "[OK] $($App.Name) installed successfully!"
                    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                    [System.Windows.Forms.Application]::DoEvents()
                }

                return $true
            }

            # If remote failed, try local script as fallback
            Write-Log "Remote script failed, trying local script fallback..." -Level WARNING
            Write-Output "  [WARN] Remote script failed, trying local script..." -Color ([System.Drawing.Color]::Yellow)
        }

        # Check if custom script exists
        $scriptPath = Join-Path $script:AppsPath $App.ScriptName

        if (Test-Path $scriptPath) {
            Write-Log "Using custom script: $scriptPath" -Level INFO
            Write-Output "  Using custom script..." -Color ([System.Drawing.Color]::Gray)

            # Update status
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[INSTALL] Running custom installation script for $($App.Name)..."
                [System.Windows.Forms.Application]::DoEvents()
            }

            & $scriptPath
            $scriptExitCode = $LASTEXITCODE

            # Hide secondary progress bar
            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }

            # Check exit code from custom script
            if ($scriptExitCode -eq 0) {
                Write-Log "$($App.Name) installed successfully via custom script" -Level SUCCESS

                # Update status - success
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "[OK] $($App.Name) installed successfully!"
                    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                    [System.Windows.Forms.Application]::DoEvents()
                }

                # Create Start Menu shortcut for Chrome Remote Desktop
                if ($App.Name -eq "Chrome Remote Desktop") {
                    Write-Log "Creating Start Menu shortcut for Chrome Remote Desktop..." -Level INFO
                    $shortcutCreated = New-WebApplicationShortcut `
                        -ShortcutName "Chrome Remote Desktop" `
                        -Url "https://remotedesktop.google.com/access" `
                        -Description "Configure and access Chrome Remote Desktop"

                    if ($shortcutCreated) {
                        Write-Output "  [OK] Start Menu shortcut created" -Color ([System.Drawing.Color]::Green)
                    }
                    else {
                        Write-Output "  [WARN] Could not create Start Menu shortcut" -Color ([System.Drawing.Color]::Orange)
                    }
                }

                return $true
            }
            else {
                $errorMessage = Get-WingetErrorMessage -ExitCode $scriptExitCode
                Write-Log "$($App.Name) installation failed via custom script: $errorMessage (Exit code: $scriptExitCode)" -Level ERROR

                # Update status - failed
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "[FAIL] $($App.Name) - $errorMessage"
                    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
                    [System.Windows.Forms.Application]::DoEvents()
                }

                return $false
            }
        }
        elseif ($App.WingetId) {
            # Use winget for installation
            if (Test-WingetAvailable) {
                Write-Log "Installing via winget: $($App.WingetId)" -Level INFO
                Write-Output "  Installing via winget..." -Color ([System.Drawing.Color]::Gray)

                # Check and install dependencies first
                $dependencies = Get-PackageDependencies -PackageId $App.WingetId
                if ($dependencies.Count -gt 0) {
                    Write-Log "Package $($App.Name) has $($dependencies.Count) dependencies" -Level INFO
                    Install-PackageDependencies -Dependencies $dependencies -PackageName $App.Name | Out-Null
                }

                # Update status - downloading
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "[DOWNLOAD] Downloading $($App.Name)..."
                    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Orange
                    [System.Windows.Forms.Application]::DoEvents()
                }

                $result = winget install --id $App.WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "$($App.Name) installed successfully" -Level SUCCESS
                    Write-Output "  [OK] $($App.Name) installed successfully!" -Color ([System.Drawing.Color]::Green)

                    # Hide secondary progress bar
                    if ($script:AppProgressBar) {
                        $script:AppProgressBar.Visible = $false
                    }

                    # Update status - success
                    if ($script:StatusLabel) {
                        $script:StatusLabel.Text = "[OK] $($App.Name) installed successfully!"
                        $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                        [System.Windows.Forms.Application]::DoEvents()
                    }

                    # Create Start Menu shortcut for Chrome Remote Desktop
                    if ($App.Name -eq "Chrome Remote Desktop") {
                        Write-Log "Creating Start Menu shortcut for Chrome Remote Desktop..." -Level INFO
                        $shortcutCreated = New-WebApplicationShortcut `
                            -ShortcutName "Chrome Remote Desktop" `
                            -Url "https://remotedesktop.google.com/access" `
                            -Description "Configure and access Chrome Remote Desktop"

                        if ($shortcutCreated) {
                            Write-Output "  [OK] Start Menu shortcut created" -Color ([System.Drawing.Color]::Green)
                        }
                        else {
                            Write-Output "  [WARN] Could not create Start Menu shortcut" -Color ([System.Drawing.Color]::Orange)
                        }
                    }

                    return $true
                }
                else {
                    $errorMessage = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
                    Write-Log "$($App.Name) installation failed: $errorMessage (Exit code: $LASTEXITCODE)" -Level ERROR
                    Write-Output "  [X] Installation failed: $errorMessage" -Color ([System.Drawing.Color]::Red)
                    Write-Output "      Exit code: $LASTEXITCODE" -Color ([System.Drawing.Color]::Red)
                    if ($result) {
                        Write-Output "      Details: $result" -Color ([System.Drawing.Color]::Red)
                    }

                    # Hide secondary progress bar
                    if ($script:AppProgressBar) {
                        $script:AppProgressBar.Visible = $false
                    }

                    # Update status - failed
                    if ($script:StatusLabel) {
                        $script:StatusLabel.Text = "[FAIL] $($App.Name) - $errorMessage"
                        $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
                        [System.Windows.Forms.Application]::DoEvents()
                    }

                    return $false
                }
            }
            else {
                Write-Log "Winget not available, cannot install $($App.Name)" -Level ERROR
                Write-Output "  [X] Winget not available" -Color ([System.Drawing.Color]::Red)

                # Hide secondary progress bar
                if ($script:AppProgressBar) {
                    $script:AppProgressBar.Visible = $false
                }

                # Update status - error
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "[ERROR] Winget not available"
                    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
                    [System.Windows.Forms.Application]::DoEvents()
                }

                return $false
            }
        }
        else {
            Write-Log "No installation method available for $($App.Name)" -Level WARNING
            Write-Output "  [!] No installation method available" -Color ([System.Drawing.Color]::Orange)

            # Hide secondary progress bar
            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }

            # Update status - warning
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[WARN] No installation method available for $($App.Name)"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Orange
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $false
        }
    }
    catch {
        Write-Log "Error installing $($App.Name): $($_.Exception.Message)" -Level ERROR
        Write-Output "  [X] Error: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red)

        # Hide secondary progress bar
        if ($script:AppProgressBar) {
            $script:AppProgressBar.Visible = $false
        }

        # Update status - error
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "[ERROR] Error installing $($App.Name): $($_.Exception.Message)"
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.Application]::DoEvents()
        }

        return $false
    }
}

function Uninstall-Application {
    <#
    .SYNOPSIS
        Uninstalls a single application using winget.

    .DESCRIPTION
        Uninstalls an application using 'winget uninstall --id {WingetId} --silent'.
        Logs all operations and updates UI with progress.

    .PARAMETER App
        The application object to uninstall (must have WingetId property).

    .OUTPUTS
        Boolean - $true if uninstall succeeded, $false otherwise.

    .EXAMPLE
        $app = $script:Applications | Where-Object { $_.Name -eq "Google Chrome" }
        Uninstall-Application -App $app
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$App
    )

    Write-Log "Uninstalling $($App.Name)..." -Level INFO
    Write-Output "`r`nUninstalling $($App.Name)..." -Color ([System.Drawing.Color]::Blue)

    # Show secondary progress bar and update status label
    if ($script:AppProgressBar) {
        $script:AppProgressBar.Visible = $true
        [System.Windows.Forms.Application]::DoEvents()
    }

    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "[PREP] Preparing to uninstall $($App.Name)..."
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::DodgerBlue
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        # Check if app has WingetId
        if (-not $App.WingetId) {
            Write-Log "Cannot uninstall $($App.Name): No WingetId defined" -Level WARNING
            Write-Output "  [WARN] Cannot uninstall: No WingetId defined for this application" -Color ([System.Drawing.Color]::Orange)

            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[WARN] Cannot uninstall $($App.Name): No WingetId"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Orange
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $false
        }

        # Check if app is actually installed
        if (-not $script:InstalledApps.ContainsKey($App.Name)) {
            Write-Log "$($App.Name) is not installed - skipping uninstall" -Level INFO
            Write-Output "  [INFO] $($App.Name) is not installed" -Color ([System.Drawing.Color]::Cyan)

            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[INFO] $($App.Name) is not installed"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Cyan
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $true  # Not an error - just not installed
        }

        # Update status - uninstalling
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "[UNINSTALL] Uninstalling $($App.Name)..."
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Orange
            [System.Windows.Forms.Application]::DoEvents()
        }

        Write-Log "Executing: winget uninstall --id $($App.WingetId) --silent" -Level INFO
        $result = winget uninstall --id $App.WingetId --silent 2>&1

        # Check exit code
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($App.Name) uninstalled successfully" -Level SUCCESS
            Write-Output "  [OK] $($App.Name) uninstalled successfully" -Color ([System.Drawing.Color]::Green)

            # Remove from installed apps hashtable
            if ($script:InstalledApps.ContainsKey($App.Name)) {
                $script:InstalledApps.Remove($App.Name)
                Write-Log "Removed $($App.Name) from installed apps cache" -Level INFO
            }

            # Hide secondary progress bar
            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }

            # Update status - success
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[OK] $($App.Name) uninstalled successfully"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $true
        }
        else {
            # Uninstall failed
            $errorMsg = $result | Out-String
            Write-Log "Failed to uninstall $($App.Name): Exit code $LASTEXITCODE" -Level ERROR
            Write-Log "Winget output: $errorMsg" -Level ERROR
            Write-Output "  [ERROR] Failed to uninstall $($App.Name)" -Color ([System.Drawing.Color]::Red)
            Write-Output "  Exit code: $LASTEXITCODE" -Color ([System.Drawing.Color]::Red)

            # Hide secondary progress bar
            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }

            # Update status - error
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "[ERROR] Failed to uninstall $($App.Name)"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $false
        }
    }
    catch {
        Write-Log "Error uninstalling $($App.Name): $($_.Exception.Message)" -Level ERROR
        Write-Output "  [ERROR] Error: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red)

        # Hide secondary progress bar
        if ($script:AppProgressBar) {
            $script:AppProgressBar.Visible = $false
        }

        # Update status - error
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "[ERROR] Error uninstalling $($App.Name): $($_.Exception.Message)"
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.Application]::DoEvents()
        }

        return $false
    }
}

#endregion Installation Functions

#region GUI Creation

function Get-DPIScaleFactor {
    <#
    .SYNOPSIS
        Wrapper function that uses the responsive GUI helper for DPI scaling.

    .DESCRIPTION
        This function calls the responsive GUI helper's Get-ResponsiveDPIScale function
        to calculate DPI scaling factor. If the responsive helper is not loaded,
        it falls back to a basic implementation.

    .OUTPUTS
        PSCustomObject with scaling information including:
        - BaseFactor: Base DPI scaling factor
        - AdditionalScale: Resolution-specific additional scaling
        - TotalScale: Combined scaling factor to apply to all dimensions
        - ScreenWidth: Screen width in pixels
        - ScreenHeight: Screen height in pixels
        - DpiX: Horizontal DPI
        - DpiY: Vertical DPI
        - ResolutionName: Detected resolution category name
        - ResolutionCategory: Category (VGA, HD, FHD, 4K, etc.)
    #>
    [CmdletBinding()]
    param()

    # Use responsive helper if available
    if ($script:ResponsiveHelperLoaded -and (Get-Command -Name Get-ResponsiveDPIScale -ErrorAction SilentlyContinue)) {
        $scaleInfo = Get-ResponsiveDPIScale
        Write-Log "Screen: $($scaleInfo.ScreenWidth)x$($scaleInfo.ScreenHeight), Resolution: $($scaleInfo.ResolutionName), Base DPI: $($scaleInfo.BaseFactor), Additional: $($scaleInfo.AdditionalScale), Total Scale: $($scaleInfo.TotalScale)" -Level INFO
        return $scaleInfo
    }

    # Fallback implementation if responsive helper is not available
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen

    # Calculate base DPI scaling
    $dpiX = $screen.Bounds.Width / [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize.Width
    $dpiY = $screen.Bounds.Height / [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize.Height

    # Use the larger of the two scaling factors, with a minimum of 1.0
    $baseFactor = [Math]::Max([Math]::Max($dpiX, $dpiY), 1.0)

    # Apply resolution-specific additional scaling
    $additionalScale = 1.0
    $resolutionName = "Unknown"
    $resolutionCategory = "Unknown"

    if ($screen.Bounds.Width -ge 7680) {
        $additionalScale = 2.5
        $resolutionName = "8K UHD (7680x4320)"
        $resolutionCategory = "8K"
    }
    elseif ($screen.Bounds.Width -ge 5120) {
        $additionalScale = 1.8
        $resolutionName = "5K (5120x2880)"
        $resolutionCategory = "5K"
    }
    elseif ($screen.Bounds.Width -ge 3840) {
        $additionalScale = 1.5
        $resolutionName = "4K UHD (3840x2160)"
        $resolutionCategory = "4K"
    }
    elseif ($screen.Bounds.Width -ge 3440) {
        $additionalScale = 1.3
        $resolutionName = "UWQHD (3440x1440)"
        $resolutionCategory = "UWQHD"
    }
    elseif ($screen.Bounds.Width -ge 2560) {
        $additionalScale = 1.3
        $resolutionName = "QHD (2560x1440)"
        $resolutionCategory = "QHD"
    }
    elseif ($screen.Bounds.Width -ge 1920) {
        $additionalScale = 1.2
        $resolutionName = "FHD (1920x1080)"
        $resolutionCategory = "FHD"
    }
    elseif ($screen.Bounds.Width -ge 1366) {
        $additionalScale = 1.0
        $resolutionName = "WXGA (1366x768)"
        $resolutionCategory = "WXGA"
    }
    elseif ($screen.Bounds.Width -ge 1280) {
        $additionalScale = 1.0
        $resolutionName = "HD (1280x720)"
        $resolutionCategory = "HD"
    }
    elseif ($screen.Bounds.Width -ge 1024) {
        $additionalScale = 1.0
        $resolutionName = "XGA (1024x768)"
        $resolutionCategory = "XGA"
    }
    elseif ($screen.Bounds.Width -ge 800) {
        $additionalScale = 0.9
        $resolutionName = "SVGA (800x600)"
        $resolutionCategory = "SVGA"
    }
    else {
        $additionalScale = 0.8
        $resolutionName = "VGA (640x480)"
        $resolutionCategory = "VGA"
    }

    $scaleFactor = $baseFactor * $additionalScale

    Write-Log "Screen: $($screen.Bounds.Width)x$($screen.Bounds.Height), Resolution: $resolutionName, Base DPI: $baseFactor, Additional: $additionalScale, Total Scale: $scaleFactor" -Level INFO

    return [PSCustomObject]@{
        BaseFactor = $baseFactor
        AdditionalScale = $additionalScale
        TotalScale = $scaleFactor
        ScreenWidth = $screen.Bounds.Width
        ScreenHeight = $screen.Bounds.Height
        DpiX = $dpiX
        DpiY = $dpiY
        ResolutionName = $resolutionName
        ResolutionCategory = $resolutionCategory
    }
}

function Create-MainForm {
    # Get DPI scaling factor using standardized function
    $scaleInfo = Get-DPIScaleFactor
    $scaleFactor = $scaleInfo.TotalScale
    $resolutionName = $scaleInfo.ResolutionName
    $screenWidth = $scaleInfo.ScreenWidth
    $screenHeight = $scaleInfo.ScreenHeight

    # Base dimensions (before scaling) - following .augment/gui-responsiveness.md standards
    $baseDimensions = @{
        # Form dimensions (relative to screen resolution)
        # Target: 1920x1080 window on a 2194x1234 screen (~87.5% of width/height)
        FormWidthRatio  = 1920.0 / 2194.0
        FormHeightRatio = 1080.0 / 1234.0
        MinFormWidth  = 800
        MinFormHeight = 600

        # Font sizes
        BaseFontSize = 10
        MinFontSize = 9
        TitleFontSize = 14
        ConsoleFontSize = 12
        TableFontSize = 11
        ButtonFontSize = 8  # Reduced from 9 to make button text smaller

        # Margins and spacing
        Margin = 20
        Spacing = 6  # Reduced from 12 to cut spacing in half
        HeaderHeight = 20
        ButtonAreaHeight = 70  # Match ButtonHeight so reserved button area equals actual button height (no bottom margin)
        ProgressAreaHeight = 130  # Height for progress bar + labels + 45px gap above buttons

        # Control dimensions
        ProgressBarHeight = 18
        ProgressLabelHeight = 30
        StatusLabelHeight = 25
        AppProgressBarHeight = 12
        ButtonHeight = 70  # Increased from 50 to accommodate multi-line text
        RowHeightMultiplier = 2.2
    }

    # Calculate target window size based on screen resolution ratio (Option A)
    $widthRatio = $baseDimensions.FormWidthRatio
    $heightRatio = $baseDimensions.FormHeightRatio

    $targetWidthPixels  = [Math]::Floor($screenWidth  * $widthRatio)
    $targetHeightPixels = [Math]::Floor($screenHeight * $heightRatio)

    # Convert to base values for New-ResponsiveForm (which will apply DPI scaling)
    if ($scaleFactor -le 0) { $scaleFactor = 1.0 }
    $baseWidth  = [int]($targetWidthPixels  / $scaleFactor)
    $baseHeight = [int]($targetHeightPixels / $scaleFactor)

    # Enforce minimum form size
    $formWidth  = [Math]::Max($baseWidth,  $baseDimensions.MinFormWidth)
    $formHeight = [Math]::Max($baseHeight, $baseDimensions.MinFormHeight)

    # Apply scaling to all dimensions
    $margin = [int]($baseDimensions.Margin * $scaleFactor)
    $spacing = [int]($baseDimensions.Spacing * $scaleFactor)
    $headerHeight = [int]($baseDimensions.HeaderHeight * $scaleFactor)
    $buttonAreaHeight = [int]($baseDimensions.ButtonAreaHeight * $scaleFactor)
    $progressAreaHeight = [int]($baseDimensions.ProgressAreaHeight * $scaleFactor)

    # Calculate font sizes with min/max constraints
    $titleFontSize = [Math]::Max([int]($baseDimensions.TitleFontSize * $scaleFactor), $baseDimensions.MinFontSize)
    $normalFontSize = [Math]::Max([int]($baseDimensions.BaseFontSize * $scaleFactor), $baseDimensions.MinFontSize)
    $consoleFontSize = [Math]::Max([int]($baseDimensions.ConsoleFontSize * $scaleFactor), $baseDimensions.MinFontSize)
    $tableFontSize = [Math]::Max([int]($baseDimensions.TableFontSize * $scaleFactor), $baseDimensions.MinFontSize)
    $buttonFontSize = [Math]::Max([int]($baseDimensions.ButtonFontSize * $scaleFactor), $baseDimensions.MinFontSize)

    Write-Log "Responsive GUI - Resolution: $resolutionName ($screenWidth x $screenHeight), Scale Factor: $scaleFactor" -Level INFO
    Write-Log "Form Size: ${formWidth}x${formHeight}, Fonts - Title: $titleFontSize, Normal: $normalFontSize, Table: $tableFontSize, Console: $consoleFontSize" -Level INFO

    # Create main form with responsive settings using New-ResponsiveForm
    $form = New-ResponsiveForm -Title "myTech.Today Application Installer v$script:ScriptVersion" `
        -Width $formWidth `
        -Height $formHeight `
        -MinWidth $baseDimensions.MinFormWidth `
        -MinHeight $baseDimensions.MinFormHeight `
        -StartPosition 'CenterScreen' `
        -Resizable $true

    # Enable visual styles for modern appearance
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Use the same content margin for the main layout so controls align cleanly
    $leftMargin = $margin
    $controlGap = [int](5 * $scaleFactor)

    # Approximate width needed for ~180 characters in the HTML/console area
    $consoleFont = New-Object System.Drawing.Font("Consolas", $consoleFontSize)
    try {
        $targetChars = 180
        $sampleText = "W" * $targetChars
        $targetOutputWidth = Measure-TextWidth -Text $sampleText -Font $consoleFont
    }
    finally {
        $consoleFont.Dispose()
    }
    if ($targetOutputWidth -le 0) {
        # Fallback: ensure a reasonable minimum width if measurement fails
        $targetOutputWidth = [int](600 * $scaleFactor)
    }

    # Determine baseline ListView width using the existing 80/20 split
    $initialClientWidth = $form.ClientSize.Width
    $baselineListViewWidth = [Math]::Floor(($initialClientWidth - $leftMargin - $controlGap - $margin) * 0.80)
    if ($baselineListViewWidth -lt 0) { $baselineListViewWidth = 0 }

    # Make the ListView up to ~30px wider than before, but never smaller
    $extraListViewWidth = [int](30 * $scaleFactor)
    $desiredListViewWidth = $baselineListViewWidth + $extraListViewWidth

    # Compute required client width to fit the desired ListView width and target HTML/console width
    $requiredClientWidth = $leftMargin + $controlGap + $desiredListViewWidth + $targetOutputWidth

    # Widen the form if necessary (but keep it within ~95% of the screen width)
    $clientWidth = $initialClientWidth
    if ($requiredClientWidth -gt $clientWidth) {
        $maxClientWidth = [int]($screenWidth * 0.95)
        $targetClientWidth = [Math]::Min($requiredClientWidth, $maxClientWidth)
        $extraWidth = $targetClientWidth - $clientWidth
        if ($extraWidth -gt 0) {
            $form.Width += $extraWidth
        }
    }

    # Cache final client area dimensions for subsequent layout calculations
    $clientWidth = $form.ClientSize.Width
    $clientHeight = $form.ClientSize.Height

    # Final ListView and HTML/console widths
    $maxOutputWidth = $clientWidth - ($leftMargin + $controlGap + $baselineListViewWidth)
    if ($maxOutputWidth -lt $targetOutputWidth) {
        # Not enough room for both desired ListView and full HTML width:
        # keep ListView at least as wide as the baseline and give the rest to the HTML area.
        $listViewWidth = $baselineListViewWidth
        $outputWidth = $clientWidth - ($leftMargin + $controlGap + $listViewWidth)
    }
    else {
        # We have enough room for a slightly wider ListView and the target HTML width.
        $listViewWidth = $desiredListViewWidth
        $outputWidth = $clientWidth - ($leftMargin + $controlGap + $listViewWidth)
    }
    if ($outputWidth -lt 0) { $outputWidth = 0 }

    # Merge additional properties into form Tag (New-ResponsiveForm already sets ScaleInfo, ScaleFactor, BaseDimensions)
    $existingTag = $form.Tag
    $form.Tag = @{
        ScaleInfo = $existingTag.ScaleInfo
        ScaleFactor = $existingTag.ScaleFactor
        BaseDimensions = $existingTag.BaseDimensions
        # Use client area dimensions for layout so controls align with the visible region
        FormWidth = $clientWidth
        FormHeight = $clientHeight
        NormalFontSize = $normalFontSize
        TitleFontSize = $titleFontSize
        ConsoleFontSize = $consoleFontSize
        TableFontSize = $tableFontSize
        ButtonFontSize = $buttonFontSize
        Margin = $margin
        Spacing = $spacing
        ButtonHeight = [int]($baseDimensions.ButtonHeight * $scaleFactor)
    }

    # Calculate content area dimensions with scaled values
    $contentTop = $headerHeight
    $searchPanelHeight = [Math]::Max([Math]::Round($normalFontSize * 2.5), 35)  # Height for search controls
    $contentHeight = $clientHeight - $headerHeight - $buttonAreaHeight - $progressAreaHeight - $margin

    # Create search panel controls
    # Increase label width to show full "Search:" text (90 pixels minimum to ensure full visibility at all DPI settings)
    $searchLabelWidth = [Math]::Max([Math]::Round($normalFontSize * 10), 90)
    # Clear button width - will align with ListView scrollbar
    $clearButtonWidth = [Math]::Max([Math]::Round($normalFontSize * 2.5), 30)
    # Position clear button to align with right edge of ListView (where scrollbar is)
    $clearButtonX = $margin + $listViewWidth - $clearButtonWidth
    # Search textbox fills space between label and clear button
    $searchTextBoxX = $margin + $searchLabelWidth + 5
    $searchTextBoxWidth = $clearButtonX - $searchTextBoxX - 5

    # Search label
    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Location = New-InstallerPoint($margin, ($contentTop + 5))
    $searchLabel.Size = New-Object System.Drawing.Size($searchLabelWidth, ($searchPanelHeight - 10))
    $searchLabel.Text = "Search:"
    $searchLabel.Font = New-Object System.Drawing.Font("Segoe UI", $normalFontSize)
    $searchLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($searchLabel)

    # Search textbox
    $script:SearchTextBox = New-Object System.Windows.Forms.TextBox
    $script:SearchTextBox.Location = New-InstallerPoint($searchTextBoxX, ($contentTop + 5))
    $script:SearchTextBox.Size = New-Object System.Drawing.Size($searchTextBoxWidth, ($searchPanelHeight - 10))
    $script:SearchTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $normalFontSize)
    $script:SearchTextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:SearchTextBox)

    # Clear search button (aligned with ListView scrollbar)
    $clearSearchButton = New-Object System.Windows.Forms.Button
    $clearSearchButton.Location = New-InstallerPoint($clearButtonX, ($contentTop + 5))
    $clearSearchButton.Size = New-Object System.Drawing.Size($clearButtonWidth, ($searchPanelHeight - 10))
    $clearSearchButton.Text = "X"
    $clearSearchButton.Font = New-Object System.Drawing.Font("Segoe UI", $normalFontSize, [System.Drawing.FontStyle]::Bold)
    $clearSearchButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $clearSearchButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Clear Search button" -Level INFO
            $script:SearchTextBox.Text = ""
            $script:SearchTerm = ""
            Filter-Applications -SearchTerm ""
        }
    })
    $form.Controls.Add($clearSearchButton)

    # Add event handler for search textbox (real-time filtering)
    $script:SearchTextBox.Add_TextChanged({
        if (-not $script:IsClosing) {
            $script:SearchTerm = $script:SearchTextBox.Text
            Filter-Applications -SearchTerm $script:SearchTerm
        }
    })

    # Result count label (positioned on the right side, above output panel)
    $script:ResultCountLabel = New-Object System.Windows.Forms.Label
    $script:ResultCountLabel.Location = New-InstallerPoint(($margin * 2 + $listViewWidth), ($contentTop + 5))
    $script:ResultCountLabel.Size = New-Object System.Drawing.Size($outputWidth, ($searchPanelHeight - 10))
    $script:ResultCountLabel.Text = "Showing 0 of 0 applications"
    $script:ResultCountLabel.Font = New-Object System.Drawing.Font("Segoe UI", ($normalFontSize - 1))
    $script:ResultCountLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:ResultCountLabel.ForeColor = [System.Drawing.Color]::Gray
    $script:ResultCountLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:ResultCountLabel)

    # Adjust ListView position and height to accommodate search panel
    $listViewTop = $contentTop + $searchPanelHeight + 5
    $listViewHeight = $contentHeight - $searchPanelHeight - 5

    # Create a SplitContainer so the user can resize the width between the ListView and HTML/console area
    $splitContainerWidth = $listViewWidth + $controlGap + $outputWidth
    $script:MainSplitContainer = New-Object System.Windows.Forms.SplitContainer
    $script:MainSplitContainer.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $script:MainSplitContainer.Location = New-InstallerPoint($leftMargin, $listViewTop)
    $script:MainSplitContainer.Size = New-Object System.Drawing.Size($splitContainerWidth, $listViewHeight)
    $script:MainSplitContainer.SplitterWidth = [int](5 * $scaleFactor)
    $script:MainSplitContainer.SplitterDistance = $listViewWidth
    $script:MainSplitContainer.Panel1MinSize = [int](200 * $scaleFactor)
    $script:MainSplitContainer.Panel2MinSize = [int](200 * $scaleFactor)
    $script:MainSplitContainer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:MainSplitContainer)

    # Create ListView for applications with responsive sizing (left side of SplitContainer)
    $script:ListView = New-Object System.Windows.Forms.ListView
    $script:ListView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:ListView.View = [System.Windows.Forms.View]::Details
    $script:ListView.FullRowSelect = $true
    $script:ListView.GridLines = $true
    $script:ListView.CheckBoxes = $true
    $script:ListView.Sorting = [System.Windows.Forms.SortOrder]::None
    $script:ListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)

    # Create ImageList to control row height based on scaled font size
    # Row height = font size * row height multiplier for comfortable spacing
    $rowHeight = [Math]::Max([Math]::Round($tableFontSize * $baseDimensions.RowHeightMultiplier), 24)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $script:ListView.SmallImageList = $imageList

    Write-Log "ListView - Font: $tableFontSize pt, Row Height: $rowHeight px" -Level INFO

    # Calculate dynamic column widths based on actual content
    $tableFont = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)

    # Application Name column - measure both data and header
    $colAppWidth = Get-DynamicColumnWidth -Items $script:Applications -PropertyName "Name" -HeaderText "Application Name" -Font $tableFont -MinWidth ([int](150 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))

    # Category column - measure both data and header
    $colCategoryWidth = Get-DynamicColumnWidth -Items $script:Applications -PropertyName "Category" -HeaderText "Category" -Font $tableFont -MinWidth ([int](100 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))

    # Status column - measure possible statuses and header
    $statusTexts = @("Not Installed", "Installed", "Installing...", "Failed", "Skipped")
    $maxStatusWidth = 0
    foreach ($statusText in $statusTexts) {
        $width = Measure-TextWidth -Text $statusText -Font $tableFont
        if ($width -gt $maxStatusWidth) {
            $maxStatusWidth = $width
        }
    }
    $headerWidth = Measure-TextWidth -Text "Install Status" -Font $tableFont
    $maxStatusWidth = [Math]::Max($maxStatusWidth, $headerWidth)
    $colStatusWidth = $maxStatusWidth + [int](30 * $scaleFactor)
    $colStatusWidth = [Math]::Max($colStatusWidth, [int](120 * $scaleFactor))

    # Version column - measure actual version strings from installed apps and header
    $versionTexts = @("Version")  # Start with header
    foreach ($app in $script:Applications) {
        if ($script:InstalledApps.ContainsKey($app.Name)) {
            $version = $script:InstalledApps[$app.Name]
            if ($version -and $version -ne "Unknown") {
                $versionTexts += $version
            }
        }
    }
    # Add some common version formats as minimum
    $versionTexts += @("1.0.0.0", "10.0.0.0", "100.0.0.0")
    $maxVersionWidth = 0
    foreach ($versionText in $versionTexts) {
        $width = Measure-TextWidth -Text $versionText -Font $tableFont
        if ($width -gt $maxVersionWidth) {
            $maxVersionWidth = $width
        }
    }
    $colVersionWidth = $maxVersionWidth + [int](30 * $scaleFactor)
    $colVersionWidth = [Math]::Max($colVersionWidth, [int](80 * $scaleFactor))

    # Description column - takes remaining space, but ensure header fits
    $descHeaderWidth = Measure-TextWidth -Text "Description" -Font $tableFont
    $minDescWidth = [Math]::Max($descHeaderWidth + [int](30 * $scaleFactor), [int](200 * $scaleFactor))
    $usedWidth = $colAppWidth + $colCategoryWidth + $colStatusWidth + $colVersionWidth
    $scrollbarWidth = [int](25 * $scaleFactor)
    $colDescWidth = [Math]::Max($listViewWidth - $usedWidth - $scrollbarWidth, $minDescWidth)

    Write-Log "Dynamic column widths - App: $colAppWidth, Category: $colCategoryWidth, Status: $colStatusWidth, Version: $colVersionWidth, Desc: $colDescWidth" -Level INFO

    # Create column headers
    $colAppName = New-Object System.Windows.Forms.ColumnHeader
    $colAppName.Text = "Application Name"
    $colAppName.Width = $colAppWidth

    $colCategory = New-Object System.Windows.Forms.ColumnHeader
    $colCategory.Text = "Category"
    $colCategory.Width = $colCategoryWidth

    $colStatus = New-Object System.Windows.Forms.ColumnHeader
    $colStatus.Text = "Install Status"
    $colStatus.Width = $colStatusWidth

    $colVersion = New-Object System.Windows.Forms.ColumnHeader
    $colVersion.Text = "Version"
    $colVersion.Width = $colVersionWidth

    $colDescription = New-Object System.Windows.Forms.ColumnHeader
    $colDescription.Text = "Description"
    $colDescription.Width = $colDescWidth

    # Add columns to ListView
    $script:ListView.Columns.AddRange(@($colAppName, $colCategory, $colStatus, $colVersion, $colDescription))

    # Add event handler to update progress label when checkboxes are checked/unchecked
    $script:ListView.Add_ItemCheck({
        param($sender, $e)

        # Prevent execution during form closing
        if ($script:IsClosing) {
            return
        }

        # Log the check state change for debugging
        try {
            $itemName = $script:ListView.Items[$e.Index].Text
            $newState = $e.NewValue
            Write-Log "User changed checkbox for '$itemName' to: $newState" -Level INFO
        }
        catch {
            # Silently ignore errors during logging
        }

        # Update progress label after check state changes
        # Note: We calculate based on the new state since ItemCheck fires before the change is applied
        try {
            $currentCheckedCount = ($script:ListView.Items | Where-Object { $_.Checked }).Count

            # Adjust count based on the change being made
            if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
                $newCheckedCount = $currentCheckedCount + 1
            }
            elseif ($e.CurrentValue -eq [System.Windows.Forms.CheckState]::Checked) {
                $newCheckedCount = $currentCheckedCount - 1
            }
            else {
                $newCheckedCount = $currentCheckedCount
            }

            if ($script:ProgressBar -and $script:ProgressLabel) {
                $script:ProgressBar.Maximum = [Math]::Max(1, $newCheckedCount)
                $script:ProgressBar.Value = 0
                $script:ProgressLabel.Text = "0 / $newCheckedCount applications"
            }
        }
        catch {
            # Silently ignore errors during UI update
        }
    })

    # Add click-to-select and drag-to-multi-select functionality
    Add-ListViewClickToSelect -ListView $script:ListView

    $script:MainSplitContainer.Panel1.Controls.Add($script:ListView)

    # Create WebBrowser control for HTML output (right side of SplitContainer)
    $script:WebBrowser = New-Object System.Windows.Forms.WebBrowser
    $script:WebBrowser.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:MainSplitContainer.Panel2.Controls.Add($script:WebBrowser)
    $script:WebBrowser.ScriptErrorsSuppressed = $true
    $script:WebBrowser.IsWebBrowserContextMenuEnabled = $false

    # Add event handler for NewWindow event (handles links with target="_blank")
    # This opens links in the default system browser instead of IE
    $script:WebBrowser.Add_NewWindow({
        param($sender, $e)

        # Cancel the new window in IE
        $e.Cancel = $true

        # Get the URL from the current navigation
        if ($script:WebBrowser.StatusText) {
            $url = $script:WebBrowser.StatusText
        }
        else {
            # Try to get URL from the document
            try {
                $activeElement = $script:WebBrowser.Document.ActiveElement
                if ($activeElement -and $activeElement.GetAttribute("href")) {
                    $url = $activeElement.GetAttribute("href")
                }
            }
            catch {
                $url = $null
            }
        }

        # Open URL in default system browser
        if ($url) {
            try {
                Start-Process $url
                Write-Log "Opened URL in default browser: $url" -Level INFO
            }
            catch {
                Write-Log "Failed to open URL in browser: $_" -Level ERROR
            }
        }
    })

    # Add event handler for Navigating event (handles links without target="_blank")
    # This opens links in the default system browser instead of IE
    $script:WebBrowser.Add_Navigating({
        param($sender, $e)

        # Allow initial document load (about:blank or initial HTML)
        if ($e.Url.AbsoluteUri -eq "about:blank" -or [string]::IsNullOrEmpty($e.Url.AbsoluteUri)) {
            return
        }

        # Check if this is an actual HTTP/HTTPS link (not about:blank, javascript:, etc.)
        if ($e.Url.Scheme -eq "http" -or $e.Url.Scheme -eq "https" -or $e.Url.Scheme -eq "tel" -or $e.Url.Scheme -eq "mailto") {
            # Cancel navigation in WebBrowser control
            $e.Cancel = $true

            # Open URL in default system browser
            try {
                Start-Process $e.Url.AbsoluteUri
                Write-Log "Opened URL in default browser: $($e.Url.AbsoluteUri)" -Level INFO
            }
            catch {
                Write-Log "Failed to open URL in browser: $_" -Level ERROR
            }
        }
    })

    # Calculate responsive HTML font sizes based on scale factor
    $htmlBodyFontSize = [Math]::Max([int](16 * $scaleFactor), 14)
    $htmlH1FontSize = [Math]::Max([int](24 * $scaleFactor), 20)
    $htmlH2FontSize = [Math]::Max([int](18 * $scaleFactor), 16)
    $htmlLogoFontSize = [Math]::Max([int](28 * $scaleFactor), 24)
    $htmlConsoleFontSize = [Math]::Max([int](14 * $scaleFactor), 12)

    # Initialize HTML content with myTech.Today marketing information and responsive styling
    $script:HtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * {
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #1e1e1e;
            color: #d4d4d4;
            margin: 10px;
            padding: 10px;
            font-size: ${htmlBodyFontSize}px;
            line-height: 1.6;
        }
        h1 {
            color: #4ec9b0;
            font-size: ${htmlH1FontSize}px;
            margin: 10px 0;
            border-bottom: 2px solid #4ec9b0;
            padding-bottom: 5px;
        }
        h2 {
            color: #569cd6;
            font-size: ${htmlH2FontSize}px;
            margin: 8px 0;
        }
        p {
            font-size: ${htmlBodyFontSize}px;
            margin: 8px 0;
        }
        .info { color: #4fc1ff; }
        .success { color: #4ec9b0; }
        .warning { color: #dcdcaa; }
        .error { color: #f48771; }
        .gray { color: #808080; }
        .box {
            border: 1px solid #4ec9b0;
            padding: 10px;
            margin: 10px 0;
            background-color: #252526;
        }
        ul {
            margin: 5px 0;
            padding-left: 20px;
            font-size: ${htmlBodyFontSize}px;
        }
        li {
            margin: 4px 0;
        }
        .contact {
            margin-top: 10px;
            padding: 8px;
            background-color: #2d2d30;
            border-left: 3px solid #4ec9b0;
        }
        .logo {
            font-size: ${htmlLogoFontSize}px;
            font-weight: bold;
            color: #4ec9b0;
            text-align: center;
            margin-bottom: 15px;
        }
        .tagline {
            text-align: center;
            color: #569cd6;
            font-style: italic;
            margin-bottom: 20px;
            font-size: ${htmlBodyFontSize}px;
        }
        a {
            color: #4fc1ff;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .service-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
            margin: 10px 0;
        }
        .service-item {
            background-color: #2d2d30;
            padding: 8px;
            border-left: 2px solid #569cd6;
            font-size: ${htmlBodyFontSize}px;
        }
        /* Console output styling - monospace font for terminal-like appearance */
        .console-line {
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: ${htmlConsoleFontSize}px;
            line-height: 1.4;
            margin: 2px 0;
            padding: 1px 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
    </style>
</head>
<body>
    <div id="content">
        <div class="logo">myTech.Today</div>
        <div class="tagline">Professional IT Solutions for Your Business</div>

        <div class="box">
            <h2>Contact Information</h2>
            <p class="info">&#9679; Website: <a href="https://mytech.today">https://mytech.today</a></p>
            <p class="info">&#9679; Phone: <a href="tel:8477674914">(847) 767-4914</a></p>
            <p class="info">&#9679; GitHub: <a href="https://github.com/mytech-today-now">@mytech-today-now</a></p>
            <p class="info">&#9679; Location: Barrington, IL</p>
        </div>

        <div class="box">
            <h2>Service Area</h2>
            <p class="success">&#10003; Serving the Chicagoland area</p>
            <p class="success">&#10003; Northern Illinois</p>
            <p class="success">&#10003; Southern Wisconsin</p>
            <p class="success">&#10003; Northern Indiana</p>
            <p class="success">&#10003; Southern Michigan</p>
        </div>

        <div class="box">
            <h2>Experience</h2>
            <p class="warning">&#9733; Serving customers for 9 years</p>
            <p class="warning">&#9733; Trusted by businesses across the region</p>
        </div>

        <div class="box">
            <h2>Our Services</h2>
            <div class="service-grid">
                <div class="service-item">WordPress Web Development</div>
                <div class="service-item">Cloud Services</div>
                <div class="service-item">PowerShell Automation</div>
                <div class="service-item">Database Solutions</div>
                <div class="service-item">Email Services</div>
                <div class="service-item">Networking Solutions</div>
                <div class="service-item">Hardware Procurement</div>
                <div class="service-item">QuickBooks Solutions</div>
                <div class="service-item">OS Solutions</div>
                <div class="service-item">Printer Solutions</div>
                <div class="service-item">App Development</div>
                <div class="service-item">WordPress Plugin Development</div>
                <div class="service-item">AI Prompt Development</div>
                <div class="service-item">Disaster Recovery</div>
                <div class="service-item">Workflow Development</div>
                <div class="service-item">System Architecture</div>
            </div>
        </div>

        <div class="contact">
            <p style="text-align: center; margin: 0;">
                <strong>Ready to get started?</strong><br>
                Select applications from the list and click 'Install Selected' to begin!
            </p>
        </div>
    </div>
</body>
</html>
"@

    $script:WebBrowser.DocumentText = $script:HtmlContent

    # Calculate progress bar position (above buttons) with scaled dimensions
    $progressTop = $clientHeight - $buttonAreaHeight - $progressAreaHeight

    # Apply scaling to progress control dimensions
    $progressBarHeight = [int]($baseDimensions.ProgressBarHeight * $scaleFactor)
    $progressLabelHeight = [int]($baseDimensions.ProgressLabelHeight * $scaleFactor)
    $statusLabelHeight = [int]($baseDimensions.StatusLabelHeight * $scaleFactor)
    $appProgressBarHeight = [int]($baseDimensions.AppProgressBarHeight * $scaleFactor)

    # Create main progress bar with scaled height
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-InstallerPoint($margin, $progressTop)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(($clientWidth - $margin * 2), $progressBarHeight)
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:ProgressBar)

    # Create progress label with percentage (scaled font and height)
    $progressLabelFontSize = [Math]::Max($normalFontSize - 1, $baseDimensions.MinFontSize)
    $script:ProgressLabel = New-Object System.Windows.Forms.Label
    $script:ProgressLabel.Text = "0 / 0 applications (0%)"
    $script:ProgressLabel.Location = New-InstallerPoint($margin, ($progressTop + $progressBarHeight + 4))
    $script:ProgressLabel.Size = New-Object System.Drawing.Size(($clientWidth - $margin * 2), $progressLabelHeight)
    $script:ProgressLabel.Font = New-Object System.Drawing.Font("Segoe UI", $progressLabelFontSize)
    $script:ProgressLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:ProgressLabel.AutoSize = $false
    $script:ProgressLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $form.Controls.Add($script:ProgressLabel)

    # Create status label for current operation (scaled font and height)
    $statusLabelFontSize = [Math]::Max($normalFontSize - 2, $baseDimensions.MinFontSize)
    $statusLabelTop = $progressTop + $progressBarHeight + $progressLabelHeight + 8
    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Text = "Ready to install applications"
    $script:StatusLabel.Location = New-InstallerPoint($margin, $statusLabelTop)
    $script:StatusLabel.Size = New-Object System.Drawing.Size(($clientWidth - $margin * 2), $statusLabelHeight)
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Consolas", $statusLabelFontSize)
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Gray
    $script:StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:StatusLabel.AutoSize = $false
    $script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $form.Controls.Add($script:StatusLabel)

    # Create secondary progress bar for individual app installation (scaled height)
    $appProgressBarTop = $statusLabelTop + $statusLabelHeight + 4
    $script:AppProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:AppProgressBar.Location = New-InstallerPoint($margin, $appProgressBarTop)
    $script:AppProgressBar.Size = New-Object System.Drawing.Size(($clientWidth - $margin * 2), $appProgressBarHeight)
    $script:AppProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:AppProgressBar.MarqueeAnimationSpeed = 30
    $script:AppProgressBar.Visible = $false  # Hidden by default
    $script:AppProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:AppProgressBar)

    # Form Tag already set after New-ResponsiveForm creation with all necessary properties

    return $form
}

function Create-Buttons {
    param($form)

    # Get scaled dimensions from form Tag
    $formInfo = $form.Tag
    $formWidth = $formInfo.FormWidth
    $formHeight = $formInfo.FormHeight
    $normalFontSize = $formInfo.NormalFontSize
    $buttonFontSize = $formInfo.ButtonFontSize
    $margin = $formInfo.Margin
    $spacing = $formInfo.Spacing
    $buttonHeight = $formInfo.ButtonHeight
    $scaleFactor = $formInfo.ScaleFactor

    # Create button fonts with scaled size
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize)
    $buttonFontBold = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize, [System.Drawing.FontStyle]::Bold)

    # Use fixed narrow button width to enable multi-line text wrapping
    # Significantly narrower than before to allow text stacking
    $buttonWidth = [int](65 * $scaleFactor)  # Fixed narrow width for all buttons

    # Calculate button Y position (scaled offset from bottom)
    # Offset equals button height so button bottoms are flush with form bottom (no extra bottom margin)
    $buttonYOffset = $buttonHeight
    $buttonY = $formHeight - $buttonYOffset

    # Calculate X positions for each button (left-aligned with scaled spacing)
    $currentX = $margin

    # Refresh button
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-InstallerPoint($currentX, $buttonY)
    $refreshButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $refreshButton.Text = "Refresh`nStatus"
    $refreshButton.Font = $buttonFont
    $refreshButton.AutoSize = $false
    $refreshButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $refreshButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $refreshButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Refresh Status button" -Level INFO
            Refresh-ApplicationList
        }
    })
    $form.Controls.Add($refreshButton)
    $currentX += $buttonWidth + $spacing

    # Select All button
    $selectAllButton = New-Object System.Windows.Forms.Button
    $selectAllButton.Location = New-InstallerPoint($currentX, $buttonY)
    $selectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectAllButton.Text = "Select`nAll"
    $selectAllButton.Font = $buttonFont
    $selectAllButton.AutoSize = $false
    $selectAllButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $selectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $selectAllButton.Add_Click({
        if ($script:IsClosing) { return }
        Write-Log "User clicked Select All button" -Level INFO
        foreach ($item in $script:ListView.Items) {
            $item.Checked = $true
        }
        # Update progress label after selecting all
        $checkedCount = ($script:ListView.Items | Where-Object { $_.Checked }).Count
        $script:ProgressBar.Maximum = $checkedCount
        $script:ProgressBar.Value = 0
        $script:ProgressLabel.Text = "0 / $checkedCount applications"
    })
    $form.Controls.Add($selectAllButton)
    $currentX += $buttonWidth + $spacing

    # Select Missing button
    $selectMissingButton = New-Object System.Windows.Forms.Button
    $selectMissingButton.Location = New-InstallerPoint($currentX, $buttonY)
    $selectMissingButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectMissingButton.Text = "Select`nMissing"
    $selectMissingButton.Font = $buttonFont
    $selectMissingButton.AutoSize = $false
    $selectMissingButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $selectMissingButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $selectMissingButton.Add_Click({
        if ($script:IsClosing) { return }
        Write-Log "User clicked Select Missing button" -Level INFO
        foreach ($item in $script:ListView.Items) {
            $item.Checked = ($item.SubItems[2].Text -eq "Not Installed")
        }
        # Update progress label after selecting missing
        $checkedCount = ($script:ListView.Items | Where-Object { $_.Checked }).Count
        $script:ProgressBar.Maximum = $checkedCount
        $script:ProgressBar.Value = 0
        $script:ProgressLabel.Text = "0 / $checkedCount applications"
    })
    $form.Controls.Add($selectMissingButton)
    $currentX += $buttonWidth + $spacing

    # Deselect All button
    $deselectAllButton = New-Object System.Windows.Forms.Button
    $deselectAllButton.Location = New-InstallerPoint($currentX, $buttonY)
    $deselectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $deselectAllButton.Text = "Deselect`nAll"
    $deselectAllButton.Font = $buttonFont
    $deselectAllButton.AutoSize = $false
    $deselectAllButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $deselectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $deselectAllButton.Add_Click({
        if ($script:IsClosing) { return }
        Write-Log "User clicked Deselect All button" -Level INFO

        foreach ($item in $script:ListView.Items) {
            $item.Checked = $false

            # Clear any profile-based ignore flag when user deselects everything
            $app = $item.Tag
            if ($app -and $app.PSObject.Properties.Match('IgnoreProfileInstall').Count -gt 0) {
                $app.IgnoreProfileInstall = $false
            }

            # Reset color based on installed status
            if ($app) {
                if ($script:InstalledApps.ContainsKey($app.Name)) {
                    $item.ForeColor = [System.Drawing.Color]::Green
                }
                else {
                    $item.ForeColor = [System.Drawing.Color]::Red
                }
            }
        }

        # Update progress label after deselecting all
        $checkedCount = 0
        $script:ProgressBar.Maximum = 1  # Avoid division by zero
        $script:ProgressBar.Value = 0
        $script:ProgressLabel.Text = "0 / 0 applications"
    })
    $form.Controls.Add($deselectAllButton)
    $currentX += $buttonWidth + $spacing

    # Export Selection button
    $exportButton = New-Object System.Windows.Forms.Button
    $exportButton.Location = New-InstallerPoint($currentX, $buttonY)
    $exportButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $exportButton.Text = "Export`nSelection"
    $exportButton.Font = $buttonFont
    $exportButton.AutoSize = $false
    $exportButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $exportButton.BackColor = [System.Drawing.Color]::DarkOrange
    $exportButton.ForeColor = [System.Drawing.Color]::White
    $exportButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $exportButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Export Selection button" -Level INFO

            # Get checked items
            $checkedItems = $script:ListView.Items | Where-Object { $_.Checked }

            if ($checkedItems.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Please select at least one application to export.",
                    "No Selection",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                return
            }

            # Get application names
            $selectedAppNames = $checkedItems | ForEach-Object { $_.Tag.Name }

            # Show save file dialog
            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
            $saveDialog.Title = "Export Installation Profile"
            $saveDialog.InitialDirectory = $script:ProfilesPath
            $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
            $computerName = $env:COMPUTERNAME
            $saveDialog.FileName = "profile-$computerName-$timestamp.json"

            if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $filePath = Export-InstallationProfile -SelectedApps $selectedAppNames -FilePath $saveDialog.FileName

                if ($filePath) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Successfully exported $($selectedAppNames.Count) application(s) to:`n$filePath",
                        "Export Successful",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to export installation profile. Check the log for details.",
                        "Export Failed",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                }
            }
        }
    })
    $form.Controls.Add($exportButton)
    $currentX += $buttonWidth + $spacing

    # Import Selection button
    $importButton = New-Object System.Windows.Forms.Button
    $importButton.Location = New-InstallerPoint($currentX, $buttonY)
    $importButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $importButton.Text = "Import`nSelection"
    $importButton.Font = $buttonFont
    $importButton.AutoSize = $false
    $importButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $importButton.BackColor = [System.Drawing.Color]::DarkBlue
    $importButton.ForeColor = [System.Drawing.Color]::White
    $importButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $importButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Import Selection button" -Level INFO

            # Show the combined Import Installation Profile dialog (slideshow + import)
            $profileFilePath = Show-ProfileBrowserDialog

            if (-not $profileFilePath) {
                Write-Log "Import Selection cancelled - no profile chosen from Import Installation Profile dialog" -Level INFO
                return
            }

            if ([string]::IsNullOrWhiteSpace($profileFilePath)) {
                Write-Log "Import Selection cancelled - resolved profile file path is empty" -Level WARNING
                return
            }

            Write-Log "Import Selection proceeding with profile file: $profileFilePath" -Level INFO

            $result = Import-InstallationProfile -FilePath $profileFilePath

            if ($result.Success) {
                # Show confirmation dialog
                $message = "Found $($result.Applications.Count) application(s) in profile."
                if ($result.MissingApps.Count -gt 0) {
                    $message += "`n`nWarning: $($result.MissingApps.Count) application(s) from the profile are not available in the current installer:"
                    $message += "`n" + ($result.MissingApps -join ", ")
                }
                $message += "`n`nDo you want to select these applications?"

                $confirmResult = [System.Windows.Forms.MessageBox]::Show(
                    $message,
                    "Import Profile",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )

                if ($confirmResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    # Clear any previous profile-based ignore flags
                    foreach ($app in $script:Applications) {
                        if ($app.PSObject.Properties.Match('IgnoreProfileInstall').Count -gt 0) {
                            $app.IgnoreProfileInstall = $false
                        }
                    }

                    # Deselect all first and reset colors
                    foreach ($item in $script:ListView.Items) {
                        $item.Checked = $false

                        $app = $item.Tag
                        if ($app) {
                            if ($script:InstalledApps.ContainsKey($app.Name)) {
                                $item.ForeColor = [System.Drawing.Color]::Green
                            }
                            else {
                                $item.ForeColor = [System.Drawing.Color]::Red
                            }
                        }
                    }

                    # Select applications from profile
                    $selectedCount = 0          # apps that will actually be installed
                    $skippedInstalledCount = 0  # apps already installed that will be ignored

                    foreach ($item in $script:ListView.Items) {
                        $app = $item.Tag
                        if ($app -and ($result.Applications -contains $app.Name)) {
                            if ($script:InstalledApps.ContainsKey($app.Name)) {
                                # Mark installed apps as checked but grayed out to indicate they will be skipped
                                if ($app.PSObject.Properties.Match('IgnoreProfileInstall').Count -eq 0) {
                                    $app | Add-Member -NotePropertyName IgnoreProfileInstall -NotePropertyValue $true -Force
                                }
                                else {
                                    $app.IgnoreProfileInstall = $true
                                }

                                $item.Checked = $true
                                $item.ForeColor = [System.Drawing.Color]::DarkGray
                                $skippedInstalledCount++
                            }
                            else {
                                # Not installed - will be installed
                                $item.Checked = $true
                                $selectedCount++
                            }
                        }
                    }

                    $importedProfileName = [System.IO.Path]::GetFileName($profileFilePath)
                    Write-Log ("Imported profile '{0}': {1} app(s) selected for installation, {2} already installed and marked to be skipped" -f $importedProfileName, $selectedCount, $skippedInstalledCount) -Level SUCCESS

                    $importMessage = "Successfully selected $selectedCount application(s) from profile."
                    if ($skippedInstalledCount -gt 0) {
                        $importMessage += "`r`n`r`nNote: $skippedInstalledCount application(s) are already installed. They are checked but grayed out and will be skipped during installation."
                    }

                    [System.Windows.Forms.MessageBox]::Show(
                        $importMessage,
                        "Import Successful",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                }
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to import profile:`n$($result.Message)",
                    "Import Failed",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    })
    $form.Controls.Add($importButton)
    $currentX += $buttonWidth + $spacing

    # Install Selected button
    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Location = New-InstallerPoint($currentX, $buttonY)
    $installButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $installButton.Text = "Install`nSelected"
    $installButton.Font = $buttonFontBold
    $installButton.AutoSize = $false
    $installButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $installButton.BackColor = [System.Drawing.Color]::Green
    $installButton.ForeColor = [System.Drawing.Color]::White
    $installButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $installButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Install Selected button" -Level INFO
            Install-SelectedApplications
        }
    })
    $form.Controls.Add($installButton)
    $currentX += $buttonWidth + $spacing

    # Uninstall Selected button
    $uninstallButton = New-Object System.Windows.Forms.Button
    $uninstallButton.Location = New-InstallerPoint($currentX, $buttonY)
    $uninstallButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $uninstallButton.Text = "Uninstall`nSelected"
    $uninstallButton.Font = $buttonFontBold
    $uninstallButton.AutoSize = $false
    $uninstallButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $uninstallButton.BackColor = [System.Drawing.Color]::DarkRed
    $uninstallButton.ForeColor = [System.Drawing.Color]::White
    $uninstallButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $uninstallButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Uninstall Selected button" -Level INFO
            Uninstall-SelectedApplications
        }
    })
    $form.Controls.Add($uninstallButton)
    $currentX += $buttonWidth + $spacing

    # Check for Updates button
    $checkUpdatesButton = New-Object System.Windows.Forms.Button
    $checkUpdatesButton.Location = New-InstallerPoint($currentX, $buttonY)
    $checkUpdatesButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $checkUpdatesButton.Text = "Check for`nUpdates"
    $checkUpdatesButton.Font = $buttonFont
    $checkUpdatesButton.AutoSize = $false
    $checkUpdatesButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $checkUpdatesButton.BackColor = [System.Drawing.Color]::DodgerBlue
    $checkUpdatesButton.ForeColor = [System.Drawing.Color]::White
    $checkUpdatesButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $checkUpdatesButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Check for Updates button" -Level INFO
            Check-ForUpdates
        }
    })
    $form.Controls.Add($checkUpdatesButton)
    $currentX += $buttonWidth + $spacing

    # Pause/Resume button (initially hidden, shown during installation)
    $script:PauseResumeButton = New-Object System.Windows.Forms.Button
    $script:PauseResumeButton.Location = New-InstallerPoint($currentX, $buttonY)
    $script:PauseResumeButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $script:PauseResumeButton.Text = "Pause"
    $script:PauseResumeButton.Font = $buttonFont
    $script:PauseResumeButton.AutoSize = $false
    $script:PauseResumeButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:PauseResumeButton.BackColor = [System.Drawing.Color]::Orange
    $script:PauseResumeButton.ForeColor = [System.Drawing.Color]::White
    $script:PauseResumeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $script:PauseResumeButton.Visible = $false  # Hidden until installation starts
    $script:PauseResumeButton.Add_Click({
        if (-not $script:IsClosing) {
            if ($script:IsPaused) {
                # Resume
                Write-Log "User clicked Resume button" -Level INFO
                $script:IsPaused = $false
                $script:PauseResumeButton.Text = "Pause"
                $script:PauseResumeButton.BackColor = [System.Drawing.Color]::Orange
                Write-Output "[RESUME] Installation resumed" -Color ([System.Drawing.Color]::Green)
            }
            else {
                # Pause
                Write-Log "User clicked Pause button" -Level INFO
                $script:IsPaused = $true
                $script:PauseResumeButton.Text = "Resume"
                $script:PauseResumeButton.BackColor = [System.Drawing.Color]::Green
                Write-Output "[PAUSE] Installation paused" -Color ([System.Drawing.Color]::Yellow)
                Save-QueueState
            }
        }
    })
    $form.Controls.Add($script:PauseResumeButton)
    $currentX += $buttonWidth + $spacing

    # Skip button (initially hidden, shown during installation)
    $script:SkipButton = New-Object System.Windows.Forms.Button
    $script:SkipButton.Location = New-InstallerPoint($currentX, $buttonY)
    $script:SkipButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $script:SkipButton.Text = "Skip`nCurrent"
    $script:SkipButton.Font = $buttonFont
    $script:SkipButton.AutoSize = $false
    $script:SkipButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:SkipButton.BackColor = [System.Drawing.Color]::DarkOrange
    $script:SkipButton.ForeColor = [System.Drawing.Color]::White
    $script:SkipButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $script:SkipButton.Visible = $false  # Hidden until installation starts
    $script:SkipButton.Add_Click({
        if (-not $script:IsClosing -and $script:IsInstalling) {
            Write-Log "User clicked Skip Current button" -Level INFO
            $script:SkipCurrent = $true
            Write-Output "[SKIP] Skipping current installation..." -Color ([System.Drawing.Color]::Yellow)
        }
    })
    $form.Controls.Add($script:SkipButton)
    $currentX += $buttonWidth + $spacing

    # Exit button
    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Location = New-InstallerPoint($currentX, $buttonY)
    $exitButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $exitButton.Text = "Exit"
    $exitButton.Font = $buttonFont
    $exitButton.AutoSize = $false
    $exitButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $exitButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $exitButton.Add_Click({ $form.Close() })
    $form.Controls.Add($exitButton)

    # Add dynamic resize handler for responsive column width adjustment
    Add-MainFormResizeHandler -Form $form -ListView $script:ListView -WebBrowser $script:WebBrowser

    # Ensure Description column resizes when the user moves the splitter between ListView and HTML/console
    if ($script:MainSplitContainer) {
        $script:MainSplitContainer.Add_SplitterMoved({
            try {
                if ($script:ListView -and $script:ListView.Columns.Count -ge 5) {
                    $usedWidth = 0
                    for ($i = 0; $i -lt 4; $i++) {
                        $usedWidth += $script:ListView.Columns[$i].Width
                    }
                    $scrollbarWidth = 25
                    $newDescWidth = [Math]::Max($script:ListView.Width - $usedWidth - $scrollbarWidth, 200)
                    $script:ListView.Columns[4].Width = $newDescWidth
                }
            }
            catch {
                # Silently ignore errors during splitter move
            }
        })
    }
}

#endregion GUI Creation

#region Event Handlers

function Filter-Applications {
    <#
    .SYNOPSIS
        Filters the application list based on search term.

    .DESCRIPTION
        Filters applications by matching search term against Name, Category, and Description.
        Updates the ListView with filtered results while preserving checkbox states.

    .PARAMETER SearchTerm
        The search term to filter by (case-insensitive).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SearchTerm = ""
    )

    # Store current checkbox states
    $checkedApps = @{}
    foreach ($item in $script:ListView.Items) {
        if ($item.Checked) {
            $app = $item.Tag
            if ($app) {
                $checkedApps[$app.Name] = $true
            }
        }
    }

    # Clear ListView
    $script:ListView.Items.Clear()

    # Filter applications
    if ([string]::IsNullOrWhiteSpace($SearchTerm)) {
        # No filter - show all applications
        $script:FilteredApplications = $script:Applications
    }
    else {
        # Filter by Name, Category, or Description (case-insensitive)
        $script:FilteredApplications = $script:Applications | Where-Object {
            $_.Name -like "*$SearchTerm*" -or
            $_.Category -like "*$SearchTerm*" -or
            $_.Description -like "*$SearchTerm*"
        }
    }

    # Group filtered applications by category
    $categories = $script:FilteredApplications | Group-Object -Property Category | Sort-Object Name

    # Add filtered applications to ListView
    foreach ($category in $categories) {
        foreach ($app in $category.Group | Sort-Object Name) {
            $item = New-Object System.Windows.Forms.ListViewItem($app.Name)
            $item.SubItems.Add($app.Category) | Out-Null

            # Check if installed
            $isInstalled = $script:InstalledApps.ContainsKey($app.Name)
            if ($isInstalled) {
                $item.SubItems.Add("Installed") | Out-Null
                $item.SubItems.Add($script:InstalledApps[$app.Name]) | Out-Null
                $item.ForeColor = [System.Drawing.Color]::Green
            }
            else {
                $item.SubItems.Add("Not Installed") | Out-Null
                $item.SubItems.Add("") | Out-Null
                $item.ForeColor = [System.Drawing.Color]::Red
            }

            # Add description
            $item.SubItems.Add($app.Description) | Out-Null

            # Store app object in Tag
            $item.Tag = $app

            # If this app was marked to be ignored for profile-based installs, keep it
            # checked and gray to indicate it will be skipped.
            $ignoreProfileInstall = $false
            if ($app.PSObject.Properties.Match('IgnoreProfileInstall').Count -gt 0 -and $app.IgnoreProfileInstall) {
                $ignoreProfileInstall = $true
            }

            if ($ignoreProfileInstall) {
                $item.Checked = $true
                $item.ForeColor = [System.Drawing.Color]::DarkGray
            }
            elseif ($checkedApps.ContainsKey($app.Name)) {
                # Restore checkbox state if it was checked before filtering
                $item.Checked = $true
            }

            $script:ListView.Items.Add($item) | Out-Null
        }
    }

    # Update result count label
    $totalCount = $script:Applications.Count
    $filteredCount = $script:FilteredApplications.Count
    $installedCount = ($script:ListView.Items | Where-Object { $_.SubItems[2].Text -eq "Installed" }).Count

    if ([string]::IsNullOrWhiteSpace($SearchTerm)) {
        $script:ResultCountLabel.Text = "Showing $filteredCount of $totalCount applications ($installedCount installed)"
    }
    else {
        $script:ResultCountLabel.Text = "Showing $filteredCount of $totalCount applications (filtered)"
    }

    # Update progress label
    $checkedCount = ($script:ListView.Items | Where-Object { $_.Checked }).Count
    if ($checkedCount -gt 0) {
        $script:ProgressBar.Maximum = $checkedCount
        $script:ProgressLabel.Text = "0 / $checkedCount applications (0%)"
    }
    else {
        $script:ProgressBar.Maximum = 1
        $script:ProgressBar.Value = 0
        $script:ProgressLabel.Text = "0 / 0 applications (0%)"
    }

    Write-Log "Filtered applications: $filteredCount of $totalCount (Search: '$SearchTerm')" -Level INFO
}

function Refresh-ApplicationList {
    Write-Output "`r`n=== Refreshing Application List ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Refreshing application list..." -Color ([System.Drawing.Color]::Blue)

    # Get installed applications
    $script:InstalledApps = Get-InstalledApplications

    # Apply current search filter
    Filter-Applications -SearchTerm $script:SearchTerm

    $installedCount = ($script:ListView.Items | Where-Object { $_.SubItems[2].Text -eq "Installed" }).Count
    $totalCount = $script:Applications.Count

    Write-Output "Ready - $installedCount of $totalCount applications installed" -Color ([System.Drawing.Color]::Green)
    Write-Output "Application list refreshed: $installedCount / $totalCount installed" -Color ([System.Drawing.Color]::Green)
}


#region Queue Management Functions

function Save-QueueState {
    <#
    .SYNOPSIS
        Saves the current installation queue state to JSON file.

    .DESCRIPTION
        Persists the installation queue, current index, and pause state to allow
        resuming interrupted installations.
    #>
    [CmdletBinding()]
    param()

    try {
        # Ensure directory exists
        $queueDir = Split-Path $script:QueueStatePath -Parent
        if (-not (Test-Path $queueDir)) {
            New-Item -Path $queueDir -ItemType Directory -Force | Out-Null
        }

        # Create state object
        $state = @{
            Version = $script:ScriptVersion
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            CurrentIndex = $script:CurrentQueueIndex
            IsPaused = $script:IsPaused
            Queue = @($script:InstallationQueue | ForEach-Object {
                @{
                    Name = $_.Name
                    ScriptName = $_.ScriptName
                    WingetId = $_.WingetId
                    Category = $_.Category
                    Description = $_.Description
                }
            })
        }

        # Save to JSON
        $state | ConvertTo-Json -Depth 10 | Set-Content -Path $script:QueueStatePath -Encoding UTF8
        Write-Log "Queue state saved to: $script:QueueStatePath" -Level INFO
        return $true
    }
    catch {
        Write-Log "Failed to save queue state: $_" -Level ERROR
        return $false
    }
}

function Load-QueueState {
    <#
    .SYNOPSIS
        Loads the installation queue state from JSON file.

    .DESCRIPTION
        Restores a previously saved installation queue to allow resuming
        interrupted installations.

    .OUTPUTS
        Returns $true if state was loaded successfully, $false otherwise.
    #>
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path $script:QueueStatePath)) {
            Write-Log "No saved queue state found" -Level INFO
            return $false
        }

        # Load state from JSON
        $state = Get-Content -Path $script:QueueStatePath -Raw | ConvertFrom-Json

        # Validate state
        if (-not $state.Queue -or $state.Queue.Count -eq 0) {
            Write-Log "Saved queue state is empty" -Level INFO
            return $false
        }

        # Restore queue
        $script:InstallationQueue = @($state.Queue | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                ScriptName = $_.ScriptName
                WingetId = $_.WingetId
                Category = $_.Category
                Description = $_.Description
            }
        })

        $script:CurrentQueueIndex = $state.CurrentIndex
        $script:IsPaused = $state.IsPaused

        Write-Log "Queue state loaded: $($script:InstallationQueue.Count) apps, index $script:CurrentQueueIndex" -Level INFO
        return $true
    }
    catch {
        Write-Log "Failed to load queue state: $_" -Level ERROR
        return $false
    }
}

function Clear-QueueState {
    <#
    .SYNOPSIS
        Clears the saved queue state file.

    .DESCRIPTION
        Removes the queue state file after successful completion or cancellation.
    #>
    [CmdletBinding()]
    param()

    try {
        if (Test-Path $script:QueueStatePath) {
            Remove-Item -Path $script:QueueStatePath -Force
            Write-Log "Queue state file cleared" -Level INFO
        }
    }
    catch {
        Write-Log "Failed to clear queue state: $_" -Level WARNING
    }
}

function Show-QueueManagementDialog {
    <#
    .SYNOPSIS
        Shows a dialog for managing the installation queue.

    .DESCRIPTION
        Displays a Windows Forms dialog allowing users to:
        - View the installation queue
        - Reorder items (move up/down, drag-drop)
        - Remove items from queue
        - Prioritize items (move to top)

    .PARAMETER Queue
        The installation queue array to manage.

    .OUTPUTS
        Returns the modified queue array, or $null if cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Queue
    )

    # Get DPI scaling factor using standardized function
    $scaleInfo = Get-DPIScaleFactor
    $scaleFactor = $scaleInfo.TotalScale
    $screenWidth = $scaleInfo.ScreenWidth
    $screenHeight = $scaleInfo.ScreenHeight

    # Create a working copy of the queue that will be modified by button handlers
    # This ensures all changes are tracked in one place
    $workingQueue = New-Object System.Collections.ArrayList
    foreach ($app in $Queue) {
        $null = $workingQueue.Add($app)
    }

    # Base dimensions (before scaling)
    $baseMargin = 15
    # Use a more compact default height for the queue ListView to avoid excessive blank space
    $baseListViewHeight = 420
    $baseButtonHeight = 35
    $baseButtonSpacing = 12
    $baseFontSize = 9  # Button font size
    $baseTableFontSize = 11  # Table font size (increased by 1)

    # Apply scaling
    $margin = [int]($baseMargin * $scaleFactor)
    $listViewHeight = [int]($baseListViewHeight * $scaleFactor)
    $buttonHeight = [int]($baseButtonHeight * $scaleFactor)
    $buttonSpacing = [int]($baseButtonSpacing * $scaleFactor)

    # Calculate font sizes with minimum constraints
    $fontSize = [Math]::Max([int]($baseFontSize * $scaleFactor), 8)
    $tableFontSize = [Math]::Max([int]($baseTableFontSize * $scaleFactor), 10)

    # Create fonts for measurement
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $tableFont = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)

    # Calculate dynamic column widths based on actual queue content
    # Index column - measure header "#" and potential index numbers
    $maxIndexWidth = Measure-TextWidth -Text "#" -Font $tableFont
    if ($Queue.Count -gt 0) {
        $maxIndexText = $Queue.Count.ToString()
        $indexWidth = Measure-TextWidth -Text $maxIndexText -Font $tableFont
        $maxIndexWidth = [Math]::Max($maxIndexWidth, $indexWidth)
    }
    $col1Width = $maxIndexWidth + [int](30 * $scaleFactor)
    $col1Width = [Math]::Max($col1Width, [int](40 * $scaleFactor))

    # Application column - measure both data and header
    if ($Queue.Count -gt 0) {
        $col2Width = Get-DynamicColumnWidth -Items $Queue -PropertyName "Name" -HeaderText "Application" -Font $tableFont -MinWidth ([int](150 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))
        $col3Width = Get-DynamicColumnWidth -Items $Queue -PropertyName "Category" -HeaderText "Category" -Font $tableFont -MinWidth ([int](100 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))
    }
    else {
        # If queue is empty, just measure headers
        $col2Width = (Measure-TextWidth -Text "Application" -Font $tableFont) + [int](30 * $scaleFactor)
        $col2Width = [Math]::Max($col2Width, [int](150 * $scaleFactor))
        $col3Width = (Measure-TextWidth -Text "Category" -Font $tableFont) + [int](30 * $scaleFactor)
        $col3Width = [Math]::Max($col3Width, [int](100 * $scaleFactor))
    }

    # Calculate ListView width based on columns
    $scrollbarWidth = [int](25 * $scaleFactor)
    $listViewWidth = $col1Width + $col2Width + $col3Width + $scrollbarWidth

    # Calculate dynamic button widths based on text
    $buttonTexts = @("Move Up", "Move Down", "Move to Top (Prioritize)", "Remove from Queue")
    $maxButtonWidth = 0
    foreach ($btnText in $buttonTexts) {
        $btnWidth = Get-DynamicButtonWidth -Text $btnText -Font $buttonFont -MinWidth ([int](120 * $scaleFactor)) -Padding ([int](40 * $scaleFactor))
        if ($btnWidth -gt $maxButtonWidth) {
            $maxButtonWidth = $btnWidth
        }
    }
    $buttonWidth = $maxButtonWidth

    # Calculate form dimensions to fit all content without clipping (avoid excessive vertical padding)
    $formWidth = $margin + $listViewWidth + $margin + $buttonWidth + $margin
    $formHeight = $margin + $listViewHeight + $margin + $buttonHeight + $margin

    # Create dialog form with responsive sizing using New-ResponsiveForm
    $queueForm = New-ResponsiveForm -Title "Manage Installation Queue" `
        -Width $formWidth `
        -Height $formHeight `
        -StartPosition 'CenterParent' `
        -Resizable $true

    # Create ListView for queue with scaled dimensions
    $queueListView = New-Object System.Windows.Forms.ListView
    $queueListView.Location = New-InstallerPoint($margin, $margin)
    $queueListView.Size = New-Object System.Drawing.Size($listViewWidth, $listViewHeight)
    $queueListView.View = [System.Windows.Forms.View]::Details
    $queueListView.FullRowSelect = $true
    $queueListView.GridLines = $true
    $queueListView.AllowDrop = $true
    $queueListView.HideSelection = $false
    $queueListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)
    $queueListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left

    # Add columns with calculated widths
    $queueListView.Columns.Add("#", $col1Width) | Out-Null
    $queueListView.Columns.Add("Application", $col2Width) | Out-Null
    $queueListView.Columns.Add("Category", $col3Width) | Out-Null

    # Set row height using ImageList for better scaling
    $rowHeight = [Math]::Max([int](22 * $scaleFactor), 22)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $queueListView.SmallImageList = $imageList

    # Helper function to refresh the ListView from workingQueue
    $refreshListView = {
        $queueListView.Items.Clear()
        $i = 1
        foreach ($app in $workingQueue) {
            $item = New-Object System.Windows.Forms.ListViewItem($i.ToString())
            $item.SubItems.Add($app.Name) | Out-Null
            $item.SubItems.Add($app.Category) | Out-Null
            $item.Tag = $app
            $queueListView.Items.Add($item) | Out-Null
            $i++
        }
    }

    # Initial population
    & $refreshListView

    $queueForm.Controls.Add($queueListView)

    # Create button panel with scaled positions
    $buttonX = $margin + $listViewWidth + $margin
    $buttonY = $margin

    # Move Up button
    $moveUpButton = New-Object System.Windows.Forms.Button
    $moveUpButton.Location = New-InstallerPoint($buttonX, $buttonY)
    $moveUpButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $moveUpButton.Text = "Move Up"
    $moveUpButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $moveUpButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $moveUpButton.Add_Click({
        if ($queueListView.SelectedIndices.Count -eq 0) { return }
        $index = $queueListView.SelectedIndices[0]
        if ($index -eq 0) { return }

        # Swap items in workingQueue
        $temp = $workingQueue[$index]
        $workingQueue[$index] = $workingQueue[$index - 1]
        $workingQueue[$index - 1] = $temp

        # Refresh ListView
        & $refreshListView

        # Maintain selection
        if ($index - 1 -lt $queueListView.Items.Count) {
            $queueListView.Items[$index - 1].Selected = $true
            $queueListView.Items[$index - 1].EnsureVisible()
        }
    }.GetNewClosure())
    $queueForm.Controls.Add($moveUpButton)

    # Move Down button
    $buttonY = $buttonY + $buttonHeight + $buttonSpacing
    $moveDownButton = New-Object System.Windows.Forms.Button
    $moveDownButton.Location = New-InstallerPoint($buttonX, $buttonY)
    $moveDownButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $moveDownButton.Text = "Move Down"
    $moveDownButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $moveDownButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $moveDownButton.Add_Click({
        if ($queueListView.SelectedIndices.Count -eq 0) { return }
        $index = $queueListView.SelectedIndices[0]
        if ($index -eq $workingQueue.Count - 1) { return }

        # Swap items in workingQueue
        $temp = $workingQueue[$index]
        $workingQueue[$index] = $workingQueue[$index + 1]
        $workingQueue[$index + 1] = $temp

        # Refresh ListView
        & $refreshListView

        # Maintain selection
        if ($index + 1 -lt $queueListView.Items.Count) {
            $queueListView.Items[$index + 1].Selected = $true
            $queueListView.Items[$index + 1].EnsureVisible()
        }
    }.GetNewClosure())
    $queueForm.Controls.Add($moveDownButton)

    # Move to Top button
    $buttonY = $buttonY + $buttonHeight + $buttonSpacing
    $moveTopButton = New-Object System.Windows.Forms.Button
    $moveTopButton.Location = New-InstallerPoint($buttonX, $buttonY)
    $moveTopButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $moveTopButton.Text = "Move to Top (Prioritize)"
    $moveTopButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $moveTopButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $moveTopButton.Add_Click({
        if ($queueListView.SelectedIndices.Count -eq 0) { return }
        $index = $queueListView.SelectedIndices[0]
        if ($index -eq 0) { return }

        # Move to top - extract the item
        $selectedApp = $workingQueue[$index]

        # Remove from current position
        $workingQueue.RemoveAt($index)

        # Insert at the front
        $workingQueue.Insert(0, $selectedApp)

        # Refresh ListView
        & $refreshListView

        # Select the moved item (now at top)
        if ($queueListView.Items.Count -gt 0) {
            $queueListView.Items[0].Selected = $true
            $queueListView.Items[0].EnsureVisible()
        }
    }.GetNewClosure())
    $queueForm.Controls.Add($moveTopButton)

    # Remove from Queue button
    $buttonY = $buttonY + $buttonHeight + $buttonSpacing
    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Location = New-InstallerPoint($buttonX, $buttonY)
    $removeButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $removeButton.Text = "Remove from Queue"
    $removeButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $removeButton.ForeColor = [System.Drawing.Color]::Red
    $removeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $removeButton.Add_Click({
        if ($queueListView.SelectedIndices.Count -eq 0) { return }
        $index = $queueListView.SelectedIndices[0]

        # Remove item from workingQueue
        $workingQueue.RemoveAt($index)

        # Refresh ListView
        & $refreshListView

        # Select the next item if available, or the previous one
        if ($workingQueue.Count -gt 0) {
            if ($index -lt $workingQueue.Count) {
                $queueListView.Items[$index].Selected = $true
                $queueListView.Items[$index].EnsureVisible()
            }
            else {
                $queueListView.Items[$workingQueue.Count - 1].Selected = $true
                $queueListView.Items[$workingQueue.Count - 1].EnsureVisible()
            }
        }
    }.GetNewClosure())
    $queueForm.Controls.Add($removeButton)

    # OK button (bottom of form)
    $okCancelButtonWidth = [int](90 * $scaleFactor)
    # Align bottom buttons with a standard bottom margin (no extra padding block)
    $bottomButtonY = $formHeight - $margin - $buttonHeight

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-InstallerPoint($buttonX, $bottomButtonY)
    $okButton.Size = New-Object System.Drawing.Size($okCancelButtonWidth, $buttonHeight)
    $okButton.Text = "OK"
    $okButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $okButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $queueForm.Controls.Add($okButton)

    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-InstallerPoint(($buttonX + $okCancelButtonWidth + $spacing), $bottomButtonY)
    $cancelButton.Size = New-Object System.Drawing.Size($okCancelButtonWidth, $buttonHeight)
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $queueForm.Controls.Add($cancelButton)

    $queueForm.AcceptButton = $okButton
    $queueForm.CancelButton = $cancelButton

    # Add dynamic resize handler for responsive layout
    Add-QueueFormResizeHandler -Form $queueForm -ListView $queueListView

    # Show dialog
    $result = $queueForm.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "Queue management completed - returning modified queue with $($workingQueue.Count) items" -Level INFO
        # Return the modified workingQueue as an array
        return $workingQueue.ToArray()
    }
    else {
        Write-Log "Queue management cancelled" -Level INFO
        return $null
    }
}

#endregion Queue Management Functions

#region Update Checker Functions

function Show-UpdatesDialog {
    <#
    .SYNOPSIS
        Shows a dialog with available updates and allows user to select which to install.

    .PARAMETER Updates
        Array of update objects from Get-AvailableUpdates.

    .OUTPUTS
        Array of selected update objects to install, or $null if cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Updates
    )

    Write-Log "Showing updates dialog with $($Updates.Count) available update(s)" -Level INFO

    # Get DPI scaling factor using standardized function
    $scaleInfo = Get-DPIScaleFactor
    $scaleFactor = $scaleInfo.TotalScale
    $screenWidth = $scaleInfo.ScreenWidth
    $screenHeight = $scaleInfo.ScreenHeight

    # Base dimensions (before scaling)
    $baseMargin = 15
    $baseTitleHeight = 30
    $baseListViewHeight = 420
    $baseButtonHeight = 35
    $baseFontSize = 10
    $baseTitleFontSize = 12
    $baseTableFontSize = 10

    # Apply scaling
    $margin = [int]($baseMargin * $scaleFactor)
    $titleHeight = [int]($baseTitleHeight * $scaleFactor)
    $listViewHeight = [int]($baseListViewHeight * $scaleFactor)
    $buttonHeight = [int]($baseButtonHeight * $scaleFactor)

    # Calculate font sizes with minimum constraints
    $fontSize = [Math]::Max([int]($baseFontSize * $scaleFactor), 9)
    $titleFontSize = [Math]::Max([int]($baseTitleFontSize * $scaleFactor), 10)
    $tableFontSize = [Math]::Max([int]($baseTableFontSize * $scaleFactor), 9)

    # Create fonts for measurement
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $tableFont = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)

    # Calculate dynamic column widths based on update content
    if ($Updates.Count -gt 0) {
        # Application name column - measure both data and header
        $col1Width = Get-DynamicColumnWidth -Items $Updates -PropertyName "Name" -HeaderText "Application" -Font $tableFont -MinWidth ([int](200 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))

        # Version columns - measure both current and available versions, plus headers
        $maxVersionWidth = 0
        # Measure header texts
        $currentHeaderWidth = Measure-TextWidth -Text "Current Version" -Font $tableFont
        $availableHeaderWidth = Measure-TextWidth -Text "Available Version" -Font $tableFont
        $maxVersionWidth = [Math]::Max($currentHeaderWidth, $availableHeaderWidth)

        # Measure version data
        foreach ($update in $Updates) {
            $currentWidth = Measure-TextWidth -Text $update.CurrentVersion -Font $tableFont
            $availableWidth = Measure-TextWidth -Text $update.AvailableVersion -Font $tableFont
            $maxWidth = [Math]::Max($currentWidth, $availableWidth)
            if ($maxWidth -gt $maxVersionWidth) {
                $maxVersionWidth = $maxWidth
            }
        }
        $col2Width = [Math]::Max($maxVersionWidth + [int](30 * $scaleFactor), [int](120 * $scaleFactor))
        $col3Width = $col2Width  # Same width for both version columns

        # Source column - measure both data and header
        $col4Width = Get-DynamicColumnWidth -Items $Updates -PropertyName "Source" -HeaderText "Source" -Font $tableFont -MinWidth ([int](100 * $scaleFactor)) -Padding ([int](30 * $scaleFactor))
    }
    else {
        # If no updates, just measure headers
        $col1Width = (Measure-TextWidth -Text "Application" -Font $tableFont) + [int](30 * $scaleFactor)
        $col1Width = [Math]::Max($col1Width, [int](200 * $scaleFactor))

        $col2Width = (Measure-TextWidth -Text "Current Version" -Font $tableFont) + [int](30 * $scaleFactor)
        $col2Width = [Math]::Max($col2Width, [int](120 * $scaleFactor))

        $col3Width = (Measure-TextWidth -Text "Available Version" -Font $tableFont) + [int](30 * $scaleFactor)
        $col3Width = [Math]::Max($col3Width, [int](120 * $scaleFactor))

        $col4Width = (Measure-TextWidth -Text "Source" -Font $tableFont) + [int](30 * $scaleFactor)
        $col4Width = [Math]::Max($col4Width, [int](100 * $scaleFactor))
    }

    # Calculate ListView width based on columns
    $scrollbarWidth = [int](25 * $scaleFactor)
    $listViewWidth = $col1Width + $col2Width + $col3Width + $col4Width + $scrollbarWidth

    # Calculate dynamic button widths
    $buttonTexts = @("Select All", "Deselect All", "Update Selected", "Cancel")
    $maxButtonWidth = 0
    foreach ($btnText in $buttonTexts) {
        $btnWidth = Get-DynamicButtonWidth -Text $btnText -Font $buttonFont -MinWidth ([int](100 * $scaleFactor)) -Padding ([int](40 * $scaleFactor))
        if ($btnWidth -gt $maxButtonWidth) {
            $maxButtonWidth = $btnWidth
        }
    }
    $buttonWidth = $maxButtonWidth

    # Calculate form dimensions to fit all content
    $formWidth = [Math]::Max($listViewWidth + ($margin * 2), [int](800 * $scaleFactor))
    $formHeight = $margin + $titleHeight + $margin + $listViewHeight + $margin + $buttonHeight + $margin + [int](60 * $scaleFactor)

    # Create form with responsive sizing using New-ResponsiveForm
    $updatesForm = New-ResponsiveForm -Title "Available Updates" `
        -Width $formWidth `
        -Height $formHeight `
        -StartPosition 'CenterScreen' `
        -Resizable $true

    # Title label with scaled font
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-InstallerPoint($margin, $margin)
    $titleLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $titleHeight)
    $titleLabel.Text = "Found $($Updates.Count) application(s) with available updates:"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $titleFontSize, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $updatesForm.Controls.Add($titleLabel)

    # ListView for updates with scaled dimensions
    $listViewTop = $margin + $titleHeight + $margin
    $updatesListView = New-Object System.Windows.Forms.ListView
    $updatesListView.Location = New-InstallerPoint($margin, $listViewTop)
    $updatesListView.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $listViewHeight)
    $updatesListView.View = [System.Windows.Forms.View]::Details
    $updatesListView.FullRowSelect = $true
    $updatesListView.CheckBoxes = $true
    $updatesListView.GridLines = $true
    $updatesListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)
    $updatesListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    # Add columns with dynamic widths
    $updatesListView.Columns.Add("Application", $col1Width) | Out-Null
    $updatesListView.Columns.Add("Current Version", $col2Width) | Out-Null
    $updatesListView.Columns.Add("Available Version", $col3Width) | Out-Null
    $updatesListView.Columns.Add("Source", $col4Width) | Out-Null

    # Set row height using ImageList for better scaling
    $rowHeight = [Math]::Max([int](20 * $scaleFactor), 20)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $updatesListView.SmallImageList = $imageList

    # Populate ListView
    foreach ($update in $Updates) {
        $item = New-Object System.Windows.Forms.ListViewItem($update.Name)
        $item.SubItems.Add($update.CurrentVersion) | Out-Null
        $item.SubItems.Add($update.AvailableVersion) | Out-Null
        $item.SubItems.Add($update.Source) | Out-Null
        $item.Tag = $update
        $item.Checked = $true  # Check all by default
        $updatesListView.Items.Add($item) | Out-Null
    }

    # Add click-to-select and drag-to-multi-select functionality
    Add-ListViewClickToSelect -ListView $updatesListView

    $updatesForm.Controls.Add($updatesListView)

    # Calculate button positions with scaling
    $buttonY = $listViewTop + $listViewHeight + $margin
    $spacing = [int](10 * $scaleFactor)

    # Select All button
    $selectAllButton = New-Object System.Windows.Forms.Button
    $selectAllButton.Location = New-InstallerPoint($margin, $buttonY)
    $selectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectAllButton.Text = "Select All"
    $selectAllButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $selectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $selectAllButton.Add_Click({
        foreach ($item in $updatesListView.Items) {
            $item.Checked = $true
        }
    })
    $updatesForm.Controls.Add($selectAllButton)

    # Deselect All button
    $deselectAllButton = New-Object System.Windows.Forms.Button
    $deselectAllButton.Location = New-InstallerPoint(($margin + $buttonWidth + $spacing), $buttonY)
    $deselectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $deselectAllButton.Text = "Deselect All"
    $deselectAllButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $deselectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $deselectAllButton.Add_Click({
        foreach ($item in $updatesListView.Items) {
            $item.Checked = $false
        }
    })
    $updatesForm.Controls.Add($deselectAllButton)

    # Update Selected button (right side) - uses same dynamic width as other buttons
    $updateSelectedButton = New-Object System.Windows.Forms.Button
    $updateSelectedButton.Location = New-InstallerPoint(($formWidth - $margin - $buttonWidth - $spacing - $buttonWidth), $buttonY)
    $updateSelectedButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $updateSelectedButton.Text = "Update Selected"
    $updateSelectedButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $updateSelectedButton.BackColor = [System.Drawing.Color]::Green
    $updateSelectedButton.ForeColor = [System.Drawing.Color]::White
    $updateSelectedButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $updateSelectedButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $updatesForm.Controls.Add($updateSelectedButton)

    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-InstallerPoint(($formWidth - $margin - $buttonWidth), $buttonY)
    $cancelButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $updatesForm.Controls.Add($cancelButton)

    $updatesForm.AcceptButton = $updateSelectedButton
    $updatesForm.CancelButton = $cancelButton

    # Add dynamic resize handler for responsive layout
    Add-UpdatesFormResizeHandler -Form $updatesForm -ListView $updatesListView -TitleLabel $titleLabel

    # Show dialog
    $result = $updatesForm.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Get checked items
        $selectedUpdates = @()
        foreach ($item in $updatesListView.Items) {
            if ($item.Checked) {
                $selectedUpdates += $item.Tag
            }
        }

        Write-Log "User selected $($selectedUpdates.Count) update(s) to install" -Level INFO
        return $selectedUpdates
    }
    else {
        Write-Log "Update dialog cancelled" -Level INFO
        return $null
    }
}

function Check-ForUpdates {
    <#
    .SYNOPSIS
        Main function to check for updates and handle the update process.

    .DESCRIPTION
        Checks for available updates, shows dialog, and processes selected updates.
    #>
    [CmdletBinding()]
    param()

    Write-Log "User initiated update check" -Level INFO
    Write-Output "[CHECK] Checking for available updates..." -Color ([System.Drawing.Color]::Cyan)

    # Get available updates
    $updates = Get-AvailableUpdates

    if ($updates.Count -eq 0) {
        Write-Log "No updates available" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "All applications are up to date!",
            "No Updates Available",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Show updates dialog
    $selectedUpdates = Show-UpdatesDialog -Updates $updates

    if ($null -eq $selectedUpdates -or $selectedUpdates.Count -eq 0) {
        Write-Log "No updates selected or dialog cancelled" -Level INFO
        return
    }

    # Confirm update
    $confirmResult = [System.Windows.Forms.MessageBox]::Show(
        "Update $($selectedUpdates.Count) application(s)?`n`nThis may take several minutes.",
        "Confirm Updates",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "User cancelled update confirmation" -Level INFO
        return
    }

    # Perform updates
    Write-Output "`r`n=== Starting Updates ===" -Color ([System.Drawing.Color]::Cyan)
    $result = Update-Applications -Updates $selectedUpdates

    # Show completion message
    $completionColor = if ($result.FailCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }
    Write-Output "`r`n=== Updates Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Updates complete: $($result.SuccessCount) succeeded, $($result.FailCount) failed" -Color $completionColor

    [System.Windows.Forms.MessageBox]::Show(
        "Updates complete!`n`nSuccessful: $($result.SuccessCount)`nFailed: $($result.FailCount)",
        "Updates Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

#endregion Update Checker Functions

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
        Array of application names to export.

    .PARAMETER FilePath
        Optional custom file path. If not specified, uses default naming convention
        in C:\mytech.today\app_installer\profiles\

    .OUTPUTS
        String - Path to the created profile file, or $null if export failed.

    .EXAMPLE
        $apps = @("Google Chrome", "7-Zip", "VLC Media Player")
        Export-InstallationProfile -SelectedApps $apps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SelectedApps,

        [Parameter(Mandatory = $false)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string]$LongDescription,

        [Parameter(Mandatory = $false)]
        [string]$IconPath,

        [Parameter(Mandatory = $false)]
        [string[]]$Categories
    )

    try {
        # Create profiles directory if it doesn't exist
        $profilesDir = $script:ProfilesPath
        if (-not (Test-Path $profilesDir)) {
            New-Item -Path $profilesDir -ItemType Directory -Force | Out-Null
            Write-Log "Created profiles directory: $profilesDir" -Level INFO
        }

        # Generate default filename if not specified
        if ([string]::IsNullOrWhiteSpace($FilePath)) {
            $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
            $computerName = $env:COMPUTERNAME
            $FilePath = Join-Path $profilesDir "profile-$computerName-$timestamp.json"
        }

        # Normalize selected applications into names and application objects
        $appNames = @()
        $appObjects = @()

        foreach ($item in $SelectedApps) {
            if ($null -eq $item) { continue }

            if ($item -is [string]) {
                $appNames += $item
                $app = $script:Applications | Where-Object { $_.Name -eq $item } | Select-Object -First 1
                if ($app) {
                    $appObjects += $app
                }
            }
            else {
                if ($item.PSObject.Properties.Match('Name').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($item.Name)) {
                    $appNames += $item.Name
                    $appObjects += $item
                }
            }
        }

        if ($appNames.Count -eq 0) {
            Write-Log "Export-InstallationProfile (GUI) called with no valid applications" -Level ERROR
            return $null
        }

        # Derive metadata for profile export (Name, Description, LongDescription, IconPath, Categories)
        $profileName = if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $Name
        }
        else {
            "Custom profile from $($env:COMPUTERNAME)"
        }

        $shortDescription = if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $Description
        }
        else {
            "Profile containing $($appNames.Count) application(s) exported from $($env:COMPUTERNAME)."
        }

        $longDescription = if (-not [string]::IsNullOrWhiteSpace($LongDescription)) {
            $LongDescription
        }
        else {
            $shortDescription
        }

        $iconPathValue = if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
            $IconPath
        }
        else {
            $null
        }

        if (-not $Categories -or $Categories.Count -eq 0) {
            $derivedCategories = @()

            $sourceApps = if ($appObjects.Count -gt 0) {
                $appObjects
            }
            else {
                $script:Applications | Where-Object { $appNames -contains $_.Name }
            }

            foreach ($app in $sourceApps) {
                if ($app.PSObject.Properties.Match('Category').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($app.Category)) {
                    if (-not ($derivedCategories -contains $app.Category)) {
                        $derivedCategories += $app.Category
                    }
                }
            }

            if ($derivedCategories.Count -eq 0) {
                $derivedCategories = @('Uncategorized')
            }

            $Categories = $derivedCategories
        }

        # Create profile object
        $profile = [PSCustomObject]@{
            Version         = "2.0"
            Name            = $profileName
            Description     = $shortDescription
            LongDescription = $longDescription
            IconPath        = $iconPathValue
            Categories      = $Categories
            Timestamp       = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            ComputerName    = $env:COMPUTERNAME
            UserName        = $env:USERNAME
            InstallerVersion = $script:ScriptVersion
            Applications    = $appNames
        }

        # Export to JSON
        $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8

        Write-Log "Exported installation profile to: $FilePath" -Level SUCCESS
        Write-Log "Profile contains $($SelectedApps.Count) application(s)" -Level INFO

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
        $result = Import-InstallationProfile -FilePath "C:\mytech.today\app_installer\profiles\profile-PC01-2025-11-09-160000.json"
        if ($result.Success) {
            # Select the applications
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        # Validate file exists
        if (-not (Test-Path $FilePath)) {
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

        if ([string]::IsNullOrWhiteSpace($profileContent)) {
            Write-Log "Profile file is empty: $FilePath" -Level ERROR
            return @{
                Success      = $false
                Applications = @()
                MissingApps  = @()
                Message      = "Profile file is empty: $FilePath"
            }
        }

        try {
            $profile = $profileContent | ConvertFrom-Json
        }
        catch {
            Write-Log "Failed to parse profile JSON from '$FilePath': $($_.Exception.Message)" -Level ERROR
            return @{
                Success      = $false
                Applications = @()
                MissingApps  = @()
                Message      = "Invalid profile JSON format in file: $FilePath"
            }
        }

        if (-not $profile) {
            Write-Log "Profile JSON did not produce an object for file: $FilePath" -Level ERROR
            return @{
                Success      = $false
                Applications = @()
                MissingApps  = @()
                Message      = "Profile JSON is invalid or empty in file: $FilePath"
            }
        }

        # Normalize application list
        if (-not $profile.PSObject.Properties.Match('Applications').Count -or -not $profile.Applications) {
            Write-Log "Invalid profile format: Missing Applications array" -Level ERROR
            return @{
                Success      = $false
                Applications = @()
                MissingApps  = @()
                Message      = "Invalid profile format: Missing required field 'Applications'"
            }
        }

        if ($profile.Applications -is [System.Array]) {
            $appList = @($profile.Applications)
        }
        else {
            $appList = @($profile.Applications)
        }

        # Normalize metadata (Version, Name, Description, LongDescription, IconPath, Categories)
        $profileVersion = if ($profile.PSObject.Properties.Match('Version').Count -gt 0 -and $profile.Version) {
            [string]$profile.Version
        }
        else {
            "1.0"
        }

        $profileName = if ($profile.PSObject.Properties.Match('Name').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($profile.Name)) {
            [string]$profile.Name
        }
        else {
            [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        }

        $shortDescription = if ($profile.PSObject.Properties.Match('Description').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($profile.Description)) {
            [string]$profile.Description
        }
        else {
            "Profile '$profileName' with $($appList.Count) application(s)."
        }

        $longDescription = if ($profile.PSObject.Properties.Match('LongDescription').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($profile.LongDescription)) {
            [string]$profile.LongDescription
        }
        else {
            $shortDescription
        }

        $iconPathValue = $null
        if ($profile.PSObject.Properties.Match('IconPath').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($profile.IconPath)) {
            $iconPathValue = [string]$profile.IconPath
        }

        # Normalize categories
        $categories = @()
        if ($profile.PSObject.Properties.Match('Categories').Count -gt 0 -and $profile.Categories) {
            if ($profile.Categories -is [System.Array]) {
                $categoriesInput = @($profile.Categories)
            }
            else {
                $categoriesInput = @([string]$profile.Categories)
            }

            foreach ($cat in $categoriesInput) {
                if (-not [string]::IsNullOrWhiteSpace($cat)) {
                    if (-not ($categories -contains $cat)) {
                        $categories += $cat
                    }
                }
            }
        }

        if ($categories.Count -eq 0) {
            $derivedCategories = @()
            foreach ($appName in $appList) {
                $app = $script:Applications | Where-Object { $_.Name -eq $appName } | Select-Object -First 1
                if ($app -and $app.PSObject.Properties.Match('Category').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($app.Category)) {
                    if (-not ($derivedCategories -contains $app.Category)) {
                        $derivedCategories += $app.Category
                    }
                }
            }

            if ($derivedCategories.Count -eq 0) {
                $derivedCategories = @('Uncategorized')
            }

            $categories = $derivedCategories
        }

        # Push normalized metadata back into profile object for downstream consumers
        if (-not $profile.PSObject.Properties.Match('Version').Count) {
            $profile | Add-Member -NotePropertyName 'Version' -NotePropertyValue $profileVersion
        }
        else {
            $profile.Version = $profileVersion
        }

        if (-not $profile.PSObject.Properties.Match('Name').Count) {
            $profile | Add-Member -NotePropertyName 'Name' -NotePropertyValue $profileName
        }
        else {
            if ([string]::IsNullOrWhiteSpace($profile.Name)) {
                $profile.Name = $profileName
            }
        }

        if (-not $profile.PSObject.Properties.Match('Description').Count) {
            $profile | Add-Member -NotePropertyName 'Description' -NotePropertyValue $shortDescription
        }
        else {
            if ([string]::IsNullOrWhiteSpace($profile.Description)) {
                $profile.Description = $shortDescription
            }
        }

        if (-not $profile.PSObject.Properties.Match('LongDescription').Count) {
            $profile | Add-Member -NotePropertyName 'LongDescription' -NotePropertyValue $longDescription
        }
        else {
            if ([string]::IsNullOrWhiteSpace($profile.LongDescription)) {
                $profile.LongDescription = $longDescription
            }
        }

        if (-not $profile.PSObject.Properties.Match('IconPath').Count) {
            $profile | Add-Member -NotePropertyName 'IconPath' -NotePropertyValue $iconPathValue
        }
        else {
            if ([string]::IsNullOrWhiteSpace($profile.IconPath)) {
                $profile.IconPath = $iconPathValue
            }
        }

        if (-not $profile.PSObject.Properties.Match('Categories').Count) {
            $profile | Add-Member -NotePropertyName 'Categories' -NotePropertyValue $categories
        }
        else {
            $profile.Categories = $categories
        }

        $profile.Applications = $appList

        Write-Log "Importing profile from: $FilePath" -Level INFO
        Write-Log "Profile name: $profileName" -Level INFO
        Write-Log "Profile version: $profileVersion" -Level INFO
        Write-Log "Profile created: $($profile.Timestamp)" -Level INFO
        Write-Log "Profile computer: $($profile.ComputerName)" -Level INFO
        Write-Log "Profile user: $($profile.UserName)" -Level INFO
        Write-Log "Profile installer version: $($profile.InstallerVersion)" -Level INFO
        Write-Log "Profile categories: $([string]::Join(', ', $categories))" -Level INFO

        # Get list of available application names
        $availableAppNames = $script:Applications | ForEach-Object { $_.Name }

        # Check which apps from profile are available
        $validApps = @()
        $missingApps = @()

        foreach ($appName in $profile.Applications) {
            if ($availableAppNames -contains $appName) {
                $validApps += $appName
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
            Success      = $true
            Applications = $validApps
            MissingApps  = $missingApps
            Message      = "Successfully imported profile with $($validApps.Count) application(s)"
            ProfileInfo  = $profile
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


function Show-ProfileBrowserDialog {
    <#
    .SYNOPSIS
        Shows a dialog that lets the user browse available profiles as cards.

    .OUTPUTS
        String - Full path to the selected profile file, or $null if cancelled.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Preparing profile browser dialog" -Level INFO

    $profileFiles = @()
    try {
        if (Test-Path $script:ProfilesPath) {
            $profileFiles = Get-ChildItem -Path $script:ProfilesPath -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name
        }
    }
    catch {
        Write-Log "Failed to enumerate profiles directory '$script:ProfilesPath': $($_.Exception.Message)" -Level WARNING
    }

    if (-not $profileFiles -or $profileFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No profile JSON files were found in:`n$($script:ProfilesPath)`n`nUse Export Selection to create a profile first, then try again.",
            "No Profiles Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        Write-Log "No profile JSON files found in $script:ProfilesPath" -Level INFO
        return $null
    }

    $profiles = @()
    foreach ($file in $profileFiles) {
        try {
            $importResult = Import-InstallationProfile -FilePath $file.FullName
            if (-not $importResult -or -not $importResult.Success) {
                Write-Log "Skipping profile file '$($file.FullName)' because Import-InstallationProfile reported failure: $($importResult.Message)" -Level WARNING
                continue
            }

            $profileData = $importResult.ProfileInfo
            if (-not $profileData -or -not $profileData.Applications -or $profileData.Applications.Count -eq 0) { continue }

            $profiles += [PSCustomObject]@{
                FilePath        = $file.FullName
                FileName        = $file.Name
                Profile         = $profileData
                Applications    = @($profileData.Applications)
                Name            = $profileData.Name
                Description     = $profileData.Description
                LongDescription = $profileData.LongDescription
                IconPath        = $profileData.IconPath
                Categories      = @($profileData.Categories)
            }
        }
        catch {
            Write-Log "Failed to load profile file '$($file.FullName)': $($_.Exception.Message)" -Level WARNING
        }
    }

    if ($profiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No valid profiles were found in:`n$($script:ProfilesPath)`n`nEnsure the JSON files contain an Applications array.",
            "No Valid Profiles",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        Write-Log "No valid profiles (with Applications) found in $script:ProfilesPath" -Level INFO
        return $null
    }

    Write-Log "Showing profile browser dialog with $($profiles.Count) profile(s)" -Level INFO

    $scaleInfo = Get-DPIScaleFactor
    $scaleFactor = $scaleInfo.TotalScale

    $baseMargin = 15
    $baseFormWidth = 820
    $baseFormHeight = 560
    $baseTitleHeight = 26
    $baseMetaHeight = 80
    $baseButtonHeight = 35
    $baseFontSize = 10
    $baseTableFontSize = 10

    $margin = [int]($baseMargin * $scaleFactor)
    $formWidth = [int]($baseFormWidth * $scaleFactor)
    $formHeight = [int]($baseFormHeight * $scaleFactor)
    $titleHeight = [int]($baseTitleHeight * $scaleFactor)
    $metaHeight = [int]($baseMetaHeight * $scaleFactor)
    $buttonHeight = [int]($baseButtonHeight * $scaleFactor)
    $fontSize = [Math]::Max([int]($baseFontSize * $scaleFactor), 9)
    $tableFontSize = [Math]::Max([int]($baseTableFontSize * $scaleFactor), 9)
    $spacing = [int](10 * $scaleFactor)
    $navButtonWidth = [int](40 * $scaleFactor)
    $navButtonHeight = [int](40 * $scaleFactor)

    # Create profile form without relying on external responsive helpers to avoid
    # potential constructor overload issues (e.g., System.Drawing.Point with 4 args).
    $profileForm = New-Object System.Windows.Forms.Form
    $profileForm.Text = "Import Installation Profile"
    $profileForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $profileForm.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $profileForm.MinimumSize = New-Object System.Drawing.Size([int]($formWidth * 0.7), [int]($formHeight * 0.7))
    $profileForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $profileForm.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $profileForm.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Regular)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-InstallerPoint($margin, $margin)
    $titleLabelWidthBase = 2 * $margin
    $titleLabelWidth = $formWidth + [int]::Negate($titleLabelWidthBase)
    $titleLabel.Size = New-Object System.Drawing.Size($titleLabelWidth, $titleHeight)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $profileForm.Controls.Add($titleLabel)

    # Icon for the profile (loaded from IconPath if available)
    $iconSize = [int](64 * $scaleFactor)
    $iconPictureBox = New-Object System.Windows.Forms.PictureBox
    $iconXAdjustment = $margin + $iconSize
    $iconX = $formWidth + [int]::Negate($iconXAdjustment)
    $iconPictureBox.Location = New-InstallerPoint($iconX, $margin)
    $iconPictureBox.Size = New-Object System.Drawing.Size($iconSize, $iconSize)
    $iconPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $iconPictureBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $iconPictureBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $profileForm.Controls.Add($iconPictureBox)

    $metaLabel = New-Object System.Windows.Forms.Label
    $metaLabel.Location = New-InstallerPoint($margin, $margin + $titleHeight + [int](4 * $scaleFactor))
    $metaWidthBase = 2 * $margin
    $metaWidth = $formWidth + [int]::Negate($metaWidthBase)
    $metaLabel.Size = New-Object System.Drawing.Size($metaWidth, $metaHeight)
    $metaLabel.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize)
    $metaLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $metaLabel.AutoSize = $false
    $metaLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $profileForm.Controls.Add($metaLabel)

    $listTop = $margin + $titleHeight + [int](4 * $scaleFactor) + $metaHeight + $margin
    $listHeightSubTotal = $listTop + $margin + $buttonHeight + $margin
    $listHeight = $formHeight + [int]::Negate($listHeightSubTotal)
    if ($listHeight -lt 0) { $listHeight = 0 }

    $listLeft = $margin + $navButtonWidth + $spacing
    $listWidthSubTotal = (2 * $margin) + (2 * $navButtonWidth) + (2 * $spacing)
    $listWidth = $formWidth + [int]::Negate($listWidthSubTotal)
    if ($listWidth -lt 0) { $listWidth = 0 }

    $appsListView = New-Object System.Windows.Forms.ListView
    $appsListView.Location = New-InstallerPoint($listLeft, $listTop)
    $appsListView.Size = New-Object System.Drawing.Size($listWidth, $listHeight)
    $appsListView.View = [System.Windows.Forms.View]::Details
    $appsListView.FullRowSelect = $true
    $appsListView.GridLines = $true
    $appsListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)
    $appsListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $scrollbarWidth = [int](25 * $scaleFactor)
    $listViewWidth = $appsListView.Size.Width
    $colCategoryWidth = [Math]::Max([int](140 * $scaleFactor), [int](120 * $scaleFactor))
    $colAppWidthSubTotal = $colCategoryWidth + $scrollbarWidth
    $colAppWidth = $listViewWidth + [int]::Negate($colAppWidthSubTotal)
    if ($colAppWidth -lt 0) { $colAppWidth = 0 }

    $appsListView.Columns.Add("Category", $colCategoryWidth) | Out-Null
    $appsListView.Columns.Add("Application", $colAppWidth) | Out-Null

    $rowHeight = [Math]::Max([int](20 * $scaleFactor), 20)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $appsListView.SmallImageList = $imageList

    $profileForm.Controls.Add($appsListView)

    $buttonFont = New-Object System.Drawing.Font("Segoe UI", $fontSize)

    # Navigation buttons on left and right of the profile list (slideshow-style)
    $navHeightDelta = $listHeight + [int]::Negate($navButtonHeight)
    if ($navHeightDelta -lt 0) { $navHeightDelta = 0 }
    $navOffsetY = [int]($navHeightDelta / 2)
    $navCenterY = $listTop + $navOffsetY

    $prevButton = New-Object System.Windows.Forms.Button
    $prevButton.Location = New-InstallerPoint($margin, $navCenterY)
    $prevButton.Size = New-Object System.Drawing.Size($navButtonWidth, $navButtonHeight)
    $prevButton.Text = "<"
    $prevButton.Font = $buttonFont
    $prevButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $profileForm.Controls.Add($prevButton)

    $nextButton = New-Object System.Windows.Forms.Button
    $nextButtonXOffset = $margin + $navButtonWidth
    $nextButtonX = $formWidth + [int]::Negate($nextButtonXOffset)
    $nextButton.Location = New-InstallerPoint($nextButtonX, $navCenterY)
    $nextButton.Size = New-Object System.Drawing.Size($navButtonWidth, $navButtonHeight)
    $nextButton.Text = ">"
    $nextButton.Font = $buttonFont
    $nextButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $profileForm.Controls.Add($nextButton)

    # Bottom action buttons: Choose Profile, Import a Profile, Cancel (right-aligned)
    $buttonYOffset = $margin + $buttonHeight
    $buttonY = $formHeight + [int]::Negate($buttonYOffset)

    $selectWidth = [int](140 * $scaleFactor)
    $importWidth = [int](150 * $scaleFactor)

    $selectButton = New-Object System.Windows.Forms.Button
    $selectButton.Size = New-Object System.Drawing.Size($selectWidth, $buttonHeight)
    $selectButton.Text = "Choose Profile"
    $selectButton.Font = $buttonFont
    $selectButton.BackColor = [System.Drawing.Color]::Green
    $selectButton.ForeColor = [System.Drawing.Color]::White
    $selectButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $importButton = New-Object System.Windows.Forms.Button
    $importButton.Size = New-Object System.Drawing.Size($importWidth, $buttonHeight)
    $importButton.Text = "Import a Profile"
    $importButton.Font = $buttonFont
    $importButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Size = New-Object System.Drawing.Size([int](100 * $scaleFactor), $buttonHeight)
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = $buttonFont
    $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $cancelOffset = $margin + $cancelButton.Width
    $cancelButtonX = $formWidth + [int]::Negate($cancelOffset)
    $cancelButton.Location = New-InstallerPoint($cancelButtonX, $buttonY)

    $importOffset = $spacing + $importButton.Width
    $importButtonX = $cancelButtonX + [int]::Negate($importOffset)
    $importButton.Location = New-InstallerPoint($importButtonX, $buttonY)

    $selectOffset = $spacing + $selectButton.Width
    $selectButtonX = $importButtonX + [int]::Negate($selectOffset)
    $selectButton.Location = New-InstallerPoint($selectButtonX, $buttonY)

    $profileForm.Controls.Add($selectButton)
    $profileForm.Controls.Add($importButton)
    $profileForm.Controls.Add($cancelButton)

    $profileForm.AcceptButton = $selectButton
    $profileForm.CancelButton = $cancelButton

    $currentIndex = 0

    $updateDisplay = {
        param([int]$index)

        $info = $profiles[$index]
        $p = $info.Profile

        $profileName = if (-not [string]::IsNullOrWhiteSpace($info.Name)) { $info.Name } else { $info.FileName }
        $shortDescription = if (-not [string]::IsNullOrWhiteSpace($info.Description)) { $info.Description } else { "Profile with $($info.Applications.Count) application(s)." }
        $longDescription = if (-not [string]::IsNullOrWhiteSpace($info.LongDescription)) { $info.LongDescription } else { $shortDescription }
        $categories = @($info.Categories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $titleLabel.Text = "Profile {0} of {1}: {2}" -f ($index + 1), $profiles.Count, $profileName

        $categoryText = if ($categories.Count -gt 0) { [string]::Join(', ', $categories) } else { 'Uncategorized' }

        $metaLabel.Text = "{0}`nCategories: {1}`nSource: {2} (Created: {3})" -f `
            $longDescription,
            $categoryText,
            $info.FileName,
            $p.Timestamp

        # Load icon if available
        $iconPictureBox.Image = $null
        if ($info.IconPath -and -not [string]::IsNullOrWhiteSpace($info.IconPath)) {
            try {
                if ($info.IconPath -match '^(http|https)://') {
                    $client = New-Object System.Net.WebClient
                    $client.Headers.Add('User-Agent', 'myTech.Today-AppInstaller')
                    $imageData = $client.DownloadData($info.IconPath)
                    $stream = New-Object System.IO.MemoryStream(,$imageData)
                    $iconPictureBox.Image = [System.Drawing.Image]::FromStream($stream)
                }
                elseif (Test-Path $info.IconPath) {
                    $iconPictureBox.Image = [System.Drawing.Image]::FromFile($info.IconPath)
                }
            }
            catch {
                Write-Log "Failed to load icon for profile '$profileName' from '$($info.IconPath)': $($_.Exception.Message)" -Level WARNING
                $iconPictureBox.Image = $null
            }
        }

        $appsListView.BeginUpdate()
        $appsListView.Items.Clear()

        $appsWithCategories = @()
        foreach ($name in $info.Applications) {
            $app = $script:Applications | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($app) {
                $appsWithCategories += [PSCustomObject]@{
                    Name     = $app.Name
                    Category = if ($app.PSObject.Properties.Match('Category').Count -gt 0 -and $app.Category) { $app.Category } else { 'Uncategorized' }
                }
            }
            else {
                $appsWithCategories += [PSCustomObject]@{
                    Name     = $name
                    Category = 'Uncategorized'
                }
            }
        }

        foreach ($appInfo in ($appsWithCategories | Sort-Object Category, Name)) {
            $item = New-Object System.Windows.Forms.ListViewItem($appInfo.Category)
            $item.SubItems.Add($appInfo.Name) | Out-Null
            $appsListView.Items.Add($item) | Out-Null
        }

        $appsListView.EndUpdate()

        # Enable navigation buttons (disable only if there is a single profile)
        $prevButton.Enabled = ($profiles.Count -gt 1)
        $nextButton.Enabled = ($profiles.Count -gt 1)

        Write-Log "Profile browser displaying profile index $index ('$profileName')" -Level INFO
    }.GetNewClosure()

    $prevButton.Add_Click({
        if ($profiles.Count -le 1) { return }
        $currentIndex = $currentIndex + [int]::Negate(1)
        if ($currentIndex -lt 0) {
            $currentIndex = [int]($profiles.Count + [int]::Negate(1))
        }
        & $updateDisplay $currentIndex
    }.GetNewClosure())

    $nextButton.Add_Click({
        if ($profiles.Count -le 1) { return }
        $currentIndex++
        if ($currentIndex -ge $profiles.Count) {
            $currentIndex = 0
        }
        & $updateDisplay $currentIndex
    }.GetNewClosure())

    $profileForm.Tag = $null

    $selectButton.Add_Click({
        if ($profiles.Count -gt 0) {
            $info = $profiles[$currentIndex]
            $profileForm.Tag = $info.FilePath
            $profileForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
    }.GetNewClosure())

    $importButton.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $openDialog.Title = "Import Installation Profile"
        $openDialog.InitialDirectory = $script:ProfilesPath

        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $profileForm.Tag = $openDialog.FileName
            Write-Log "Profile file chosen via Import a Profile button: $($profileForm.Tag)" -Level INFO
            $profileForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
        else {
            Write-Log "Import a Profile file selection dialog was cancelled" -Level INFO
        }
    }.GetNewClosure())

    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    & $updateDisplay $currentIndex

    $result = $profileForm.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $profileForm.Tag) {
        Write-Log "Profile selected from Import Installation Profile dialog: $($profileForm.Tag)" -Level INFO
        return [string]$profileForm.Tag
    }
    else {
        Write-Log "Import Installation Profile dialog cancelled" -Level INFO
        return $null
    }
}


#endregion Profile Export/Import Functions


function Install-SelectedApplications {
    # Prevent execution during form closing
    if ($script:IsClosing) {
        Write-Log "Installation blocked: Form is closing" -Level WARNING
        return
    }

    # Prevent multiple simultaneous installations
    if ($script:IsInstalling) {
        Write-Log "Installation blocked: Installation already in progress" -Level WARNING
        [System.Windows.Forms.MessageBox]::Show(
            "An installation is already in progress. Please wait for it to complete.",
            "Installation In Progress",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    # Log that installation was explicitly triggered by user
    Write-Log "Install-SelectedApplications function called by user action" -Level INFO

    # Get checked items (including ones that may be ignored because they are already installed)
    $allCheckedItems = $script:ListView.Items | Where-Object { $_.Checked }

    if ($allCheckedItems.Count -eq 0) {
        Write-Log "Installation cancelled: No applications selected" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one application to install.",
            "No Selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Separate apps that are marked to be ignored (profile-selected but already installed)
    $ignoredItems = @()
    $checkedItems = @()

    foreach ($item in $allCheckedItems) {
        $app = $item.Tag
        $ignoreProfileInstall = $false
        if ($app -and $app.PSObject.Properties.Match('IgnoreProfileInstall').Count -gt 0 -and $app.IgnoreProfileInstall) {
            $ignoreProfileInstall = $true
        }

        if ($ignoreProfileInstall) {
            $ignoredItems += $item
        }
        else {
            $checkedItems += $item
        }
    }

    if ($checkedItems.Count -eq 0) {
        # Everything selected is already installed and flagged to be skipped
        Write-Log "Installation cancelled: All selected applications are already installed and marked to be skipped" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "All selected applications are already installed and will be skipped. There is nothing to install.",
            "Nothing to Install",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Log which applications were selected for installation (excluding ignored ones)
    Write-Log "User selected $($checkedItems.Count) application(s) for installation" -Level INFO
    foreach ($item in $checkedItems) {
        Write-Log "  - Selected: $($item.Text)" -Level INFO
    }

    if ($ignoredItems.Count -gt 0) {
        Write-Log "Additionally, $($ignoredItems.Count) selected application(s) are already installed and will be skipped" -Level INFO
    }

    # Check which apps are already installed among those that will be processed
    $alreadyInstalled = @()
    $notInstalled = @()

    foreach ($item in $checkedItems) {
        $app = $item.Tag
        if ($script:InstalledApps.ContainsKey($app.Name)) {
            $alreadyInstalled += $app
        }
        else {
            $notInstalled += $app
        }
    }

    # Build confirmation message
    # NOTE: Limit the number of applications listed to keep the confirmation dialog
    # from growing taller than the screen when many apps are selected.
    $maxAppsToListInConfirm = 20
    $confirmMessage = ""

    if ($notInstalled.Count -gt 0) {
        $confirmMessage += "New installations ($($notInstalled.Count)):`r`n"

        $appsToShow = $notInstalled | Select-Object -First $maxAppsToListInConfirm
        foreach ($app in $appsToShow) {
            $confirmMessage += "  - $($app.Name)`r`n"
        }

        if ($notInstalled.Count -gt $maxAppsToListInConfirm) {
            $remaining = $notInstalled.Count - $maxAppsToListInConfirm
            $confirmMessage += "  ... and $remaining more new application(s)`r`n"
        }

        $confirmMessage += "`r`n"
    }

    if ($alreadyInstalled.Count -gt 0) {
        $confirmMessage += "Already installed - will reinstall ($($alreadyInstalled.Count)):`r`n"

        $appsToShow = $alreadyInstalled | Select-Object -First $maxAppsToListInConfirm
        foreach ($app in $appsToShow) {
            $version = $script:InstalledApps[$app.Name]
            if ($app.Name -eq "O&O ShutUp10") {
                $confirmMessage += "  - $($app.Name) ($version) [Will re-run configuration]`r`n"
            }
            else {
                $confirmMessage += "  - $($app.Name) ($version)`r`n"
            }
        }

        if ($alreadyInstalled.Count -gt $maxAppsToListInConfirm) {
            $remaining = $alreadyInstalled.Count - $maxAppsToListInConfirm
            $confirmMessage += "  ... and $remaining more reinstall(s)`r`n"
        }

        $confirmMessage += "`r`n"
    }

    if ($ignoredItems.Count -gt 0) {
        $confirmMessage += "Note: $($ignoredItems.Count) selected application(s) are already installed, checked, and grayed out in the list. They will be skipped during installation.`r`n`r`n"
    }

    $confirmMessage += "Proceed with installation?"

    # Confirm installation - REQUIRED for all installations
    Write-Log "Displaying installation confirmation dialog to user" -Level INFO
    $result = [System.Windows.Forms.MessageBox]::Show(
        $confirmMessage,
        "Confirm Installation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "Installation cancelled by user (clicked No or closed dialog)" -Level INFO
        return
    }

    # User confirmed - log and set installation flag
    Write-Log "User confirmed installation - proceeding with $($checkedItems.Count) application(s)" -Level INFO

    # Log reinstallation information
    if ($alreadyInstalled.Count -gt 0) {
        Write-Log "User confirmed reinstallation of $($alreadyInstalled.Count) already-installed application(s)" -Level INFO
        foreach ($app in $alreadyInstalled) {
            if ($app.Name -eq "O&O ShutUp10") {
                Write-Log "O&O ShutUp10 will be re-run (always allowed)" -Level INFO
            }
            else {
                Write-Log "User chose to reinstall: $($app.Name)" -Level INFO
            }
        }
    }

    # Build installation queue from checked items (excluding ignored ones)
    $script:InstallationQueue = @($checkedItems | ForEach-Object { $_.Tag })

    # Reorder queue to install O&O ShutUp10 first if present
    $ooShutUpApp = $script:InstallationQueue | Where-Object { $_.Name -eq "O&O ShutUp10" }
    if ($ooShutUpApp) {
        Write-Log "O&O ShutUp10 detected - moving to front of installation queue" -Level INFO
        $otherApps = $script:InstallationQueue | Where-Object { $_.Name -ne "O&O ShutUp10" }
        $script:InstallationQueue = @($ooShutUpApp) + $otherApps
    }

    # Show queue management dialog
    Write-Log "Showing queue management dialog" -Level INFO
    $modifiedQueue = Show-QueueManagementDialog -Queue $script:InstallationQueue

    if ($null -eq $modifiedQueue) {
        Write-Log "Installation cancelled - user closed queue management dialog" -Level INFO
        return
    }

    # Update queue with user's modifications
    $script:InstallationQueue = $modifiedQueue
    Write-Log "Queue finalized with $($script:InstallationQueue.Count) application(s)" -Level INFO

    # Reset queue state
    $script:CurrentQueueIndex = 0
    $script:IsPaused = $false
    $script:SkipCurrent = $false

    # Save initial queue state
    Save-QueueState

    # Set installation flag
    $script:IsInstalling = $true

    # Disable buttons during installation (except pause/skip buttons)
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $false
        }
    }

    # Show and enable Pause/Resume and Skip buttons
    if ($script:PauseResumeButton) {
        $script:PauseResumeButton.Visible = $true
        $script:PauseResumeButton.Enabled = $true
    }
    if ($script:SkipButton) {
        $script:SkipButton.Visible = $true
        $script:SkipButton.Enabled = $true
    }

    # Setup progress bar
    $script:ProgressBar.Maximum = $script:InstallationQueue.Count
    $script:ProgressBar.Value = 0

    Write-Output "`r`n=== Starting Installation ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installing $($script:InstallationQueue.Count) application(s)..." -Color ([System.Drawing.Color]::Blue)
    Write-Output "[i] Queue: $($script:InstallationQueue.Name -join ', ')" -Color ([System.Drawing.Color]::Gray)

    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    $completedCount = 0
    $startTime = Get-Date  # Track installation start time
    $installationTimes = @()  # Track individual installation times for ETA

    # Track which apps succeeded, failed, or were skipped (for detailed logging)
    $successfulApps = @()
    $failedApps = @()
    $skippedApps = @()

    # Process queue
    while ($script:CurrentQueueIndex -lt $script:InstallationQueue.Count) {
        # Check if paused
        while ($script:IsPaused) {
            Write-Output "[PAUSE] Installation paused - waiting for resume..." -Color ([System.Drawing.Color]::Yellow)
            Save-QueueState
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 500
        }

        # Get current app from queue
        $app = $script:InstallationQueue[$script:CurrentQueueIndex]
        $currentIndex = $script:CurrentQueueIndex + 1

        # Calculate percentage
        $percentComplete = [Math]::Round(($currentIndex / $script:InstallationQueue.Count) * 100, 1)

        Write-Output "Installing $($app.Name) ($currentIndex of $($script:InstallationQueue.Count) - $percentComplete%)..." -Color ([System.Drawing.Color]::Blue)

        # Track individual app installation time
        $appStartTime = Get-Date

        # Reset skip flag
        $script:SkipCurrent = $false

        # Install application (unless skipped)
        if (-not $script:SkipCurrent) {
            $success = Install-Application -App $app
        }
        else {
            Write-Output "[SKIP] Skipping $($app.Name)" -Color ([System.Drawing.Color]::Yellow)
            $success = $false
        }

        # Calculate installation time
        $appEndTime = Get-Date
        $appDuration = ($appEndTime - $appStartTime).TotalSeconds
        $installationTimes += $appDuration

        # Update ListView item if it exists
        $listViewItem = $script:ListView.Items | Where-Object { $_.Tag.Name -eq $app.Name } | Select-Object -First 1
        if ($listViewItem) {
            if ($success) {
                $listViewItem.SubItems[2].Text = "Installed"
                $listViewItem.ForeColor = [System.Drawing.Color]::Green
            }
            elseif ($script:SkipCurrent) {
                $listViewItem.SubItems[2].Text = "Skipped"
                $listViewItem.ForeColor = [System.Drawing.Color]::Orange
            }
        }

        if ($script:SkipCurrent) {
            $skippedCount++
            $skippedApps += $app.Name
        }
        elseif ($success) {
            $successCount++
            $successfulApps += $app.Name
        }
        else {
            $failCount++
            $failedApps += $app.Name
        }

        # Update progress after installation completes
        $completedCount++
        $script:CurrentQueueIndex++
        $script:ProgressBar.Value = $completedCount
        $percentComplete = [Math]::Round(($completedCount / $script:InstallationQueue.Count) * 100, 1)

        # Calculate ETA
        $etaText = ""
        if ($installationTimes.Count -gt 0 -and $completedCount -lt $script:InstallationQueue.Count) {
            $avgTime = ($installationTimes | Measure-Object -Average).Average
            $remainingApps = $script:InstallationQueue.Count - $completedCount
            $etaSeconds = $avgTime * $remainingApps
            $etaMinutes = [Math]::Round($etaSeconds / 60, 1)
            $etaText = " | ETA: $etaMinutes min"
        }

        $script:ProgressLabel.Text = "$completedCount / $($script:InstallationQueue.Count) applications ($percentComplete%)$etaText"

        # Save queue state after each installation
        Save-QueueState

        # Process Windows messages to keep UI responsive
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Clear queue state (installation completed successfully)
    Clear-QueueState

    # Reset installation flag
    $script:IsInstalling = $false
    $script:IsPaused = $false
    Write-Log "Installation process completed - IsInstalling flag reset" -Level INFO

    # Hide Pause/Resume and Skip buttons
    if ($script:PauseResumeButton) {
        $script:PauseResumeButton.Visible = $false
    }
    if ($script:SkipButton) {
        $script:SkipButton.Visible = $false
    }

    # Re-enable buttons
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $true
        }
    }

    # Calculate total time
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    # Show completion message
    $completionColor = if ($failCount -eq 0 -and $skippedCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }

    Write-Output "`r`n=== Installation Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installation complete: $successCount succeeded, $failCount failed, $skippedCount skipped" -Color $completionColor
    Write-Output "Success: $successCount | Failed: $failCount | Skipped: $skippedCount | Time: $totalMinutes minutes" -Color $completionColor

    # Also show which applications succeeded, failed, or were skipped in the HTML console
    if ($successfulApps.Count -gt 0) {
        Write-Output ('Successful installs ({0}): {1}' -f $successfulApps.Count, ($successfulApps -join ', ')) -Color ([System.Drawing.Color]::Green)
    }
    if ($failedApps.Count -gt 0) {
        Write-Output ('Failed installs ({0}): {1}' -f $failedApps.Count, ($failedApps -join ', ')) -Color ([System.Drawing.Color]::Red)
    }
    if ($skippedApps.Count -gt 0) {
        Write-Output ('Skipped installs ({0}): {1}' -f $skippedApps.Count, ($skippedApps -join ', ')) -Color ([System.Drawing.Color]::Orange)
    }


    # Log installation summary (including failures) to the persistent log file
    $summaryLevel = if ($failCount -gt 0) { "ERROR" } elseif ($skippedCount -gt 0) { "WARNING" } else { "SUCCESS" }
    Write-Log ("Installation summary: {0} succeeded, {1} failed, {2} skipped out of {3} application(s). Total time: {4} minutes." -f `
        $successCount, $failCount, $skippedCount, $script:InstallationQueue.Count, $totalMinutes) -Level $summaryLevel

    if ($failedApps.Count -gt 0) {
        Write-Log ("Failed applications ({0}): {1}" -f $failedApps.Count, ($failedApps -join ', ')) -Level ERROR
    }
    if ($skippedApps.Count -gt 0) {
        Write-Log ("Skipped applications ({0}): {1}" -f $skippedApps.Count, ($skippedApps -join ', ')) -Level WARNING
    }
    if ($successfulApps.Count -gt 0) {
        Write-Log ("Successfully installed applications ({0}): {1}" -f $successfulApps.Count, ($successfulApps -join ', ')) -Level INFO
    }

    # Update status label
    if ($script:StatusLabel) {
        $statusText = "[COMPLETE] All installations complete! ($successCount succeeded, $failCount failed"
        if ($skippedCount -gt 0) {
            $statusText += ", $skippedCount skipped"
        }
        $statusText += ", $totalMinutes min)"
        $script:StatusLabel.Text = $statusText
        $script:StatusLabel.ForeColor = if ($failCount -eq 0 -and $skippedCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Show Windows Toast notification
    $toastTitle = "Installation Complete"
    $toastMessage = "Successfully installed $successCount of $($script:InstallationQueue.Count) applications in $totalMinutes minutes"
    if ($failCount -gt 0) {
        $toastMessage += "`n$failCount installation(s) failed"
    }
    if ($skippedCount -gt 0) {
        $toastMessage += "`n$skippedCount installation(s) skipped"
    }
    Show-ToastNotification -Title $toastTitle -Message $toastMessage -Type $(if ($failCount -eq 0 -and $skippedCount -eq 0) { 'Success' } else { 'Warning' })

    $completionMessage = "Installation complete!`n`nSuccessful: $successCount`nFailed: $failCount"
    if ($skippedCount -gt 0) {
        $completionMessage += "`nSkipped: $skippedCount"
    }
    $completionMessage += "`nTotal Time: $totalMinutes minutes"

    [System.Windows.Forms.MessageBox]::Show(
        $completionMessage,
        "Installation Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    # Refresh the list
    Refresh-ApplicationList
}

function Uninstall-SelectedApplications {
    <#
    .SYNOPSIS
        Uninstalls selected applications with confirmation and progress tracking.

    .DESCRIPTION
        Uninstalls multiple applications selected in the ListView.
        Shows confirmation dialog, tracks progress, and refreshes the application list.
    #>

    # Prevent execution during form closing
    if ($script:IsClosing) {
        Write-Log "Uninstall blocked: Form is closing" -Level WARNING
        return
    }

    # Prevent multiple simultaneous operations
    if ($script:IsInstalling) {
        Write-Log "Uninstall blocked: Installation/uninstall already in progress" -Level WARNING
        [System.Windows.Forms.MessageBox]::Show(
            "An installation or uninstall is already in progress. Please wait for it to complete.",
            "Operation In Progress",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    # Log that uninstall was explicitly triggered by user
    Write-Log "Uninstall-SelectedApplications function called by user action" -Level INFO

    # Get checked items
    $checkedItems = $script:ListView.Items | Where-Object { $_.Checked }

    if ($checkedItems.Count -eq 0) {
        Write-Log "Uninstall cancelled: No applications selected" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one application to uninstall.",
            "No Selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Log which applications were selected
    Write-Log "User selected $($checkedItems.Count) application(s) for uninstall" -Level INFO
    foreach ($item in $checkedItems) {
        Write-Log "  - Selected: $($item.Text)" -Level INFO
    }

    # Check which apps are actually installed
    $installedApps = @()
    $notInstalledApps = @()

    foreach ($item in $checkedItems) {
        $app = $item.Tag
        if ($script:InstalledApps.ContainsKey($app.Name)) {
            $installedApps += $app
        }
        else {
            $notInstalledApps += $app
        }
    }

    # If no apps are installed, show message and return
    if ($installedApps.Count -eq 0) {
        Write-Log "Uninstall cancelled: None of the selected applications are installed" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "None of the selected applications are currently installed.",
            "Nothing to Uninstall",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Build confirmation message
    $confirmMessage = "You are about to uninstall $($installedApps.Count) application(s):`r`n`r`n"

    foreach ($app in $installedApps) {
        $version = $script:InstalledApps[$app.Name]
        $confirmMessage += "  - $($app.Name) ($version)`r`n"
    }

    if ($notInstalledApps.Count -gt 0) {
        $confirmMessage += "`r`nNot installed - will skip ($($notInstalledApps.Count)):`r`n"
        foreach ($app in $notInstalledApps) {
            $confirmMessage += "  - $($app.Name)`r`n"
        }
    }

    if ($notInstalledApps.Count -gt 0) {
        Write-Log ('Selected applications not currently installed and will be skipped during uninstall ({0}): {1}' -f $notInstalledApps.Count, ($notInstalledApps.Name -join ', ')) -Level INFO
    }


    $confirmMessage += "`r`nThis action cannot be undone. Proceed with uninstall?"

    # Confirm uninstall - REQUIRED
    Write-Log "Displaying uninstall confirmation dialog to user" -Level INFO
    $result = [System.Windows.Forms.MessageBox]::Show(
        $confirmMessage,
        "Confirm Uninstall",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "Uninstall cancelled by user (clicked No or closed dialog)" -Level INFO
        return
    }

    # User confirmed - log and set installation flag
    Write-Log "User confirmed uninstall - proceeding with $($installedApps.Count) application(s)" -Level INFO

    # Set installation flag (reuse for uninstall to prevent concurrent operations)
    $script:IsInstalling = $true

    # Disable buttons during uninstall
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $false
        }
    }

    # Setup progress bar
    $script:ProgressBar.Maximum = $installedApps.Count
    $script:ProgressBar.Value = 0

    # Initialize progress label for uninstall operation
    if ($script:ProgressLabel) {
        $script:ProgressLabel.Text = "0 / $($installedApps.Count) applications (0%)"
    }

    Write-Output "`r`n=== Starting Uninstall ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Uninstalling $($installedApps.Count) application(s)..." -Color ([System.Drawing.Color]::Blue)
    Write-Output "[i] Apps: $($installedApps.Name -join ', ')" -Color ([System.Drawing.Color]::Gray)

    $successCount = 0
    $failCount = 0
    $startTime = Get-Date

    # Track which apps succeeded/failed for detailed logging and HTML output
    $successfulUninstalls = @()
    $failedUninstalls = @()


    # Process each app
    for ($i = 0; $i -lt $installedApps.Count; $i++) {
        $app = $installedApps[$i]
        $currentIndex = $i + 1

        # Calculate percentage
        $percentComplete = [Math]::Round(($currentIndex / $installedApps.Count) * 100, 1)

        Write-Output "Uninstalling $($app.Name) ($currentIndex of $($installedApps.Count) - $percentComplete%)..." -Color ([System.Drawing.Color]::Blue)

        # Uninstall the application
        $result = Uninstall-Application -App $app

        if ($result) {
            $successCount++
            $successfulUninstalls += $app.Name
        }
        else {
            $failCount++
            $failedUninstalls += $app.Name
        }

        # Update progress bar
        $script:ProgressBar.Value = $currentIndex

        # Update progress label to reflect uninstall progress
        if ($script:ProgressLabel) {
            $script:ProgressLabel.Text = "$currentIndex / $($installedApps.Count) applications ($percentComplete%)"
        }

        [System.Windows.Forms.Application]::DoEvents()
    }

    # Calculate total time
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    # Show completion message
    $completionColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }

    Write-Output "`r`n=== Uninstall Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Uninstall complete: $successCount succeeded, $failCount failed" -Color $completionColor
    Write-Output "Success: $successCount | Failed: $failCount | Time: $totalMinutes minutes" -Color $completionColor

    # Also show which applications were successfully uninstalled or failed in the HTML console
    if ($successfulUninstalls.Count -gt 0) {
        Write-Output ('Successfully uninstalled ({0}): {1}' -f $successfulUninstalls.Count, ($successfulUninstalls -join ', ')) -Color ([System.Drawing.Color]::Green)
    }
    if ($failedUninstalls.Count -gt 0) {
        Write-Output ('Failed to uninstall ({0}): {1}' -f $failedUninstalls.Count, ($failedUninstalls -join ', ')) -Color ([System.Drawing.Color]::Red)
    }

    # Log uninstall summary (including failures) to the persistent log file
    $uninstallSummaryLevel = if ($failCount -gt 0) { 'ERROR' } else { 'SUCCESS' }
    Write-Log ('Uninstall summary: {0} succeeded, {1} failed out of {2} application(s). Total time: {3} minutes.' -f `
        $successCount, $failCount, $installedApps.Count, $totalMinutes) -Level $uninstallSummaryLevel

    if ($failedUninstalls.Count -gt 0) {
        Write-Log ('Failed uninstalls ({0}): {1}' -f $failedUninstalls.Count, ($failedUninstalls -join ', ')) -Level ERROR
    }
    if ($successfulUninstalls.Count -gt 0) {
        Write-Log ('Successfully uninstalled applications ({0}): {1}' -f $successfulUninstalls.Count, ($successfulUninstalls -join ', ')) -Level INFO
    }


    # Update status label
    if ($script:StatusLabel) {
        $statusText = "[COMPLETE] All uninstalls complete! ($successCount succeeded, $failCount failed, $totalMinutes min)"
        $script:StatusLabel.Text = $statusText
        $script:StatusLabel.ForeColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Show Windows Toast notification
    $toastTitle = "Uninstall Complete"
    $toastMessage = "Successfully uninstalled $successCount of $($installedApps.Count) applications in $totalMinutes minutes"
    if ($failCount -gt 0) {
        $toastMessage += "`n$failCount uninstall(s) failed"
    }
    Show-ToastNotification -Title $toastTitle -Message $toastMessage -Type $(if ($failCount -eq 0) { 'Success' } else { 'Warning' })

    $completionMessage = "Uninstall complete!`n`nSuccessful: $successCount`nFailed: $failCount`nTotal Time: $totalMinutes minutes"

    [System.Windows.Forms.MessageBox]::Show(
        $completionMessage,
        "Uninstall Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    # Reset installation flag
    $script:IsInstalling = $false

    # Re-enable buttons
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $true
        }
    }

    # Hide pause/skip buttons
    if ($script:PauseResumeButton) {
        $script:PauseResumeButton.Visible = $false
    }
    if ($script:SkipButton) {
        $script:SkipButton.Visible = $false
    }

    # Refresh the list
    Refresh-ApplicationList
}

#endregion Event Handlers

#region Marketing Display

function Show-MarketingInformation {
    <#
    .SYNOPSIS
        Displays application info, marketing, and contact information in the HTML output panel.

    .DESCRIPTION
        Shows application count, status, myTech.Today company information, services,
        and contact details in the GUI HTML output panel with professional formatting.
    #>
    [CmdletBinding()]
    param()

    if ($script:WebBrowser -and $script:WebBrowser.Document) {
        # Calculate installed app count
        $totalApps = $script:Applications.Count
        $installedCount = 0
        if ($script:ListView -and $script:ListView.Items.Count -gt 0) {
            $installedCount = ($script:ListView.Items | Where-Object { $_.SubItems[2].Text -eq "Installed" }).Count
        }

        $marketingHtml = @"
<div class="box" style="border-color: #569cd6;">
    <h1 style="color: #569cd6; border-bottom-color: #569cd6;">myTech.Today Application Installer v$script:ScriptVersion</h1>

    <div style="background-color: #2d2d30; padding: 10px; margin: 10px 0; border-left: 3px solid #4ec9b0;">
        <p class="success" style="margin: 5px 0; font-size: 23px;">
            <strong>[APPS] Total Applications Available:</strong> $totalApps
        </p>
        <p class="info" style="margin: 5px 0; font-size: 23px;">
            <strong>[OK] Currently Installed:</strong> $installedCount
        </p>
        <p class="warning" style="margin: 5px 0; font-size: 23px;">
            <strong>📥 Available to Install:</strong> $($totalApps - $installedCount)
        </p>
    </div>
</div>

<div class="box">
    <h1>Thank you for using myTech.Today App Installer!</h1>

    <h2 class="warning">Need IT Support? We are Here to Help!</h2>

    <p>
        <strong>myTech.Today</strong> is a full-service Managed Service Provider (MSP)
        based in Barrington, IL, proudly serving businesses and individuals throughout
        <strong>Chicagoland, IL</strong>, <strong>Southern Wisconsin</strong>,
        <strong>Northern Indiana</strong>, and <strong>Southern Michigan</strong>.
    </p>

    <h2 class="success">We specialize in:</h2>
    <ul>
        <li>IT Consulting and Support</li>
        <li>Network Design and Management</li>
        <li>Cybersecurity and Compliance</li>
        <li>Cloud Integration (Azure, AWS, Microsoft 365)</li>
        <li>System Administration and Security</li>
        <li>Database Management and Custom Development</li>
    </ul>

    <div class="contact">
        <h2 class="warning">Contact Us:</h2>
        <p>
            <strong>Email:</strong> <a href="mailto:sales@mytech.today" style="color: #4fc1ff;">sales@mytech.today</a><br>
            <strong>Phone:</strong> (847) 767-4914<br>
            <strong>Web:</strong> <a href="https://mytech.today" style="color: #4fc1ff;">https://mytech.today</a>
        </p>
    </div>

    <p class="success" style="text-align: center; margin-top: 15px; font-size: 22px;">
        <strong>Serving the Midwest with 20+ years of IT expertise!</strong>
    </p>
</div>
"@

        try {
            $contentDiv = $script:WebBrowser.Document.GetElementById("content")
            if ($contentDiv) {
                $contentDiv.InnerHtml += $marketingHtml
            }
        }
        catch {
            Write-Log "Failed to display marketing information: $_" -Level ERROR
        }
    }

    Write-Log "Marketing information displayed" -Level INFO
}

#endregion Marketing Display

#region Main Execution

try {
    # Initialize logging
    Write-Host "`n[i] Initializing logging..." -ForegroundColor Cyan

    if ($script:LoggingModuleLoaded) {
        # Use generic logging module
        $logPath = Initialize-Log -ScriptName "AppInstaller-GUI" -ScriptVersion $script:ScriptVersion
        if ($logPath) {
            Write-Log "=== myTech.Today Application Installer GUI v$script:ScriptVersion ===" -Level INFO
            Write-Log "Log initialized at: $logPath" -Level INFO
            Write-Host "[OK] Logging initialized with generic module" -ForegroundColor Green
        }
        else {
            Write-Host "[WARN] Generic logging module failed to initialize" -ForegroundColor Yellow
        }
    }
    else {
        # Fallback to old logging method
        Initialize-Logging
        Write-Host "[OK] Logging initialized with fallback method" -ForegroundColor Green
    }

    Write-Host "`n[i] Creating GUI form..." -ForegroundColor Cyan

    # Create the form (this creates the WebBrowser control)
    $form = Create-MainForm
    Write-Host "[OK] Main form created" -ForegroundColor Green

    Write-Host "[i] Creating buttons..." -ForegroundColor Cyan
    Create-Buttons -form $form
    Write-Host "[OK] Buttons created" -ForegroundColor Green

    # Wait for WebBrowser to finish loading before writing output
    Start-Sleep -Milliseconds 500

    # Now we can use Write-Output since WebBrowser exists
    Write-Output "=== myTech.Today Application Installer GUI v$script:ScriptVersion ===" -Color ([System.Drawing.Color]::Blue)
    Write-Output "Initializing..." -Color ([System.Drawing.Color]::Gray)

    # Ensure winget is available (install on Windows 10 if needed)
    Write-Host "`n[i] Checking for winget availability..." -ForegroundColor Cyan
    Ensure-WingetAvailable | Out-Null
    Write-Host "[OK] winget check complete" -ForegroundColor Green

    # Initial load - detect installed applications
    Write-Host "`n[i] Detecting installed applications..." -ForegroundColor Cyan
    Refresh-ApplicationList
    Write-Host "[OK] Application detection complete" -ForegroundColor Green

    # Display additional marketing information with dynamic stats
    Show-MarketingInformation

    Write-Host "`n[OK] GUI initialized successfully!" -ForegroundColor Green
    Write-Host "[i] Showing GUI window..." -ForegroundColor Cyan

    # Bring the form to the foreground and give it focus
    Write-Host "[i] Bringing window to foreground..." -ForegroundColor Yellow
    $form.TopMost = $true
    $form.Add_Shown({
        $this.Activate()
        $this.BringToFront()
        $this.TopMost = $false
    })

    # Add FormClosing event handler for cleanup
    $form.Add_FormClosing({
        param($formSender, $formEvent)

        Write-Host "`n[i] Form closing initiated..." -ForegroundColor Cyan

        # Set closing flag FIRST to prevent any event handlers from executing
        $script:IsClosing = $true
        Write-Log "Form closing - IsClosing flag set to prevent event handlers" -Level INFO

        # Check if installation is in progress
        if ($script:IsInstalling) {
            Write-Host "[WARN] Installation in progress - asking user to confirm close" -ForegroundColor Yellow
            Write-Log "User attempted to close form during installation" -Level WARNING

            $confirmClose = [System.Windows.Forms.MessageBox]::Show(
                "An installation is currently in progress. Are you sure you want to close?`n`nThis may interrupt the installation process.",
                "Installation In Progress",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )

            if ($confirmClose -ne [System.Windows.Forms.DialogResult]::Yes) {
                Write-Log "User cancelled form close - installation will continue" -Level INFO
                $script:IsClosing = $false
                $formEvent.Cancel = $true
                return
            }
            else {
                Write-Log "User confirmed form close during installation" -Level WARNING
            }
        }

        Write-Host "[i] Cleaning up resources..." -ForegroundColor Cyan

        try {
            # Dispose of WebBrowser control
            if ($script:WebBrowser) {
                $script:WebBrowser.Dispose()
                $script:WebBrowser = $null
            }

            # Dispose of ListView
            if ($script:ListView) {
                $script:ListView.Dispose()
                $script:ListView = $null
            }

            # Dispose of progress controls
            if ($script:ProgressBar) {
                $script:ProgressBar.Dispose()
                $script:ProgressBar = $null
            }

            if ($script:ProgressLabel) {
                $script:ProgressLabel.Dispose()
                $script:ProgressLabel = $null
            }

            if ($script:StatusLabel) {
                $script:StatusLabel.Dispose()
                $script:StatusLabel = $null
            }

            if ($script:AppProgressBar) {
                $script:AppProgressBar.Dispose()
                $script:AppProgressBar = $null
            }

            # Clear large script-level variables to free memory
            $script:SelectedApps = @()
            $script:InstalledApps = @{}
            $script:HtmlContent = $null
            $script:Applications = @()

            Write-Host "[OK] Resources cleaned up" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Error during cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    })

    # Show the form (this blocks until the form is closed)
    Write-Host "[i] Calling ShowDialog()..." -ForegroundColor Yellow
    $result = $form.ShowDialog()
    Write-Host "[i] ShowDialog() returned: $result" -ForegroundColor Yellow

    # Cleanup
    Write-Log "Application installer GUI closed" -Level INFO
    Write-Host "`n[i] Application installer GUI closed." -ForegroundColor Cyan
}
catch {
    Write-Host "`n[ERROR] GUI initialization failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Log "GUI initialization failed: $($_.Exception.Message)" -Level ERROR

    # Show error dialog
    [System.Windows.Forms.MessageBox]::Show(
        "Failed to initialize GUI:`n`n$($_.Exception.Message)`n`nCheck the log file for details.",
        "GUI Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )

    Read-Host "`nPress Enter to exit"
}
finally {
    # Final cleanup - dispose of form
    if ($form) {
        Write-Host "[i] Disposing form..." -ForegroundColor Cyan
        $form.Dispose()
        $form = $null
        Write-Host "[OK] Form disposed" -ForegroundColor Green
    }

    # Force garbage collection to free memory
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

#endregion Main Execution


