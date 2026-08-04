@echo off
echo.
echo ================================================
echo   RetailWatch - PC Setup
echo ================================================
echo.
echo Downloading setup script...
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/charlesgonzalez-dotcom/retailwatch-setup/main/scripts/1-setup-backoffice.ps1' -OutFile 'C:\Users\Public\rw-setup.ps1' -UseBasicParsing"
powershell -ExecutionPolicy Bypass -File "C:\Users\Public\rw-setup.ps1"
pause
