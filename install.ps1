<#
.SYNOPSIS
    Menu-driven application installer for automated Windows setup.

.DESCRIPTION
    This script provides a comprehensive menu-driven interface for installing and managing
    multiple applications on Windows systems. Features include:
    - Interactive menu with installation status display
    - Version detection for installed applications
    - Selective installation (individual apps, all apps, or only missing apps)
    - Centralized logging to C:\mytech.today\logs\
    - Support for 93 applications via winget and custom installers
    - Error handling with fallback solutions
    - Automatic winget installation on Windows 10

.PARAMETER Action
    The action to perform. Valid values: Menu, InstallAll, InstallMissing, Status
    Default: Menu (interactive mode)

.PARAMETER AppName
    Specific application name to install (when not using menu)

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
    .\install.ps1 -AppName "Chrome"
    Installs only Google Chrome

.NOTES
    File Name      : install.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Version        : 1.3.7

.LINK
    https://github.com/mytech-today-now/PowerShellScripts
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Menu', 'InstallAll', 'InstallMissing', 'Status')]
    [string]$Action = 'Menu',

    [Parameter(Mandatory = $false)]
    [string]$AppName
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Script variables
$script:ScriptVersion = '1.3.7'
$script:OriginalScriptPath = $PSScriptRoot
$script:SystemInstallPath = "$env:SystemDrive\mytech.today\app_installer"
$script:ScriptPath = $script:SystemInstallPath  # Will be updated after copy
$script:CentralLogPath = "C:\mytech.today\logs\"
$script:LogPath = $null
$script:AppsPath = Join-Path $script:ScriptPath "apps"

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
$copiedToSystem = Copy-ScriptToSystemLocation

# Update script paths to use system location
if ($copiedToSystem) {
    $script:ScriptPath = $script:SystemInstallPath
    $script:AppsPath = Join-Path $script:ScriptPath "apps"
}

