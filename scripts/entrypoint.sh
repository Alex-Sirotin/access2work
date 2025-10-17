#!/bin/bash
set -e

echo "🔒 Запуск VPN (dial.py)"
python3 /vpn/dial.py > /vpn/secrets/dial.log 2>&1 || echo "⚠️ dial.py завершился с ошибкой"

# Путь к конфигу БД
DB_CONFIG="/vpn/db_targets.json"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
JIRA_PORT="443"
JIRA_HOST="jira.tektorg.ru"
GITLAB_HTTPS_PORT="443"
GITLAB_HOST="gitlab.tektorg.ru"

echo "📄 Генерация haproxy.cfg"
echo "global
    log stdout format raw daemon

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  30s
    timeout server  30s
" > "$HAPROXY_CFG"

# GitLab SSH
if [[ -n "$GIT_PROXY_PORT" && -n "$GITLAB" ]]; then
    echo "
frontend gitlab_ssh
    bind *:$GIT_PROXY_PORT
    default_backend gitlab_ssh_backend

backend gitlab_ssh_backend
    server gitlab ${GITLAB} check
" >> "$HAPROXY_CFG"
    echo "➕ GitLab SSH: $GIT_PROXY_PORT → $GITLAB"
fi

# PostgreSQL из db_targets.json
if [[ -f "$DB_CONFIG" ]]; then
    jq -c '.[]' "$DB_CONFIG" | while read -r db; do
        name=$(echo "$db" | jq -r '.name')
        remote_host=$(echo "$db" | jq -r '.remote_host')
        remote_port=$(echo "$db" | jq -r '.remote_port')
        port=$(echo "$db" | jq -r '.port')

        if [[ -z "$remote_host" || -z "$remote_port" || -z "$port" ]]; then
            echo "⚠️ [$name] Пропущен — неполные данные"
            continue
        fi

        echo "
frontend ${name}_pg
    bind *:$port
    default_backend ${name}_pg_backend

backend ${name}_pg_backend
    server ${name}_pg $remote_host:$remote_port check
" >> "$HAPROXY_CFG"
        echo "➕ [$name] PostgreSQL: $port → $remote_host:$remote_port"
    done
else
    echo "⚠️ Конфигурация БД не найдена: $DB_CONFIG"
fi

# HTTPS сайты (Jira, GitLab)
if [[ -n "$JIRA_PORT" && -n "$JIRA_HOST" ]]; then
    echo "
frontend jira_https
    bind *:$JIRA_PORT
    default_backend jira_backend

backend jira_backend
    server jira $JIRA_HOST:443 check
" >> "$HAPROXY_CFG"
    echo "➕ Jira HTTPS: $JIRA_PORT → $JIRA_HOST:443"
fi

if [[ -n "$GITLAB_HTTPS_PORT" && -n "$GITLAB_HOST" ]]; then
    echo "
frontend gitlab_https
    bind *:$GITLAB_HTTPS_PORT
    default_backend gitlab_backend

backend gitlab_backend
    server gitlab $GITLAB_HOST:443 check
" >> "$HAPROXY_CFG"
    echo "➕ GitLab HTTPS: $GITLAB_HTTPS_PORT → $GITLAB_HOST:443"
fi

echo "📄 haproxy.cfg:"
cat "$HAPROXY_CFG"

echo "✅ HAProxy запущен — контейнер активен"
exec haproxy -f /etc/haproxy/haproxy.cfg
