FROM ubuntu:20.04

WORKDIR /vpn
ENV DEBIAN_FRONTEND=noninteractive

COPY requirements.txt ./
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl netcat openssh-client \
        python3 python3-pip openvpn gnupg iproute2 iputils-ping procps \
        socat postgresql-client git && \
    pip3 install --no-cache-dir -r requirements.txt && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/dial.py scripts/seal.py ./
COPY vpn_configs/ /vpn/vpn_configs/
COPY vpn_profiles/ /vpn/vpn_profiles/
COPY secrets/ /vpn/secrets/
COPY scripts/entrypoint.sh /vpn/entrypoint.sh

CMD ["bash", "/vpn/entrypoint.sh"]

# FROM ubuntu:20.04

# WORKDIR /vpn
# ENV DEBIAN_FRONTEND=noninteractive

# # === Установка системных пакетов и Python-зависимостей ===
# COPY requirements.txt ./
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     curl wget build-essential file python3 python3-pip gnupg \
#     iproute2 iputils-ping procps openvpn \
#     net-tools git dante-server proxychains gettext \
#     netcat openssh-client socat && \
#     pip3 install --no-cache-dir -r requirements.txt && \
#     rm -rf /var/lib/apt/lists/*

# # === Копирование скриптов ===
# COPY scripts/dial.py scripts/seal.py ./
# COPY scripts/diag.sh ./

# # Конфигурация Dante SOCKS5
# COPY danted.template.conf /vpn/danted.template.conf

# # Proxychains конфиг
# RUN echo "socks5 127.0.0.1 1080" >> /etc/proxychains.conf

# # === Команда по умолчанию ===
# #CMD ["python3", "dial.py"]
# COPY scripts/entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh
# ENTRYPOINT ["/entrypoint.sh"]
