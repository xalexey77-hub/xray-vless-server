#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="/etc/xray-vless/server.env"
CLIENT_FILE="/etc/xray-vless/client.json"
CLIENT_TXT="/etc/xray-vless/client.txt"

[[ $EUID -eq 0 ]] || { echo "Запустите: sudo ./scripts/show-client-config.sh" >&2; exit 1; }
[[ -r "$ENV_FILE" ]] || { echo "Конфигурация сервера не найдена: $ENV_FILE" >&2; exit 1; }

. "$ENV_FILE"

SERVER_IP="${SERVER_IP:-}"
if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
fi
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"

python3 - "$SERVER_IP" "$UUID" "$SERVER_NAME" "$PUBLIC_KEY" "$SHORT_ID" "$XHTTP_PATH" <<'PY'
import sys, urllib.parse
server_ip, uuid, sni, pbk, sid, path = sys.argv[1:]
uri = (
    f"vless://{uuid}@{server_ip}:443"
    f"?encryption=none&security=reality"
    f"&sni={urllib.parse.quote(sni, safe='')}"
    f"&fp=chrome&pbk={urllib.parse.quote(pbk, safe='')}"
    f"&sid={sid}&type=xhttp"
    f"&path={urllib.parse.quote(path, safe='')}&mode=auto"
    f"#Xray-XHTTP-REALITY"
)
print(uri)
PY

echo
echo "JSON:"
cat "$CLIENT_FILE"
