#!/usr/bin/env python3
import json
import os
import sys
import socket

from config import settings

HAPROXY_CFG = settings.HAPROXY_CFG
DB_CONFIG = settings.DB_CONFIG
GITLAB_HOST = settings.GITLAB_HOST
GIT_PROXY_PORT = settings.GIT_PROXY_PORT
SITES_CONFIG = settings.SITES_CONFIG

def is_port_open(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False

config = [
    "global",
    "    log stdout format raw daemon",
    "",
    "defaults",
    "    log     global",
    "    option tcplog",
    "    mode    tcp",
    "    timeout connect 5s",
    "    timeout client  30s",
    "    timeout server  30s",
    ""
]

# GitLab SSH
if GIT_PROXY_PORT and GITLAB_HOST:
    config += [
        f"frontend gitlab_ssh",
        f"    bind *:{GIT_PROXY_PORT}",
        f"    default_backend gitlab_ssh_backend",
        "",
        f"backend gitlab_ssh_backend",
        f"    server gitlab {GITLAB_HOST} ",
        ""
    ]

# PostgreSQL
if os.path.exists(DB_CONFIG):
    with open(DB_CONFIG) as f:
        for db in json.load(f):
            name = db.get("name")
            remote_host = db.get("remote_host")
            remote_port = db.get("remote_port")
            port = db.get("port")
            if not (name and remote_host and remote_port and port):
                continue
            config += [
                f"frontend {name}_pg",
                f"    bind *:{port}",
                f"    default_backend {name}_pg_backend",
                "",
                f"backend {name}_pg_backend",
                f"    server {name}_pg {remote_host}:{remote_port} ",
                ""
            ]
         
if os.path.exists(SITES_CONFIG):
    with open(SITES_CONFIG) as f:
        sites = json.load(f)

http_acls = []
http_use = []
https_use = []
backends = []

for site in sites:
    name = site["name"]
    host = site["host"]
    port = site.get("port")

    if port:
        # нестандартный порт — отдельный фронтенд
        ...
    else:
        if host.startswith("*."):
            domain = host[2:]
            # HTTP
            if is_port_open(host, 80):
                http_acls.append(f"    acl host_{name} hdr(host) -m end {domain}")
                http_use.append(f"    use_backend {name}_http_be if host_{name}")
                backends += [
                    f"backend {name}_http_be",
                    "    mode http",
                    f"    server {name} {domain}:80 ",
                    ""
                ]
            else:
                print(f"⚠️ HTTP порт 80 недоступен для {host} — backend {name}_http_be не будет добавлен")
            # HTTPS
            # if is_port_open(host, 443):
                https_use.append(f"    use_backend {name}_https_be if {{ req.ssl_sni -m end {domain} }}")
                backends += [
                    f"backend {name}_https_be",
                    "    mode tcp",
                    f"    server {name} {domain}:443 ",
                    ""
                ]
            # else:
            #     print(f"⚠️ HTTP порт 443 недоступен для {host} — backend {name}_https_be не будет добавлен")
        else:
            # обычный точный хост
            if is_port_open(host, 80):
                http_acls.append(f"    acl host_{name} hdr(host) -i {host}")
                http_use.append(f"    use_backend {name}_http_be if host_{name}")
                backends += [
                    f"backend {name}_http_be",
                    "    mode http",
                    f"    server {name} {host}:80 ",
                    ""
                ]
            else:
                print(f"⚠️ HTTP порт 80 недоступен для {host} — backend {name}_http_be не будет добавлен")

            # if is_port_open(host, 443):
                https_use.append(f"    use_backend {name}_https_be if {{ req.ssl_sni -i {host} }}")
                backends += [
                    f"backend {name}_https_be",
                    "    mode tcp",
                    f"    server {name} {host}:443 ",
                    ""
                ]
            # else:
            #     print(f"⚠️ HTTP порт 443 недоступен для {host} — backend {name}_https_be не будет добавлен")

# Добавляем фронтенды для http/https
config += [
    "frontend http_in",
    "    bind *:80",
    "    mode http",
    *http_acls,
    *http_use,
    "",
    "frontend https_in",
    "    bind *:443",
    "    mode tcp",
    "    tcp-request inspect-delay 5s",
    "    tcp-request content accept if { req.ssl_hello_type 1 }",
    *https_use,
    "    default_backend reject_https",
    "",
    "backend reject_https",
    "    mode tcp",
    "    tcp-request content reject",
    ""
]

# Добавляем все backend'и
config += backends

config += [
    "frontend stats_in",
    "   bind *:9100",
    "   mode http",
    "   stats enable",
    "   stats uri /haproxy_stats",
    "   stats realm Haproxy\ Statistics",
    "   stats auth admin:password",
    ""
]

# Запись в haproxy.cfg
try:
    with open(HAPROXY_CFG, "w") as f:
        f.write("\n".join(config))
    print(f"✅ haproxy.cfg сгенерирован: {HAPROXY_CFG}")
except Exception as e:
    print(f"❌ Не удалось записать {HAPROXY_CFG}: {e}", file=sys.stderr)
    sys.exit(1)
