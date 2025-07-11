#!/bin/sh

# ===============================================
#      UCI-DEFAULTS ОФЛАЙН-СКРИПТ НАСТРОЙКИ
# ===============================================
# Имя файла: /etc/uci-defaults/zz1-final-offline-setup.sh
# ===============================================

# Включаем режим отладки. Каждая команда будет выведена в лог перед выполнением.
set -x

# Логирование теперь можно направить в системный лог или оставить в файле
echo "Running zz1-final-offline-setup.sh" > /root/setup_log.txt
SETUP_LOGFILE="/root/setup_log.txt"
exec > >(tee -a "$SETUP_LOGFILE") 2>&1

# -----------------------------
#      ПЕРЕМЕННЫЕ СИСТЕМЫ
# -----------------------------

KERNEL_VERSION=$(cat /proc/version | awk '{print $3}')
ARCH_VERSION=$(grep ARCH /etc/os-release | cut -d'"' -f2)

NAME_VALUE=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
ROUTER_NAME=$(case "$NAME_VALUE" in 
    "OpenWrt") echo "oWRT" ;; 
    "ImmortalWrt") echo "iWRT" ;; 
    *) echo "WRT" ;; 
esac)

MODEL_FULL=$(ubus call system board | grep '"model"' | cut -d '"' -f 4)
ROUTER_MODEL=$(echo $MODEL_FULL | awk '{print $NF}')
ROUTER_MODEL_NAME=$(case "$ROUTER_MODEL" in 
    "GL-MT2500") echo "Brume2" ;; 
    "R5S") echo "R5S" ;; 
    *) echo "$ROUTER_MODEL" ;; 
esac)

HOSTNAME_PATTERN="${ROUTER_MODEL_NAME}-${ROUTER_NAME}"

# --------------------------------------------------------------------------------------------------------------------
#      НАСТРОЙКА РОУТЕРА      ########################################################
# --------------------------------------------------------------------------------------------------------------------

echo -e "\033[35mСКРИПТ ПЕРВОНАЧАЛЬНОЙ ОФЛАЙН-НАСТРОЙКИ РОУТЕРА\033[0m"

#################### Удалить строку Enable FullCone NAT (если нужно) ####################
echo -e "\033[35mУдалить строку Enable FullCone NAT...\033[0m"
sed -i "/option fullcone '1'/d" /etc/config/firewall
echo -e "\033[36mПерезагрузка Firewall...\033[0m"
/etc/init.d/firewall restart

#################### Стандартная настройка ДНС (перед установкой AGH) ####################
echo -e "\033[36mОстанавливаем и отключаем службу AdGuardHome...\033[0m"
/etc/init.d/adguardhome stop >/dev/null 2>&1 && /etc/init.d/adguardhome disable >/dev/null 2>&1

#################### Настройка системного времени (без NTP) ####################
echo -e "\033[35mНастройка часового пояса...\033[0m"
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
/etc/init.d/system reload
date

#################### Подготовка к установке пакетов ####################
echo -e "\033[35mПодготовка системы к установке пакетов...\033[0m"

# Убедимся, что архитектура указана верно
if ! grep -qF "${ARCH_VERSION}" /etc/apk/arch; then
    echo -e "\033[36mДобавляю строку ${ARCH_VERSION} в /etc/apk/arch\033[0m"
    echo "${ARCH_VERSION}" > /etc/apk/arch
else
    echo -e "\033[36mАрхитектура в /etc/apk/arch уже настроена.\033[0m"
fi

#################### Установка всех пакетов из /root/apps/ ####################
echo -e "\033[35mУстановка пакетов из локальной директории /root/apps/...\033[0m"

echo -e "\033[35mУстановка speedtest от Ookla...\033[0m"
if [ -f /root/apps/speedtest ]; then
    cp /root/apps/speedtest /usr/bin/speedtest
    chmod +x /usr/bin/speedtest
    echo -e "\033[32mУстановлен speedtest от Ookla из /root/apps/\033[0m"
else
    echo -e "\033[33mФайл speedtest не найден в /root/apps/. Пропускаем установку.\033[0m"
fi

echo -e "\033[35mУстановка AdGuardHome...\033[0m"
if [ -f /root/apps/AdGuardHome ]; then
    cp /root/apps/AdGuardHome /usr/bin/AdGuardHome
    chmod +x /usr/bin/AdGuardHome
    echo -e "\033[32mУстановлен AdGuardHome из /root/apps/\033[0m"
