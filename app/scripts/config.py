from pydantic_settings import BaseSettings
from dotenv import load_dotenv

class Settings(BaseSettings):
    IMAGE_NAME: str = "access2work"
    CONTAINER_NAME: str = "access2work_container"

    # WORKDIR: str = "/app"
    # LOG_DIR: str = "/logs"
    # VPN_DIR: str = "/vpn"
    # DATA_DIR: str = "/data"

    MAX_RETRIES: int = 5
    OTP_VALIDITY: int = 30
    VPN_CONFIG: str = "/vpn/config/vpn.js"
    VPN_PROFILE_DIR: str = "/vpn/vpn"
    VPN_SECRET_DIR: str = "/vpn/secrets"
    GPG_PASSPHRASE: str = "your-secret-passphrase"
    SEAL_MODE: str = "normal"
    STOP_ON_FAILURE: bool = True
    VPN_CONNECT_DELAY: int = 15
    OPENVPN_RETRY: str = "1"
    OPENVPN_RETRY_DELAY: str = "2"
    HOSTS_DIR: str = "/etc/hosts"

    ENABLE_LOG: bool = True
    LOG_PATH: str = "/vpn/logs/connect.log"
    SEAL_LOG_PATH: str = "/vpn/logs/seal.log"
    FALLBACK_LOG: str = "/vpn/logs/fallback.log"

    DB_CONFIG: str = "/vpn/config/db_targets.json"
    EXTRA_HOSTS_CONFIG: str = "/vpn/config/extra_hosts.txt"
    # SITES_CONFIG: str = "sites.json"
    GITLAB_HOST: str = "gitlab.tektorg.ru"
    GIT_PROXY_PORT: int = 2222

    class Config:
        env_file = ".env"

settings = Settings()
