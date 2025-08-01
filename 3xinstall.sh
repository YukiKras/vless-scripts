#!/bin/bash

# Проверяем наличие команды x-ui
if command -v x-ui &> /dev/null; then
    echo "Обнаружена установленная панель x-ui."

    # Запрос у пользователя на переустановку
    read -p "Вы хотите переустановить x-ui? [y/N]: " confirm
    confirm=${confirm,,}  # перевод в нижний регистр

    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        echo "Отмена. Скрипт завершает работу."
        exit 1
    fi

    echo "Удаление x-ui..."
    # Тихое удаление x-ui (если установлен через официальный скрипт)
    /usr/local/x-ui/x-ui uninstall -y &>/dev/null || true
    rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service
    systemctl daemon-reexec
    systemctl daemon-reload
    echo "x-ui успешно удалена. Продолжаем выполнение скрипта..."
fi

# Вывод всех команд кроме диалога — в лог
exec 3>&1  # Сохраняем stdout для сообщений пользователю
LOG_FILE="/var/log/3x-ui_install_log.txt"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# === Порт панели: по умолчанию 8080, а при аргументе extend — ручной выбор ===
if [[ "$1" == "--extend" ]]; then
    read -rp $'\033[0;33mВведите порт для панели (Enter для 8080): \033[0m' USER_PORT
    PORT=${USER_PORT:-8080}

    # === Вопрос о SelfSNI ===
    echo -e "\n${yellow}Хотите установить SelfSNI (поддельный сайт для маскировки)?${plain}"
    read -rp $'\033[0;36mВведите y для установки или нажмите Enter для пропуска: \033[0m' INSTALL_SELFSNI
    if [[ "$INSTALL_SELFSNI" == "y" || "$INSTALL_SELFSNI" == "Y" ]]; then
        echo -e "${green}Устанавливается SelfSNI...${plain}" >&3
        bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh)
    else
        echo -e "${yellow}Установка SelfSNI пропущена.${plain}" >&3
    fi
else
    PORT=8080
    echo -e "${yellow}Порт панели не указан, используется по умолчанию: ${PORT}${plain}" >&3
fi

echo -e "Весь процесс установки будет сохранён в файле: \033[0;36m${LOG_FILE}\033[0m" >&3
echo -e "\n\033[1;34mИдёт установка... Пожалуйста, не закрывайте терминал.\033[0m"

# Генерация
gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}
USERNAME=$(gen_random_string 10)
PASSWORD=$(gen_random_string 10)
WEBPATH=$(gen_random_string 18)

# Проверка root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Ошибка:${plain} скрипт нужно запускать от root" >&3
    exit 1
fi

# Определение ОС
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
else
    echo "Не удалось определить ОС" >&3
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | arm64 | aarch64) echo 'arm64' ;;
        armv7* | arm) echo 'armv7' ;;
        armv6*) echo 'armv6' ;;
        armv5*) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo "unknown" ;;
    esac
}
ARCH=$(arch)

# Проверка GLIBC
glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
required_version="2.32"
if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
    echo -e "${red}GLIBC слишком старая ($glibc_version), требуется >= 2.32.${plain}" >&3
    echo -e "${red}Вам необходимо установить более свежую ОС">&3
    exit 1
fi

# Установка зависимостей
case "${release}" in
    ubuntu | debian | armbian)
        apt-get update > /dev/null 2>&1
        apt-get install -y -q wget curl tar tzdata jq xxd > /dev/null 2>&1
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update > /dev/null 2>&1
        yum install -y -q wget curl tar tzdata jq xxd > /dev/null 2>&1
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update > /dev/null 2>&1
        dnf install -y -q wget curl tar tzdata jq xxd > /dev/null 2>&1
        ;;
    arch | manjaro | parch)
        pacman -Syu --noconfirm > /dev/null 2>&1
        pacman -S --noconfirm wget curl tar tzdata jq xxd > /dev/null 2>&1
        ;;
    opensuse-tumbleweed)
        zypper refresh > /dev/null 2>&1
        zypper install -y wget curl tar timezone jq xxd > /dev/null 2>&1
        ;;
    *)
        apt-get update > /dev/null 2>&1
        apt-get install -y wget curl tar tzdata jq xxd > /dev/null 2>&1
        ;;
esac

# Установка x-ui
cd /usr/local/ || exit 1
tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
wget -q -O x-ui-linux-${ARCH}.tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-${ARCH}.tar.gz

