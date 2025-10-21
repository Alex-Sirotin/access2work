import os
import json
import subprocess
import time
from pathlib import Path
import pyotp
import requests
import psutil
from config import settings

MAX_RETRIES = settings.MAX_RETRIES
OTP_VALIDITY = settings.OTP_VALIDITY
VPN_CONNECT_DELAY = settings.VPN_CONNECT_DELAY
OPENVPN_RETRY = settings.OPENVPN_RETRY
OPENVPN_RETRY_DELAY = settings.OPENVPN_RETRY_DELAY
GPG_PASSPHRASE = settings.GPG_PASSPHRASE
HOSTS_DIR = settings.HOSTS_DIR

ENABLE_LOG = settings.ENABLE_LOG
STOP_ON_FAILURE = settings.STOP_ON_FAILURE
FALLBACK_LOG = settings.FALLBACK_LOG
LOG_PATH = settings.LOG_PATH

VPN_CONFIG = settings.VPN_CONFIG
SECRET_DIR = settings.VPN_SECRET_DIR
PROFILE_DIR = settings.VPN_PROFILE_DIR
EXTRA_HOSTS_CONFIG = settings.EXTRA_HOSTS_CONFIG

def log_event(message):
    print(message)
    if ENABLE_LOG:
        try:
            with open(LOG_PATH, "a") as log:
                log.write(message + "\n")
        except Exception as e:
            print(f"⚠️ Не удалось записать лог в {LOG_PATH}: {e}")
            print(f"📄 Пишем в резервный лог: {FALLBACK_LOG}")
            try:
                with open(FALLBACK_LOG, "a") as fallback:
                    fallback.write(message + "\n")
            except Exception as e2:
                print(f"❌ Ошибка записи в {FALLBACK_LOG}: {e2}")

def load_vpn_configs():
    configs = []
    config_file = Path(VPN_CONFIG)
    
    try:
        with open(config_file) as f:
            data = json.load(f)
            for entry in data:
                entry["SecretPath"] = str(Path(SECRET_DIR) / f"{entry['Name']}.gpg")
                entry["Order"] = int(entry.get("Order", 9999))
                configs.append(entry)
    except Exception as e:
        log_event(f"[{config_file.name}] ❌ Ошибка чтения: {e}")
    
    sorted_configs = sorted(configs, key=lambda c: c["Order"])
    log_event(f"📋 Порядок подключения: {[c['Name'] for c in sorted_configs]}")
    return sorted_configs

