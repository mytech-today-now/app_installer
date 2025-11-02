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
        $script:StatusLabel.Text = "🔍 Preparing to install $($App.Name)..."
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::DodgerBlue
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        # Check if custom script exists
        $scriptPath = Join-Path $script:AppsPath $App.ScriptName

        if (Test-Path $scriptPath) {
            Write-Log "Using custom script: $scriptPath" -Level INFO
            Write-Output "  Using custom script..." -Color ([System.Drawing.Color]::Gray)

            # Update status
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "📦 Running custom installation script for $($App.Name)..."
                [System.Windows.Forms.Application]::DoEvents()
            }

            & $scriptPath

            # Hide secondary progress bar
            if ($script:AppProgressBar) {
                $script:AppProgressBar.Visible = $false
            }

            # Update status - success
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = "✅ $($App.Name) installed successfully!"
                $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                [System.Windows.Forms.Application]::DoEvents()
            }

            return $true
        }
        elseif ($App.WingetId) {
            # Use winget for installation
            if (Test-WingetAvailable) {
                Write-Log "Installing via winget: $($App.WingetId)" -Level INFO
                Write-Output "  Installing via winget..." -Color ([System.Drawing.Color]::Gray)

                # Update status - downloading
                if ($script:StatusLabel) {
                    $script:StatusLabel.Text = "⬇️ Downloading $($App.Name)..."
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
                        $script:StatusLabel.Text = "✅ $($App.Name) installed successfully!"
                        $script:StatusLabel.ForeColor = [System.Drawing.Color]::Green
                        [System.Windows.Forms.Application]::DoEvents()
                    }

                    return $true
                }
                else {
                    Write-Log "$($App.Name) installation failed with exit code: $LASTEXITCODE" -Level ERROR
                    Write-Output "  [X] Installation failed with exit code: $LASTEXITCODE" -Color ([System.Drawing.Color]::Red)
                    Write-Output "      $result" -Color ([System.Drawing.Color]::Red)

                    # Hide secondary progress bar
                    if ($script:AppProgressBar) {
                        $script:AppProgressBar.Visible = $false
                    }

                    # Update status - failed
                    if ($script:StatusLabel) {
                        $script:StatusLabel.Text = "❌ $($App.Name) installation failed (Exit code: $LASTEXITCODE)"
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
                    $script:StatusLabel.Text = "❌ Winget not available"
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
                $script:StatusLabel.Text = "⚠️ No installation method available for $($App.Name)"
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
            $script:StatusLabel.Text = "❌ Error installing $($App.Name): $($_.Exception.Message)"
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.Application]::DoEvents()
        }

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
    # Table font is one size larger than normal
    $tableFontSize = $normalFontSize + 1
    $script:ListView.Font = New-Object System.Drawing.Font("Segoe UI", $tableFontSize)
    $script:ListView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    # Create ImageList to control row height based on font size
    # Row height = font size * 2.2 for comfortable spacing
    $rowHeight = [Math]::Max([Math]::Round($tableFontSize * 2.2), 24)
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(1, $rowHeight)
    $script:ListView.SmallImageList = $imageList

    Write-Log "ListView row height set to: $rowHeight px (based on table font size: $tableFontSize pt)" -Level INFO

    # Add columns with optimized widths for readability
    # Adjusted proportions: App=22%, Category=12%, Status=12%, Version=10%, Description=42%
    # Remaining 2% for scrollbar and margins
    $colAppWidth = [Math]::Floor($listViewWidth * 0.22)
    $colCategoryWidth = [Math]::Floor($listViewWidth * 0.12)
    $colStatusWidth = [Math]::Floor($listViewWidth * 0.12)
    $colVersionWidth = [Math]::Floor($listViewWidth * 0.10)
    $colDescWidth = [Math]::Floor($listViewWidth * 0.42)

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

    $colDescription = New-Object System.Windows.Forms.ColumnHeader
    $colDescription.Text = "Description"
    $colDescription.Width = $colDescWidth

    # Add columns to ListView
    $script:ListView.Columns.AddRange(@($colAppName, $colCategory, $colStatus, $colVersion, $colDescription))

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

    # Initialize HTML content with myTech.Today marketing information
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
            font-size: 21px;
            line-height: 1.6;
        }
        h1 {
            color: #4ec9b0;
            font-size: 29px;
            margin: 10px 0;
            border-bottom: 2px solid #4ec9b0;
            padding-bottom: 5px;
        }
        h2 {
            color: #569cd6;
            font-size: 23px;
            margin: 8px 0;
        }
        p {
            font-size: 21px;
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
            font-size: 21px;
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
            font-size: 32px;
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
        }
        /* Console output styling - monospace font for terminal-like appearance */
        .console-line {
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 19px;
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

    # Calculate progress bar position (above buttons)
    $progressTop = $formHeight - $buttonAreaHeight - $progressAreaHeight

    # Create progress bar (more compact)
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point($margin, $progressTop)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 18)  # Reduced from 25 to 18
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:ProgressBar)

    # Create progress label with percentage
    $script:ProgressLabel = New-Object System.Windows.Forms.Label
    $script:ProgressLabel.Text = "0 / 0 applications (0%)"
    $script:ProgressLabel.Location = New-Object System.Drawing.Point($margin, ($progressTop + 22))
    $script:ProgressLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 30)  # Increased from 25 to 30 to prevent descender clipping
    $script:ProgressLabel.Font = New-Object System.Drawing.Font("Segoe UI", ([Math]::Max($normalFontSize - 1, 9)))
    $script:ProgressLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:ProgressLabel.AutoSize = $false
    $script:ProgressLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft  # Changed from MiddleLeft to TopLeft to prevent descender clipping
    $form.Controls.Add($script:ProgressLabel)

    # Create status label for current operation
    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Text = "Ready to install applications"
    $script:StatusLabel.Location = New-Object System.Drawing.Point($margin, ($progressTop + 52))
    $script:StatusLabel.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 25)
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Consolas", ([Math]::Max($normalFontSize - 2, 8)))
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::Gray
    $script:StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:StatusLabel.AutoSize = $false
    $script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $form.Controls.Add($script:StatusLabel)

    # Create secondary progress bar for individual app installation (NEW - Phase 2)
    $script:AppProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:AppProgressBar.Location = New-Object System.Drawing.Point($margin, ($progressTop + 77))
    $script:AppProgressBar.Size = New-Object System.Drawing.Size(($formWidth - $margin * 2), 12)  # Smaller than main progress bar
    $script:AppProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:AppProgressBar.MarqueeAnimationSpeed = 30
    $script:AppProgressBar.Visible = $false  # Hidden by default
    $script:AppProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($script:AppProgressBar)

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
    # Button font is one size smaller than normal
    $buttonFontSize = [Math]::Max($normalFontSize - 1, 8)
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
    $startTime = Get-Date  # Track installation start time
    $installationTimes = @()  # Track individual installation times for ETA

    foreach ($item in $checkedItems) {
        $currentIndex++
        $app = $item.Tag

        # Calculate percentage
        $percentComplete = [Math]::Round(($currentIndex / $checkedItems.Count) * 100, 1)

        Write-Output "Installing $($app.Name) ($currentIndex of $($checkedItems.Count) - $percentComplete%)..." -Color ([System.Drawing.Color]::Blue)

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
        $percentComplete = [Math]::Round(($completedCount / $checkedItems.Count) * 100, 1)

        # Calculate ETA
        $etaText = ""
        if ($installationTimes.Count -gt 0 -and $completedCount -lt $checkedItems.Count) {
            $avgTime = ($installationTimes | Measure-Object -Average).Average
            $remainingApps = $checkedItems.Count - $completedCount
            $etaSeconds = $avgTime * $remainingApps
            $etaMinutes = [Math]::Round($etaSeconds / 60, 1)
            $etaText = " | ETA: $etaMinutes min"
        }

        $script:ProgressLabel.Text = "$completedCount / $($checkedItems.Count) applications ($percentComplete%)$etaText"

        # Process Windows messages to keep UI responsive
        [System.Windows.Forms.Application]::DoEvents()
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
    $completionColor = if ($failCount -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Orange }

    Write-Output "`r`n=== Installation Complete ===" -Color ([System.Drawing.Color]::Cyan)
    Write-Output "Installation complete: $successCount succeeded, $failCount failed" -Color $completionColor
    Write-Output "Success: $successCount | Failed: $failCount | Time: $totalMinutes minutes" -Color $completionColor

    # Update status label
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "✅ All installations complete! ($successCount succeeded, $failCount failed, $totalMinutes min)"
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
            <strong>📦 Total Applications Available:</strong> $totalApps
        </p>
        <p class="info" style="margin: 5px 0; font-size: 23px;">
            <strong>✅ Currently Installed:</strong> $installedCount
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


