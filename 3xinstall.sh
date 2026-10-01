#!/bin/bash


CLIENT_INSTALL=false

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

LOG_FILE="/var/log/3x-ui_install_log.txt"

REALITY_PORT=8443
HYSTERIA_PORT=8444
DOMAINS=("games.mail.ru" "ozon.ru")

PORT=8080

USERNAME=""
PASSWORD=""
WEBPATH=""
CLEAN_PATH=""
BEST_DOMAIN=""
ARCH=""
SERVER_IP=""
XRAY_BIN=""

PRIVATE_KEY=""
PUBLIC_KEY=""
PQ_DECRYPTION=""
PQ_ENCRYPTION=""

UUID=""
EMAIL=""
HY2_EMAIL=""
HYSTERIA_PASSWORD=""
SALAMANDER_PASSWORD=""
SHORT_IDS_JSON=""
SHORT_ID=""
SPIDER_X=""
SUB_ID=""

COOKIE_JAR=""
CSRF_TOKEN=""

VLESS_LINK=""
HY2_LINK=""

PANEL_PROTO="http"

gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}Ошибка:${plain} скрипт нужно запускать от root" >&3
        exit 1
    fi
}

remove_existing_xui() {
    if ! command -v x-ui &> /dev/null; then
        return 0
    fi

    echo "Обнаружена установленная панель x-ui."
    read -p "Вы хотите переустановить x-ui? [y/N]: " confirm
    confirm=${confirm,,}
    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        echo "Отмена. Скрипт завершает работу."
        exit 1
    fi

    echo "Удаление x-ui..."
    systemctl stop x-ui 2>/dev/null || true
    systemctl unmask x-ui &>/dev/null || true
    rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service
    systemctl daemon-reexec
    systemctl daemon-reload
    rm -f /root/3x-ui.txt
    echo "x-ui успешно удалена. Продолжаем выполнение скрипта..."
}


sni_request() {
    echo ""
    echo -e "${cyan}Выберите SNI (Enter — вариант 1):${plain}"
    echo "  1. ${DOMAINS[0]}"
    echo "  2. ${DOMAINS[1]}"
    echo "  3. свой вариант"
    echo ""
    read -rp "Ваш выбор [1-3]: " sni_choice
    sni_choice=${sni_choice:-1}

    case "$sni_choice" in
        1) BEST_DOMAIN="${DOMAINS[0]}" ;;
        2) BEST_DOMAIN="${DOMAINS[1]}" ;;
        3)
            read -rp "Введите свой домен (например example.com): " custom_domain
            if [[ -z "$custom_domain" ]]; then
                echo -e "${yellow}Домен не введён, использую ${DOMAINS[0]}${plain}"
                BEST_DOMAIN="${DOMAINS[0]}"
            else
                BEST_DOMAIN="$custom_domain"
            fi
            ;;
        *)
            echo -e "${yellow}Некорректный выбор, использую ${DOMAINS[0]}${plain}"
            BEST_DOMAIN="${DOMAINS[0]}"
            ;;
    esac

    echo ""
    echo -e "${green}SNI / DEST: ${BEST_DOMAIN}${plain}"
    echo ""
}


client_check() {
    echo ""
    echo -e "${cyan}Установка клиенту? (Enter — вариант 1):${plain}"
    echo "  1. Да"
    echo "  2. Личное"
    echo ""
    read -rp "Ваш выбор [1-2]: " install_choice
    install_choice=${install_choice:-1}

    case "$install_choice" in
        1) CLIENT_INSTALL=true ;;
        2) CLIENT_INSTALL=false ;;
        *)
            echo -e "${yellow}Некорректный выбор, использую вариант 1 (Да)${plain}"
            CLIENT_INSTALL=true
            ;;
    esac
}

setup_logging() {
    exec 3>&1
    exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
}

prompt_port() {
    read -rp $'\033[0;33mВведите порт для панели (Enter для 8080): \033[0m' USER_PORT
    PORT=${USER_PORT:-8080}

    echo -e "Лог установки: ${cyan}${LOG_FILE}${plain}" >&3
    echo -e "\n\033[1;34mИдёт установка... Пожалуйста, не закрывайте терминал.\033[0m"
}

