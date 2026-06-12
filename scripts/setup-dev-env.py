import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from datetime import datetime, timezone

# Configuração
BACKEND_PORT = 8080
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable",
)
WORKSPACE_ROOT = Path(__file__).parent.parent
BACKEND_DIR = WORKSPACE_ROOT / "backend"
DART_DEFINE_FILE = WORKSPACE_ROOT / ".vscode" / ".dart-define.json"
LOCAL_DART_DEFINE_FILE = WORKSPACE_ROOT / ".vscode" / ".dart-define.local.json"
EMULATOR_DART_DEFINE_FILE = WORKSPACE_ROOT / ".vscode" / ".dart-define.emulator.json"
DEV_TARGET_FILE = WORKSPACE_ROOT / ".vscode" / ".dev-target.json"


def log(msg):
    print(f"[setup-dev-env] {msg}", flush=True)


def run(cmd, cwd=WORKSPACE_ROOT, timeout=60, env=None):
    log("$ " + " ".join(cmd))
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=merged_env,
        text=True,
        timeout=timeout,
    )


def ensure_postgres():
    log("Subindo Postgres de desenvolvimento...")
    result = run(["docker", "compose", "up", "-d", "postgres"], timeout=120)
    if result.returncode != 0:
        sys.exit(result.returncode)

    log("Aguardando Postgres ficar pronto...")
    for _ in range(30):
        result = run(
            [
                "docker",
                "compose",
                "exec",
                "-T",
                "postgres",
                "pg_isready",
                "-U",
                "supanotes",
                "-d",
                "supanotes",
            ],
            timeout=10,
        )
        if result.returncode == 0:
            log("Postgres pronto.")
            return
        time.sleep(1)

    log("Postgres nao ficou pronto em 30s.")
    sys.exit(1)


def run_migrations():
    log("Verificando migrations pendentes do backend...")
    result = run(
        ["go", "run", "./cmd/migrate"],
        cwd=BACKEND_DIR,
        timeout=120,
        env={"DATABASE_URL": DATABASE_URL},
    )
    if result.returncode != 0:
        sys.exit(result.returncode)


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


def setup_android_reverse_for_physical_devices():
    adb_path = find_adb()
    if not adb_path:
        log("adb nao encontrado. Pulando adb reverse.")
        return {
            "adbAvailable": False,
            "physicalDevices": [],
            "emulators": [],
            "adbPath": None,
        }

    devices_output = run_adb(adb_path, ["devices"], timeout=5)
    if devices_output is None:
        log("adb devices travou (timeout). Pulando adb reverse.")
        return {
            "adbAvailable": True,
            "physicalDevices": [],
            "emulators": [],
            "adbPath": adb_path,
        }

    physical_devices = []
    emulators = []
    for line in devices_output.splitlines():
        if not re.match(r"^\S+\s+device$", line):
            continue

        device_id = line.split()[0]
        is_emulator = "emulator" in device_id
        if not is_emulator:
            hw = run_adb(adb_path, ["-s", device_id, "shell", "getprop", "ro.hardware"], timeout=3)
            if hw and re.search(r"goldfish|ranchu|qemu|virtio", hw):
                is_emulator = True

        if is_emulator:
            emulators.append(device_id)
            continue

        physical_devices.append(device_id)
        log(f"Executando adb reverse tcp:{BACKEND_PORT} tcp:{BACKEND_PORT} em {device_id} ...")
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
        "adbAvailable": True,
        "physicalDevices": physical_devices,
        "emulators": emulators,
        "adbPath": adb_path,
    }


def write_dart_define(path, api_base_url):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"API_BASE_URL": api_base_url}, f, indent=4)


def main():
    ensure_postgres()
    run_migrations()

    android = setup_android_reverse_for_physical_devices()
    local_api_base_url = f"http://localhost:{BACKEND_PORT}/api/v1"
    emulator_api_base_url = f"http://10.0.2.2:{BACKEND_PORT}/api/v1"

    write_dart_define(DART_DEFINE_FILE, local_api_base_url)
    write_dart_define(LOCAL_DART_DEFINE_FILE, local_api_base_url)
    write_dart_define(EMULATOR_DART_DEFINE_FILE, emulator_api_base_url)

    # Gera .dev-target.json
    dev_target = {
        "apiBaseUrl": local_api_base_url,
        "emulatorApiBaseUrl": emulator_api_base_url,
        "adbAvailable": android["adbAvailable"],
        "physicalDevices": android["physicalDevices"],
        "emulators": android["emulators"],
        "adbPath": android["adbPath"],
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
    with open(DEV_TARGET_FILE, "w", encoding="utf-8") as f:
        json.dump(dev_target, f, indent=4)

    log(f"API_BASE_URL local/device: {local_api_base_url}")
    log(f"API_BASE_URL emulador: {emulator_api_base_url}")
    log("Arquivos gerados: .vscode/.dart-define*.json, .vscode/.dev-target.json")


if __name__ == "__main__":
    main()
