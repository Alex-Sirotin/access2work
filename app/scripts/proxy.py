import json
import subprocess
import socket
import os
import time

from config import settings

DB_CONFIG = settings.DB_CONFIG
REPO_CONFIG = settings.REPO_CONFIG
PROXY_LOG_PATH = settings.PROXY_LOG_PATH
PROXY_MODE = settings.PROXY_MODE

def log(msg):
    with open(PROXY_LOG_PATH, "a") as f:
        f.write(msg + "\n")
    print(msg)

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        log(f"❌ Ошибка чтения {path}: {e}")
        return []

def is_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0

def start_tunnel(name, local_port, remote_host, remote_port, remote_user):
    if is_port_open(local_port):
        if PROXY_MODE == "force":
            log(f"🔁 [{name}] порт {local_port} занят, но PROXY_MODE=force — перезапускаем туннель")
        else:
            log(f"⏸ [{name}] порт {local_port} уже занят — туннель не запускается")
            return

    cmd = [
        "autossh", "-M", "0", "-f", "-N",
        "-o", "StrictHostKeyChecking=no",
        "-L", f"{local_port}:localhost:{remote_port}",
        f"{remote_user}@{remote_host}"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)

        time.sleep(2)
        if not is_port_open(local_port):
            log(f"⚠️ [{name}] autossh запущен, но порт {local_port} не слушается — туннель не поднят")

        if result.returncode == 0:
            log(f"✅ [{name}] туннель {local_port} → {remote_host}:{remote_port} запущен")
        else:
            log(f"❌ [{name}] ошибка запуска: {result.stderr.strip()}")
    except subprocess.CalledProcessError as e:
        log(f"❌ [{name}] ошибка запуска туннеля: {e}")

def main():
    db_targets = load_json(DB_CONFIG)
    for db in db_targets:
        start_tunnel(
            name=db.get("name", "db"),
            local_port=db["port"],
            remote_host=db["remote_host"],
            remote_port=db["remote_port"],
            remote_user=db["user"]
        )

    repos = load_json(REPO_CONFIG)
    for repo in repos:
        start_tunnel(
            name=repo.get("name", "repo"),
            local_port=repo["port"],
            remote_host=repo["remote_host"],
            remote_port=repo["remote_port"],
            remote_user=repo["remote_user"]
        )

if __name__ == "__main__":
    log(f"📡 proxy.py — запуск туннелей (PROXY_MODE={PROXY_MODE or 'normal'})")
    main()
