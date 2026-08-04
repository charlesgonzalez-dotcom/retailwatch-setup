@echo off
echo.
echo ================================================
echo   RetailWatch - PC Setup
echo ================================================
echo.
echo Downloading latest setup script from GitHub...

set USB=%~dp0

powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/charlesgonzalez-dotcom/retailwatch-setup/main/scripts/1-setup-backoffice.ps1' -OutFile '%TEMP%\rw-setup.ps1'"

if not exist "%TEMP%\rw-setup.ps1" (
    echo ERROR: Could not download setup script. Check internet connection.
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%TEMP%\rw-setup.ps1" -USB "%USB%"
pause
