#!/usr/bin/env bash
set -Eeuo pipefail

# Create a timestamped local backup of Xray and project secrets.
# Backups are stored outside the Git repository.

[[ "$EUID" -eq 0 ]] || { echo "Run as root or with sudo." >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/root/xray-vless-backups"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

for path in \
  /usr/local/etc/xray/config.json \
  /etc/xray-vless \
  /etc/systemd/system/xray.service \
  /etc/systemd/system/xray.service.d; do
  if [[ -e "$path" ]]; then
    cp -a "$path" "$BACKUP_DIR/"
  fi
done

# Capture useful system state without storing command history or SSH passwords.
systemctl cat xray.service > "$BACKUP_DIR/xray.service.txt" 2>&1 || true
ss -lntup > "$BACKUP_DIR/listening.txt" 2>&1 || true
ufw status verbose > "$BACKUP_DIR/ufw.txt" 2>&1 || true

printf '%s\n' "$BACKUP_DIR" > "$BACKUP_ROOT/latest"
chmod 600 "$BACKUP_ROOT/latest"

cat <<EOF
Backup created:
$BACKUP_DIR

Latest backup marker:
$BACKUP_ROOT/latest
EOF
