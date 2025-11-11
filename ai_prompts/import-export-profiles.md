Feature 1: Export/Import Configuration Profiles
Add export/import configuration profile functionality to 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' and 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install.ps1'.

Requirements:
- Add "Export Selection" button/menu option to save current application selections to a JSON file
- Add "Import Selection" button/menu option to load application selections from a JSON file
- JSON format should include: selected apps, timestamp, computer name, user name, installer version
- Default save location: C:\mytech.today\app_installer\profiles\
- File naming convention: profile-{ComputerName}-{yyyy-MM-dd-HHmmss}.json
- GUI: Add buttons next to "Install Selected" button
- CLI: Add menu options "E" for Export and "I" for Import
- Validate JSON structure before importing
- Show confirmation dialog with app count before importing
- Log all export/import operations to centralized log

Implementation Details:
- Create Export-InstallationProfile function that accepts array of selected apps
- Create Import-InstallationProfile function that returns array of apps to select
- JSON structure: { "Version": "1.0", "Timestamp": "2025-11-09T16:00:00", "ComputerName": "PC01", "UserName": "user", "InstallerVersion": "1.3.7", "Applications": ["Google Chrome", "7-Zip", ...] }
- Handle missing applications gracefully (app in profile but not in current installer version)
- Add error handling for file I/O operations
- Follow .augment/ guidelines for PowerShell scripts (ASCII-only indicators, no emoji in code)

Testing:
- Export a selection of 10 apps and verify JSON structure
- Import the profile and verify all apps are selected correctly
- Test with missing apps in profile
- Test with corrupted JSON file
- Verify logging of export/import operations

Documentation:
- Update README.md with export/import feature documentation
- Update CHANGELOG.md with version increment (1.3.8 for GUI, 1.4.1 for CLI)
- Add examples of JSON profile structure
- Document use cases (backup selections, deploy to multiple machines)