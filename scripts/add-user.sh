#!/usr/bin/env bash
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
CONFIG="/usr/local/etc/xray/config.json"
DATA_DIR="/etc/xray-vless"
USERS_DIR="$DATA_DIR/users"
PORT=443

usage() {
  echo "Usage: sudo $0 <username>"
  echo "Example: sudo $0 friend1"
  exit 1
}

[[ $# -eq 1 ]] || usage
NAME="$1"

if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: username may contain only A-Z, a-z, 0-9, dot, underscore and dash." >&2
  exit 1
fi

[[ -x "$XRAY_BIN" ]] || { echo "ERROR: Xray not found: $XRAY_BIN" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "ERROR: config not found: $CONFIG" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl is required." >&2; exit 1; }

mkdir -p "$USERS_DIR"
chmod 700 "$USERS_DIR"

if jq -e --arg name "$NAME" '.inbounds[] | select(.port == 443) | .settings.clients[]? | select(.email == $name)' "$CONFIG" >/dev/null; then
  echo "ERROR: user '$NAME' already exists." >&2
  exit 1
fi

UUID="$($XRAY_BIN uuid)"
PUBLIC_KEY="$({
  PK=$(jq -r '.inbounds[] | select(.port == 443) | .streamSettings.realitySettings.privateKey' "$CONFIG")
  "$XRAY_BIN" x25519 -i "$PK"
} | sed -n 's/^Password (PublicKey): //p')"
SHORT_ID=$(jq -r '.inbounds[] | select(.port == 443) | .streamSettings.realitySettings.shortIds[0]' "$CONFIG")
SNI=$(jq -r '.inbounds[] | select(.port == 443) | .streamSettings.realitySettings.serverNames[0]' "$CONFIG")
PATH_VALUE=$(jq -r '.inbounds[] | select(.port == 443) | .streamSettings.xhttpSettings.path' "$CONFIG")
MODE=$(jq -r '.inbounds[] | select(.port == 443) | .streamSettings.xhttpSettings.mode' "$CONFIG")
SERVER_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"

[[ -n "$SERVER_IP" ]] || { echo "ERROR: could not determine public IPv4 address." >&2; exit 1; }
[[ -n "$PUBLIC_KEY" && "$PUBLIC_KEY" != "null" ]] || { echo "ERROR: could not derive REALITY public key." >&2; exit 1; }
[[ -n "$SHORT_ID" && "$SHORT_ID" != "null" ]] || { echo "ERROR: REALITY shortId not found." >&2; exit 1; }
[[ -n "$SNI" && "$SNI" != "null" ]] || { echo "ERROR: REALITY serverName not found." >&2; exit 1; }
[[ -n "$PATH_VALUE" && "$PATH_VALUE" != "null" ]] || { echo "ERROR: XHTTP path not found." >&2; exit 1; }

TMP_CONFIG=$(mktemp)
BACKUP="$DATA_DIR/config.backup.$(date +%Y%m%d-%H%M%S).json"
trap 'rm -f "$TMP_CONFIG"' EXIT

cp -a "$CONFIG" "$BACKUP"

jq --arg uuid "$UUID" --arg name "$NAME" '
  .inbounds |= map(
    if .port == 443 then
      .settings.clients += [{"id": $uuid, "email": $name}]
    else . end
  )
' "$CONFIG" > "$TMP_CONFIG"

"$XRAY_BIN" run -test -config "$TMP_CONFIG"

cp "$TMP_CONFIG" "$CONFIG"
chown root:nogroup "$CONFIG" 2>/dev/null || chown root:root "$CONFIG"
chmod 640 "$CONFIG"

SERVICE=""
for candidate in xray.service xray-vless.service; do
  if systemctl cat "$candidate" >/dev/null 2>&1; then
    SERVICE="$candidate"
    break
  fi
done
[[ -n "$SERVICE" ]] || { cp "$BACKUP" "$CONFIG"; echo "ERROR: Xray systemd service not found." >&2; exit 1; }

if ! systemctl restart "$SERVICE"; then
  cp "$BACKUP" "$CONFIG"
  systemctl restart "$SERVICE" || true
  echo "ERROR: Xray restart failed. Configuration rolled back." >&2
  exit 1
fi
sleep 1
if [[ "$(systemctl is-active "$SERVICE")" != "active" ]]; then
  cp "$BACKUP" "$CONFIG"
  systemctl restart "$SERVICE" || true
  echo "ERROR: Xray is not active. Configuration rolled back." >&2
  exit 1
fi

URL_PATH=$(printf '%s' "$PATH_VALUE" | jq -sRr @uri)
CLIENT_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${URL_PATH}&mode=${MODE}#${NAME}"

cat > "$USERS_DIR/${NAME}.txt" <<EOF
Name: $NAME
UUID: $UUID
VLESS URL: $CLIENT_URL
EOF
chmod 600 "$USERS_DIR/${NAME}.txt"

cat <<EOF

User created successfully.

Name:       $NAME
UUID:       $UUID
Server:     $SERVER_IP:$PORT
SNI:        $SNI
Public key: $PUBLIC_KEY
Short ID:   $SHORT_ID
XHTTP path: $PATH_VALUE
XHTTP mode: $MODE

VLESS URL:
$CLIENT_URL

Backup:
$BACKUP
EOF
