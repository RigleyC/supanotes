import json
import os
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timezone

# Configuração
BACKEND_PORT = 8080
WORKSPACE_ROOT = Path(__file__).parent.parent
DART_DEFINE_FILE = WORKSPACE_ROOT / ".vscode" / ".dart-define.json"
DEV_TARGET_FILE = WORKSPACE_ROOT / ".vscode" / ".dev-target.json"


def log(msg):
    print(f"[setup-dev-env] {msg}", flush=True)


def find_adb():
    """Procura adb.exe em vários locais comuns."""
    # 1. PATH
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        adb_path = Path(path_dir) / "adb.exe"
        if adb_path.exists():
            return str(adb_path)

    # 2. ANDROID_HOME
    android_home = os.environ.get("ANDROID_HOME")
    if android_home:
        adb_path = Path(android_home) / "platform-tools" / "adb.exe"
        if adb_path.exists():
            return str(adb_path)

    # 3. ANDROID_SDK_ROOT
    android_sdk_root = os.environ.get("ANDROID_SDK_ROOT")
    if android_sdk_root:
        adb_path = Path(android_sdk_root) / "platform-tools" / "adb.exe"
        if adb_path.exists():
            return str(adb_path)

    # 4. LOCALAPPDATA
    local_appdata = os.environ.get("LOCALAPPDATA")
    if local_appdata:
        candidates = [
            Path(local_appdata) / "Android" / "Sdk" / "platform-tools" / "adb.exe",
            Path(local_appdata) / "Android" / "android-sdk" / "platform-tools" / "adb.exe",
        ]
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)

    # 5. Program Files
    program_files = os.environ.get("ProgramFiles")
    if program_files:
        candidates = [
            Path(program_files) / "Android" / "android-sdk" / "platform-tools" / "adb.exe",
            Path(program_files) / "Android" / "Sdk" / "platform-tools" / "adb.exe",
        ]
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)

    return None


def run_adb(adb_path, args, timeout=5):
    """Executa adb com timeout para evitar travamentos."""
    try:
        result = subprocess.run(
            [adb_path] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        log(f"adb timeout apos {timeout}s")
        return None
    except Exception as e:
        log(f"adb erro: {e}")
        return None


def get_dev_target():
    adb_path = find_adb()
    if not adb_path:
        log("adb nao encontrado. Assumindo desktop/web.")
        return {
            "type": "desktop",
            "apiBaseUrl": f"http://localhost:{BACKEND_PORT}/api/v1",
            "adbAvailable": False,
            "deviceId": None,
            "adbPath": None,
        }

    log(f"adb encontrado: {adb_path}")

    # adb devices com timeout
    devices_output = run_adb(adb_path, ["devices"], timeout=5)
    if devices_output is None:
        log("adb devices travou (timeout). Assumindo desktop/web.")
        return {
            "type": "desktop",
            "apiBaseUrl": f"http://localhost:{BACKEND_PORT}/api/v1",
            "adbAvailable": True,
            "deviceId": None,
            "adbPath": adb_path,
        }

    # Parse dispositivos
    device_lines = []
    for line in devices_output.splitlines():
        if re.match(r"^\S+\s+device$", line):
            device_lines.append(line)

    if not device_lines:
        log("Nenhum dispositivo Android conectado. Assumindo desktop/web.")
        return {
            "type": "desktop",
            "apiBaseUrl": f"http://localhost:{BACKEND_PORT}/api/v1",
            "adbAvailable": True,
            "deviceId": None,
            "adbPath": adb_path,
        }

    for line in device_lines:
        parts = line.split()
        device_id = parts[0]

        is_emulator = "emulator" in device_id

        if not is_emulator:
            hw = run_adb(adb_path, ["-s", device_id, "shell", "getprop", "ro.hardware"], timeout=3)
            if hw and re.search(r"goldfish|ranchu|qemu|virtio", hw):
                is_emulator = True

        if is_emulator:
            log(f"Emulador detectado: {device_id}")
            return {
                "type": "emulator",
                "apiBaseUrl": f"http://10.0.2.2:{BACKEND_PORT}/api/v1",
                "adbAvailable": True,
                "deviceId": device_id,
                "adbPath": adb_path,
            }
        else:
            log(f"Dispositivo fisico detectado: {device_id}")
            log(f"Executando adb reverse tcp:{BACKEND_PORT} tcp:{BACKEND_PORT} ...")
            reverse_out = run_adb(
                adb_path,
                ["-s", device_id, "reverse", f"tcp:{BACKEND_PORT}", f"tcp:{BACKEND_PORT}"],
                timeout=5,
            )
            if reverse_out is not None:
                log(f"adb reverse OK para {device_id}")
            else:
                log(f"adb reverse falhou ou timeout para {device_id}")
            return {
                "type": "device",
                "apiBaseUrl": f"http://localhost:{BACKEND_PORT}/api/v1",
                "adbAvailable": True,
                "deviceId": device_id,
                "adbPath": adb_path,
            }

    return {
        "type": "unknown",
        "apiBaseUrl": f"http://localhost:{BACKEND_PORT}/api/v1",
        "adbAvailable": True,
        "deviceId": None,
        "adbPath": adb_path,
    }


def main():
    target = get_dev_target()

    # Gera .dart-define.json
    dart_define = {"API_BASE_URL": target["apiBaseUrl"]}
    with open(DART_DEFINE_FILE, "w", encoding="utf-8") as f:
        json.dump(dart_define, f, indent=4)

    # Gera .dev-target.json
    dev_target = {
        "type": target["type"],
        "apiBaseUrl": target["apiBaseUrl"],
        "adbAvailable": target["adbAvailable"],
        "deviceId": target["deviceId"],
        "adbPath": target["adbPath"],
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
    with open(DEV_TARGET_FILE, "w", encoding="utf-8") as f:
        json.dump(dev_target, f, indent=4)

    log(f"Target: {target['type']}")
    log(f"API_BASE_URL: {target['apiBaseUrl']}")
    log(f"Arquivos gerados: .vscode/.dart-define.json, .vscode/.dev-target.json")


if __name__ == "__main__":
    main()
