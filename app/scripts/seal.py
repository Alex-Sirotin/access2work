import os
import json
import subprocess
from pathlib import Path
from datetime import datetime
import pyotp
from config import settings

VPN_CONFIG = Path(settings.VPN_CONFIG)
SECRETS_DIR = Path(settings.VPN_SECRET_DIR)
LOG_PATH = Path(settings.SEAL_LOG_PATH)
SEAL_MODE = settings.SEAL_MODE
GPG_PASSPHRASE = settings.GPG_PASSPHRASE
FORCE = SEAL_MODE == "force"
DRYRUN = SEAL_MODE == "dryrun"

def log(msg):
    print(msg)
    with open(LOG_PATH, "a") as f:
        f.write(f"{datetime.now().isoformat()} {msg}\n")

def validate_base32(secret):
    import base64
    try:
        base64.b32decode(secret.upper())
        return True
    except Exception:
        return False

def encrypt_and_save(secret, output_path):
    result = subprocess.run(
        ["gpg", "--quiet", "--batch", "--yes", "--passphrase-fd", "0", "-o", str(output_path), "-c"],
        input=GPG_PASSPHRASE + "\n" + secret,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"GPG error: {result.stderr.strip()}")

def process_vpn_configs():
    config_file = VPN_CONFIG

    try:
        with open(config_file) as f:
            vpn_list = json.load(f)
    except Exception as e:
        log(f"❌ Ошибка чтения {config_file.name}: {e}")
        return

    for config in vpn_list:
        profile_name = config.get("Name")
        if not profile_name:
            log("⚠️ Пропущен конфиг без поля Name")
            continue

        gpg_path = SECRETS_DIR / f"{profile_name}.gpg"

        try:
            otp_secret = config.get("otp_secret")
            if not otp_secret and "OtpAuthUrl" in config:
                try:
                    otp_secret = pyotp.parse_uri(config["OtpAuthUrl"]).secret
                    log(f"🔍 {profile_name}: otp_secret извлечён из OtpAuthUrl")
                except Exception as e:
                    log(f"❌ {profile_name}: Ошибка парсинга OtpAuthUrl — {e}")
                    continue

            if not otp_secret:
                log(f"⚠️ {profile_name}: otp_secret отсутствует")
                continue
            if not validate_base32(otp_secret):
                log(f"❌ {profile_name}: Невалидный otp_secret")
                continue
            if gpg_path.exists() and not FORCE:
                log(f"♻️ {profile_name}: .gpg уже существует, пропущено")
                continue

            if DRYRUN:
                log(f"🟡 [DRYRUN] Пропущено шифрование для {profile_name}")
            else:
                encrypt_and_save(otp_secret, gpg_path)
                log(f"✅ Зашифровано: {gpg_path}")

        except Exception as e:
            log(f"❌ {profile_name}: Ошибка — {e}")

def main():
    log(f"🔐 Запуск seal.py — SEAL_MODE={SEAL_MODE}")
    if not GPG_PASSPHRASE and not DRYRUN:
        log("❌ GPG_PASSPHRASE не задан — остановка")
        return

    process_vpn_configs()

if __name__ == "__main__":
    main()
