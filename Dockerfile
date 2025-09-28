FROM ubuntu:20.04

WORKDIR /vpn
ENV DEBIAN_FRONTEND=noninteractive

# === Установка системных пакетов и Python-зависимостей ===
COPY requirements.txt ./
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl wget build-essential file python3 python3-pip gnupg \
        iproute2 iputils-ping procps openvpn && \
    pip3 install --no-cache-dir -r requirements.txt && \
    rm -rf /var/lib/apt/lists/*

# === Копирование скриптов ===
COPY dial.py seal.py vpn-diag.sh ./
RUN chmod +x vpn-diag.sh

# === Команда по умолчанию ===
CMD ["python3", "dial.py"]
