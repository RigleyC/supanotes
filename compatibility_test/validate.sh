#!/bin/bash
set -e

echo "======================================="
echo "Running Yjs Compatibility Test Suite"
echo "======================================="

echo ""
echo "[1/5] Running Dart Generator..."
cd dart_runner
dart run bin/runner.dart --mode=generate

echo ""
echo "[2/5] Running Go Verification..."
cd ../go_runner
go run main.go --mode=verify

echo ""
echo "[3/5] Running Go Generator..."
go run main.go --mode=generate

echo ""
echo "[4/5] Running Dart Verification..."
cd ../dart_runner
dart run bin/runner.dart --mode=verify

echo ""
echo "[5/5] Running 10,000 Iterations Fuzzing Stress-Test..."
dart run bin/fuzzer.dart

echo ""
echo "======================================="
echo "✅ Yjs Compatibility Cross-Verification Passed!"
echo "======================================="
cd ..
