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

#################### Настройка системного времени (без NTP) ####################
echo -e "\033[35mНастройка часового пояса...\033[0m"
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
#-#/etc/init.d/system reload
date

#################### Подготовка системы к установке пакетов ####################
echo -e "\033[35mПодготовка системы к установке пакетов...\033[0m"

# Проверяем, какой пакетный менеджер используется
if command -v apk >/dev/null 2>&1; then
    echo -e "\033[36mОбнаружен пакетный менеджер APK.\033[0m"
    # 1. Убедимся, что архитектура указана верно
    if ! grep -qF "${ARCH_VERSION}" /etc/apk/arch; then
        echo -e "\033[36mДобавляю архитектуру ${ARCH_VERSION} в /etc/apk/arch...\033[0m"
        echo "${ARCH_VERSION}" > /etc/apk/arch
    else
        echo -e "\033[36mАрхитектура в /etc/apk/arch уже настроена.\033[0m"
    fi
    # 2. Определяем список репозиториев
    DISTFEEDS_FILE="/etc/apk/repositories.d/distfeeds.list"
    CUSTOMFEEDS_FILE="/etc/apk/repositories.d/customfeeds.list"
    # 3. Копируем ключи для подписи пакетов, если они есть
    [ ! -f /etc/apk/keys/immortalwrt-snapshots.pem ] && cp /root/apps/immortalwrt-snapshots.pem /etc/apk/keys/
    [ ! -f /etc/apk/keys/openwrt-snapshots.pem ] && cp /root/apps/openwrt-snapshots.pem /etc/apk/keys/
    [ ! -f /etc/apk/keys/youtubeUnblock.pem ] && cp /root/apps/youtubeUnblock.pem /etc/apk/keys/
    [ ! -f /etc/apk/keys/public-key.pem ] && cp /root/apps/public-key.pem /etc/apk/keys/
elif command -v opkg >/dev/null 2>&1; then
    DISTFEEDS_FILE="/etc/opkg/distfeeds.conf"
    CUSTOMFEEDS_FILE="/etc/opkg/customfeeds.conf"
    echo -e "\033[36mОбнаружен пакетный менеджер OPKG.\033[0m"
else
    echo -e "\033[31mОшибка: Пакетный менеджер (apk или opkg) не найден.\033[0m"
fi

if [ -f "$DISTFEEDS_FILE" ]; then
    echo -e "\033[37mОчистка файла репозиториев $DISTFEEDS_FILE...\033[0m"
    # Создаем бэкап на всякий случай
    cp "$DISTFEEDS_FILE" "${DISTFEEDS_FILE}.bak"
    # Фильтруем содержимое файла и сохраняем результат в переменную
    FILTERED_CONTENT=$(grep -E "targets|packages/${ARCH_VERSION}/(base|luci|packages|routing|telephony|video)" "$DISTFEEDS_FILE")
    # Проверяем, что переменная не пустая, прежде чем перезаписывать файл
    if [ -n "$FILTERED_CONTENT" ]; then
        echo "$FILTERED_CONTENT" > "$DISTFEEDS_FILE"
        echo -e "\033[32mФайл репозиториев успешно очищен.\033[0m"
    else
        echo -e "\033[31mОшибка: Фильтрация не нашла ни одной нужной строки! Оригинальный файл не изменен.\033[0m"
    fi
else
    echo "Файл $DISTFEEDS_FILE не найден."
fi

cat <<EOF > "$CUSTOMFEEDS_FILE"
# add your custom package feeds here
#
# http://www.example.com/path/to/files/packages.adb

EOF

#################### Установка всех пакетов из /root/apps/ ####################
echo -e "\033[35mУстановка пакетов из локальной директории /root/apps/...\033[0m"

#echo -e "\033[35mУстановка speedtest от Ookla...\033[0m"
#if [ -f /root/apps/speedtest ]; then
#    cp /root/apps/speedtest /usr/bin/speedtest
#    chmod +x /usr/bin/speedtest
#    echo -e "\033[32mУстановлен speedtest от Ookla из /root/apps/\033[0m"
#else
#    echo -e "\033[33mФайл speedtest не найден в /root/apps/. Пропускаем установку.\033[0m"
#fi

echo -e "\033[35mУстановка AdGuardHome...\033[0m"
if [ -f /root/apps/AdGuardHome ]; then
    /etc/init.d/adguardhome stop >/dev/null 2>&1
    cp /root/apps/AdGuardHome /usr/bin/AdGuardHome
    chmod +x /usr/bin/AdGuardHome
    echo -e "\033[32mУстановлен AdGuardHome из /root/apps/\033[0m"