systemctl stop x-ui 2>/dev/null
rm -rf /usr/local/x-ui/
tar -xzf x-ui-linux-${ARCH}.tar.gz
rm -f x-ui-linux-${ARCH}.tar.gz

cd x-ui || exit 1
chmod +x x-ui
[[ "$ARCH" == armv* ]] && mv bin/xray-linux-${ARCH} bin/xray-linux-arm && chmod +x bin/xray-linux-arm
chmod +x x-ui bin/xray-linux-${ARCH}
cp -f x-ui.service /etc/systemd/system/
wget -q -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
chmod +x /usr/local/x-ui/x-ui.sh /usr/bin/x-ui

# Настройка
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" -webBasePath "$WEBPATH" >>"$LOG_FILE" 2>&1
/usr/local/x-ui/x-ui migrate >>"$LOG_FILE" 2>&1

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl enable x-ui >>"$LOG_FILE" 2>&1
systemctl start x-ui >>"$LOG_FILE" 2>&1

# Генерация Reality ключей
KEYS=$(/usr/local/x-ui/bin/xray-linux-${ARCH} x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private" | sed -E 's/.*key:\s*//')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "Public" | sed -E 's/.*key:\s*//')
SHORT_ID=$(head -c 8 /dev/urandom | xxd -p)
UUID=$(cat /proc/sys/kernel/random/uuid)
EMAIL=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)

# === Выбор SNI и DEST с наименьшим пингом ===
DOMAINS=("teamdocs.su" "wikiportal.su" "docscenter.su")
BEST_DOMAIN=""
BEST_PING=9999

echo -e "${green}Оцениваем пинг до рекомендуемых SNI...${plain}" >&3

for domain in "${DOMAINS[@]}"; do
    PING_RESULT=$(ping -c 4 -W 1 "$domain" 2>/dev/null | awk -F'time=' '/time=/{sum+=$2} END{if(NR>0) printf "%.2f", sum/NR}')
    if [[ -n "$PING_RESULT" ]]; then
        echo -e "  $domain: ${PING_RESULT} ms" >&3
        PING_MS=$(printf "%.0f" "$PING_RESULT")
        if [[ "$PING_MS" -lt "$BEST_PING" ]]; then
            BEST_PING=$PING_MS
            BEST_DOMAIN=$domain
        fi
    else
        echo -e "  $domain: \033[0;31mнедоступен\033[0m" >&3
    fi
done

if [[ -z "$BEST_DOMAIN" ]]; then
    echo -e "${red}Не удалось определить доступный домен. Используем teamdocs.su по умолчанию.${plain}" >&3
    BEST_DOMAIN="teamdocs.su"
fi

echo -e "${green}Выбран домен с наименьшим пингом: ${BEST_DOMAIN}${plain}" >&3

# === Аутентификация в x-ui API ===
COOKIE_JAR=$(mktemp)

# === Авторизация через cookie ===
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/${WEBPATH}/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}")

if ! echo "$LOGIN_RESPONSE" | grep -q '"success":true'; then
    echo -e "${red}Ошибка авторизации через cookie.${plain}" >&3
    echo "$LOGIN_RESPONSE" >&3
    exit 1
fi

# === Формирование JSON ===
SETTINGS_JSON=$(jq -nc --arg uuid "$UUID" --arg email "$EMAIL" '{
  clients: [
    {
      id: $uuid,
      flow: "xtls-rprx-vision",
      email: $email
    }
  ],
  decryption: "none"
}')

STREAM_SETTINGS_JSON=$(jq -nc --arg pk "$PRIVATE_KEY" --arg sid "$SHORT_ID" --arg dest "${BEST_DOMAIN}:443" --arg sni "$BEST_DOMAIN" '{
  network: "tcp",
  security: "reality",
  realitySettings: {
    show: false,
    dest: $dest,
    xver: 0,
    serverNames: [$sni],
    privateKey: $pk,
    shortIds: [$sid]
  }
}')

SNIFFING_JSON=$(jq -nc '{
  enabled: true,
  destOverride: ["http", "tls"]
}')

