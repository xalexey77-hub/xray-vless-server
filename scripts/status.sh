#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="xray-vless.service"
CONFIG="/usr/local/etc/xray/config.json"
ENV_FILE="/etc/xray-vless/server.env"
CLIENT_FILE="/etc/xray-vless/client.json"
CLIENT_TXT="/etc/xray-vless/client.txt"

systemctl --no-pager --full status "$SERVICE" || true

echo
echo "--- Listening on TCP/443 ---"
ss -ltnp 2>/dev/null | grep -E '(:443[[:space:]]|\]:443[[:space:]])' || true

echo
echo "--- Client parameters ---"
if [[ -r "$ENV_FILE" ]]; then
  . "$ENV_FILE"
  echo "ServerName : ${SERVER_NAME}"
  echo "PublicKey  : ${PUBLIC_KEY}"
  echo "ShortID    : ${SHORT_ID}"
  echo "XHTTP path : ${XHTTP_PATH}"
  echo "UUID       : ${UUID}"
fi

echo
echo "Client JSON: $CLIENT_FILE"
echo "VLESS URL : $CLIENT_TXT"
