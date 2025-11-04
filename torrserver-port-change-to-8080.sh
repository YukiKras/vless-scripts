#!/bin/bash
sed -i 's/8090/8080/g' /etc/systemd/system/torrserver.service
systemctl daemon-reload
systemctl restart torrserver
IPv4=$(python3 -c "print('$(ip a | grep /32)'.split('inet ')[1].split('/32')[0])")
echo "torrserver перенастроен на порт 8080: https://$IPv4:8080"
echo "Данные для подключения не изменились "
sed -i 's/8090/8080/g' /root/TorrServer.log
