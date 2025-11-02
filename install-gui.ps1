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
    - Support for 65+ applications via winget and custom installers

.NOTES
    File Name      : install-gui.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Version        : 1.3.7

.LINK
    https://github.com/mytech-today-now/PowerShellScripts
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# Script variables
$script:ScriptVersion = '1.3.7'
$script:OriginalScriptPath = $PSScriptRoot
$script:SystemInstallPath = "$env:SystemDrive\mytech.today\app_installer"
$script:ScriptPath = $script:SystemInstallPath
$script:CentralLogPath = "C:\mytech.today\logs\"
$script:LogPath = $null
$script:AppsPath = Join-Path $script:ScriptPath "apps"
$script:InstalledApps = @{}
$script:SelectedApps = @()

# Application registry - defines all supported applications
# Using PSCustomObject for proper property access with Group-Object
$script:Applications = @(
    # Browsers
    [PSCustomObject]@{ Name = "Google Chrome"; ScriptName = "chrome.ps1"; WingetId = "Google.Chrome"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Brave Browser"; ScriptName = "brave.ps1"; WingetId = "Brave.Brave"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Firefox"; ScriptName = "firefox.ps1"; WingetId = "Mozilla.Firefox"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Vivaldi"; ScriptName = "vivaldi.ps1"; WingetId = "Vivaldi.Vivaldi"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Opera"; ScriptName = "opera.ps1"; WingetId = "Opera.Opera"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "LibreWolf"; ScriptName = "librewolf.ps1"; WingetId = "LibreWolf.LibreWolf"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Tor Browser"; ScriptName = "torbrowser.ps1"; WingetId = "TorProject.TorBrowser"; Category = "Browsers" }
    [PSCustomObject]@{ Name = "Waterfox"; ScriptName = "waterfox.ps1"; WingetId = "Waterfox.Waterfox"; Category = "Browsers" }
    # Development Tools
    [PSCustomObject]@{ Name = "Notepad++"; ScriptName = "notepadplusplus.ps1"; WingetId = "Notepad++.Notepad++"; Category = "Development" }
    [PSCustomObject]@{ Name = "Git"; ScriptName = "git.ps1"; WingetId = "Git.Git"; Category = "Development" }
    [PSCustomObject]@{ Name = "Python"; ScriptName = "python.ps1"; WingetId = "Python.Python.3.12"; Category = "Development" }
    [PSCustomObject]@{ Name = "Node.js"; ScriptName = "nodejs.ps1"; WingetId = "OpenJS.NodeJS.LTS"; Category = "Development" }
    [PSCustomObject]@{ Name = "Docker Desktop"; ScriptName = "docker.ps1"; WingetId = "Docker.DockerDesktop"; Category = "Development" }
    [PSCustomObject]@{ Name = "Sublime Text"; ScriptName = "sublimetext.ps1"; WingetId = "SublimeHQ.SublimeText.4"; Category = "Development" }
    [PSCustomObject]@{ Name = "Geany"; ScriptName = "geany.ps1"; WingetId = "Geany.Geany"; Category = "Development" }
    [PSCustomObject]@{ Name = "NetBeans IDE"; ScriptName = "netbeans.ps1"; WingetId = "Apache.NetBeans"; Category = "Development" }
    [PSCustomObject]@{ Name = "IntelliJ IDEA Community"; ScriptName = "intellij.ps1"; WingetId = "JetBrains.IntelliJIDEA.Community"; Category = "Development" }
    [PSCustomObject]@{ Name = "WinSCP"; ScriptName = "winscp.ps1"; WingetId = "WinSCP.WinSCP"; Category = "Development" }
    # Productivity
    [PSCustomObject]@{ Name = "LibreOffice"; ScriptName = "libreoffice.ps1"; WingetId = "TheDocumentFoundation.LibreOffice"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Obsidian"; ScriptName = "obsidian.ps1"; WingetId = "Obsidian.Obsidian"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Joplin"; ScriptName = "joplin.ps1"; WingetId = "Joplin.Joplin"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Foxit PDF Reader"; ScriptName = "foxitreader.ps1"; WingetId = "Foxit.FoxitReader"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Sumatra PDF"; ScriptName = "sumatrapdf.ps1"; WingetId = "SumatraPDF.SumatraPDF"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Notion"; ScriptName = "notion.ps1"; WingetId = "Notion.Notion"; Category = "Productivity" }
    # Media & Creative
    [PSCustomObject]@{ Name = "OBS Studio"; ScriptName = "obs.ps1"; WingetId = "OBSProject.OBSStudio"; Category = "Media" }
    [PSCustomObject]@{ Name = "GIMP"; ScriptName = "gimp.ps1"; WingetId = "GIMP.GIMP"; Category = "Media" }
    [PSCustomObject]@{ Name = "Audacity"; ScriptName = "audacity.ps1"; WingetId = "Audacity.Audacity"; Category = "Media" }
    [PSCustomObject]@{ Name = "Handbrake"; ScriptName = "handbrake.ps1"; WingetId = "HandBrake.HandBrake"; Category = "Media" }
    [PSCustomObject]@{ Name = "OpenShot"; ScriptName = "openshot.ps1"; WingetId = "OpenShot.OpenShot"; Category = "Media" }
    [PSCustomObject]@{ Name = "ClipGrab"; ScriptName = "clipgrab.ps1"; WingetId = "Philipp Schmieder.ClipGrab"; Category = "Media" }
    [PSCustomObject]@{ Name = "Inkscape"; ScriptName = "inkscape.ps1"; WingetId = "Inkscape.Inkscape"; Category = "Media" }
    [PSCustomObject]@{ Name = "Paint.NET"; ScriptName = "paintdotnet.ps1"; WingetId = "dotPDN.PaintDotNet"; Category = "Media" }
    [PSCustomObject]@{ Name = "Avidemux"; ScriptName = "avidemux.ps1"; WingetId = "Avidemux.Avidemux"; Category = "Media" }
    [PSCustomObject]@{ Name = "MPC-HC"; ScriptName = "mpchc.ps1"; WingetId = "clsid2.mpc-hc"; Category = "Media" }
    [PSCustomObject]@{ Name = "Foobar2000"; ScriptName = "foobar2000.ps1"; WingetId = "PeterPawlowski.foobar2000"; Category = "Media" }
    # Utilities
    [PSCustomObject]@{ Name = "AngryIP Scanner"; ScriptName = "angryip.ps1"; WingetId = "angryziber.AngryIPScanner"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "CCleaner"; ScriptName = "ccleaner.ps1"; WingetId = "Piriform.CCleaner"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Bitvise SSH Client"; ScriptName = "bitvise.ps1"; WingetId = "Bitvise.SSH.Client"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Belarc Advisor"; ScriptName = "belarc.ps1"; WingetId = $null; Category = "Utilities" }
    [PSCustomObject]@{ Name = "O&O ShutUp10"; ScriptName = "shutup10.ps1"; WingetId = $null; Category = "Utilities" }
    [PSCustomObject]@{ Name = "FileMail Desktop"; ScriptName = "filemail.ps1"; WingetId = $null; Category = "Utilities" }
    [PSCustomObject]@{ Name = "PowerToys"; ScriptName = "powertoys.ps1"; WingetId = "Microsoft.PowerToys"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Everything"; ScriptName = "everything.ps1"; WingetId = "voidtools.Everything"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Greenshot"; ScriptName = "greenshot.ps1"; WingetId = "Greenshot.Greenshot"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Bulk Rename Utility"; ScriptName = "bulkrename.ps1"; WingetId = "TGRMNSoftware.BulkRenameUtility"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Revo Uninstaller"; ScriptName = "revouninstaller.ps1"; WingetId = "RevoUninstaller.RevoUninstaller"; Category = "Utilities" }
    # Security
    [PSCustomObject]@{ Name = "Avira Antivirus"; ScriptName = "avira.ps1"; WingetId = "Avira.Avira"; Category = "Security" }
    [PSCustomObject]@{ Name = "Kaspersky Security Cloud"; ScriptName = "kaspersky.ps1"; WingetId = "Kaspersky.KasperskySecurityCloud"; Category = "Security" }
    [PSCustomObject]@{ Name = "AVG AntiVirus Free"; ScriptName = "avg.ps1"; WingetId = "AVG.AVG"; Category = "Security" }
    [PSCustomObject]@{ Name = "Avast Free Antivirus"; ScriptName = "avast.ps1"; WingetId = "Avast.Avast.Free"; Category = "Security" }
    [PSCustomObject]@{ Name = "Malwarebytes"; ScriptName = "malwarebytes.ps1"; WingetId = "Malwarebytes.Malwarebytes"; Category = "Security" }
    [PSCustomObject]@{ Name = "Bitwarden"; ScriptName = "bitwarden.ps1"; WingetId = "Bitwarden.Bitwarden"; Category = "Security" }
    [PSCustomObject]@{ Name = "Grok AI Shortcuts"; ScriptName = "grok-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts" }
    [PSCustomObject]@{ Name = "ChatGPT Shortcuts"; ScriptName = "chatgpt-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts" }
    [PSCustomObject]@{ Name = "dictation.io Shortcut"; ScriptName = "dictation-shortcut.ps1"; WingetId = $null; Category = "Shortcuts" }
    [PSCustomObject]@{ Name = "Uninstall McAfee"; ScriptName = "uninstall-mcafee.ps1"; WingetId = $null; Category = "Maintenance" }
    # Development Tools
    [PSCustomObject]@{ Name = "Visual Studio Code"; ScriptName = "vscode.ps1"; WingetId = "Microsoft.VisualStudioCode"; Category = "Development" }
    [PSCustomObject]@{ Name = "Postman"; ScriptName = "postman.ps1"; WingetId = "Postman.Postman"; Category = "Development" }
    [PSCustomObject]@{ Name = "PyCharm Community"; ScriptName = "pycharm.ps1"; WingetId = "JetBrains.PyCharm.Community"; Category = "Development" }
    [PSCustomObject]@{ Name = "Eclipse IDE"; ScriptName = "eclipse.ps1"; WingetId = "EclipseAdoptium.Temurin.17.JRE"; Category = "Development" }
    [PSCustomObject]@{ Name = "Atom Editor"; ScriptName = "atom.ps1"; WingetId = "GitHub.Atom"; Category = "Development" }
    [PSCustomObject]@{ Name = "Brackets"; ScriptName = "brackets.ps1"; WingetId = "Adobe.Brackets"; Category = "Development" }
    [PSCustomObject]@{ Name = "Vagrant"; ScriptName = "vagrant.ps1"; WingetId = "Hashicorp.Vagrant"; Category = "Development" }
    # Communication
    [PSCustomObject]@{ Name = "Telegram Desktop"; ScriptName = "telegram.ps1"; WingetId = "Telegram.TelegramDesktop"; Category = "Communication" }
    [PSCustomObject]@{ Name = "Signal"; ScriptName = "signal.ps1"; WingetId = "OpenWhisperSystems.Signal"; Category = "Communication" }
    [PSCustomObject]@{ Name = "Thunderbird"; ScriptName = "thunderbird.ps1"; WingetId = "Mozilla.Thunderbird"; Category = "Communication" }
    # Media & Graphics
    [PSCustomObject]@{ Name = "VLC Media Player"; ScriptName = "vlc.ps1"; WingetId = "VideoLAN.VLC"; Category = "Media" }
    [PSCustomObject]@{ Name = "FFmpeg"; ScriptName = "ffmpeg.ps1"; WingetId = "Gyan.FFmpeg"; Category = "Media" }
    [PSCustomObject]@{ Name = "Krita"; ScriptName = "krita.ps1"; WingetId = "KDE.Krita"; Category = "Media" }
    [PSCustomObject]@{ Name = "OpenToonz"; ScriptName = "opentoonz.ps1"; WingetId = "OpenToonz.OpenToonz"; Category = "Media" }
    [PSCustomObject]@{ Name = "Kdenlive"; ScriptName = "kdenlive.ps1"; WingetId = "KDE.Kdenlive"; Category = "Media" }
    [PSCustomObject]@{ Name = "Shotcut"; ScriptName = "shotcut.ps1"; WingetId = "Meltytech.Shotcut"; Category = "Media" }
    [PSCustomObject]@{ Name = "darktable"; ScriptName = "darktable.ps1"; WingetId = "darktable.darktable"; Category = "Media" }
    [PSCustomObject]@{ Name = "RawTherapee"; ScriptName = "rawtherapee.ps1"; WingetId = "RawTherapee.RawTherapee"; Category = "Media" }
    # Productivity
    [PSCustomObject]@{ Name = "7-Zip"; ScriptName = "7zip.ps1"; WingetId = "7zip.7zip"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Adobe Acrobat Reader"; ScriptName = "adobereader.ps1"; WingetId = "Adobe.Acrobat.Reader.64-bit"; Category = "Productivity" }
    [PSCustomObject]@{ Name = "Apache OpenOffice"; ScriptName = "openoffice.ps1"; WingetId = "Apache.OpenOffice"; Category = "Productivity" }
    # 3D & CAD
    [PSCustomObject]@{ Name = "Blender"; ScriptName = "blender.ps1"; WingetId = "BlenderFoundation.Blender"; Category = "3D & CAD" }
    [PSCustomObject]@{ Name = "FreeCAD"; ScriptName = "freecad.ps1"; WingetId = "FreeCAD.FreeCAD"; Category = "3D & CAD" }
    [PSCustomObject]@{ Name = "LibreCAD"; ScriptName = "librecad.ps1"; WingetId = "LibreCAD.LibreCAD"; Category = "3D & CAD" }
    [PSCustomObject]@{ Name = "KiCad"; ScriptName = "kicad.ps1"; WingetId = "KiCad.KiCad"; Category = "3D & CAD" }
    # Networking & Security
    [PSCustomObject]@{ Name = "Nmap"; ScriptName = "nmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking" }
    [PSCustomObject]@{ Name = "Wireshark"; ScriptName = "wireshark.ps1"; WingetId = "WiresharkFoundation.Wireshark"; Category = "Networking" }
    [PSCustomObject]@{ Name = "Zenmap"; ScriptName = "zenmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking" }
    # System Utilities
    [PSCustomObject]@{ Name = "WinDirStat"; ScriptName = "windirstat.ps1"; WingetId = "WinDirStat.WinDirStat"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Core Temp"; ScriptName = "coretemp.ps1"; WingetId = "ALCPU.CoreTemp"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "GPU-Z"; ScriptName = "gpuz.ps1"; WingetId = "TechPowerUp.GPU-Z"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "CrystalDiskInfo"; ScriptName = "crystaldiskinfo.ps1"; WingetId = "CrystalDewWorld.CrystalDiskInfo"; Category = "Utilities" }
    [PSCustomObject]@{ Name = "Sysinternals Suite"; ScriptName = "sysinternals.ps1"; WingetId = "Microsoft.Sysinternals.Suite"; Category = "Utilities" }
    # Runtime Environments
    [PSCustomObject]@{ Name = "Java Runtime Environment"; ScriptName = "java.ps1"; WingetId = "Oracle.JavaRuntimeEnvironment"; Category = "Runtime" }
    # Writing & Screenwriting
    [PSCustomObject]@{ Name = "Trelby"; ScriptName = "trelby.ps1"; WingetId = $null; Category = "Writing" }
    [PSCustomObject]@{ Name = "KIT Scenarist"; ScriptName = "kitscenarist.ps1"; WingetId = $null; Category = "Writing" }
    [PSCustomObject]@{ Name = "Storyboarder"; ScriptName = "storyboarder.ps1"; WingetId = "Wonderunit.Storyboarder"; Category = "Writing" }
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
        $sourcePath = $script:OriginalScriptPath
        $sourceAppsPath = Join-Path $sourcePath "apps"

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
        # Convert color to hex
        $hexColor = "#{0:X2}{1:X2}{2:X2}" -f $Color.R, $Color.G, $Color.B

        # Escape HTML special characters
        $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($Message)

        # Replace newlines with <br> tags
        $escapedMessage = $escapedMessage -replace "`r`n", "<br>" -replace "`n", "<br>"

        # Append to HTML content
        $htmlLine = "<div style='color: $hexColor; margin: 2px 0;'>$escapedMessage</div>"

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
    }
    catch {
        Write-Log "Error detecting installed applications: $($_.Exception.Message)" -Level WARNING
    }

    Write-Log "Found $($installedApps.Count) installed applications" -Level INFO
    Write-Output "Found $($installedApps.Count) installed applications" -Color ([System.Drawing.Color]::Green)

    return $installedApps
}

#endregion Helper Functions

#region Installation Functions

function Install-Application {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$App
    )

    Write-Log "Installing $($App.Name)..." -Level INFO
    Write-Output "`r`nInstalling $($App.Name)..." -Color ([System.Drawing.Color]::Blue)

    try {
        # Check if custom script exists
        $scriptPath = Join-Path $script:AppsPath $App.ScriptName

        if (Test-Path $scriptPath) {
            Write-Log "Using custom script: $scriptPath" -Level INFO
            Write-Output "  Using custom script..." -Color ([System.Drawing.Color]::Gray)
            & $scriptPath
        }
        elseif ($App.WingetId) {
            # Use winget for installation
            if (Test-WingetAvailable) {
                Write-Log "Installing via winget: $($App.WingetId)" -Level INFO
                Write-Output "  Installing via winget..." -Color ([System.Drawing.Color]::Gray)

                $result = winget install --id $App.WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "$($App.Name) installed successfully" -Level SUCCESS
                    Write-Output "  [OK] $($App.Name) installed successfully!" -Color ([System.Drawing.Color]::Green)
                    return $true
                }
                else {
                    Write-Log "$($App.Name) installation failed with exit code: $LASTEXITCODE" -Level ERROR
                    Write-Output "  [X] Installation failed with exit code: $LASTEXITCODE" -Color ([System.Drawing.Color]::Red)
                    Write-Output "      $result" -Color ([System.Drawing.Color]::Red)
                    return $false
                }
            }
            else {
                Write-Log "Winget not available, cannot install $($App.Name)" -Level ERROR
                Write-Output "  [X] Winget not available" -Color ([System.Drawing.Color]::Red)
                return $false
            }
        }
        else {
            Write-Log "No installation method available for $($App.Name)" -Level WARNING
            Write-Output "  [!] No installation method available" -Color ([System.Drawing.Color]::Orange)
            return $false
        }
    }
    catch {
        Write-Log "Error installing $($App.Name): $($_.Exception.Message)" -Level ERROR
        Write-Output "  [X] Error: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red)
        return $false
    }
}

#endregion Installation Functions

#region GUI Creation

function Get-OptimalFormSize {
    <#
    .SYNOPSIS
        Calculates optimal form size and font sizes based on screen resolution.

    .DESCRIPTION
        Detects screen resolution and calculates form size as percentage of screen.
        Supports HD, FHD, QHD, 4K UHD, UWQHD, and UW4K displays.
        Calculates appropriate font sizes based on resolution and DPI.
    #>
    [CmdletBinding()]
    param()

    # Get primary screen dimensions
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $screenWidth = $screen.WorkingArea.Width
    $screenHeight = $screen.WorkingArea.Height

    Write-Log "Detected screen resolution: ${screenWidth}x${screenHeight}" -Level INFO

    # Calculate form size as percentage of screen (70% width, 80% height)
    $formWidth = [Math]::Min([Math]::Floor($screenWidth * 0.70), 2400)  # Max 2400px
    $formHeight = [Math]::Min([Math]::Floor($screenHeight * 0.80), 1400)  # Max 1400px

    # Ensure minimum size
    $formWidth = [Math]::Max($formWidth, 1000)
    $formHeight = [Math]::Max($formHeight, 600)

    # Calculate DPI scaling factor
    $graphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $dpiX = $graphics.DpiX
    $graphics.Dispose()
    $dpiScale = $dpiX / 96.0  # 96 DPI is standard

    # Calculate resolution-based font scaling
    # Base font sizes for different resolutions:
    # HD (1280x720): 1.0x
    # FHD (1920x1080): 1.0x
    # QHD (2560x1440): 1.3x
    # 4K UHD (3840x2160): 1.8x
    # UWQHD (3440x1440): 1.3x
    # UW4K (5120x2160): 1.8x

    $resolutionScale = 1.0

    if ($screenWidth -ge 5000) {
        # UW4K or 5K+
        $resolutionScale = 1.8
        $resolutionName = "UW4K/5K+"
    }
    elseif ($screenWidth -ge 3800) {
        # 4K UHD
        $resolutionScale = 1.8
        $resolutionName = "4K UHD"
    }
    elseif ($screenWidth -ge 3400) {
        # UWQHD
        $resolutionScale = 1.3
        $resolutionName = "UWQHD"
    }
    elseif ($screenWidth -ge 2500) {
        # QHD
        $resolutionScale = 1.3
        $resolutionName = "QHD"
    }
    elseif ($screenWidth -ge 1900) {
        # FHD
        $resolutionScale = 1.0
        $resolutionName = "FHD"
    }
    else {
        # HD or lower
        $resolutionScale = 1.0
        $resolutionName = "HD"
    }

    # Combine DPI scale and resolution scale
    $combinedScale = $dpiScale * $resolutionScale

    Write-Log "Resolution: $resolutionName, DPI scale: $dpiScale, Resolution scale: $resolutionScale, Combined: $combinedScale" -Level INFO

    return @{
        Width = $formWidth
        Height = $formHeight
        DpiScale = $dpiScale
        ResolutionScale = $resolutionScale
        CombinedScale = $combinedScale
        ScreenWidth = $screenWidth
        ScreenHeight = $screenHeight
        ResolutionName = $resolutionName
    }
}

function Create-MainForm {
    # Get optimal form size based on screen resolution
    $sizeInfo = Get-OptimalFormSize
    $formWidth = $sizeInfo.Width
    $formHeight = $sizeInfo.Height
    $dpiScale = $sizeInfo.DpiScale
    $combinedScale = $sizeInfo.CombinedScale
    $resolutionName = $sizeInfo.ResolutionName

    # Calculate responsive margins and spacing
    # Removed header area completely - info moved to right panel
    $margin = 20
    $headerHeight = $margin    # No header, just top margin
    $buttonAreaHeight = 150    # Increased from 110 to 150 to accommodate much taller buttons (75px) with 3x padding
    $progressAreaHeight = 50   # Increased from 35 to 50 for more space for progress label

    # Create main form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "myTech.Today Application Installer v$script:ScriptVersion"
    $form.ClientSize = New-Object System.Drawing.Size($formWidth, $formHeight)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 600)
    $form.MaximizeBox = $true
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    # Calculate font sizes based on combined DPI and resolution scaling
    # Base sizes: Title=14pt, Normal=10pt, Console=9pt
    # Cap maximum sizes to prevent oversized text on high-res displays
    $titleFontSize = [Math]::Min([Math]::Max([Math]::Round(14 * $combinedScale), 14), 20)
    $normalFontSize = [Math]::Min([Math]::Max([Math]::Round(10 * $combinedScale), 10), 13)
    $consoleFontSize = [Math]::Min([Math]::Max([Math]::Round(9 * $combinedScale), 9), 11)

    Write-Log "Font sizes - Title: $titleFontSize, Normal: $normalFontSize, Console: $consoleFontSize" -Level INFO

    # Header labels removed - information moved to right panel HTML display
    # This provides more space for the application list and eliminates text overflow issues

    # Calculate content area dimensions
    $contentTop = $headerHeight
    $contentHeight = $formHeight - $headerHeight - $buttonAreaHeight - $progressAreaHeight - $margin
    $listViewWidth = [Math]::Floor(($formWidth - $margin * 3) * 0.58)  # 58% of width
    $outputWidth = $formWidth - $listViewWidth - $margin * 3

    # Create ListView for applications
    $script:ListView = New-Object System.Windows.Forms.ListView
    $script:ListView.Location = New-Object System.Drawing.Point($margin, $contentTop)
    $script:ListView.Size = New-Object System.Drawing.Size($listViewWidth, $contentHeight)
    $script:ListView.View = [System.Windows.Forms.View]::Details
    $script:ListView.FullRowSelect = $true
    $script:ListView.GridLines = $true
    $script:ListView.CheckBoxes = $true
    $script:ListView.Sorting = [System.Windows.Forms.SortOrder]::None
    $script:ListView.Font = New-Object System.Drawing.Font("Segoe UI", $normalFontSize)
    $script:ListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    # Create ImageList to control row height based on font size
    # Row height = font size * 2.2 for comfortable spacing
    $rowHeight = [Math]::Max([Math]::Round($normalFontSize * 2.2), 24)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $script:ListView.SmallImageList = $imageList

    Write-Log "ListView row height set to: $rowHeight px (based on font size: $normalFontSize pt)" -Level INFO

    # Add columns with optimized widths for readability
    # Adjusted proportions: App=40%, Category=20%, Status=20%, Version=18%
    # Remaining 2% for scrollbar and margins
    $colAppWidth = [Math]::Floor($listViewWidth * 0.40)
    $colCategoryWidth = [Math]::Floor($listViewWidth * 0.20)
    $colStatusWidth = [Math]::Floor($listViewWidth * 0.20)
    $colVersionWidth = [Math]::Floor($listViewWidth * 0.18)

    # Create column headers explicitly for better control
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

    # Add columns to ListView
    $script:ListView.Columns.AddRange(@($colAppName, $colCategory, $colStatus, $colVersion))

    # Add event handler to update progress label when checkboxes are checked/unchecked
    $script:ListView.Add_ItemCheck({
        param($sender, $e)

        # Use BeginInvoke to update after the check state has changed
        $script:ListView.BeginInvoke([Action]{
            $checkedCount = ($script:ListView.Items | Where-Object { $_.Checked }).Count
            $script:ProgressBar.Maximum = $checkedCount
            $script:ProgressBar.Value = 0
            $script:ProgressLabel.Text = "0 / $checkedCount applications"
        })
    })

    $form.Controls.Add($script:ListView)

    # Create WebBrowser control for HTML output (replaces RichTextBox)
    $script:WebBrowser = New-Object System.Windows.Forms.WebBrowser
    $script:WebBrowser.Location = New-Object System.Drawing.Point(($margin * 2 + $listViewWidth), $contentTop)
    $script:WebBrowser.Size = New-Object System.Drawing.Size($outputWidth, $contentHeight)
    $script:WebBrowser.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:WebBrowser.ScriptErrorsSuppressed = $true
    $script:WebBrowser.IsWebBrowserContextMenuEnabled = $false
    $script:WebBrowser.AllowNavigation = $false

    # Initialize HTML content
    $script:HtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #1e1e1e;
            color: #d4d4d4;
            margin: 10px;
            padding: 10px;
            font-size: 18px;
            line-height: 1.6;
        }
        h1 {
            color: #4ec9b0;
            font-size: 26px;
            margin: 10px 0;
            border-bottom: 2px solid #4ec9b0;
            padding-bottom: 5px;
        }
        h2 {
            color: #569cd6;
            font-size: 20px;
            margin: 8px 0;
        }
        p {
            font-size: 18px;
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
            font-size: 18px;
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
    </style>
</head>
<body>
    <div id="content">
    </div>
</body>
</html>
"@

    $script:WebBrowser.DocumentText = $script:HtmlContent
    $form.Controls.Add($script:WebBrowser)

    # Calculate progress bar position (above buttons)
    $progressTop = $formHeight - $buttonAreaHeight - $progressAreaHeight

    # Create progress bar (more compact)
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point($margin, $progressTop)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 18)  # Reduced from 25 to 18
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:ProgressBar)

    # Create progress label with more space to prevent clipping (especially descenders like 'p')
    $script:ProgressLabel = New-Object System.Windows.Forms.Label
    $script:ProgressLabel.Text = "0 / 0 applications"
    $script:ProgressLabel.Location = New-Object System.Drawing.Point($margin, ($progressTop + 22))
    $script:ProgressLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 30)  # Increased from 25 to 30 to prevent descender clipping
    $script:ProgressLabel.Font = New-Object System.Drawing.Font("Segoe UI", ([Math]::Max($normalFontSize - 1, 9)))
    $script:ProgressLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:ProgressLabel.AutoSize = $false
    $script:ProgressLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft  # Changed from MiddleLeft to TopLeft to prevent descender clipping
    $form.Controls.Add($script:ProgressLabel)

    # Store form dimensions and font sizes for button creation
    $form.Tag = @{
        FormWidth = $formWidth
        FormHeight = $formHeight
        DpiScale = $dpiScale
        CombinedScale = $combinedScale
        NormalFontSize = $normalFontSize
        TitleFontSize = $titleFontSize
        ConsoleFontSize = $consoleFontSize
    }

    return $form
}

