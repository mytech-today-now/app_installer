# Changelog

All notable changes to the App Installer project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.0] - 2025-12-15 (GUI) / [1.6.0] - 2025-12-15 (CLI)

### Added - Automatic Start Menu Shortcut for Chrome Remote Desktop 🔗

- **New Feature: Automatic shortcut creation for Chrome Remote Desktop**
- **Missing shortcut detection and repair**
- **Enhanced error handling with comprehensive winget error codes**

**Chrome Remote Desktop Shortcut Creation:**

Chrome Remote Desktop is a web-based application that requires users to navigate to `https://remotedesktop.google.com/access` to configure and use it. To improve user experience, the installer now automatically creates a Start Menu shortcut that opens this URL directly.

**Implementation Details:**

1. **New-WebApplicationShortcut Function**
   - Creates Start Menu shortcuts that open URLs in the default browser
   - Detects Chrome browser installation (checks 3 common paths)
   - Falls back to default browser if Chrome not found
   - Proper COM object creation and cleanup
   - Configurable shortcut name, URL, description, and icon
   - Returns boolean success/failure status
   - Location: `%ProgramData%\Microsoft\Windows\Start Menu\Programs`

2. **Automatic Shortcut Creation**
   - Shortcut created after successful Chrome Remote Desktop installation
   - Works with both winget and custom script installations
   - Opens `https://remotedesktop.google.com/access` in browser
   - Uses Chrome browser with `--new-window` flag if available
   - Falls back to `explorer.exe` for default browser
   - Descriptive shortcut: "Configure and access Chrome Remote Desktop"

3. **Missing Shortcut Detection**
   - `Get-InstalledApplications` checks for Chrome Remote Desktop shortcut
   - If app is installed but shortcut is missing, creates it automatically
   - Logs shortcut creation status for troubleshooting
   - Ensures users always have easy access to configuration page

4. **Enhanced Error Handling**
   - Custom script exit codes captured immediately after execution
   - Uses `Get-WingetErrorMessage` for custom script failures
   - Detailed error messages with exit codes in both CLI and GUI
   - Consistent error handling across installation methods

**Bug Fixes:**

1. **Chrome Remote Desktop Package ID**
   - Fixed incorrect WingetId in `apps/chromeremote.ps1`
   - Changed from `Google.ChromeRemoteDesktop` to `Google.ChromeRemoteDesktopHost`
   - Ensures successful installation via winget
   - Improved exit code handling in custom script

2. **Exit Code Handling**
   - Capture exit code in variable before using it
   - Prevents `$LASTEXITCODE` from being overwritten by subsequent commands
   - Return actual winget exit code for better debugging
   - Consistent exit code usage throughout scripts

**Benefits:**

- ✅ **User Experience:** Easy access to Chrome Remote Desktop configuration via Start Menu
- ✅ **Reliability:** Missing shortcuts are automatically repaired during app detection
- ✅ **Consistency:** Uniform shortcut creation across CLI and GUI installers
- ✅ **Debugging:** Better error messages for custom script failures
- ✅ **Accessibility:** Start Menu shortcut provides quick access to web interface
- ✅ **Compatibility:** Works with or without Chrome browser installed

**Technical Details:**

- Function: `New-WebApplicationShortcut` (100+ lines)
- Shortcut location: `%ProgramData%\Microsoft\Windows\Start Menu\Programs`
- Target: Chrome browser with `--new-window` flag, or `explorer.exe` for default browser
- Icon: Chrome executable or Windows internet icon (SHELL32.dll,14)
- COM object: WScript.Shell for .lnk file creation

**Files Modified:**

- `apps/chromeremote.ps1` - Fixed WingetId and improved error handling
- `install.ps1` - Version 1.6.0
  * Added `New-WebApplicationShortcut` function
  * Added shortcut creation after Chrome Remote Desktop installation
  * Added missing shortcut detection in `Get-InstalledApplications`
  * Enhanced custom script error handling
- `install-gui.ps1` - Version 1.5.0
  * Added `New-WebApplicationShortcut` function
  * Added shortcut creation after Chrome Remote Desktop installation
  * Added missing shortcut detection in `Get-InstalledApplications`
  * Enhanced custom script error handling

**Impact:**

- Features: Automatic shortcut creation and repair for web-based applications
- Performance: Minimal overhead - only runs for Chrome Remote Desktop
- Breaking: None - all changes are additive enhancements
- Compatibility: Works with or without Chrome browser installed

## [1.4.5] - 2025-11-11 (GUI)

### Changed - Multi-Line Button Text with Narrower Width 🎨

- **Enabled multi-line text wrapping on all control buttons**
- **Significantly reduced button width for more compact layout**
- **Increased button height to accommodate stacked text**
- **Reduced spacing between buttons by 50%**

**User Requirements:**

The user requested that control buttons on the main GUI should:
1. Have stacked text (multi-line) to make them narrower
2. Increase button heights to accommodate multi-line text with margins
3. Cut spacing between buttons in half
4. Make button width significantly narrower

**Changes:**

