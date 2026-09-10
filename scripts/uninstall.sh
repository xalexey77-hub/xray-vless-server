#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="xray-vless.service"
XRAY_DIR="/usr/local/etc/xray"
DATA_DIR="/etc/xray-vless"

[[ $EUID -eq 0 ]] || { echo "Запустите: sudo ./scripts/uninstall.sh" >&2; exit 1; }

read -r -p "Удалить Xray VLESS сервер и его конфигурацию? [yes/NO]: " answer
[[ "$answer" == "yes" ]] || { echo "Отменено."; exit 0; }

systemctl disable --now "$SERVICE" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE}"
systemctl daemon-reload
rm -rf "$XRAY_DIR" "$DATA_DIR"
rm -f /usr/local/bin/xray /usr/local/bin/xray-rm.sh /usr/local/etc/systemd/system/xray.service

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw delete allow 443/tcp >/dev/null 2>&1 || true
fi

echo "Xray VLESS server удалён."
echo "Пакеты apt (curl, jq, openssl, python3) намеренно не удаляются."
