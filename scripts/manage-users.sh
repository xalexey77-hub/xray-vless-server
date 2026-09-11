#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ADD="$SCRIPT_DIR/add-user.sh"
LIST="$SCRIPT_DIR/list-users.sh"
SHOW="$SCRIPT_DIR/show-user.sh"
REMOVE="$SCRIPT_DIR/remove-user.sh"
BACKUP="$SCRIPT_DIR/backup.sh"
CONFIG="/usr/local/etc/xray/config.json"
XRAY="/usr/local/bin/xray"

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }

pause() {
  echo
  read -r -p "Press Enter to continue..." _
}

show_menu() {
  clear
  echo "================================"
  echo "        XRAY USER MANAGER"
  echo "================================"
  echo
  echo "1. List users"
  echo "2. Add user"
  echo "3. Show VLESS + QR"
  echo "4. Remove user"
  echo "5. Check Xray"
  echo "6. Create backup"
  echo "0. Exit"
  echo
}

choose_user() {
  local prompt="$1"
  local name
  echo
  "$LIST"
  echo
  read -r -p "$prompt" name
  [[ -n "$name" ]] || { echo "ERROR: username is empty." >&2; return 1; }
  printf '%s\n' "$name"
}

while true; do
  show_menu
  read -r -p "Choose an action: " choice
  echo

  case "$choice" in
    1)
      "$LIST"
      pause
      ;;
    2)
      read -r -p "Username: " name
      if [[ -z "$name" ]]; then
        echo "ERROR: username is empty."
      else
        "$ADD" "$name"
      fi
      pause
      ;;
    3)
      read -r -p "Username: " name
      if [[ -n "$name" ]]; then
        "$SHOW" "$name" --png
      else
        echo "ERROR: username is empty."
      fi
      pause
      ;;
    4)
      read -r -p "Username to remove: " name
      if [[ "$name" == "xhttp-main" ]]; then
        echo "ERROR: xhttp-main is the manually configured main profile and cannot be removed here."
      elif [[ -n "$name" ]]; then
        read -r -p "Remove '$name'? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          "$REMOVE" "$name"
        else
          echo "Cancelled."
        fi
      else
        echo "ERROR: username is empty."
      fi
      pause
      ;;
    5)
      echo "=== SERVICE ==="
      systemctl is-active xray.service || true
      echo
      echo "=== VERSION ==="
      "$XRAY" version
      echo
      echo "=== CONFIG TEST ==="
      "$XRAY" run -test -config "$CONFIG"
      echo
      echo "=== PORT 443 ==="
      ss -lntp | grep ':443' || echo "443 is not listening"
      pause
      ;;
    6)
      "$BACKUP"
      pause
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Unknown option."
      pause
      ;;
  esac
done
