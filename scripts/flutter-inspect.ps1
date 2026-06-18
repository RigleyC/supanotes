<#
.SYNOPSIS
    Captures Flutter widget tree diagnostics via Dart VM Service Protocol.
.DESCRIPTION
    Starts flutter run --debug, captures the VM service URI, then queries
    the VM service for widget/render tree dumps.
.USAGE
    .\scripts\flutter-inspect.ps1 [-DeviceId ZF523BLZDT]
#>
param(
    [string]$DeviceId = "ZF523BLZDT"
)

$ErrorActionPreference = "Stop"

Write-Host "Starting Flutter app in debug mode on $DeviceId..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C after the app launches to capture diagnostics." -ForegroundColor Yellow
Write-Host ""

# Start flutter run and capture output to find VM service URI
$flutterProcess = Start-Process -FilePath "flutter" `
    -ArgumentList "run", "--debug", "-d", $DeviceId, "--machine" `
    -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\flutter_run.json" `
    -RedirectStandardError "$env:TEMP\flutter_run_err.txt"

# Wait for app to start and parse VM service URI
$vmServiceUri = $null
$timeout = 120
$elapsed = 0

Write-Host "Waiting for app to start (max ${timeout}s)..." -ForegroundColor Cyan

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 2
    $elapsed += 2

    if (Test-Path "$env:TEMP\flutter_run.json") {
        $content = Get-Content "$env:TEMP\flutter_run.json" -Raw -ErrorAction SilentlyContinue
        if ($content -match '"vmServiceUri"\s*:\s*"([^"]+)"') {
            $vmServiceUri = $matches[1]
            break
        }
    }

    Write-Host "." -NoNewline
}

Write-Host ""

if (-not $vmServiceUri) {
    Write-Host "Could not find VM service URI. Make sure the app started successfully." -ForegroundColor Red

    # Try reading the error output
    if (Test-Path "$env:TEMP\flutter_run_err.txt") {
        $errContent = Get-Content "$env:TEMP\flutter_run_err.txt" -Raw
        if ($errContent) {
            Write-Host "Flutter output:" -ForegroundColor Yellow
            Write-Host $errContent
        }
    }

    exit 1
}

Write-Host ""
Write-Host "VM Service URI: $vmServiceUri" -ForegroundColor Green
Write-Host ""

# Query VM service for isolate info
try {
    $vmInfo = Invoke-RestMethod -Uri "$vmServiceUri/vm" -Method Get
    $isolateId = $vmInfo.vm.isolates[0].id
    Write-Host "Isolate ID: $isolateId" -ForegroundColor Green

    # Try to evaluate debugDumpRenderTree()
    Write-Host ""
    Write-Host "Evaluating debugDumpRenderTree()..." -ForegroundColor Cyan

    $evalBody = @{
        expression = """
import 'dart:developer';
import 'package:flutter/widgets.dart';
// debugDumpRenderTree is available in debug builds
final result = StringBuffer();
debugPrint = (String? message, {int? wrapWidth}) {
    result.writeln(message ?? '');
};
WidgetsBinding.instance.renderViewElement?.debugDescribeChildren()?.forEach((d) => result.writeln(d));
result.toString();
"""
        isolateId = $isolateId
    } | ConvertTo-Json

    $evalResult = Invoke-RestMethod -Uri "$vmServiceUri/$isolateId/evaluate" `
        -Method Post -Body $evalBody -ContentType "application/json"

    if ($evalResult.result) {
        Write-Host ""
        Write-Host "=== Widget Tree ===" -ForegroundColor Magenta
        Write-Host $evalResult.result.value
    } else {
        Write-Host "Evaluation result: $($evalResult | ConvertTo-Json -Depth 3)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error querying VM service: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Press 'D' in the flutter run terminal to open DevTools manually." -ForegroundColor Yellow
}

# Cleanup
if (-not $flutterProcess.HasExited) {
    Write-Host ""
    Write-Host "Stopping Flutter app..." -ForegroundColor Cyan
    $flutterProcess.Kill()
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
