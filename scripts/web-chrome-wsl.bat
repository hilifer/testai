@echo off
chcp 65001 >nul 2>&1

echo ============================================================
echo  Claw Code: Chrome Debug Mode for WSL
echo ============================================================
echo.

set CDP_PORT=18892
set PROFILE_DIR=%USERPROFILE%\.claw\chrome-profile

REM --- Find Chrome ---
set CHROME_PATH=
if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" (
    set "CHROME_PATH=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
    goto chrome_found
)
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" (
    set "CHROME_PATH=C:\Program Files\Google\Chrome\Application\chrome.exe"
    goto chrome_found
)
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" (
    set "CHROME_PATH=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    goto chrome_found
)

echo [ERROR] Chrome not found!
echo Install Chrome: https://www.google.com/chrome/
pause
exit /b 1

:chrome_found
echo [OK] Chrome: %CHROME_PATH%
echo.

REM --- Kill existing Chrome (must restart with debug flags) ---
echo [1/4] Closing existing Chrome...
taskkill /F /IM chrome.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM --- Setup port forwarding (so WSL can reach localhost:18892) ---
echo [2/4] Setting up port forwarding (0.0.0.0:%CDP_PORT% -^> 127.0.0.1:%CDP_PORT%)...
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=%CDP_PORT% >nul 2>&1
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=%CDP_PORT% connectaddress=127.0.0.1 connectport=%CDP_PORT% >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Port forwarding failed. Run this .bat as Administrator!
) else (
    echo [OK] Port forwarding ready
)

REM --- Add firewall rule ---
echo [3/4] Adding firewall rule for port %CDP_PORT%...
netsh advfirewall firewall delete rule name="Claw Chrome CDP" >nul 2>&1
netsh advfirewall firewall add rule name="Claw Chrome CDP" dir=in action=allow protocol=TCP localport=%CDP_PORT% >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Firewall rule failed. Run this .bat as Administrator!
) else (
    echo [OK] Firewall rule added
)

REM --- Launch Chrome with debug port ---
echo [4/4] Starting Chrome with CDP on port %CDP_PORT%...
echo.
start "" "%CHROME_PATH%" --remote-debugging-port=%CDP_PORT% --remote-debugging-address=0.0.0.0 --user-data-dir="%PROFILE_DIR%" --no-first-run --no-default-browser-check

REM --- Wait and verify ---
timeout /t 3 /nobreak >nul
curl -sf http://localhost:%CDP_PORT%/json/version >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Chrome CDP not responding yet, waiting...
    timeout /t 3 /nobreak >nul
)

curl -sf http://localhost:%CDP_PORT%/json/version >nul 2>&1
if %errorlevel% equ 0 (
    echo.
    echo ============================================================
    echo  ALL READY!
    echo.
    echo  Chrome CDP:       http://localhost:%CDP_PORT%
    echo  Port forwarding:  0.0.0.0:%CDP_PORT% -^> 127.0.0.1:%CDP_PORT%
    echo  Firewall:         port %CDP_PORT% allowed
    echo.
    echo  Now in WSL run:
    echo    ./scripts/web-login-wsl.sh deepseek
    echo ============================================================
) else (
    echo.
    echo [WARN] Chrome started but CDP not verified.
    echo        Log in to chat.deepseek.com then try WSL:
    echo          ./scripts/web-login-wsl.sh deepseek
)

echo.
echo Press any key to exit (Chrome will keep running)...
pause >nul