# === Отправка инбаунда через API с cookie ===
ADD_RESULT=$(curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/${WEBPATH}/panel/api/inbounds/add" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc \
    --argjson settings "$SETTINGS_JSON" \
    --argjson stream "$STREAM_SETTINGS_JSON" \
    --argjson sniffing "$SNIFFING_JSON" \
    '{
      enable: true,
      remark: "reality443-auto",
      listen: "0.0.0.0",
      port: 443,
      protocol: "vless",
      settings: ($settings | tostring),
      streamSettings: ($stream | tostring),
      sniffing: ($sniffing | tostring)
    }')"
)

# Очистка временных cookie
rm -f "$COOKIE_JAR"

# Проверка
if echo "$ADD_RESULT" | grep -q '"success":true'; then
    echo -e "${green}Инбаунд успешно добавлен через API.${plain}" >&3

    # Перезапуск x-ui
    systemctl restart x-ui >>"$LOG_FILE" 2>&1

    SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:443?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&sni=teamdocs.su&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#${EMAIL}"

    echo -e "\n\033[0;32mVLESS Reality успешно создан!\033[0m" >&3
    echo -e "\033[1;36mВаш VPN ключ, его можно использовать сразу на нескольких устройствах:\033[0m" >&3
    echo -e ""
    echo -e "${VLESS_LINK}" >&3
    echo -e ""
    echo -e "С инструкцией по созданию дополнительных Vless ключей вы можете ознакомиться тут: https://wiki.yukikras.net/ru/razvertyvanie-proksi-protokola-vless-s-pomoshyu-3x-ui#%D0%BA%D0%B0%D0%BA-%D0%B4%D0%BE%D0%B1%D0%B0%D0%B2%D0%BB%D1%8F%D1%82%D1%8C-%D0%BD%D0%BE%D0%B2%D1%8B%D1%85-%D0%BA%D0%BB%D0%B8%D0%B5%D0%BD%D1%82%D0%BE%D0%B2"
    echo -e ""

    {
    echo "Ваш VPN ключ, его можно использовать сразу на нескольких устройствах:"
    echo ""
    echo "$VLESS_LINK"
    echo ""
    echo "С инструкцией по созданию дополнительных Vless ключей вы можете ознакомиться тут: https://wiki.yukikras.net/ru/razvertyvanie-proksi-protokola-vless-s-pomoshyu-3x-ui#%D0%BA%D0%B0%D0%BA-%D0%B4%D0%BE%D0%B1%D0%B0%D0%B2%D0%BB%D1%8F%D1%82%D1%8C-%D0%BD%D0%BE%D0%B2%D1%8B%D1%85-%D0%BA%D0%BB%D0%B8%D0%B5%D0%BD%D1%82%D0%BE%D0%B2"
    echo ""
    } >> /root/3x-ui.txt
else
    echo -e "${red}Ошибка при добавлении инбаунда через API:${plain}" >&3
    echo "$ADD_RESULT" >&3
fi

# === Общая финальная информация (всегда выводится) ===
SERVER_IP=${SERVER_IP:-$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)}

echo -e "\n\033[1;32mПанель управления 3X-UI (https://github.com/MHSanaei/3x-ui) доступна по следующим данным:\033[0m" >&3
echo -e "Адрес панели: \033[1;36mhttp://${SERVER_IP}:${PORT}/${WEBPATH}\033[0m" >&3
echo -e "Логин:        \033[1;33m${USERNAME}\033[0m" >&3
echo -e "Пароль:       \033[1;33m${PASSWORD}\033[0m" >&3

echo -e "\nИнструкции по настройке VPN приложений вы сможете найти здесь:" >&3
echo -e "\033[1;34mhttps://wiki.yukikras.net/ru/nastroikavpn\033[0m" >&3

echo -e "\nВсе данные сохранены в файл: \033[1;36m/root/3x-ui.txt\033[0m" >&3
echo -e "Для повторного просмотра информации используйте команду:" >&3
echo -e "" >&3
echo -e "\033[0;36mcat /root/3x-ui.txt\033[0m" >&3
echo -e "" >&3

{
  echo "Панель управления 3X-UI (https://github.com/MHSanaei/3x-ui) доступна по следующим данным:"
  echo "Адрес панели - http://${SERVER_IP}:${PORT}/${WEBPATH}"
  echo "Логин:         ${USERNAME}"
  echo "Пароль:        ${PASSWORD}"
  echo ""
  echo "Инструкции по настройке VPN приложений:"
  echo "https://wiki.yukikras.net/ru/nastroikavpn"
} >> /root/3x-ui.txt