1. **Multi-Line Text Wrapping**
   - Added line breaks (`n) to all button text labels
   - Set `AutoSize = $false` to enable text wrapping
   - Set `TextAlign = MiddleCenter` for centered multi-line text
   - Examples:
     - "Refresh Status" → "Refresh`nStatus"
     - "Select All" → "Select`nAll"
     - "Install Selected" → "Install`nSelected"
     - "Check for Updates" → "Check for`nUpdates"

2. **Button Width Reduction**
   - Changed from dynamic width calculation to fixed narrow width
   - New width: 65 * scaleFactor (significantly narrower than before)
   - Previous: Dynamic width based on longest text with MinWidth 70 and Padding 20
   - Buttons are now much more compact horizontally

3. **Button Height Increase**
   - Increased base button height from 50pt to 70pt
   - Provides adequate space for 2-line text with margins
   - Ensures text is readable and not cramped

4. **Spacing Reduction**
   - Reduced base spacing from 12pt to 6pt (50% reduction)
   - Buttons are now closer together horizontally
   - More efficient use of horizontal space

**Implementation Details:**

- Updated `Spacing` in base dimensions (line 3006): 12 → 6
- Updated `ButtonHeight` in base dimensions (line 3016): 50 → 70
- Replaced dynamic button width calculation with fixed width (line 3636): `65 * scaleFactor`
- Updated all 12 control buttons to include:
  - Multi-line text with `n line breaks
  - `AutoSize = $false`
  - `TextAlign = MiddleCenter`

**Buttons Updated:**
1. Refresh Status
2. Select All
3. Select Missing
4. Deselect All
5. Export Selection
6. Import Selection
7. Install Selected
8. Uninstall Selected
9. Check for Updates
10. Pause/Resume (hidden initially)
11. Skip Current (hidden initially)
12. Exit

**Visual Impact:**

- Buttons are significantly narrower, allowing more buttons to fit in the same horizontal space
- Multi-line text makes button labels clear and readable despite narrower width
- Reduced spacing creates a more compact, efficient button layout
- Buttons no longer extend past the right edge of HTML content area
- More modern, space-efficient appearance

**Files Modified:**
- `install-gui.ps1` - Version 1.4.5
  - Updated base dimensions for spacing and button height
  - Changed button width from dynamic to fixed narrow width
  - Added multi-line text support to all control buttons

## [1.4.4] - 2025-11-11 (GUI) / [1.5.4] - 2025-11-11 (CLI)

### Fixed - GitHub URLs for Scripts Repository 🔗

- **Updated GitHub URLs to point to correct scripts repository**
- **Fixed 404 errors when loading from GitHub**
- **Enabled online loading of responsive and logging modules**

**Issue:**

The responsive GUI helper and generic logging module were failing to load from GitHub with 404 errors because the URLs were pointing to the wrong repository:
- Old URL: `https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/refs/heads/main/scripts/responsive.ps1`
- Old URL: `https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/refs/heads/main/scripts/logging.ps1`

The scripts directory is actually a separate Git repository at `https://github.com/mytech-today-now/scripts.git`, not part of the PowerShellScripts repository.

**Solution:**

Updated all GitHub URLs to point to the correct scripts repository:
- New URL: `https://raw.githubusercontent.com/mytech-today-now/scripts/main/responsive.ps1`
- New URL: `https://raw.githubusercontent.com/mytech-today-now/scripts/main/logging.ps1`

Also pushed the latest commits from the scripts repository to GitHub to ensure the files are available online.

**Implementation Details:**

1. **GUI Version (install-gui.ps1)**
   - Updated responsive helper URL (line 33)
   - Updated logging module URL (line 68)

2. **CLI Version (install.ps1)**
   - Updated logging module URL (line 87)

3. **Scripts Repository**
   - Pushed local commits to origin/main
   - Ensured responsive.ps1 and logging.ps1 are available on GitHub

**Testing:**
- Syntax validation passed for both GUI and CLI ✓
- URLs updated correctly ✓
- Scripts repository pushed to GitHub ✓

**Files Modified:**
- `install-gui.ps1` - Version 1.4.4
  - Updated responsive helper URL
  - Updated logging module URL
  - Updated version numbers
- `install.ps1` - Version 1.5.4
  - Updated logging module URL
  - Updated version numbers

**Expected Behavior:**

When running the installer, you should now see:
```
Loading responsive GUI helper...
[OK] Responsive GUI helper loaded successfully
Loading generic logging module...
[OK] Generic logging module loaded successfully
```

Instead of the previous 404 errors and fallback messages.

## [1.4.3] - 2025-11-11 (GUI)

### Fixed - Responsive Helper Local Fallback 🔧

- **Added local fallback for responsive GUI helper**
- **Fixed "New-ResponsiveForm not recognized" error**
- **Improved offline functionality**

**Issue:**

When the responsive GUI helper failed to load from GitHub (404 error), the script would fall back to a local DPI scaling implementation that didn't include the `New-ResponsiveForm` function. This caused the GUI to fail with the error:

```
The term 'New-ResponsiveForm' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

**Solution:**

Added local file fallback for the responsive helper, similar to the logging module:
- Attempts to load from GitHub first
- If GitHub fails, tries to load from local path: `../scripts/responsive.ps1`
- Provides clear status messages for each attempt
- Gracefully handles missing local file

**Implementation Details:**

1. **Local Fallback Logic**
   - Check if local responsive.ps1 exists at `../scripts/responsive.ps1`
   - Source the file using dot-sourcing (`. $localResponsivePath`)
   - Set `$script:ResponsiveHelperLoaded` flag on success
   - Display appropriate status messages

2. **Error Handling**
   - Try-catch blocks for both GitHub and local loading
   - Clear error messages for each failure scenario
   - Warning message if local file not found

**Testing:**
- Syntax validation passed ✓
- Local fallback working correctly ✓
- GUI launches successfully when GitHub is unavailable ✓

**Files Modified:**
- `install-gui.ps1` - Version 1.4.3
  - Added local fallback for responsive helper (lines 32-61)
  - Updated version numbers

## [1.4.2] - 2025-11-11 (GUI)

### Changed - Responsive Form Creation 🎨

- **Replaced manual form creation with New-ResponsiveForm function**
- **Improved DPI scaling and multi-monitor support**
- **Simplified form initialization code**

**Feature Overview:**

The GUI now uses the centralized `New-ResponsiveForm` function from the responsive.ps1 module instead of manually creating forms. This provides:
- Consistent form creation across all dialogs
- Automatic DPI scaling and responsive sizing
- Better multi-monitor support
- Reduced code duplication
- Easier maintenance and updates

**Implementation Details:**

1. **Main Form Creation**
   - Replaced manual `New-Object System.Windows.Forms.Form` with `New-ResponsiveForm`
   - Automatically applies DPI scaling, font sizing, and responsive settings
   - Merges custom properties into form Tag for backward compatibility
   - Maintains all existing functionality

2. **Dialog Forms**
   - Queue Management dialog now uses `New-ResponsiveForm`
   - Updates dialog now uses `New-ResponsiveForm`
   - Consistent styling and behavior across all forms

3. **Code Improvements**
   - Removed duplicate form Tag assignment
   - Consolidated form initialization logic
   - Better separation of concerns

**Testing:**
- Syntax validation passed ✓
- Form creation working correctly ✓
- All dialogs functional ✓

**Files Modified:**
- `install-gui.ps1` - Version 1.4.2
  * Replaced main form creation with New-ResponsiveForm (line 3041)
  * Replaced queue dialog form creation with New-ResponsiveForm (line 4336)
  * Replaced updates dialog form creation with New-ResponsiveForm (line 4669)
  * Merged form Tag properties for backward compatibility (lines 3048-3063)
  * Removed duplicate Tag assignment (line 3598)
  * Updated version numbers

## [1.4.1] - 2025-11-11 (GUI) / [1.5.3] - 2025-11-11 (CLI)

### Added - Uninstall Applications Feature 🗑️

- **Added ability to uninstall applications via GUI and CLI**
- **Confirmation dialog before uninstalling with app list**
- **Progress tracking during uninstall operations**
- **Automatic UI refresh after uninstall completes**

**Feature Overview:**

Both GUI and CLI versions now support uninstalling applications that were previously installed via winget. This feature provides:
- Safe uninstallation with confirmation dialogs
- Only shows installed applications for uninstall
- Progress tracking with success/fail counts
- Automatic removal from installed apps cache
- Detailed logging of all uninstall operations
- UI refresh to reflect current installation status

**Implementation Details:**

1. **GUI Version (install-gui.ps1 v1.4.1)**
   - Added "Uninstall Selected" button (dark red) next to "Install Selected" button
   - Button only enabled when applications are selected
   - Confirmation dialog shows list of apps to be uninstalled with versions
   - Warns about apps that are not installed (will be skipped)
   - Progress bar shows uninstall progress
   - Status label updates during uninstall process
   - Completion message shows success/fail statistics
   - Automatically refreshes application list after uninstall

2. **CLI Version (install.ps1 v1.5.3)**
   - Added "X. Uninstall/Remove Selected Applications" menu option
   - Interactive selection of apps to uninstall (supports ranges, multi-select, categories)
   - Confirmation prompt shows list of apps to be uninstalled with versions
   - Warns about apps that are not installed (will be skipped)
   - Progress tracking with Write-Progress (parent/child progress IDs)
   - Completion summary shows success/fail statistics
   - Menu automatically refreshes on next iteration

3. **Core Functions**
   - `Uninstall-Application` - Uninstalls a single application
     * Accepts application object as parameter
     * Uses `winget uninstall --id {WingetId} --silent` command
     * Implements error handling and logging
     * Updates UI with progress (status label, progress bar)
     * Removes app from `$script:InstalledApps` hashtable on success
     * Returns boolean for success/failure
   - `Uninstall-SelectedApplications` (GUI only) - Batch uninstall handler
     * Gets checked items from ListView
     * Filters to only installed applications
     * Shows confirmation dialog with app list
     * Processes uninstall queue with progress tracking
     * Shows completion message with statistics
     * Refreshes application list

4. **Safety Features**
   - Confirmation required before uninstalling (cannot be bypassed)
   - Only installed applications can be uninstalled
   - Applications without WingetId cannot be uninstalled
   - Detailed logging of all uninstall operations
   - Error handling for failed uninstalls
   - UI prevents concurrent install/uninstall operations

**Testing:**
- Syntax validation passed for both GUI and CLI ✓
- Uninstall-Application function created and tested ✓
- GUI "Uninstall Selected" button added and wired up ✓
- CLI "X" menu option added and wired up ✓
- Confirmation dialogs working correctly ✓
- Progress tracking functional ✓
- UI refresh after uninstall working ✓

**Files Modified:**
- `install-gui.ps1` - Version 1.4.1
  * Added `Uninstall-Application` function (lines 2686-2839)
  * Added `Uninstall-SelectedApplications` function (lines 5405-5620)
  * Added "Uninstall Selected" button (lines 3877-3893)
  * Updated version numbers
- `install.ps1` - Version 1.5.3
  * Added `Uninstall-Application` function (lines 2526-2659)
  * Added "X" menu option and handler (lines 1184, 3226-3331)
  * Updated version numbers

**Files Created:**
- `test-uninstall.ps1` - Test script for uninstall functionality

## [1.4.0] - 2025-11-11 (GUI) / [1.5.2] - 2025-11-11 (CLI)

### Changed - Generic Logging Module Integration 📝

- **Integrated generic logging module from GitHub for centralized logging**
- **Replaced custom logging functions with shared logging module**
- **Monthly log rotation with markdown table format**

**Feature Overview:**

Both GUI and CLI versions now use a centralized generic logging module that provides:
- Consistent logging format across all myTech.Today scripts
- Monthly log rotation (one file per month: `scriptname-yyyy-MM.md`)
- Cyclical logging with 10MB size limit
- Markdown table format for structured logging
- ASCII-only indicators (no emoji): `[INFO]`, `[OK]`, `[WARN]`, `[ERROR]`
- Console output with color coding
- Can be imported from GitHub URL or local path

**Implementation Details:**

1. **Logging Module Import**
   - Loaded from GitHub URL: `https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/refs/heads/main/scripts/logging.ps1`
   - Automatic fallback to local path if network unavailable
   - Error handling for network failures

2. **Initialize-Log Function**
   - Replaces old `Initialize-Logging` function
   - Creates monthly log files: `AppInstaller-GUI-yyyy-MM.md` or `AppInstaller-CLI-yyyy-MM.md`
   - Includes script version and metadata in log header
   - Automatic log rotation when file exceeds 10MB

3. **Write-Log Function**
   - Compatible with existing log calls (no changes needed)
   - Supports log levels: INFO, SUCCESS, WARNING, ERROR
   - Writes to both console (with colors) and file (markdown table)
   - Format: `| Timestamp | Level | Message |`

4. **Benefits**
   - Centralized logging logic shared across multiple scripts
   - Easier maintenance and updates
   - Consistent log format for all myTech.Today tools
   - Monthly rotation prevents log files from growing too large
   - Markdown format makes logs easy to read and parse
   - Backward compatibility with fallback to old logging functions

**Testing:**
- Syntax validation passed for both GUI and CLI ✓
- Generic logging module loads successfully ✓
- Log files created in correct monthly format ✓
- All log levels working correctly ✓
- Fallback to local path working ✓

**Files Modified:**
- `install-gui.ps1` - Version 1.4.0
- `install.ps1` - Version 1.5.2

## [1.3.9] - 2025-11-11 (GUI)

### Changed - Responsive GUI Helper Integration 📐

- **Integrated responsive GUI helper from GitHub for improved DPI scaling**
- **Enhanced multi-monitor support with automatic DPI detection**
- **Improved cross-resolution compatibility (VGA to 8K UHD)**

**Feature Overview:**

The GUI now uses a centralized responsive helper module loaded from GitHub that provides:
- Automatic DPI scaling detection and calculation
- Support for multiple screen resolutions (VGA, SVGA, XGA, HD, WXGA, FHD, QHD, UWQHD, 4K UHD, 5K, 8K UHD)
- Multi-monitor support with different DPI settings
- Caching mechanism for improved performance
- Consistent scaling across all GUI elements

**Implementation Details:**

1. **Responsive Helper Import**
   - Loaded from GitHub URL: `https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/refs/heads/main/scripts/responsive.ps1`
   - Automatic fallback to local DPI scaling if network unavailable
   - Error handling for network failures

2. **Updated Get-DPIScaleFactor Function**
   - Now uses `Get-ResponsiveDPIScale` from responsive helper when available
   - Maintains backward compatibility with fallback implementation
   - Returns comprehensive scale information:
     * BaseFactor: Base DPI scaling factor
     * AdditionalScale: Resolution-specific additional scaling
     * TotalScale: Combined scaling factor
     * ScreenWidth/ScreenHeight: Screen dimensions
     * DpiX/DpiY: DPI values
     * ResolutionName: Detected resolution category
     * ResolutionCategory: Category identifier

3. **Benefits**
   - Centralized DPI scaling logic shared across multiple scripts
   - Easier maintenance and updates
   - Consistent behavior across different tools
   - Better support for high-DPI displays (4K, 5K, 8K)
   - Improved multi-monitor setups

**Testing:**
- Tested on 1920x1080 at 100% DPI ✓
- Syntax validation passed ✓
- Backward compatibility maintained ✓

## [1.3.8] - 2025-11-10 (GUI) / [1.5.1] - 2025-11-10 (CLI)

### Added - Export/Import Configuration Profiles 💾

- **Added export/import profile functionality to both GUI and CLI versions**
- **Save and load application selections for backup or deployment**
- **JSON-based profile format with metadata**

**Feature Overview:**

Export/Import Configuration Profiles allow users to save their application selections to a JSON file and load them later. This is useful for:
- Backing up application selections
- Deploying the same set of applications to multiple machines
- Sharing configurations with team members
- Standardizing installations across an organization

**Implementation Details:**

1. **Export-InstallationProfile Function**
   - Accepts array of selected applications
   - Creates JSON file with metadata:
     * Version (profile format version)
     * Timestamp (when profile was created)
     * ComputerName (source computer)
     * UserName (user who created profile)
     * InstallerVersion (version of installer used)
     * Applications (array of application names)
   - Default save location: `C:\mytech.today\app_installer\profiles\`
   - Default filename: `profile-{ComputerName}-{yyyy-MM-dd-HHmmss}.json`
   - Comprehensive error handling for file I/O operations
   - Logs all export operations to centralized log

2. **Import-InstallationProfile Function**
   - Reads and validates JSON profile file
   - Returns hashtable with:
     * Success (boolean)
     * Applications (array of valid app objects)
     * MissingApps (array of apps not in current installer)
     * Message (status message)
     * ProfileInfo (original profile metadata)
   - Handles missing applications gracefully
   - Validates JSON structure before processing
   - Logs all import operations including warnings for missing apps

3. **GUI Implementation (install-gui.ps1 v1.3.8)**
   - Added "Export Selection" button (orange background)
   - Added "Import Selection" button (dark blue background)
   - Buttons positioned between "Deselect All" and "Install Selected"
   - Export dialog:
     * Shows save file dialog with default filename
     * Validates that at least one app is selected
     * Displays success/failure message with file path
   - Import dialog:
     * Shows open file dialog
     * Displays confirmation with app count and missing apps warning
     * Automatically selects imported applications in ListView
     * Shows success message with count of selected apps

4. **CLI Implementation (install.ps1 v1.5.1)**
   - Added "E. Export Selection to Profile" menu option
   - Added "I. Import Selection from Profile" menu option
   - Export workflow:
     * Prompts for application selection (supports multi-select, ranges)
     * Prompts for filename (or uses default)
     * Displays success message with file path
   - Import workflow:
     * Lists available profiles in profiles directory
     * Allows selection by number or full path
     * Displays profile information and missing apps warning
     * Prompts for confirmation before installation
     * Automatically installs selected applications if confirmed

5. **Profile Format**
   ```json
   {
     "Version": "1.0",
     "Timestamp": "2025-11-10T18:40:47",
     "ComputerName": "PC01",
     "UserName": "user",
     "InstallerVersion": "1.3.8",
     "Applications": ["Google Chrome", "7-Zip", "VLC Media Player"]
   }
   ```

6. **Error Handling**
   - Validates file existence before import
   - Validates JSON structure (Version and Applications fields required)
   - Handles corrupted JSON files gracefully
   - Handles missing applications (apps in profile but not in current installer)
   - Comprehensive logging of all operations
   - User-friendly error messages

**Testing:**
- ✅ Exported selection of 10 applications and verified JSON structure
- ✅ Imported profile and verified all apps selected correctly
- ✅ Tested with missing apps in profile (handled gracefully with warnings)
- ✅ Tested with corrupted JSON file (proper error handling)
- ✅ Verified logging of all export/import operations
- ✅ Tested GUI buttons and dialogs
- ✅ Tested CLI menu options and workflows

**Benefits:**
- Saves time when setting up multiple machines
- Ensures consistency across deployments
- Provides backup of application selections
- Facilitates team collaboration and standardization
- Handles edge cases (missing apps, corrupted files) gracefully

## [1.3.7] - 2025-10-31

### Added - Marketing and Contact Information Display 📢

- **Added marketing information display in GUI output console**
- **Shows company services and contact details**
- **Matches CLI version marketing material**

**Issue:**
- GUI version didn't show the marketing material that the CLI version displays
- Users weren't aware of myTech.Today's services and contact information
- Missing opportunity to inform users about available IT support

**Solution:**

1. **Created Show-MarketingInformation Function**
   - Displays formatted marketing banner in output console
   - Shows company information and services
   - Includes contact details (email, phone, website)
   - Uses appropriate colors for readability on black background
   - Matches CLI version content with GUI-appropriate formatting

2. **Marketing Content Includes:**
   - Thank you banner with decorative borders
   - Company description (MSP serving Chicagoland)
   - Service offerings:
     * IT Consulting & Support
     * Network Design & Management
     * Cybersecurity & Compliance
     * Cloud Integration (Azure, AWS, Microsoft 365)
     * System Administration & Security
     * Database Management & Custom Development
   - Contact information:
     * Email: sales@mytech.today
     * Phone: (847) 767-4914
     * Web: https://mytech.today
   - Tagline: "Serving Chicagoland with 20+ years of IT expertise!"

3. **Display Timing:**
   - Shows after application detection completes
   - Appears before "GUI ready" message
   - Visible immediately when GUI opens
   - Doesn't interfere with installation output

4. **Formatting:**
   - Uses box-drawing characters (╔═╗║╚═╝) for professional appearance
   - Color-coded sections (Cyan headers, Yellow highlights, Green emphasis)
   - Bullet points (•) for service list
   - Proper spacing for readability

**Benefits:**
- ✅ Users informed about available IT services
- ✅ Contact information readily available
- ✅ Professional branding and marketing
- ✅ Consistent with CLI version
- ✅ Non-intrusive display in output console
- ✅ Increases awareness of myTech.Today services

**Files Modified:**
- `app_installer/install-gui.ps1` (added marketing display)
- `app_installer/CHANGELOG.md` (documented changes)

## [1.3.6] - 2025-10-31

### Enhanced - ListView Table Layout and Readability 📊

- **Improved column widths for better content display**
- **Added dynamic row height based on font size**
- **Enhanced column headers with clearer names**

**Issue:**
- ListView table had fixed column widths that didn't optimize for content
- Row heights were too small, making text cramped on high-resolution displays
- Column headers were generic ("Application" instead of "Application Name")

**Solution:**

1. **Dynamic Row Height Control**
   - Added ImageList to control row height
   - Row height = font size × 2.2 for comfortable spacing
   - Minimum row height of 24px
   - Scales automatically with font size on different resolutions
   - Example: 11pt font → 24px rows, 20pt font → 44px rows, 30pt font → 66px rows

2. **Optimized Column Widths**
   - Application: 40% → 45% (more space for long app names)
   - Category: 20% → 20% (unchanged, adequate)
   - Status: 18% → 15% (reduced, "Installed" fits easily)
   - Version: 20% → 18% (slightly reduced but still adequate)
   - Total: 98% (2% reserved for scrollbar and margins)

3. **Improved Column Headers**
   - "Application" → "Application Name" (more descriptive)
   - "Category" → "Category" (unchanged, clear)
   - "Status" → "Install Status" (more specific)
   - "Version" → "Version" (unchanged, clear)

**Row Height Examples by Resolution:**

| Resolution | Font Size | Row Height | Spacing |
|------------|-----------|------------|---------|
| FHD @ 100% | 11pt | 24px | Comfortable |
| FHD @ 125% | 14pt | 31px | Spacious |
| QHD @ 100% | 14pt | 31px | Spacious |
| 4K @ 100% | 20pt | 44px | Very spacious |
| 4K @ 150% | 30pt | 66px | Extra spacious |

**Benefits:**
- ✅ Text no longer cramped in rows
- ✅ Column widths optimized for content
- ✅ Headers more descriptive and clear
- ✅ Row height scales with font size automatically
- ✅ Better readability on all screen sizes
- ✅ Professional table appearance

**Files Modified:**
- `app_installer/install-gui.ps1` (enhanced ListView layout)
- `app_installer/CHANGELOG.md` (documented changes)

## [1.3.5] - 2025-10-31

### Fixed - Responsive Font Scaling for High-Resolution Displays 🎨

- **Implemented resolution-aware font scaling**
- **Text now readable on HD, FHD, QHD, 4K UHD, UWQHD, and UW4K displays**

**Issue:**
- GUI window resized correctly for different screen resolutions
- But text (ListView, TextBox, Labels, Buttons) was too small on 4K screens
- Font sizes only scaled with DPI, not with screen resolution
- 9pt base font was unreadable on 4K displays even with DPI scaling

**Solution:**

1. **Added Resolution-Based Font Scaling**
   - Detects screen resolution category (HD, FHD, QHD, 4K, UWQHD, UW4K)
   - Applies resolution-specific scaling multiplier:
     - HD (1280x720): 1.0x
     - FHD (1920x1080): 1.0x
     - QHD (2560x1440): 1.3x
     - 4K UHD (3840x2160): 1.8x
     - UWQHD (3440x1440): 1.3x
     - UW4K (5120x2160): 1.8x

2. **Increased Base Font Sizes**
   - Title: 16pt → 18pt base
   - Normal text: 9pt → 11pt base
   - Console text: 9pt → 10pt base

3. **Combined DPI and Resolution Scaling**
   - Combines Windows DPI scaling with resolution scaling
   - Formula: `fontSize = baseSize * dpiScale * resolutionScale`
   - Example on 4K with 150% DPI: 11pt * 1.5 * 1.8 = 29.7pt

4. **Updated Get-OptimalFormSize Function**
   - Now returns resolution category name
   - Returns combined scale factor
   - Logs all scaling information

5. **Updated Version Label**
   - Shows resolution category (e.g., "4K UHD")
   - Helps users verify correct scaling is applied

**Font Size Examples:**

| Resolution | DPI | Title Font | Normal Font | Console Font |
|------------|-----|------------|-------------|--------------|
| FHD (1920x1080) | 100% | 18pt | 11pt | 10pt |
| FHD (1920x1080) | 125% | 23pt | 14pt | 13pt |
| QHD (2560x1440) | 100% | 23pt | 14pt | 13pt |
| QHD (2560x1440) | 125% | 29pt | 18pt | 16pt |
| 4K (3840x2160) | 100% | 32pt | 20pt | 18pt |
| 4K (3840x2160) | 150% | 49pt | 30pt | 27pt |

**Benefits:**
- ✅ Text readable on all screen resolutions
- ✅ Automatic scaling based on screen size
- ✅ Respects Windows DPI settings
- ✅ No manual configuration needed
- ✅ Consistent user experience across devices

**Files Modified:**
- `app_installer/install-gui.ps1` (enhanced font scaling)
- `app_installer/CHANGELOG.md` (documented changes)

## [1.3.4] - 2025-10-31

### Fixed - GUI Window Not Appearing 🔧

- **Added comprehensive error handling and debug output**
- **Investigating why GUI window doesn't appear despite successful initialization**

**Issue:**
- Console shows successful initialization
- Files copied to system location
- Logging initialized
- Form created successfully
- But GUI window doesn't appear on screen

**Changes Made:**

1. **Added Try-Catch Block**
   - Wrapped entire main execution in try-catch
   - Catches and displays any errors
   - Shows error dialog if initialization fails
   - Logs errors to file

2. **Added Debug Output**
   - Shows each initialization step
   - Confirms logging initialized
   - Confirms form created
   - Confirms buttons created
   - Confirms application detection complete
   - Shows when ShowDialog() is called
   - Shows ShowDialog() return value

3. **Better Error Messages**
   - Displays error message in console
   - Displays error message in dialog box
   - Shows stack trace for debugging
   - Logs errors to file

**Debug Output Added:**
```
[i] Initializing logging...
[OK] Logging initialized
[i] Creating GUI form...
[OK] Main form created
[i] Creating buttons...
[OK] Buttons created
[i] Detecting installed applications...
[OK] Application detection complete
[OK] GUI initialized successfully!
[i] Showing GUI window...
[i] Calling ShowDialog()...
[i] ShowDialog() returned: <result>
```

**Purpose:**
- Identify exactly where the GUI initialization is failing
- Provide detailed error messages if something goes wrong
- Help diagnose why the window isn't appearing

## [1.3.3] - 2025-10-31

### Fixed - Critical GUI Launch Issues 🔧

- **Fixed GUI Not Launching**
  - Added missing self-installation functionality
  - Fixed initialization order issues
  - GUI now launches properly and copies itself to system location

**Issues Fixed:**
- ❌ **Problem:** GUI script didn't launch at all
- ❌ **Problem:** No logging occurred
- ❌ **Problem:** Script not copied to `C:\mytech.today\app_installer\`
- ✅ **Solution:** Added self-installation function
- ✅ **Solution:** Fixed initialization order
- ✅ **Solution:** Added proper error handling

**Changes Made:**

1. **Added Self-Installation Function**
   - Copied `Copy-ScriptToSystemLocation()` from CLI version
   - Copies both `install.ps1` and `install-gui.ps1` to system location
   - Copies all app scripts from `apps\` folder
   - Copies documentation files (CHANGELOG.md, README.md)
   - Creates system directories if they don't exist
   - Falls back to original location if copy fails

2. **Fixed Initialization Order**
   - Initialize logging FIRST (before any Write-Log calls)
   - Create form SECOND (creates OutputTextBox control)
   - Call Write-Output THIRD (after OutputTextBox exists)
   - Show form LAST (blocks until closed)

3. **Added Console Output**
   - Shows installation progress in console
   - Displays system location path
   - Shows success/failure messages
   - Helps with debugging

**Execution Flow (Fixed):**
```
1. Display header banner
2. Copy script to C:\mytech.today\app_installer\
3. Initialize logging system
4. Create GUI form and controls
5. Detect installed applications
6. Show GUI window
7. Wait for user interaction
8. Close and cleanup
```

**Self-Installation Details:**
- Source: Current script location (e.g., Q:\_kyle\...\app_installer\)
- Target: `C:\mytech.today\app_installer\`
- Files copied:
  - install.ps1 (CLI version)
  - install-gui.ps1 (GUI version)
  - apps\*.ps1 (all app installation scripts)
  - CHANGELOG.md
  - README.md

**Console Output Example:**
```
+===================================================================+
|         myTech.Today Application Installer GUI v1.3.3          |
+===================================================================+

[i] Installing to system location...
    Source: Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer
    Target: C:\mytech.today\app_installer
    [>>] Copying install.ps1...
    [>>] Copying install-gui.ps1...
    [>>] Copying app scripts...
    [OK] Copied 26 app scripts
    [OK] Installation to system location complete!
    Location: C:\mytech.today\app_installer

[i] Initializing GUI...
[OK] GUI initialized successfully!

[GUI window opens]
```

**Benefits:**
- ✅ GUI now launches properly
- ✅ Logging works correctly
- ✅ Script copied to system location
- ✅ Scheduled tasks can find the script
- ✅ Consistent with CLI version behavior
- ✅ Better error messages
- ✅ Console feedback during initialization

## [1.3.2] - 2025-10-31

### Enhanced - Responsive GUI for High-Resolution Displays 🖥️

- **Responsive Design for 2K, 4K, and Ultra-Wide Displays**
  - GUI now automatically adapts to screen resolution
  - Optimal sizing for all display types (1080p, 2K, 4K, ultra-wide)
  - DPI-aware scaling for high-resolution displays

**Responsive Features:**
- 📐 **Dynamic Form Sizing**
  - Form size calculated as 70% width, 80% height of screen
  - Maximum size: 2400x1400 pixels
  - Minimum size: 1000x600 pixels
  - Automatically centers on screen

- 🔍 **DPI-Aware Scaling**
  - Font sizes scale with DPI settings
  - Title font: 16pt base (scales up on high-DPI)
  - Normal font: 9pt base (scales up on high-DPI)
  - Console font: 9pt base (scales up on high-DPI)
  - Crisp text on all displays

- 📏 **Proportional Layout**
  - ListView: 58% of form width
  - Output console: 42% of form width
  - All controls resize with form
  - Maintains aspect ratios

- ⚓ **Anchor Properties**
  - All controls anchored to form edges
  - ListView: Top, Bottom, Left, Right (fully resizable)
  - Output console: Top, Bottom, Right (resizes vertically)
  - Progress bar: Bottom, Left, Right (stays at bottom)
  - Buttons: Bottom, Left (stay at bottom)
  - Labels: Top, Left, Right (stay at top)

- 📊 **Column Width Scaling**
  - Application column: 40% of ListView width
  - Category column: 20% of ListView width
  - Status column: 18% of ListView width
  - Version column: 20% of ListView width
  - Columns resize proportionally

- 🎯 **Button Sizing**
  - Buttons calculate width based on form width
  - Equal width distribution across 6 buttons
  - Minimum button width: 120 pixels
  - Responsive spacing maintained

**Screen Resolution Support:**
- ✅ **1080p (1920x1080)** - Form: 1344x864
- ✅ **2K (2560x1440)** - Form: 1792x1152
- ✅ **4K (3840x2160)** - Form: 2400x1400 (capped at max)
- ✅ **Ultra-wide (3440x1440)** - Form: 2400x1152
- ✅ **5K (5120x2880)** - Form: 2400x1400 (capped at max)

**Technical Implementation:**
- `Get-OptimalFormSize()` - Detects screen and calculates optimal size
- `[System.Windows.Forms.Screen]::PrimaryScreen` - Gets screen dimensions
- `[System.Drawing.Graphics]::FromHwnd()` - Detects DPI settings
- `AutoScaleMode = Dpi` - Enables DPI-aware scaling
- `Anchor` properties on all controls for responsive resizing
- Proportional calculations for all dimensions

**Benefits:**
- ✅ Perfect display on any screen size
- ✅ No more tiny GUI on 4K displays
- ✅ No more oversized GUI on 1080p displays
- ✅ Crisp, readable text on high-DPI displays
- ✅ Professional appearance on all resolutions
- ✅ Fully resizable window with maintained proportions
- ✅ Automatic adaptation to user's display

**Version Display:**
- Shows detected screen resolution in version label
- Example: "Version 1.3.2 - 65 Applications | Screen: 3840x2160"

## [1.3.1] - 2025-10-31

### Added - GUI Version 🎨

- **New GUI Application: install-gui.ps1**
  - Modern Windows Forms-based graphical user interface
  - All features from command-line version available in GUI
  - Professional, user-friendly design

**GUI Features:**
- 📋 **Application List View**
  - Sortable columns: Application, Category, Status, Version
  - Checkbox selection for each application
  - Color-coded status (Green = Installed, Red = Not Installed)
  - Real-time status updates

- 🎯 **Smart Selection Buttons**
  - Select All - Check all 65 applications
  - Select Missing - Check only applications not installed
  - Deselect All - Uncheck all applications
  - Individual checkbox selection

- 📊 **Real-time Progress Tracking**
  - Progress bar showing installation progress
  - Current/Total application counter
  - Status label showing current operation
  - Live output console with color-coded messages

- 💻 **Output Console**
  - Black background with green text (terminal-style)
  - Color-coded messages (Blue=Info, Green=Success, Red=Error, Orange=Warning)
  - Auto-scrolling to latest messages
  - Full installation log visibility

- 🔄 **Action Buttons**
  - Refresh Status - Re-scan installed applications
  - Install Selected - Install checked applications
  - Exit - Close the application

**GUI Layout:**
```
+------------------------------------------------------------------+
|  myTech.Today Application Installer                             |
|  Version 1.3.0 - 65 Applications                                 |
|  Status: Ready - 45 of 65 applications installed                 |
+------------------------------------------------------------------+
|                                    |                             |
|  Application List (Checkboxes)     |  Output Console             |
|  - Google Chrome [✓] Installed     |  > Detecting apps...        |
|  - Brave Browser [✓] Installed     |  > Found 45 installed       |
|  - Firefox [✓] Installed           |  > Ready                    |
|  - Visual Studio Code [ ] Missing  |                             |
|  - Postman [ ] Missing             |                             |
|  ...                               |                             |
|                                    |                             |
+------------------------------------------------------------------+
|  Progress: [████████░░░░░░░░░░] 8 / 10 applications             |
+------------------------------------------------------------------+
|  [Refresh] [Select All] [Select Missing] [Deselect] [Install] [Exit] |
+------------------------------------------------------------------+
```

**Technical Details:**
- Uses System.Windows.Forms for maximum compatibility
- Responsive UI with DoEvents() during installation
- Same logging system as command-line version
- Same application registry (65 apps, 13 categories)
- Same installation methods (winget + custom scripts)
- Requires PowerShell 5.1+ and Administrator privileges

**Benefits:**
- ✅ User-friendly graphical interface
- ✅ Visual feedback during installation
- ✅ Easy application selection with checkboxes
- ✅ Real-time progress tracking
- ✅ Professional appearance
- ✅ All command-line features available
- ✅ No learning curve for non-technical users

**Usage:**
```powershell
# Run the GUI installer
.\app_installer\install-gui.ps1

# Or from system location
C:\mytech.today\app_installer\install-gui.ps1
```

## [1.3.0] - 2025-10-31

### Added - 39 New Applications 🚀

- **Massive Expansion: Added 39 Professional Applications**
  - Expanded from 26 to 65 total applications
  - Added 7 new categories for better organization
  - All new apps support automatic installation via winget

**New Categories Added:**
- 💬 **COMMUNICATION** (3 apps) - Telegram, Signal, Thunderbird
- 🎨 **3D & CAD** (4 apps) - Blender, FreeCAD, LibreCAD, KiCad
- 🌐 **NETWORKING** (3 apps) - Nmap, Wireshark, Zenmap
- ⚙️ **RUNTIME** (1 app) - Java Runtime Environment
- ✍️ **WRITING** (3 apps) - Trelby, KIT Scenarist, Storyboarder

**Development Tools (7 new apps):**
- Visual Studio Code - Microsoft's popular code editor
- Postman - HTTP API testing tool
- PyCharm Community - Python IDE by JetBrains
- Eclipse IDE - Java development environment
- Atom Editor - Hackable text editor
- Brackets - Modern web design editor
- Vagrant - Development environment automation

**Communication (3 new apps):**
- Telegram Desktop - Secure messaging platform
- Signal - Privacy-focused messaging
- Thunderbird - Email client by Mozilla

**Media & Graphics (8 new apps):**
- VLC Media Player - Universal media player
- FFmpeg - Multimedia processing framework
- Krita - Professional digital painting
- OpenToonz - 2D animation software
- Kdenlive - Video editor
- Shotcut - Cross-platform video editor
- darktable - Photography workflow & RAW developer
- RawTherapee - RAW photo processing

**Productivity (3 new apps):**
- 7-Zip - File archiver with high compression
- Adobe Acrobat Reader - PDF viewer
- Apache OpenOffice - Office suite

**3D & CAD (4 new apps):**
- Blender - 3D creation suite
- FreeCAD - Parametric 3D modeler
- LibreCAD - 2D CAD application
- KiCad - Electronic design automation (EDA)

**Networking & Security (3 new apps):**
- Nmap - Network discovery and security auditing
- Wireshark - Network protocol analyzer
- Zenmap - Nmap GUI interface

**System Utilities (5 new apps):**
- WinDirStat - Disk usage analyzer
- Core Temp - CPU temperature monitoring
- GPU-Z - Graphics card information
- CrystalDiskInfo - Hard disk health monitoring
- Sysinternals Suite - Windows system utilities

**Runtime Environments (1 new app):**
- Java Runtime Environment - Required for Java applications

**Writing & Screenwriting (3 new apps):**
- Trelby - Screenwriting software
- KIT Scenarist - Script writing with research tools
- Storyboarder - Storyboarding software

**Technical Details:**
- All apps use PSCustomObject for proper grouping
- Most apps have WingetId for automatic installation
- Apps without WingetId will need custom installation scripts
- Categories automatically displayed in menu
- Total applications: 65 (was 26)
- Total categories: 13 (was 8)

**Benefits:**
- ✅ Comprehensive software collection for professionals
- ✅ Covers development, media, CAD, networking, and more
- ✅ One-click installation for all supported apps
- ✅ Organized by category for easy navigation
- ✅ Automatic updates via winget

## [1.2.1] - 2025-10-31

### Fixed - Category Grouping Not Working 🔧

- **Fixed Critical Bug: Category Headers Showing as Empty**
  - Category headers were displaying as "  ===  ===" instead of "  === BROWSERS ==="
  - All applications were grouped into a single category with empty name
  - Applications were not being separated by category

**Root Cause:**
- Application registry used hashtables (`@{ ... }`)
- PowerShell's `Group-Object` cmdlet doesn't work properly with hashtables
- Hashtables use bracket notation (`$app['Category']`) not dot notation (`$app.Category`)
- `Group-Object -Property Category` couldn't access the Category property

**Solution:**
- Converted all hashtables to PSCustomObjects using `[PSCustomObject]@{ ... }`
- PSCustomObjects support dot notation for property access
- `Group-Object -Property Category` now works correctly
- Applications now properly grouped by category

**Before (Broken):**
```powershell
$script:Applications = @(
    @{ Name = "Chrome"; Category = "Browsers" }  # Hashtable
)
```

**After (Fixed):**
```powershell
$script:Applications = @(
    [PSCustomObject]@{ Name = "Chrome"; Category = "Browsers" }  # PSCustomObject
)
```

**Impact:**
- ✅ Category headers now display correctly: "=== BROWSERS ==="
- ✅ Applications properly grouped by category
- ✅ Menu now organized and easy to navigate
- ✅ All 8 categories display with proper names

**Technical Details:**
- Changed 26 application definitions from hashtables to PSCustomObjects
- No changes to property names or values
- Maintains backward compatibility with all existing code
- `Group-Object`, `Sort-Object`, and property access all work correctly now

## [1.2.0] - 2025-10-31

### Improved - Prominent Category Headers 🎨

- **Enhanced Category Display for Better Organization**
  - Category headers now prominently displayed with visual separators
  - Categories shown in UPPERCASE with colored formatting
  - Better visual hierarchy makes it easier to scan the application list

**Before:**
```
  [Browsers]
    1. Google Chrome - [OK] Installed
    2. Brave Browser - [ ] Not Installed
```

**After:**
```
  === BROWSERS ===

    1. Google Chrome - [OK] Installed
    2. Brave Browser - [ ] Not Installed
```

**Categories:**
- 🌐 **BROWSERS** - Chrome, Brave, Firefox
- 💻 **DEVELOPMENT** - Notepad++, Git, Python, Node.js, Docker
- 📊 **PRODUCTIVITY** - LibreOffice
- 🎬 **MEDIA** - OBS Studio, GIMP, Audacity, Handbrake, OpenShot, ClipGrab
- 🔧 **UTILITIES** - AngryIP Scanner, CCleaner, Bitvise, Belarc, O&O ShutUp10, FileMail
- 🔒 **SECURITY** - Avira Antivirus
- 🔗 **SHORTCUTS** - Grok AI, ChatGPT, dictation.io
- 🛠️ **MAINTENANCE** - Uninstall McAfee

**Technical Details:**
- Category headers use Cyan and Yellow colors for visibility
- Categories displayed in UPPERCASE for prominence
- Visual separators (===) make categories stand out
- Blank lines before/after category headers improve readability
- Applications still grouped and sorted by category

**Benefits:**
- ✅ Much easier to find applications by category
- ✅ Better visual organization
- ✅ Clearer menu structure
- ✅ Professional appearance
- ✅ Improved user experience

## [1.1.1] - 2025-10-31

### Improved - Menu Clarity for Individual App Installation 📋

- **Made Individual App Installation More Discoverable**
  - Added menu hint: "1-26. Install Specific Application (type number)"
  - Updated prompt: "Enter your choice (number or letter):"
  - Functionality already existed but wasn't clearly communicated to users

**What Changed:**
- Menu now explicitly shows users can type a number (1-26) to install specific apps
- Prompt clarifies that both numbers and letters are accepted
- No code logic changes - just improved user guidance

**Example:**
```
  [Actions]
    1-26. Install Specific Application (type number)
    A. Install All Applications
    M. Install Missing Applications Only
    S. Show Status Only
    R. Refresh Status
    Q. Quit

Enter your choice (number or letter): _
```

**Benefits:**
- ✅ Users now know they can install individual apps by number
- ✅ Clearer, more intuitive menu
- ✅ Better user experience
- ✅ No breaking changes

## [1.1.0] - 2025-10-31

### Fixed - ReadKey Fatal Error 🔧

- **Fixed Fatal Error: "Exception calling 'ReadKey' with '1' argument(s)"**
  - Error occurred when script tried to read key press after installation
  - `$Host.UI.RawUI.ReadKey()` not supported in all PowerShell environments
  - Caused script to crash with fatal error at the end

- **New Function: Read-KeySafe**
  - Safely reads key press with fallback mechanisms
  - Tries `$Host.UI.RawUI.ReadKey()` first (preferred method)
  - Falls back to `Read-Host` if RawUI not available
  - Falls back to 2-second pause if Read-Host fails
  - Handles PowerShell ISE, remote sessions, and non-interactive environments

- **Replaced All ReadKey Calls**
  - All `$Host.UI.RawUI.ReadKey()` calls replaced with `Read-KeySafe`
  - No more fatal errors when pressing keys
  - Works in all PowerShell environments
  - Graceful degradation for unsupported environments

**Technical Details:**
- `Read-KeySafe` function with triple-fallback mechanism
- Try-catch blocks handle all error scenarios
- Works in: PowerShell Console, PowerShell ISE, VS Code, Remote Sessions
- Simplified user prompts (removed redundant "Press any key" text)

**Benefits:**
- ✅ No more fatal errors
- ✅ Works in all PowerShell environments
- ✅ Graceful error handling
- ✅ Better user experience

## [1.0.9] - 2025-10-31

### Added - Self-Installation to System Location 📦

- **Automatic Installation to System Location**
  - Script now copies itself to `%SystemDrive%\mytech.today\app_installer\` on first run
  - Ensures installer is always available in a known, permanent location
  - Scheduled tasks and automation always use the system location
  - Prevents issues if original script location is deleted or moved

- **New Function: Copy-ScriptToSystemLocation**
  - Copies install.ps1 to system location
  - Copies all app scripts from apps\ folder
  - Copies documentation files (CHANGELOG.md, README.md)
  - Creates directory structure automatically
  - Handles errors gracefully with fallback to original location

- **Smart Path Management**
  - Detects if already running from system location (skips copy)
  - Updates internal paths to use system location after copy
  - Scheduled task always points to system location
  - Works regardless of where script is originally run from

**System Location Structure:**
```
%SystemDrive%\mytech.today\app_installer\
├── install.ps1
├── CHANGELOG.md
├── README.md
└── apps\
    ├── chrome.ps1
    ├── firefox.ps1
    ├── winget-update.ps1
    └── [all other app scripts]
```

**Benefits:**
- ✅ Installer always available in predictable location
- ✅ Scheduled tasks work reliably
- ✅ No dependency on original script location
- ✅ Professional installation experience
- ✅ Easy to find and manage

**Technical Details:**
- Runs before any other script logic
- Creates `C:\mytech.today\app_installer\` directory
- Copies all .ps1 files from apps\ folder
- Updates `$script:ScriptPath` and `$script:AppsPath` variables
- Install-MonthlyUpdateTask explicitly uses system location
- Falls back to original location if copy fails

## [1.0.8] - 2025-10-31

### Fixed - Scheduled Task Creation Error 🔧

- **Fixed PowerShell 5.1 Compatibility Issue**
  - Replaced `New-ScheduledTaskTrigger -Monthly` with `schtasks.exe`
  - Error was: "A parameter cannot be found that matches parameter name 'Monthly'"
  - PowerShell 5.1 doesn't support `-Monthly` parameter on `New-ScheduledTaskTrigger`
  - Now uses `schtasks.exe` for maximum compatibility

- **Refactored Install-MonthlyUpdateTask Function**
  - Completely rewritten to use `schtasks.exe` command-line tool
  - Works reliably across all PowerShell versions (5.1, 7+)
  - Simpler, more maintainable code
  - Better error handling and reporting

**Technical Details:**
- Uses `schtasks.exe /Create` with `/SC MONTHLY /D 15 /ST 13:00`
- Checks for existing task and deletes before recreating
- Runs with highest privileges (`/RL HIGHEST`)
- Runs as current user (`/RU $env:USERDOMAIN\$env:USERNAME`)

**Benefits:**
- Universal compatibility with all Windows versions
- No dependency on PowerShell version-specific cmdlets
- More reliable task creation
- Clearer error messages

## [1.0.7] - 2025-10-31

### Added - Monthly Automatic Updates 🔄

- **Created Monthly Update Scheduled Task**
  - Automatically creates Windows scheduled task on first run
  - Task runs on 15th of every month at 1:00 PM
  - Located in Task Scheduler under "myTech.Today" folder
  - Task name: "Monthly Application Updates"
  - Runs with highest privileges (triggers UAC prompt)

- **New Script: winget-update.ps1**
  - Runs `winget update --all` to update all applications
  - Displays friendly, verbose explanation to users
  - Explains why Microsoft UAC prompts appear
  - Provides clear instructions: "Click OK/Yes/Allow"
  - Includes myTech.Today branding and contact information
  - Logs all updates to `C:\mytech.today\logs\winget-update-YYYY-MM.log`

- **User-Friendly Messaging**
  - Explains what's happening and why
  - Addresses Microsoft's security prompts proactively
  - Reduces user confusion and anxiety
  - Provides 10-second countdown before starting updates
  - Shows completion message with next update date

- **Task Scheduler Integration**
  - Uses PowerShell ScheduledTasks module
  - Creates custom task folder: "myTech.Today"
  - Configures task to run even on battery power
  - Starts task if missed (StartWhenAvailable)
  - Requires network connection
  - 2-hour execution time limit

**Schedule Details:**
- **Frequency:** Monthly
- **Day:** 15th of each month
- **Time:** 1:00 PM
- **Privileges:** Highest (Administrator)
- **User Context:** Current user (Interactive logon)

**Benefits:**
- Keeps all applications up-to-date automatically
- Improves security with regular updates
- Reduces manual maintenance burden
- Clear communication reduces user confusion
- Professional branding reinforces myTech.Today services

## [1.0.6] - 2025-10-31

### Fixed - URL Display Issue 🔧

- **Removed ANSI Hyperlink Escape Sequences**
  - Simplified website URL display to plain text
  - Removed ANSI escape sequences that were displaying as literal characters
  - Fixed display issue: `]8;;https://mytech.today\https://mytech.today]8;;\`
  - Now displays cleanly as: `https://mytech.today`
  - Universal compatibility across all PowerShell consoles

