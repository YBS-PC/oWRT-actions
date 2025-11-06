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

# --- Управление цветами ---
# Установите в "true" для цветного вывода, в "false" для чистого текста.
USE_COLORS="true"

if [ "$USE_COLORS" = "true" ]; then
    COLOR_RED='\033[31m'
    COLOR_GREEN='\033[32m'
    COLOR_YELLOW='\033[33m'
    COLOR_BLUE='\033[34m'
    COLOR_MAGENTA='\033[35m'
    COLOR_CYAN='\033[36m'
    COLOR_WHITE='\033[37m'
    COLOR_RESET='\033[0m'
else
    # Если цвета отключены, все переменные будут пустыми
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_MAGENTA=''
    COLOR_CYAN=''
    COLOR_WHITE=''
    COLOR_RESET=''
fi

# -----------------------------
#      ПЕРЕМЕННЫЕ СИСТЕМЫ
# -----------------------------

KERNEL_VERSION=$(cat /proc/version | awk '{print $3}')
ARCH_VERSION=$(grep ARCH /etc/os-release | cut -d'"' -f2)

NAME_VALUE=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
case "$NAME_VALUE" in
	"OpenWrt") ROUTER_NAME="oWRT" ;;
	"ImmortalWrt") ROUTER_NAME="iWRT" ;;
	*) ROUTER_NAME="WRT" ;;
esac

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

echo -e "${COLOR_MAGENTA}СКРИПТ ПЕРВОНАЧАЛЬНОЙ ОФЛАЙН-НАСТРОЙКИ РОУТЕРА${COLOR_RESET}"

#################### Удалить строку Enable FullCone NAT (если нужно) ####################
echo -e "${COLOR_MAGENTA}Удалить строку Enable FullCone NAT...${COLOR_RESET}"
sed -i "/option fullcone '1'/d" /etc/config/firewall

#################### Настройка системного времени (без NTP) ####################
echo -e "${COLOR_MAGENTA}Настройка часового пояса...${COLOR_RESET}"
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
#-#/etc/init.d/system reload
date

#################### Подготовка системы к установке пакетов ####################
echo -e "${COLOR_MAGENTA}Подготовка системы к установке пакетов...${COLOR_RESET}"

# Проверяем, какой пакетный менеджер используется
if command -v apk >/dev/null 2>&1; then
	echo -e "${COLOR_CYAN}Обнаружен пакетный менеджер APK.${COLOR_RESET}"
	# 1. Убедимся, что архитектура указана верно
	if ! grep -qF "${ARCH_VERSION}" /etc/apk/arch; then
		echo -e "${COLOR_CYAN}Добавляю архитектуру ${ARCH_VERSION} в /etc/apk/arch...${COLOR_RESET}"
		echo "${ARCH_VERSION}" > /etc/apk/arch
	else
		echo -e "${COLOR_CYAN}Архитектура в /etc/apk/arch уже настроена.${COLOR_RESET}"
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
	echo -e "${COLOR_CYAN}Обнаружен пакетный менеджер OPKG.${COLOR_RESET}"
else
	echo -e "${COLOR_RED}Ошибка: Пакетный менеджер (apk или opkg) не найден.${COLOR_RESET}"
fi

if [ -f "$DISTFEEDS_FILE" ]; then
	echo -e "${COLOR_WHITE}Очистка файла репозиториев $DISTFEEDS_FILE...${COLOR_RESET}"
	# Создаем бэкап на всякий случай
	cp "$DISTFEEDS_FILE" "${DISTFEEDS_FILE}.bak"
	# Фильтруем содержимое файла и сохраняем результат в переменную
	FILTERED_CONTENT=$(grep -E "targets|packages/${ARCH_VERSION}/(base|luci|packages|routing|telephony|video)" "$DISTFEEDS_FILE")
	# Проверяем, что переменная не пустая, прежде чем перезаписывать файл
	if [ -n "$FILTERED_CONTENT" ]; then
		echo "$FILTERED_CONTENT" > "$DISTFEEDS_FILE"
		echo -e "${COLOR_GREEN}Файл репозиториев успешно очищен.${COLOR_RESET}"
	else
		echo -e "${COLOR_RED}Ошибка: Фильтрация не нашла ни одной нужной строки! Оригинальный файл не изменен.${COLOR_RESET}"
	fi
else
	echo "Файл $DISTFEEDS_FILE не найден."
fi

cat << 'EOF' > "$CUSTOMFEEDS_FILE"
# add your custom package feeds here
#
# http://www.example.com/path/to/files/packages.adb

EOF

