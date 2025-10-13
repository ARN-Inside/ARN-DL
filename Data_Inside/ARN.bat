@echo off
:: This script handles the elevation and runs the main PowerShell script.

:: 1. Check for Administrator privileges.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

:: 2. If not admin, relaunch this script as admin and exit.
if '%errorlevel%' NEQ '0' (
    powershell.exe -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul
    exit /b
)

:: 3. If we are here, we have admin privileges. Run the PowerShell script in this black window.
:: The .ps1 script is in the same folder as this launcher.
start "ARN-DL | AlgoRythmic.Network" /max powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0ARN-DL.ps1"
