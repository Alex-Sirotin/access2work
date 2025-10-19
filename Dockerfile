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
        haproxy \
        postgresql-client \
        git \
        jq \
        ssh && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /vpn

COPY scripts/requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

COPY scripts/ ./
COPY vpn_configs/ vpn_profiles/ secrets/ ./

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD bash /vpn/healthcheck.sh

RUN chmod +x ./entrypoint.sh
CMD ["/vpn/entrypoint.sh"]
