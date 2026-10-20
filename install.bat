@echo off
REM ============================================================================
REM  myTech.Today - App Installer Setup
REM  Starts the shared PowerShell runtime discovery entry point.
REM ============================================================================
setlocal DisableDelayedExpansion

echo.
echo ============================================================
echo   myTech.Today - App Installer Setup
echo ============================================================
echo.

if not exist "%~dp0app-installer.ps1" (
    echo [ERROR] App Installer script was not found: "%~dp0app-installer.ps1"
    exit /b 2
)
if not exist "%~dp0tools\Start-Installer.ps1" (
    echo [ERROR] Shared runtime launcher was not found: "%~dp0tools\Start-Installer.ps1"
    exit /b 2
)
set "STARTER_PATH=%~dp0tools\Start-Installer.ps1"
set "PWSH_EXE="
if defined ProgramW6432 if exist "%ProgramW6432%\PowerShell\7\pwsh.exe" set "PWSH_EXE=%ProgramW6432%\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if defined ProgramFiles if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" set "PWSH_EXE=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe" set "PWSH_EXE=%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Microsoft\PowerShell\pwsh.exe" set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\PowerShell\pwsh.exe"

set "APP_INSTALLER_WHATIF="
for %%A in (%*) do (
    if /I "%%~A"=="-WhatIf" set "APP_INSTALLER_WHATIF=1"
    if /I "%%~A"=="-WhatIf:$true" set "APP_INSTALLER_WHATIF=1"
)
if defined APP_INSTALLER_WHATIF goto :WHATIF_BOOTSTRAP

if not defined TEMP (
    echo [ERROR] A temporary directory is unavailable for startup diagnostics.
    exit /b 2
)
set "BOOTSTRAP_STATUS_FILE=%TEMP%\app-installer-bootstrap-%RANDOM%-%RANDOM%.status"
set "BOOTSTRAP_ERROR_FILE=%TEMP%\app-installer-bootstrap-%RANDOM%-%RANDOM%.err"
type nul > "%BOOTSTRAP_STATUS_FILE%"
if errorlevel 1 (
    echo [ERROR] Could not prepare temporary startup status.
    exit /b 2
)
type nul > "%BOOTSTRAP_ERROR_FILE%"
if errorlevel 1 (
    echo [ERROR] Could not prepare temporary startup diagnostics.
    del "%BOOTSTRAP_STATUS_FILE%" >nul 2>&1
    exit /b 2
)
set "APP_INSTALLER_BOOTSTRAP_STARTED_FILE=%BOOTSTRAP_STATUS_FILE%"

if not defined PWSH_EXE goto :TRY_WINDOWS_POWERSHELL
"%PWSH_EXE%" -NoProfile -File "%STARTER_PATH%" %* 2>"%BOOTSTRAP_ERROR_FILE%"
set "BOOTSTRAP_RC=%ERRORLEVEL%"
call :CLASSIFY_BOOTSTRAP
if errorlevel 100 goto :TRY_WINDOWS_POWERSHELL
if errorlevel 1 goto :BOOTSTRAP_FAILED
goto :BOOTSTRAP_FINISHED

