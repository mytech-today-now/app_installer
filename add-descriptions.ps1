<#
.SYNOPSIS
    Adds descriptions to all applications in the registry.

.DESCRIPTION
    This script contains all application descriptions to be added to both
    install-gui.ps1 and install.ps1 files.

.NOTES
    File Name      : add-descriptions.ps1
    Author         : myTech.Today
    Version        : 1.0.0
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
#>

# Application descriptions mapping
$descriptions = @{
    # Browsers
    "Google Chrome" = "Fast, secure web browser by Google"
    "Brave Browser" = "Privacy-focused browser with ad blocking"
    "Firefox" = "Open-source browser with privacy features"
    "Microsoft Edge" = "Chromium-based browser by Microsoft"
    "Vivaldi" = "Highly customizable browser for power users"
    "Opera" = "Feature-rich browser with built-in VPN"
    "Opera GX" = "Gaming browser with resource limiter"
    "LibreWolf" = "Privacy-hardened Firefox fork"
    "Tor Browser" = "Anonymous browsing via Tor network"
    "Waterfox" = "Privacy-focused Firefox-based browser"
    "Chromium" = "Open-source base for Chrome"
    "Pale Moon" = "Lightweight Firefox-based browser"
    
    # Development Tools
    "Visual Studio Code" = "Powerful code editor with extensions"
    "Notepad++" = "Lightweight text and code editor"
    "Git" = "Distributed version control system"
    "GitHub Desktop" = "GUI for Git and GitHub workflows"
    "Python" = "Popular programming language runtime"
    "Node.js" = "JavaScript runtime for server-side apps"
    "Docker Desktop" = "Container platform for development"
    "Postman" = "API development and testing tool"
    "Insomnia" = "REST and GraphQL API client"
    "Sublime Text" = "Fast, sophisticated text editor"
    "Geany" = "Lightweight IDE with GTK toolkit"
    "NetBeans IDE" = "IDE for Java and web development"
    "IntelliJ IDEA Community" = "Java IDE by JetBrains"
    "PyCharm Community" = "Python IDE by JetBrains"
    "Eclipse IDE" = "Popular Java development environment"
    "Atom Editor" = "Hackable text editor by GitHub"
    "Brackets" = "Modern editor for web design"
    "WinSCP" = "SFTP and FTP client for Windows"
    "FileZilla" = "Fast and reliable FTP client"
    "DBeaver" = "Universal database management tool"
    "HeidiSQL" = "Lightweight MySQL/MariaDB client"
    "Vagrant" = "Development environment manager"
    "Windows Terminal" = "Modern terminal with tabs and themes"
    
    # Productivity
    "LibreOffice" = "Free office suite with Writer, Calc, Impress"
    "Apache OpenOffice" = "Open-source office productivity suite"
    "7-Zip" = "High-compression file archiver"
    "Adobe Acrobat Reader" = "PDF viewer and form filler"
    "Foxit PDF Reader" = "Fast, lightweight PDF reader"
    "Sumatra PDF" = "Minimalist PDF and eBook reader"
    "Obsidian" = "Knowledge base with markdown linking"
    "Joplin" = "Open-source note-taking app"
    "Notion" = "All-in-one workspace for notes and docs"
    "Calibre" = "eBook library management and conversion"
    "Zotero" = "Research citation and bibliography manager"
    "FreeMind" = "Mind mapping and brainstorming tool"
    "XMind" = "Professional mind mapping software"
    
    # Media & Creative
    "VLC Media Player" = "Versatile media player for all formats"
    "OBS Studio" = "Live streaming and screen recording"
    "GIMP" = "Advanced image editing and manipulation"
    "Audacity" = "Multi-track audio editor and recorder"
    "Handbrake" = "Video transcoder and converter"
    "OpenShot" = "Easy-to-use video editor"
    "Kdenlive" = "Professional video editing suite"
    "Shotcut" = "Cross-platform video editor"
    "ClipGrab" = "Video downloader and converter"
    "Inkscape" = "Vector graphics editor"
    "Paint.NET" = "Simple yet powerful image editor"
    "Krita" = "Digital painting and illustration tool"
    "Avidemux" = "Simple video editing and filtering"
    "MPC-HC" = "Lightweight media player"
    "Foobar2000" = "Advanced audio player and organizer"
    "FFmpeg" = "Multimedia framework for conversion"
    "OpenToonz" = "2D animation production software"
    "darktable" = "Photography workflow and RAW editor"
    "RawTherapee" = "RAW image processing program"
    "Spotify" = "Music streaming service"
    "iTunes" = "Media player and library manager"
    "MediaInfo" = "Technical metadata viewer for media files"
    "MKVToolNix" = "Matroska video file editor"
    
    # Utilities
    "PowerToys" = "Windows system utilities by Microsoft"
    "Everything" = "Instant file search engine"
    "WinDirStat" = "Disk usage statistics viewer"
    "TreeSize Free" = "Disk space manager and analyzer"
    "CCleaner" = "System cleaner and optimizer"
    "Greenshot" = "Screenshot tool with annotations"
    "ShareX" = "Screen capture and file sharing"
    "Bulk Rename Utility" = "Advanced file renaming tool"
    "Revo Uninstaller" = "Complete software removal tool"
    "Recuva" = "File recovery and undelete utility"
    "Speccy" = "System information and diagnostics"
    "HWiNFO" = "Hardware analysis and monitoring"
    "Core Temp" = "CPU temperature monitor"
    "GPU-Z" = "Graphics card information tool"
    "CrystalDiskInfo" = "Hard drive health monitor"
    "Sysinternals Suite" = "Advanced Windows troubleshooting tools"
    "AngryIP Scanner" = "Fast network IP scanner"
    "Bitvise SSH Client" = "SSH and SFTP client for Windows"
    "Belarc Advisor" = "System profile and security status"
    "O&O ShutUp10" = "Windows privacy settings manager"
    "FileMail Desktop" = "Large file transfer service"
    
    # Security
    "Bitwarden" = "Open-source password manager"
    "KeePass" = "Secure password database manager"
    "VeraCrypt" = "Disk encryption software"
    "Malwarebytes" = "Anti-malware and threat protection"
    "Avira Security" = "Antivirus and security suite"
    "Kaspersky Security Cloud" = "Cloud-based antivirus protection"
    "AVG AntiVirus Free" = "Free antivirus protection"
    "Avast Free Antivirus" = "Comprehensive free antivirus"
    "Sophos Home" = "Enterprise-grade home security"
    
    # Communication
    "Discord" = "Voice, video, and text chat platform"
    "Zoom" = "Video conferencing and meetings"
    "Microsoft Teams" = "Collaboration and communication hub"
    "Skype" = "Video calls and instant messaging"
    "Slack" = "Team collaboration and messaging"
    "Telegram Desktop" = "Fast, secure messaging app"
    "Signal" = "Privacy-focused encrypted messaging"
    "Thunderbird" = "Open-source email client"
    
    # 3D & CAD
    "Blender" = "3D modeling, animation, and rendering"
    "FreeCAD" = "Parametric 3D CAD modeler"
    "LibreCAD" = "2D CAD drafting application"
    "KiCad" = "Electronic design automation suite"
    "OpenSCAD" = "Script-based 3D CAD modeler"
    "Wings 3D" = "Polygon mesh modeling tool"
    "Sweet Home 3D" = "Interior design and floor planning"
    
    # Networking
    "Wireshark" = "Network protocol analyzer"
    "Nmap" = "Network discovery and security scanner"
    "Zenmap" = "GUI for Nmap security scanner"
    "PuTTY" = "SSH and telnet client"
    "Advanced IP Scanner" = "Fast network scanner for Windows"
    "Fing CLI" = "Network scanning and troubleshooting"
    
    # Runtime Environments
    "Java Runtime Environment" = "Java application runtime"
    ".NET Desktop Runtime 6" = ".NET 6 desktop application runtime"
    ".NET Desktop Runtime 8" = ".NET 8 desktop application runtime"
    "Visual C++ Redistributable" = "Microsoft C++ runtime libraries"
    
    # Writing & Screenwriting
    "Trelby" = "Screenplay writing software"
    "KIT Scenarist" = "Screenwriting and story development"
    "Storyboarder" = "Storyboard creation tool"
    "FocusWriter" = "Distraction-free writing environment"
    "Manuskript" = "Novel writing and organization tool"
    "yWriter" = "Word processor for novelists"
    
    # Gaming
    "Steam" = "Digital game distribution platform"
    "Epic Games Launcher" = "Epic Games store and launcher"
    "GOG Galaxy" = "DRM-free game launcher"
    "EA App" = "Electronic Arts game platform"
    
    # Cloud Storage
    "Google Drive" = "Cloud storage and file sync by Google"
    "Dropbox" = "Cloud file storage and sharing"
    "OneDrive" = "Microsoft cloud storage service"
    "MEGA" = "Secure cloud storage with encryption"
    
    # Remote Desktop
    "TeamViewer" = "Remote access and support software"
    "AnyDesk" = "Fast remote desktop application"
    "Chrome Remote Desktop" = "Remote access via Chrome browser"
    "TightVNC" = "Remote desktop control software"
    
    # Backup & Recovery
    "Veeam Agent FREE" = "Free backup and recovery solution"
    "Macrium Reflect Free" = "Disk imaging and cloning tool"
    "EaseUS Todo Backup Free" = "Backup and disaster recovery"
    "Duplicati" = "Encrypted backup to cloud storage"
    
    # Education
    "Anki" = "Flashcard-based learning system"
    "GeoGebra" = "Interactive math and geometry software"
    "Stellarium" = "Planetarium and astronomy software"
    "MuseScore" = "Music notation and composition"
    
    # Finance
    "GnuCash" = "Personal and small business accounting"
    "HomeBank" = "Personal finance management"
    "Money Manager Ex" = "Easy-to-use finance tracker"
    
    # Shortcuts & Maintenance
    "Grok AI Shortcuts" = "Quick access to Grok AI assistant"
    "ChatGPT Shortcuts" = "Quick access to ChatGPT"
    "dictation.io Shortcut" = "Web-based voice dictation tool"
    "Uninstall McAfee" = "Remove McAfee software completely"
}

Write-Host "Application descriptions loaded: $($descriptions.Count) apps" -ForegroundColor Green
Write-Host ""
Write-Host "To use these descriptions, update the Applications array in both:" -ForegroundColor Cyan
Write-Host "  - install-gui.ps1" -ForegroundColor Yellow
Write-Host "  - install.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "Add Description property to each PSCustomObject:" -ForegroundColor Cyan
Write-Host '  [PSCustomObject]@{ Name = "App Name"; ...; Description = "Description here" }' -ForegroundColor Gray