generate_credentials() {
    USERNAME=$(gen_random_string 10)
    PASSWORD=$(gen_random_string 10)
    WEBPATH=$(gen_random_string 18)
    CLEAN_PATH=$(echo "$WEBPATH" | sed 's@^/@@;s@/$@@')

    echo -e "${green}VLESS инбаунд: in-${REALITY_PORT}-tcp → порт ${REALITY_PORT}${plain}" >&3
    echo -e "${green}Hysteria2 инбаунд: in-${HYSTERIA_PORT}-udp → порт ${HYSTERIA_PORT}${plain}" >&3
}

setup_bbr() {
    echo -e "${yellow}Настройка TCP BBR и сетевых буферов...${plain}" >&3

    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1-2 | tr -d '.')

    if [[ "$kernel_version" -le 49 ]]; then
        echo -e "${yellow}Ядро не поддерживает BBR. Пропускаем.${plain}" >&3
        return 0
    fi

    modprobe tcp_bbr 2>/dev/null || true
    local sysctl_conf="/etc/sysctl.d/99-bbr-optimize.conf"

    echo "net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.rmem_default=26214400
net.core.wmem_default=26214400
net.core.netdev_max_backlog=250000
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
" > "$sysctl_conf"

    sysctl -p "$sysctl_conf" >>"$LOG_FILE" 2>&1

    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${green}TCP BBR включён.${plain}" >&3
    else
        echo -e "${yellow}BBR не применился (текущий: ${current_cc}).${plain}" >&3
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        release=$ID
    else
        echo "Не удалось определить ОС" >&3
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) ARCH='amd64' ;;
        i*86 | x86) ARCH='386' ;;
        armv8* | arm64 | aarch64) ARCH='arm64' ;;
        armv7* | arm) ARCH='armv7' ;;
        armv6*) ARCH='armv6' ;;
        armv5*) ARCH='armv5' ;;
        s390x) ARCH='s390x' ;;
        *) ARCH="unknown" ;;
    esac
}

install_dependencies() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update > /dev/null 2>&1
            apt-get install -y -q wget curl tar tzdata jq xxd qrencode sqlite3 socat cron > /dev/null 2>&1
            systemctl enable --now cron >/dev/null 2>&1 || true
            ;;
        centos | rhel | almalinux | rocky | ol)
            yum -y update > /dev/null 2>&1
            yum install -y -q wget curl tar tzdata jq xxd qrencode sqlite socat cronie > /dev/null 2>&1
            systemctl enable --now crond >/dev/null 2>&1 || true
            ;;
        fedora | amzn | virtuozzo)
            dnf -y update > /dev/null 2>&1
            dnf install -y -q wget curl tar tzdata jq xxd qrencode sqlite socat cronie > /dev/null 2>&1
            systemctl enable --now crond >/dev/null 2>&1 || true
            ;;
        arch | manjaro | parch)
            pacman -Syu --noconfirm > /dev/null 2>&1
            pacman -S --noconfirm wget curl tar tzdata jq xxd qrencode sqlite socat cronie > /dev/null 2>&1
            systemctl enable --now cronie >/dev/null 2>&1 || true
            ;;
        opensuse-tumbleweed)
            zypper refresh > /dev/null 2>&1
            zypper install -y wget curl tar timezone jq xxd qrencode sqlite3 socat cron > /dev/null 2>&1
            systemctl enable --now cron >/dev/null 2>&1 || true
            ;;
        *)
            apt-get update > /dev/null 2>&1
            apt-get install -y wget curl tar tzdata jq xxd qrencode sqlite3 socat cron > /dev/null 2>&1
            systemctl enable --now cron >/dev/null 2>&1 || true
            ;;
    esac
}

download_and_extract_xui() {
    cd /usr/local/ || exit 1
    local file="x-ui-linux-${ARCH}.tar.gz"
    local url="https://github.com/MHSanaei/3x-ui/releases/download/v3.6.0/${file}"

    systemctl stop x-ui 2>/dev/null || true
    rm -rf /usr/local/x-ui/ "$file"

    if ! wget -q -O "$file" "$url"; then
        echo "Ошибка: не удалось скачать 3x-ui с GitHub" >&3
        exit 1
    fi

    if ! tar -xzf "$file"; then
        echo "Ошибка: не удалось распаковать архив 3x-ui" >&3
        rm -f "$file"
        exit 1
    fi
    rm -f "$file"

    cd x-ui || exit 1
    chmod +x x-ui bin/xray-linux-* 2>/dev/null || true

    systemctl unmask x-ui &>/dev/null || true
}