#endregion Self-Installation to System Location

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
    [PSCustomObject]@{ Name = "Sublime Text"; ScriptName = "sublime text.ps1"; WingetId = "SublimeHQ.SublimeText.4"; Category = "Development"; Description = "Fast, sophisticated text editor" }
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
    # Communication
    [PSCustomObject]@{ Name = "Discord"; ScriptName = "discord.ps1"; WingetId = "Discord.Discord"; Category = "Communication"; Description = "Voice, video, and text chat platform" }
    [PSCustomObject]@{ Name = "Zoom"; ScriptName = "zoom.ps1"; WingetId = "Zoom.Zoom"; Category = "Communication"; Description = "Video conferencing and meetings" }
    [PSCustomObject]@{ Name = "Microsoft Teams"; ScriptName = "teams.ps1"; WingetId = "Microsoft.Teams"; Category = "Communication"; Description = "Collaboration and communication hub" }
    [PSCustomObject]@{ Name = "Skype"; ScriptName = "skype.ps1"; WingetId = "Microsoft.Skype"; Category = "Communication"; Description = "Video calls and instant messaging" }
    [PSCustomObject]@{ Name = "Slack"; ScriptName = "slack.ps1"; WingetId = "SlackTechnologies.Slack"; Category = "Communication"; Description = "Team collaboration and messaging" }
    [PSCustomObject]@{ Name = "Telegram Desktop"; ScriptName = "telegram.ps1"; WingetId = "Telegram.TelegramDesktop"; Category = "Communication"; Description = "Fast, secure messaging app" }
    [PSCustomObject]@{ Name = "Signal"; ScriptName = "signal.ps1"; WingetId = "OpenWhisperSystems.Signal"; Category = "Communication"; Description = "Privacy-focused encrypted messaging" }
    [PSCustomObject]@{ Name = "Thunderbird"; ScriptName = "thunderbird.ps1"; WingetId = "Mozilla.Thunderbird"; Category = "Communication"; Description = "Open-source email client" }
    # 3D & CAD
    [PSCustomObject]@{ Name = "Blender"; ScriptName = "blender.ps1"; WingetId = "BlenderFoundation.Blender"; Category = "3D & CAD"; Description = "3D modeling, animation, and rendering" }
    [PSCustomObject]@{ Name = "FreeCAD"; ScriptName = "freecad.ps1"; WingetId = "FreeCAD.FreeCAD"; Category = "3D & CAD"; Description = "Parametric 3D CAD modeler" }
    [PSCustomObject]@{ Name = "LibreCAD"; ScriptName = "librecad.ps1"; WingetId = "LibreCAD.LibreCAD"; Category = "3D & CAD"; Description = "2D CAD drafting application" }
    [PSCustomObject]@{ Name = "KiCad"; ScriptName = "kicad.ps1"; WingetId = "KiCad.KiCad"; Category = "3D & CAD"; Description = "Electronic design automation suite" }
    [PSCustomObject]@{ Name = "OpenSCAD"; ScriptName = "openscad.ps1"; WingetId = "OpenSCAD.OpenSCAD"; Category = "3D & CAD"; Description = "Script-based 3D CAD modeler" }
    [PSCustomObject]@{ Name = "Wings 3D"; ScriptName = "wings3d.ps1"; WingetId = "Wings3D.Wings3D"; Category = "3D & CAD"; Description = "Polygon mesh modeling tool" }
    [PSCustomObject]@{ Name = "Sweet Home 3D"; ScriptName = "sweethome3d.ps1"; WingetId = "eTeks.SweetHome3D"; Category = "3D & CAD"; Description = "Interior design and floor planning" }
    # Networking
    [PSCustomObject]@{ Name = "Wireshark"; ScriptName = "wireshark.ps1"; WingetId = "WiresharkFoundation.Wireshark"; Category = "Networking"; Description = "Network protocol analyzer" }
    [PSCustomObject]@{ Name = "Nmap"; ScriptName = "nmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking"; Description = "Network discovery and security scanner" }
    [PSCustomObject]@{ Name = "Zenmap"; ScriptName = "zenmap.ps1"; WingetId = "Insecure.Nmap"; Category = "Networking"; Description = "GUI for Nmap security scanner" }
    [PSCustomObject]@{ Name = "PuTTY"; ScriptName = "putty.ps1"; WingetId = "PuTTY.PuTTY"; Category = "Networking"; Description = "SSH and telnet client" }
    [PSCustomObject]@{ Name = "Advanced IP Scanner"; ScriptName = "advancedipscanner.ps1"; WingetId = "Famatech.AdvancedIPScanner"; Category = "Networking"; Description = "Fast network scanner for Windows" }
    [PSCustomObject]@{ Name = "Fing CLI"; ScriptName = "fing.ps1"; WingetId = "Fing.Fing"; Category = "Networking"; Description = "Network scanning and troubleshooting" }
    # Runtime Environments
    [PSCustomObject]@{ Name = "Java Runtime Environment"; ScriptName = "java.ps1"; WingetId = "Oracle.JavaRuntimeEnvironment"; Category = "Runtime"; Description = "Java application runtime" }
    [PSCustomObject]@{ Name = ".NET Desktop Runtime 6"; ScriptName = "dotnet6.ps1"; WingetId = "Microsoft.DotNet.DesktopRuntime.6"; Category = "Runtime"; Description = ".NET 6 desktop application runtime" }
    [PSCustomObject]@{ Name = ".NET Desktop Runtime 8"; ScriptName = "dotnet8.ps1"; WingetId = "Microsoft.DotNet.DesktopRuntime.8"; Category = "Runtime"; Description = ".NET 8 desktop application runtime" }
    [PSCustomObject]@{ Name = "Visual C++ Redistributable"; ScriptName = "vcredist.ps1"; WingetId = "Microsoft.VCRedist.2015+.x64"; Category = "Runtime"; Description = "Microsoft C++ runtime libraries" }
    # Writing & Screenwriting
    [PSCustomObject]@{ Name = "Trelby"; ScriptName = "trelby.ps1"; WingetId = $null; Category = "Writing"; Description = "Screenplay writing software" }
    [PSCustomObject]@{ Name = "KIT Scenarist"; ScriptName = "kitscenarist.ps1"; WingetId = $null; Category = "Writing"; Description = "Screenwriting and story development" }
    [PSCustomObject]@{ Name = "Storyboarder"; ScriptName = "storyboarder.ps1"; WingetId = "Wonderunit.Storyboarder"; Category = "Writing"; Description = "Storyboard creation tool" }
    [PSCustomObject]@{ Name = "FocusWriter"; ScriptName = "focuswriter.ps1"; WingetId = "GottCode.FocusWriter"; Category = "Writing"; Description = "Distraction-free writing environment" }
    [PSCustomObject]@{ Name = "Manuskript"; ScriptName = "manuskript.ps1"; WingetId = "TheologicalElucidations.Manuskript"; Category = "Writing"; Description = "Novel writing and organization tool" }
    [PSCustomObject]@{ Name = "yWriter"; ScriptName = "ywriter.ps1"; WingetId = "Spacejock.yWriter"; Category = "Writing"; Description = "Word processor for novelists" }
    # Gaming
    [PSCustomObject]@{ Name = "Steam"; ScriptName = "steam.ps1"; WingetId = "Valve.Steam"; Category = "Gaming"; Description = "Digital game distribution platform" }
    [PSCustomObject]@{ Name = "Epic Games Launcher"; ScriptName = "epicgames.ps1"; WingetId = "EpicGames.EpicGamesLauncher"; Category = "Gaming"; Description = "Epic Games store and launcher" }
    [PSCustomObject]@{ Name = "GOG Galaxy"; ScriptName = "goggalaxy.ps1"; WingetId = "GOG.Galaxy"; Category = "Gaming"; Description = "DRM-free game launcher" }
    [PSCustomObject]@{ Name = "EA App"; ScriptName = "eaapp.ps1"; WingetId = "ElectronicArts.EADesktop"; Category = "Gaming"; Description = "Electronic Arts game platform" }
    # Cloud Storage
    [PSCustomObject]@{ Name = "Google Drive"; ScriptName = "googledrive.ps1"; WingetId = "Google.GoogleDrive"; Category = "Cloud Storage"; Description = "Cloud storage and file sync by Google" }
    [PSCustomObject]@{ Name = "Dropbox"; ScriptName = "dropbox.ps1"; WingetId = "Dropbox.Dropbox"; Category = "Cloud Storage"; Description = "Cloud file storage and sharing" }
    [PSCustomObject]@{ Name = "OneDrive"; ScriptName = "onedrive.ps1"; WingetId = "Microsoft.OneDrive"; Category = "Cloud Storage"; Description = "Microsoft cloud storage service" }
    [PSCustomObject]@{ Name = "MEGA"; ScriptName = "mega.ps1"; WingetId = "Mega.MEGASync"; Category = "Cloud Storage"; Description = "Secure cloud storage with encryption" }
    # Remote Desktop
    [PSCustomObject]@{ Name = "TeamViewer"; ScriptName = "teamviewer.ps1"; WingetId = "TeamViewer.TeamViewer"; Category = "Remote Desktop"; Description = "Remote access and support software" }
    [PSCustomObject]@{ Name = "AnyDesk"; ScriptName = "anydesk.ps1"; WingetId = "AnyDeskSoftwareGmbH.AnyDesk"; Category = "Remote Desktop"; Description = "Fast remote desktop application" }
    [PSCustomObject]@{ Name = "Chrome Remote Desktop"; ScriptName = "chromeremote.ps1"; WingetId = "Google.ChromeRemoteDesktop"; Category = "Remote Desktop"; Description = "Remote access via Chrome browser" }
    [PSCustomObject]@{ Name = "TightVNC"; ScriptName = "tightvnc.ps1"; WingetId = "GlavSoft.TightVNC"; Category = "Remote Desktop"; Description = "Remote desktop control software" }
    # Backup & Recovery
    [PSCustomObject]@{ Name = "Veeam Agent FREE"; ScriptName = "veeam.ps1"; WingetId = "Veeam.Agent.Windows"; Category = "Backup"; Description = "Free backup and recovery solution" }
    [PSCustomObject]@{ Name = "Macrium Reflect Free"; ScriptName = "macrium.ps1"; WingetId = "Macrium.ReflectFree"; Category = "Backup"; Description = "Disk imaging and cloning tool" }
    [PSCustomObject]@{ Name = "EaseUS Todo Backup Free"; ScriptName = "easeus.ps1"; WingetId = "EASEUSAG.EaseUSTodoBackupFree"; Category = "Backup"; Description = "Backup and disaster recovery" }
    [PSCustomObject]@{ Name = "Duplicati"; ScriptName = "duplicati.ps1"; WingetId = "Duplicati.Duplicati"; Category = "Backup"; Description = "Encrypted backup to cloud storage" }
    # Education
    [PSCustomObject]@{ Name = "Anki"; ScriptName = "anki.ps1"; WingetId = "Anki.Anki"; Category = "Education"; Description = "Flashcard-based learning system" }
    [PSCustomObject]@{ Name = "GeoGebra"; ScriptName = "geogebra.ps1"; WingetId = "GeoGebra.Classic"; Category = "Education"; Description = "Interactive math and geometry software" }
    [PSCustomObject]@{ Name = "Stellarium"; ScriptName = "stellarium.ps1"; WingetId = "Stellarium.Stellarium"; Category = "Education"; Description = "Planetarium and astronomy software" }
    [PSCustomObject]@{ Name = "MuseScore"; ScriptName = "musescore.ps1"; WingetId = "Musescore.Musescore"; Category = "Education"; Description = "Music notation and composition" }
    # Finance
    [PSCustomObject]@{ Name = "GnuCash"; ScriptName = "gnucash.ps1"; WingetId = "GnuCash.GnuCash"; Category = "Finance"; Description = "Personal and small business accounting" }
    [PSCustomObject]@{ Name = "HomeBank"; ScriptName = "homebank.ps1"; WingetId = "HomeBank.HomeBank"; Category = "Finance"; Description = "Personal finance management" }
    [PSCustomObject]@{ Name = "Money Manager Ex"; ScriptName = "moneymanagerex.ps1"; WingetId = "MoneyManagerEx.MoneyManagerEx"; Category = "Finance"; Description = "Easy-to-use finance tracker" }
    # Shortcuts & Maintenance
    [PSCustomObject]@{ Name = "Grok AI Shortcuts"; ScriptName = "grok-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Quick access to Grok AI assistant" }
    [PSCustomObject]@{ Name = "ChatGPT Shortcuts"; ScriptName = "chatgpt-shortcuts.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Quick access to ChatGPT" }
    [PSCustomObject]@{ Name = "dictation.io Shortcut"; ScriptName = "dictation-shortcut.ps1"; WingetId = $null; Category = "Shortcuts"; Description = "Web-based voice dictation tool" }
    [PSCustomObject]@{ Name = "Uninstall McAfee"; ScriptName = "uninstall-mcafee.ps1"; WingetId = $null; Category = "Maintenance"; Description = "Remove McAfee software completely" }
)

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
        if (-not (Test-Path $script:CentralLogPath)) {
            New-Item -Path $script:CentralLogPath -ItemType Directory -Force | Out-Null
        }

        # Use script-specific log file in central location
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        $logFileName = "$scriptName-$(Get-Date -Format 'yyyy-MM').md"
        $script:LogPath = Join-Path $script:CentralLogPath $logFileName

        # Initialize markdown log file if it doesn't exist
        if (-not (Test-Path $script:LogPath)) {
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
        if ($script:LogPath -and (Test-Path $script:LogPath)) {
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

    try {
        # Check if running on Windows 10
        $osVersion = [System.Environment]::OSVersion.Version
        $isWindows10 = $osVersion.Major -eq 10 -and $osVersion.Build -lt 22000

        if (-not $isWindows10) {
            Write-Log "Not running on Windows 10, skipping winget installation" -Level INFO
            return $false
        }

        Write-Host "`n[i] Detected Windows 10. Installing winget (Windows Package Manager)..." -ForegroundColor Cyan
        Write-Log "Installing winget on Windows 10" -Level INFO

        $tempDir = Join-Path $env:TEMP "winget_install"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Install VCLibs dependency
        Write-Host "  [i] Downloading VCLibs dependency..." -ForegroundColor Gray
        $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vcLibsPath = Join-Path $tempDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Invoke-WebRequest -Uri $vcLibsUrl -OutFile $vcLibsPath -UseBasicParsing
        Write-Host "  [i] Installing VCLibs..." -ForegroundColor Gray
        Add-AppxPackage -Path $vcLibsPath -ErrorAction SilentlyContinue

        # Install UI.Xaml dependency
        Write-Host "  [i] Downloading UI.Xaml dependency..." -ForegroundColor Gray
        $uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        $uiXamlPath = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.x64.appx"
        Invoke-WebRequest -Uri $uiXamlUrl -OutFile $uiXamlPath -UseBasicParsing
        Write-Host "  [i] Installing UI.Xaml..." -ForegroundColor Gray
        Add-AppxPackage -Path $uiXamlPath -ErrorAction SilentlyContinue

        # Get latest winget release
        Write-Host "  [i] Fetching latest winget release information..." -ForegroundColor Gray
        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $msixBundleUrl = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url

        if (-not $msixBundleUrl) {
            Write-Log "Failed to find winget msixbundle in latest release" -Level ERROR
            Write-Host "  [X] Failed to find winget download URL" -ForegroundColor Red
            return $false
        }

        # Download and install winget
        Write-Host "  [i] Downloading winget..." -ForegroundColor Gray
        $wingetPath = Join-Path $tempDir "Microsoft.DesktopAppInstaller.msixbundle"
        Invoke-WebRequest -Uri $msixBundleUrl -OutFile $wingetPath -UseBasicParsing

        Write-Host "  [i] Installing winget..." -ForegroundColor Gray
        Add-AppxPackage -Path $wingetPath

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        # Verify installation
        Start-Sleep -Seconds 2
        $wingetInstalled = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        if ($wingetInstalled) {
            Write-Host "  [OK] winget installed successfully!" -ForegroundColor Green
            Write-Log "winget installed successfully on Windows 10" -Level SUCCESS
            return $true
        }
        else {
            Write-Host "  [X] winget installation completed but command not found" -ForegroundColor Red
            Write-Log "winget installation completed but command not available" -Level WARNING
            return $false
        }
    }
    catch {
        Write-Log "Failed to install winget: $($_.Exception.Message)" -Level ERROR
        Write-Host "  [X] Failed to install winget: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
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
        Write-Host "`n[i] winget not found. Attempting to install on Windows 10..." -ForegroundColor Yellow
        $installed = Install-WingetOnWindows10

        if ($installed) {
            return $true
        }
        else {
            Write-Host "[X] Failed to install winget automatically. Please install 'App Installer' from Microsoft Store." -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "[X] winget not found. Please install 'App Installer' from Microsoft Store." -ForegroundColor Red
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
        if (Test-WingetAvailable) {
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
    }
    catch {
        Write-Log "Error detecting installed applications: $_" -Level WARNING
    }
    
    return $installedApps
}

#endregion

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

    Write-Host "  [Actions]" -ForegroundColor Magenta
    Write-Host "    1-$($menuItems.Count). Install Specific Application (type number)" -ForegroundColor Cyan
    Write-Host "    A. Install All Applications" -ForegroundColor Yellow
    Write-Host "    M. Install Missing Applications Only" -ForegroundColor Yellow
    Write-Host "    S. Show Status Only" -ForegroundColor Yellow
    Write-Host "    R. Refresh Status" -ForegroundColor Yellow
    Write-Host "    Q. Quit" -ForegroundColor Yellow
    Write-Host ""

    return $menuItems
}

function Install-Application {
    <#
    .SYNOPSIS
        Installs a specific application.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$App,

        [Parameter(Mandatory = $false)]
        [int]$CurrentIndex = 0,

        [Parameter(Mandatory = $false)]
        [int]$TotalCount = 0
    )

    Write-Log "Installing $($App.Name)..." -Level INFO

    # Show overall progress if index and total are provided
    if ($TotalCount -gt 0) {
        $percentComplete = [Math]::Round(($CurrentIndex / $TotalCount) * 100, 1)
        Write-Progress -Activity "Installing Applications" `
            -Status "Installing $($App.Name) ($CurrentIndex of $TotalCount - $percentComplete%)" `
            -PercentComplete $percentComplete `
            -Id 1
    }

    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Installing: $($App.Name)" -ForegroundColor Cyan
    if ($TotalCount -gt 0) {
        Write-Host "║  Progress: $CurrentIndex of $TotalCount ($percentComplete%)" -ForegroundColor Cyan
    }
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    try {
        # Check if custom script exists
        $scriptPath = Join-Path $script:AppsPath $App.ScriptName

        if (Test-Path $scriptPath) {
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

            Write-Host "  [1/2] 🔍 Using custom installation script..." -ForegroundColor Gray
            Write-Verbose "Executing script: $scriptPath"
            & $scriptPath
            Write-Verbose "Custom script completed with exit code: $LASTEXITCODE"

            if ($TotalCount -gt 0) {
                Write-Progress -Activity "Installing $($App.Name)" `
                    -Status "Complete" `
                    -PercentComplete 100 `
                    -ParentId 1 `
                    -Id 2 `
                    -Completed
            }

            Write-Host "  [2/2] ✅ Installation complete!" -ForegroundColor Green
            return $true
        }
        elseif ($App.WingetId) {
            # Use winget for installation
            if (Test-WingetAvailable) {
                Write-Log "Installing via winget: $($App.WingetId)" -Level INFO
                Write-Verbose "Installing $($App.Name) using winget ID: $($App.WingetId)"

                # Phase 1: Checking
                if ($TotalCount -gt 0) {
                    Write-Progress -Activity "Installing $($App.Name)" `
                        -Status "Checking for existing installation..." `
                        -PercentComplete 10 `
                        -ParentId 1 `
                        -Id 2
                }
                Write-Host "  [1/3] 🔍 Checking for existing installation..." -ForegroundColor Gray
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
                Write-Host "  [2/3] 📦 Downloading and installing package..." -ForegroundColor Yellow
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
                    Write-Host "  [3/3] ✅ $($App.Name) installed successfully!" -ForegroundColor Green
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

                    Write-Log "$($App.Name) installation failed: $result" -Level ERROR
                    Write-Host "  [3/3] ❌ Installation failed. Check log for details." -ForegroundColor Red
                    return $false
                }
            }
            else {
                Write-Log "winget not available, cannot install $($App.Name)" -Level ERROR
                Write-Host "  ❌ winget not available. Please install App Installer from Microsoft Store." -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Log "No installation method available for $($App.Name)" -Level WARNING
            Write-Host "  ⚠️ No installation method configured for $($App.Name)" -ForegroundColor Yellow
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
        Write-Host "  ❌ Error: $_" -ForegroundColor Red
        return $false
    }
}

