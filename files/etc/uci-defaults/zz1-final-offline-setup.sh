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

# --- БЛОК ЗАЩИТЫ ОТ ПОВТОРНОГО ЗАПУСКА ---
LOCK_FILE="/root/.setup_completed"
#if [ -f "$LOCK_FILE" ]; then
#if [ -f "$LOCK_FILE" ] && { [ "$CURRENT_VARIANT" = "clear" ] || [ "$CURRENT_VARIANT" = "crystal_clear" ]; }; then
#    echo "Скрипт уже был выполнен ранее."
#    exit 0
#fi
# -----------------------------------------

# --------------------------------------------------------------------------------------------------------------------
#      НАСТРОЙКА РОУТЕРА      ########################################################
# --------------------------------------------------------------------------------------------------------------------

echo -e "СКРИПТ ПЕРВОНАЧАЛЬНОЙ ОФЛАЙН-НАСТРОЙКИ РОУТЕРА"

#################### Удалить строку Enable FullCone NAT (если нужно) ####################
echo -e "Удалить строку Enable FullCone NAT..."
sed -i "/option fullcone '1'/d" /etc/config/firewall

#################### Настройка системного времени (без NTP) ####################
echo -e "Настройка часового пояса..."
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
#-#/etc/init.d/system reload
date

#################### Подготовка системы к установке пакетов ####################
echo -e "Подготовка системы к установке пакетов..."

# Проверяем, какой пакетный менеджер используется
if command -v apk >/dev/null 2>&1; then
	echo -e "Обнаружен пакетный менеджер APK."
	# 1. Убедимся, что архитектура указана верно
	if ! grep -qF "${ARCH_VERSION}" /etc/apk/arch; then
		echo -e "Добавляю архитектуру ${ARCH_VERSION} в /etc/apk/arch..."
		echo "${ARCH_VERSION}" > /etc/apk/arch
	else
		echo -e "Архитектура в /etc/apk/arch уже настроена."
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
	echo -e "Обнаружен пакетный менеджер OPKG."
else
	echo -e "Ошибка: Пакетный менеджер (apk или opkg) не найден."
fi

if [ -f "$DISTFEEDS_FILE" ]; then
	echo -e "Очистка файла репозиториев $DISTFEEDS_FILE..."
	# Создаем бэкап на всякий случай
	cp "$DISTFEEDS_FILE" "${DISTFEEDS_FILE}.bak"
	# Фильтруем содержимое файла и сохраняем результат в переменную
	FILTERED_CONTENT=$(grep -E "targets|packages/${ARCH_VERSION}/(base|luci|packages|routing|telephony|video)" "$DISTFEEDS_FILE")
	# Проверяем, что переменная не пустая, прежде чем перезаписывать файл
	if [ -n "$FILTERED_CONTENT" ]; then
		echo "$FILTERED_CONTENT" > "$DISTFEEDS_FILE"
		echo -e "Файл репозиториев успешно очищен."
	else
		echo -e "Ошибка: Фильтрация не нашла ни одной нужной строки! Оригинальный файл не изменен."
	fi

    # --- АВТОМАТИЧЕСКОЕ ДОБАВЛЕНИЕ KMODS (ТОЛЬКО ДЛЯ APK) ---
    if command -v apk >/dev/null 2>&1; then
        echo -e "Попытка автоматического добавления репозитория kmods..."
        
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
            
            echo -e "Определена версия ядра: ${K_VER_TEMP} -> Папка: ${K_MODS_DIR}"
            
            # 2. Ищем базовый URL в существующем файле
            BASE_REPO_URL=$(grep "/targets/.*/packages/packages.adb" "$DISTFEEDS_FILE" | head -n1)
            
            if [ -n "$BASE_REPO_URL" ]; then
                # Отрезаем хвост '/packages/packages.adb'
                TARGET_BASE=$(echo "$BASE_REPO_URL" | sed 's|/packages/packages\.adb||')
                
                # 3. Формируем URL
                KMODS_URL="${TARGET_BASE}/kmods/${K_MODS_DIR}/packages.adb"
                
                # 4. Проверяем и записываем
                if ! grep -q "$KMODS_URL" "$DISTFEEDS_FILE"; then
                    echo -e "Добавляю репозиторий kmods: ${KMODS_URL}"
                    echo "$KMODS_URL" >> "$DISTFEEDS_FILE"
                else
                    echo -e "Репозиторий kmods уже присутствует."
                fi
            else
                echo -e "Ошибка: Не удалось найти базовый URL в $DISTFEEDS_FILE"
            fi
        else
            echo -e "Ошибка: Не удалось определить версию ядра через apk list."
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
echo -e "Установка пакетов из локальной директории..."