#################### Установка всех пакетов из /tmp/ ####################
echo -e "${COLOR_MAGENTA}Установка пакетов из локальной директории...${COLOR_RESET}"

echo -e "${COLOR_MAGENTA}Установка sing-box...${COLOR_RESET}"
if [ -f /root/apps/sing-box.tar.gz ]; then
	/etc/init.d/sing-box stop >/dev/null 2>&1
	tar -xzf /root/apps/sing-box.tar.gz -C /tmp/
	rm /root/apps/sing-box.tar.gz
	cp /tmp/sing-box /usr/bin/sing-box
	chmod +x /usr/bin/sing-box
	echo -e "${COLOR_GREEN}Установлен sing-box из /root/apps/${COLOR_RESET}"
else
	echo -e "${COLOR_YELLOW}Файл sing-box не найден в /root/apps/. Пропускаем установку.${COLOR_RESET}"
fi

echo -e "${COLOR_MAGENTA}Установка speedtest...${COLOR_RESET}"
if [ -f /root/apps/speedtest.tar.gz ]; then
	tar -xzf /root/apps/speedtest.tar.gz -C /tmp/
	rm /root/apps/speedtest.tar.gz
	cp /tmp/speedtest /usr/bin/speedtest
	chmod +x /usr/bin/speedtest
	echo -e "${COLOR_GREEN}Установлен speedtest из /root/apps/${COLOR_RESET}"
else
	echo -e "${COLOR_YELLOW}Файл speedtest не найден в /tmp/. Пропускаем установку.${COLOR_RESET}"
fi

#################### Настройка homeproxy ####################
echo -e "${COLOR_MAGENTA}Настройка luci-app-homeproxy...${COLOR_RESET}"
echo -e "${COLOR_YELLOW}Отключаем dns_hijacked в luci-app-homeproxy${COLOR_RESET}"
sed -i "s/const dns_hijacked = uci\.get('dhcp', '@dnsmasq\[0\]', 'dns_redirect') || '0'/const dns_hijacked = '1'/" /etc/homeproxy/scripts/firewall_post.ut

/etc/init.d/homeproxy disable

# Проблема: uci-defaults для homeproxy создает  по умолчанию в конфиге firewall ссылки на файлы, которые homeproxy создает только в режимах TUN или Server.
# 1. Создаем скрипт-помощник
# Используем кавычки вокруг EOF, чтобы $ не интерпретировался
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
echo -e "${COLOR_WHITE}Создан скрипт-помощник для homeproxy: $HELPER_SCRIPT_PATH${COLOR_RESET}"
# 2. Модифицируем init-скрипт homeproxy, чтобы он вызывал скрипт помощник
HOMEPROXY_INIT_SCRIPT="/etc/init.d/homeproxy"
TAB_CHAR=$'\t'
HELPER_CALL_COMMAND="${TAB_CHAR}. ${HELPER_SCRIPT_PATH}"
if [ -f "$HOMEPROXY_INIT_SCRIPT" ]; then
	# Проверяем, не была ли команда добавлена ранее
	if ! grep -q "$HELPER_SCRIPT_PATH" "$HOMEPROXY_INIT_SCRIPT"; then
		# Вставляем вызов нашего скрипта в начало start_service() и stop_service()
		sed -i "/start_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
		sed -i "/stop_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
		echo -e "${COLOR_WHITE}Init-скрипт homeproxy модифицирован для вызова помощника.${COLOR_RESET}"
	else
		echo -e "${COLOR_GREEN}Init-скрипт homeproxy уже был модифицирован.${COLOR_RESET}"
	fi
else
	echo -e "${COLOR_YELLOW}Скрипт $HOMEPROXY_INIT_SCRIPT не найден.${COLOR_RESET}"
fi
# 3. Первоначальный запуск помощника, чтобы исправить конфиг сразу
. "$HELPER_SCRIPT_PATH"

/etc/init.d/homeproxy enable

echo -e "${COLOR_WHITE}luci-app-homeproxy настроен.${COLOR_RESET}"

SB_version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP -m 1 'v?\K[\d.]+')
echo -e "\e[37mУстановленная версия sing-box: $SB_version\e[0m"

#################### Настройка youtubeUnblock ####################
echo -e "${COLOR_MAGENTA}Настройка youtubeUnblock...${COLOR_RESET}"

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

YTB_NFT_GUEST_MARK_CONTENT=$(cat << "EOF"
chain guest_mark {
	type filter hook prerouting priority mangle; policy accept;
	iifname "br-guest" meta mark set 0x00000042
}
EOF
)

