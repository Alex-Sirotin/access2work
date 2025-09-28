#!/bin/sh

LOG="/vpn/secrets/vpn_diag.log"
VPNCMD="/vpn/vpnclient/vpncmd"
echo "🧪 VPN диагностика — $(date)" > "$LOG"

log() {
  echo "$1" | tee -a "$LOG"
}

log "\n🔍 Проверка vpnclient:"
$VPNCMD localhost /CLIENT /CMD AccountList >> "$LOG" 2>&1 || log "❌ AccountList не выполнен"

log "\n🔌 Проверка подключения аккаунта:"
for profile in /vpn/vpn_profiles/*.vpn; do
  name=$(basename "$profile" .vpn)
  log "\n➡️ $name:"
  $VPNCMD localhost /CLIENT /CMD AccountStatusGet "$name" >> "$LOG" 2>&1 || log "❌ AccountStatusGet $name не выполнен"
done

log "\n🌐 Проверка DNS и ping:"
ping -c 3 google.com >> "$LOG" 2>&1 || log "❌ ping google.com не прошёл"

log "\n📡 Проверка сетевых интерфейсов:"
ip link show >> "$LOG" 2>&1
ip addr show >> "$LOG" 2>&1
ip route show >> "$LOG" 2>&1

log "\n🌍 Проверка внешнего IP:"
curl -s https://api.ipify.org >> "$LOG" 2>&1 || log "❌ curl ipify не сработал"

log "\n📄 Содержимое vpn_profiles:"
ls -lh /vpn/vpn_profiles >> "$LOG" 2>&1

log "\n📄 Содержимое vpn_configs:"
ls -lh /vpn/vpn_configs >> "$LOG" 2>&1

log "\n📄 Содержимое secrets:"
ls -lh /vpn/secrets >> "$LOG" 2>&1

log "\n✅ Диагностика завершена"