if [ -f /root/apps/sing-box.tar.gz ]; then
	echo -e "Установка sing-box..."
	/etc/init.d/sing-box stop >/dev/null 2>&1
	tar -xzf /root/apps/sing-box.tar.gz -C /tmp/
	rm /root/apps/sing-box.tar.gz
	cp /tmp/sing-box /usr/bin/sing-box
	chmod +x /usr/bin/sing-box
	echo -e "Установлен sing-box из /root/apps/"
else
	echo -e "Файл sing-box не найден в /root/apps/. Пропускаем установку."
fi

if [ -f /root/apps/speedtest.tar.gz ]; then
	echo -e "Установка speedtest..."
	tar -xzf /root/apps/speedtest.tar.gz -C /tmp/
	rm /root/apps/speedtest.tar.gz
	cp /tmp/speedtest /usr/bin/speedtest
	chmod +x /usr/bin/speedtest
	echo -e "Установлен speedtest из /root/apps/"
else
	echo -e "Файл speedtest не найден в /root/apps/. Пропускаем установку."
fi

#################### Настройка homeproxy ####################
# Проверяем, установлен ли homeproxy, прежде чем пытаться его настраивать
if [ -f "/etc/init.d/homeproxy" ]; then

	echo -e "Настройка luci-app-homeproxy..."
	echo -e "Отключаем dns_hijacked в luci-app-homeproxy"
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
	echo -e "Создан скрипт-помощник для homeproxy: $HELPER_SCRIPT_PATH"
	# 2. Модифицируем init-скрипт homeproxy, чтобы он вызывал скрипт помощник
	HOMEPROXY_INIT_SCRIPT="/etc/init.d/homeproxy"

	HELPER_CALL_COMMAND="${TAB_CHAR}. ${HELPER_SCRIPT_PATH}"
	if [ -f "$HOMEPROXY_INIT_SCRIPT" ]; then
		# Проверяем, не была ли команда добавлена ранее
		if ! grep -q "$HELPER_SCRIPT_PATH" "$HOMEPROXY_INIT_SCRIPT"; then
			# Вставляем вызов нашего скрипта в начало start_service() и stop_service()
			sed -i "/start_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
			sed -i "/stop_service() {/a \\$HELPER_CALL_COMMAND" "$HOMEPROXY_INIT_SCRIPT"
			echo -e "Init-скрипт homeproxy модифицирован для вызова помощника."
		else
			echo -e "Init-скрипт homeproxy уже был модифицирован."
		fi
	else
		echo -e "Скрипт $HOMEPROXY_INIT_SCRIPT не найден."
	fi
	# 3. Первоначальный запуск помощника, чтобы исправить конфиг сразу
	. "$HELPER_SCRIPT_PATH"

	/etc/init.d/homeproxy enable

	echo -e "luci-app-homeproxy настроен."

	SB_version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP -m 1 'v?\K[\d.]+')
	echo -e "\e[37mУстановленная версия sing-box: $SB_version\e[0m"

else
    echo -e "Пакет homeproxy не найден. Настройка пропущена."
fi

#################### Настройка Passwall 2 (Интеграция с AGH) ####################
# Проверяем, установлен ли passwall2
PASSWALL_INIT="/etc/init.d/passwall2"

if [ -f "$PASSWALL_INIT" ]; then
    echo -e "Настройка Passwall 2 для работы с AdGuardHome..."
    
    # Отключаем службу перед настройкой
    "$PASSWALL_INIT" disable
    "$PASSWALL_INIT" stop >/dev/null 2>&1

    # --- КОНФИГУРАЦИЯ ЧЕРЕЗ UCI ---
    uci -q batch <<-EOF
        set passwall2.@global[0].dns_redirect='0'
		set passwall2.@global[0].dns_shunt='closed'
		set passwall2.@global[0].remote_dns='127.0.0.1:53'
        set passwall2.@global[0].china_dns='127.0.0.1:53'
		set passwall2.@global[0].adblock='0'
		set passwall2.@global[0].enabled='1'
		commit passwall2
