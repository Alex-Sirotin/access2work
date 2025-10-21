#!/bin/bash
set -e

echo "🧪 Диагностика — $(date)"

# Загрузка переменных из .env
source /vpn/.env 2>/dev/null || echo "⚠️ .env не найден или не загружен"

# Проверка базовых утилит
echo -e "\n🔧 Проверка утилит:"
for cmd in nc psql rinetd openvpn; do
    command -v $cmd >/dev/null && echo "✅ $cmd установлен" || echo "❌ $cmd не найден"
done

# Интерфейсы и маршруты
echo -e "\n📡 Интерфейсы:"
ip -brief address || echo "❌ ip addr не сработал"

echo -e "\n🧭 Маршруты:"
ip route show || echo "❌ ip route не сработал"

# VPN-интерфейсы
echo -e "\n🔒 VPN-интерфейсы:"
ip link show | grep tun || echo "❌ tun-интерфейс не найден"

echo -e "\n🧪 Проверка PostgreSQL-баз из db_targets.json"

if [[ ! -f "$DB_CONFIG" ]]; then
    echo "❌ Конфигурация БД не найдена: $DB_CONFIG"
    exit 1
fi

jq -c '.[]' "$DB_CONFIG" | while read -r db; do
    name=$(echo "$db" | jq -r '.name')
    host=$(echo "$db" | jq -r '.remote_host')
    port=$(echo "$db" | jq -r '.remote_port')
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

# # Проверка Jira
# echo -e "\n🔍 Jira:"
# if wget --no-check-certificate --timeout=5 --tries=1 https://jira.tektorg.ru -O /dev/null >/dev/null 2>&1; then
#     echo "✅ Jira доступна"
# else
#     echo "❌ Jira недоступна"
# fi

# # Проверка GitLab
# echo -e "\n🔍 GitLab TCP-порт 443:"
# if nc -z -w 3 gitlab.tektorg.ru 443; then
#     echo "✅ GitLab TCP-порт 443 доступен"
# else
#     echo "❌ GitLab TCP-порт 443 недоступен"
# fi
