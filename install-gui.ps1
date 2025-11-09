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
    Version        : 1.3.7

.LINK
    https://github.com/mytech-today-now/app_installer
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
$script:IsClosing = $false  # Flag to prevent event handlers during form closing
$script:IsInstalling = $false  # Flag to track if installation is in progress

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
            $manageRPPath = "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1"
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

#endregion Installation Functions

#region GUI Creation

function Get-DPIScaleFactor {
    <#
    .SYNOPSIS
        Calculates DPI scaling factor based on screen resolution and DPI settings.

    .DESCRIPTION
        Detects screen resolution and DPI, then calculates appropriate scaling factor.
        Supports VGA through 8K UHD displays with progressive scaling.
        Follows myTech.Today GUI responsiveness standards from .augment/gui-responsiveness.md

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
    #>
    [CmdletBinding()]
    param()

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

    if ($screen.Bounds.Width -ge 7680) {
        # 8K UHD or higher
        $additionalScale = 2.5
        $resolutionName = "8K UHD"
    }
    elseif ($screen.Bounds.Width -ge 5120) {
        # 5K
        $additionalScale = 1.8
        $resolutionName = "5K"
    }
    elseif ($screen.Bounds.Width -ge 3840) {
        # 4K UHD or UW4K
        $additionalScale = 1.5
        $resolutionName = "4K UHD"
    }
    elseif ($screen.Bounds.Width -ge 3440) {
        # UWQHD
        $additionalScale = 1.3
        $resolutionName = "UWQHD"
    }
    elseif ($screen.Bounds.Width -ge 2560) {
        # QHD
        $additionalScale = 1.3
        $resolutionName = "QHD"
    }
    elseif ($screen.Bounds.Width -ge 1920) {
        # FHD
        $additionalScale = 1.2
        $resolutionName = "FHD"
    }
    elseif ($screen.Bounds.Width -ge 1280) {
        # HD, WXGA
        $additionalScale = 1.0
        $resolutionName = "HD/WXGA"
    }
    elseif ($screen.Bounds.Width -ge 1024) {
        # XGA
        $additionalScale = 1.0
        $resolutionName = "XGA"
    }
    elseif ($screen.Bounds.Width -ge 800) {
        # SVGA
        $additionalScale = 0.9
        $resolutionName = "SVGA"
    }
    else {
        # VGA or smaller
        $additionalScale = 0.8
        $resolutionName = "VGA"
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
        # Form dimensions (as percentage of screen)
        FormWidthPercent = 0.70    # 70% of screen width
        FormHeightPercent = 0.80   # 80% of screen height
        MinFormWidth = 1000
        MinFormHeight = 600
        MaxFormWidth = 2400
        MaxFormHeight = 1400

        # Font sizes
        BaseFontSize = 10
        MinFontSize = 9
        TitleFontSize = 14
        ConsoleFontSize = 9
        TableFontSize = 11
        ButtonFontSize = 9

        # Margins and spacing
        Margin = 20
        Spacing = 12
        HeaderHeight = 20
        ButtonAreaHeight = 150
        ProgressAreaHeight = 50

        # Control dimensions
        ProgressBarHeight = 18
        ProgressLabelHeight = 30
        StatusLabelHeight = 25
        AppProgressBarHeight = 12
        ButtonHeight = 75
        RowHeightMultiplier = 2.2
    }

    # Calculate form size as percentage of screen with min/max constraints
    $formWidth = [Math]::Min(
        [Math]::Max(
            [Math]::Floor($screenWidth * $baseDimensions.FormWidthPercent * $scaleFactor),
            $baseDimensions.MinFormWidth
        ),
        $baseDimensions.MaxFormWidth
    )

    $formHeight = [Math]::Min(
        [Math]::Max(
            [Math]::Floor($screenHeight * $baseDimensions.FormHeightPercent * $scaleFactor),
            $baseDimensions.MinFormHeight
        ),
        $baseDimensions.MaxFormHeight
    )

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

    # Create main form with responsive settings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "myTech.Today Application Installer v$script:ScriptVersion"
    $form.ClientSize = New-Object System.Drawing.Size($formWidth, $formHeight)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size($baseDimensions.MinFormWidth, $baseDimensions.MinFormHeight)
    $form.MaximizeBox = $true
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", $normalFontSize)

    # Enable visual styles for modern appearance
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Calculate content area dimensions with scaled values
    $contentTop = $headerHeight
    $contentHeight = $formHeight - $headerHeight - $buttonAreaHeight - $progressAreaHeight - $margin
    $listViewWidth = [Math]::Floor(($formWidth - $margin * 3) * 0.58)  # 58% of width
    $outputWidth = $formWidth - $listViewWidth - $margin * 3

    # Create ListView for applications with responsive sizing
    $script:ListView = New-Object System.Windows.Forms.ListView
    $script:ListView.Location = New-Object System.Drawing.Point($margin, $contentTop)
    $script:ListView.Size = New-Object System.Drawing.Size($listViewWidth, $contentHeight)
    $script:ListView.View = [System.Windows.Forms.View]::Details
    $script:ListView.FullRowSelect = $true
    $script:ListView.GridLines = $true
    $script:ListView.CheckBoxes = $true
    $script:ListView.Sorting = [System.Windows.Forms.SortOrder]::None
    $script:ListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)
    $script:ListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    # Create ImageList to control row height based on scaled font size
    # Row height = font size * row height multiplier for comfortable spacing
    $rowHeight = [Math]::Max([Math]::Round($tableFontSize * $baseDimensions.RowHeightMultiplier), 24)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $script:ListView.SmallImageList = $imageList

    Write-Log "ListView - Font: $tableFontSize pt, Row Height: $rowHeight px" -Level INFO

    # Add columns with optimized widths for readability
    # Proportions: App=22%, Category=12%, Status=12%, Version=10%, Description=42%, Scrollbar=2%
    $colAppWidth = [Math]::Floor($listViewWidth * 0.22)
    $colCategoryWidth = [Math]::Floor($listViewWidth * 0.12)
    $colStatusWidth = [Math]::Floor($listViewWidth * 0.12)
    $colVersionWidth = [Math]::Floor($listViewWidth * 0.10)
    $colDescWidth = [Math]::Floor($listViewWidth * 0.42)

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

    $form.Controls.Add($script:ListView)

    # Create WebBrowser control for HTML output (replaces RichTextBox)
    $script:WebBrowser = New-Object System.Windows.Forms.WebBrowser
    $script:WebBrowser.Location = New-Object System.Drawing.Point(($margin * 2 + $listViewWidth), $contentTop)
    $script:WebBrowser.Size = New-Object System.Drawing.Size($outputWidth, $contentHeight)
    $script:WebBrowser.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
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
    $form.Controls.Add($script:WebBrowser)

    # Calculate progress bar position (above buttons) with scaled dimensions
    $progressTop = $formHeight - $buttonAreaHeight - $progressAreaHeight

    # Apply scaling to progress control dimensions
    $progressBarHeight = [int]($baseDimensions.ProgressBarHeight * $scaleFactor)
    $progressLabelHeight = [int]($baseDimensions.ProgressLabelHeight * $scaleFactor)
    $statusLabelHeight = [int]($baseDimensions.StatusLabelHeight * $scaleFactor)
    $appProgressBarHeight = [int]($baseDimensions.AppProgressBarHeight * $scaleFactor)

    # Create main progress bar with scaled height
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point($margin, $progressTop)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $progressBarHeight)
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:ProgressBar)

    # Create progress label with percentage (scaled font and height)
    $progressLabelFontSize = [Math]::Max($normalFontSize - 1, $baseDimensions.MinFontSize)
    $script:ProgressLabel = New-Object System.Windows.Forms.Label
    $script:ProgressLabel.Text = "0 / 0 applications (0%)"
    $script:ProgressLabel.Location = New-Object System.Drawing.Point($margin, ($progressTop + $progressBarHeight + 4))
    $script:ProgressLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $progressLabelHeight)
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
    $script:StatusLabel.Location = New-Object System.Drawing.Point($margin, $statusLabelTop)
    $script:StatusLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $statusLabelHeight)
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Consolas", $statusLabelFontSize)
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Gray
    $script:StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:StatusLabel.AutoSize = $false
    $script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $form.Controls.Add($script:StatusLabel)

    # Create secondary progress bar for individual app installation (scaled height)
    $appProgressBarTop = $statusLabelTop + $statusLabelHeight + 4
    $script:AppProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:AppProgressBar.Location = New-Object System.Drawing.Point($margin, $appProgressBarTop)
    $script:AppProgressBar.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), $appProgressBarHeight)
    $script:AppProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:AppProgressBar.MarqueeAnimationSpeed = 30
    $script:AppProgressBar.Visible = $false  # Hidden by default
    $script:AppProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:AppProgressBar)

    # Store form dimensions, font sizes, and scaling info for button creation
    $form.Tag = @{
        FormWidth = $formWidth
        FormHeight = $formHeight
        ScaleFactor = $scaleFactor
        NormalFontSize = $normalFontSize
        TitleFontSize = $titleFontSize
        ConsoleFontSize = $consoleFontSize
        TableFontSize = $tableFontSize
        ButtonFontSize = $buttonFontSize
        Margin = $margin
        Spacing = $spacing
        ButtonHeight = [int]($baseDimensions.ButtonHeight * $scaleFactor)
        BaseDimensions = $baseDimensions
    }

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

    # Calculate button width based on longest text with scaled padding
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

    # Add scaled horizontal padding (base 40px scaled)
    $horizontalPadding = [int](40 * $scaleFactor)
    $buttonWidth = [Math]::Ceiling($maxTextWidth) + $horizontalPadding

    # Calculate button Y position (scaled offset from bottom)
    $buttonYOffset = [int](85 * $scaleFactor)
    $buttonY = $formHeight - $buttonYOffset

    # Calculate X positions for each button (left-aligned with scaled spacing)
    $currentX = $margin

    # Refresh button
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $refreshButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $refreshButton.Text = "Refresh Status"
    $refreshButton.Font = $buttonFont
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
    $selectAllButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $selectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectAllButton.Text = "Select All"
    $selectAllButton.Font = $buttonFont
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
    $selectMissingButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $selectMissingButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $selectMissingButton.Text = "Select Missing"
    $selectMissingButton.Font = $buttonFont
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
    $deselectAllButton.Location = New-Object System.Drawing.Point($currentX, $buttonY)
    $deselectAllButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $deselectAllButton.Text = "Deselect All"
    $deselectAllButton.Font = $buttonFont
    $deselectAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $deselectAllButton.Add_Click({
        if ($script:IsClosing) { return }
        Write-Log "User clicked Deselect All button" -Level INFO
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
    $installButton.Add_Click({
        if (-not $script:IsClosing) {
            Write-Log "User clicked Install Selected button" -Level INFO
            Install-SelectedApplications
        }
    })
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

            # Add description
            $item.SubItems.Add($app.Description) | Out-Null

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

    # Get checked items
    $checkedItems = $script:ListView.Items | Where-Object { $_.Checked }

    if ($checkedItems.Count -eq 0) {
        Write-Log "Installation cancelled: No applications selected" -Level INFO
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one application to install.",
            "No Selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # Log which applications were selected
    Write-Log "User selected $($checkedItems.Count) application(s) for installation" -Level INFO
    foreach ($item in $checkedItems) {
        Write-Log "  - Selected: $($item.Text)" -Level INFO
    }

    # Check which apps are already installed
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
    $confirmMessage = ""

    if ($notInstalled.Count -gt 0) {
        $confirmMessage += "New installations ($($notInstalled.Count)):`r`n"
        foreach ($app in $notInstalled) {
            $confirmMessage += "  - $($app.Name)`r`n"
        }
        $confirmMessage += "`r`n"
    }

    if ($alreadyInstalled.Count -gt 0) {
        $confirmMessage += "Already installed - will reinstall ($($alreadyInstalled.Count)):`r`n"
        foreach ($app in $alreadyInstalled) {
            $version = $script:InstalledApps[$app.Name]
            if ($app.Name -eq "O&O ShutUp10") {
                $confirmMessage += "  - $($app.Name) ($version) [Will re-run configuration]`r`n"
            }
            else {
                $confirmMessage += "  - $($app.Name) ($version)`r`n"
            }
        }
        $confirmMessage += "`r`n"
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
    $script:IsInstalling = $true

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

    # Disable buttons during installation
    foreach ($control in $form.Controls) {
        if ($control -is [System.Windows.Forms.Button]) {
            $control.Enabled = $false
        }
    }

    # Reorder checked items to install O&O ShutUp10 first if present
    $itemsToInstall = $checkedItems
    $ooShutUpItem = $itemsToInstall | Where-Object { $_.Tag.Name -eq "O&O ShutUp10" }
    if ($ooShutUpItem) {
        Write-Log "O&O ShutUp10 detected - moving to front of installation queue" -Level INFO
        Write-Output "[i] O&O ShutUp10 will be installed first" -Color ([System.Drawing.Color]::Cyan)
        $otherItems = $itemsToInstall | Where-Object { $_.Tag.Name -ne "O&O ShutUp10" }
        $itemsToInstall = @($ooShutUpItem) + $otherItems
    }

    # Setup progress bar
    $script:ProgressBar.Maximum = $itemsToInstall.Count
    $script:ProgressBar.Value = 0

    Write-Output "`r`n=== Starting Installation ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installing $($itemsToInstall.Count) application(s)..." -Color ([System.Drawing.Color]::Blue)

    $successCount = 0
    $failCount = 0
    $currentIndex = 0
    $completedCount = 0
    $startTime = Get-Date  # Track installation start time
    $installationTimes = @()  # Track individual installation times for ETA

    foreach ($item in $itemsToInstall) {
        $currentIndex++
        $app = $item.Tag

        # Calculate percentage
        $percentComplete = [Math]::Round(($currentIndex / $itemsToInstall.Count) * 100, 1)

        Write-Output "Installing $($app.Name) ($currentIndex of $($itemsToInstall.Count) - $percentComplete%)..." -Color ([System.Drawing.Color]::Blue)

        # Track individual app installation time
        $appStartTime = Get-Date

        # Install application
        $success = Install-Application -App $app

        # Calculate installation time
        $appEndTime = Get-Date
        $appDuration = ($appEndTime - $appStartTime).TotalSeconds
        $installationTimes += $appDuration

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
        $percentComplete = [Math]::Round(($completedCount / $itemsToInstall.Count) * 100, 1)

        # Calculate ETA
        $etaText = ""
        if ($installationTimes.Count -gt 0 -and $completedCount -lt $itemsToInstall.Count) {
            $avgTime = ($installationTimes | Measure-Object -Average).Average
            $remainingApps = $itemsToInstall.Count - $completedCount
            $etaSeconds = $avgTime * $remainingApps
            $etaMinutes = [Math]::Round($etaSeconds / 60, 1)
            $etaText = " | ETA: $etaMinutes min"
        }

        $script:ProgressLabel.Text = "$completedCount / $($itemsToInstall.Count) applications ($percentComplete%)$etaText"

        # Process Windows messages to keep UI responsive
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Reset installation flag
    $script:IsInstalling = $false
    Write-Log "Installation process completed - IsInstalling flag reset" -Level INFO

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
    $completionColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }

    Write-Output "`r`n=== Installation Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installation complete: $successCount succeeded, $failCount failed" -Color $completionColor
    Write-Output "Success: $successCount | Failed: $failCount | Time: $totalMinutes minutes" -Color $completionColor

    # Update status label
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "[COMPLETE] All installations complete! ($successCount succeeded, $failCount failed, $totalMinutes min)"
        $script:StatusLabel.ForeColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Show Windows Toast notification
    $toastTitle = "Installation Complete"
    $toastMessage = "Successfully installed $successCount of $($checkedItems.Count) applications in $totalMinutes minutes"
    if ($failCount -gt 0) {
        $toastMessage += "`n$failCount installation(s) failed"
    }
    Show-ToastNotification -Title $toastTitle -Message $toastMessage -Type $(if ($failCount -eq 0) { 'Success' } else { 'Warning' })

    [System.Windows.Forms.MessageBox]::Show(
        "Installation complete!`n`nSuccessful: $successCount`nFailed: $failCount`nTotal Time: $totalMinutes minutes",
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


