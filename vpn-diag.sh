#!/bin/sh
echo "🧪 VPN диагностика — $(date)"

echo "\n🌍 Внешний IP:"
curl -s https://ifconfig.me || echo "❌ curl не сработал"

echo "\n📡 Интерфейсы:"
ip addr show || echo "❌ ip addr не сработал"

echo "\n🧭 Маршруты:"
ip route show || echo "❌ ip route не сработал"

echo "\n🔌 Интерфейс tun0:"
ip addr show dev tun0 || echo "❌ tun0 не найден"

echo "\n📋 Процесс OpenVPN:"
ps -ef | grep openvpn | grep -v grep || echo "❌ openvpn не запущен"
