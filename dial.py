import os
import json
import subprocess
import time
from pathlib import Path
import pyotp
import requests
from dotenv import load_dotenv

load_dotenv()

VPNCMD = "/vpn/vpnclient/vpncmd"
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "3"))
OTP_VALIDITY = int(os.getenv("OTP_VALIDITY", "30"))
CONFIG_DIR = os.getenv("VPN_CONFIG_DIR", "/vpn/vpn_configs")
PROFILE_DIR = os.getenv("VPN_PROFILE_DIR", "/vpn/vpn_profiles")
SECRET_DIR = os.getenv("VPN_SECRET_DIR", "/vpn/secrets")
LOG_PATH = os.getenv("LOG_PATH", "/vpn/secrets/vpn_connect.log")
ENABLE_LOG = os.getenv("ENABLE_LOG", "true").lower() == "true"
STOP_ON_FAILURE = os.getenv("STOP_ON_FAILURE", "true").lower() == "true"

def log_event(message):
    print(message)
    if ENABLE_LOG:
        try:
            with open(LOG_PATH, "a") as log:
                log.write(message + "\n")
        except Exception as e:
            fallback_path = "/vpn/secrets/fallback.log"
            print(f"⚠️ Не удалось записать лог в {LOG_PATH}: {e}")
            print(f"📄 Пишем в резервный лог: {fallback_path}")
            try:
                with open(fallback_path, "a") as fallback:
                    fallback.write(message + "\n")
            except Exception as e2:
                print(f"❌ Ошибка записи в fallback.log: {e2}")

def get_ip():
    try:
        return requests.get("https://ifconfig.me", timeout=5).text.strip()
    except:
        return "Unavailable"

def load_vpn_configs():
    configs = []
    for file in Path(CONFIG_DIR).glob("*.json"):
        try:
            with open(file) as f:
                config = json.load(f)
                config["Name"] = file.stem
                config["SecretPath"] = str(Path(SECRET_DIR) / f"{file.stem}.gpg")
                config["Order"] = int(config.get("Order", 9999))
                configs.append(config)
        except Exception as e:
            log_event(f"[{file.name}] ❌ Ошибка чтения: {e}")
    sorted_configs = sorted(configs, key=lambda c: c["Order"])
    log_event(f"📋 Порядок подключения: {[c['Name'] for c in sorted_configs]}")
    return sorted_configs

def decrypt_secret(path):
    if not Path(path).exists():
        log_event(f"❌ SecretPath не найден: {path}")
        return None
    if path.endswith(".gpg"):
        passphrase = os.getenv("GPG_PASSPHRASE")
        if not passphrase:
            log_event("❌ GPG_PASSPHRASE не задан в .env")
            return None
        result = subprocess.run(
            ["gpg", "--quiet", "--batch", "--yes", "--passphrase-fd", "0", "--decrypt", path],
            input=passphrase,
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            log_event(f"❌ Ошибка GPG: {result.stderr.strip()}")
            return None
        return result.stdout.strip()
    return Path(path).read_text().strip()

def import_vpn_profile(vpn_name):
    profile_path = f"{PROFILE_DIR}/{vpn_name}.vpn"
    if not Path(profile_path).exists():
        log_event(f"[{vpn_name}] ⚠️ Профиль {profile_path} не найден — пропуск")
        return False
    subprocess.run([VPNCMD, "localhost", "/CLIENT", "/CMD", "AccountDelete", vpn_name], capture_output=True)
    subprocess.run([VPNCMD, "localhost", "/CLIENT", "/CMD", "AccountImport", profile_path], capture_output=True)
    log_event(f"[{vpn_name}] 📥 Профиль импортирован")
    return True

def connect_vpn(vpn, initial_ip):
    if not import_vpn_profile(vpn["Name"]):
        return False

    secret = decrypt_secret(vpn["SecretPath"])
    if not secret:
        return False

    log_event(f"[{vpn['Name']}] 🔐 Расшифрованный секрет: {repr(secret)}")

    otp = pyotp.TOTP(secret).now()
    password = vpn.get("Prefix", "") + otp

    cmd = [
        VPNCMD, "localhost", "/CLIENT", "/CMD",
        "AccountConnect", vpn["Name"],
        f"/USERNAME:{vpn['Username']}",
        f"/PASSWORD:{password}"
    ]

    log_event(f"[{vpn['Name']}] 🧪 Команда подключения: {' '.join(cmd)}")

    for attempt in range(1, MAX_RETRIES + 1):
        log_event(f"[{vpn['Name']}] 🔄 Попытка {attempt}")
        result = subprocess.run(cmd, capture_output=True, text=True)

        if "Session Status            : Connected" in result.stdout:
            log_event(f"[{vpn['Name']}] ✅ Подключено")
            new_ip = get_ip()
            log_event(f"[{vpn['Name']}] 🌐 IP после подключения: {new_ip}")
            if initial_ip == new_ip:
                log_event(f"[{vpn['Name']}] ⚠️ IP не изменился — возможно, VPN не активен")

            status_cmd = [VPNCMD, "localhost", "/CLIENT", "/CMD", "AccountStatusGet", vpn["Name"]]
            status_result = subprocess.run(status_cmd, capture_output=True, text=True)
            log_event(f"[{vpn['Name']}] 📊 Статус аккаунта:\n{status_result.stdout.strip()}")

            route_result = subprocess.run(["ip", "route"], capture_output=True, text=True)
            log_event(f"[{vpn['Name']}] 📡 ip route:\n{route_result.stdout.strip()}")

            rule_result = subprocess.run(["ip", "rule"], capture_output=True, text=True)
            log_event(f"[{vpn['Name']}] 📜 ip rule:\n{rule_result.stdout.strip()}")

            tun_result = subprocess.run(["ip", "addr", "show", "dev", "tun0"], capture_output=True, text=True)
            log_event(f"[{vpn['Name']}] 🔌 Интерфейс tun0:\n{tun_result.stdout.strip()}")

            return True
        else:
            log_event(f"[{vpn['Name']}] ❌ Ошибка подключения:\n{result.stdout.strip()}")
        time.sleep(5)

    log_event(f"[{vpn['Name']}] ❌ Ошибка после {MAX_RETRIES} попыток")
    return False

def start_vpnclient():
    result = subprocess.run(["/vpn/vpnclient/vpnclient", "start"], capture_output=True, text=True)
    if result.returncode != 0:
        log_event(f"❌ Не удалось запустить vpnclient: {result.stderr.strip()}")
    else:
        log_event("✅ vpnclient запущен")

    try:
        ps = subprocess.run(["ps", "-ef"], capture_output=True, text=True)
        lines = [line for line in ps.stdout.splitlines() if "vpnclient" in line and "start" not in line]
        if lines:
            for line in lines:
                log_event(f"🔎 vpnclient процесс: {line}")
        else:
            log_event("⚠️ vpnclient процесс не найден в ps")
    except Exception as e:
        log_event(f"❌ Ошибка при проверке vpnclient процесса: {e}")

def main():
    start_vpnclient()
    initial_ip = get_ip()
    log_event(f"🌐 IP до подключения: {initial_ip}")
    vpns = load_vpn_configs()
    for vpn in vpns:
        success = connect_vpn(vpn, initial_ip)
        if not success and STOP_ON_FAILURE:
            log_event(f"[{vpn['Name']}] ⛔ Остановка цепочки из-за ошибки")
            break

if __name__ == "__main__":
    main()