EOF
    
    echo -e "DNS перехват в Passwall 2 отключен. DNS полностью управляется AdGuardHome."

    # Включаем службу
    "$PASSWALL_INIT" enable
    echo -e "Passwall 2 настроен и включен."
    
else
    echo -e "Passwall 2 не найден. Пропуск."
fi

#################### Настройка youtubeUnblock ####################
echo -e "Настройка youtubeUnblock..."

echo -e "Проверка и создание необходимых IPSet'ов..."
# Список всех ipset'ов, которые используются в правилах ниже.
# Если добавишь новое правило с новым ipset'ом, просто добавь его имя сюда.
REQUIRED_IPSETS="dpi_ips no_dpi_ips dpi_guest_ips"
FIREWALL_CONFIG_CHANGED=0
for ipset_name in $REQUIRED_IPSETS; do
    # Ищем ipset с таким именем в конфиге firewall.
    # `uci show firewall` выводит всю конфигурацию.
    # `grep` ищет строку вида: firewall.cfgXXXXXX.name='имя_нашего_ipset'
    if ! uci show firewall | grep -q "\.name='$ipset_name'"; then
        echo "--> IPSet '$ipset_name' не найден. Создаем его как пустой..."
        # 1. Создаем новую секцию ipset и получаем ее ID (например, cfg037416)
        handle=$(uci add firewall ipset)
        # 2. Устанавливаем параметры для этой новой секции
        uci set firewall."$handle".name="$ipset_name"
        uci set firewall."$handle".match="net"
        uci set firewall."$handle".family="ipv4" # или "ipv6", если нужно. Для DPI обычно ipv4.
        # Устанавливаем флаг, что конфиг был изменен
        FIREWALL_CONFIG_CHANGED=1
    else
        echo "--> IPSet '$ipset_name' уже существует. Пропускаем."
    fi
done
# Если мы внесли хотя бы одно изменение, коммитим конфиг firewall
if [ "$FIREWALL_CONFIG_CHANGED" -eq 1 ]; then
    echo "Сохранение изменений в /etc/config/firewall..."
    uci commit firewall
    # Можно добавить перезагрузку firewall, чтобы изменения применились немедленно,
    # хотя init-скрипт youtubeUnblock, скорее всего, сделает это сам.
    # /etc/init.d/firewall reload
fi

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
	iifname "br-guest" ip saddr != @dpi_guest_ips meta mark set 0x00000042
}
EOF
)

# Проверяем, установлен ли youtubeUnblock. 
if [ -x "/usr/bin/youtubeUnblock" ]; then
	echo -e "Служба youtubeUnblock установлена. Применяем конфигурацию..."
	# Отключаем службу на время настройки
	/etc/init.d/youtubeUnblock disable
	echo "$YTB_NFT_FILE_CONTENT" > "$YTB_NFT_FILE"
	chmod 0644 "$YTB_NFT_FILE"
	echo "$YTB_NFT_GUEST_MARK_CONTENT" > "$YTB_NFT_GUEST_MARK_FILE"
	chmod 0644 "$YTB_NFT_GUEST_MARK_FILE"
	/etc/init.d/youtubeUnblock enable
	echo -e "youtubeUnblock настроен и включен."
else
	echo -e "Служба youtubeUnblock не установлена. Настройка пропущена."
fi

#################### Настройка internet-detector ####################
if [ -f "/etc/init.d/internet-detector" ]; then
	echo -e "Настройка internet-detector..."
	/etc/init.d/internet-detector disable
	sed -i 's/START=[0-9][0-9]/START=99/' /etc/init.d/internet-detector
	echo -e "Служба internet-detector настроена (но отключена)."
fi

#################### Настройка путей для owut (attendedsysupgrade) ####################
echo -e "Настройка путей для owut..."
if [ "$NAME_VALUE" == "OpenWrt" ]; then
	sed -i "s|option url 'https://asu-2.kyarucloud.moe'|option url 'https://sysupgrade.openwrt.org'|" /etc/config/attendedsysupgrade
	echo -e "owut настроен на OpenWrt"