def decrypt_secret(path):
    if not Path(path).exists():
        log_event(f"❌ SecretPath не найден: {path}")
        return None
    if path.endswith(".gpg"):
        if not GPG_PASSPHRASE:
            log_event("❌ GPG_PASSPHRASE не задан в .env")
            return None
        result = subprocess.run(
            ["gpg", "--quiet", "--batch", "--yes", "--passphrase-fd", "0", "--decrypt", path],
            input=GPG_PASSPHRASE,
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            log_event(f"❌ Ошибка GPG: {result.stderr.strip()}")
            return None
        log_event(f"🔓 Секрет расшифрован: {path}")
        return result.stdout.strip()
    return Path(path).read_text().strip()

def find_free_tun(start=0, max_search=10):
    for i in range(start, start + max_search):
        name = f"tun{i}"
        if not any(name in iface for iface in psutil.net_if_addrs()):
            return name
    return None

def connect_vpn(vpn, index):
    ovpn_path = f"{PROFILE_DIR}/{vpn['Name']}.ovpn"
    if not Path(ovpn_path).exists():
        log_event(f"[{vpn['Name']}] ⚠️ Профиль {ovpn_path} не найден — пропуск")
        return False

    secret = decrypt_secret(vpn["SecretPath"])
    if not secret:
        return False

    if not vpn.get("Username"):
        log_event(f"[{vpn['Name']}] ❌ Username не задан в конфиге")
        return False

    auth_path = f"{SECRET_DIR}/{vpn['Name']}.auth"

    try:
        for attempt in range(1, MAX_RETRIES + 1):
            otp_time = time.time()
            otp = pyotp.TOTP(secret).now()
            password = vpn.get("Prefix", "") + otp

            with open(auth_path, "w") as f:
                f.write(f"{vpn['Username']}\n{password}\n")
            os.chmod(auth_path, 0o600)

            age = time.time() - otp_time
            if age > OTP_VALIDITY:
                log_event(f"[{vpn['Name']}] ⚠️ OTP устарел ({int(age)}s) — пропуск попытки")
                if STOP_ON_FAILURE:
                    return False
                continue

            dev_name = find_free_tun(start=index)
            if not dev_name:
                log_event(f"[{vpn['Name']}] ❌ Нет свободного tun-интерфейса")
                return False
            log_event(f"[{vpn['Name']}] 🧵 Назначен интерфейс: {dev_name}")

            cmd = [
                "openvpn",
                "--config", ovpn_path,
                "--auth-user-pass", auth_path,
                "--dev", dev_name,
                "--connect-retry-max", OPENVPN_RETRY,
                "--connect-retry", OPENVPN_RETRY_DELAY
            ]

            log_event(f"[{vpn['Name']}] 🔄 Попытка {attempt}")
            log_event(f"[{vpn['Name']}] 🔌 Запуск OpenVPN:\n{' '.join(cmd)}")

            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            for line in process.stdout:
                decoded = line.decode("utf-8", errors="ignore").strip()
                log_event(f"[{vpn['Name']}] 📡 {decoded}")
                if "Initialization Sequence Completed" in decoded:
                    log_event(f"[{vpn['Name']}] ✅ VPN подключен")
                    try:
                        os.remove(auth_path)
                        log_event(f"[{vpn['Name']}] 🧹 Удалён .auth после подключения")
                    except Exception as e:
                        log_event(f"[{vpn['Name']}] ⚠️ Не удалось удалить .auth: {e}")

                    route_result = subprocess.run(["ip", "route"], capture_output=True, text=True)
                    log_event(f"[{vpn['Name']}] 📡 ip route:\n{route_result.stdout.strip()}")

                    rule_result = subprocess.run(["ip", "rule"], capture_output=True, text=True)
                    log_event(f"[{vpn['Name']}] 📜 ip rule:\n{rule_result.stdout.strip()}")

                    tun_result = subprocess.run(["ip", "addr", "show", "dev", dev_name], capture_output=True, text=True)
                    log_event(f"[{vpn['Name']}] 🔌 Интерфейс {dev_name}:\n{tun_result.stdout.strip()}")

                    return True

            time.sleep(5)

    finally:
        if Path(auth_path).exists():
            try:
                os.remove(auth_path)
                log_event(f"[{vpn['Name']}] 🧹 Удалён .auth после неудачи")
            except Exception as e:
                log_event(f"[{vpn['Name']}] ⚠️ Не удалось удалить .auth: {e}")

    log_event(f"[{vpn['Name']}] ❌ Ошибка после {MAX_RETRIES} попыток")
    return False

def inject_hosts(file_path=f"{EXTRA_HOSTS_CONFIG}"):
    if not Path(file_path).exists():
        log_event(f"⚠️ Файл hosts не найден: {file_path}")
        return
    try:
        with open(file_path) as f:
            lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        with open(HOSTS_DIR, "a") as hosts:
            for line in lines:
                hosts.write(line + "\n")
        log_event(f"📌 Добавлено {len(lines)} записей в {HOSTS_DIR}")
    except Exception as e:
        log_event(f"❌ Ошибка при добавлении в {HOSTS_DIR}: {e}")

def main():
    vpns = load_vpn_configs()
    if not vpns:
        log_event("❌ Нет доступных VPN-конфигов — завершение")
        return
    inject_hosts()
    subprocess.run(["cat", HOSTS_DIR])
    for i, vpn in enumerate(vpns):
        success = connect_vpn(vpn, i)
        if not success and STOP_ON_FAILURE:
            log_event(f"[{vpn['Name']}] ⛔ Остановка цепочки из-за ошибки")
            break
        if i < len(vpns) - 1:
            log_event(f"⏳ Пауза {VPN_CONNECT_DELAY}s перед следующим VPN")
            time.sleep(VPN_CONNECT_DELAY)
    log_event("✅ dial.py завершён")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log_event(f"❌ dial.py аварийно завершён: {e}")