# Проверяем, установлен ли youtubeUnblock. 
if [ -x "/usr/bin/youtubeUnblock" ]; then
	echo -e "${COLOR_WHITE}Служба youtubeUnblock установлена. Применяем конфигурацию...${COLOR_RESET}"
	# Отключаем службу на время настройки
	/etc/init.d/youtubeUnblock disable
	echo "$YTB_NFT_FILE_CONTENT" > "$YTB_NFT_FILE"
	chmod 0644 "$YTB_NFT_FILE"
	echo "$YTB_NFT_GUEST_MARK_CONTENT" > "$YTB_NFT_GUEST_MARK_FILE"
	chmod 0644 "$YTB_NFT_GUEST_MARK_FILE"
	/etc/init.d/youtubeUnblock enable
	echo -e "${COLOR_WHITE}youtubeUnblock настроен и включен.${COLOR_RESET}"
else
	echo -e "${COLOR_YELLOW}Служба youtubeUnblock не установлена. Настройка пропущена.${COLOR_RESET}"
fi

#################### Настройка internet-detector ####################
echo -e "${COLOR_MAGENTA}Настройка internet-detector...${COLOR_RESET}"
/etc/init.d/internet-detector disable
sed -i 's/START=[0-9][0-9]/START=99/' /etc/init.d/internet-detector
echo -e "${COLOR_WHITE}Служба internet-detector настроена (но отключена).${COLOR_RESET}"

#################### Обновить баннер ####################
echo -e "${COLOR_MAGENTA}Обновить баннер...${COLOR_RESET}"
cp /etc/banner /etc/banner.bak
sed -i 's/W I R E L E S S/N E T W O R K/g' /etc/banner
ADD_TEXT="Kernel $KERNEL_VERSION,"
if ! grep -q "Kernel $KERNEL_VERSION" /etc/banner; then
	sed -i '/, r/s/,/, '"$ADD_TEXT"'/' /etc/banner
fi

#################### Обновить имя хоста ####################
echo -e "${COLOR_MAGENTA}Обновить имя хоста...${COLOR_RESET}"
uci set system.@system[0].hostname="$HOSTNAME_PATTERN"
uci commit system
uci set uhttpd.defaults.commonname="$HOSTNAME_PATTERN"
uci commit uhttpd
echo -e "${COLOR_CYAN}Имя хоста установлено: $HOSTNAME_PATTERN${COLOR_RESET}"

sed -i "s/File Manager/Файловый менеджер/" /usr/share/luci/menu.d/luci-app-filemanager.json && echo -e "${COLOR_CYAN}Обновлен Файловый менеджер${COLOR_RESET}"

#################### Настройка путей для owut (attendedsysupgrade) ####################
echo -e "${COLOR_MAGENTA}Настройка путей для owut...${COLOR_RESET}"
if [ "$NAME_VALUE" == "OpenWrt" ]; then
	sed -i "s|option url 'https://asu-2.kyarucloud.moe'|option url 'https://sysupgrade.openwrt.org'|" /etc/config/attendedsysupgrade
	echo -e "${COLOR_CYAN}owut настроен на OpenWrt${COLOR_RESET}"
else
	sed -i "s|option url 'https://sysupgrade.openwrt.org'|option url 'https://asu-2.kyarucloud.moe'|" /etc/config/attendedsysupgrade
	echo -e "${COLOR_CYAN}owut настроен на ImmortalWrt${COLOR_RESET}"
fi

#################### Настройка и запуск AdGuardHome ####################
echo -e "${COLOR_MAGENTA}Настройка и запуск AdGuardHome...${COLOR_RESET}"

/etc/init.d/adguardhome disable
/etc/init.d/adguardhome stop

# Создание новой рабочей директории
mkdir -p /opt/AdGuardHome

# Установка прав доступа (поскольку теперь используется root)
chown -R root:root /opt/AdGuardHome
chmod 755 /opt/AdGuardHome

# Проверить, существует ли группа 'adguardhome'
if ! grep -q '^adguardhome:' /etc/group; then
	# Если нет - создать ее как системную группу
	echo "adguardhome:x:853:" >> /etc/group
fi
# Проверить, существует ли пользователь 'adguardhome'
if ! grep -q '^adguardhome:' /etc/passwd; then
	# Если нет - создать его как системного пользователя:
	echo "adguardhome:x:853:853:AdGuard Home:/var/lib/adguardhome:/bin/false" >> /etc/passwd
fi

