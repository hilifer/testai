@echo off
REM ============================================================
REM Claw Code: 在 Windows 上启动 Chrome 调试模式
REM 供 WSL 中的 claw-code 使用
REM 双击运行此文件，或在 CMD 中运行
REM ============================================================

set CDP_PORT=18892
set PROFILE_DIR=%USERPROFILE%\.claw\chrome-profile

REM 查找 Chrome
set CHROME_DIR=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe
if exist "%CHROME_DIR%" goto found
set CHROME_DIR=C:\Program Files\Google\Chrome\Application\chrome.exe
if exist "%CHROME_DIR%" goto found
set CHROME_DIR=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe
if exist "%CHROME_DIR%" goto found

echo [ERROR] Chrome not found!
echo Please install Google Chrome: https://www.google.com/chrome/
pause
exit /b 1

:found
echo ============================================================
echo  Claw Code: Chrome Debug Mode
echo  CDP Port: %CDP_PORT%
echo  Profile:  %PROFILE_DIR%
echo ============================================================
echo.
echo Chrome is starting in debug mode.
echo.
echo After logging in to AI websites, go to WSL and run:
echo   ./scripts/web-login-wsl.sh deepseek
echo.
echo Keep this window open!
echo ============================================================

"%CHROME_DIR%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%PROFILE_DIR%" --no-first-run --no-default-browser-check
