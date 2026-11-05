@echo off
setlocal EnableExtensions
chcp 65001 >nul
pushd "%~dp0"

echo ============================================
echo  Metrolist Kilo - remaining Stage 2 tests
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

if not exist ".\kilo_remaining_tests.ps1" (
    echo Downloading kilo_remaining_tests.ps1 ...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/wahaha232/Metrolist/stage2-bluetooth/scripts/kilo_remaining_tests.ps1' -OutFile '.\kilo_remaining_tests.ps1'"
    if errorlevel 1 (
        echo.
        echo Download failed. Download it manually and place it next to this BAT:
        echo https://raw.githubusercontent.com/wahaha232/Metrolist/stage2-bluetooth/scripts/kilo_remaining_tests.ps1
        popd
        pause
        exit /b 1
    )
)

echo Running tests...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\kilo_remaining_tests.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
echo Exit code: %RC%
popd
pause
exit /b %RC%

:help
echo Usage:
echo   run_kilo_tests.bat [options]
echo.
echo All options are passed to kilo_remaining_tests.ps1:
echo   -Adb "C:\path\to\adb.exe"      Use a specific adb binary
echo   -ReleaseApk "C:\path\app.apk"  Install this release APK for the release check
echo   -SkipIdle                      Skip the home idle regression
echo   -SkipRelease                   Skip the release APK check
echo   -Reboot                        Also test persistence after a phone reboot
echo.
echo Requirements:
echo   - adb in PATH (or use -Adb)
echo   - phone connected and USB/wireless debugging authorized
echo   - app language Traditional Chinese (for UI text matching)
echo.
echo Results are written to test-results\remaining-tests-*.txt
popd
pause
exit /b 0