**Before:**
```
Web:     ]8;;https://mytech.today\https://mytech.today]8;;\
```

**After:**
```
Web:     https://mytech.today
```

**Benefits:**
- Clean, readable URL display in all consoles
- No escape sequence artifacts
- Users can still copy/paste URL to browser
- Works in PowerShell 5.1, 7+, ISE, cmd.exe, all terminals

## [1.0.5] - 2025-10-31

### Added - Marketing and Contact Information 📢

- **Added Professional Marketing Blurb**
  - Displays after program completion
  - Includes company description and service offerings
  - Highlights myTech.Today as MSP serving Barrington, IL and Chicagoland
  - Lists core services: IT consulting, PowerShell automation, cloud integration, etc.

- **Added Contact Information**
  - Email: sales@mytech.today
  - Phone: (847) 767-4914
  - Website: https://mytech.today (clickable hyperlink)
  - Location: Barrington, IL / Chicagoland area

- **Clickable Hyperlink Support**
  - Website URL is clickable in modern terminals (Windows Terminal, VS Code, etc.)
  - Uses ANSI escape sequences for hyperlink functionality
  - Fallback to plain text in older consoles

**Benefits:**
- Professional branding and marketing
- Easy access to contact information
- Promotes myTech.Today services to users
- Clickable link for immediate website access

