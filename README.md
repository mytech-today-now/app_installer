# App Installer - myTech.Today

**Version:** 1.0.0  
**Author:** myTech.Today  
**License:** All rights reserved  

## Overview

The **App Installer** is a comprehensive, menu-driven PowerShell application installer system designed for automated Windows setup. It provides an interactive interface for installing and managing 27+ essential applications with status tracking, version detection, and centralized logging.

## Features

âœ… **Interactive Menu Interface** - User-friendly menu with real-time installation status  
âœ… **Version Detection** - Automatically detects installed applications and their versions  
âœ… **Selective Installation** - Install individual apps, all apps, or only missing apps  
âœ… **Centralized Logging** - All activities logged to `C:\mytech.today\logs\` in markdown format  
âœ… **winget Integration** - Leverages Windows Package Manager for most installations  
âœ… **Custom Installers** - Specialized scripts for apps not available via winget  
âœ… **Error Handling** - Comprehensive error handling with fallback solutions  
âœ… **Silent Installation** - Most apps install silently without user interaction  

## Supported Applications (27+)

### Browsers
- Google Chrome
- Brave Browser
- Firefox

### Development Tools
- Notepad++
- Git
- Python (latest stable)
- Node.js (latest stable LTS)
- Docker Desktop

### Productivity
- LibreOffice Suite

### Media & Creative
- OBS Studio
- GIMP
- Audacity
- Handbrake
- OpenShot Video Editor
- ClipGrab

### Utilities
- AngryIP Scanner
- CCleaner
- Bitvise SSH Client
- Belarc Advisor
- O&O ShutUp10++
- FileMail Desktop

### Security
- Avira Antivirus Free
- Uninstall McAfee Products

### Shortcuts
- Grok AI (Desktop & Start Menu)
- ChatGPT (Desktop & Start Menu)
- dictation.io (Desktop & Start Menu)

## Requirements

- **Operating System:** Windows 10 (1809+), Windows 11, Windows Server 2016+
- **PowerShell:** 5.1 or later (PowerShell 7.2+ recommended)
- **Privileges:** Administrator rights required
- **winget:** Windows Package Manager (recommended, installed by default on Windows 11)

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
   ```powershell
   .\install.ps1
   ```

## Usage

### Interactive Menu Mode (Default)

Launch the interactive menu:

```powershell
.\install.ps1
```

**Menu Options:**
- **1-26:** Install individual application by number
- **A:** Install all applications
- **M:** Install missing applications only
- **S/R:** Show/Refresh status
- **Q:** Quit

### Command-Line Mode

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
â"œâ"€â"€ install.ps1                      # Main menu-driven installer
â"œâ"€â"€ apps/                            # Individual app installation scripts
â"‚   â"œâ"€â"€ chrome.ps1                   # (Uses winget)
â"‚   â"œâ"€â"€ brave.ps1                    # (Uses winget)
â"‚   â"œâ"€â"€ firefox.ps1                  # (Uses winget)
â"‚   â"œâ"€â"€ notepadplusplus.ps1          # (Uses winget)
â"‚   â"œâ"€â"€ git.ps1                      # (Uses winget)
â"‚   â"œâ"€â"€ python.ps1                   # (Uses winget)
â"‚   â"œâ"€â"€ nodejs.ps1                   # (Uses winget)
â"‚   â"œâ"€â"€ docker.ps1                   # (Uses winget)
â"‚   â"œâ"€â"€ libreoffice.ps1              # (Uses winget)
â"‚   â"œâ"€â"€ obs.ps1                      # (Uses winget)
â"‚   â"œâ"€â"€ gimp.ps1                     # (Uses winget)
â"‚   â"œâ"€â"€ audacity.ps1                 # (Uses winget)
â"‚   â"œâ"€â"€ handbrake.ps1                # (Uses winget)
â"‚   â"œâ"€â"€ openshot.ps1                 # (Uses winget)
â"‚   â"œâ"€â"€ clipgrab.ps1                 # (Uses winget)
â"‚   â"œâ"€â"€ angryip.ps1                  # (Uses winget)
â"‚   â"œâ"€â"€ ccleaner.ps1                 # (Uses winget)
â"‚   â"œâ"€â"€ bitvise.ps1                  # (Uses winget)
â"‚   â"œâ"€â"€ avira.ps1                    # (Uses winget)
â"‚   â"œâ"€â"€ belarc.ps1                   # Custom installer
â"‚   â"œâ"€â"€ shutup10.ps1                 # Custom installer
â"‚   â"œâ"€â"€ filemail.ps1                 # Custom installer
â"‚   â"œâ"€â"€ grok-shortcuts.ps1           # Creates shortcuts
â"‚   â"œâ"€â"€ chatgpt-shortcuts.ps1        # Creates shortcuts
â"‚   â"œâ"€â"€ dictation-shortcut.ps1       # Creates shortcuts
â"‚   â""â"€â"€ uninstall-mcafee.ps1         # McAfee removal tool
â"œâ"€â"€ README.md                        # This file
â"œâ"€â"€ CHANGELOG.md                     # Version history
â""â"€â"€ ai_prompts/
    â""â"€â"€ prompt.01.md                 # Original requirements
```