function Create-Buttons {
    param($form)

    # Get form dimensions from Tag
    $formInfo = $form.Tag
    $formWidth = $formInfo.FormWidth
    $formHeight = $formInfo.FormHeight
    $normalFontSize = $formInfo.NormalFontSize

    # Button configuration
    $margin = 20
    $spacing = 12             # Proper spacing between buttons
    $buttonCount = 6

    # Create button font first (needed for width calculation)
    $buttonFontSize = [Math]::Max($normalFontSize, 9)
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize)
    $buttonFontBold = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize, [System.Drawing.FontStyle]::Bold)

    # Calculate button width based on longest text
    # Button texts: "Refresh Status", "Select All", "Select Missing", "Deselect All", "Install Selected", "Exit"
    $buttonTexts = @("Refresh Status", "Select All", "Select Missing", "Deselect All", "Install Selected", "Exit")

    # Create temporary graphics object to measure text
    $tempBitmap = New-Object System.Drawing.Bitmap(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($tempBitmap)

    # Measure all button texts and find the maximum width
    $maxTextWidth = 0
    foreach ($text in $buttonTexts) {
        $textSize = $graphics.MeasureString($text, $buttonFont)
        if ($textSize.Width -gt $maxTextWidth) {
            $maxTextWidth = $textSize.Width
        }
    }

    # Clean up graphics objects
    $graphics.Dispose()
    $tempBitmap.Dispose()

    # Add horizontal padding (20px on each side = 40px total)
    $buttonWidth = [Math]::Ceiling($maxTextWidth) + 40

    # Increase button height for 3x more vertical padding (top and bottom margin)
    # Text height ~15px + 30px top padding + 30px bottom padding = 75px
    $buttonHeight = 75        # Increased from 35 to 75 for 3x more vertical padding

    # Calculate button Y position (moved much lower to avoid clipping progress label)
    $buttonY = $formHeight - 85  # Moved from -55 to -85 (30px lower) to create more space above buttons

    # Calculate X positions for each button (left-aligned with proper spacing)
    $currentX = $margin

    # Refresh button
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $refreshButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $refreshButton.Text = "Refresh Status"
    $refreshButton.Font = $buttonFont
    $refreshButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $refreshButton.Add_Click({ Refresh-ApplicationList })
    $form.Controls.Add($refreshButton)
    $currentX += $buttonWidth + $spacing

    # Select All button
    $selectAllButton = New-Object System.Windows.Forms.Button
    $selectAllButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $selectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectAllButton.Text = "Select All"
    $selectAllButton.Font = $buttonFont
    $selectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $selectAllButton.Add_Click({
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
    $selectMissingButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $selectMissingButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectMissingButton.Text = "Select Missing"
    $selectMissingButton.Font = $buttonFont
    $selectMissingButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $selectMissingButton.Add_Click({
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
    $deselectAllButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $deselectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $deselectAllButton.Text = "Deselect All"
    $deselectAllButton.Font = $buttonFont
    $deselectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $deselectAllButton.Add_Click({
        foreach ($item in $script:ListView.Items) {
            $item.Checked = $false
        }
        # Update progress label after deselecting all
        $checkedCount = 0
        $script:ProgressBar.Maximum = 1  # Avoid division by zero
        $script:ProgressBar.Value = 0
        $script:ProgressLabel.Text = "0 / 0 applications"
    })
    $form.Controls.Add($deselectAllButton)
    $currentX += $buttonWidth + $spacing

    # Install Selected button
    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $installButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $installButton.Text = "Install Selected"
    $installButton.Font = $buttonFontBold
    $installButton.BackColor = [System.Drawing.Color]::Green
    $installButton.ForeColor = [System.Drawing.Color]::White
    $installButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $installButton.Add_Click({ Install-SelectedApplications })
    $form.Controls.Add($installButton)
    $currentX += $buttonWidth + $spacing

    # Exit button
    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $exitButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $exitButton.Text = "Exit"
    $exitButton.Font = $buttonFont
    $exitButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $exitButton.Add_Click({ $form.Close() })
    $form.Controls.Add($exitButton)
}

#endregion GUI Creation

#region Event Handlers

function Refresh-ApplicationList {
    Write-Output "`r`n=== Refreshing Application List ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Refreshing application list..." -Color ([System.Drawing.Color]::Blue)

    # Clear existing items
    $script:ListView.Items.Clear()

    # Get installed applications
    $script:InstalledApps = Get-InstalledApplications

    # Group applications by category
    $categories = $script:Applications | Group-Object -Property Category | Sort-Object Name

    # Add applications to ListView
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

            # Store app object in Tag
            $item.Tag = $app

            $script:ListView.Items.Add($item) | Out-Null
        }
    }

    $installedCount = ($script:ListView.Items | Where-Object { $_.SubItems[2].Text -eq "Installed" }).Count
    $totalCount = $script:ListView.Items.Count

    Write-Output "Ready - $installedCount of $totalCount applications installed" -Color ([System.Drawing.Color]::Green)
    Write-Output "Application list refreshed: $installedCount / $totalCount installed" -Color ([System.Drawing.Color]::Green)
}

function Install-SelectedApplications {
    # Get checked items
    $checkedItems = $script:ListView.Items | Where-Object { $_.Checked }

    if ($checkedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one application to install.",
            "No Selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Confirm installation
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Install $($checkedItems.Count) selected application(s)?",
        "Confirm Installation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    # Disable buttons during installation
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $false
        }
    }

    # Setup progress bar
    $script:ProgressBar.Maximum = $checkedItems.Count
    $script:ProgressBar.Value = 0

    Write-Output "`r`n=== Starting Installation ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installing $($checkedItems.Count) application(s)..." -Color ([System.Drawing.Color]::Blue)

    $successCount = 0
    $failCount = 0
    $currentIndex = 0
    $completedCount = 0

    foreach ($item in $checkedItems) {
        $currentIndex++
        $app = $item.Tag

        Write-Output "Installing $($app.Name) ($currentIndex of $($checkedItems.Count))..." -Color ([System.Drawing.Color]::Blue)

        # Install application
        $success = Install-Application -App $app

        if ($success) {
            $successCount++
            $item.SubItems[2].Text = "Installed"
            $item.ForeColor = [System.Drawing.Color]::Green
        }
        else {
            $failCount++
        }

        # Update progress after installation completes
        $completedCount++
        $script:ProgressBar.Value = $completedCount
        $script:ProgressLabel.Text = "$completedCount / $($checkedItems.Count) applications"

        # Process Windows messages to keep UI responsive
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Re-enable buttons
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $true
        }
    }

    # Show completion message
    $completionColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }

    Write-Output "`r`n=== Installation Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installation complete: $successCount succeeded, $failCount failed" -Color $completionColor
    Write-Output "Success: $successCount | Failed: $failCount" -Color $completionColor

    [System.Windows.Forms.MessageBox]::Show(
        "Installation complete!`n`nSuccessful: $successCount`nFailed: $failCount",
        "Installation Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

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
        <p class="success" style="margin: 5px 0; font-size: 20px;">
            <strong>📦 Total Applications Available:</strong> $totalApps
        </p>
        <p class="info" style="margin: 5px 0; font-size: 20px;">
            <strong>✅ Currently Installed:</strong> $installedCount
        </p>
        <p class="warning" style="margin: 5px 0; font-size: 20px;">
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
            <strong>Web:</strong> <a href="https://mytech.today" target="_blank" style="color: #4fc1ff;">https://mytech.today</a>
        </p>
    </div>

    <p class="success" style="text-align: center; margin-top: 15px; font-size: 19px;">
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
    Initialize-Logging
    Write-Host "[OK] Logging initialized" -ForegroundColor Green

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

    # Display marketing information
    Show-MarketingInformation

    Write-Output "`r`nGUI ready. Select applications and click 'Install Selected' to begin." -Color ([System.Drawing.Color]::Green)

    Write-Host "`n[OK] GUI initialized successfully!" -ForegroundColor Green
    Write-Host "[i] Showing GUI window..." -ForegroundColor Cyan

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

#endregion Main Execution


