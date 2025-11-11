Add installation queue management to 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' and 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install.ps1' for better control over large batch installations.

Requirements:
- Show installation queue before starting
- Allow reordering of queue (move up/down, prioritize)
- Add pause/resume functionality during installation
- Add skip functionality to skip current app and continue
- Show estimated time remaining for entire queue
- Save queue state if interrupted (resume on next run)
- GUI: Add queue management dialog with drag-drop reordering
- CLI: Add queue display with reorder options

Implementation Details:
- Create $script:InstallationQueue array to track pending installations
- Create Show-InstallationQueue function to display queue
- Implement Reorder-Queue function for priority changes
- Add pause/resume state management
- Calculate ETA based on average installation time
- Save queue state to JSON file: C:\mytech.today\app_installer\queue-state.json
- Restore queue on script startup if interrupted
- Follow .augment/ guidelines for PowerShell scripts

Testing:
- Queue 20 applications for installation
- Reorder queue and verify changes
- Pause installation and verify state is saved
- Resume installation and verify it continues correctly
- Test skip functionality
- Verify ETA calculation accuracy

Documentation:
- Update README.md with queue management documentation
- Update CHANGELOG.md with version increment
- Document queue state file format
- Add examples of queue management workflows