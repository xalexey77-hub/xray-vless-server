#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="/etc/xray-vless"
USERS_DIR="$DATA_DIR/users"

usage() {
  echo "Usage: sudo $0 <username>"
  echo "Example: sudo $0 iam"
  exit 1
}

[[ $# -eq 1 ]] || usage
NAME="$1"

if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid username." >&2
  exit 1
fi

FILE="$USERS_DIR/${NAME}.txt"
[[ -f "$FILE" ]] || {
  echo "ERROR: user file not found: $FILE" >&2
  echo "Run: sudo bash scripts/add-user.sh $NAME" >&2
  exit 1
}

URL=$(sed -n 's/^VLESS URL: //p' "$FILE")
[[ -n "$URL" ]] || { echo "ERROR: VLESS URL not found in $FILE" >&2; exit 1; }

echo "=== USER ==="
grep -E '^(Name|UUID): ' "$FILE"
echo
echo "=== VLESS URL ==="
echo "$URL"

echo
if command -v qrencode >/dev/null 2>&1; then
  echo "=== QR CODE ==="
  qrencode -t ANSIUTF8 "$URL"
else
  echo "QR code: qrencode is not installed."
  echo "Install once: apt update && apt install -y qrencode"
fi