function Install-AllApplications {
    <#
    .SYNOPSIS
        Installs all applications.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Installing all applications..." -Level INFO
    Write-Verbose "Starting installation of all $($script:Applications.Count) applications"
    Write-Host "`n+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                    Installing All Applications                    |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0
    $totalCount = $script:Applications.Count
    $currentIndex = 0
    $startTime = Get-Date
    $installationTimes = @()  # Track individual installation times for ETA

    Write-Verbose "Total applications to install: $totalCount"

    foreach ($app in $script:Applications) {
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
                Write-Host "  ⏱️  Estimated time remaining: $etaMinutes minutes ($remainingApps apps left)" -ForegroundColor DarkGray
            }
        }

        if ($result) {
            $successCount++
        }
        else {
            $failCount++
        }
        Start-Sleep -Seconds 1
    }

    # Complete the overall progress
    Write-Progress -Activity "Installing Applications" -Completed -Id 1

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    Write-Verbose "Installation batch completed in $totalMinutes minutes"
    Write-Verbose "Success rate: $([Math]::Round(($successCount / $totalCount) * 100, 1))%"

    # Installation Summary
    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     INSTALLATION SUMMARY                           ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Total Applications: $totalCount" -ForegroundColor White
    Write-Host "║  ✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "║  ❌ Failed: $failCount" -ForegroundColor Red
    Write-Host "║  ⏱️  Total Time: $totalMinutes minutes" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Log "Installation complete. Success: $successCount, Failed: $failCount, Duration: $totalMinutes minutes" -Level INFO
    Write-Verbose "Installation summary logged to: $script:LogFile"
}

