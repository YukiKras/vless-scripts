#!/bin/bash

# Проверяем, запускается ли скрипт с правами root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами root."
  exit 1
fi

# Устанавливаем nginx
apt update && apt install -y nginx

# Создаем конфигурацию для reverse proxy
cat > /etc/nginx/sites-available/reverse-proxy.conf <<EOF
server {
    listen 8888;

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

# Получаем публичный IP сервера
public_ip=$(curl -s ifconfig.me)
if [ -z "$public_ip" ]; then
  echo "Не удалось определить публичный IP-адрес. Проверьте подключение к интернету."
  exit 1
fi

# Выводим сообщение пользователю
echo "Ваша панель Marzban доступна по ссылке: http://$public_ip:8888/dashboard"
