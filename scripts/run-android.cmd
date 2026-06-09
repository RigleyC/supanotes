@echo off
REM Run the Flutter app on a connected Android device, automatically setting
REM up `adb reverse` so the device can reach the host backend at :8080.
REM
REM Usage: scripts\run-android.cmd [port]
REM Default port: 8080
REM
REM Requirements:
REM   - adb in PATH (Android Platform Tools)
REM   - USB debugging enabled on device
REM   - Backend listening on host :PORT (all interfaces, not 127.0.0.1)

setlocal

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"

where adb >nul 2>nul
if errorlevel 1 (
  echo [error] adb not found in PATH. Install Android Platform Tools.
  exit /b 1
)

REM Check that at least one device is connected.
adb devices | findstr /R "device$" >nul
if errorlevel 1 (
  echo [error] No adb devices connected. Plug in your phone and enable USB debugging.
  adb devices
  exit /b 1
)

REM Probe the backend on the host before doing anything else.
curl -s -o nul -w "" http://127.0.0.1:%PORT%/healthz 2>nul
if errorlevel 1 (
  echo [error] Backend not reachable on 127.0.0.1:%PORT%. Start it first.
  exit /b 1
)
echo [ok] Backend reachable on 127.0.0.1:%PORT%

REM Set up reverse tunnel for every connected device.
for /f "tokens=*" %%i in ('adb devices ^| findstr /R "device$"') do (
  for /f "tokens=1" %%d in ("%%i") do (
    echo [adb] reverse tcp:%PORT% tcp:%PORT%  on device %%d
    adb -s %%d reverse tcp:%PORT% tcp:%PORT% >nul
    if errorlevel 1 (
      echo [error] adb reverse failed on device %%d.
      exit /b 1
    )
  )
)

echo [ok] Reverse tunnel established. Launching app...
echo.

flutter run -d android
endlocal