## Logging

All activities are logged to:
```
C:\mytech.today\logs\install-yyyy-MM.md
```

**Log Format:** Markdown table with icons  
**Log Rotation:** Monthly (one file per month)  
**Log Levels:** â„¹ï¸ INFO, âš ï¸ WARNING, âŒ ERROR, âœ… SUCCESS

**Example Log Entry:**
```markdown
| 2025-10-31 10:30:00 | âœ… **SUCCESS** | Google Chrome installed successfully |
```

## How It Works

### Application Registry

The script maintains an internal registry of all supported applications with:
- **Name:** Display name
- **ScriptName:** Individual installation script filename
- **WingetId:** Windows Package Manager ID (if available)
- **Category:** Application category for menu organization

### Installation Process

1. **Detection:** Checks if application is already installed via winget or registry
2. **Method Selection:**
   - If custom script exists in `apps/` folder â†' Use custom script
   - If WingetId is defined â†' Use `winget install`
   - Otherwise â†' Display warning
3. **Execution:** Run installation with silent/automated parameters
4. **Logging:** Log all activities to centralized log file
5. **Status:** Display success/failure with color-coded output

### Version Detection

- **Primary:** Uses `winget list` for fast, accurate detection
- **Fallback:** Checks Windows registry for installed programs
- **Display:** Shows version number or "Installed" if version unavailable

## Customization

### Adding New Applications

1. **Add to Application Registry** in `install.ps1`:
   ```powershell
   @{ Name = "MyApp"; ScriptName = "myapp.ps1"; WingetId = "Publisher.MyApp"; Category = "Utilities" }
   ```

2. **Create Custom Script** (optional) in `apps/myapp.ps1`:
   ```powershell
   # Custom installation logic
   Write-Host "Installing MyApp..." -ForegroundColor Cyan
   # ... installation code ...
   ```

3. **Test Installation**:
   ```powershell
   .\install.ps1
   ```

### Modifying Categories

Edit the `Category` property in the application registry to organize apps differently.

## Troubleshooting

### winget Not Available

**Error:** "winget is not available on this system"

**Solutions:**
- Install "App Installer" from Microsoft Store
- Update Windows to latest version
- Verify: `winget --version`

### Installation Fails

**Error:** "Installation failed. Check log for details."

**Solutions:**
1. Check log file: `C:\mytech.today\logs\install-yyyy-MM.md`
2. Verify internet connection
3. Run as Administrator
4. Try manual installation of specific app
5. Check if antivirus is blocking installation

### Application Not Detected

**Issue:** Installed app shows as "Not Installed"

**Causes:**
- App installed via portable version
- App installed in non-standard location
- Registry entry doesn't match detection pattern

**Solution:** Detection is informational only; app will still function

## Best Practices

âœ… **Run as Administrator** - Required for most installations  
âœ… **Check winget availability** - Ensures smooth installation  
âœ… **Review logs** - Check `C:\mytech.today\logs\` for details  
âœ… **Install missing only** - Saves time on already-configured systems  
âœ… **Restart after major installs** - Some apps require restart  

## Security Considerations

- All downloads use HTTPS
- winget packages are verified by Microsoft
- Custom scripts download from official sources only
- McAfee removal uses official MCPR tool
- No credentials or sensitive data stored

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## Support

For issues, questions, or contributions:
- **GitHub Issues:** https://github.com/mytech-today-now/PowerShellScripts/issues
- **Documentation:** See `.augment/` folder for development guidelines

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## License

Copyright (c) 2025 myTech.Today. All rights reserved.

## Author

**myTech.Today**  
https://github.com/mytech-today-now/PowerShellScripts

---

**Last Updated:** 2025-10-31  
**Version:** 1.0.0

