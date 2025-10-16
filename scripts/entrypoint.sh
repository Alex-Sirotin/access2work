#!/bin/bash
set -e

echo "🔒 Запуск VPN (dial.py)"
python3 /vpn/dial.py > /vpn/secrets/dial.log 2>&1 || echo "⚠️ dial.py завершился с ошибкой"

# Используем переменные из .env
GIT_PORT="${GIT_PROXY_PORT:-2222}"
PG_PORT_FUTURE="${PG_PROXY_PORT_FUTURE:-15340}"
PG_PORT_STAGE="${PG_PROXY_PORT_STAGE:-25340}"
GIT_DEFAULT="${GITLAB:-gitlab.tektorg.ru:22}"
STAGE_DEFAULT="${PG_STAGE:-10.101.32.8:5340}"
FUTURE_DEFAULT="${PG_FUTURE:-10.101.32.39:5340}"

# Генерация rinetd.conf
cat <<EOF > /etc/rinetd.conf
0.0.0.0 $GIT_PORT ${GIT_DEFAULT/:/ } 
0.0.0.0 $PG_PORT_FUTURE ${FUTURE_DEFAULT/:/ } 
0.0.0.0 $PG_PORT_STAGE ${STAGE_DEFAULT/:/ } 
EOF

echo "📄 rinetd.conf:"
cat /etc/rinetd.conf

echo "🔁 Запуск rinetd в foreground-режиме"
rinetd -f -c /etc/rinetd.conf > /vpn/secrets/rinetd.log 2>&1 &
RINETD_PID=$!

# Проверка, что rinetd действительно запустился
sleep 1
if ! ps -p $RINETD_PID > /dev/null; then
    echo "❌ rinetd завершился сразу — возможно, ошибка в конфиге или занятый порт"
    cat /vpn/secrets/rinetd.log
    exit 1
fi

echo "✅ TCP-прокси запущены: Git ($GIT_PORT), PostgreSQL ($PG_PORT_FUTURE, $PG_PORT_STAGE)"

# Удержание контейнера, пока работает rinetd
wait $RINETD_PID

echo "🛑 rinetd завершился — остановка контейнера"
