#!/bin/bash

# Проверяем, запускается ли скрипт с правами root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами root."
  exit 1
fi

read -p "Введите внешний порт Marzban (по умолчанию 1500): " MPORT
MPORT=${MPORT:-1500}

# Проверка, что это число
if ! [[ "$MPORT" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: значение должно быть числом"
    exit 1
fi

# Спрашиваем пользователя о кастомной заглушке
read -p "Установить кастомный шаблон заглушки? (y/n): " INSTALL_TEMPLATE

read -p "Вы хотите использовать Let's Encrypt для SSL? (y/n, по умолчанию n — самоподписанный): " USE_LETSENCRYPT
USE_LETSENCRYPT=${USE_LETSENCRYPT:-n}

ssl_dir="/opt/marzban/ssl"
mkdir -p "$ssl_dir"

if [[ "$USE_LETSENCRYPT" =~ ^[Yy]$ ]]; then
    read -p "Введите ваш домен (должен быть уже привязан к этому серверу): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo "Ошибка: домен не введён"
        exit 1
    fi

    echo "Устанавливаю certbot и получаю сертификат от Let's Encrypt для $DOMAIN..."

    apt update && apt install -y certbot

    # Получаем сертификат (режим standalone требует остановки служб на 80 порту)
    systemctl stop nginx 2>/dev/null || true
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN"

    cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    key_file="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "Ошибка: сертификат не получен. Проверьте DNS, доступность порта 80 и домен."
        exit 1
    fi

    echo "Сертификат успешно получен."
else
    echo "Генерация самоподписанного сертификата..."

    DOMAIN=$(curl -s ifconfig.me)
    if [ -z "$DOMAIN" ]; then
      echo "Не удалось определить публичный IP-адрес. Проверьте подключение к интернету."
      exit 1
    fi

    cert_file="$ssl_dir/$DOMAIN.pem"
    key_file="$ssl_dir/$DOMAIN.key.pem"

    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$key_file" \
      -out "$cert_file" \
      -subj "/C=RU/ST=Moscow/L=Moscow/O=Example Company/OU=IT Department/CN=$DOMAIN"
fi

env_file="/opt/marzban/.env"

touch "$env_file"

sed -i '/^UVICORN_SSL_CERTFILE = /d' "$env_file"
sed -i '/^UVICORN_SSL_KEYFILE = /d' "$env_file"

echo "UVICORN_SSL_CERTFILE = \"$cert_file\"" >> "$env_file"
echo "UVICORN_SSL_KEYFILE = \"$key_file\"" >> "$env_file"

sed -i '/^UVICORN_PORT = /d' "$env_file"
echo "UVICORN_PORT = $MPORT" >> "$env_file"

if [[ "$INSTALL_TEMPLATE" =~ ^[Yy]$ ]]; then
    echo "Устанавливаю кастомный шаблон..."

    # Создаём директорию, если её нет
    mkdir -p /var/lib/marzban/templates/home/

    # Скачиваем index.html
    curl -fsSL "https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzban-ispmgr/index.html" -o /var/lib/marzban/templates/home/index.html

    # Проверка успешной загрузки
    if [ ! -s /var/lib/marzban/templates/home/index.html ]; then
        echo "Ошибка: Не удалось скачать шаблон. Пропускаем установку шаблона."
    else
        # Обновляем .env
        sed -i '/^CUSTOM_TEMPLATES_DIRECTORY = /d' "$env_file"
        sed -i '/^HOME_PAGE_TEMPLATE = /d' "$env_file"

        echo 'CUSTOM_TEMPLATES_DIRECTORY = "/var/lib/marzban/templates/"' >> "$env_file"
        echo 'HOME_PAGE_TEMPLATE = "home/index.html"' >> "$env_file"

        echo "Кастомный шаблон установлен."
    fi
else
    echo "Кастомный шаблон не будет установлен."
fi


marzban restart

echo ""
echo "Marzban теперь доступен по адресу: https://$DOMAIN:$MPORT/dashboard"
echo ""
