#!/bin/bash
set -e

echo "🔒 Запуск VPN (dial.py)"
echo "🔒 Запуск VPN (dial.py)" >> "$LOG_PATH"
python3 "/vpn/scripts/dial.py"
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

echo "📡 Запуск proxy.py (autossh-туннели)"
echo "📡 Запуск proxy.py (autossh-туннели)" >> "$LOG_PATH"
python3 /vpn/scripts/proxy.py
rc=$?
if [ $rc -ne 0 ]; then
  echo "⚠️ proxy.py завершился с ошибкой: код $rc"
  echo "⚠️ proxy.py завершился с ошибкой: код $rc" >> "$LOG_PATH"
else
  echo "✅ proxy.py завершился успешно"
  echo "✅ proxy.py завершился успешно" >> "$LOG_PATH"
fi

echo "⏸ Контейнер запущен, ожидание остановки..."
echo "⏸ Контейнер запущен, ожидание остановки..." >> "$LOG_PATH"
tail -f /dev/null
