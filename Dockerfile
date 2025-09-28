FROM ubuntu:20.04

WORKDIR /vpn
ENV DEBIAN_FRONTEND=noninteractive

# === Обновление и установка системных пакетов ===
RUN apt-get update && apt-get install -y \
    curl wget build-essential file python3 python3-pip gnupg \
    iproute2 iputils-ping procps \
    && rm -rf /var/lib/apt/lists/*

# === Установка Python-зависимостей ===
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

# === Копирование скриптов ===
COPY dial.py seal.py vpn-diag.sh ./
RUN chmod +x /vpn/vpn-diag.sh

# === Копирование локального архива SoftEther (fallback) ===
COPY build/softether-vpnclient.tar.gz /vpn/softether-vpnclient-local.tar.gz

# === Попытка скачать SoftEther VPN Client, иначе fallback ===
RUN wget --quiet -O softether-vpnclient.tar.gz \
      "https://www.softether-download.com/files/softether/v4.43-9799-rtm-2023.09.29-tree/Linux/SoftEther_VPN_Client/64bit_-_Ubuntu/softether-vpnclient.tar.gz" \
    || cp softether-vpnclient-local.tar.gz softether-vpnclient.tar.gz

# === Проверка архива и сборка SoftEther VPN Client ===
RUN file softether-vpnclient.tar.gz | grep -q 'gzip compressed data' \
    && tar xzf softether-vpnclient.tar.gz \
    && cd vpnclient \
    && yes 1 | make

# === Установка команды по умолчанию ===
#CMD ["python3", "/vpn/dial.py"]
CMD ["sleep", "infinity"]

