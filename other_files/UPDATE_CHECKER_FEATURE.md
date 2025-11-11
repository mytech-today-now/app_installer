# Application Update Checker Feature

## Overview

The Application Update Checker feature allows users to easily identify and install available updates for applications that were installed via winget. This feature integrates seamlessly with the existing installer interface and provides a streamlined update experience.

## Version

- **Feature Added:** Version 1.5.0
- **Date:** November 10, 2025
- **Previous Version:** 1.4.0 (Queue Management feature)

---

## Features

### 1. Update Detection

Automatically detects available updates for installed applications:

- **Winget Integration:** Uses `winget upgrade` command to check for updates
- **Version Comparison:** Shows current version vs. available version
- **Source Tracking:** Displays the source of each update (winget, msstore, etc.)
- **Comprehensive Scanning:** Checks all applications installed via winget

### 2. Update Selection Dialog

Interactive dialog for reviewing and selecting updates:

- **ListView Display:** Shows all available updates in a sortable list
- **Columns:**
  - Application name
  - Current version
  - Available version
  - Source
- **Checkboxes:** Select which updates to install
- **Select All / Deselect All:** Bulk selection controls
- **Update Selected:** Install only checked updates

### 3. Update Installation

Automated update process with progress tracking:

- **Silent Installation:** Updates run in the background
- **Progress Feedback:** Real-time status updates in output panel
- **Error Handling:** Graceful handling of failed updates
- **Success Tracking:** Counts successful and failed updates
- **Logging:** All operations logged to centralized log

### 4. User Interface

#### GUI Mode (install-gui.ps1)

- **Check for Updates Button:** Blue button in main button panel
- **Updates Dialog:** Windows Forms dialog with ListView
- **Confirmation Prompt:** Confirms before starting updates
- **Completion Summary:** Shows results after updates complete

#### CLI Mode (install.ps1)

- **Menu Option "U":** Check for Updates option in main menu
- **Text-Based Display:** Table showing available updates
- **Selection Prompts:** Choose which updates to install
- **Progress Indicators:** Text-based progress during updates

---

## User Experience

### GUI Workflow

1. **Click "Check for Updates":** Blue button in button panel
2. **Wait for Scan:** Winget scans for available updates
3. **Review Updates:** Dialog shows all available updates
   - All updates checked by default
   - Uncheck any you don't want to install
   - Use Select All / Deselect All as needed
4. **Click "Update Selected":** Confirms and starts update process
5. **Monitor Progress:** Watch output panel for real-time status
6. **View Results:** Completion dialog shows success/fail counts

### No Updates Available

If no updates are found:
- Message box displays: "All applications are up to date!"
- No further action required

### Update Dialog

```
┌─────────────────────────────────────────────────────────────────┐
│ Available Updates                                               │
├─────────────────────────────────────────────────────────────────┤
│ Found 5 application(s) with available updates:                 │
│                                                                 │
│ ☑ Application        │ Current Ver │ Available Ver │ Source   │
│ ☑ Google Chrome      │ 119.0.6045  │ 120.0.6099    │ winget   │
│ ☑ Visual Studio Code │ 1.84.2      │ 1.85.0        │ winget   │
│ ☑ 7-Zip              │ 23.00       │ 23.01         │ winget   │
│ ☑ VLC Media Player   │ 3.0.18      │ 3.0.20        │ winget   │
│ ☑ Git                │ 2.42.0      │ 2.43.0        │ winget   │
│                                                                 │
│ [Select All]  [Deselect All]      [Update Selected]  [Cancel]  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technical Implementation

### Core Functions

#### Get-AvailableUpdates

Checks for available updates using winget.

```powershell
function Get-AvailableUpdates {
    # Runs: winget upgrade
    # Parses output table
    # Returns array of update objects
    
    # Output format:
    # [PSCustomObject]@{
    #     Name = "Google Chrome"
    #     Id = "Google.Chrome"
    #     CurrentVersion = "119.0.6045"
    #     AvailableVersion = "120.0.6099"
    #     Source = "winget"
    # }
}
```

**Parsing Logic:**
1. Run `winget upgrade` command
2. Find header line (contains "Name", "Id", "Version", "Available")
3. Find separator line (dashes)
4. Parse each subsequent line until summary line
5. Split by multiple spaces (2+) to extract columns
6. Create PSCustomObject for each update

#### Update-Applications

Updates selected applications using winget.

```powershell
function Update-Applications {
    param([array]$Updates)
    
    # For each update:
    # 1. Run: winget upgrade --id {Id} --silent --accept-agreements
    # 2. Check exit code
    # 3. Log result
    # 4. Update UI
    
    # Returns hashtable:
    # @{
    #     SuccessCount = 3
    #     FailCount = 2
    #     Results = @(...)
    # }
}
```

**Update Process:**
- Uses `Start-Process` with `-Wait` for synchronous execution
- Passes `--silent` flag for unattended installation
- Auto-accepts source and package agreements
- Captures exit code for error handling
- Uses `Get-WingetErrorMessage` to translate exit codes

#### Show-UpdatesDialog (GUI Only)

Displays Windows Forms dialog with update list.

```powershell
function Show-UpdatesDialog {
    param([array]$Updates)
    
    # Creates:
    # - Form (700x500)
    # - Title label
    # - ListView with checkboxes
    # - Select All / Deselect All buttons
    # - Update Selected / Cancel buttons
    
    # Returns:
    # - Array of selected updates
    # - $null if cancelled
}
```

#### Check-ForUpdates (GUI Only)

Main orchestration function for GUI mode.

```powershell
function Check-ForUpdates {
    # 1. Get available updates
    # 2. Show "no updates" message if none found
    # 3. Show updates dialog
    # 4. Confirm update action
    # 5. Call Update-Applications
    # 6. Show completion message
}
```

---

## Winget Integration

### Commands Used

**Check for Updates:**
```powershell
winget upgrade
```

**Install Update:**
```powershell
winget upgrade --id {WingetId} --silent --accept-source-agreements --accept-package-agreements
```

### Output Parsing

Winget upgrade output format:
```
Name                 Id                  Version    Available  Source
-----------------------------------------------------------------
Google Chrome        Google.Chrome       119.0.6045 120.0.6099 winget
Visual Studio Code   Microsoft.VSCode    1.84.2     1.85.0     winget
7-Zip                7zip.7zip           23.00      23.01      winget

