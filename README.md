# Xray VLESS Server for Ubuntu

Автоматическая установка собственного VLESS-сервера на Ubuntu с транспортом **XHTTP** и защитой **REALITY**.

Проект рассчитан на собственный VPS и предназначен для подключения к нему с Xray-клиентов. Секретные параметры сервера генерируются непосредственно на сервере и не должны попадать в Git.

## Что устанавливается

- Xray-core из официального установщика Xray
- VLESS inbound на TCP/443
- XHTTP transport
- REALITY
- systemd service Xray
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
sudo bash install.sh
```

Установщик спросит:

1. `REALITY serverName` — имя хоста, соответствующее сертификату целевого TLS-сервера.
2. `REALITY destination` — адрес целевого TLS-сервера, например `www.example.com:443`.
3. `XHTTP path` — путь XHTTP, например `/xhttp`.

После установки скрипт покажет VLESS URL. Его можно импортировать в клиент, поддерживающий VLESS + XHTTP + REALITY.

## Проверка

```bash
sudo bash scripts/status.sh
```

Получить основной клиентский профиль повторно:

```bash
sudo bash scripts/show-client-config.sh
```

Логи:

```bash
sudo journalctl -u xray.service -f
```

Проверка конфигурации:

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

## Управление пользователями

Каждый пользователь получает отдельный UUID. REALITY public key, shortId, SNI и XHTTP параметры остаются общими для сервера.

### Добавить пользователя

```bash
sudo bash scripts/add-user.sh friend1
```

Скрипт:

- генерирует новый UUID;
- добавляет пользователя в VLESS inbound на `443`;
- проверяет конфигурацию Xray;
- создаёт резервную копию конфигурации;
- перезапускает Xray и проверяет его состояние;
- выводит готовую VLESS-ссылку;
- сохраняет ссылку в `/etc/xray-vless/users/friend1.txt`.

### Посмотреть пользователей

```bash
sudo bash scripts/list-users.sh
```

### Удалить пользователя

```bash
sudo bash scripts/remove-user.sh friend1
```

Скрипт не позволит удалить последнего пользователя, чтобы не оставить VLESS без действующего UUID.

### Важная особенность

VLESS URL содержит UUID пользователя и публичные параметры подключения. Его можно передавать пользователю, которому предоставляется доступ. **REALITY private key сервера никогда не передаётся клиентам и не публикуется в Git.**

## Файлы на сервере

- `/usr/local/etc/xray/config.json` — конфигурация Xray
- `/etc/xray-vless/server.env` — секретные параметры сервера
- `/etc/xray-vless/client.json` — параметры основного клиента
- `/etc/xray-vless/client.txt` — VLESS URL основного клиента
- `/etc/xray-vless/users/` — индивидуальные VLESS-ссылки пользователей

Эти файлы с секретами не должны попадать в Git.

## Удаление

```bash
sudo bash scripts/uninstall.sh
```

Скрипт запросит подтверждение `yes` перед удалением.

## Важно

REALITY/XHTTP не гарантирует работу в любой сети: эффективность зависит от текущих методов фильтрации и блокировок. Перед использованием необходимо убедиться, что выбранный `serverName` действительно соответствует TLS-сертификату и поддерживает необходимые параметры TLS.

Конфигурация проекта намеренно минимальная. Скрипты управления несколькими VLESS-пользователями включены в проект.
