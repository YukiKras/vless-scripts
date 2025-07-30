#!/bin/bash

echo "Скрипт начал свою работу, пожалуйста до окончанию его работы не закрывайте терминал..."

# Проверка, свободен ли порт 8080
if lsof -iTCP:8080 -sTCP:LISTEN -t >/dev/null ; then
  echo "Порт 8080 уже занят. Скрипт завершён."
  exit 1
fi

# Проверка, активен ли ufw
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS=$(ufw status | grep -i "Status: active")
  if [[ -n "$UFW_STATUS" ]]; then
    echo "UFW активен. Добавляем правило для порта 8080..."
    ufw allow 8080/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw allow 8443/tcp >/dev/null
    echo "Перезапуск UFW..."
    ufw reload >/dev/null
  else
    echo "UFW установлен, но не активен."
  fi
else
  echo "UFW не установлен."
fi

# Изменение порта панели на 8080 через x-ui (пункт 9)
(
  sleep 1
  echo 9         # Change panel port
  sleep 1
  echo 8080      # New port
  sleep 1
  echo y         # Confirm
  sleep 1
) | x-ui > /dev/null

# Извлечение текущего Access URL через пункт 10
ACCESS_URL=$(
  ( 
    sleep 1
    echo 10       # Show current panel settings
    sleep 2
  ) | x-ui 2>/dev/null | grep -i "Access URL" | awk -F': ' '{print $2}'
)

# Проверка, удалось ли получить ссылку
if [[ -z "$ACCESS_URL" ]]; then
  echo "Не удалось получить Access URL панели."
  exit 1
fi

clear
echo
echo "Панель x-ui теперь доступна по следующей ссылке:"
echo "$ACCESS_URL"
echo
echo "Используйте предыдущие логин и пароль для входа."

# Обновление ссылки в /root/3x-ui.txt при наличии файла
if [[ -f /root/3x-ui.txt ]]; then
  echo
  echo "Обнаружен файл /root/3x-ui.txt — обновляем ссылку на панель..."
  sed -i -E "s#(URL - |Ссылка - |Адрес панели -)[^\s]+#\1$ACCESS_URL#g" /root/3x-ui.txt
  echo "Ссылка успешно обновлена в /root/3x-ui.txt"
fi