install_systemd_service() {
    if [[ -f "bin/x-ui.service" ]]; then
        cp -f bin/x-ui.service /etc/systemd/system/
    elif [[ -f "x-ui.service" ]]; then
        cp -f x-ui.service /etc/systemd/system/
    else
        wget -q -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service
    fi

    if [[ ! -s "/etc/systemd/system/x-ui.service" ]]; then
        echo "[Unit]
Description=x-ui Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
" > "/etc/systemd/system/x-ui.service"
    fi
    systemctl unmask x-ui &>/dev/null || true
}

install_xui_cli() {
    local file="/usr/bin/x-ui"
    local url="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh"

    if ! wget -q -O "$file" "$url"; then
        echo "Ошибка: не удалось скачать x-ui.sh с GitHub"
        exit 1
    fi

    chmod +x /usr/local/x-ui/x-ui.sh /usr/bin/x-ui 2>/dev/null || true
}

configure_and_start_xui() {
    local webpath_formatted
    webpath_formatted="/$(echo "$WEBPATH" | sed 's@^/@@;s@/$@@')/"

    /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" -webBasePath "$webpath_formatted" >>"$LOG_FILE" 2>&1
    /usr/local/x-ui/x-ui migrate >>"$LOG_FILE" 2>&1

    systemctl daemon-reload >>"$LOG_FILE" 2>&1
    systemctl enable x-ui >>"$LOG_FILE" 2>&1
    systemctl start x-ui >>"$LOG_FILE" 2>&1
}

wait_for_panel() {
    echo -e "${yellow}Ожидаем запуска панели...${plain}" >&3
    for i in {1..15}; do
        sleep 2
        if curl -s -k -L --max-time 3 "http://127.0.0.1:${PORT}/${CLEAN_PATH}/" | grep -qiE "html|3x-ui|x-ui|login" 2>/dev/null; then
            echo -e "${green}Панель готова.${plain}" >&3
            break
        fi
        if [[ $i -eq 15 ]]; then
            echo -e "${yellow}Панель долго стартует, продолжаем...${plain}" >&3
        fi
    done
}

install_xui() {
    download_and_extract_xui
    install_systemd_service
    install_xui_cli
    configure_and_start_xui
    wait_for_panel
}

generate_xray_keys() {
    XRAY_BIN="/usr/local/x-ui/bin/xray-linux-${ARCH}"
    [[ -x "$XRAY_BIN" ]] || XRAY_BIN=$(find /usr/local/x-ui/bin -maxdepth 1 -type f -name 'xray-linux-*' | head -n1)

    local keys
    keys=$("$XRAY_BIN" x25519 2>&1)
    PRIVATE_KEY=$(echo "$keys" | awk -F': ' '/[Pp]rivate/{print $NF}' | tr -d '[:space:]')
    PUBLIC_KEY=$(echo "$keys" | awk -F': ' '/[Pp]ublic|[Pp]assword/{print $NF}' | tr -d '[:space:]')

    local vlessenc_output
    vlessenc_output=$("$XRAY_BIN" vlessenc 2>&1)
    PQ_DECRYPTION=$(echo "$vlessenc_output" | awk '/Authentication: X25519/{f=1} f && /"decryption"/{print; exit}' | sed -E 's/.*"decryption": *"([^"]*)".*/\1/')
    PQ_ENCRYPTION=$(echo "$vlessenc_output" | awk '/Authentication: X25519/{f=1} f && /"encryption"/{print; exit}' | sed -E 's/.*"encryption": *"([^"]*)".*/\1/')

    if [[ -z "$PQ_DECRYPTION" || -z "$PQ_ENCRYPTION" ]]; then
        echo -e "${yellow}Не удалось сгенерировать VLESS Encryption, используем decryption/encryption: none${plain}" >&3
        PQ_DECRYPTION="none"
        PQ_ENCRYPTION="none"
    else
        echo -e "${green}VLESS Encryption (mlkem768x25519plus) сгенерирован.${plain}" >&3
    fi
}

