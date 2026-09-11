#!/usr/bin/env bash
set -Eeuo pipefail

# Restore Xray configuration and project data from a backup created by
# scripts/backup.sh. The script validates Xray configuration before restart
# and automatically attempts to roll back if the service does not recover.

[[ "$EUID" -eq 0 ]] || { echo "Run as root or with sudo." >&2; exit 1; }

BACKUP_ROOT="/root/xray-vless-backups"
BACKUP_DIR="${1:-}"

if [[ -z "$BACKUP_DIR" && -f "$BACKUP_ROOT/latest" ]]; then
  BACKUP_DIR="$(cat "$BACKUP_ROOT/latest")"
fi

[[ -d "$BACKUP_DIR" ]] || {
  echo "ERROR: backup directory not found: $BACKUP_DIR" >&2
  echo "Usage: sudo bash $0 /root/xray-vless-backups/YYYYMMDD-HHMMSS" >&2
  exit 1
}

CONFIG="/usr/local/etc/xray/config.json"
RESTORE_CONFIG="$BACKUP_DIR/config.json/config.json"
[[ -f "$RESTORE_CONFIG" ]] || RESTORE_CONFIG="$BACKUP_DIR/config.json"

if [[ -f "$RESTORE_CONFIG" ]]; then
  /usr/local/bin/xray run -test -config "$RESTORE_CONFIG"
else
  echo "ERROR: Xray config not found in backup: $BACKUP_DIR" >&2
  exit 1
fi

LIVE_BACKUP="/root/xray-vless-backups/pre-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LIVE_BACKUP"
chmod 700 "$LIVE_BACKUP"
cp -a "$CONFIG" "$LIVE_BACKUP/config.json" 2>/dev/null || true

cp -a "$RESTORE_CONFIG" "$CONFIG"
chown root:nogroup "$CONFIG" 2>/dev/null || chown root:root "$CONFIG"
chmod 640 "$CONFIG"

if [[ -d "$BACKUP_DIR/xray-vless" ]]; then
  rm -rf /etc/xray-vless
  cp -a "$BACKUP_DIR/xray-vless" /etc/
  chmod 700 /etc/xray-vless 2>/dev/null || true
fi

systemctl daemon-reload
if ! systemctl restart xray.service; then
  cp -a "$LIVE_BACKUP/config.json" "$CONFIG" 2>/dev/null || true
  systemctl restart xray.service || true
  echo "ERROR: restore failed; previous Xray config restored." >&2
  exit 1
fi

sleep 1
if [[ "$(systemctl is-active xray.service)" != "active" ]]; then
  cp -a "$LIVE_BACKUP/config.json" "$CONFIG" 2>/dev/null || true
  chown root:nogroup "$CONFIG" 2>/dev/null || chown root:root "$CONFIG"
  chmod 640 "$CONFIG"
  systemctl restart xray.service || true
  echo "ERROR: Xray did not become active; previous config restored." >&2
  exit 1
fi

echo "Restore completed successfully from: $BACKUP_DIR"
echo "Pre-restore backup: $LIVE_BACKUP"
