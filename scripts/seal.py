import os
import json
import subprocess
from pathlib import Path
from datetime import datetime
import pyotp

SECRETS_DIR = Path("/vpn/secrets")
CONFIGS_DIR = Path("/vpn/vpn_configs")
LOG_PATH = SECRETS_DIR / "vpn_seal.log"

SEAL_MODE = os.getenv("SEAL_MODE", "normal").lower()
FORCE = SEAL_MODE == "force"
DRYRUN = SEAL_MODE == "dryrun"
GPG_PASSPHRASE = os.getenv("GPG_PASSPHRASE")

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

def main():
    log(f"🔐 Запуск seal.py — SEAL_MODE={SEAL_MODE}")
    if not GPG_PASSPHRASE and not DRYRUN:
        log("❌ GPG_PASSPHRASE не задан — остановка")
        return

    for config_path in CONFIGS_DIR.glob("*.json"):
        profile_name = config_path.stem
        gpg_path = SECRETS_DIR / f"{profile_name}.gpg"

        try:
            with open(config_path) as f:
                config = json.load(f)

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

    if DRYRUN:
        log("🔍 Завершён dry-run: ни один файл не был создан.")
    else:
        log("✅ Завершено шифрование всех доступных конфигов.")

if __name__ == "__main__":
    main()
