#!/usr/bin/env bash
set -euo pipefail

CONFIG="/usr/local/etc/xray/config.json"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash scripts/list-users.sh" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "ERROR: config not found: $CONFIG" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

printf '%-24s %s\n' "NAME" "UUID"
printf '%-24s %s\n' "------------------------" "------------------------------------"

jq -r '
  .inbounds[]
  | select(.port == 443)
  | .settings.clients[]?
  | [(.email // "unnamed"), .id] | @tsv
' "$CONFIG" | while IFS=$'\t' read -r name uuid; do
  printf '%-24s %s\n' "$name" "$uuid"
done
