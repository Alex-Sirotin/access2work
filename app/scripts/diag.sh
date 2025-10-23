#!/bin/bash

echo "🧪 Диагностика — $(date)"

# Счётчики
db_total=0; db_sql_ok=0; db_remote_ok=0; db_local_ok=0
repo_total=0; repo_remote_ok=0; repo_local_ok=0

# 🔧 Утилиты
echo -e "\n🔧 Утилиты:"
for cmd in nc psql openvpn; do
    command -v $cmd >/dev/null && echo "✅ $cmd" || echo "❌ $cmd"
done

# 📡 Сеть
echo -e "\n📡 Сеть:"
ip -brief address || echo "❌ ip addr"
ip route show || echo "❌ ip route"
ip link show | grep tun || echo "❌ tun не найден"

echo "🔑 ENV: DB_CONFIG=$DB_CONFIG, REPO_CONFIG=$REPO_CONFIG"

if [[ $(jq length "$DB_CONFIG") -eq 0 ]]; then
    echo "⚠️ [$DB_CONFIG] пустой или не содержит массив"
fi

if [[ $(jq length "$REPO_CONFIG") -eq 0 ]]; then
    echo "⚠️ [$REPO_CONFIG] пустой или не содержит массив"
fi

# 🧪 Базы данных
[[ -f "$DB_CONFIG" ]] || { echo "❌ Нет $DB_CONFIG"; exit 1; }
jq -c '.[]' "$DB_CONFIG" | while read -r db; do
    ((db_total++))
    rhost=$(echo "$db" | jq -r '.remote_host')
    rport=$(echo "$db" | jq -r '.remote_port')
    lport=$(echo "$db" | jq -r '.port')
    dbname=$(echo "$db" | jq -r '.database')
    user=$(echo "$db" | jq -r '.user')
    pass=$(echo "$db" | jq -r '.password')

    nc -z "$rhost" "$rport" && ((db_remote_ok++))
    nc -z localhost "$lport" && ((db_local_ok++))

    if [[ -n "$pass" && "$pass" != "null" ]]; then
        export PGPASSWORD="$pass"
        psql -h "$rhost" -p "$rport" -U "$user" -d "$dbname" -c "SELECT 1;" >/dev/null 2>&1 && ((db_sql_ok++))
    fi
done

# 🧪 Репозитории
[[ -f "$REPO_CONFIG" ]] || { echo "❌ Нет $REPO_CONFIG"; exit 1; }
jq -c '.[]' "$REPO_CONFIG" | while read -r repo; do
    ((repo_total++))
    rhost=$(echo "$repo" | jq -r '.remote_host')
    rport=$(echo "$repo" | jq -r '.remote_port')
    lport=$(echo "$repo" | jq -r '.port')

    nc -z "$rhost" "$rport" && ((repo_remote_ok++))
    nc -z localhost "$lport" && ((repo_local_ok++))
done

# 📊 Сводка
echo -e "\n📊 Сводка:"
printf "📦 БД: %d/%d SQL | %d удалённых | %d локальных\n" "$db_sql_ok" "$db_total" "$db_remote_ok" "$db_local_ok"
printf "📁 Репо: %d/%d удалённых | %d локальных\n" "$repo_remote_ok" "$repo_total" "$repo_local_ok"