else
	sed -i "s|option url 'https://sysupgrade.openwrt.org'|option url 'https://asu-2.kyarucloud.moe'|" /etc/config/attendedsysupgrade
	echo -e "owut настроен на ImmortalWrt"
fi

#################### Настройка и запуск AdGuardHome ####################
if [ -x "/usr/bin/AdGuardHome" ] && [ -f "/etc/config/adguardhome" ]; then
    echo -e "Настройка параметров AdGuardHome через UCI..."

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

    # Применяем настройки ко всем вариантам (универсальный подход) может понадобится set adguardhome.config.enabled='1'
    uci -q batch <<EOF
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
	
	luci.http.prepare_content("text/html")
	luci.http.write(string.format([[
		<script>window.location='%s'; window.open('%s', '_blank');</script>
		<a href="%s" target="_blank">Click here if redirect fails</a>
	]], "javascript:history.back()", redirect_url, redirect_url))
end
EOF

    # Освобождение порта 53 для AdGuardHome
    uci set dhcp.@dnsmasq[0].port="54"
    uci delete dhcp.@dnsmasq[0].server
    uci commit dhcp

    /etc/init.d/adguardhome enable
    /etc/init.d/adguardhome start
    echo -e "AdGuardHome успешно настроен и запущен."
else
    echo -e "AdGuardHome не установлен или конфиг отсутствует. Пропуск."
fi

#################### Патч для SQM (Внешний файл конфигурации) ####################
echo -e "Настройка SQM на использование внешнего конфига /opt/sqm_custom.conf..."

# 1. Проверяем текущее состояние SQM в конфиге (включен или нет)
# Если опция не задана или равна 0, считаем, что сервис выключен.
SQM_ENABLED_STATE=$(uci -q get sqm.@queue[0].enabled)

SQM_RUN_SCRIPT="/usr/lib/sqm/run.sh"
CUSTOM_CONF="/opt/sqm_custom.conf"

if [ -f "$SQM_RUN_SCRIPT" ]; then

    # 2. Создаем файл кастомных настроек
    mkdir -p /opt
    cat > "$CUSTOM_CONF" <<EOF
# Custom SQM Options
# LuCI удаляет эти опции из /etc/config/sqm, поэтому мы храним их здесь.
# nowash - нужен для работы ручных правил DSCP (VIP gaming)
# diffserv4 - разделяет трафик на 4 полосы (Voice, Video, BestEffort, Bulk)

