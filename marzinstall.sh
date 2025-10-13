#!/bin/bash
set -e

# Установка Docker и Marzban
echo "Обновление системы и установка Docker..."
apt update
apt install -y docker.io docker-compose curl jq openssl qrencode

echo "Установка Marzban..."
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install > /dev/null 2>&1 &

echo -n "Ожидание запуска Marzban..."
while ! sudo docker ps | grep marzban; do
    echo -n "."
    sleep 2
done
echo -e "\nMarzban успешно запущен!"

# Создание администратора
ADMIN_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')
sudo marzban cli admin create --username admin --sudo --password "$ADMIN_PASSWORD" --telegram-id 0 --discord-webhook 0
SERVER_IP=$(hostname -I | awk '{print $1}')
OUTPUT_FILE="/root/marzban.txt"

# Выбор оптимального домена (SNI)
DOMAINS=("teamdocs.su" "wikiportal.su" "docscenter.su")
BEST_DOMAIN=""
BEST_PING=9999

echo "Подбираем лучший домен для Reality..."
for domain in "${DOMAINS[@]}"; do
    echo "Проверка пинга $domain..."
    PING_RESULT=$(ping -c 4 -W 1 "$domain" 2>/dev/null | awk -F'time=' '/time=/{sum+=$2} END{if(NR>0) printf "%.2f", sum/NR}' || echo "")
    if [[ -n "$PING_RESULT" ]]; then
        PING_MS=$(printf "%.0f" "$PING_RESULT")
        if [[ "$PING_MS" -lt "$BEST_PING" ]]; then
            BEST_PING=$PING_MS
            BEST_DOMAIN=$domain
        fi
    fi
done

[[ -z "$BEST_DOMAIN" ]] && BEST_DOMAIN="teamdocs.su"
REALITY_DOMAIN=$BEST_DOMAIN
REALITY_DEST="${REALITY_DOMAIN}:443"
echo "Выбран домен: $REALITY_DOMAIN"

# Проверка контейнера Marzban
echo "Ожидание запуска контейнера Marzban..."
while ! docker ps | grep marzban; do
    echo -n "."
    sleep 2
done
echo -e "\nКонтейнер Marzban работает."

# Генерация ключей Xray
CONTAINER=""
while true; do
    CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'marzban[_-]marzban[_-]1')
    if [[ -n "$CONTAINER" ]]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo -e "\nКонтейнер $CONTAINER найден."

# Проверяем, что внутри контейнера есть команда xray
if ! docker exec "$CONTAINER" which xray >/dev/null 2>&1; then
    echo "Ошибка: команда xray не найдена в контейнере $CONTAINER"
    exit 1
fi

echo "Генерация ключей Xray..."
KEYS=$(docker exec $CONTAINER xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk '/Private key:/ {print $3}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/Public key:/ {print $3}')
SHORT_ID=$(openssl rand -hex 8)
echo "Ключи успешно сгенерированы."

# Настройка Xray
XCONFIG_PATH="/var/lib/marzban/xray_config.json"
cat > "$XCONFIG_PATH" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "reality-inbound",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": ["$REALITY_DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "publicKey": "$PUBLIC_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" }
  ]
}
EOF

echo "Перезагрузка Marzban для применения конфигурации..."
marzban restart &
echo -n "Ожидание перезапуска контейнера..."
sleep 60
echo -e "\nКонтейнер Marzban снова работает, продолжаем скрипт..."


# Получение API токена
TOKEN=$(curl -s -X POST "http://127.0.0.1:8000/api/admin/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=/password/&username=admin&password=$ADMIN_PASSWORD" | jq -r '.access_token')

# Создание Vless-пользователя
USER_NAME="user"
USER_UUID=$(cat /proc/sys/kernel/random/uuid)
FLOW_TYPE="xtls-rprx-vision"

