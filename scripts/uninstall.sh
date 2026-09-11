#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="xray.service"
LEGACY_SERVICE="xray-vless.service"
XRAY_DIR="/usr/local/etc/xray"
DATA_DIR="/etc/xray-vless"

[[ $EUID -eq 0 ]] || { echo "Запустите: sudo bash scripts/uninstall.sh" >&2; exit 1; }

read -r -p "Удалить Xray VLESS сервер и его конфигурацию? [yes/NO]: " answer
[[ "$answer" == "yes" ]] || { echo "Отменено."; exit 0; }

# Stop the current official unit and any legacy unit from older project versions.
systemctl disable --now "$SERVICE" 2>/dev/null || true
systemctl disable --now "$LEGACY_SERVICE" 2>/dev/null || true

# Remove only the legacy project-created unit. The official xray.service unit
# is removed by the official Xray uninstaller below.
rm -f "/etc/systemd/system/${LEGACY_SERVICE}"
systemctl daemon-reload

if [[ -x /usr/local/bin/xray-rm.sh ]]; then
  /usr/local/bin/xray-rm.sh || true
else
  rm -f /usr/local/bin/xray
  rm -f /etc/systemd/system/xray.service
  rm -f /usr/local/etc/systemd/system/xray.service
  systemctl daemon-reload
fi

rm -rf "$XRAY_DIR" "$DATA_DIR"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw delete allow 443/tcp >/dev/null 2>&1 || true
fi

echo "Xray VLESS server удалён."
echo "Пакеты apt (curl, jq, openssl, python3) намеренно не удаляются."