else
    echo -e "\033[33mФайл AdGuardHome не найден в /root/apps/. Пропускаем установку.\033[0m"
fi

echo -e "\033[35mУстановка sing-box...\033[0m"
if [ -f /root/apps/sing-box ]; then
    cp /root/apps/sing-box /usr/bin/sing-box
    chmod +x /usr/bin/sing-box
    echo -e "\033[32mУстановлен sing-box из /root/apps/\033[0m"
else
    echo -e "\033[33mФайл sing-box не найден в /root/apps/. Пропускаем установку.\033[0m"
fi

#################### Настройка homeproxy ####################
echo -e "\033[35mНастройка luci-app-homeproxy...\033[0m"
mkdir -p /var/run/homeproxy
echo -e "\033[33mОтключаем dns_hijacked в luci-app-homeproxy\033[0m"
sed -i "s/const dns_hijacked = uci\.get('dhcp', '@dnsmasq\[0\]', 'dns_redirect') || '0'/const dns_hijacked = '1'/" /etc/homeproxy/scripts/firewall_post.ut
echo -e "\033[37mluci-app-homeproxy настроен.\033[0m"
SB_version=$(/usr/bin/sing-box version | grep -oP 'v?\K[\d.]+' | head -n 1)
echo -e "\e[37mУстановленная версия sing-box: $SB_version\e[0m"

#################### Настройка youtubeUnblock ####################
echo -e "\033[35mНастройка youtubeUnblock...\033[0m"
/etc/init.d/youtubeUnblock disable && /etc/init.d/youtubeUnblock stop
sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' /usr/share/firewall4/templates/ruleset.uc

# Путь к файлу правил и строка для поиска
NFT_FILE="/usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft"
SEARCH_STRING="@dpi_ips"

# Проверяем, существует ли файл И содержит ли он искомую строку.
# Мы перезаписываем файл, только если он НЕ существует ИЛИ если он существует, но НЕ содержит нужную строку.
if [ ! -f "$NFT_FILE" ] || ! grep -q "$SEARCH_STRING" "$NFT_FILE"; then
    echo -e "\033[36mФайл правил $NFT_FILE youtubeUnblock не найден или устарел. Создаем/перезаписываем его.\033[0m"
#cat <<EOF > "$NFT_FILE"
cat <<EOF > /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
#!/usr/sbin/nft -f
# This file will be applied automatically for nftables <table> <chain> position <number> <condition> <action>

# Drop (reject) UDP to dest port 443 to Google IPs
add rule inet fw4 prerouting ip daddr @google_ips udp dport 443 reject with icmp port-unreachable

# DPI through youtubeUnblock
add chain inet fw4 youtubeUnblock { type filter hook postrouting priority mangle - 1; policy accept; }

# Exclusion of the guest network by tag (traffic will bypass the queue)
add rule inet fw4 youtubeUnblock meta mark 0x00000042 counter return

# DPI through youtubeUnblock
add rule inet fw4 youtubeUnblock ip daddr @cloudflare_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @google_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @aws_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @cdn77_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @fornex_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @akamai_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @vultr_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @facebook_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass

# Skipping traffic with the label 0x8000
insert rule inet fw4 output mark and 0x8000 == 0x8000 counter accept

#--------------------------------------------------------------------------------------------------------------------------------------------
# DEF #
#add chain inet fw4 youtubeUnblock { type filter hook postrouting priority mangle - 1; policy accept; }
#add rule inet fw4 youtubeUnblock tcp dport 443 ct original packets < 20 counter queue num 537 bypass
#add rule inet fw4 youtubeUnblock meta l4proto udp ct original packets < 9 counter queue num 537 bypass
#insert rule inet fw4 output mark and 0x8000 == 0x8000 counter accept
EOF
else
    echo -e "\033[32mФайл правил $NFT_FILE youtubeUnblock уже содержит '$SEARCH_STRING'. Обновление не требуется.\033[0m"
fi

/etc/init.d/youtubeUnblock enable && /etc/init.d/youtubeUnblock restart
echo -e "\033[37myoutubeUnblock настроен и включен.\033[0m"
/etc/init.d/firewall restart

#################### Настройка internet-detector ####################
echo -e "\033[35mНастройка internet-detector...\033[0m"
/etc/init.d/internet-detector stop && /etc/init.d/internet-detector disable
sed -i 's/START=[0-9][0-9]/START=99/' /etc/init.d/internet-detector
echo -e "\033[37mСлужба internet-detector настроена (но отключена).\033[0m"

