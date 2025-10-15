#!/bin/bash
set -e

# Проверка зависимостей
command -v socat >/dev/null || { echo "❌ socat не установлен"; exit 1; }

# Подключение к VPN
python3 /vpn/dial.py

# Используем переменные из .env
GIT_PORT="${GIT_PROXY_PORT:-2222}"
PG_PORT_FUTURE="${PG_PROXY_PORT_FUTURE:-15340}"
PG_PORT_STAGE="${PG_PROXY_PORT_STAGE:-25340}"
GIT_DEFAULT="${GITLAB:-gitlab.tektorg.ru:22}"
STAGE_DEFAULT="${PG_STAGE:-10.101.32.8:5340}"
FUTURE_DEFAULT="${PG_FUTURE:-10.101.32.39:5340}"


# TCP-прокси
echo "🔁 Git proxy: localhost:$GIT_PORT → $GIT_DEFAULT"
socat -v TCP-LISTEN:"$GIT_PORT",fork TCP:"$GIT_DEFAULT" &

echo "🔁 PG future: localhost:$PG_PORT_FUTURE → $FUTURE_DEFAULT"
socat -v TCP-LISTEN:"$PG_PORT_FUTURE",fork TCP:"$FUTURE_DEFAULT" &

echo "🔁 PG stage : localhost:$PG_PORT_STAGE → $STAGE_DEFAULT"
socat -v TCP-LISTEN:"$PG_PORT_STAGE",fork TCP:"$STAGE_DEFAULT" &

echo "✅ TCP-прокси запущены: Git ($GIT_PORT), PostgreSQL ($PG_PORT_FUTURE, $PG_PORT_STAGE)"
tail -f /dev/null
