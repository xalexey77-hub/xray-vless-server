#!/usr/bin/env bash
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
CONFIG="/usr/local/etc/xray/config.json"
DATA_DIR="/etc/xray-vless"
USERS_DIR="$DATA_DIR/users"
QR_DIR="$DATA_DIR/qr"
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

INBOUND_COUNT=$(jq '[.inbounds[] | select(.port == 443 and .protocol == "vless")] | length' "$CONFIG")
[[ "$INBOUND_COUNT" -eq 1 ]] || {
  echo "ERROR: expected exactly one VLESS inbound on port 443, found $INBOUND_COUNT." >&2
  exit 1
}

PUBLIC_KEY="$({
  PK=$(jq -r '.inbounds[] | select(.port == 443 and .protocol == "vless") | .streamSettings.realitySettings.privateKey' "$CONFIG")
  [[ -n "$PK" && "$PK" != "null" ]] || exit 1
  "$XRAY_BIN" x25519 -i "$PK"
} | sed -n 's/^Password (PublicKey): //p')"
SHORT_ID=$(jq -r '.inbounds[] | select(.port == 443 and .protocol == "vless") | .streamSettings.realitySettings.shortIds[0]' "$CONFIG")
SNI=$(jq -r '.inbounds[] | select(.port == 443 and .protocol == "vless") | .streamSettings.realitySettings.serverNames[0]' "$CONFIG")
PATH_VALUE=$(jq -r '.inbounds[] | select(.port == 443 and .protocol == "vless") | .streamSettings.xhttpSettings.path' "$CONFIG")
MODE=$(jq -r '.inbounds[] | select(.port == 443 and .protocol == "vless") | .streamSettings.xhttpSettings.mode' "$CONFIG")
SERVER_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"

[[ -n "$SERVER_IP" ]] || { echo "ERROR: could not determine public IPv4 address." >&2; exit 1; }
[[ -n "$PUBLIC_KEY" && "$PUBLIC_KEY" != "null" ]] || { echo "ERROR: could not derive REALITY public key." >&2; exit 1; }
[[ -n "$SHORT_ID" && "$SHORT_ID" != "null" ]] || { echo "ERROR: REALITY shortId not found." >&2; exit 1; }
[[ -n "$SNI" && "$SNI" != "null" ]] || { echo "ERROR: REALITY serverName not found." >&2; exit 1; }
[[ -n "$PATH_VALUE" && "$PATH_VALUE" != "null" ]] || { echo "ERROR: XHTTP path not found." >&2; exit 1; }
[[ -n "$MODE" && "$MODE" != "null" ]] || { echo "ERROR: XHTTP mode not found." >&2; exit 1; }

URL_PATH=$(printf '%s' "$PATH_VALUE" | jq -sRr @uri)

make_qr() {
  local url="$1"
  if command -v qrencode >/dev/null 2>&1; then
    mkdir -p "$QR_DIR"
    chmod 700 "$QR_DIR"
    qrencode -o "$QR_DIR/${NAME}.png" -s 8 -m 2 "$url"
    chmod 600 "$QR_DIR/${NAME}.png"
    echo "QR PNG:    $QR_DIR/${NAME}.png"
  else
    echo "QR PNG:    not created (qrencode is not installed)"
  fi
}

# Existing users are not duplicated. If their metadata file is missing,
# recreate it from the current server configuration.
EXISTING_UUID=$(jq -r --arg name "$NAME" '
  .inbounds[]
  | select(.port == 443 and .protocol == "vless")
  | .settings.clients[]?
  | select(.email == $name)
  | .id
' "$CONFIG" | head -n1)

if [[ -n "$EXISTING_UUID" && "$EXISTING_UUID" != "null" ]]; then
  CLIENT_URL="vless://${EXISTING_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${URL_PATH}&mode=${MODE}#${NAME}"

  cat > "$USERS_DIR/${NAME}.txt" <<EOF
Name: $NAME
UUID: $EXISTING_UUID
VLESS URL: $CLIENT_URL
EOF
  chmod 600 "$USERS_DIR/${NAME}.txt"
  make_qr "$CLIENT_URL"

  echo
  echo "User already exists. Metadata file has been created/refreshed."
  echo
  echo "Name:       $NAME"
  echo "UUID:       $EXISTING_UUID"
  echo "Server:     $SERVER_IP:$PORT"
  echo "SNI:        $SNI"
  echo "Public key: $PUBLIC_KEY"
  echo "Short ID:   $SHORT_ID"
  echo "XHTTP path: $PATH_VALUE"
  echo "XHTTP mode: $MODE"
  echo
  echo "VLESS URL:"
  echo "$CLIENT_URL"
  exit 0
fi

UUID="$($XRAY_BIN uuid)"
TMP_CONFIG=$(mktemp --suffix=.json)
BACKUP="$DATA_DIR/config.backup.$(date +%Y%m%d-%H%M%S).json"
trap 'rm -f "$TMP_CONFIG"' EXIT

cp -a "$CONFIG" "$BACKUP"

jq --arg uuid "$UUID" --arg name "$NAME" '
  .inbounds |= map(
    if .port == 443 and .protocol == "vless" then
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

if [[ -z "$SERVICE" ]]; then
  cp "$BACKUP" "$CONFIG"
  echo "ERROR: Xray systemd service not found. Configuration rolled back." >&2
  exit 1
fi

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

CLIENT_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${URL_PATH}&mode=${MODE}#${NAME}"

cat > "$USERS_DIR/${NAME}.txt" <<EOF
Name: $NAME
UUID: $UUID
VLESS URL: $CLIENT_URL
EOF
chmod 600 "$USERS_DIR/${NAME}.txt"
make_qr "$CLIENT_URL"

echo
echo "User created successfully."
echo
echo "Name:       $NAME"
echo "UUID:       $UUID"
echo "Server:     $SERVER_IP:$PORT"
echo "SNI:        $SNI"
echo "Public key: $PUBLIC_KEY"
echo "Short ID:   $SHORT_ID"
echo "XHTTP path: $PATH_VALUE"
echo "XHTTP mode: $MODE"
echo
echo "VLESS URL:"
echo "$CLIENT_URL"
echo
echo "Backup:"
echo "$BACKUP"
