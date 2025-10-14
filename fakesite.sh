#!/bin/bash

# Значение порта по умолчанию
SPORT=9000

# Разбор аргументов
while [[ $# -gt 0 ]]; do
    case "$1" in
        --selfsni-port)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                SPORT="$2"
                shift 2
            else
                echo "Ошибка: укажите корректный порт после аргумента --selfsni-port."
                exit 1
            fi
            ;;
        *)
            echo "Неизвестный аргумент: $1"
            echo "Использование: $0 [--selfsni-port <порт>]"
            exit 1
            ;;
    esac
done

WITHOUT_80=0
for arg in "$@"; do
    if [[ "$arg" == "--without-80" ]]; then
        WITHOUT_80=1
    fi
done

# Проверка системы
if ! grep -E -q "^(ID=debian|ID=ubuntu)" /etc/os-release; then
    echo "Скрипт поддерживает только Debian или Ubuntu. Завершаю работу."
    exit 1
fi

# Запрос доменного имени
read -p "Введите доменное имя: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "Доменное имя не может быть пустым. Завершаю работу."
    exit 1
fi

# Получение внешнего IP сервера
external_ip=$(curl -s --max-time 3 https://api.ipify.org)

# Проверка, что curl успешно получил IP
if [[ -z "$external_ip" ]]; then
  echo "Не удалось определить внешний IP сервера. Проверьте подключение к интернету."
  exit 1
fi

echo "Внешний IP сервера: $external_ip"

# Получение A-записи домена
domain_ip=$(dig +short A "$DOMAIN")

# Проверка, что A-запись существует
if [[ -z "$domain_ip" ]]; then
  echo "Не удалось получить A-запись для домена $DOMAIN. Убедитесь, что домен существует, подробнее что делать вы можете ознакомиться тут: https://wiki.yukikras.net/ru/selfsni"
  exit 1
fi

echo "A-запись домена $DOMAIN указывает на: $domain_ip"

# Сравнение IP адресов
if [[ "$domain_ip" == "$external_ip" ]]; then
  echo "A-запись домена $DOMAIN соответствует внешнему IP сервера."
else
  echo "A-запись домена $DOMAIN не соответствует внешнему IP сервера, подробнее что делать вы можете ознакомиться тут: https://wiki.yukikras.net/ru/selfsni#a-запись-домена-не-соответствует-внешнему-ip-сервера-или-не-удалось-получить-a-запись-для-домена"
  exit 1
fi

# Проверка, занят ли порт
if ss -tuln | grep -q ":443 "; then
    echo "Порт 443 занят, пожалуйста освободите порт, подробнее что делать вы можете ознакомиться тут: https://wiki.yukikras.net/ru/selfsni#порт-44380-занят-пожалуйста-освободите-порт"
    exit 1
else
    echo "Порт 443 свободен."
fi

if [[ $WITHOUT_80 -eq 0 ]]; then
    if ss -tuln | grep -q ":80 "; then
        echo "Порт 80 занят, пожалуйста освободите порт, подробнее что делать вы можете ознакомиться тут: https://wiki.yukikras.net/ru/selfsni"
        exit 1
    else
        echo "Порт 80 свободен."
    fi
else
    echo "Пропускаем настройку порта 80 (--without-80). Порт 80 останется свободен."
fi

# Установка nginx и certbot
apt update && apt install -y nginx certbot python3-certbot-nginx git

# Скачивание репозитория
TEMP_DIR=$(mktemp -d)
git clone https://github.com/learning-zone/website-templates.git "$TEMP_DIR"

# Выбор случайного сайта
SITE_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | shuf -n 1)
cp -r "$SITE_DIR"/* /var/www/html/

# Выпуск сертификата
if [[ $WITHOUT_80 -eq 1 ]]; then
    echo "Выпускаем сертификат с помощью TLS-ALPN-01 (порт 443), порт 80 не используется..."
    certbot certonly --nginx -d "$DOMAIN" --agree-tos -m "admin@$DOMAIN" --non-interactive --preferred-challenges tls-alpn-01
else
    echo "Выпускаем сертификат обычным способом через HTTP-01..."
    certbot --nginx -d "$DOMAIN" --agree-tos -m "admin@$DOMAIN" --non-interactive
fi

# Настройка конфигурации Nginx
cat > /etc/nginx/sites-enabled/sni.conf <<EOF
server {
EOF

if [[ $WITHOUT_80 -eq 0 ]]; then
cat >> /etc/nginx/sites-enabled/sni.conf <<EOF
    listen 80;
    server_name $DOMAIN;

    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    return 404;
EOF
fi

cat >> /etc/nginx/sites-enabled/sni.conf <<EOF
}

server {
    listen 127.0.0.1:$SPORT ssl http2 proxy_protocol;

    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";

    ssl_stapling on;
    ssl_stapling_verify on;

    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Настройки Proxy Protocol
    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

rm /etc/nginx/sites-enabled/default

# Перезапуск Nginx
nginx -t && systemctl reload nginx

# Показ путей сертификатов
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo ""
echo ""
echo ""
echo ""
echo "Сертификат и ключ расположены в следующих путях:"
echo "Сертификат: $CERT_PATH"
echo "Ключ: $KEY_PATH"
echo ""
echo "В качестве Dest укажите: 127.0.0.1:$SPORT"
echo "В качестве SNI укажите: $DOMAIN"

# Удаление временной директории
rm -rf "$TEMP_DIR"

echo "Скрипт завершён."
