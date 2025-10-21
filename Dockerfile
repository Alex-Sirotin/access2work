FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        netcat \
        python3 \
        python3-pip \
        openvpn \
        gnupg \
        iproute2 \
        iputils-ping \
        procps \
        postgresql-client \
        git \
        jq \
        ssh && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /vpn

# Устанавливаем Python-зависимости
COPY app/scripts/requirements.txt ./scripts/
RUN pip3 install --no-cache-dir -r ./scripts/requirements.txt

COPY app/scripts ./scripts/
COPY app/config ./config/
COPY app/vpn ./vpn/

# Healthcheck
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD bash ./scripts/healthcheck.sh

# Entrypoint
RUN chmod +x ./scripts/*.sh
CMD ["/vpn/scripts/entrypoint.sh"]