echo -e "${COLOR_CYAN}Настройки для AdGuardHome...${COLOR_RESET}"
cat > /etc/config/adguardhome << 'EOF'
config adguardhome 'config'
	option enabled '1'
	# All paths must be readable by the configured user
	option config_file '/etc/adguardhome/adguardhome.yaml'
	# Where to store persistent data by AdGuard Home
	option work_dir '/opt/AdGuardHome'
	option log_file '/var/AdGuardHome.log'
	option user 'root'
	option group 'root'
	option verbose '0'
	# Files and directories that AdGuard Home has read-only access to
	# list jail_mount '/etc/ssl/adguardhome.crt'
	# list jail_mount '/etc/ssl/adguardhome.key'
EOF

# Настройка init.d/adguardhome
if ! grep -q 'local log_file' /etc/init.d/adguardhome; then
	echo "Строка 'local log_file (legacy config_get log_file)' не найдена. Добавляю..."
	sed -i "/local verbose=0/a \\\tlocal log_file='/var/AdGuardHome.log'" /etc/init.d/adguardhome
	sed -i 's/--logfile syslog/--logfile "$log_file"/' /etc/init.d/adguardhome
else
	echo "Строка 'local log_file' уже существует. Пропускаю добавление."
fi

AGH_version=$(/usr/bin/AdGuardHome --version 2>/dev/null | grep -oP 'v?\K[\d.]+')
echo -e "${COLOR_YELLOW}Установленная версия AGH: $AGH_version${COLOR_RESET}"

# Освобождение порта 53 для AdGuardHome
uci set dhcp.@dnsmasq[0].port="0"
uci delete dhcp.@dnsmasq[0].server
uci commit dhcp
echo -e "${COLOR_CYAN}Остановка ДНС сервера DNSmasq - порт 0...${COLOR_RESET}"

if [ -n "$AGH_version" ]; then
	echo -e "${COLOR_CYAN}Запуск AdGuardHome...${COLOR_RESET}"
	/etc/init.d/adguardhome enable
	/etc/init.d/adguardhome start
	echo -e "${COLOR_WHITE}Запущенная версия AdGuardHome: $AGH_version${COLOR_RESET}"
else
	echo -e "${COLOR_RED}AdGuardHome не установлен или не найден.${COLOR_RESET}"
fi

# Меню для перехода к AdGuardHome
cat << 'EOF' > /usr/lib/lua/luci/controller/adguardhome_net.lua
module("luci.controller.adguardhome_net", package.seeall)

function index()
	entry({"admin", "network", "adguardhome"}, call("redirectToAdGuardHome"), _("AdGuardHome"), 40)
end

function redirectToAdGuardHome()
	local router_ip = luci.http.getenv("SERVER_ADDR") -- Получаем IP-адрес роутера
	local redirect_url = "http://" .. router_ip .. ":8080" -- Собираем URL
	luci.http.redirect(redirect_url) -- Перенаправляем на адрес роутера с портом 8080
end
EOF

#################### Финальные настройки ####################
echo -e "${COLOR_MAGENTA}Финальные настройки системы...${COLOR_RESET}"

# Очистка временных файлов конфигурации
find /etc/config/ -type f -name '*-opkg' -exec rm {} \;
find /etc/config/ -type f -name '*apk-new' -exec rm {} \;
echo -e "${COLOR_CYAN}Удалены временные файлы конфигурации.${COLOR_RESET}"

# Включение FullCone NAT для ImmortalWrt
if [ "$NAME_VALUE" == "ImmortalWrt" ]; then
	uci set firewall.@defaults[0].fullcone='1' && uci commit firewall
	echo -e "${COLOR_WHITE}FullCone NAT включен на ImmortalWrt${COLOR_RESET}"
else
	echo -e "${COLOR_WHITE}Прошивка не ImmortalWrt. FullCone NAT не настраивается.${COLOR_RESET}"
fi

# Расширение интерфейса bootstrap
if ! grep -q "/* LuCI Bootstrap: Custom Fullwidth CSS */" /www/luci-static/bootstrap/cascade.css; then
	cat << 'EOF' >> /www/luci-static/bootstrap/cascade.css

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

# Включить sqm
/etc/init.d/sqm disable
/etc/init.d/sqm enable
echo "sqm включен"

#Отключаем старый скрипт управления диодами phy-leds
/etc/init.d/phy-leds disable

cat /tmp/sysinfo/model && . /etc/openwrt_release

echo -e "${COLOR_GREEN}Первоначальная настройка завершена успешно.${COLOR_RESET}"

# Отложенная перезагрузка в фоне (&) в дочерней оболочке ()...
echo -e "${COLOR_GREEN}Запрос на перезагрузку системы...${COLOR_RESET}"
(sleep 120; sync; reboot) &

# ВАЖНО: Завершаем скрипт с кодом 0 для его автоматического удаления
exit 0
