Integrate the generic logging module from 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1' into 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' and 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install.ps1'.

Requirements:
- Replace existing logging functions with generic logging module
- Import logging.ps1 from GitHub URL at script startup
- Use Initialize-Log function to set up logging
- Replace all Write-Log calls with generic module functions
- Maintain existing log format and location (C:\mytech.today\logs\)
- Preserve monthly log rotation (scriptname-yyyy-MM.md format)
- Ensure all log levels are properly mapped (INFO, SUCCESS, WARNING, ERROR, CRITICAL)
- Test both local and GitHub import methods

Implementation Details:
- Add at top of script: $loggingUrl = 'https://raw.githubusercontent.com/mytech-today-now/PowerShellScripts/main/scripts/logging.ps1'
- Add: Invoke-Expression (Invoke-WebRequest -Uri $loggingUrl -UseBasicParsing).Content
- Replace Initialize-Logging with Initialize-Log -ScriptName "AppInstaller-GUI" -ScriptVersion $script:ScriptVersion
- Replace all Write-Log calls with generic module equivalents
- Remove old logging functions (Initialize-Logging, Write-Log)
- Test fallback to local logging if GitHub import fails
- Follow .augment/ guidelines for PowerShell scripts

Testing:
- Run installer and verify logging works with generic module
- Check log file format matches expected markdown format
- Test with internet disconnected (should fall back gracefully)
- Verify all log levels are working correctly
- Compare log output before and after integration

Documentation:
- Update README.md to document logging module integration
- Update CHANGELOG.md with version increment (1.3.8 for GUI, 1.4.1 for CLI)
- Document logging module URL and import process
- Add troubleshooting for logging module import failures