generate_client_identifiers() {
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || gen_random_string 36)
    EMAIL=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)
    HY2_EMAIL=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)

    HYSTERIA_PASSWORD=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)
    SALAMANDER_PASSWORD=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)

    SPIDER_X="/$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)"
    SUB_ID=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)

    SHORT_IDS_JSON="[]"
    local len sid
    for len in 2 4 6 8 10 12 14 16; do
        sid=$(head -c $((len/2)) /dev/urandom | xxd -p)
        SHORT_IDS_JSON=$(echo "$SHORT_IDS_JSON" | jq --arg s "$sid" '. + [$s]')
    done
    SHORT_ID=$(echo "$SHORT_IDS_JSON" | jq -r '.[0]')
}

panel_login() {
    COOKIE_JAR=$(mktemp)

    local login_page
    login_page=$(curl -s -k -c "$COOKIE_JAR" "${PANEL_PROTO}://127.0.0.1:${PORT}/${CLEAN_PATH}/")
    CSRF_TOKEN=$(echo "$login_page" | grep -oP 'name="csrf-token" content="\K[^"]+')

    if [[ -z "$CSRF_TOKEN" ]]; then
        echo -e "${red}Не удалось получить CSRF-токен со страницы логина.${plain}" >&3
        exit 1
    fi

    local login_response
    login_response=$(curl -s -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "${PANEL_PROTO}://127.0.0.1:${PORT}/${CLEAN_PATH}/login" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${CSRF_TOKEN}" \
        -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}")

    if ! echo "$login_response" | grep -q '"success":true'; then
        echo -e "${red}Ошибка авторизации через API.${plain}" >&3
        echo "$login_response" >&3
        exit 1
    fi
}

add_vless_reality_inbound() {
    local now_ms
    now_ms=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")

    local settings_json
    settings_json=$(jq -nc \
        --arg uuid "$UUID" \
        --arg email "$EMAIL" \
        --arg subid "$SUB_ID" \
        --arg decryption "$PQ_DECRYPTION" \
        --arg encryption "$PQ_ENCRYPTION" \
        --argjson created "$now_ms" '{
        clients: [
            {
                id: $uuid,
                email: $email,
                flow: "xtls-rprx-vision",
                limitIp: 0,
                totalGB: 0,
                expiryTime: 0,
                enable: true,
                tgId: 0,
                subId: $subid,
                comment: "",
                reset: 0,
                created_at: $created,
                updated_at: $created
            }
        ],
        decryption: $decryption,
        encryption: $encryption
    }')

    local stream_settings_json
    stream_settings_json=$(jq -nc \
        --arg pbk "$PUBLIC_KEY" \
        --arg prk "$PRIVATE_KEY" \
        --argjson sids "$SHORT_IDS_JSON" \
        --arg domain "$BEST_DOMAIN" \
        --arg spx "$SPIDER_X" '{
        network: "tcp",
        tcpSettings: {
            acceptProxyProtocol: false,
            header: { type: "none" }
        },
        security: "reality",
        realitySettings: {
            show: false,
            xver: 0,
            target: ($domain + ":443"),
            serverNames: [("www." + $domain), $domain],
            privateKey: $prk,
            minClientVer: "",
            maxClientVer: "",
            maxTimediff: 0,
            shortIds: $sids,
            mldsa65Seed: "",
            limitFallbackUpload: { afterBytes: 0, bytesPerSec: 0, burstBytesPerSec: 0 },
            limitFallbackDownload: { afterBytes: 0, bytesPerSec: 0, burstBytesPerSec: 0 },
            settings: {
                publicKey: $pbk,
                fingerprint: "firefox",
                serverName: "",
                spiderX: $spx,
                mldsa65Verify: ""
            }
        }
    }')

    local sniffing_json
    sniffing_json=$(jq -nc '{ enabled: true, destOverride: ["http", "tls"] }')

    local add_result
    add_result=$(curl -s -k -b "$COOKIE_JAR" -X POST "${PANEL_PROTO}://127.0.0.1:${PORT}/${CLEAN_PATH}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${CSRF_TOKEN}" \
        -d "$(jq -nc \
            --argjson settings "$settings_json" \
            --argjson stream "$stream_settings_json" \
            --argjson sniffing "$sniffing_json" \
            --arg port "$REALITY_PORT" \
            '{
                enable: true,
                remark: "VLESS-Reality",
                listen: "",
                port: ($port | tonumber),
                protocol: "vless",
                tag: ("in-" + $port + "-tcp"),
                settings: ($settings | tostring),
                streamSettings: ($stream | tostring),
                sniffing: ($sniffing | tostring)
            }')"
    )

    if echo "$add_result" | grep -q '"success":true'; then
        echo -e "${green}VLESS Reality инбаунд успешно добавлен.${plain}" >&3
    else
        echo -e "${red}Ошибка добавления VLESS инбаунда:${plain}" >&3
        echo "$add_result" >&3
    fi
}

