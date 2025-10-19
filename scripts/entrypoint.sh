#!/bin/bash
set -e

echo "🔒 Запуск VPN (dial.py)"
echo "🔒 Запуск VPN (dial.py)" >> "$LOG_PATH"
python3 /vpn/dial.py
rc=$?
if [ $rc -ne 0 ]; then
  echo "⚠️ dial.py завершился с ошибкой: код $rc" | tee -a "$LOG_PATH"
  exit $rc
fi
echo "✅ dial.py завершился успешно" >> "$LOG_PATH"

if [ -d /root/ssh ]; then
    echo "🔑 Настройка SSH-ключей из /root/ssh" >> "$LOG_PATH"
    cp -r /root/ssh /root/.ssh
    chown -R root:root /root/.ssh
    chmod 600 /root/.ssh/* || true
    chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts* || true

    echo "📁 Содержимое /root/.ssh:" >> "$LOG_PATH"
    ls -l /root/.ssh >> "$LOG_PATH"
fi

echo "📄 Генерация haproxy.cfg через proxy.py"
echo "📄 Генерация haproxy.cfg через proxy.py" >> "$LOG_PATH"
python3 /vpn/proxy.py

echo "📄 haproxy.cfg:" >> "$LOG_PATH"
cat "$HAPROXY_CFG" >> "$LOG_PATH"

echo "✅ HAProxy запущен — контейнер активен"
echo "✅ HAProxy запущен — контейнер активен" >> "$LOG_PATH"
exec haproxy -f "$HAPROXY_CFG"
