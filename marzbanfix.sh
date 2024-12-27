#!/bin/bash

# Проверяем, запускается ли скрипт с правами root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами root."
  exit 1
fi

# Устанавливаем nginx
apt update && apt install -y nginx

# Получаем публичный IP сервера
public_ip=$(curl -s ifconfig.me)
if [ -z "$public_ip" ]; then
  echo "Не удалось определить публичный IP-адрес. Проверьте подключение к интернету."
  exit 1
fi

# Генерация самоподписного сертификата
mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "/etc/nginx/ssl/$public_ip.key.pem" \
  -out "/etc/nginx/ssl/$public_ip.pem" \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=Example Company/OU=IT Department/CN=$public_ip"


# Создаем конфигурацию для reverse proxy
cat > /etc/nginx/sites-available/reverse-proxy.conf <<EOF
server {
    listen 8888 ssl;
    server_name $public_ip;

    # Путь к SSL-сертификатам
    ssl_certificate /etc/nginx/ssl/$public_ip.pem;
    ssl_certificate_key /etc/nginx/ssl/$public_ip.key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location ~* /(sub|dashboard|statics|api|docs|redoc|openapi.json) {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Активируем новую конфигурацию
ln -s /etc/nginx/sites-available/reverse-proxy.conf /etc/nginx/sites-enabled/reverse-proxy.conf

# Проверяем конфигурацию nginx
nginx -t
if [ $? -ne 0 ]; then
  echo "Ошибка в конфигурации nginx. Проверьте файл /etc/nginx/sites-available/reverse-proxy.conf"
  exit 1
fi

# Перезапускаем nginx
systemctl restart nginx

# Выводим сообщение пользователю
echo ""
echo ""
echo ""
echo "Ваша панель Marzban доступна по ссылке: https://$public_ip:8888/dashboard"
echo ""
echo ""
echo ""