#################### Обновить баннер ####################
echo -e "\033[35mОбновить баннер...\033[0m"
cp /etc/banner /etc/banner.bak
sed -i 's/W I R E L E S S/N E T W O R K/g' /etc/banner
ADD_TEXT="Kernel $KERNEL_VERSION,"
if ! grep -q "Kernel $KERNEL_VERSION" /etc/banner; then
    sed -i '/, r/s/,/, '"$ADD_TEXT"'/' /etc/banner
fi

#################### Обновить имя хоста ####################
echo -e "\033[35mОбновить имя хоста...\033[0m"
uci set system.@system[0].hostname="$HOSTNAME_PATTERN"
uci commit system
uci set uhttpd.defaults.commonname="$HOSTNAME_PATTERN"
uci commit uhttpd
echo -e "\033[36mИмя хоста установлено: $HOSTNAME_PATTERN\033[0m"

sed -i "s/File Manager/Файловый менеджер/" /usr/share/luci/menu.d/luci-app-filemanager.json && echo -e "\033[36mОбновлен Файловый менеджер\033[0m"

#################### Настройка путей для owut (attendedsysupgrade) ####################
echo -e "\033[35mНастройка путей для owut...\033[0m"
if [ "$NAME_VALUE" == "OpenWrt" ]; then
    sed -i "s|option url 'https://asu-2.kyarucloud.moe'|option url 'https://sysupgrade.openwrt.org'|" /etc/config/attendedsysupgrade
    echo -e "\033[36mowut настроен на OpenWrt\033[0m"
else
    sed -i "s|option url 'https://sysupgrade.openwrt.org'|option url 'https://asu-2.kyarucloud.moe'|" /etc/config/attendedsysupgrade
    echo -e "\033[36mowut настроен на ImmortalWrt\033[0m"
fi

#################### Настройка и запуск AdGuardHome ####################
echo -e "\033[35mНастройка и запуск AdGuardHome...\033[0m"
/etc/init.d/adguardhome stop && /etc/init.d/adguardhome disable

echo -e "\033[36mНастройки для AdGuardHome...\033[0m"
echo "config adguardhome config" > /etc/config/adguardhome
echo -e "\toption enabled '1'" >> /etc/config/adguardhome
echo -e "\toption workdir /opt/AdGuardHome" >> /etc/config/adguardhome
echo -e "\toption configpath /etc/adguardhome.yaml" >> /etc/config/adguardhome
echo -e "\toption logfile /var/AdGuardHome.log" >> /etc/config/adguardhome

# Настройка init.d/adguardhome
# sed -i 's/START=[0-9][0-9]/START=98/' /etc/init.d/adguardhome
sed -i 's/config_get CONF.*/config_get CONF_FILE config configpath/' /etc/init.d/adguardhome
sed -i '/config_get LOG/d' /etc/init.d/adguardhome
sed -i '/config_get CONF/a\  config_get LOG_FILE config logfile' /etc/init.d/adguardhome
sed -i '/config_get WORK_DIR/d' /etc/init.d/adguardhome
sed -i '/config_get LOG/a\  config_get WORK_DIR config workdir' /etc/init.d/adguardhome
sed -i '/procd_set_param command/d' /etc/init.d/adguardhome
sed -i '/procd_open_instance/a\  procd_set_param command "$PROG" -c "$CONF_FILE" -w "$WORK_DIR" -l "$LOG_FILE" --no-check-update' /etc/init.d/adguardhome
sed -i '/chmod -R 0777/d' /etc/init.d/adguardhome
sed -i '/mkdir -m 0755/a\  chmod -R 0777 $WORK_DIR' /etc/init.d/adguardhome

AGH_version=$(/usr/bin/AdGuardHome --version 2>/dev/null | grep -oP 'v?\K[\d.]+')
echo -e "\033[33mУстановленная версия AGH: $AGH_version\033[0m"

# Освобождение порта 53 для AdGuardHome
uci set dhcp.@dnsmasq[0].port="54"
uci del_list dhcp.@dnsmasq[0].server="1.1.1.2"
uci del_list dhcp.@dnsmasq[0].server="77.88.8.88"
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#53"
uci commit dhcp
echo -e "\033[36mПерезапуск DNSmasq на порту 54...\033[0m"
/etc/init.d/dnsmasq restart

if [ -n "$AGH_version" ]; then
    echo -e "\033[36mЗапуск AdGuardHome...\033[0m"
    /etc/init.d/adguardhome enable && /etc/init.d/adguardhome restart
    echo -e "\033[37mЗапущенная версия AdGuardHome: $AGH_version\033[0m"
