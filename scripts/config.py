from pydantic_settings import BaseSettings
from dotenv import load_dotenv

class Settings(BaseSettings):
    IMAGE_NAME: str = "access2work"
    CONTAINER_NAME: str = "access2work_container"

    MAX_RETRIES: int = 5
    OTP_VALIDITY: int = 30
    VPN_CONFIG_DIR: str = "/vpn/vpn_configs"
    VPN_PROFILE_DIR: str = "/vpn/vpn_profiles"
    VPN_SECRET_DIR: str = "/vpn/secrets"
    GPG_PASSPHRASE: str = "your-secret-passphrase"
    SEAL_MODE: str = "normal"
    STOP_ON_FAILURE: bool = True
    VPN_CONNECT_DELAY: int = 15
    OPENVPN_RETRY: str = "1"
    OPENVPN_RETRY_DELAY: str = "2"
    HOSTS_DIR: str = "/etc/hosts"

    ENABLE_LOG: bool = True
    LOG_PATH: str = "/vpn/secrets/vpn_connect.log"
    SEAL_LOG_PATH: str = "/vpn/secrets/vpn_seal.log"
    FALLBACK_LOG: str = "/vpn/secrets/fallback.log"

    DB_CONFIG: str = "/vpn/db_targets.json"    
    SITES_CONFIG: str = "/vpn/sites.json"
    HAPROXY_CFG: str = "/etc/haproxy/haproxy.cfg"
    GITLAB_HOST: str = "gitlab.tektorg.ru"
    GIT_PROXY_PORT: int = 2222

    class Config:
        env_file = ".env"

settings = Settings()
