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

if not exist "%~dp0app-installer.ps1" (
    echo [ERROR] App Installer script was not found: "%~dp0app-installer.ps1"
    exit /b 2
)

REM Check if PowerShell 7+ is installed (PATH first, then common locations)
call :FIND_PWSH
if defined PWSH_EXE (
    echo [OK] PowerShell 7+ found: %PWSH_EXE%
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
    if not exist "%~dp0invoke-elevated-install.ps1" (
        echo [ERROR] The elevation helper was not found: "%~dp0invoke-elevated-install.ps1"
        exit /b 2
    )
    if not defined TEMP (
        echo [ERROR] A temporary directory is unavailable for elevation diagnostics.
        exit /b 2
    )
    set "ELEVATION_ERROR_FILE=%TEMP%\app-installer-elevation-%RANDOM%.err"
    type nul > "!ELEVATION_ERROR_FILE!" 2>nul
    if errorlevel 1 (
        echo [ERROR] Could not prepare temporary elevation diagnostics.
        exit /b 2
    )
    powershell -NoProfile -File "%~dp0invoke-elevated-install.ps1" "%~f0" %* 2>"!ELEVATION_ERROR_FILE!"
    set "ELEVATION_RC=!ERRORLEVEL!"

    if exist "!ELEVATION_ERROR_FILE!" (
        findstr /I /C:"execution policy" /C:"running scripts is disabled" /C:"not digitally signed" "!ELEVATION_ERROR_FILE!" >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            type "!ELEVATION_ERROR_FILE!"
            echo PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.
            echo Signature guidance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5
            del "!ELEVATION_ERROR_FILE!" >nul 2>&1
            exit /b 1
        )
        type "!ELEVATION_ERROR_FILE!"
        del "!ELEVATION_ERROR_FILE!" >nul 2>&1
    )

    if "!ELEVATION_RC!"=="9009" (
        echo [ERROR] Windows PowerShell could not be started. The elevated installer result is unknown.
    )
    if not "!ELEVATION_RC!"=="0" (
        echo [ERROR] The elevated App Installer did not complete successfully; exit code !ELEVATION_RC!.
    )
    exit /b !ELEVATION_RC!
)

winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
set WINGET_RC=%ERRORLEVEL%

REM Re-check for pwsh after winget attempt (handles "already installed" case)
call :FIND_PWSH
if defined PWSH_EXE (
    echo.
    echo [OK] PowerShell 7 is available: %PWSH_EXE%
    echo.
    goto :RUN_INSTALLER
)

if %WINGET_RC% NEQ 0 (
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
if not defined TEMP (
    echo [ERROR] A temporary directory is unavailable for launch diagnostics.
    exit /b 2
)
set "POLICY_ERROR_FILE=%TEMP%\app-installer-launch-%RANDOM%.err"
type nul > "%POLICY_ERROR_FILE%" 2>nul
if errorlevel 1 (
    echo [ERROR] Could not prepare temporary launch diagnostics.
    exit /b 2
)

"%PWSH_EXE%" -NoProfile -File "%~dp0app-installer.ps1" %* 2>"%POLICY_ERROR_FILE%"
set "INSTALLER_RC=!ERRORLEVEL!"

if exist "%POLICY_ERROR_FILE%" (
    findstr /I /C:"execution policy" /C:"running scripts is disabled" /C:"not digitally signed" "%POLICY_ERROR_FILE%" >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        type "%POLICY_ERROR_FILE%"
        echo PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.
        echo Signature guidance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5
        del "%POLICY_ERROR_FILE%" >nul 2>&1
        exit /b 1
    )
    type "%POLICY_ERROR_FILE%"
    del "%POLICY_ERROR_FILE%" >nul 2>&1
)

if not "!INSTALLER_RC!"=="0" (
    echo.
    echo [ERROR] Installer exited with code: !INSTALLER_RC!
    exit /b !INSTALLER_RC!
)

echo.
echo [INFO] Setup complete.
pause
exit /b !INSTALLER_RC!

REM ---- Subroutine: locate pwsh.exe via PATH or common install dirs ----
:FIND_PWSH
set "PWSH_EXE="
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PWSH_EXE=pwsh"
    goto :EOF
)
REM Check common install locations
for %%D in (
    "%ProgramFiles%\PowerShell\7\pwsh.exe"
    "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    "%LocalAppData%\Microsoft\PowerShell\pwsh.exe"
    "%ProgramW6432%\PowerShell\7\pwsh.exe"
) do (
    if exist %%D (
        set "PWSH_EXE=%%~D"
        goto :EOF
    )
)
goto :EOF