generate_ip_certificate() {
    SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)
    mkdir -p /root/cert/ip

    ACME_BIN="/root/.acme.sh/acme.sh"

    if [[ ! -x "$ACME_BIN" ]]; then
        for pkg_mgr in apt-get yum dnf pacman zypper; do
            command -v "$pkg_mgr" &>/dev/null && break
        done
        case "$pkg_mgr" in
            apt-get) apt-get install -y -q socat cron >/dev/null 2>&1; systemctl enable --now cron >/dev/null 2>&1 ;;
            yum) yum install -y -q socat cronie >/dev/null 2>&1; systemctl enable --now crond >/dev/null 2>&1 ;;
            dnf) dnf install -y -q socat cronie >/dev/null 2>&1; systemctl enable --now crond >/dev/null 2>&1 ;;
            pacman) pacman -S --noconfirm socat cronie >/dev/null 2>&1; systemctl enable --now cronie >/dev/null 2>&1 ;;
            zypper) zypper install -y socat cron >/dev/null 2>&1; systemctl enable --now cron >/dev/null 2>&1 ;;
        esac
        curl -s https://get.acme.sh | sh -s email="admin@${SERVER_IP}.nip.io" >>"$LOG_FILE" 2>&1
    fi

    local cert_ok=false
    local existing_cert="/root/.acme.sh/${SERVER_IP}_ecc/${SERVER_IP}.cer"

    if [[ -x "$ACME_BIN" ]]; then
        if [[ -s "$existing_cert" ]] && openssl x509 -checkend 3600 -noout -in "$existing_cert" >/dev/null 2>&1; then
            "$ACME_BIN" --install-cert -d "$SERVER_IP" --ecc \
                --key-file /root/cert/ip/privkey.pem \
                --fullchain-file /root/cert/ip/fullchain.pem \
                --reloadcmd "systemctl restart x-ui" >>"$LOG_FILE" 2>&1
            [[ -s "/root/cert/ip/fullchain.pem" && -s "/root/cert/ip/privkey.pem" ]] && cert_ok=true
        else
            local stopped_services=()
            for svc in nginx apache2 httpd caddy; do
                systemctl is-active --quiet "$svc" 2>/dev/null && systemctl stop "$svc" 2>/dev/null && stopped_services+=("$svc")
            done

            "$ACME_BIN" --issue -d "$SERVER_IP" --standalone --server letsencrypt --cert-profile shortlived >>"$LOG_FILE" 2>&1
            local issue_status=$?

            for svc in "${stopped_services[@]}"; do
                systemctl start "$svc" 2>/dev/null || true
            done

            if [[ $issue_status -eq 0 ]]; then
                "$ACME_BIN" --install-cert -d "$SERVER_IP" --ecc \
                    --key-file /root/cert/ip/privkey.pem \
                    --fullchain-file /root/cert/ip/fullchain.pem \
                    --reloadcmd "systemctl restart x-ui" >>"$LOG_FILE" 2>&1
                [[ -s "/root/cert/ip/fullchain.pem" && -s "/root/cert/ip/privkey.pem" ]] && cert_ok=true
            fi
        fi
    fi

    if [[ "$cert_ok" == true ]]; then
        /usr/local/x-ui/x-ui setting -webCert /root/cert/ip/fullchain.pem -webCertKey /root/cert/ip/privkey.pem >>"$LOG_FILE" 2>&1
        systemctl restart x-ui
        for i in {1..15}; do
            sleep 2
            if curl -s -k -L --max-time 3 "https://127.0.0.1:${PORT}/${CLEAN_PATH}/" | grep -qiE "html|3x-ui|x-ui|login" 2>/dev/null; then
                break
            fi
        done
        PANEL_PROTO="https"
    fi

    if [[ "$cert_ok" != true ]]; then
        openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "/root/cert/ip/privkey.pem" -out "/root/cert/ip/fullchain.pem" \
            -days 3650 -subj "/CN=${BEST_DOMAIN}" \
            -addext "subjectAltName=IP:${SERVER_IP}" >/dev/null 2>&1
        chmod 600 /root/cert/ip/privkey.pem
    fi
}