else
    echo -e "\033[33mФайл AdGuardHome не найден в /root/apps/. Пропускаем установку.\033[0m"
fi

echo -e "\033[35mУстановка sing-box...\033[0m"
if [ -f /root/apps/sing-box ]; then
    /etc/init.d/sing-box stop >/dev/null 2>&1
    cp /root/apps/sing-box /usr/bin/sing-box
    chmod +x /usr/bin/sing-box
    echo -e "\033[32mУстановлен sing-box из /root/apps/\033[0m"
else
    echo -e "\033[33mФайл sing-box не найден в /root/apps/. Пропускаем установку.\033[0m"
fi

#################### Настройка homeproxy ####################
echo -e "\033[35mНастройка luci-app-homeproxy...\033[0m"
echo -e "\033[33mОтключаем dns_hijacked в luci-app-homeproxy\033[0m"
sed -i "s/const dns_hijacked = uci\.get('dhcp', '@dnsmasq\[0\]', 'dns_redirect') || '0'/const dns_hijacked = '1'/" /etc/homeproxy/scripts/firewall_post.ut

/etc/init.d/homeproxy disable

# Проблема: uci-defaults для homeproxy создает в конфиге firewall ссылки на файлы, которые homeproxy создает только в режимах TUN или Server.
# 1. Создаем наш скрипт-помощник
HELPER_SCRIPT_PATH="/etc/homeproxy/scripts/update_firewall_rules.sh"
cat << 'EOF' > "$HELPER_SCRIPT_PATH"
#!/bin/sh
PROXY_MODE=$(uci -q get homeproxy.config.proxy_mode || echo "redirect_tproxy")
SERVER_ENABLED=$(uci -q get homeproxy.server.enabled || echo "0")
if (echo "$PROXY_MODE" | grep -q "tun") || [ "$SERVER_ENABLED" = "1" ]; then
    uci -q batch <<-E_O_F
	set firewall.homeproxy_forward=include
	set firewall.homeproxy_forward.type=nftables
	set firewall.homeproxy_forward.path="/var/run/homeproxy/fw4_forward.nft"
	set firewall.homeproxy_forward.position="chain-pre"
	set firewall.homeproxy_forward.chain="forward"

	set firewall.homeproxy_input=include
	set firewall.homeproxy_input.type=nftables
	set firewall.homeproxy_input.path="/var/run/homeproxy/fw4_input.nft"
	set firewall.homeproxy_input.position="chain-pre"
	set firewall.homeproxy_input.chain="input"
E_O_F
else
    uci -q batch <<-E_O_F
        delete firewall.homeproxy_forward
        delete firewall.homeproxy_input
E_O_F
fi
uci -q commit firewall
EOF
chmod +x "$HELPER_SCRIPT_PATH"
echo -e "\033[37mСоздан скрипт-помощник для homeproxy: $HELPER_SCRIPT_PATH\033[0m"
# 2. Модифицируем init-скрипт homeproxy, чтобы он вызывал наш помощник
HOMEPROXY_INIT_SCRIPT="/etc/init.d/homeproxy"
TAB_CHAR=$'\t'
HELPER_CALL_COMMAND="${TAB_CHAR}. ${HELPER_SCRIPT_PATH}"
if [ -f "$HOMEPROXY_INIT_SCRIPT" ]; then
    # Проверяем, не была ли команда добавлена ранее
    if ! grep -q "$HELPER_SCRIPT_PATH" "$HOMEPROXY_INIT_SCRIPT"; then
        # Вставляем вызов нашего скрипта в начало start_service() и stop_service()
        sed -i "/start_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
        sed -i "/stop_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
        echo -e "\033[37mInit-скрипт homeproxy модифицирован для вызова помощника.\033[0m"
    else
        echo -e "\033[32mInit-скрипт homeproxy уже был модифицирован.\033[0m"
    fi
else
    echo -e "\033[33mСкрипт $HOMEPROXY_INIT_SCRIPT не найден.\033[0m"
fi
# 3. Первоначальный запуск нашего помощника, чтобы исправить конфиг сразу
. "$HELPER_SCRIPT_PATH"

/etc/init.d/homeproxy enable

echo -e "\033[37mluci-app-homeproxy настроен.\033[0m"

SB_version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP 'v?\K[\d.]+' | head -n 1)
echo -e "\e[37mУстановленная версия sing-box: $SB_version\e[0m"

#################### Настройка youtubeUnblock ####################
echo -e "\033[35mНастройка youtubeUnblock...\033[0m"

sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' /usr/share/firewall4/templates/ruleset.uc

