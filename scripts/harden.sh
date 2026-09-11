#!/usr/bin/env bash
set -Eeuo pipefail

# Safe baseline hardening for an Ubuntu VPS running Xray.
# This script intentionally does NOT modify Xray configuration or its
# listening ports. It installs/enables UFW, allows SSH and TCP/443,
# enables unattended security updates when available, and creates a
# backup of relevant configuration before making firewall changes.

SSH_PORT="${SSH_PORT:-22}"
XRAY_PORT="443"
BACKUP_DIR="/root/xray-vless-backups/hardening-$(date +%Y%m%d-%H%M%S)"

[[ "$EUID" -eq 0 ]] || { echo "Run as root or with sudo." >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Backup SSH and Xray configuration before changes.
cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config" 2>/dev/null || true
cp -a /etc/ssh/sshd_config.d "$BACKUP_DIR/sshd_config.d" 2>/dev/null || true
cp -a /usr/local/etc/xray/config.json "$BACKUP_DIR/config.json" 2>/dev/null || true
cp -a /etc/xray-vless "$BACKUP_DIR/xray-vless" 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ufw unattended-upgrades

# Default-deny inbound, allow outbound.
ufw default deny incoming
ufw default allow outgoing

# Keep SSH open before enabling the firewall.
ufw allow "$SSH_PORT/tcp" comment 'SSH'
ufw allow "$XRAY_PORT/tcp" comment 'Xray VLESS XHTTP REALITY'

ufw --force enable

# Enable unattended security upgrades where supported.
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
systemctl enable --now unattended-upgrades.service 2>/dev/null || true

# Validate SSH config but do not restart sshd automatically.
sshd -t

cat <<EOF

Hardening completed.

Firewall:
  SSH TCP/$SSH_PORT  allowed
  Xray TCP/$XRAY_PORT allowed

Backup:
  $BACKUP_DIR

Xray configuration was not modified.
SSH was not restarted automatically.

Verify from a second terminal before closing the current SSH session:
  ssh -p $SSH_PORT root@<SERVER_IP>

Then check:
  ufw status verbose
  systemctl is-active xray.service
  ss -lntup
EOF
