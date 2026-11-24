@echo off
setlocal enabledelayedexpansion
echo ========================================================
echo   Building Cashon for Windows (Release Mode)
echo ========================================================
cd /d "%~dp0..\budget"

echo.
echo [1/3] Running Flutter Windows Release Build...
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Flutter Windows build failed with exit code %ERRORLEVEL%.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/3] Checking for Inno Setup Compiler (ISCC)...
set "ISCC_PATH="
where iscc >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "ISCC_PATH=iscc"
) else if exist "C:\Program Files\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "%LOCALAPPDATA%\Programs\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=%LOCALAPPDATA%\Programs\Inno Setup 7\ISCC.exe"
) else if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
)

if defined ISCC_PATH (
    echo Compiling Installer with Inno Setup...
    "%ISCC_PATH%" "windows\installer\inno_setup.iss"
    if !ERRORLEVEL! EQU 0 (
        echo.
        echo [SUCCESS] Windows Setup Installer created!
        echo Opening installer directory...
        start "" "build\windows\installer"
    ) else (
        echo [WARNING] Inno Setup compilation had issues. Opening runner release folder...
        start "" "build\windows\x64\runner\Release"
    )
) else (
    echo Inno Setup not detected on PATH.
    echo Portable release executable is ready in:
    echo   build\windows\x64\runner\Release\budget.exe
    echo.
    echo (To generate a single setup.exe, install Inno Setup 6 from https://jrsoftware.org/isdl.php)
    echo Opening release folder...
    start "" "build\windows\x64\runner\Release"
)

echo.
echo ========================================================
echo   Build Finished!
echo ========================================================
pause
