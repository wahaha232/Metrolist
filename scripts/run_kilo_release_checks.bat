@echo off
setlocal EnableExtensions
chcp 65001 >nul
pushd "%~dp0"

echo ============================================
echo  Metrolist Kilo - release acceptance checks
echo ============================================
echo.

where powershell >nul 2>nul
if errorlevel 1 (
    echo PowerShell was not found.
    popd
    pause
    exit /b 1
)

if /I "%~1"=="-h" goto :help
if /I "%~1"=="--help" goto :help

if not exist ".\kilo_release_checks.ps1" (
    echo Downloading kilo_release_checks.ps1 ...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/wahaha232/Metrolist/stage2-bluetooth/scripts/kilo_release_checks.ps1' -OutFile '.\kilo_release_checks.ps1'"
    if errorlevel 1 (
        echo.
        echo Download failed. Download it manually and place it next to this BAT:
        echo https://raw.githubusercontent.com/wahaha232/Metrolist/stage2-bluetooth/scripts/kilo_release_checks.ps1
        popd
        pause
        exit /b 1
    )
)

echo Running release checks...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\kilo_release_checks.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
echo Exit code: %RC%
popd
pause
exit /b %RC%

:help
echo Usage:
echo   run_kilo_release_checks.bat [options]
echo.
echo All options are passed to kilo_release_checks.ps1:
echo   -Apk "C:\path\app.apk"        Release APK to check/install
echo   -SkipInstall                  Do not install the APK
echo   -SkipIdle                     Skip the home idle regression
echo   -SkipManual                   Skip the Bluetooth headset checklist
echo   -SkipReleaseGates             Skip signing/version checks
echo   -AllowDebugSignature          Accept a debug-signed APK (internal builds)
echo   -Reboot                       Test persistence after a phone reboot
echo   -Adb "C:\path\to\adb.exe"     Use a specific adb binary
echo.
echo Results are written to test-results\release-checks-*.txt
popd
pause
exit /b 0
