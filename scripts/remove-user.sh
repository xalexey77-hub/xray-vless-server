#!/usr/bin/env bash
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
CONFIG="/usr/local/etc/xray/config.json"
DATA_DIR="/etc/xray-vless"
USERS_DIR="$DATA_DIR/users"

usage() {
  echo "Usage: sudo $0 <username>"
  echo "Example: sudo $0 friend1"
  exit 1
}

[[ $# -eq 1 ]] || usage
NAME="$1"

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "ERROR: config not found: $CONFIG" >&2; exit 1; }
[[ -x "$XRAY_BIN" ]] || { echo "ERROR: Xray not found: $XRAY_BIN" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

if ! jq -e --arg name "$NAME" '.inbounds[] | select(.port == 443) | .settings.clients[]? | select(.email == $name)' "$CONFIG" >/dev/null; then
  echo "ERROR: user '$NAME' not found." >&2
  exit 1
fi

COUNT=$(jq '[.inbounds[] | select(.port == 443) | .settings.clients[]?] | length' "$CONFIG")
if [[ "$COUNT" -le 1 ]]; then
  echo "ERROR: refusing to remove the last VLESS user." >&2
  exit 1
fi

TMP_CONFIG=$(mktemp)
BACKUP="$DATA_DIR/config.backup.$(date +%Y%m%d-%H%M%S).json"
trap 'rm -f "$TMP_CONFIG"' EXIT

cp -a "$CONFIG" "$BACKUP"

jq --arg name "$NAME" '
  .inbounds |= map(
    if .port == 443 then
      .settings.clients |= map(select(.email != $name))
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

rm -f "$USERS_DIR/${NAME}.txt"

echo "User '$NAME' removed successfully."
echo "Backup: $BACKUP"