option iqdisc_opts 'nat dual-dsthost diffserv4 nowash'
option eqdisc_opts 'nat dual-srchost diffserv4 nowash'
EOF
    echo -e "Создан файл $CUSTOM_CONF"

    # 3. Патчим run.sh, чтобы он читал этот файл
    if ! grep -q "sqm_custom.conf" "$SQM_RUN_SCRIPT"; then
        echo ">>> Внедрение чтения $CUSTOM_CONF в $SQM_RUN_SCRIPT ..."
        
        cat <<'EOF' > /tmp/sqm_loader.txt

    # --- Load Custom Config (/opt/sqm_custom.conf) ---
    if [ -f "/opt/sqm_custom.conf" ]; then
        cust_i=$(grep "^option iqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        cust_e=$(grep "^option eqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        
        [ -n "$cust_i" ] && export IQDISC_OPTS="$cust_i"
        [ -n "$cust_e" ] && export EQDISC_OPTS="$cust_e"
    fi
    # -------------------------------------------------
EOF
        sed -i '/export EQDISC_OPTS/r /tmp/sqm_loader.txt' "$SQM_RUN_SCRIPT"
        rm /tmp/sqm_loader.txt
        echo -e "Скрипт SQM успешно пропатчен."
    else
        echo -e "Скрипт SQM уже настроен на чтение custom файла."
    fi

    # 4. Умный перезапуск (только если SQM был включен)
    if [ "$SQM_ENABLED_STATE" == "1" ]; then
        echo -e "SQM активен в конфиге. Перезапуск для применения патча..."
        /etc/init.d/sqm enable
        /etc/init.d/sqm restart
        echo -e "SQM успешно перезапущен."
    else
        echo -e "SQM отключен в конфиге (enabled='0' или отсутствует). Служба не запущена."
        # На всякий случай убираем из автозагрузки, если он там был
        /etc/init.d/sqm disable 2>/dev/null
    fi

else
    echo -e "Пакет SQM не установлен. Пропуск."
fi

#################### Финальные настройки ####################
echo -e "Финальные настройки системы..."

# Очистка временных файлов конфигурации
find /etc/config/ -type f -name '*-opkg' -exec rm {} \;
find /etc/config/ -type f -name '*apk-new' -exec rm {} \;
echo -e "Удалены временные файлы конфигурации."

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
	echo -e "FullCone NAT включен"
else
	echo -e "FullCone не доступен"
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
    echo -e "TCP BBR включен."
else
    # Если BBR недоступен, убираем настройки, чтобы не было ошибок при загрузке
    sed -i '/net\.core\.default_qdisc.*fq/d; /net\.ipv4\.tcp_congestion_control.*bbr/d; /# TCP BBR/d' /etc/sysctl.conf
    echo -e "TCP BBR недоступен."
fi

#Отключаем старый скрипт управления диодами phy-leds
if [ -x "/etc/init.d/phy-leds" ]; then
	/etc/init.d/phy-leds disable
fi

# =========================================================
# СПЕЦИАЛЬНАЯ НАСТРОЙКА ДЛЯ РЕЖИМА СВИТЧА (switch)
# =========================================================

cat /tmp/sysinfo/model && . /etc/openwrt_release && cat /etc/build_variant

if [ ! -f "$LOCK_FILE" ] && [ "$CURRENT_VARIANT" = "switch" ]; then
    echo -e ">>> АКТИВАЦИЯ РЕЖИМА КОММУТАТОРА (SWITCH) <<<"
    echo "Настройка сетевых интерфейсов, моста и защиты от петель..."
    uci delete network.lan
    uci delete network.wan
    uci delete network.wan6
    RAW_PORTS=$(ls /sys/class/net/)
    # Фильтр для исключения системных интерфейсов и Wi-Fi
    EXCLUDE_PATTERN="^lo$|^sit|^tun|^br-|^wlan|^phy|^mon|^bond|^veth|^docker"
    if echo "$RAW_PORTS" | grep -qE "^p[0-9]+"; then
        echo "Обнаружена архитектура DSA (есть порты p1...). Исключаем eth0."
        FILTERED_PORTS=$(echo "$RAW_PORTS" | grep -vE "$EXCLUDE_PATTERN|^eth0$" | tr '\n' ' ')
    else
        echo "Архитектура DSA не обнаружена. Оставляем eth0."
        FILTERED_PORTS=$(echo "$RAW_PORTS" | grep -vE "$EXCLUDE_PATTERN" | tr '\n' ' ')
    fi
    FILTERED_PORTS=$(echo $FILTERED_PORTS)
    echo $FILTERED_PORTS
    uci set network.@device[0].name='br-lan'
    uci set network.@device[0].type='bridge'
    uci set network.@device[0].ports="$FILTERED_PORTS"
    uci set network.@device[0].stp='1'
    uci set network.@device[0].igmp_snooping='1'
    uci set network.@device[0].multicast_querier='1'
    uci set network.lan=interface
    uci set network.lan.device='br-lan'
    uci set network.lan.proto='dhcp'
    uci set network.lan.ip6assign='0'
	uci set network.@device[0].ipv6='0'
	uci set network.globals.packet_steering='2'
    uci -q delete network.globals.ula_prefix
    echo "Отключение встроенного DHCP-сервера..."
    uci set dhcp.lan.ignore='1'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ra='disabled'
    uci -q delete dhcp.odhcpd
    uci set dhcp.odhcpd=odhcpd
    uci set dhcp.odhcpd.disabled='1'
	/etc/init.d/odhcpd disable
    echo "Упрощение Firewall и включение аппаратного ускорения..."
    uci -q delete firewall.@zone[1]
    uci -q delete firewall.@forwarding[0]
    uci set firewall.@defaults[0].flow_offloading='1'
    uci set firewall.@defaults[0].flow_offloading_hw='1'
    uci set firewall.@zone[0].name='lan'
    uci set firewall.@zone[0].network='lan'
    uci set firewall.@zone[0].input='ACCEPT'
    uci set firewall.@zone[0].output='ACCEPT'
    uci set firewall.@zone[0].forward='ACCEPT'
    while uci -q delete firewall.@rule[0]; do :; done
	uci -q delete dhcp.wan
    echo "Сохранение конфигурации..."
    uci commit
    echo -e "Роутер переведен в режим управляемого свитча. IP будет получен по DHCP."
fi

if [ "$CURRENT_VARIANT" = "switch" ]; then
    HOSTNAME_PATTERN="${ROUTER_MODEL_NAME}-${CURRENT_VARIANT}"
fi

# =========================================================
# ФИНАЛЬНЫЙ БЛОК: СИНХРОНИЗАЦИЯ ВРЕМЕНИ И БАННЕР
# Перенесен в конец, чтобы успели отработать драйверы RTC
# =========================================================
# 1. Считываем время из аппаратных часов (RTC)
# Это самое важное для R5S/R6S! Исправляет "2104" или "1970" сразу, даже без интернета.
if command -v hwclock >/dev/null 2>&1; then
    echo "Syncing from Hardware Clock (RTC)..."
    hwclock -s -u 2>/dev/null
fi
# 2. Если есть интернет, пробуем точную синхронизацию по NTP
# Проверяем доступность Google DNS (как маркер интернета)
if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    echo "Internet detected. Forcing NTP sync..."
    # Останавливаем фоновую службу, чтобы освободить порт UDP 123
    /etc/init.d/sysntpd stop 2>/dev/null
    # Принудительная синхронизация (ntpd из BusyBox)
    # -q: выйти после синхронизации
    # -n: не уходить в фон
    # -p: сервер времени
    ntpd -q -n -p ru.pool.ntp.org 2>/dev/null
    # Запускаем службу обратно
    /etc/init.d/sysntpd start 2>/dev/null
    # Записываем точное время обратно в аппаратные часы (чтобы сохранить его на будущее)
    if command -v hwclock >/dev/null 2>&1; then
        hwclock -w -u 2>/dev/null
    fi
    echo -e "Time synced with internet."
else
    echo -e "No internet connection. Using RTC time."
	date
    # Просто убеждаемся, что служба запущена
    /etc/init.d/sysntpd restart 2>/dev/null
fi
# Даем системе пару секунд на осознание изменений
sleep 2
# 3. Обновление баннера (Теперь с правильной датой)
echo -e "Обновление баннера..."
cp /etc/banner /etc/banner.bak
sed -i 's/W I R E L E S S/N E T W O R K/g' /etc/banner
# Удаляем старые записи
sed -i "/Build Variant:/d" /etc/banner
sed -i "/Kernel Version:/d" /etc/banner
# Формируем строку даты
if [ -f "/etc/build_date" ]; then
    DATE_STR=$(cat /etc/build_date)
else
    CURRENT_YEAR=$(date +%Y)
    # Если год выглядит адекватным (между 2025 и 2050)
    if [ "$CURRENT_YEAR" -ge 2025 ] && [ "$CURRENT_YEAR" -le 2050 ]; then
        DATE_STR=$(date +'%Y-%m-%d')
    else
        DATE_STR="***"
    fi
fi

echo " Kernel Version: $KERNEL_VERSION" >> /etc/banner
echo " Build Variant: $CURRENT_VARIANT ($DATE_STR)" >> /etc/banner

echo -e "Первоначальная настройка завершена успешно."

#################### Обновить имя хоста ####################
echo -e "Обновить имя хоста..."
uci set system.@system[0].hostname="$HOSTNAME_PATTERN"
uci commit system
uci set uhttpd.defaults.commonname="$HOSTNAME_PATTERN"
uci commit uhttpd
echo -e "Имя хоста установлено: $HOSTNAME_PATTERN"

sed -i "s/File Manager/Файловый менеджер/" /usr/share/luci/menu.d/luci-app-filemanager.json && echo -e "Обновлен Файловый менеджер"

# --- СОЗДАЕМ LOCK-ФАЙЛ ПЕРЕД ВЫХОДОМ ---
touch "$LOCK_FILE"
# --------------------------------------

# Отложенная перезагрузка в фоне (&) в дочерней оболочке ()...
echo -e "Запрос на перезагрузку системы..."
(sleep 120; sync; reboot) &

# ВАЖНО: Завершаем скрипт с кодом 0 для его автоматического удаления
exit 0
