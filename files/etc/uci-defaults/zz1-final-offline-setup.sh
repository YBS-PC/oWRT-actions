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

MY_ROUTER=$(ubus call system board | grep '"board_name"' | cut -d '"' -f 4 | cut -d ',' -f 2)
MODEL_FULL=$(ubus call system board | grep '"model"' | cut -d '"' -f 4)
ROUTER_MODEL=$(echo $MODEL_FULL | awk '{print $NF}')
ROUTER_MODEL_NAME=$(case "$ROUTER_MODEL" in 
	"GL-MT2500") echo "Brume2" ;; 
	"R5S") echo "R5S" ;;
	"R6S") echo "R6S" ;;
	"GL-AXT1800") echo "SLATEX" ;;
	"RB5009") echo "RB5009" ;;
	*) echo "$MY_ROUTER" ;; 
esac)

HOSTNAME_PATTERN="${ROUTER_MODEL_NAME}-${ROUTER_NAME}"

TAB_CHAR=$(printf '\t')

# Читаем вариант из файла, который создал WRT-part3.sh
CURRENT_VARIANT=$(cat /etc/build_variant 2>/dev/null | head -n 1)
echo "Detected Build Variant: ${CURRENT_VARIANT:-unknown}"

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

    # --- АВТОМАТИЧЕСКОЕ ДОБАВЛЕНИЕ KMODS (ТОЛЬКО ДЛЯ APK) ---
    if command -v apk >/dev/null 2>&1; then
        echo -e "${COLOR_MAGENTA}Попытка автоматического добавления репозитория kmods...${COLOR_RESET}"
        
        # 1. Получаем полную версию пакета через apk list
        # 2>/dev/null убирает WARNING о кеше, head -n1 берет первую строку, awk берет первое слово (имя-версия)
        KERNEL_PKG=$(apk list -I kernel 2>/dev/null | head -n1 | awk '{print $1}')
        
        if [ -n "$KERNEL_PKG" ]; then
            # Убираем префикс 'kernel-' (остается: 6.12.63~hash-r1)
            K_VER_TEMP=${KERNEL_PKG#kernel-}
            
            # Убираем суффикс ревизии '-rX' (остается: 6.12.63~hash)
            K_VER_TEMP=${K_VER_TEMP%-r*}
            
            # Заменяем тильду '~' на '-1-', чтобы получить формат пути сервера
            # Результат: 6.12.63-1-hash
            K_MODS_DIR=$(echo "$K_VER_TEMP" | sed 's/~/-1-/')
            
            echo -e "${COLOR_CYAN}Определена версия ядра: ${K_VER_TEMP} -> Папка: ${K_MODS_DIR}${COLOR_RESET}"
            
            # 2. Ищем базовый URL в существующем файле
            BASE_REPO_URL=$(grep "/targets/.*/packages/packages.adb" "$DISTFEEDS_FILE" | head -n1)
            
            if [ -n "$BASE_REPO_URL" ]; then
                # Отрезаем хвост '/packages/packages.adb'
                TARGET_BASE=$(echo "$BASE_REPO_URL" | sed 's|/packages/packages\.adb||')
                
                # 3. Формируем URL
                KMODS_URL="${TARGET_BASE}/kmods/${K_MODS_DIR}/packages.adb"
                
                # 4. Проверяем и записываем
                if ! grep -q "$KMODS_URL" "$DISTFEEDS_FILE"; then
                    echo -e "${COLOR_GREEN}Добавляю репозиторий kmods: ${KMODS_URL}${COLOR_RESET}"
                    echo "$KMODS_URL" >> "$DISTFEEDS_FILE"
                else
                    echo -e "${COLOR_YELLOW}Репозиторий kmods уже присутствует.${COLOR_RESET}"
                fi
            else
                echo -e "${COLOR_RED}Ошибка: Не удалось найти базовый URL в $DISTFEEDS_FILE${COLOR_RESET}"
            fi
        else
            echo -e "${COLOR_RED}Ошибка: Не удалось определить версию ядра через apk list.${COLOR_RESET}"
        fi
    fi
    # --------------------------------------------------------

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
# Проверяем, установлен ли homeproxy, прежде чем пытаться его настраивать
if [ -f "/etc/init.d/homeproxy" ]; then

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

else
    echo -e "${COLOR_YELLOW}Пакет homeproxy не найден. Настройка пропущена.${COLOR_RESET}"
fi

#################### Настройка Passwall 2 (Интеграция с AGH) ####################
# Проверяем, установлен ли passwall2
PASSWALL_INIT="/etc/init.d/passwall2"

if [ -f "$PASSWALL_INIT" ]; then
    echo -e "${COLOR_MAGENTA}Настройка Passwall 2 для работы с AdGuardHome...${COLOR_RESET}"
    
    # Отключаем службу перед настройкой
    "$PASSWALL_INIT" disable
    "$PASSWALL_INIT" stop >/dev/null 2>&1

    # --- КОНФИГУРАЦИЯ ЧЕРЕЗ UCI ---
    uci -q batch <<-EOF
        # 1. Отключаем перехват DNS (Redirect/Tproxy на 53 порту)
        set passwall2.@global[0].dns_redirect='0'
        
        # 2. Отключаем Shunt (разделение DNS), так как AGH сам все решит
        set passwall2.@global[0].dns_shunt='closed'
        
        # 3. Указываем Passwall использовать локальный AGH как DNS
        set passwall2.@global[0].remote_dns='127.0.0.1:53'
        set passwall2.@global[0].china_dns='127.0.0.1:53'
        
        # 4. Отключаем любые попытки фильтрации UDP
        set passwall2.@global[0].adblock='0'
        
        # 5. Убеждаемся, что Passwall включен глобально
        set passwall2.@global[0].enabled='1'
        
        commit passwall2
EOF
    
    echo -e "${COLOR_WHITE}DNS перехват в Passwall 2 отключен. DNS полностью управляется AdGuardHome.${COLOR_RESET}"

    # Включаем службу
    "$PASSWALL_INIT" enable
    echo -e "${COLOR_GREEN}Passwall 2 настроен и включен.${COLOR_RESET}"
    
else
    echo -e "${COLOR_YELLOW}Passwall 2 не найден. Пропуск.${COLOR_RESET}"
fi

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

# If the destination IP is in the no_dpi_ips list, we exit the chain.
add rule inet fw4 youtubeUnblock ip daddr @no_dpi_ips counter return

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
	iifname "br-guest" ip saddr != @dpi_local_ips meta mark set 0x00000042
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
# Удаляем старую запись о варианте, если она есть
sed -i "/Build Variant:/d" /etc/banner
sed -i "/Kernel Version:/d" /etc/banner
# Добавляем новые строки в конец
echo " Kernel Version: $KERNEL_VERSION" >> /etc/banner
echo " Build Variant: $CURRENT_VARIANT ($(date +'%Y-%m-%d'))" >> /etc/banner

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
if [ -x "/usr/bin/AdGuardHome" ] && [ -f "/etc/config/adguardhome" ]; then
    echo -e "${COLOR_MAGENTA}Настройка параметров AdGuardHome через UCI...${COLOR_RESET}"

    # Отключаем на время настройки
    /etc/init.d/adguardhome disable
    /etc/init.d/adguardhome stop

    # Подготовка путей
    mkdir -p /opt/AdGuardHome
    chown -R root:root /opt/AdGuardHome
    chmod 755 /opt/AdGuardHome
    
    # Создаем пользователей/группы (на всякий случай для системы)
    if ! grep -q '^adguardhome:' /etc/group; then echo "adguardhome:x:853:" >> /etc/group; fi
    if ! grep -q '^adguardhome:' /etc/passwd; then echo "adguardhome:x:853:853:AdGuard Home:/var/lib/adguardhome:/bin/false" >> /etc/passwd; fi

    # Применяем настройки ко всем вариантам (универсальный подход)
    uci -q batch <<EOF
        set adguardhome.config.enabled='1'
        set adguardhome.config.work_dir='/opt/AdGuardHome'
        set adguardhome.config.user='root'
        set adguardhome.config.group='root'
        commit adguardhome
EOF

    # Патч init-скрипта (Handling Jail vs Classic)
    if grep -q "procd_add_jail" /etc/init.d/adguardhome; then
        echo ">>> [Jail] Patching init script..."
        if ! grep -q 'local log_file' /etc/init.d/adguardhome; then
            sed -i "/local verbose=0/a ${TAB_CHAR}local log_file='/var/AdGuardHome.log'" /etc/init.d/adguardhome
            sed -i 's/--logfile syslog/--logfile "$log_file"/' /etc/init.d/adguardhome
        fi
    else
        echo ">>> [Classic] Patching old-style init script..."
        if ! grep -q 'config_get LOG_FILE' /etc/init.d/adguardhome; then
            sed -i "/config_get PID_FILE/a ${TAB_CHAR}config_get LOG_FILE config logfile '/var/AdGuardHome.log'" /etc/init.d/adguardhome
            sed -i 's/--pidfile "\$PID_FILE"/--pidfile "\$PID_FILE" --logfile "\$LOG_FILE"/' /etc/init.d/adguardhome
        fi
    fi

    # Меню для перехода к AdGuardHome в LuCI
    cat << 'EOF' > /usr/lib/lua/luci/controller/adguardhome_net.lua
module("luci.controller.adguardhome_net", package.seeall)
function index()
	entry({"admin", "network", "adguardhome"}, call("redirectToAdGuardHome"), _("AdGuardHome"), 40)
end
function redirectToAdGuardHome()
	local router_ip = luci.http.getenv("SERVER_ADDR")
	local redirect_url = "http://" .. router_ip .. ":8080"
	luci.http.redirect(redirect_url)
end
EOF

    # Освобождение порта 53 для AdGuardHome
    uci set dhcp.@dnsmasq[0].port="54"
    uci delete dhcp.@dnsmasq[0].server
    uci commit dhcp

    /etc/init.d/adguardhome enable
    /etc/init.d/adguardhome start
    echo -e "${COLOR_GREEN}AdGuardHome успешно настроен и запущен.${COLOR_RESET}"
else
    echo -e "${COLOR_RED}AdGuardHome не установлен или конфиг отсутствует. Пропуск.${COLOR_RESET}"
fi

#################### Финальные настройки ####################
echo -e "${COLOR_MAGENTA}Финальные настройки системы...${COLOR_RESET}"

# Очистка временных файлов конфигурации
find /etc/config/ -type f -name '*-opkg' -exec rm {} \;
find /etc/config/ -type f -name '*apk-new' -exec rm {} \;
echo -e "${COLOR_CYAN}Удалены временные файлы конфигурации.${COLOR_RESET}"

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

# Включение FullCone NAT
if [ -f "/lib/modules/$(uname -r)/nft_fullcone.ko" ] || lsmod | grep -q nft_fullcone || [ -d "/sys/module/nft_fullcone" ]; then
	uci set firewall.@defaults[0].fullcone='1' && uci commit firewall
	echo -e "${COLOR_WHITE}FullCone NAT включен${COLOR_RESET}"
else
	echo -e "${COLOR_WHITE}FullCone не доступен${COLOR_RESET}"
fi

# Включить TCP BBR
# Мы проверяем наличие модуля tcp_bbr.ko в папке с модулями текущего ядра ИЛИ наличие bbr в списке доступных алгоритмов в procfs
if [ -f "/lib/modules/$(uname -r)/tcp_bbr.ko" ] || grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    # Если BBR доступен, удаляем старые/конфликтующие записи из sysctl.conf
    sed -i '/# TCP BBR/d; /net\.core\.default_qdisc.*fq/d; /net\.ipv4\.tcp_congestion_control.*bbr/d' /etc/sysctl.conf
    # Удаляем пустые строки в конце файла
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/sysctl.conf
    # Добавляем правильные настройки: fq_codel для совместимости с CAKE и bbr для TCP
    echo -e "\n# TCP BBR\nnet.core.default_qdisc = fq_codel\nnet.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo -e "${COLOR_GREEN}TCP BBR включен.${COLOR_RESET}"
else
    # Если BBR недоступен, убираем настройки, чтобы не было ошибок при загрузке
    sed -i '/net\.core\.default_qdisc.*fq/d; /net\.ipv4\.tcp_congestion_control.*bbr/d; /# TCP BBR/d' /etc/sysctl.conf
    echo -e "${COLOR_YELLOW}TCP BBR недоступен.${COLOR_RESET}"
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
