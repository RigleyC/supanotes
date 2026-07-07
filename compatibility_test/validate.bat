@echo off
echo =======================================
echo Running Yjs Compatibility Test Suite
echo =======================================

echo.
echo [1/4] Running Dart Generator...
cd dart_runner
call dart run bin/runner.dart --mode=generate
if %errorlevel% neq 0 (
    echo ❌ Dart Generator failed!
    exit /b %errorlevel%
)

echo.
echo [2/4] Running Go Verification...
cd ../go_runner
call go run main.go --mode=verify
if %errorlevel% neq 0 (
    echo ❌ Go Verification failed!
    exit /b %errorlevel%
)

echo.
echo [3/4] Running Go Generator...
call go run main.go --mode=generate
if %errorlevel% neq 0 (
    echo ❌ Go Generator failed!
    exit /b %errorlevel%
)

echo.
echo [4/4] Running Dart Verification...
cd ../dart_runner
call dart run bin/runner.dart --mode=verify
if %errorlevel% neq 0 (
    echo ❌ Dart Verification failed!
    exit /b %errorlevel%
)

echo.
echo =======================================
echo ✅ Yjs Compatibility Cross-Verification Passed!
echo =======================================
cd ..
