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

REM --- Kill existing Chrome ---
echo [1/4] Closing existing Chrome...
taskkill /F /IM chrome.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM --- Firewall ---
echo [2/4] Adding firewall rule for port %CDP_PORT%...
netsh advfirewall firewall delete rule name="Claw Chrome CDP" >nul 2>&1
netsh advfirewall firewall add rule name="Claw Chrome CDP" dir=in action=allow protocol=TCP localport=%CDP_PORT% >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Firewall rule failed. Run as Administrator!
) else (
    echo [OK] Firewall rule added
)

REM --- Launch Chrome ---
echo [3/4] Starting Chrome with CDP on port %CDP_PORT%...
start "" "%CHROME_PATH%" --remote-debugging-port=%CDP_PORT% --remote-debugging-address=0.0.0.0 --user-data-dir="%PROFILE_DIR%" --no-first-run --no-default-browser-check

REM --- Wait for Chrome to start ---
timeout /t 3 /nobreak >nul

REM --- Verify Chrome CDP locally ---
echo [4/4] Verifying Chrome CDP...
curl -sf http://localhost:%CDP_PORT%/json/version >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Chrome not ready, waiting 3 more seconds...
    timeout /t 3 /nobreak >nul
)
curl -sf http://localhost:%CDP_PORT%/json/version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Chrome CDP not responding on localhost:%CDP_PORT%
    echo         Close all Chrome and re-run this script as Administrator.
    pause
    exit /b 1
)
echo [OK] Chrome CDP verified on localhost:%CDP_PORT%
echo.

REM --- Start TCP relay for WSL ---
echo Starting TCP relay on 0.0.0.0:%CDP_PORT% for WSL access...
echo (This window must stay open!)
echo.
echo ============================================================
echo  ALL READY!
echo.
echo  Chrome CDP:  http://localhost:%CDP_PORT%
echo  WSL relay:   0.0.0.0:%CDP_PORT% (this window)
echo.
echo  Now in WSL run:
echo    ./scripts/web-login-wsl.sh deepseek
echo.
echo  DO NOT CLOSE THIS WINDOW (relay will stop)
echo ============================================================
echo.

REM --- PowerShell TCP relay: listens on 0.0.0.0:CDP_PORT, forwards to 127.0.0.1:CDP_PORT ---
REM This replaces netsh portproxy which doesn't work well with CDP/WebSocket
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$port = %CDP_PORT%; " ^
  "$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port); " ^
  "try { $listener.Start() } catch { " ^
  "  Write-Host '[WARN] Port already in use, trying relay on port 18893...'; " ^
  "  $port = 18893; " ^
  "  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port); " ^
  "  $listener.Start() " ^
  "}; " ^
  "Write-Host \"[OK] TCP relay listening on 0.0.0.0:$port\"; " ^
  "while ($true) { " ^
  "  $client = $listener.AcceptTcpClient(); " ^
  "  $target = [System.Net.Sockets.TcpClient]::new('127.0.0.1', %CDP_PORT%); " ^
  "  $clientStream = $client.GetStream(); " ^
  "  $targetStream = $target.GetStream(); " ^
  "  $job1 = [System.Threading.Tasks.Task]::Run([Action]{ " ^
  "    try { $clientStream.CopyTo($targetStream) } catch {} " ^
  "  }); " ^
  "  $job2 = [System.Threading.Tasks.Task]::Run([Action]{ " ^
  "    try { $targetStream.CopyTo($clientStream) } catch {} " ^
  "  }); " ^
  "  [System.Threading.Tasks.Task]::WaitAny(@($job1, $job2)) | Out-Null; " ^
  "  $client.Close(); $target.Close() " ^
  "}"
