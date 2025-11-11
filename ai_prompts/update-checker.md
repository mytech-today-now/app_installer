Add application update checker functionality to 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' and 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install.ps1' to identify which installed applications have updates available.

Requirements:
- Add "Check for Updates" button/menu option
- Use 'winget upgrade' command to detect available updates
- Display list of applications with updates available
- Show current version and available version for each app
- Add "Update All" and "Update Selected" options
- Progress tracking during update process
- Log all update operations to centralized log
- GUI: Add button in button panel, show results in new dialog
- CLI: Add menu option "U" for Update Check

Implementation Details:
- Create Get-AvailableUpdates function that calls 'winget upgrade' and parses output
- Parse winget output to extract: app name, current version, available version, winget ID
- Create Update-Applications function that accepts array of apps to update
- Use 'winget upgrade --id {WingetId}' for each application
- Show progress bar/indicator during update process
- Handle errors gracefully (app not found, update failed, etc.)
- Match winget output to $script:Applications array by WingetId
- Follow .augment/ guidelines for PowerShell scripts

Testing:
- Run update check on system with outdated applications
- Verify version comparison is accurate
- Test updating single application
- Test updating multiple applications
- Verify error handling for failed updates
- Test with applications not installed via winget

Documentation:
- Update README.md with update checker documentation
- Update CHANGELOG.md with version increment (1.3.8 for GUI, 1.4.1 for CLI)
- Document winget upgrade command usage
- Add troubleshooting section for update failures