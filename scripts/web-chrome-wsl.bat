@echo off
chcp 65001 >nul 2>&1
REM ============================================================
REM Claw Code: Launch Chrome in debug mode for WSL
REM Double-click this file or run it in CMD
REM ============================================================

set CDP_PORT=18892
set PROFILE_DIR=%USERPROFILE%\.claw\chrome-profile

REM --- Find Chrome ---
set CHROME_PATH=
for %%P in (
    "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
    "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
) do (
    if exist %%P (
        set CHROME_PATH=%%P
        goto found
    )
)

echo [ERROR] Chrome not found!
echo Please install Google Chrome: https://www.google.com/chrome/
pause
exit /b 1

:found
echo ============================================================
echo  Claw Code: Chrome Debug Mode
echo  Chrome:   %CHROME_PATH%
echo  CDP Port: %CDP_PORT%
echo  Profile:  %PROFILE_DIR%
echo ============================================================
echo.
echo  1. Log in to your AI website (e.g. chat.deepseek.com)
echo  2. Then in WSL run: ./scripts/web-login-wsl.sh deepseek
echo  3. Keep this window open!
echo.
echo ============================================================

%CHROME_PATH% --remote-debugging-port=%CDP_PORT% --user-data-dir="%PROFILE_DIR%" --no-first-run --no-default-browser-check

pause