## [1.0.4] - 2025-10-31

### Fixed - Character Encoding for Console Compatibility 🔧

- **Replaced Unicode Emoji with ASCII Equivalents** ✅ → [OK]
  - Removed all Unicode emoji characters (✅, ❌, ⚠️, ℹ️, ⏭️)
  - Replaced with ASCII-safe alternatives ([OK], [X], [!], [i], [>>])
  - Fixes display issues in PowerShell consoles that don't support Unicode emojis
  - Ensures consistent display across all Windows versions and console configurations

**Replacements Made:**
- ✅ → [OK] (success/installed)
- ❌ → [X] (error/not installed)
- ⚠️ → [!] (warning)
- ℹ️ → [i] (info)
- ⏭️ → [>>] (skipped)

**Files Updated:**
- `install.ps1` - Main installer script
- All 26 app installation scripts in `apps/` directory

**Benefits:**
- ✅ Universal compatibility across all PowerShell consoles
- ✅ No more garbled characters (âœ…, âŒ) in output
- ✅ Consistent display on Windows 10, 11, Server editions
- ✅ Works in PowerShell ISE, VS Code, Windows Terminal, cmd.exe

## [1.0.3] - 2025-10-31

### Added - Complete App Installation Scripts 📦

- **Created 19 Missing Installation Scripts** ✅
  - All applications defined in `install.ps1` now have corresponding installation scripts
  - Previously only 7 scripts existed, now all 26 apps have dedicated scripts
  - Ensures consistency and maintainability across the installer

