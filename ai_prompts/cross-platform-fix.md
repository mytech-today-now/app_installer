You are an expert PowerShell developer specializing in cross-platform scripting using PowerShell 7+ (which runs identically on Windows, macOS, and Linux). The repository is a PowerShell-based application installer with a GUI component (install-gui.ps1) that currently relies on Windows Forms (System.Windows.Forms), making it Windows-only despite the core logic being cross-platform compatible.

Your task is to refactor the entire repository to create the best possible, most user-friendly, and maintainable cross-platform application installer product. Prioritize ease of use, robustness, clear code structure, and future extensibility.

Key goals:
- Make the installer fully functional on Windows, macOS, and Linux without requiring platform-specific code branches where possible.
- The GUI must work on all three platforms. Do **not** use System.Windows.Forms or any Windows-specific GUI framework, as it will fail on macOS and Linux.
- Prefer modern, lightweight, cross-platform GUI solutions that integrate well with PowerShell. Options to consider (in order of preference based on ease and native feel):
  1. Terminal.Gui (gui.cs) – highly recommended for console-based GUIs that run identically in terminals on all platforms, support mouse/keyboard, tables, dialogs, menus, etc.
  2. Avalonia UI via a small .NET wrapper if a desktop windowed GUI is strongly desired (but avoid if console GUI suffices).
  3. Fallback to rich console output with interactive prompts using $Host.UI if a full GUI is not feasible.
- The current error in install-gui.ps1 is caused by incorrectly calling $ListView.Columns.AddRange() with a plain array (likely of strings) instead of a properly typed [System.Windows.Forms.ColumnHeader[]] array. This must be fixed in any Windows-specific legacy branch, but the primary refactor should eliminate Windows Forms entirely.
- Preserve all existing functionality: directory creation, file copying, app script/profile management, logging, responsive layout, and the main installer GUI with lists, buttons, search, etc.
- Make the code modular: separate core installation logic, logging, data handling, and GUI into distinct functions/modules.
- Use best practices:
  - Strict mode (`Set-StrictMode -Version Latest`).
  - Error handling with try/catch and meaningful messages.
  - Parameter validation.
  - Comment extensively but concisely.
  - Use PowerShell 7+ features (e.g., ternary operators, null-coalescing).
  - Support both GUI and CLI modes (detect if GUI is requested/available).
- Installation paths must adapt per platform:
  - Windows: Respect user profile (e.g., "$env:USERPROFILE\myTech.Today\AppInstaller").
  - macOS: "$HOME/Library/Application Support/myTech.Today/AppInstaller" or similar standard location.
  - Linux: "$HOME/.local/share/myTech.Today/AppInstaller" or respect XDG Base Directory spec.
  - Logs: Platform-appropriate locations (e.g., "$HOME/.myTech.Today/logs" on non-Windows).
- Detect platform using $IsWindows, $IsMacOS, $IsLinux and adjust behavior accordingly.
- Ensure the installer script itself can run directly via pwsh on all platforms.
- If copying files/apps/profiles, use cross-platform cmdlets (Copy-Item works everywhere).
- Test thoroughly in your mind for edge cases: permissions, existing installs, partial copies, high-DPI on macOS/Windows.
- Output clean, refactored code with clear separation (e.g., one file for core, one for GUI using Terminal.Gui).

Analyze the provided error log thoroughly:
- The script successfully detects Windows, loads .NET 4.8, copies files, initializes logging.
- It fails specifically in Create-MainForm (line ~3506) when adding column headers to a ListView via AddRange, passing a System.Object[] instead of ColumnHeader objects.

Fix this root cause in the refactor by replacing the entire Windows Forms GUI with a cross-platform alternative.

Produce high-quality, production-ready code that feels polished and intuitive to end users on any OS. Provide the complete refactored scripts (install-gui.ps1, install.ps1 if needed, any new modules) with explanations where complex.