# Путь к файлу правил и его код
YTB_NFT_FILE="/usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft"
YTB_NFT_FILE_CONTENT=$(cat <<"EOF"
#!/usr/sbin/nft -f
# This file will be applied automatically for nftables <table> <chain> position <number> <condition> <action>

# Drop (reject) UDP to dest port 443 to DPI IPs
add rule inet fw4 prerouting ip daddr @dpi_ips udp dport 443 reject with icmp port-unreachable

# DPI through youtubeUnblock
add chain inet fw4 youtubeUnblock { type filter hook postrouting priority mangle - 1; policy accept; }

# Exclusion of the guest network by tag (traffic will bypass the queue)
add rule inet fw4 youtubeUnblock meta mark 0x00000042 counter return

# DPI through youtubeUnblock
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips meta l4proto udp ct original packets < 9 counter queue num 537 bypass

# Skipping traffic with the label 0x8000
insert rule inet fw4 output mark and 0x8000 == 0x8000 counter accept
EOF
)

# Настройка правила nftables для пометки трафика гостевой сети
YTB_NFT_GUEST_MARK_FILE="/etc/nftables.d/guest_mark.nft"
# Используем кавычки вокруг EOF, чтобы $ не интерпретировался
YTB_NFT_GUEST_MARK_CONTENT=$(cat << "EOF"
chain guest_mark {
	type filter hook prerouting priority mangle; policy accept;
	iifname "br-guest" meta mark set 0x00000042
}
EOF
)

# Проверяем, установлен ли youtubeUnblock. 
# Мы ищем исполняемый файл - это самый надежный способ.
if [ -x "/usr/bin/youtubeUnblock" ]; then
    echo -e "\033[37mСлужба youtubeUnblock установлена. Применяем конфигурацию...\033[0m"
    # Отключаем службу на время настройки
    /etc/init.d/youtubeUnblock disable
    echo "$YTB_NFT_FILE_CONTENT" > "$YTB_NFT_FILE"
    chmod 0644 "$YTB_NFT_FILE"
    echo "$YTB_NFT_GUEST_MARK_CONTENT" > "$YTB_NFT_GUEST_MARK_FILE"
    chmod 0644 "$YTB_NFT_GUEST_MARK_FILE"
    /etc/init.d/youtubeUnblock enable
    echo -e "\033[37myoutubeUnblock настроен и включен.\033[0m"
else
    echo -e "\033[33mСлужба youtubeUnblock не установлена. Настройка пропущена.\033[0m"
fi

#################### Настройка internet-detector ####################
echo -e "\033[35mНастройка internet-detector...\033[0m"
/etc/init.d/internet-detector disable
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

/etc/init.d/adguardhome disable

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
uci delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#53"
uci commit dhcp
echo -e "\033[36mПерезапуск DNSmasq на порту 54...\033[0m"

if [ -n "$AGH_version" ]; then
    echo -e "\033[36mЗапуск AdGuardHome...\033[0m"
    /etc/init.d/adguardhome enable
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
    uci set firewall.@defaults[0].fullcone='1' && uci commit firewall
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

# Исправить порядок запуска uhttpd
# /etc/init.d/uhttpd disable
# sed -i 's/^START=[0-9]*/START=60/' /etc/init.d/uhttpd
# /etc/init.d/uhttpd enable

# Включить sqm
/etc/init.d/sqm disable
/etc/init.d/sqm enable
echo "sqm включен"

# Перезапуск служб
#-#/etc/init.d/rpcd restart
#-#/etc/init.d/uhttpd restart
#-#/etc/init.d/system restart
#-#/etc/init.d/firewall restart
#-#/etc/init.d/sqm restart
#-#/etc/init.d/dnsmasq restart
#-#/etc/init.d/adguardhome restart

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
#-#echo -e "\033[35mПроверка статуса служб...\033[0m"
#-#date
#-#echo -e "\033[33myoutubeUnblock:\033[0m"
#-#service | grep youtubeUnblock | awk '{print $2, $3}'
#-#echo -e "\033[33madguardhome:\033[0m"
#-#service | grep adguardhome | awk '{print $2, $3}'
#-#echo -e "\033[33msqm:\033[0m"
#-#service | grep sqm | awk '{print $2, $3}'

cat /tmp/sysinfo/model && . /etc/openwrt_release

echo -e "\033[32mПервоначальная настройка завершена успешно.\033[0m"

# Отложенная перезагрузка в фоне (&) в дочерней оболочке ()...
echo -e "\033[32mЗапрос на перезагрузку системы...\033[0m"
(sleep 60; reboot) &

# ВАЖНО: Завершаем скрипт с кодом 0 для его автоматического удаления
exit 0