**New Scripts Created:**
- **Browsers**: chrome.ps1, brave.ps1, firefox.ps1
- **Development**: notepadplusplus.ps1, git.ps1, python.ps1, nodejs.ps1, docker.ps1
- **Productivity**: libreoffice.ps1
- **Media**: obs.ps1, gimp.ps1, audacity.ps1, handbrake.ps1, openshot.ps1, clipgrab.ps1
- **Utilities**: angryip.ps1, ccleaner.ps1, bitvise.ps1
- **Security**: avira.ps1

**Existing Scripts (7):**
- belarc.ps1, chatgpt-shortcuts.ps1, dictation-shortcut.ps1, filemail.ps1, grok-shortcuts.ps1, shutup10.ps1, uninstall-mcafee.ps1

### Technical Details

**Script Template:**
- All new scripts use standardized winget-based installation
- Proper error handling with try-catch blocks
- Winget availability checking
- Silent installation with automatic agreement acceptance
- Clear success/failure reporting with colored output
- Exit codes for automation (0 = success, 1 = failure)

**Benefits:**
- ✅ Complete coverage: All 26 apps in `$script:Applications` array now have scripts
- ✅ Consistency: Standardized template across all winget-based installations
- ✅ Maintainability: Easy to modify individual app installations
- ✅ Extensibility: Clear pattern for adding new applications
- ✅ Reliability: Proper error handling and status reporting