:TRY_WINDOWS_POWERSHELL
set "WINDOWS_POWERSHELL_EXE="
if defined PROCESSOR_ARCHITEW6432 (
    set "WINDOWS_POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
) else (
    set "WINDOWS_POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)
if not exist "%WINDOWS_POWERSHELL_EXE%" goto :NO_BOOTSTRAP_ENGINE
type nul > "%BOOTSTRAP_STATUS_FILE%"
type nul > "%BOOTSTRAP_ERROR_FILE%"
"%WINDOWS_POWERSHELL_EXE%" -NoProfile -File "%STARTER_PATH%" %* 2>"%BOOTSTRAP_ERROR_FILE%"
set "BOOTSTRAP_RC=%ERRORLEVEL%"
call :CLASSIFY_BOOTSTRAP
if errorlevel 100 goto :NO_BOOTSTRAP_ENGINE
if errorlevel 1 goto :BOOTSTRAP_FAILED
goto :BOOTSTRAP_FINISHED

:CLASSIFY_BOOTSTRAP
findstr /I /C:"STARTED" "%BOOTSTRAP_STATUS_FILE%" >nul 2>&1
if not errorlevel 1 (
    if exist "%BOOTSTRAP_ERROR_FILE%" type "%BOOTSTRAP_ERROR_FILE%" 1>&2
    if exist "%BOOTSTRAP_ERROR_FILE%" (
        findstr /I /C:"execution policy" /C:"running scripts is disabled" /C:"not digitally signed" "%BOOTSTRAP_ERROR_FILE%" >nul 2>&1
        if not errorlevel 1 (
            echo PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator. 1>&2
            echo Signature guidance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5 1>&2
            echo No alternate engine was tried. 1>&2
        )
    )
    exit /b 0
)
if exist "%BOOTSTRAP_ERROR_FILE%" (
    findstr /I /C:"execution policy" /C:"running scripts is disabled" /C:"not digitally signed" "%BOOTSTRAP_ERROR_FILE%" >nul 2>&1
    if not errorlevel 1 (
        type "%BOOTSTRAP_ERROR_FILE%" 1>&2
        echo PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator. 1>&2
        echo Signature guidance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5 1>&2
        echo No alternate engine was tried. 1>&2
        exit /b 1
    )
    type "%BOOTSTRAP_ERROR_FILE%" 1>&2
)
exit /b 100

:BOOTSTRAP_FAILED
echo [ERROR] The App Installer launcher failed before it could select a compatible PowerShell engine.
del "%BOOTSTRAP_STATUS_FILE%" >nul 2>&1
del "%BOOTSTRAP_ERROR_FILE%" >nul 2>&1
exit /b 1

:BOOTSTRAP_FINISHED
del "%BOOTSTRAP_STATUS_FILE%" >nul 2>&1
del "%BOOTSTRAP_ERROR_FILE%" >nul 2>&1
if not "%BOOTSTRAP_RC%"=="0" (
    echo.
    echo [ERROR] Installer exited with code: %BOOTSTRAP_RC%
    exit /b %BOOTSTRAP_RC%
)
echo.
echo [INFO] Setup complete.
pause
exit /b 0

:WHATIF_BOOTSTRAP
if defined PWSH_EXE goto :WHATIF_USE_PWSH
set "WINDOWS_POWERSHELL_EXE="
if defined PROCESSOR_ARCHITEW6432 (
    set "WINDOWS_POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
) else (
    set "WINDOWS_POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)
if not exist "%WINDOWS_POWERSHELL_EXE%" goto :NO_BOOTSTRAP_ENGINE_WHATIF
goto :WHATIF_USE_WINDOWS_POWERSHELL

:WHATIF_USE_PWSH
"%PWSH_EXE%" -NoProfile -File "%STARTER_PATH%" %*
set "BOOTSTRAP_RC=%ERRORLEVEL%"
goto :WHATIF_FINISHED

:WHATIF_USE_WINDOWS_POWERSHELL
"%WINDOWS_POWERSHELL_EXE%" -NoProfile -File "%STARTER_PATH%" %*
set "BOOTSTRAP_RC=%ERRORLEVEL%"

:WHATIF_FINISHED
echo [INFO] WhatIf completed without creating bootstrap status files or applying a runtime plan.
if not "%BOOTSTRAP_RC%"=="0" (
    echo [ERROR] Installer preflight exited with code: %BOOTSTRAP_RC%
    exit /b %BOOTSTRAP_RC%
)
exit /b 0

:NO_BOOTSTRAP_ENGINE
del "%BOOTSTRAP_STATUS_FILE%" >nul 2>&1
del "%BOOTSTRAP_ERROR_FILE%" >nul 2>&1
echo [ERROR] No PowerShell executable could start the runtime discovery launcher.
call :SHOW_RUNTIME_PLAN
exit /b 1

:NO_BOOTSTRAP_ENGINE_WHATIF
echo [ERROR] No PowerShell executable could start the runtime discovery launcher.
call :SHOW_RUNTIME_PLAN
exit /b 1

:SHOW_RUNTIME_PLAN
echo [PLAN] Required prerequisite: PowerShell Core 7.6.7 for Windows x64.
echo [PLAN] Official source: https://github.com/PowerShell/PowerShell/releases/download/v7.6.7/PowerShell-7.6.7-win-x64.zip
echo [PLAN] Expected SHA-256: D2F952EBDBF24386CB8923553AA58E41A846DB35A6155EA04C58142A4B16DBB7
echo [PLAN] The ZIP can be extracted for the current user without administrator privileges. It does not change PATH or the default PowerShell engine.
echo [INFO] No PowerShell engine was available to run the compatibility preflight. No download, install, elevation, or application action was started.
echo Install the pinned runtime from the official source, then retry on a supported Windows 11 x64 client.
exit /b 0
