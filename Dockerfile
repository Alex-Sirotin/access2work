FROM ubuntu:20.04

WORKDIR /vpn
ENV DEBIAN_FRONTEND=noninteractive

# === Обновление и установка системных пакетов ===
RUN apt-get update && apt-get install -y \
    curl wget build-essential file python3 python3-pip gnupg \
    iproute2 iputils-ping procps openvpn \
    && rm -rf /var/lib/apt/lists/*

# === Установка Python-зависимостей ===
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

# === Копирование скриптов ===
COPY dial.py seal.py vpn-diag.sh ./
RUN chmod +x /vpn/vpn-diag.sh

# === Установка команды по умолчанию ===
CMD ["python3", "/vpn/dial.py"]
