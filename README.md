# Xray VLESS Server for Ubuntu

Автоматическая установка собственного VLESS-сервера на Ubuntu с транспортом **XHTTP** и защитой **REALITY**.

Проект рассчитан на собственный VPS и предназначен для подключения к нему с Xray-клиентов. Он не хранит UUID и REALITY private key в GitHub: эти данные генерируются непосредственно на сервере.

## Что устанавливается

- Xray-core из официального установщика Xray
- VLESS inbound на TCP/443
- XHTTP transport
- REALITY
- systemd service `xray-vless.service`
- автоматическая генерация UUID, REALITY key pair и shortId
- UFW rule для TCP/443, если UFW уже активен
- VLESS URL и JSON-параметры клиента

## Требования

- Ubuntu 24.04 или новее
- VPS с публичным IPv4
- root/sudo
- свободный TCP-порт 443

## Установка

```bash
git clone https://github.com/xalexey77-hub/xray-vless-server.git
cd xray-vless-server
sudo ./install.sh
```

Установщик спросит:

1. `REALITY serverName` — имя хоста, соответствующее сертификату целевого TLS-сервера.
2. `REALITY destination` — адрес целевого TLS-сервера, например `www.example.com:443`.
3. `XHTTP path` — путь XHTTP, например `/xhttp`.

После установки скрипт покажет VLESS URL. Его можно импортировать в клиент, поддерживающий VLESS + XHTTP + REALITY.

## Проверка

```bash
sudo ./scripts/status.sh
```

Получить клиентские параметры повторно:

```bash
sudo ./scripts/show-client-config.sh
```

Логи:

```bash
sudo journalctl -u xray-vless.service -f
```

Проверка конфигурации:

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

## Файлы на сервере

- `/usr/local/etc/xray/config.json` — конфигурация Xray
- `/etc/xray-vless/server.env` — секретные параметры сервера
- `/etc/xray-vless/client.json` — параметры клиента
- `/etc/xray-vless/client.txt` — VLESS URL
- `/etc/systemd/system/xray-vless.service` — systemd unit

Эти файлы с секретами не должны попадать в Git.

## Удаление

```bash
sudo ./scripts/uninstall.sh
```

Скрипт запросит подтверждение `yes` перед удалением.

## Важно

REALITY/XHTTP не гарантирует работу в любой сети: эффективность зависит от текущих методов фильтрации и блокировок. Перед использованием необходимо убедиться, что выбранный `serverName` действительно соответствует TLS-сертификату и поддерживает необходимые параметры TLS.

Конфигурация проекта намеренно минимальная. Дополнительные XHTTP tuning-параметры, несколько пользователей, маршрутизацию и альтернативные профили можно добавить позже.