3 upgrades available.
```

**Parsing Strategy:**
- Split lines by `\r?\n`
- Find header line (regex: `Name.*Id.*Version.*Available`)
- Skip separator line (dashes)
- Parse data lines until summary line (regex: `^\d+\s+upgrade`)
- Split each line by 2+ spaces: `$line -split '\s{2,}'`

### Error Handling

Uses `Get-WingetErrorMessage` function to translate exit codes:
- `0` = Success
- `-1978335189` = Package not found
- `-1978335191` = Already installed
- `-1978335196` = Installation failed
- `-1978335221` = Upgrade failed
- And 50+ other error codes

---

## Logging

All update operations are logged to: `C:\mytech.today\logs\`

**Log Entries:**
```
[INFO] User initiated update check
[INFO] Checking for available updates using winget upgrade
[INFO] Winget upgrade command completed
[INFO] Found update: Google Chrome (119.0.6045 -> 120.0.6099)
[INFO] Found 5 application(s) with available updates
[INFO] Showing updates dialog with 5 available update(s)
[INFO] User selected 3 update(s) to install
[INFO] Starting update process for 3 application(s)
[INFO] Updating Google Chrome from 119.0.6045 to 120.0.6099
[INFO] Successfully updated Google Chrome
[ERROR] Failed to update Visual Studio Code: Installation failed (Exit code: -1978335196)
[INFO] Update process completed: 2 succeeded, 1 failed
```

---

## Benefits

1. **Convenience:** One-click update checking for all applications
2. **Visibility:** Clear view of current vs. available versions
3. **Control:** Choose which updates to install
4. **Efficiency:** Batch update multiple applications
5. **Reliability:** Uses official winget upgrade mechanism
6. **Transparency:** Detailed logging of all operations
7. **Safety:** Confirmation prompts before making changes

---

## Limitations

1. **Winget Only:** Only detects updates for apps installed via winget
2. **No Auto-Update:** Manual check required (no scheduled updates)
3. **No Rollback:** Cannot downgrade to previous versions
4. **Network Required:** Requires internet connection to check/download
5. **Admin Rights:** Some updates may require administrator privileges

---

## Future Enhancements

Potential improvements for future versions:

1. **Scheduled Checks:** Automatic update checking on schedule
2. **Auto-Update:** Option to automatically install updates
3. **Update Notifications:** Toast notifications when updates available
4. **Update History:** Track update history and rollback capability
5. **Selective Auto-Update:** Auto-update specific apps only
6. **Update Profiles:** Different update policies for different app categories
7. **Bandwidth Control:** Limit download speed for updates
8. **Update Staging:** Test updates before full deployment

---

## Related Features

- **Queue Management (v1.4.0):** Manage installation order
- **Search & Filter (v1.3.9):** Find applications quickly
- **.NET Framework Auto-Install (v1.3.8):** Ensure prerequisites
- **Progress Tracking:** Real-time status and ETA display
- **Centralized Logging:** All operations logged

---

This feature brings professional-grade update management to the myTech.Today Application Installer, making it easy to keep all installed applications up to date with minimal effort.

