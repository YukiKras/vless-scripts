# vless-scripts
Различные скрипты для VPN на основе протокола Vless

# Установка SNI сайта
Скачивает и устанавливает рандомный шаблонный сайт отсюда: https://github.com/learning-zone/website-templates

И получает на него Let's Encrypt сертификат и настраивает nginx под использовании сайта в качестве SNI для Vless Reality
## Скачать и запустить
```
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh)
```

# Возвращение https в Marzban
Возвращает возможность пользоваться Marzban из вне как раньше без SSH туннеля, и позволяет опционаольно установить заглушку логина ISPManager.
## Скачать и запустить
```
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzbanfix.sh)
```

# Заглушка логина в ISPManager:

## Installation Guide for Marzban Home Template

This guide provides step-by-step instructions for setting up the Marzban home template on a Debian-based system.

### Before you begin, ensure you have the following:

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
```
CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"
```

Set HOME_PAGE_TEMPLATE to "home/index.html"
```
HOME_PAGE_TEMPLATE="home/index.html"
```

### Step 4: Restart Marzban

```bash
marzban restart
```