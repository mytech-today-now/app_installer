Add uninstall functionality to 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' and 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install.ps1' to allow users to remove installed applications.

Requirements:
- Add "Uninstall Selected" button/menu option
- Only enable for applications that are currently installed
- Show confirmation dialog before uninstalling (list apps to be removed)
- Use 'winget uninstall' command for removal
- Progress tracking during uninstall process
- Log all uninstall operations to centralized log
- GUI: Add button next to "Install Selected", disable for non-installed apps
- CLI: Add menu option "R" for Remove/Uninstall
- Refresh version detection after uninstall completes

Implementation Details:
- Create Uninstall-Applications function that accepts array of apps to remove
- Use 'winget uninstall --id {WingetId} --silent' for each application
- Show confirmation dialog with app count and names
- Implement progress tracking (X of Y uninstalled)
- Handle errors gracefully (app not found, uninstall failed, etc.)
- Refresh $script:InstalledApps hashtable after uninstall
- Update UI to reflect new installation status
- Follow .augment/ guidelines for PowerShell scripts (ASCII-only indicators)

Testing:
- Install test application and then uninstall it
- Verify confirmation dialog shows correct app list
- Test uninstalling multiple applications
- Verify error handling for failed uninstalls
- Test with applications not installed via winget
- Verify UI updates after uninstall completes

Documentation:
- Update README.md with uninstall feature documentation
- Update CHANGELOG.md with version increment (1.3.8 for GUI, 1.4.1 for CLI)
- Add warnings about uninstalling critical applications
- Document winget uninstall command usage