else
    echo -e "\033[31mAdGuardHome не установлен или не найден.\033[0m"
fi

#################### Финальные настройки ####################
echo -e "\033[35mФинальные настройки системы...\033[0m"

# Очистка временных файлов конфигурации
find /etc/config/ -type f -name '*-opkg' -exec rm {} \;
find /etc/config/ -type f -name '*apk-new' -exec rm {} \;
echo -e "\033[36mУдалены временные файлы конфигурации.\033[0m"

# Включение FullCone NAT для ImmortalWrt
if [ "$NAME_VALUE" == "ImmortalWrt" ]; then
    uci set firewall.@defaults[0].fullcone='1' && uci commit firewall && /etc/init.d/firewall restart
    echo -e "\033[37mFullCone NAT включен на ImmortalWrt\033[0m"
else
    echo -e "\033[37mПрошивка не ImmortalWrt. FullCone NAT не настраивается.\033[0m"
fi

# Расширение интерфейса bootstrap
if ! grep -q "/* LuCI Bootstrap: Custom Fullwidth CSS */" /www/luci-static/bootstrap/cascade.css; then
    cat << EOF >> /www/luci-static/bootstrap/cascade.css

/* LuCI Bootstrap: Custom Fullwidth CSS */

/* 100% ширина для всех мобильных устройств (в любом положении) */
@media only screen and (max-width: 1199px),
       (hover: none) and (pointer: coarse) {
    #maincontent, .container, .main-content, .wrapper {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
    }
}

/* 50% ширина только для ПК и ноутбуков */
@media only screen and (min-width: 1200px) and (hover: hover) {
    #maincontent, .container, .main-content, .wrapper {
        width: 50% !important;
        max-width: 50% !important;
        margin: 0 auto !important;
        padding: 0 !important;
    }
}

EOF

    echo "CSS успешно обновлен"
else
    echo "CSS уже содержит обновленные стили"
fi

# Исправить uhttpd
/etc/init.d/uhttpd disable
# Показать текущее значение
echo "Текущее значение uhttpd:"
grep "^START=" /etc/init.d/uhttpd
# Изменить START на 60
sed -i 's/^START=[0-9]*/START=60/' /etc/init.d/uhttpd
# Показать новое значение
echo "Новое значение uhttpd:"
grep "^START=" /etc/init.d/uhttpd
# Включить uhttpd
/etc/init.d/uhttpd enable
echo "Готово! uhttpd будет запускаться с приоритетом 60"

# Перезапуск служб
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
# /etc/init.d/system restart

/etc/init.d/sqm enable && /etc/init.d/sqm restart

/etc/init.d/phy-leds disable && echo -e "\033[36mОтключен старый скрипт управления диодами phy-leds\033[0m"

for param in /proc/sys/net/ipv4/tcp_rmem \
             /proc/sys/net/ipv4/tcp_wmem \
             /proc/sys/net/ipv4/tcp_fastopen \
             /proc/sys/net/core/rmem_max \
             /proc/sys/net/core/wmem_max \
             /proc/sys/net/ipv4/tcp_window_scaling \
             /proc/sys/net/ipv4/ip_local_port_range \
             /proc/sys/net/core/default_qdisc \
             /proc/sys/net/ipv4/tcp_congestion_control; do
  name=$(basename $param)
  echo -e "$name: \033[33m$(cat $param)\033[0m"
done

#################### Проверка служб ####################
echo -e "\033[35mПроверка статуса служб...\033[0m"
date
sleep 3
echo -e "\033[33myoutubeUnblock:\033[0m"
service | grep youtubeUnblock | awk '{print $2, $3}'
echo -e "\033[33madguardhome:\033[0m"
service | grep adguardhome | awk '{print $2, $3}'
echo -e "\033[33msqm:\033[0m"
service | grep sqm | awk '{print $2, $3}'

cat /tmp/sysinfo/model && . /etc/openwrt_release

echo -e "\033[32mПервоначальная настройка завершена успешно.\033[0m"

echo -e "\033[32mЗапрос на перезагрузку системы...\033[0m"
# Создаем файл-триггер для перезагрузки.
# Система uci-defaults увидит его и выполнит перезагрузку после завершения всех скриптов.
touch /etc/uci-defaults/.uci_reboot

# ВАЖНО: Завершаем скрипт с кодом 0 для его автоматического удаления
exit 0