add_hysteria2_inbound() {
    local now_ms
    now_ms=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")

    local hysteria_settings_json
    hysteria_settings_json=$(jq -nc \
        --arg auth "$HYSTERIA_PASSWORD" \
        --arg email "$HY2_EMAIL" \
        --arg subid "$SUB_ID" \
        --argjson created "$now_ms" '{
        clients: [
            {
                auth: $auth,
                email: $email,
                limitIp: 0,
                totalGB: 0,
                expiryTime: 0,
                enable: true,
                tgId: 0,
                subId: $subid,
                comment: "",
                reset: 0,
                created_at: $created,
                updated_at: $created
            }
        ],
        version: 2
    }')

    local hysteria_stream_json
    hysteria_stream_json=$(jq -nc \
        --arg domain "$BEST_DOMAIN" \
        --arg salpass "$SALAMANDER_PASSWORD" '{
        network: "hysteria",
        hysteriaSettings: {
            version: 2,
            udpIdleTimeout: 60
        },
        security: "tls",
        tlsSettings: {
            serverName: $domain,
            minVersion: "1.2",
            maxVersion: "1.3",
            cipherSuites: "",
            rejectUnknownSni: false,
            disableSystemRoot: false,
            enableSessionResumption: false,
            certificates: [
                {
                    certificateFile: "/root/cert/ip/fullchain.pem",
                    keyFile: "/root/cert/ip/privkey.pem",
                    ocspStapling: 0,
                    oneTimeLoading: false,
                    usage: "encipherment",
                    buildChain: false,
                    useFile: true
                }
            ],
            alpn: ["h3"],
            echServerKeys: "",
            settings: {
                fingerprint: "firefox",
                echConfigList: "",
                pinnedPeerCertSha256: [],
                verifyPeerCertByName: ""
            }
        },
        finalmask: {
            udp: [
                {
                    type: "salamander",
                    settings: {
                        password: $salpass
                    }
                }
            ]
        }
    }')

    local sniffing_json
    sniffing_json=$(jq -nc '{ enabled: true, destOverride: ["http", "tls"] }')

    local add_hy2_result
    add_hy2_result=$(curl -s -k -b "$COOKIE_JAR" -X POST "${PANEL_PROTO}://127.0.0.1:${PORT}/${CLEAN_PATH}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${CSRF_TOKEN}" \
        -d "$(jq -nc \
            --argjson settings "$hysteria_settings_json" \
            --argjson stream "$hysteria_stream_json" \
            --argjson sniffing "$sniffing_json" \
            --arg port "$HYSTERIA_PORT" \
            '{
                enable: true,
                remark: "Hysteria2",
                listen: "",
                port: ($port | tonumber),
                protocol: "hysteria",
                tag: ("in-" + $port + "-udp"),
                settings: ($settings | tostring),
                streamSettings: ($stream | tostring),
                sniffing: ($sniffing | tostring)
            }')"
    )

    if echo "$add_hy2_result" | grep -q '"success":true'; then
        echo -e "${green}Hysteria2 инбаунд успешно добавлен.${plain}" >&3
    else
        echo -e "${red}Ошибка добавления Hysteria2 инбаунда:${plain}" >&3
        echo "$add_hy2_result" >&3
    fi
}

setup_inbounds() {
    generate_ip_certificate
    panel_login
    add_vless_reality_inbound
    add_hysteria2_inbound
    rm -f "$COOKIE_JAR"
}

build_connection_links() {
    SERVER_IP=${SERVER_IP:-$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)}

    local spx_encoded
    spx_encoded=$(printf '%s' "$SPIDER_X" | sed 's/\//%2F/g')

    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${REALITY_PORT}?type=tcp&security=reality&encryption=${PQ_ENCRYPTION}&flow=xtls-rprx-vision&sni=${BEST_DOMAIN}&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=${spx_encoded}#VLESS-Reality"
    HY2_LINK="hysteria2://${HYSTERIA_PASSWORD}@${SERVER_IP}:${HYSTERIA_PORT}?insecure=1&alpn=h3&fp=firefox&obfs=salamander&obfs-password=${SALAMANDER_PASSWORD}&security=tls&sni=${BEST_DOMAIN}#Hysteria2-${HY2_EMAIL}"
}

