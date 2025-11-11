Integrate the responsive GUI helper from 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\responsive.ps1' into 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' to improve DPI scaling and multi-monitor support.

Requirements:
- Import responsive.ps1 from GitHub URL at script startup
- Replace manual DPI scaling calculations with responsive helper functions
- Use New-ResponsiveForm instead of manual form creation
- Use New-ResponsiveButton, New-ResponsiveLabel, etc. for all controls
- Improve multi-monitor support and DPI awareness
- Test on various screen resolutions and DPI settings
- Maintain existing form layout and functionality

Implementation Details:
- Add at top of script: $responsiveUrl = 'https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/responsive.ps1'
- Add: Invoke-Expression (Invoke-WebRequest -Uri $responsiveUrl -UseBasicParsing).Content
- Replace form creation with: $form = New-ResponsiveForm -Title "myTech.Today App Installer" -Width 1200 -Height 800
- Replace all control creation with responsive equivalents
- Remove manual DPI scaling code
- Test on 100%, 125%, 150%, 200% DPI settings
- Follow .augment/patterns.md responsive GUI guidelines

Testing:
- Test on 1920x1080 at 100% DPI
- Test on 1920x1080 at 150% DPI
- Test on 4K monitor at 200% DPI
- Test on multi-monitor setup with different DPI settings
- Verify all controls scale correctly

Documentation:
- Update README.md with responsive GUI documentation
- Update CHANGELOG.md with version increment (1.3.8)
- Document responsive helper URL and import process
- Add screenshots at different DPI settings