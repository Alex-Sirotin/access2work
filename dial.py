import os
import json
import subprocess
import time
from pathlib import Path
import pyotp
import requests
from dotenv import load_dotenv

load_dotenv()

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

def connect_vpn(vpn, initial_ip):
    ovpn_path = f"{PROFILE_DIR}/{vpn['Name']}.ovpn"
    if not Path(ovpn_path).exists():
        log_event(f"[{vpn['Name']}] ⚠️ Профиль {ovpn_path} не найден — пропуск")
        return False

    secret = decrypt_secret(vpn["SecretPath"])
    if not secret:
        return False

    otp = pyotp.TOTP(secret).now()
    password = vpn.get("Prefix", "") + otp

    auth_path = f"{SECRET_DIR}/{vpn['Name']}.auth"
    try:
        with open(auth_path, "w") as f:
            f.write(f"{vpn['Username']}\n{password}\n")
    except Exception as e:
        log_event(f"[{vpn['Name']}] ❌ Ошибка записи .auth: {e}")
        return False

    cmd = ["openvpn", "--config", ovpn_path]
    log_event(f"[{vpn['Name']}] 🔌 Запуск OpenVPN:\n{' '.join(cmd)}")

    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    for attempt in range(1, MAX_RETRIES + 1):
        log_event(f"[{vpn['Name']}] 🔄 Попытка {attempt}")
        for line in process.stdout:
            decoded = line.decode("utf-8", errors="ignore").strip()
            log_event(f"[{vpn['Name']}] 📡 {decoded}")
            if "Initialization Sequence Completed" in decoded:
                log_event(f"[{vpn['Name']}] ✅ VPN подключен")
                new_ip = get_ip()
                log_event(f"[{vpn['Name']}] 🌐 IP после подключения: {new_ip}")
                if initial_ip == new_ip:
                    log_event(f"[{vpn['Name']}] ⚠️ IP не изменился — возможно, VPN не активен")

                route_result = subprocess.run(["ip", "route"], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 📡 ip route:\n{route_result.stdout.strip()}")

                rule_result = subprocess.run(["ip", "rule"], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 📜 ip rule:\n{rule_result.stdout.strip()}")

                tun_result = subprocess.run(["ip", "addr", "show", "dev", "tun0"], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 🔌 Интерфейс tun0:\n{tun_result.stdout.strip()}")

                return True
        time.sleep(5)

    log_event(f"[{vpn['Name']}] ❌ Ошибка после {MAX_RETRIES} попыток")
    return False

def main():
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
