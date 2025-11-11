# App Installer - myTech.Today

**Version:** 1.4.1 (GUI) / 1.5.3 (CLI)
**Author:** myTech.Today
**License:** All rights reserved

## Overview

The **App Installer** is a comprehensive PowerShell application installer system designed for automated Windows setup. It provides both a modern **graphical user interface (GUI)** and a traditional **command-line interface** for installing and managing **212 essential applications** with real-time status tracking, version detection, and centralized logging.

![App Installer GUI](https://mytech.today/wp-content/uploads/2025/11/install-gui.ps1_.jpeg)

## Features

### GUI Features (install-gui.ps1)

✅ **Modern Windows Forms Interface** - Professional GUI with responsive design and DPI scaling
✅ **Responsive GUI Helper** - Centralized DPI scaling from GitHub for multi-monitor and high-DPI support
✅ **Generic Logging Module** - Centralized logging system with monthly rotation and markdown format
✅ **Real-Time Search & Filter** - Instantly filter 271 applications by name, category, or description
✅ **Real-Time Progress Tracking** - Dynamic progress bar and status updates as you select apps
✅ **Category Organization** - Applications grouped into 13 categories for easy browsing
✅ **Checkbox Selection** - Select individual apps, all apps, or only missing apps
✅ **Export/Import Profiles** - Save and load application selections for backup or deployment
✅ **Uninstall Applications** - Remove installed applications with confirmation and progress tracking
✅ **Live Status Display** - See installation status, version numbers, and progress in real-time
✅ **HTML Console Output** - Professional, color-coded installation logs in right panel
✅ **Marketing Information** - Company info and service details displayed in HTML panel
✅ **Responsive Layout** - Adapts to different screen sizes and resolutions (VGA to 8K UHD)
✅ **Professional Buttons** - Standard Windows-style buttons with proper spacing

### Core Features (Both Versions)

✅ **Version Detection** - Automatically detects installed applications via winget and registry
✅ **Selective Installation** - Install individual apps, all apps, or only missing apps
✅ **Generic Logging Module** - Centralized logging with monthly rotation (scriptname-yyyy-MM.md format)
✅ **Centralized Logging** - All activities logged to `C:\mytech.today\logs\` in markdown table format
✅ **winget Integration** - Leverages Windows Package Manager for 90+ applications
✅ **Custom Installers** - Specialized scripts for apps not available via winget
✅ **Error Handling** - Comprehensive error handling with fallback solutions
✅ **Silent Installation** - Most apps install silently without user interaction
✅ **Administrator Privileges** - Automatic elevation and privilege checking

## Supported Applications (212)

### Browsers (15)
- Google Chrome, Brave Browser, Firefox, Vivaldi, Opera, LibreWolf, Tor Browser, Waterfox
- Microsoft Edge, Chromium, Arc Browser, Ungoogled Chromium, Midori Browser, Min Browser, Floorp

### Development (26)
- Notepad++, Git, Python, Node.js, Docker Desktop, Sublime Text, Geany, NetBeans IDE
- IntelliJ IDEA Community, FileZilla, Visual Studio Code, Postman, PyCharm Community
- Eclipse IDE, Atom Editor, Brackets, Vagrant, Android Studio, RStudio, Rider
- DataGrip, WebStorm, CLion, GoLand, Vim, CMake, Lazygit

### Productivity (16)
- LibreOffice, Obsidian, Joplin, Foxit PDF Reader, Sumatra PDF, Notion
- 7-Zip, Adobe Acrobat Reader, Apache OpenOffice, Calibre, Zotero, Trello
- WPS Office, PDF24 Creator, Typora, AnyDesk

### Media (26)
- OBS Studio, GIMP, Audacity, Handbrake, OpenShot, ClipGrab, Inkscape, Paint.NET
- Avidemux, MPC-HC, Foobar2000, VLC Media Player, FFmpeg, Krita, OpenToonz
- Kdenlive, Shotcut, darktable, RawTherapee, Spotify, iTunes, AIMP
- DaVinci Resolve, Tenacity, Blender

### Utilities (24)
- AngryIP Scanner, CCleaner, Bitvise SSH Client, Belarc Advisor, O&O ShutUp10
- FileMail Desktop, PowerToys, Everything, Greenshot, Bulk Rename Utility
- Revo Uninstaller, WinDirStat, Core Temp, GPU-Z, CrystalDiskInfo
- Sysinternals Suite, winget Auto-Update, ShareX, Rainmeter, Speccy
- BleachBit, Rufus, Ventoy, HWiNFO

### Security (12)
- Avira Antivirus, Kaspersky Security Cloud, AVG AntiVirus Free, Avast Free Antivirus
- Malwarebytes, Bitwarden, 1Password, LastPass, Dashlane, Sophos Home
- KeePassXC, NordPass, Proton Pass

### Communication (11)
- Telegram Desktop, Signal, Thunderbird, Discord, Slack, Zoom, Microsoft Teams
- Skype, WhatsApp Desktop, Viber, Element

### 3D & CAD (10)
- Blender, FreeCAD, LibreCAD, KiCad, OpenSCAD, Wings 3D, Sweet Home 3D
- Dust3D, MeshLab, Slic3r

### Networking (9)
- Nmap, Wireshark, Zenmap, PuTTY, Advanced Port Scanner, Advanced IP Scanner
- Fing CLI, GlassWire, NetLimiter, TCPView

### Runtime (7)
- Java Runtime Environment, .NET Desktop Runtime 6, .NET Desktop Runtime 8
- Visual C++ Redistributable, Go Programming Language, Rust, PHP

### Writing (9)
- Trelby, KIT Scenarist, Storyboarder, Manuskript, yWriter, Celtx
- bibisco, Scribus, FocusWriter

### Gaming (7)
- Steam, Epic Games Launcher, GOG Galaxy, EA App, Ubisoft Connect
- Battle.net, Itch.io

### Cloud Storage (6)
- Google Drive, Dropbox, OneDrive, MEGA, pCloud, Sync.com

### Remote Desktop (7)
- TeamViewer, AnyDesk, Chrome Remote Desktop, TightVNC, RustDesk
- UltraVNC, Parsec

### Backup (7)
- Veeam Agent FREE, EaseUS Todo Backup Free, Duplicati, Cobian Backup
- FreeFileSync, Syncthing, Macrium Reflect Free

### Education (7)
- Anki, GeoGebra, Stellarium, MuseScore, Moodle Desktop, Scratch Desktop
- Celestia

### Finance (6)
- GnuCash, HomeBank, Money Manager Ex, KMyMoney, Skrooge
- Firefly III Desktop

### Shortcuts & Maintenance (7)
- Grok AI (Desktop & Start Menu)
- ChatGPT (Desktop & Start Menu)
- dictation.io (Desktop & Start Menu)
- Uninstall McAfee Products
- PowerToys, AutoHotkey, Everything

## Requirements

- **Operating System:** Windows 10 (1809+), Windows 11, Windows Server 2016+
- **PowerShell:** 5.1 or later (PowerShell 7.2+ recommended)
- **Privileges:** Administrator rights required
- **winget:** Windows Package Manager (recommended, installed by default on Windows 11)
- **.NET Framework:** 4.7.2 or later (for GUI version)
  - **Note:** The GUI installer (`install-gui.ps1`) will automatically detect and offer to install .NET Framework 4.8 if not present or if an older version is detected

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
- **Search & Filter** - Real-time search box to filter applications by name, category, or description
  - Type to instantly filter the list (e.g., "chrome", "browser", "video")
  - Clear button (X) to reset search
  - Result count shows "Showing X of 271 applications"
  - Checkbox states preserved when filtering
- **Application Table** - Browse all 271 applications with checkboxes
- **Category Grouping** - Applications organized by category
- **Status Column** - Shows "Installed" with version or "Not Installed"
- **Progress Tracking** - Real-time progress: "0 / 5 applications" updates as you select
- **Buttons:**
  - **Refresh Status** - Re-scan for installed applications
  - **Select All** - Select all applications (filtered or all)
  - **Select Missing** - Select only applications not currently installed
  - **Deselect All** - Clear all selections
  - **Export Selection** - Save selected applications to a JSON profile
  - **Import Selection** - Load applications from a JSON profile
  - **Install Selected** - Install checked applications
  - **Uninstall Selected** - Remove checked applications (only installed apps)
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
- **1-212:** Install individual application by number
- **A:** Install all applications
- **M:** Install missing applications only
- **U:** Check for updates
- **E:** Export selection to profile
- **I:** Import selection from profile
- **X:** Uninstall/Remove selected applications
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

## Export/Import Configuration Profiles

Both the GUI and CLI versions support exporting and importing application selection profiles. This feature is useful for:
- **Backing up your application selections**
- **Deploying the same set of applications to multiple machines**
- **Sharing configurations with team members**
- **Standardizing installations across an organization**

### Profile Format

Profiles are saved as JSON files with the following structure:

```json
{
  "Version": "1.0",
  "Timestamp": "2025-11-10T18:40:47",
  "ComputerName": "MYTECHTODAY-LAP",
  "UserName": "kyle",
  "InstallerVersion": "1.3.8",
  "Applications": [
    "Google Chrome",
    "7-Zip",
    "VLC Media Player",
    "Visual Studio Code",
    "Git"
  ]
}
```

### Default Profile Location

Profiles are saved to: `C:\mytech.today\app_installer\profiles\`

Default filename format: `profile-{ComputerName}-{yyyy-MM-dd-HHmmss}.json`

### Using Export/Import in GUI

1. **Export Selection:**
   - Select the applications you want to export
   - Click the **"Export Selection"** button
   - Choose a location and filename (or use the default)
   - The profile will be saved with metadata including timestamp, computer name, and user

2. **Import Selection:**
   - Click the **"Import Selection"** button
   - Browse to and select a profile JSON file
   - Review the confirmation dialog showing the number of applications
   - Click "Yes" to select the applications from the profile
   - Applications not available in the current installer version will be listed as warnings

### Using Export/Import in CLI

1. **Export Selection:**
   - From the main menu, press **E**
   - Enter the application numbers to export (e.g., "1,3,5" or "1-10")
   - Enter a filename or press Enter to use the default
   - The profile will be saved to the profiles directory

2. **Import Selection:**
   - From the main menu, press **I**
   - Select a profile from the list or enter a full path
   - Review the profile information and confirm installation
   - Applications will be installed automatically if confirmed

### Handling Missing Applications

When importing a profile, the installer will:
- ✅ Identify which applications from the profile are available in the current installer
- ⚠️ Warn about applications that are not available (e.g., removed or renamed apps)
- ✅ Proceed with installing only the available applications
- 📝 Log all import operations including missing applications

## Directory Structure

```
app_installer/
├── install-gui.ps1                  # GUI-based installer (recommended)
├── install.ps1                      # Command-line menu-driven installer
├── apps/                            # Individual app installation scripts (212 total)
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

## Uninstall Applications

Both the GUI and CLI versions support uninstalling applications that were previously installed via winget.

### GUI Uninstall (install-gui.ps1)

1. **Select Applications** - Check the applications you want to uninstall
2. **Click "Uninstall Selected"** - Dark red button next to "Install Selected"
3. **Confirm Uninstall** - Review the list of applications to be removed
4. **Progress Tracking** - Watch real-time progress as apps are uninstalled
5. **Completion** - View success/fail statistics

**Safety Features:**
- ⚠️ **Confirmation required** - Cannot uninstall without explicit confirmation
- ⚠️ **Only installed apps** - Only shows applications that are currently installed
- ⚠️ **Cannot undo** - Uninstall is permanent (warning shown in confirmation)
- ✅ **Detailed logging** - All uninstall operations logged to centralized log
- ✅ **Error handling** - Failed uninstalls are reported with error details

### CLI Uninstall (install.ps1)

1. **Select Menu Option "X"** - Choose "X. Uninstall/Remove Selected Applications"
2. **Enter Application Numbers** - Type numbers (e.g., "1,3,5" or "1-10")
3. **Confirm Uninstall** - Review the list and confirm with "Y"
4. **Progress Tracking** - Watch progress with success/fail counts
5. **Completion** - View final statistics

**Example:**
```powershell
.\install.ps1
# Select "X" from menu
# Enter: 1,5,10
# Confirm: Y
```

**Important Notes:**
- ⚠️ Applications without a WingetId cannot be uninstalled via this tool
- ⚠️ Some applications may require manual uninstallation from Windows Settings
- ⚠️ Uninstalling critical system applications may cause issues
- ✅ The application list automatically refreshes after uninstall completes

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

Both scripts maintain an internal registry of all 212 supported applications with:
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
  - The GUI installer will automatically detect and offer to install .NET Framework 4.8 if needed
  - If automatic installation fails, download manually from: https://dotnet.microsoft.com/download/dotnet-framework/net48
- Check Windows display scaling settings
- Try running on different monitor if using multi-monitor setup
- GUI automatically adapts to DPI scaling

### .NET Framework Installation Issues

**Issue:** GUI fails to start with assembly loading errors

**Solutions:**
- Run `install-gui.ps1` - it will automatically detect missing .NET Framework
- If prompted, allow the script to install .NET Framework 4.8
- A system restart may be required after .NET Framework installation
- If automatic installation fails, install manually from Microsoft's website
- Verify installation by running `app_installer\test-dotnet-check.ps1`

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