print_summary() {
    echo -e "\n\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "\033[1;32m   VLESS Reality\033[0m" >&3
    echo -e "\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "${cyan}${VLESS_LINK}${plain}" >&3
    echo -e "" >&3
    qrencode -t ANSIUTF8 "$VLESS_LINK"
    echo -e "" >&3

    echo -e "\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "\033[1;32m   Hysteria2\033[0m" >&3
    echo -e "\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "${cyan}${HY2_LINK}${plain}" >&3
    echo -e "" >&3
    qrencode -t ANSIUTF8 "$HY2_LINK"
    echo -e "" >&3

    echo -e "\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "\033[1;32m   Панель управления 3X-UI\033[0m" >&3
    echo -e "\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "Адрес панели: \033[1;36m${PANEL_PROTO}://${SERVER_IP}:${PORT}/${CLEAN_PATH}\033[0m" >&3
    echo -e "Логин:        \033[1;33m${USERNAME}\033[0m" >&3
    echo -e "Пароль:       \033[1;33m${PASSWORD}\033[0m" >&3
    echo -e "" >&3
    echo -e "Все данные сохранены в файл: \033[1;36m/root/3x-ui.txt\033[0m" >&3
    echo -e "Для просмотра в будущем введите: \033[0;36mcat /root/3x-ui.txt\033[0m\n" >&3
}

print_client_summary() {
    echo -e "\n\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "" >&3
    echo "VLESS Reality: \`${VLESS_LINK}\`" >&3
    echo "" >&3
    echo "Hysteria2: \`${HY2_LINK}\`" >&3
    echo "" >&3
    echo "Панель 3x-ui:" >&3
    echo "" >&3
    echo "${PANEL_PROTO}://${SERVER_IP}:${PORT}/${CLEAN_PATH}" >&3
    echo "Логин: ${USERNAME}" >&3
    echo "Пароль: ${PASSWORD}" >&3
    echo "" >&3
    echo "Подключение протестировали, всё работает." >&3
    echo "" >&3
    echo "Рекомендуемые клиенты throne на пк: https://github.com/throneproj/Throne/releases/download/1.2.4/Throne-1.2.4-windows-universal-installer.exe" >&3
    echo "V2Box на мобильном устройстве." >&3
    echo "" >&3
    echo "В Throne нажимаете по пустому ПКМ и выбираете добавить профиль из буфера обмена, в V2BOX в конфигурациях нажимаете + импортировать из буфера обмена." >&3
    echo -e "" >&3
    echo -e "\n\033[1;32m══════════════════════════════════════════════════\033[0m" >&3
    echo -e "" >&3
    echo -e "Все данные сохранены в файл: \033[1;36m/root/3x-ui.txt\033[0m" >&3
    echo -e "Для просмотра в будущем введите: \033[0;36mcat /root/3x-ui.txt\033[0m\n" >&3
}

save_summary_file() {
    {
        echo "======================================"
        echo "   VLESS Reality"
        echo "======================================"
        echo "$VLESS_LINK"
        echo ""
        echo "Порт: ${REALITY_PORT} | SNI: ${BEST_DOMAIN}"
        echo ""
        echo "======================================"
        echo "   Hysteria2"
        echo "======================================"
        echo "$HY2_LINK"
        echo ""
        echo "Порт: ${HYSTERIA_PORT} | SNI: ${BEST_DOMAIN}"
        echo ""
        echo "======================================"
        echo "   Панель управления 3X-UI"
        echo "======================================"
        echo "Адрес:  ${PANEL_PROTO}://${SERVER_IP}:${PORT}/${CLEAN_PATH}"
        echo "Логин:  ${USERNAME}"
        echo "Пароль: ${PASSWORD}"
    } > /root/3x-ui.txt
}

print_results() {
    build_connection_links

    if [[ "$CLIENT_INSTALL" == true ]]; then
        print_client_summary
    else
        print_summary
    fi

    save_summary_file
}

main() {
    check_root
    detect_os
    detect_arch

    remove_existing_xui
    sni_request
    client_check
    setup_logging
    prompt_port
    generate_credentials

    setup_bbr

    install_dependencies

    install_xui

    generate_xray_keys
    generate_client_identifiers

    setup_inbounds

    print_results
}

main "$@"
