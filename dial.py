import os
import json
import subprocess
import time
from pathlib import Path
import pyotp
import requests
from dotenv import load_dotenv
import psutil

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

def find_free_tun(start=0, max_search=10):
    for i in range(start, start + max_search):
        name = f"tun{i}"
        if not any(name in iface for iface in psutil.net_if_addrs()):
            return name
    return None

def connect_vpn(vpn, initial_ip, index):
    ovpn_path = f"{PROFILE_DIR}/{vpn['Name']}.ovpn"
    if not Path(ovpn_path).exists():
        log_event(f"[{vpn['Name']}] ⚠️ Профиль {ovpn_path} не найден — пропуск")
        return False

    secret = decrypt_secret(vpn["SecretPath"])
    if not secret:
        return False

    for attempt in range(1, MAX_RETRIES + 1):
        otp_time = time.time()
        otp = pyotp.TOTP(secret).now()
        password = vpn.get("Prefix", "") + otp

        auth_path = f"{SECRET_DIR}/{vpn['Name']}.auth"
        try:
            with open(auth_path, "w") as f:
                f.write(f"{vpn['Username']}\n{password}\n")
            os.chmod(auth_path, 0o600)
        except Exception as e:
            log_event(f"[{vpn['Name']}] ❌ Ошибка записи .auth: {e}")
            return False

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
            "--dev", dev_name
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
                new_ip = get_ip()
                log_event(f"[{vpn['Name']}] 🌐 IP после подключения: {new_ip}")
                if initial_ip == new_ip:
                    log_event(f"[{vpn['Name']}] ⚠️ IP не изменился — возможно, VPN не активен")

                route_result = subprocess.run(["ip", "route"], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 📡 ip route:\n{route_result.stdout.strip()}")

                rule_result = subprocess.run(["ip", "rule"], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 📜 ip rule:\n{rule_result.stdout.strip()}")

                tun_result = subprocess.run(["ip", "addr", "show", "dev", dev_name], capture_output=True, text=True)
                log_event(f"[{vpn['Name']}] 🔌 Интерфейс {dev_name}:\n{tun_result.stdout.strip()}")

                return True

        time.sleep(5)

    log_event(f"[{vpn['Name']}] ❌ Ошибка после {MAX_RETRIES} попыток")
    return False

def post_connect_check(target_file=None):
    import os
    if target_file is None:
        target_file = os.path.join(os.environ.get("SECRET_DIR", "/vpn/secrets"), "targets.txt")
    import socket, requests
    from urllib.parse import urlparse

    def check_tcp(host, port, timeout=3):
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except:
            return False

    def check_http(url, timeout=5):
        try:
            r = requests.get(url, timeout=timeout)
            return r.status_code
        except:
            return None

    print(f"📋 Проверка доступности целей из {target_file}")
    try:
        with open(target_file) as f:
            for line in f:
                target = line.strip()
                if not target or target.startswith("#"):
                    continue

                if target.startswith("http"):
                    status = check_http(target)
                    print(f"🌐 {target} → HTTP {status if status else '❌'}")
                elif ":" in target:
                    host, port = target.split(":")
                    ok = check_tcp(host, int(port))
                    print(f"🔌 {host}:{port} → {'✅' if ok else '❌'}")
                else:
                    print(f"⚠️ Неизвестный формат: {target}")
    except Exception as e:
        print(f"⛔ Ошибка при проверке целей: {e}")

def inject_hosts(file_path=f"{SECRET_DIR}/extra_hosts.txt"):
    if not Path(file_path).exists():
        log_event(f"⚠️ Файл hosts не найден: {file_path}")
        return
    try:
        with open(file_path) as f:
            lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        with open("/etc/hosts", "a") as hosts:
            for line in lines:
                hosts.write(line + "\n")
        log_event(f"📌 Добавлено {len(lines)} записей в /etc/hosts")
    except Exception as e:
        log_event(f"❌ Ошибка при добавлении в /etc/hosts: {e}")

def main():
    initial_ip = get_ip()
    log_event(f"🌐 IP до подключения: {initial_ip}")
    vpns = load_vpn_configs()
    inject_hosts()
    for i, vpn in enumerate(vpns):
        success = connect_vpn(vpn, initial_ip, i)
        if not success and STOP_ON_FAILURE:
            log_event(f"[{vpn['Name']}] ⛔ Остановка цепочки из-за ошибки")
            break

    if success:
        post_connect_check()

if __name__ == "__main__":
    main()
