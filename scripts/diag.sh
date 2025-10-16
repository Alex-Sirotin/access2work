#!/bin/bash
set -e

echo "🧪 Диагностика — $(date)"

# Загрузка переменных из .env
source /vpn/.env 2>/dev/null || echo "⚠️ .env не найден или не загружен"

# Проверка базовых утилит
echo -e "\n🔧 Проверка утилит:"
for cmd in curl nc psql rinetd openvpn; do
    command -v $cmd >/dev/null && echo "✅ $cmd установлен" || echo "❌ $cmd не найден"
done

# Внешний IP
echo -e "\n🌍 Внешний IP через VPN:"
curl -s https://ifconfig.me || echo "❌ curl не сработал"

# Интерфейсы и маршруты
echo -e "\n📡 Интерфейсы:"
ip -brief address || echo "❌ ip addr не сработал"

echo -e "\n🧭 Маршруты:"
ip route show || echo "❌ ip route не сработал"

# VPN-интерфейсы
echo -e "\n🔒 VPN-интерфейсы:"
ip link show | grep tun || echo "❌ tun-интерфейс не найден"

# rinetd
echo -e "\n📋 Конфигурация rinetd:"
cat /etc/rinetd.conf || echo "❌ rinetd.conf не найден"

echo -e "\n📡 Слушающие порты rinetd:"
ss -tnlp | grep rinetd || echo "❌ rinetd не слушает"

echo -e "\n🧪 Проверка PostgreSQL-баз из db_targets.json"

DB_CONFIG="/vpn/vpn_configs/db_targets.json"

if [[ ! -f "$DB_CONFIG" ]]; then
    echo "❌ Конфигурация БД не найдена: $DB_CONFIG"
    exit 1
fi

jq -c '.[]' "$DB_CONFIG" | while read -r db; do
    name=$(echo "$db" | jq -r '.name')
    host=$(echo "$db" | jq -r '.host // "localhost"')
    port=$(echo "$db" | jq -r '.port // 5432')
    database=$(echo "$db" | jq -r '.database')
    user=$(echo "$db" | jq -r '.user')
    password=$(echo "$db" | jq -r '.password')

    echo -e "\n🔍 [$name] Проверка подключения к $database@$host:$port"

    if [[ -z "$password" || "$password" == "null" ]]; then
        echo "❌ [$name] Пароль не задан в конфиге"
        continue
    fi

    export PGPASSWORD="$password"

    psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT 1;" \
        && echo "✅ [$name] Доступно" \
        || echo "❌ [$name] Недоступно"
done

# Jira
echo -e "\n🌐 Jira доступность:"
curl -s -I https://jira.tektorg.ru | head -n 1 | grep "200\|302" && echo "✅ Jira доступна" || echo "❌ Jira недоступна"

# Gitlab
echo -e "\n🌐 Gitlab доступность:"
curl -s -I https://gitlab.tektorg.ru | head -n 1 | grep "200\|302" && echo "✅ Gitlab доступен" || echo "❌ Gitlab недоступен"
