@echo off
REM Sets up `adb reverse` so an Android physical device can reach the backend
REM at http://localhost:8080. Run once per `adb` session, before `flutter run`.
REM
REM Usage: scripts\android-reverse.cmd [port]
REM Default port: 8080

setlocal

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"

where adb >nul 2>nul
if errorlevel 1 (
  echo [error] adb not found in PATH. Install Android Platform Tools.
  exit /b 1
)

for /f "tokens=*" %%i in ('adb devices ^| findstr /R "device$"') do (
  for /f "tokens=1" %%d in ("%%i") do (
    echo [adb] reverse tcp:%PORT% tcp:%PORT%  on device %%d
    adb -s %%d reverse tcp:%PORT% tcp:%PORT%
  )
)

echo.
echo Done. Backend on host must be listening on :%PORT% (all interfaces).
echo Backend should bind to ":PORT", not "127.0.0.1:PORT".
endlocal