## [1.0.2] - 2025-10-31

### Fixed - Smart Quotes in Box-Drawing Characters ðŸ"§

- **Character Encoding Issue** âŒ â†' âœ…
  - Replaced Unicode box-drawing characters (â•"â•â•—â•'â•šâ•) with ASCII equivalents (+===+|||)
  - Fixed error: "The string is missing the terminator"
  - Smart quotes (curly quotes) were embedded in box-drawing characters causing parse errors
  - Affected lines: 286-288, 408-410, 426-428, 443-445, 469-471

- **ReadKey Parameter Quotes** âŒ â†' âœ…
  - Replaced double quotes with single quotes for ReadKey parameters
  - Changed `"NoEcho,IncludeKeyDown"` to `'NoEcho,IncludeKeyDown'`
  - Prevents potential quote-related parse issues
  - Affected lines: 515, 519, 525, 530, 542

### Changed

- **Menu Display** ðŸ"
  - Box-drawing characters changed from Unicode (â•"â•â•—â•'â•šâ•) to ASCII (+===+|||)
  - Maintains visual structure with better compatibility
  - No functionality changes

### Technical Details

**Before (Unicode box-drawing with embedded smart quotes):**
```
â•"â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
â•'         myTech.Today Application Installer v1.0.1              â•'
â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
```

**After (ASCII box-drawing):**
```
+===================================================================+
|         myTech.Today Application Installer v1.0.2              |
+===================================================================+
```

### Root Cause

The Unicode box-drawing characters contained embedded smart quotes (LEFT SINGLE QUOTATION MARK U+2018, RIGHT DOUBLE QUOTATION MARK U+2021) which PowerShell's parser interpreted as string delimiters, causing "missing terminator" errors.

### Impact

âœ… **PowerShell 5.1 Compatible** - Script now parses correctly on all PowerShell versions
âœ… **No Parse Errors** - Eliminated all string terminator errors
âœ… **ASCII-Safe** - Uses only ASCII characters for box-drawing
âœ… **No Functionality Changes** - Same behavior, just compatible characters

### Testing

Tested with PowerShell parser:
- âœ… PowerShell 5.1 (Windows 10) - No parse errors
- âœ… PowerShell 7.2+ (Windows 11) - No parse errors

## [1.0.1] - 2025-10-31

### Fixed - PowerShell 5.1 Compatibility ðŸ"§

- **Null-Coalescing Operator Removed** âŒ â†' âœ…
  - Replaced `??` operator with PowerShell 5.1 compatible if-else syntax
  - Fixed error: "Unexpected token '??' in expression or statement"
  - The `??` operator is only available in PowerShell 7.0+
  - Changed line 261 from `$match.DisplayVersion ?? "Installed"` to proper if-else statement

### Changed

- **Version Detection** ðŸ"
  - Updated version detection logic to use if-else instead of null-coalescing operator
  - Maintains same functionality with PowerShell 5.1 compatibility
  - No breaking changes to functionality

### Technical Details

**Before (PowerShell 7+ only):**
```powershell
$installedApps[$app.Name] = $match.DisplayVersion ?? "Installed"
```

**After (PowerShell 5.1+ compatible):**
```powershell
$version = if ($match.DisplayVersion) { $match.DisplayVersion } else { "Installed" }
$installedApps[$app.Name] = $version
```

### Impact

âœ… **PowerShell 5.1 Compatible** - Script now works on Windows 10 with PowerShell 5.1
âœ… **No Functionality Changes** - Same behavior, just compatible syntax
âœ… **Backward Compatible** - Works on PowerShell 5.1, 7.0, 7.1, 7.2+

### Testing

Tested on:
- âœ… PowerShell 5.1 (Windows 10)
- âœ… PowerShell 7.2+ (Windows 11)

## [1.0.0] - 2025-10-31

### Added - Initial Release ðŸŽ‰

#### Main Features
- **Interactive Menu Interface** ðŸ"‹
  - Menu-driven application installer with real-time status display
  - Color-coded status indicators (âœ… Installed, âŒ Not Installed)
  - Organized by category (Browsers, Development, Productivity, Media, Utilities, Security, Shortcuts, Maintenance)
  - Support for 27+ applications

- **Installation Modes** ðŸš€
  - **Interactive Menu:** Select individual apps or batch operations
  - **Install All:** Install all 27+ applications automatically
  - **Install Missing:** Install only applications not currently installed
  - **Status Display:** View installation status without making changes
  - **Command-Line Support:** Non-interactive mode for automation

- **Version Detection** ðŸ"
  - Automatic detection of installed applications
  - Version number display for installed apps
  - Uses winget list for fast, accurate detection
  - Fallback to Windows registry for comprehensive coverage

- **Centralized Logging** ðŸ"
  - All activities logged to `C:\mytech.today\logs\install-yyyy-MM.md`
  - Markdown table format with icons (â„¹ï¸ INFO, âš ï¸ WARNING, âŒ ERROR, âœ… SUCCESS)
  - Monthly log rotation
  - Detailed activity tracking

- **winget Integration** ðŸ"¦
  - Leverages Windows Package Manager for most installations
  - Silent installation support
  - Automatic package verification
  - Fallback for systems without winget

#### Supported Applications (27+)

**Browsers:**
- Google Chrome (`Google.Chrome`)
- Brave Browser (`Brave.Brave`)
- Firefox (`Mozilla.Firefox`)

**Development Tools:**
- Notepad++ (`Notepad++.Notepad++`)
- Git (`Git.Git`)
- Python 3.12 (`Python.Python.3.12`)
- Node.js LTS (`OpenJS.NodeJS.LTS`)
- Docker Desktop (`Docker.DockerDesktop`)

**Productivity:**
- LibreOffice Suite (`TheDocumentFoundation.LibreOffice`)

**Media & Creative:**
- OBS Studio (`OBSProject.OBSStudio`)
- GIMP (`GIMP.GIMP`)
- Audacity (`Audacity.Audacity`)
- Handbrake (`HandBrake.HandBrake`)
- OpenShot Video Editor (`OpenShot.OpenShot`)
- ClipGrab (`Philipp Schmieder.ClipGrab`)

**Utilities:**
- AngryIP Scanner (`angryziber.AngryIPScanner`)
- CCleaner (`Piriform.CCleaner`)
- Bitvise SSH Client (`Bitvise.SSH.Client`)
- Belarc Advisor (custom installer)
- O&O ShutUp10++ (custom installer)
- FileMail Desktop (custom installer)

**Security:**
- Avira Antivirus Free (`Avira.Avira`)
- Uninstall McAfee Products (custom removal tool)

**Shortcuts:**
- Grok AI (Desktop & Start Menu shortcuts to https://grok.x.ai)
- ChatGPT (Desktop & Start Menu shortcuts to https://chat.openai.com)
- dictation.io (Desktop & Start Menu shortcuts to https://dictation.io/speech)

#### Custom Installation Scripts

**Shortcut Creators:**
- `grok-shortcuts.ps1` - Creates Grok AI shortcuts
- `chatgpt-shortcuts.ps1` - Creates ChatGPT shortcuts
- `dictation-shortcut.ps1` - Creates dictation.io shortcuts

**Custom Installers:**
- `shutup10.ps1` - Downloads and installs O&O ShutUp10++ privacy tool
- `belarc.ps1` - Downloads and installs Belarc Advisor system information tool
- `filemail.ps1` - Downloads and installs FileMail Desktop for large file transfers
- `uninstall-mcafee.ps1` - Uses official MCPR tool to remove all McAfee products

#### Technical Features

- **PowerShell Compatibility:** 5.1+ and 7.2+ compatible
- **Platform Support:** Windows 10 (1809+), Windows 11, Windows Server 2016+
- **Administrator Privileges:** Required and enforced via `#Requires -RunAsAdministrator`
- **Error Handling:** Comprehensive try-catch blocks with fallback solutions
- **Logging System:** Markdown-formatted logs with monthly rotation
- **Status Detection:** Multi-method detection (winget + registry)
- **Silent Installation:** Most apps install without user interaction
- **Color-Coded Output:** Visual feedback with color-coded console messages

#### myTech.Today Standards Compliance

âœ… **Centralized Logging:** All logs to `C:\mytech.today\logs\`  
âœ… **Markdown Log Format:** Table format with icons and timestamps  
âœ… **Monthly Log Rotation:** One file per month (`install-yyyy-MM.md`)  
âœ… **Branding:** myTech.Today author and copyright  
âœ… **Comment-Based Help:** Full PowerShell help documentation  

### Files Added

- `install.ps1` - Main menu-driven installer (570 lines)
- `apps/grok-shortcuts.ps1` - Grok AI shortcut creator
- `apps/chatgpt-shortcuts.ps1` - ChatGPT shortcut creator
- `apps/dictation-shortcut.ps1` - dictation.io shortcut creator
- `apps/uninstall-mcafee.ps1` - McAfee removal tool
- `apps/shutup10.ps1` - O&O ShutUp10++ installer
- `apps/belarc.ps1` - Belarc Advisor installer
- `apps/filemail.ps1` - FileMail Desktop installer
- `README.md` - Comprehensive documentation
- `CHANGELOG.md` - Version history (this file)
- `ai_prompts/prompt.01.md` - Original requirements

### Platform Support

- Windows 10 (1809 or later)
- Windows 11
- Windows Server 2016
- Windows Server 2019
- Windows Server 2022
- PowerShell 5.1 or later
- Requires Administrator privileges

### Dependencies

- **winget (Windows Package Manager):** Recommended for most installations
  - Included by default on Windows 11
  - Available via "App Installer" from Microsoft Store on Windows 10
- **Internet Connection:** Required for downloading applications
- **Administrator Rights:** Required for installation

### Known Limitations

- **winget Required:** Most applications require winget for installation
- **Internet Required:** Cannot install applications offline (except from cache)
- **Version Detection:** Some portable apps may not be detected
- **Silent Install:** Some apps may show brief UI during installation

### Future Enhancements

Potential features for future versions:
- Offline installation support with local package cache
- Configuration file for customizing application list
- Scheduled task for automatic updates
- Export/import of application selections
- Chocolatey fallback for apps not in winget
- Portable app support
- Custom installation paths
- Application update checker
- Uninstall functionality
- Application groups/profiles

### Related Issues

- GitHub Issue #2: Enhancement: Implement Comprehensive App Installer System with Menu-Driven Interface

### Testing

- Manual testing completed on Windows 11
- All installation methods verified
- Logging system tested
- Version detection tested
- Menu interface tested
- Command-line modes tested

### Documentation

- Complete README.md with installation and usage instructions
- Comment-based help for all functions
- Inline code documentation
- Troubleshooting guide
- Best practices section

### Security

- All downloads use HTTPS
- winget packages verified by Microsoft
- Custom scripts download from official sources only
- McAfee removal uses official MCPR tool
- No credentials or sensitive data stored
- Administrator privileges required and enforced

---

## Version History Summary

| Version | Date | Description |
|---------|------|-------------|
| 1.0.0 | 2025-10-31 | Initial release with 27+ applications, menu interface, and centralized logging |

---

**Developer:** myTech.Today  
**Repository:** https://github.com/mytech-today-now/PowerShellScripts  
**Issue Tracker:** https://github.com/mytech-today-now/PowerShellScripts/issues

[Unreleased]: https://github.com/mytech-today-now/PowerShellScripts/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mytech-today-now/PowerShellScripts/releases/tag/v1.0.0

