@echo off
REM ============================================================================
REM  myTech.Today - App Installer Setup
REM  Checks for PowerShell 7+, installs if needed, then runs the installer
REM ============================================================================
setlocal enabledelayedexpansion 

echo.
echo ============================================================
echo   myTech.Today - App Installer Setup
echo ============================================================
echo.

REM Check if PowerShell 7+ is installed
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] PowerShell 7+ is installed
    goto :RUN_INSTALLER
)

echo [INFO] PowerShell 7+ not found. Checking for winget...

REM Check if winget is available
where winget >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] winget is not available on this system.
    echo.
    echo Please install PowerShell 7 manually:
    echo   1. Visit: https://github.com/PowerShell/PowerShell/releases
    echo   2. Download the latest .msi installer for Windows
    echo   3. Run the installer and follow the prompts
    echo   4. Re-run this script after installation
    echo.
    pause
    exit /b 1
)

echo [INFO] Installing PowerShell 7 using winget...
echo        This may require administrator privileges.
echo.

REM Check for admin privileges
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARN] Not running as administrator. Requesting elevation...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to install PowerShell 7.
    echo         Please install manually from: https://github.com/PowerShell/PowerShell/releases
    pause
    exit /b 1
)

echo.
echo [OK] PowerShell 7 installed successfully!
echo.

:RUN_INSTALLER
echo [INFO] Running App Installer...
echo.

REM Run the PowerShell installer script
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [WARN] Installer exited with code: %ERRORLEVEL%
)

echo.
echo [INFO] Setup complete.
pause

