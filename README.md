# vless-scripts

Различные скрипты для VPN на основе протокола Vless

# Полная авто-установка Marzban панели (БЕТА)

Устанавливает и настраивает Marzban полностью автоматически, находится на разработке и может выполняться с ошибками

## Скачать и запустить

С настройками по умолчанию:

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzinstall.sh)
```

# Полная авто-установка 3x-ui панели

Устанавливает и настраивает 3x-ui полностью автоматически.

## Скачать и запустить

С настройками по умолчанию:

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/3xinstall.sh)
```

Расширенную, с возможностью предустановить свои настройки и установки SelfSNI:

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/3xinstall.sh) --extend
```

# Установка SNI сайта

Скачивает и устанавливает рандомный шаблонный сайт отсюда: <https://github.com/learning-zone/website-templates>

И получает на него Let's Encrypt сертификат и настраивает nginx под использовании сайта в качестве SNI для Vless Reality

## Скачать и запустить

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh)
```

## Аргументы
### Настройка своего внутреннего порта в nginx
``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh) --port 9443
```

### Настройка Nginx без http на 80 порту

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh) --without-80
```

# Возвращение https в Marzban

Возвращает возможность пользоваться Marzban из вне как раньше без SSH туннеля, и позволяет опционаольно установить заглушку логина ISPManager.

## Скачать и запустить

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzbanfix.sh)
```

# Автофикс порта 3x-ui панели

Автоматически настраивает 3x-ui панель на работу с 8080 портом, запустить скрипт можно с помощью следующей команды:

``` bash
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/3xuiportfix.sh)
```

# Заглушка логина в ISPManager

## Installation Guide for Marzban Home Template

This guide provides step-by-step instructions for setting up the Marzban home template on a Debian-based system.

### Before you begin, ensure you have the following

- A Debian-based operating system.
- `wget` installed. If not, you can install it using the following commands:

  ```bash
  sudo apt-get update
  sudo apt-get install wget

### Step 1: Create Necessary Directories

First, you'll need to create the necessary directories for the Marzban home template.

Open your terminal and run the following command:

```bash
sudo mkdir -p /var/lib/marzban/templates/home/
```

This command will create all the required directories in the path `/var/lib/marzban/templates/home/`.

### Step 2: Download the Template File

Next, download the `index.html` template file from the GitHub repository and save it in the created directory.

Run the following command:

```bash
sudo wget https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzban-ispmgr/index.html -O /var/lib/marzban/templates/home/index.html
```

This command will download the `index.html` file and place it in the `/var/lib/marzban/templates/home/` directory.

### Step 3: Marzban .env

```bash
nano /opt/marzban/.env
```

Set CUSTOM_TEMPLATES_DIRECTORY to "/var/lib/marzban/templates/"

``` plaintext
CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"
```

Set HOME_PAGE_TEMPLATE to "home/index.html"

``` plaintext
HOME_PAGE_TEMPLATE="home/index.html"
```

### Step 4: Restart Marzban

```bash
marzban restart
```
