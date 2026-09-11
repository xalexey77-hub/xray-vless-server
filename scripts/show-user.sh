#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="/etc/xray-vless"
USERS_DIR="$DATA_DIR/users"
QR_DIR="$DATA_DIR/qr"

usage() {
  echo "Usage: sudo $0 <username> [--png]"
  echo "Example: sudo $0 iam"
  echo "         sudo $0 iam --png"
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
NAME="$1"
PNG=0
[[ $# -eq 1 || "$2" == "--png" ]] || usage
[[ $# -eq 2 ]] && PNG=1

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

  if [[ "$PNG" -eq 1 ]]; then
    mkdir -p "$QR_DIR"
    chmod 700 "$QR_DIR"
    PNG_FILE="$QR_DIR/${NAME}.png"
    qrencode -o "$PNG_FILE" -s 8 -m 2 "$URL"
    chmod 600 "$PNG_FILE"
    echo
    echo "=== PNG FILE ==="
    echo "$PNG_FILE"
  fi
else
  echo "QR code: qrencode is not installed."
  echo "Install once: apt update && apt install -y qrencode"
fi
