FROM ubuntu:20.04

WORKDIR /vpn
ENV DEBIAN_FRONTEND=noninteractive

COPY requirements.txt ./
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl netcat openssh-client \
        python3 python3-pip openvpn gnupg iproute2 iputils-ping procps \
        rinetd postgresql-client git jq && \
    pip3 install --no-cache-dir -r requirements.txt && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/dial.py scripts/seal.py scripts/diag.sh ./
COPY vpn_configs/ /vpn/vpn_configs/
COPY vpn_profiles/ /vpn/vpn_profiles/
COPY secrets/ /vpn/secrets/
COPY scripts/entrypoint.sh /vpn/entrypoint.sh

CMD ["bash", "/vpn/entrypoint.sh"]