function Install-MissingApplications {
    <#
    .SYNOPSIS
        Installs only applications that are not currently installed.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Installing missing applications..." -Level INFO
    Write-Host "`n+===================================================================+" -ForegroundColor Cyan
    Write-Host "|                Installing Missing Applications Only               |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan

    $installedApps = Get-InstalledApplications
    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    $totalCount = $script:Applications.Count
    $currentIndex = 0
    $startTime = Get-Date
    $installationTimes = @()  # Track individual installation times for ETA

    foreach ($app in $script:Applications) {
        $currentIndex++

        if ($installedApps.ContainsKey($app.Name)) {
            Write-Host "`n⏭️  Skipping $($app.Name) - Already installed ($($installedApps[$app.Name]))" -ForegroundColor Gray
            $skippedCount++

            # Update progress for skipped apps
            $percentComplete = [Math]::Round(($currentIndex / $totalCount) * 100, 1)
            Write-Progress -Activity "Installing Missing Applications" `
                -Status "Skipped $($app.Name) ($currentIndex of $totalCount - $percentComplete%)" `
                -PercentComplete $percentComplete `
                -Id 1
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
                    Write-Host "  ⏱️  Estimated time remaining: $etaMinutes minutes ($remainingApps apps left)" -ForegroundColor DarkGray
                }
            }

            if ($result) {
                $successCount++
            }
            else {
                $failCount++
            }
        }
        Start-Sleep -Seconds 1
    }

    # Complete the overall progress
    Write-Progress -Activity "Installing Missing Applications" -Completed -Id 1

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalMinutes = [Math]::Round($duration.TotalMinutes, 1)

    Write-Verbose "Installation batch completed in $totalMinutes minutes"
    Write-Verbose "Installed: $successCount, Skipped: $skippedCount, Failed: $failCount"

    # Installation Summary
    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     INSTALLATION SUMMARY                           ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Total Applications: $totalCount" -ForegroundColor White
    Write-Host "║  ✅ Installed: $successCount" -ForegroundColor Green
    Write-Host "║  ⏭️  Skipped: $skippedCount" -ForegroundColor Gray
    Write-Host "║  ❌ Failed: $failCount" -ForegroundColor Red
    Write-Host "║  ⏱️  Total Time: $totalMinutes minutes" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Log "Installation complete. Installed: $successCount, Skipped: $skippedCount, Failed: $failCount, Duration: $totalMinutes minutes" -Level INFO
    Write-Verbose "Installation summary logged to: $script:LogFile"
}

function Install-MonthlyUpdateTask {
    <#
    .SYNOPSIS
        Creates a scheduled task for monthly winget updates

    .DESCRIPTION
        Creates a Windows scheduled task that runs winget-update.ps1 monthly on the 15th at 1 PM.
        The task is created in a "myTech.Today" folder in Task Scheduler.
        Uses schtasks.exe for maximum compatibility across PowerShell versions.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Log "Creating monthly update scheduled task..." -Level INFO
        Write-Host "`n[i] Setting up monthly application updates..." -ForegroundColor Cyan

        # Path to the update script - ALWAYS use system location for scheduled tasks
        $systemAppsPath = Join-Path $script:SystemInstallPath "apps"
        $updateScriptPath = Join-Path $systemAppsPath "winget-update.ps1"

        Write-Host "    [i] Task will use: $updateScriptPath" -ForegroundColor Gray

        # Verify the script exists
        if (-not (Test-Path $updateScriptPath)) {
            Write-Log "Update script not found: $updateScriptPath" -Level ERROR
            Write-Host "  [X] Update script not found. Skipping task creation." -ForegroundColor Red
            return $false
        }

        # Task configuration
        $taskName = "Monthly Application Updates"
        $taskFolder = "myTech.Today"
        $taskFullPath = "\$taskFolder\$taskName"

        # Check if task already exists and delete it
        $existingTask = schtasks.exe /Query /TN $taskFullPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Scheduled task already exists. Deleting old task..." -Level INFO
            Write-Host "  [i] Task already exists. Updating configuration..." -ForegroundColor Yellow

            $deleteResult = schtasks.exe /Delete /TN $taskFullPath /F 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Warning: Could not delete existing task: $deleteResult" -Level WARNING
            }
        }

        # Build the PowerShell command
        $psCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$updateScriptPath`""

        # Create the scheduled task using schtasks.exe
        # /SC MONTHLY = Monthly schedule
        # /D 15 = Day 15 of the month
        # /ST 13:00 = Start time 1:00 PM
        # /RL HIGHEST = Run with highest privileges
        # /RU = Run as current user
        $createResult = schtasks.exe /Create `
            /TN $taskFullPath `
            /TR $psCommand `
            /SC MONTHLY `
            /D 15 `
            /ST 13:00 `
            /RL HIGHEST `
            /RU "$env:USERDOMAIN\$env:USERNAME" `
            /F 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "Error creating scheduled task via schtasks: $createResult" -Level ERROR
            Write-Host "  [X] Failed to create scheduled task" -ForegroundColor Red
            Write-Host "      Error: $createResult" -ForegroundColor Red
            return $false
        }

        Write-Log "Scheduled task created successfully: $taskFullPath" -Level SUCCESS
        Write-Host "  [OK] Monthly update task created successfully!" -ForegroundColor Green
        Write-Host "      Schedule: 15th of every month at 1:00 PM" -ForegroundColor Gray
        Write-Host "      Location: Task Scheduler > $taskFolder > $taskName" -ForegroundColor Gray

        return $true
    }
    catch {
        Write-Log "Error creating scheduled task: $_" -Level ERROR
        Write-Host "  [X] Failed to create scheduled task: $_" -ForegroundColor Red
        return $false
    }
}

#endregion

# Initialize logging
Initialize-Logging
Write-Log "=== App Installer v$script:ScriptVersion Started ===" -Level INFO
Write-Log "Action: $Action" -Level INFO

# Check for winget availability (install on Windows 10 if needed)
Write-Host "`n[i] Checking for winget availability..." -ForegroundColor Cyan
$wingetAvailable = Ensure-WingetAvailable

if (-not $wingetAvailable) {
    Write-Log "winget is not available on this system" -Level WARNING
    Write-Host "`n⚠️  WARNING: winget (Windows Package Manager) is not available." -ForegroundColor Yellow
    Write-Host "   Many applications require winget for installation." -ForegroundColor Yellow
    Write-Host ""

    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -ne 'Y') {
        Write-Log "User cancelled due to missing winget" -Level INFO
        exit 0
    }
}
else {
    Write-Host "[OK] winget is available" -ForegroundColor Green
}

