#Requires -Version 5.1
<#
.SYNOPSIS
    Detecta o target de desenvolvimento Flutter e configura o ambiente.

.DESCRIPTION
    - Procura adb no PATH, ANDROID_HOME, ANDROID_SDK_ROOT e locais padrao.
    - Detecta se o target e emulador, dispositivo fisico ou desktop.
    - Executa 'adb reverse tcp:8080 tcp:8080' para dispositivos fisicos.
    - Gera .vscode/.dart-define.json com a URL base correta do backend.
    - Gera .vscode/.dev-target.json com metadados do target detectado.
    - Todos os comandos adb tem timeout de 5s para nunca travar.

.OUTPUTS
    Escreve arquivos JSON em .vscode/ e logs no console.
#>

param(
    [int]$BackendPort = 8080,
    [string]$DartDefineFile = ".vscode/.dart-define.json",
    [string]$DevTargetFile = ".vscode/.dev-target.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve caminhos relativos ao workspace (script esta em scripts/)
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$dartDefinePath = Join-Path $workspaceRoot $DartDefineFile
$devTargetPath = Join-Path $workspaceRoot $DevTargetFile

function Find-Adb {
    # 1. PATH
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($adb) { return $adb.Source }

    # 2. ANDROID_HOME
    if ($env:ANDROID_HOME) {
        $p = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
        if (Test-Path $p) { return $p }
    }

    # 3. ANDROID_SDK_ROOT
    if ($env:ANDROID_SDK_ROOT) {
        $p = Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe"
        if (Test-Path $p) { return $p }
    }

    # 4. LOCALAPPDATA padrao (Android Studio no Windows)
    $localAppData = $env:LOCALAPPDATA
    if ($localAppData) {
        $candidates = @(
            "$localAppData\Android\Sdk\platform-tools\adb.exe"
            "$localAppData\Android\android-sdk\platform-tools\adb.exe"
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { return $c }
        }
    }

    # 5. Program Files
    $progFiles = $env:ProgramFiles
    if ($progFiles) {
        $candidates = @(
            "$progFiles\Android\android-sdk\platform-tools\adb.exe"
            "$progFiles\Android\Sdk\platform-tools\adb.exe"
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { return $c }
        }
    }

    return $null
}

function Invoke-AdbWithTimeout {
    param(
        [string]$AdbPath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 5
    )

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $AdbPath
    $pinfo.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    $process.Start() | Out-Null

    # Aguarda o processo com timeout
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        Write-Host "[setup-dev-env] adb timeout apos ${TimeoutSeconds}s. Matando processo..."
        try { $process.Kill() } catch {}
        $process.WaitForExit(1000) | Out-Null
        return $null
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    if ($process.ExitCode -ne 0 -and $stderr) {
        Write-Host "[setup-dev-env] adb stderr: $stderr"
    }
    return $stdout
}

function Get-DevTarget {
    $adbPath = Find-Adb
    if (-not $adbPath) {
        Write-Host "[setup-dev-env] adb nao encontrado. Assumindo desktop/web."
        return @{ type = 'desktop'; apiBaseUrl = "http://localhost:$BackendPort/api/v1"; adbAvailable = $false; deviceId = $null; adbPath = $null }
    }

    Write-Host "[setup-dev-env] adb encontrado: $adbPath"

    # adb devices com timeout para nunca travar
    $devicesOutput = Invoke-AdbWithTimeout -AdbPath $adbPath -Arguments @("devices") -TimeoutSeconds 5
    if ($devicesOutput -eq $null) {
        Write-Host "[setup-dev-env] adb devices travou (timeout). Assumindo desktop/web."
        return @{ type = 'desktop'; apiBaseUrl = "http://localhost:$BackendPort/api/v1"; adbAvailable = $true; deviceId = $null; adbPath = $adbPath }
    }

    $deviceLines = $devicesOutput -split "`r?`n" | Where-Object { $_ -match '^\S+\s+device$' }

    if (-not $deviceLines) {
        Write-Host "[setup-dev-env] Nenhum dispositivo Android conectado. Assumindo desktop/web."
        return @{ type = 'desktop'; apiBaseUrl = "http://localhost:$BackendPort/api/v1"; adbAvailable = $true; deviceId = $null; adbPath = $adbPath }
    }

    foreach ($line in $deviceLines) {
        $parts = $line -split '\s+'
        $deviceId = $parts[0]

        $isEmulator = $deviceId -match 'emulator'

        if (-not $isEmulator) {
            $hw = Invoke-AdbWithTimeout -AdbPath $adbPath -Arguments @("-s", $deviceId, "shell", "getprop", "ro.hardware") -TimeoutSeconds 3
            if ($hw -and ($hw -match 'goldfish|ranchu|qemu|virtio')) {
                $isEmulator = $true
            }
        }

        if ($isEmulator) {
            Write-Host "[setup-dev-env] Emulador detectado: $deviceId"
            return @{
                type = 'emulator'
                apiBaseUrl = "http://10.0.2.2:$BackendPort/api/v1"
                adbAvailable = $true
                deviceId = $deviceId
                adbPath = $adbPath
            }
        }
        else {
            Write-Host "[setup-dev-env] Dispositivo fisico detectado: $deviceId"
            Write-Host "[setup-dev-env] Executando adb reverse tcp:$BackendPort tcp:$BackendPort ..."
            $reverseOut = Invoke-AdbWithTimeout -AdbPath $adbPath -Arguments @("-s", $deviceId, "reverse", "tcp:$BackendPort", "tcp:$BackendPort") -TimeoutSeconds 5
            if ($reverseOut -ne $null) {
                Write-Host "[setup-dev-env] adb reverse OK para $deviceId"
            } else {
                Write-Warning "[setup-dev-env] adb reverse falhou ou timeout para $deviceId"
            }
            return @{
                type = 'device'
                apiBaseUrl = "http://localhost:$BackendPort/api/v1"
                adbAvailable = $true
                deviceId = $deviceId
                adbPath = $adbPath
            }
        }
    }

    return @{ type = 'unknown'; apiBaseUrl = "http://localhost:$BackendPort/api/v1"; adbAvailable = $true; deviceId = $null; adbPath = $adbPath }
}

$target = Get-DevTarget

$dartDefine = @{
    API_BASE_URL = $target.apiBaseUrl
}
$dartDefine | ConvertTo-Json -Depth 2 | Set-Content -Path $dartDefinePath -Encoding UTF8

$devTarget = @{
    type         = $target.type
    apiBaseUrl   = $target.apiBaseUrl
    adbAvailable = $target.adbAvailable
    deviceId     = $target.deviceId
    adbPath      = $target.adbPath
    generatedAt  = (Get-Date -Format "o")
}
$devTarget | ConvertTo-Json -Depth 2 | Set-Content -Path $devTargetPath -Encoding UTF8

Write-Host "[setup-dev-env] Target: $($target.type)"
Write-Host "[setup-dev-env] API_BASE_URL: $($target.apiBaseUrl)"
Write-Host "[setup-dev-env] Arquivos gerados: $DartDefineFile, $DevTargetFile"
