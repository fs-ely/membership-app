@echo off
setlocal EnableExtensions
rem ============================================================================
rem  setup.bat - launcher for Windows Command Prompt.
rem
rem  Command Prompt cannot execute setup.sh (it has no bash interpreter) and
rem  cannot execute setup.ps1 either (that is PowerShell's job). So this thin
rem  batch file only picks an engine and hands the arguments over verbatim.
rem  It contains no application logic of its own - all real work lives in
rem  setup.ps1 (preferred) or setup.sh (Git Bash fallback).
rem
rem  Usage:  setup.bat [options]      e.g.  setup.bat --seed --db-password=x
rem          setup.bat --help
rem
rem  NOTE: this file must be saved with CRLF line endings. An LF-only .bat
rem  misbehaves around goto/labels and multi-line if blocks.
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%setup.ps1"
set "SH=%SCRIPT_DIR%setup.sh"

if not exist "%PS1%" goto :no_ps1

rem --- Engine 1: PowerShell 7+ ------------------------------------------------
where pwsh >nul 2>&1
if not errorlevel 1 goto :use_pwsh

rem --- Engine 2: Windows PowerShell 5.1 (ships with Windows) -----------------
where powershell >nul 2>&1
if not errorlevel 1 goto :use_ps

rem --- Engine 3: Git Bash -----------------------------------------------------
rem `where bash` alone is not enough: Git for Windows installs into
rem Program Files\Git, which is normally NOT on the system PATH, so probe the
rem well-known install locations as well.
set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH_EXE for /f "delims=" %%B in ('where bash 2^>nul') do if not defined BASH_EXE set "BASH_EXE=%%B"
if not defined BASH_EXE goto :no_engine
if not exist "%SH%" goto :no_sh
goto :use_bash

:use_pwsh
echo Using PowerShell 7 ^(pwsh^) - running setup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
goto :finish

:use_ps
echo Using Windows PowerShell 5.1 - running setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
goto :finish

:use_bash
echo Using Git Bash - running setup.sh
echo   Note: Git Bash translates paths, so setup.ps1 is preferred when available.
"%BASH_EXE%" "%SH%" %*
goto :finish

:no_ps1
echo [!!] setup.ps1 was not found next to setup.bat.
echo      Expected: "%PS1%"
echo      Keep setup.bat, setup.ps1 and setup.sh in the same folder.
endlocal
exit /b 1

:no_sh
echo [!!] Found Git Bash, but setup.sh is missing.
echo      Expected: "%SH%"
endlocal
exit /b 1

:no_engine
echo [!!] No PowerShell and no Git Bash were found.
echo.
echo   Options:
echo     1. Open "Git Bash" from the Start menu, then run:  ./setup.sh
echo     2. In PowerShell, run:                             .\setup.ps1
echo     3. In WSL, run:                                    wsl bash setup.sh
echo.
echo   PowerShell ships with Windows, so option 2 should always work.
endlocal
exit /b 1

:finish
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
