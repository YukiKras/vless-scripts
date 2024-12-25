# vless-scripts
Различные скрипты для VPN на основе протокола Vless

# Установка SNI сайта
Скачивает и устанавливает шаблонный сайт отсюда: https://github.com/learning-zone/website-templates

И получает на него Let's Encrypt сертификат и настраивает nginx под использовании сайта в качестве SNI для Vless Reality
## Скачать и запустить
```
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh)
```

# Возвращение http в Marzban
Возвращает возможность пользоваться Marzban из вне как раньше без SSL/TLS сертификата и SSH туннеля, устанавливая reverse proxy в nginx до него на 8888 порт по http.
## Скачать и запустить
```
bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/marzbanfix.sh)
```