# Main execution
try {
    switch ($Action) {
        'Menu' {
            # Interactive menu mode
            do {
                $menuItems = Show-Menu
                Write-Host "Enter your choice (number or letter): " -NoNewline -ForegroundColor White
                $choice = Read-Host

                if ($choice -match '^\d+$') {
                    $index = [int]$choice
                    if ($menuItems.ContainsKey($index)) {
                        Install-Application -App $menuItems[$index]
                        Read-KeySafe
                    }
                    else {
                        Write-Host "Invalid selection." -ForegroundColor Red
                        Read-KeySafe
                    }
                }
                elseif ($choice -eq 'A') {
                    Install-AllApplications
                    Read-KeySafe
                }
                elseif ($choice -eq 'M') {
                    Install-MissingApplications
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

        'Status' {
            $menuItems = Show-Menu
            Write-Host "`nStatus display complete." -ForegroundColor Green
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

    # Create monthly update scheduled task (if not already created)
    Install-MonthlyUpdateTask
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
Write-Host "    - IT Consulting & Support" -ForegroundColor Gray
Write-Host "    - Custom PowerShell Automation" -ForegroundColor Gray
Write-Host "    - Infrastructure Optimization" -ForegroundColor Gray
Write-Host "    - Cloud Integration (Azure, AWS, Microsoft 365)" -ForegroundColor Gray
Write-Host "    - System Administration & Security" -ForegroundColor Gray
Write-Host "    - Database Management & Custom Development" -ForegroundColor Gray
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

exit 0

