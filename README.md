# App Installer - myTech.Today

**Version:** 1.3.7
**Author:** myTech.Today
**License:** All rights reserved

## Overview

The **App Installer** is a comprehensive PowerShell application installer system designed for automated Windows setup. It provides both a modern **graphical user interface (GUI)** and a traditional **command-line interface** for installing and managing **93 essential applications** with real-time status tracking, version detection, and centralized logging.

![App Installer GUI](https://mytech.today/wp-content/uploads/2025/10/summary_tab.jpeg)

## Features

### GUI Features (install-gui.ps1)
✅ **Modern Windows Forms Interface** - Professional GUI with responsive design and DPI scaling
✅ **Real-Time Progress Tracking** - Dynamic progress bar and status updates as you select apps
✅ **Category Organization** - Applications grouped into 13 categories for easy browsing
✅ **Checkbox Selection** - Select individual apps, all apps, or only missing apps
✅ **Live Status Display** - See installation status, version numbers, and progress in real-time
✅ **HTML Console Output** - Professional, color-coded installation logs in right panel
✅ **Marketing Information** - Company info and service details displayed in HTML panel
✅ **Responsive Layout** - Adapts to different screen sizes and resolutions
✅ **Professional Buttons** - Standard Windows-style buttons with proper spacing

### Core Features (Both Versions)
✅ **Version Detection** - Automatically detects installed applications via winget and registry
✅ **Selective Installation** - Install individual apps, all apps, or only missing apps
✅ **Centralized Logging** - All activities logged to `C:\mytech.today\logs\` in markdown format
✅ **winget Integration** - Leverages Windows Package Manager for 90+ applications
✅ **Custom Installers** - Specialized scripts for apps not available via winget
✅ **Error Handling** - Comprehensive error handling with fallback solutions
✅ **Silent Installation** - Most apps install silently without user interaction
✅ **Administrator Privileges** - Automatic elevation and privilege checking

## Supported Applications (93)

### Browsers (8)
- Google Chrome, Brave Browser, Firefox, Vivaldi, Opera, LibreWolf, Tor Browser, Waterfox

### Development (17)
- Notepad++, Git, Python, Node.js, Docker Desktop, Sublime Text, Geany, NetBeans IDE
- IntelliJ IDEA Community, FileZilla, Visual Studio Code, Postman, PyCharm Community
- Eclipse IDE, Atom Editor, Brackets, Vagrant

### Productivity (9)
- LibreOffice, Obsidian, Joplin, Foxit PDF Reader, Sumatra PDF, Notion
- 7-Zip, Adobe Acrobat Reader, Apache OpenOffice

### Media (19)
- OBS Studio, GIMP, Audacity, Handbrake, OpenShot, ClipGrab, Inkscape, Paint.NET
- Avidemux, MPC-HC, Foobar2000, VLC Media Player, FFmpeg, Krita, OpenToonz
- Kdenlive, Shotcut, darktable, RawTherapee

### Utilities (17)
- AngryIP Scanner, CCleaner, Bitvise SSH Client, Belarc Advisor, O&O ShutUp10
- FileMail Desktop, PowerToys, Everything, Greenshot, Bulk Rename Utility
- Revo Uninstaller, WinDirStat, Core Temp, GPU-Z, CrystalDiskInfo
- Sysinternals Suite, winget Auto-Update

### Security (6)
- Avira Antivirus, Kaspersky Security Cloud, AVG AntiVirus Free, Avast Free Antivirus
- Malwarebytes, Bitwarden

### Communication (3)
- Telegram Desktop, Signal, Thunderbird

### 3D & CAD (4)
- Blender, FreeCAD, LibreCAD, KiCad

### Networking (3)
- Nmap, Wireshark, Zenmap

### Writing (3)
- Trelby, KIT Scenarist, Storyboarder

### Shortcuts (3)
- Grok AI (Desktop & Start Menu)
- ChatGPT (Desktop & Start Menu)
- dictation.io (Desktop & Start Menu)

### Runtime (1)
- Java Runtime Environment

### Maintenance (1)
- Uninstall McAfee Products

## Requirements

- **Operating System:** Windows 10 (1809+), Windows 11, Windows Server 2016+
- **PowerShell:** 5.1 or later (PowerShell 7.2+ recommended)
- **Privileges:** Administrator rights required
- **winget:** Windows Package Manager (recommended, installed by default on Windows 11)
- **.NET Framework:** 4.7.2 or later (for GUI version)

## Installation

1. **Clone or download** the repository:
   ```powershell
   git clone https://github.com/mytech-today-now/PowerShellScripts.git
   cd PowerShellScripts\app_installer
   ```

2. **Ensure winget is installed** (Windows 11 has it by default):
   - For Windows 10: Install "App Installer" from Microsoft Store
   - Verify: `winget --version`

3. **Run as Administrator**:

   **GUI Version (Recommended):**
   ```powershell
   .\install-gui.ps1
   ```

   **Command-Line Version:**
   ```powershell
   .\install.ps1
   ```

## Usage

### GUI Mode (install-gui.ps1) - Recommended

Launch the graphical interface:

```powershell
.\install-gui.ps1
```

**GUI Features:**
- **Application Table** - Browse all 93 applications with checkboxes
- **Category Grouping** - Applications organized by category
- **Status Column** - Shows "Installed" with version or "Not Installed"
- **Progress Tracking** - Real-time progress: "0 / 5 applications" updates as you select
- **Buttons:**
  - **Refresh Status** - Re-scan for installed applications
  - **Select All** - Select all 93 applications
  - **Select Missing** - Select only applications not currently installed
  - **Deselect All** - Clear all selections
  - **Install Selected** - Install checked applications
  - **Exit** - Close the application

**Progress Display:**
- When you select apps: Shows "0 / X applications" (X = number selected)
- During installation: Shows "Y / X applications" (Y = completed, X = total)
- Progress bar fills as each application installs

### Command-Line Mode (install.ps1)

**Interactive Menu:**
```powershell
.\install.ps1
```

**Menu Options:**
- **1-93:** Install individual application by number
- **A:** Install all applications
- **M:** Install missing applications only
- **S/R:** Show/Refresh status
- **Q:** Quit

**Command-Line Parameters:**

**Install all applications:**
```powershell
.\install.ps1 -Action InstallAll
```

**Install only missing applications:**
```powershell
.\install.ps1 -Action InstallMissing
```

**Show status only:**
```powershell
.\install.ps1 -Action Status
```

**Install specific application:**
```powershell
.\install.ps1 -AppName "Chrome"
```

## Directory Structure

```
app_installer/
├── install-gui.ps1                  # GUI-based installer (recommended)
├── install.ps1                      # Command-line menu-driven installer
├── apps/                            # Individual app installation scripts (93 total)
│   ├── chrome.ps1                   # (Uses winget)
│   ├── brave.ps1                    # (Uses winget)
│   ├── firefox.ps1                  # (Uses winget)
│   ├── vscode.ps1                   # (Uses winget)
│   ├── python.ps1                   # (Uses winget)
│   ├── docker.ps1                   # (Uses winget)
│   ├── obs.ps1                      # (Uses winget)
│   ├── belarc.ps1                   # Custom installer
│   ├── shutup10.ps1                 # Custom installer
│   ├── filemail.ps1                 # Custom installer
│   ├── grok-shortcuts.ps1           # Creates shortcuts
│   ├── chatgpt-shortcuts.ps1        # Creates shortcuts
│   ├── dictation-shortcut.ps1       # Creates shortcuts
│   ├── uninstall-mcafee.ps1         # McAfee removal tool
│   └── ... (89 more scripts)
├── README.md                        # This file
├── CHANGELOG.md                     # Version history
└── ai_prompts/
    └── prompt.01.md                 # Original requirements
```

## Logging

All activities are logged to:
```
C:\mytech.today\logs\install-yyyy-MM.md
```

**Log Format:** Markdown table with icons
**Log Rotation:** Monthly (one file per month)
**Log Levels:** ℹ️ INFO, ⚠️ WARNING, ❌ ERROR, ✅ SUCCESS

**Example Log Entry:**
```markdown
| 2025-11-02 10:30:00 | ✅ **SUCCESS** | Google Chrome installed successfully |
```

## How It Works

### Application Registry

Both scripts maintain an internal registry of all 93 supported applications with:
- **Name:** Display name
- **ScriptName:** Individual installation script filename
- **WingetId:** Windows Package Manager ID (if available)
- **Category:** Application category for organization

### Installation Process

1. **Detection:** Checks if application is already installed via winget or registry
2. **Method Selection:**
   - If custom script exists in `apps/` folder → Use custom script
   - If WingetId is defined → Use `winget install`
   - Otherwise → Display warning
3. **Execution:** Run installation with silent/automated parameters
4. **Logging:** Log all activities to centralized log file
5. **Status:** Display success/failure with color-coded output

### Version Detection

- **Primary:** Uses `winget list` for fast, accurate detection
- **Fallback:** Checks Windows registry for installed programs
- **Display:** Shows version number or "Installed" if version unavailable





## Customization

### Adding New Applications

1. **Add to Application Registry** in `install-gui.ps1` or `install.ps1`:
   ```powershell
   [PSCustomObject]@{
       Name = "MyApp"
       ScriptName = "myapp.ps1"
       WingetId = "Publisher.MyApp"
       Category = "Utilities"
   }
   ```

2. **Create Custom Script** (optional) in `apps/myapp.ps1`:
   ```powershell
   # Custom installation logic
   Write-Host "Installing MyApp..." -ForegroundColor Cyan
   winget install --id Publisher.MyApp --silent --accept-package-agreements --accept-source-agreements
   ```

3. **Test Installation**:
   ```powershell
   .\install-gui.ps1
   ```

### Modifying Categories

Edit the `Category` property in the application registry to organize apps differently. Available categories:
- Browsers, Development, Productivity, Media, Utilities, Security
- Communication, 3D & CAD, Networking, Writing, Shortcuts, Runtime, Maintenance

## Troubleshooting

### winget Not Available

**Error:** "winget is not available on this system"

**Solutions:**
- Install "App Installer" from Microsoft Store
- Update Windows to latest version
- Verify: `winget --version`
- Restart PowerShell after installation

### Installation Fails

**Error:** "Installation failed. Check log for details."

**Solutions:**
1. Check log file: `C:\mytech.today\logs\install-yyyy-MM.md`
2. Verify internet connection
3. Run as Administrator
4. Try manual installation of specific app
5. Check if antivirus is blocking installation
6. Ensure winget is up to date: `winget upgrade --id Microsoft.Winget.Source`

### Application Not Detected

**Issue:** Installed app shows as "Not Installed"

**Causes:**
- App installed via portable version
- App installed in non-standard location
- Registry entry doesn't match detection pattern
- winget database not updated

**Solutions:**
- Click "Refresh Status" button in GUI
- Restart the application
- Detection is informational only; app will still function

### GUI Not Displaying Correctly

**Issue:** Text too small, buttons clipped, or layout issues

**Solutions:**
- Ensure .NET Framework 4.7.2 or later is installed
- Check Windows display scaling settings
- Try running on different monitor if using multi-monitor setup
- GUI automatically adapts to DPI scaling

## Best Practices

✅ **Run as Administrator** - Required for most installations
✅ **Check winget availability** - Ensures smooth installation
✅ **Review logs** - Check `C:\mytech.today\logs\` for details
✅ **Install missing only** - Saves time on already-configured systems
✅ **Restart after major installs** - Some apps (Docker, Python) require restart
✅ **Use GUI version** - More user-friendly and provides better feedback
✅ **Select apps carefully** - Don't install everything if you don't need it

## Security Considerations

- All downloads use HTTPS
- winget packages are verified by Microsoft
- Custom scripts download from official sources only
- McAfee removal uses official MCPR tool
- No credentials or sensitive data stored
- All installations run with user consent
- Logs contain no sensitive information

## Recent Updates (v1.3.7)

### GUI Improvements
- ✅ Dynamic progress tracking - Shows "0 / X applications" as you select
- ✅ Increased HTML panel font sizes for better readability (14px → 18px)
- ✅ Fixed progress label text clipping (descenders now fully visible)
- ✅ Improved button layout with proper spacing and sizing
- ✅ Real-time status updates during installation
- ✅ Professional Windows Forms design with DPI scaling

### Application Additions
- ✅ Expanded from 27 to 93 applications
- ✅ Added 13 categories for better organization
- ✅ New categories: Communication, 3D & CAD, Networking, Writing, Runtime

### Bug Fixes
- ✅ Fixed Brave Browser detection issue
- ✅ Fixed button text truncation
- ✅ Fixed progress bar not updating correctly
- ✅ Improved version detection accuracy

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly on Windows 10 and Windows 11
4. Update documentation if adding new features
5. Submit a pull request with detailed description

## Support

For issues, questions, or contributions:
- **GitHub Issues:** https://github.com/mytech-today-now/PowerShellScripts/issues
- **Documentation:** See `.augment/` folder for development guidelines
- **Company Website:** https://mytech.today

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

**Recent Versions:**
- **v1.3.7** - GUI improvements, dynamic progress tracking, font size increases
- **v1.3.0** - Added 30+ new applications, expanded to 93 total
- **v1.2.0** - Introduced GUI version (install-gui.ps1)
- **v1.0.0** - Initial release with 27 applications

## License

Copyright (c) 2025 myTech.Today. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution, or use is strictly prohibited.

## Author

**myTech.Today**
Professional IT Services - Serving the Midwest
https://github.com/mytech-today-now/PowerShellScripts

**Service Area:**
- Chicagoland, IL
- Southern Wisconsin
- Northern Indiana
- Southern Michigan

**Expertise:**
- 20+ years of IT experience
- Windows automation and deployment
- PowerShell scripting and development
- System administration and support

---

**Last Updated:** 2025-11-02
**Version:** 1.3.7
**Maintained by:** myTech.Today