USER_JSON=$(jq -n \
  --arg username "$USER_NAME" \
  --arg uuid "$USER_UUID" \
  --arg inbound "reality-inbound" \
  --arg flow "$FLOW_TYPE" \
  '{
    username: $username,
    proxies: { vless: { uuid: $uuid, flow: $flow } },
    inbounds: { vless: [$inbound] },
    expire: 0,
    data_limit: 0,
    data_limit_reset_strategy: "no_reset",
    status: "active"
  }')

curl -s -X POST "http://127.0.0.1:8000/api/user" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON"

# Проверка успешности
API_USERS_URL="http://127.0.0.1:8000/api/users?limit=10&sort=-created_at"

API_USERS_RESULT=$(curl -s -X GET "$API_USERS_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")

SERVER_IP=$(hostname -I | awk '{print $1}')

# Проверка успешности
if echo "$API_USERS_RESULT" | grep -q '"users":'; then
    # Берём ссылку первого пользователя в списке (самый последний созданный)
    VLESS_LINK=$(echo "$API_USERS_RESULT" | jq -r '.users[0].links[0]')

    if [[ -n "$VLESS_LINK" ]]; then
        echo -e "\033[0;32mVless-пользователь найден. Ссылка получена через API.\033[0m"

        # Сохраняем в файл
        OUTPUT_FILE="/root/marzban.txt"
        {
          echo "Ваш Vless ключ, его можно использовать сразу на нескольких устройствах."
          echo "Your Vless key, it can be used on multiple devices at once."
          echo ""
          echo "$VLESS_LINK"
          echo ""
          echo "QR:"
          qrencode -t ANSIUTF8 "$VLESS_LINK"
          echo ""
          echo "ENG:"
          echo "Marzban Control Panel (https://github.com/Gozargah/Marzban) was successfully installed:"
          echo "URL - http://127.0.0.1:8000/dashboard/"
          echo "Login - admin"
          echo "Password - $ADMIN_PASSWORD"
          echo ""
          echo "The web panel is now only available locally due to a security update from the developers of this panel."
          echo "To access the web panel, we recommend creating an SSH tunnel from your device to the server by executing the following command in your terminal:"
          echo "ssh -L 8000:localhost:8000 root@$SERVER_IP"
          echo "When connecting, enter the root password of the server, and after the SSH connection is established, the panel will be accessible in your browser at the above URL."
          echo "For more detailed instructions on how to access the panel, refer to the guide:"
          echo "https://wiki.aeza.net/razvertyvanie-proksi-protokola-vless-s-pomoshyu-marzban#id-2.-poluchenie-dannykh-dlya-vkhoda-v-marzban"
          echo ""
          echo "RUS:"
          echo "Панель управления Marzban (https://github.com/Gozargah/Marzban) доступна по следующим данным:"
          echo "Ссылка - http://127.0.0.1:8000/dashboard/"
          echo "Логин - admin"
          echo "Пароль - $ADMIN_PASSWORD"
          echo "Веб панель теперь доступна лишь локально в связи с обновлением безопасности разработчиков данной панели."
          echo "Для доступа к веб-панели рекомендуем выполнить проброс SSH-туннеля с вашего устройства до сервера командой в командную строку или терминал:"
          echo "ssh -L 8000:localhost:8000 root@$SERVER_IP"
          echo "При подключении ввести root-пароль сервера и после открытия подключения по SSH, панель будет доступна в браузере по указанной выше ссылке."
          echo "Подробная инструкция по входу в панель описана в инструкции:"
          echo "https://wiki.aeza.net/razvertyvanie-proksi-protokola-vless-s-pomoshyu-marzban#id-2.-poluchenie-dannykh-dlya-vkhoda-v-marzban"
        } > "$OUTPUT_FILE"

        echo -e "\033[0;32mВсе данные сохранены в файл: $OUTPUT_FILE\033[0m"
    else
        echo -e "\033[0;31mОшибка: VLESS ссылка не найдена для последнего пользователя.\033[0m"
        exit 1
    fi
else
    echo -e "\033[0;31mОшибка при получении списка пользователей через API!\033[0m"
    echo "$API_USERS_RESULT"
    exit 1
fi