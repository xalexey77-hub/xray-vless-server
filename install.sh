#!/usr/bin/env bash
set -Eeuo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
DATA_DIR="/etc/xray-vless"
CONFIG="${XRAY_DIR}/config.json"
ENV_FILE="${DATA_DIR}/server.env"
CLIENT_FILE="${DATA_DIR}/client.json"
SERVICE="xray.service"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запустите скрипт от root: sudo bash install.sh"
command -v apt-get >/dev/null || die "Поддерживается Ubuntu/Debian с apt-get."

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  die "Не удалось определить ОС."
fi

[[ "${ID:-}" == "ubuntu" ]] || warn "ОС определена как ${PRETTY_NAME:-unknown}; скрипт рассчитан прежде всего на Ubuntu."

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
case "$ARCH" in
  amd64|arm64) ;;
  *) die "Архитектура $ARCH пока не поддерживается этим установщиком." ;;
esac

log "Установка зависимостей"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates openssl jq python3

if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)443$|\]:443$'; then
  die "TCP/443 уже занят. Освободите порт 443 или остановите сервис, который его использует."
fi

log "Установка Xray из официального установщика"
if [[ ! -x "$XRAY_BIN" ]] || [[ ! -f /etc/systemd/system/xray.service ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$tmp"
  bash "$tmp" install -u nobody
  rm -f "$tmp"
  trap - EXIT
fi

[[ -x "$XRAY_BIN" ]] || die "Xray не установлен в $XRAY_BIN"
[[ -f /etc/systemd/system/xray.service ]] || die "Официальный systemd unit xray.service не найден."

# Disable the old custom unit if it exists. The official installer/service is used.
if systemctl cat xray-vless.service >/dev/null 2>&1; then
  log "Отключение старого xray-vless.service"
  systemctl disable --now xray-vless.service 2>/dev/null || true
fi

log "Настройка параметров сервера"
read -r -p "REALITY serverName [www.google.com]: " SERVER_NAME
SERVER_NAME="${SERVER_NAME:-www.google.com}"

read -r -p "REALITY destination [${SERVER_NAME}:443]: " DEST
DEST="${DEST:-${SERVER_NAME}:443}"

read -r -p "XHTTP path [/xhttp]: " XHTTP_PATH
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
[[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/$XHTTP_PATH"

UUID="$($XRAY_BIN uuid)"
[[ -n "$UUID" ]] || die "Не удалось сгенерировать UUID"

KEY_OUTPUT="$($XRAY_BIN x25519 2>&1)" || die "Не удалось сгенерировать REALITY key pair: $KEY_OUTPUT"
PRIVATE_KEY="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PrivateKey: //p' | head -n1)"
PUBLIC_KEY="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^Password (PublicKey): //p' | head -n1)"

# Compatibility with Xray versions that print a plain PublicKey/Password label.
[[ -n "$PRIVATE_KEY" ]] || PRIVATE_KEY="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^Private Key: //p' | head -n1)"
[[ -n "$PUBLIC_KEY" ]] || PUBLIC_KEY="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PublicKey: //p' | head -n1)"
[[ -n "$PUBLIC_KEY" ]] || PUBLIC_KEY="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^Password: //p' | head -n1)"

[[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "Не удалось разобрать вывод 'xray x25519': $KEY_OUTPUT"

SHORT_ID="$(openssl rand -hex 8)"

install -d -m 0755 "$XRAY_DIR" "$DATA_DIR"

cat > "$CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "email": "main"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "${XHTTP_PATH}",
          "mode": "auto"
        },
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# The official xray.service runs as nobody:nogroup, so it must be able to read config.json.
chown root:nogroup "$CONFIG" 2>/dev/null || chown root:root "$CONFIG"
chmod 640 "$CONFIG"

cat > "$ENV_FILE" <<EOF
UUID=${UUID}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
SERVER_NAME=${SERVER_NAME}
DEST=${DEST}
XHTTP_PATH=${XHTTP_PATH}
EOF
chmod 600 "$ENV_FILE"

cat > "$CLIENT_FILE" <<EOF
{
  "protocol": "vless",
  "address": "YOUR_SERVER_IP",
  "port": 443,
  "id": "${UUID}",
  "encryption": "none",
  "security": "reality",
  "serverName": "${SERVER_NAME}",
  "fingerprint": "chrome",
  "publicKey": "${PUBLIC_KEY}",
  "shortId": "${SHORT_ID}",
  "network": "xhttp",
  "xhttpPath": "${XHTTP_PATH}",
  "xhttpMode": "auto"
}
EOF
chmod 600 "$CLIENT_FILE"

log "Проверка конфигурации Xray"
"$XRAY_BIN" run -test -config "$CONFIG"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  log "Открытие TCP/443 в UFW"
  ufw allow 443/tcp >/dev/null
fi

systemctl daemon-reload
systemctl enable --now "$SERVICE"
sleep 2

if ! systemctl is-active --quiet "$SERVICE"; then
  systemctl --no-pager --full status "$SERVICE" || true
  die "Xray не запустился."
fi

SERVER_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"

VLESS_URI="vless://${UUID}@${SERVER_IP}:443?encryption=none&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$XHTTP_PATH")&mode=auto#Xray-XHTTP-REALITY"

printf '%s\n' "$VLESS_URI" > "${DATA_DIR}/client.txt"
chmod 600 "${DATA_DIR}/client.txt"

cat > "${DATA_DIR}/client.json" <<EOF
{
  "protocol": "vless",
  "address": "${SERVER_IP}",
  "port": 443,
  "id": "${UUID}",
  "encryption": "none",
  "security": "reality",
  "serverName": "${SERVER_NAME}",
  "fingerprint": "chrome",
  "publicKey": "${PUBLIC_KEY}",
  "shortId": "${SHORT_ID}",
  "network": "xhttp",
  "xhttpPath": "${XHTTP_PATH}",
  "xhttpMode": "auto"
}
EOF
chmod 600 "${DATA_DIR}/client.json"

echo
echo "=============================================="
echo " Xray VLESS + XHTTP + REALITY установлен"
echo "=============================================="
echo "Service : ${SERVICE}"
echo "Config  : ${CONFIG}"
echo "Secrets : ${ENV_FILE}"
echo ""
echo "UUID       : ${UUID}"
echo "PublicKey  : ${PUBLIC_KEY}"
echo "ShortID    : ${SHORT_ID}"
echo "ServerName : ${SERVER_NAME}"
echo "XHTTP path : ${XHTTP_PATH}"
echo ""
echo "VLESS URL:"
echo "${VLESS_URI}"
echo ""
echo "Скопируйте VLESS URL в клиент Xray/sing-box, поддерживающий XHTTP + REALITY."
echo "После установки: sudo bash scripts/status.sh"
