#!/bin/bash
echo "🧪 Диагностика — $(date)"

command -v nc >/dev/null || echo "❌ nc не установлен"
command -v ssh >/dev/null || echo "❌ ssh не установлен"
command -v openvpn >/dev/null || echo "❌ openvpn не установлен"

echo -e "\n🌍 Внешний IP:"
curl -s https://ifconfig.me || echo "❌ curl не сработал"

echo -e "\n📡 Интерфейсы:"
ip addr show || echo "❌ ip addr не сработал"

echo -e "\n🧭 Маршруты:"
ip route show || echo "❌ ip route не сработал"

echo -e "\n🔌 Интерфейс tun0:"
ip addr show dev tun0 || echo "❌ tun0 не найден"

echo -e "\n📋 Процесс OpenVPN:"
ps -ef | grep openvpn | grep -v grep || echo "❌ openvpn не запущен"

echo -e "\n🧪 SOCKS5-прокси:"
nc -z localhost ${PROXY_PORT:-1080} && echo "✅ Прокси слушает" || echo "❌ Прокси не слушает"

echo -e "\n🌐 Доступность GitLab через прокси:"
curl --socks5-hostname localhost:${PROXY_PORT:-1080} https://gitlab.tektorg.ru -s -o /dev/null && echo "✅ GitLab доступен через VPN" || echo "❌ GitLab недоступен через VPN"

echo -e "\n🔐 Проверка SSH-доступа к GitLab:"
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o ProxyCommand="nc -x localhost:${PROXY_PORT:-1080} -X 5 %h %p" git@gitlab.tektorg.ru exit || echo "❌ SSH-доступ к GitLab не работает"
