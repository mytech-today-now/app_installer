# .NET Framework Automatic Installation Feature

## Overview

The GUI installer (`install-gui.ps1`) now includes automatic .NET Framework detection and installation functionality. This ensures that the required .NET Framework 4.7.2+ is present before attempting to load Windows Forms assemblies.

## Version

- **Feature Added:** Version 1.3.8
- **Date:** November 9, 2025

## What Changed

### New Functions Added

1. **`Get-DotNetFrameworkVersion`**
   - Checks the Windows registry for installed .NET Framework version
   - Returns the release number (e.g., 533509 for .NET Framework 4.8)
   - Returns 0 if .NET Framework 4.5+ is not detected

2. **`Get-DotNetFrameworkVersionName`**
   - Converts release number to human-readable version name
   - Supports versions from .NET Framework 4.5 to 4.8
   - Example: Release 533509 → "4.8"

3. **`Install-DotNetFramework`**
   - Installs .NET Framework 4.8 using winget
   - Provides user prompts for restart after installation
   - Falls back to manual installation instructions if winget fails

4. **`Ensure-DotNetFramework`**
   - Main orchestration function
   - Checks for .NET Framework 4.7.2 or later
   - Prompts user to install/upgrade if needed
   - Returns true if prerequisites are met, false otherwise

### Execution Flow

```
Script Start
    ↓
Display Header (Version 1.3.8)
    ↓
Ensure-DotNetFramework
    ↓
Get-DotNetFrameworkVersion
    ↓
Is .NET Framework installed?
    ├─ No → Prompt to install → Install-DotNetFramework → Restart prompt
    └─ Yes → Check version
              ↓
              Is version >= 4.7.2?
              ├─ No → Prompt to upgrade → Install-DotNetFramework
              └─ Yes → Continue
                        ↓
                        Load GUI Assemblies
                        ↓
                        Start GUI
```

## Technical Details

### Registry Check

The script checks the following registry key:
```
HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full
```

It reads the `Release` value to determine the installed version:
- **528040+** = .NET Framework 4.8
- **461808+** = .NET Framework 4.7.2
- **461308+** = .NET Framework 4.7.1
- **460798+** = .NET Framework 4.7
- And so on...

### Installation Method

The script uses winget to install .NET Framework 4.8:
```powershell
winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-source-agreements --accept-package-agreements
```

### Error Handling

- If winget is not available, provides manual download link
- If installation fails, provides manual download link
- If user declines installation, script exits gracefully
- All errors are logged with appropriate color-coded messages

## User Experience

### Scenario 1: .NET Framework 4.8 Already Installed

```
=== myTech.Today Application Installer - GUI Mode ===
Version: 1.3.8

[CHECK] Checking .NET Framework version...
[CHECK] .NET Framework release number: 533509
[OK] .NET Framework 4.8 detected (Release: 533509)
[OK] .NET Framework version is sufficient for GUI

[INFO] Loading GUI assemblies...
[OK] GUI assemblies loaded successfully
```

### Scenario 2: .NET Framework Not Installed

```
=== myTech.Today Application Installer - GUI Mode ===
Version: 1.3.8

[CHECK] Checking .NET Framework version...
[ERROR] .NET Framework not detected
[INFO] .NET Framework 4.7.2 or later is required for this GUI

Would you like to install .NET Framework 4.8 now? (Y/N): Y

[INSTALL] Installing .NET Framework 4.8...
[INFO] This is required for the GUI to function properly
[INFO] Installation may take several minutes and require a restart
[DOWNLOAD] Downloading .NET Framework 4.8...
[OK] .NET Framework 4.8 installed successfully!
[WARN] A system restart may be required for changes to take effect
[INFO] Please restart your computer and run this script again

Would you like to restart now? (Y/N):
```

### Scenario 3: Old .NET Framework Version

```
=== myTech.Today Application Installer - GUI Mode ===
Version: 1.3.8

[CHECK] Checking .NET Framework version...
[CHECK] .NET Framework release number: 394802
[OK] .NET Framework 4.6.2 detected (Release: 394802)
[WARN] .NET Framework 4.6.2 is installed, but 4.7.2 or later is recommended
[INFO] Current version may not support all GUI features

Would you like to upgrade to .NET Framework 4.8? (Y/N):
```

## Testing

A test script is provided to verify .NET Framework detection:

```powershell
.\app_installer\test-dotnet-check.ps1
```

This script:
- Checks for .NET Framework installation
- Verifies version is 4.7.2 or later
- Tests assembly loading (System.Windows.Forms, System.Drawing, System.Web)
- Reports success or failure with detailed messages

## Benefits

1. **Automatic Detection** - No manual checking required
2. **User-Friendly** - Clear prompts and instructions
3. **Graceful Degradation** - Falls back to manual installation if needed
4. **Prevents Errors** - Catches missing .NET before GUI initialization
5. **Informative** - Detailed logging of version and status
6. **Flexible** - User can choose to install, upgrade, or exit

## Compatibility

- **Windows 10 (1809+)** - Fully supported
- **Windows 11** - Fully supported
- **Windows Server 2016+** - Fully supported
- **PowerShell 5.1+** - Required
- **Administrator Rights** - Required for installation

## Files Modified

1. **`app_installer/install-gui.ps1`**
   - Added .NET Framework detection functions (lines 29-224)
   - Added prerequisite check before assembly loading (lines 225-253)
   - Updated version to 1.3.8

2. **`app_installer/README.md`**
   - Updated Requirements section with automatic installation note
   - Added troubleshooting section for .NET Framework issues

3. **`app_installer/test-dotnet-check.ps1`** (New)
   - Test script for .NET Framework detection
   - Verifies all prerequisites are met

## Future Enhancements

Potential improvements for future versions:

1. **Silent Mode** - Add parameter to skip prompts and install automatically
2. **Offline Support** - Bundle .NET Framework installer for offline scenarios
3. **Version Selection** - Allow user to choose which .NET Framework version to install
4. **Rollback** - Ability to revert to previous .NET Framework version if issues occur
5. **Detailed Logging** - Log .NET Framework installation to centralized log file

## References

- [.NET Framework Version Detection](https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed)
- [.NET Framework 4.8 Download](https://dotnet.microsoft.com/download/dotnet-framework/net48)
- [Windows Forms Requirements](https://docs.microsoft.com/en-us/dotnet/desktop/winforms/overview/)

## Support

If you encounter issues with .NET Framework installation:

1. Run the test script: `.\app_installer\test-dotnet-check.ps1`
2. Check the error messages for specific guidance
3. Try manual installation from Microsoft's website
4. Ensure you have administrator rights
5. Verify Windows Update is functioning correctly

## Conclusion

This feature significantly improves the user experience by automatically handling .NET Framework prerequisites. Users no longer need to manually check or install .NET Framework before running the GUI installer - the script handles everything automatically with clear prompts and helpful error messages.

