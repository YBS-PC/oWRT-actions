#!/bin/sh

# ===============================================
#      UCI-DEFAULTS ОФЛАЙН-СКРИПТ НАСТРОЙКИ
# ===============================================
# Имя файла: /etc/uci-defaults/zz1-final-offline-setup.sh
# ===============================================

# Функции логирования (без local для POSIX-совместимости)
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"; }
log_ok()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]   $*"; }
log_err()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERR]  $*"; }

# Обёртка выполнения команды
run_cmd() {
    desc="$1"; shift
    log_info "$desc"
    if "$@"; then
        log_ok "$desc"
        return 0
    else
        rc=$?
        log_err "$desc (exit: $rc)"
        return $rc
    fi
}

# Только для команд, где ожидаемый "провал" не является ошибкой (uci -q delete и т.п.)
run_cmd_ign() {
    desc="$1"; shift
    log_info "$desc (ignoring errors)"
    "$@" 2>/dev/null
    log_ok "$desc"
}

# ========== НАЧАЛО СКРИПТА ==========

# Не включаем set -x, чтобы не дублировать структурированный лог
# set -x   # раскомментировать при отладке

SETUP_LOGFILE="/root/setup_log.txt"
: > "$SETUP_LOGFILE"
exec > >(tee -a "$SETUP_LOGFILE") 2>&1
log_info "Запуск zz1-final-offline-setup.sh"

# -----------------------------
#      ПЕРЕМЕННЫЕ СИСТЕМЫ
# -----------------------------

KERNEL_VERSION=$(cat /proc/version | awk '{print $3}')
log_ok "KERNEL_VERSION=$KERNEL_VERSION"

ARCH_VERSION=$(grep ARCH /etc/os-release | cut -d'"' -f2)
log_ok "ARCH_VERSION=$ARCH_VERSION"

NAME_VALUE=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
log_ok "NAME_VALUE=$NAME_VALUE"

case "$NAME_VALUE" in
    "OpenWrt")      ROUTER_NAME="oWRT" ;;
    "ImmortalWrt")  ROUTER_NAME="iWRT" ;;
    *)              ROUTER_NAME="WRT"  ;;
esac
log_ok "ROUTER_NAME=$ROUTER_NAME"

MY_ROUTER=$(ubus call system board | grep '"board_name"' | cut -d '"' -f 4 | cut -d ',' -f 2)
log_ok "MY_ROUTER=$MY_ROUTER"

MODEL_FULL=$(ubus call system board | grep '"model"' | cut -d '"' -f 4)
log_ok "MODEL_FULL=$MODEL_FULL"

ROUTER_MODEL=$(echo $MODEL_FULL | awk '{print $NF}')
ROUTER_MODEL_NAME=$(case "$ROUTER_MODEL" in
    "GL-MT2500")    echo "Brume2" ;;
    "R5S")          echo "R5S" ;;
    "R6S")          echo "R6S" ;;
    "GL-AXT1800")   echo "SLATEX" ;;
    "RB5009")       echo "RB5009" ;;
    *)              echo "$MY_ROUTER" ;;
esac)
log_ok "ROUTER_MODEL_NAME=$ROUTER_MODEL_NAME"

HOSTNAME_PATTERN="${ROUTER_MODEL_NAME}-${ROUTER_NAME}"
TAB_CHAR=$(printf '\t')
CURRENT_VARIANT=$(cat /etc/build_variant 2>/dev/null | head -n 1)
log_ok "Build Variant: ${CURRENT_VARIANT:-unknown}"

# --- БЛОК ЗАЩИТЫ ОТ ПОВТОРНОГО ЗАПУСКА ---
LOCK_FILE="/root/.setup_completed"
#if [ -f "$LOCK_FILE" ]; then
#if [ -f "$LOCK_FILE" ] && { [ "$CURRENT_VARIANT" = "clear" ] || [ "$CURRENT_VARIANT" = "crystal_clear" ]; }; then
#    echo "Скрипт уже был выполнен ранее."
#    exit 0
#fi
# --- БЛОК ЗАЩИТЫ ОТ ПОВТОРНОГО ЗАПУСКА ---

# ====================================================================
#      НАСТРОЙКИ
# ====================================================================

# Fullcone NAT
run_cmd "Удаление строки Fullcone NAT" sed -i "/option fullcone '1'/d" /etc/config/firewall

# Часовой пояс
run_cmd "Установка часового пояса" uci set system.@system[0].zonename='Europe/Moscow'
run_cmd "Сохранение system" uci commit system
date

# Пакетный менеджер
if command -v apk >/dev/null 2>&1; then
    log_info "Пакетный менеджер APK"
    if ! grep -qF "${ARCH_VERSION}" /etc/apk/arch; then
        echo "${ARCH_VERSION}" > /etc/apk/arch
        log_ok "Архитектура записана"
    else
        log_ok "Архитектура уже прописана"
    fi
    DISTFEEDS_FILE="/etc/apk/repositories.d/distfeeds.list"
    CUSTOMFEEDS_FILE="/etc/apk/repositories.d/customfeeds.list"
    for key in immortalwrt-snapshots.pem openwrt-snapshots.pem youtubeUnblock.pem public-key.pem; do
        [ -f "/etc/apk/keys/$key" ] || cp "/root/apps/$key" "/etc/apk/keys/" 2>/dev/null
    done
elif command -v opkg >/dev/null 2>&1; then
    log_info "Пакетный менеджер OPKG"
    DISTFEEDS_FILE="/etc/opkg/distfeeds.conf"
    CUSTOMFEEDS_FILE="/etc/opkg/customfeeds.conf"
else
    log_err "Пакетный менеджер не найден"
fi

if [ -f "$DISTFEEDS_FILE" ]; then
    cp "$DISTFEEDS_FILE" "${DISTFEEDS_FILE}.bak"
    FILTERED_CONTENT=$(grep -E "targets|packages/${ARCH_VERSION}/(base|luci|packages|routing|telephony|video)" "$DISTFEEDS_FILE")
    if [ -n "$FILTERED_CONTENT" ]; then
        echo "$FILTERED_CONTENT" > "$DISTFEEDS_FILE"
        log_ok "Репозитории очищены"
    else
        log_err "Фильтрация не дала результатов"
    fi

    if command -v apk >/dev/null 2>&1; then
        KERNEL_PKG=$(apk list -I kernel 2>/dev/null | head -n1 | awk '{print $1}')
        if [ -n "$KERNEL_PKG" ]; then
            K_VER_TEMP=${KERNEL_PKG#kernel-}
            K_VER_TEMP=${K_VER_TEMP%-r*}
            K_MODS_DIR=$(echo "$K_VER_TEMP" | sed 's/~/-1-/')
            BASE_REPO_URL=$(grep "/targets/.*/packages/packages.adb" "$DISTFEEDS_FILE" | head -n1)
            if [ -n "$BASE_REPO_URL" ]; then
                TARGET_BASE=$(echo "$BASE_REPO_URL" | sed 's|/packages/packages\.adb||')
                KMODS_URL="${TARGET_BASE}/kmods/${K_MODS_DIR}/packages.adb"
                if ! grep -q "$KMODS_URL" "$DISTFEEDS_FILE"; then
                    echo "$KMODS_URL" >> "$DISTFEEDS_FILE"
                    log_ok "Репозиторий kmods добавлен"
                fi
            fi
        fi
    fi
fi

# Создание customfeeds с проверкой
cat << 'EOF' > "$CUSTOMFEEDS_FILE"
# add your custom package feeds here
#
# http://www.example.com/path/to/files/packages.adb
EOF
_RC=$?; [ $_RC -eq 0 ] && log_ok "$CUSTOMFEEDS_FILE создан" || log_err "Ошибка создания $CUSTOMFEEDS_FILE (exit: $_RC)"

# Установка локальных пакетов
if [ -f /root/apps/sing-box.tar.gz ]; then
    run_cmd "Остановка sing-box" /etc/init.d/sing-box stop
    run_cmd "Распаковка sing-box" tar -xzf /root/apps/sing-box.tar.gz -C /tmp/
    rm /root/apps/sing-box.tar.gz
    run_cmd "Копирование sing-box" cp /tmp/sing-box /usr/bin/sing-box
    run_cmd "Права sing-box" chmod +x /usr/bin/sing-box
fi

if [ -f /root/apps/speedtest.tar.gz ]; then
    run_cmd "Распаковка speedtest" tar -xzf /root/apps/speedtest.tar.gz -C /tmp/
    rm /root/apps/speedtest.tar.gz
    run_cmd "Копирование speedtest" cp /tmp/speedtest /usr/bin/speedtest
    run_cmd "Права speedtest" chmod +x /usr/bin/speedtest
fi

# homeproxy
if [ -f "/etc/init.d/homeproxy" ]; then
    log_info "Настройка homeproxy"
    run_cmd "Отключение dns_hijacked" sed -i "s/const dns_hijacked = uci\.get('dhcp', '@dnsmasq\[0\]', 'dns_redirect') || '0'/const dns_hijacked = '1'/" /etc/homeproxy/scripts/firewall_post.ut
    run_cmd "Отключение homeproxy" /etc/init.d/homeproxy disable

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
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Скрипт-помощник homeproxy создан" || log_err "Ошибка создания $HELPER_SCRIPT_PATH (exit: $_RC)"
    chmod +x "$HELPER_SCRIPT_PATH"

    HOMEPROXY_INIT="/etc/init.d/homeproxy"
    HELPER_CALL="${TAB_CHAR}. ${HELPER_SCRIPT_PATH}"
    if [ -f "$HOMEPROXY_INIT" ] && ! grep -q "$HELPER_SCRIPT_PATH" "$HOMEPROXY_INIT"; then
        sed -i "/start_service() {/a \\$HELPER_CALL" "$HOMEPROXY_INIT"
        sed -i "/stop_service() {/a \\$HELPER_CALL" "$HOMEPROXY_INIT"
        log_ok "Init homeproxy пропатчен"
    fi

    . "$HELPER_SCRIPT_PATH"
    run_cmd "Включение homeproxy" /etc/init.d/homeproxy enable
    SB_version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP -m 1 'v?\K[\d.]+')
    log_ok "Версия sing-box: $SB_version"

    NFT_RULE_FILE="/etc/nftables.d/bypass_homeproxy_ips.nft"
    if [ ! -f "$NFT_RULE_FILE" ]; then
        cat > "$NFT_RULE_FILE" << EOF
chain bypass_homeproxy_mark {
	type filter hook prerouting priority mangle - 1; policy accept;
	ip daddr @bypass_ips meta mark set 0x00000064 counter
}
EOF
        _RC=$?; [ $_RC -eq 0 ] && log_ok "Файл bypass_homeproxy_ips.nft создан" || log_err "Ошибка создания $NFT_RULE_FILE (exit: $_RC)"
    fi
fi

# Passwall
if [ ! -f "$LOCK_FILE" ] && [ "$CURRENT_VARIANT" = "passwall" ] && [ -f "/etc/init.d/passwall2" ]; then
    log_info "Настройка Passwall2"
    run_cmd "Остановка passwall2" /etc/init.d/passwall2 stop
    run_cmd "Отключение passwall2" /etc/init.d/passwall2 disable

    uci -q batch <<-EOF
        set passwall2.@global[0].dns_redirect='0'
        set passwall2.@global[0].dns_shunt='closed'
        set passwall2.@global[0].remote_dns='127.0.0.1:53'
        set passwall2.@global[0].china_dns='127.0.0.1:53'
        set passwall2.@global[0].adblock='0'
        set passwall2.@global[0].enabled='1'
        commit passwall2
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Конфигурация passwall2 обновлена" || log_err "Ошибка uci batch passwall2 (exit: $_RC)"

    run_cmd "Включение passwall2" /etc/init.d/passwall2 enable
fi

# IPSet для youtubeUnblock
FIREWALL_CONFIG_CHANGED=0
for ipset_name in dpi_ips bypass_ips; do
    if ! uci show firewall | grep -q "\.name='$ipset_name'"; then
        handle=$(uci add firewall ipset)
        uci set firewall."$handle".name="$ipset_name"
        uci set firewall."$handle".match="dest_net"
        uci set firewall."$handle".family="ipv4"
        FIREWALL_CONFIG_CHANGED=1
    fi
done
[ "$FIREWALL_CONFIG_CHANGED" = 1 ] && uci commit firewall && log_ok "Firewall сохранён"

run_cmd "Правка ruleset.uc" sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' /usr/share/firewall4/templates/ruleset.uc

if [ -x "/usr/bin/youtubeUnblock" ]; then
    run_cmd "Остановка youtubeUnblock" /etc/init.d/youtubeUnblock stop
    run_cmd "Отключение youtubeUnblock" /etc/init.d/youtubeUnblock disable
    cat << "EOF" > /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
#!/usr/sbin/nft -f
# This file will be applied automatically for nftables <table> <chain> position <number> <condition> <action>

# Drop (reject) UDP to dest port 443 to DPI IPs
add rule inet fw4 prerouting ip daddr @dpi_ips udp dport 443 reject with icmp port-unreachable

# DPI through youtubeUnblock
add chain inet fw4 youtubeUnblock { type filter hook postrouting priority mangle - 1; policy accept; }

# Exclusion of the guest network by tag (traffic will bypass the queue)
add rule inet fw4 youtubeUnblock meta mark 0x00000042 counter return

# If the destination IP is in the bypass_ips list, we exit the chain.
add rule inet fw4 youtubeUnblock ip daddr @bypass_ips counter return

# DPI through youtubeUnblock
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips tcp dport 443 ct original packets < 20 counter queue num 537 bypass
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips meta l4proto udp ct original packets < 9 counter queue num 537 bypass

# Skipping traffic with the label 0x8000
insert rule inet fw4 output mark and 0x8000 == 0x8000 counter accept
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Файл youtubeUnblock.nft записан" || log_err "Ошибка записи правил (exit: $_RC)"
    chmod 0644 /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
    run_cmd "Включение youtubeUnblock" /etc/init.d/youtubeUnblock enable
else
    log_info "youtubeUnblock не установлен"
fi

# internet-detector
[ -f "/etc/init.d/internet-detector" ] && {
    run_cmd "Отключение internet-detector" /etc/init.d/internet-detector disable
    run_cmd "Смена START на 99" sed -i 's/START=[0-9][0-9]/START=99/' /etc/init.d/internet-detector
}

# attendedsysupgrade
if [ "$NAME_VALUE" = "OpenWrt" ]; then
    run_cmd "Настройка owut (OpenWrt)" sed -i "s|option url 'https://asu-2.kyarucloud.moe'|option url 'https://sysupgrade.openwrt.org'|" /etc/config/attendedsysupgrade
else
    run_cmd "Настройка owut (ImmortalWrt)" sed -i "s|option url 'https://sysupgrade.openwrt.org'|option url 'https://asu-2.kyarucloud.moe'|" /etc/config/attendedsysupgrade
fi

# AdGuardHome
if [ -x "/usr/bin/AdGuardHome" ] && [ -f "/etc/config/adguardhome" ]; then
    log_info "Настройка AdGuardHome"
    run_cmd "Остановка adguardhome" /etc/init.d/adguardhome stop
    run_cmd "Отключение adguardhome" /etc/init.d/adguardhome disable
    mkdir -p /opt/AdGuardHome
    run_cmd "chown /opt/AdGuardHome" chown -R root:root /opt/AdGuardHome
    run_cmd "chmod /opt/AdGuardHome" chmod 755 /opt/AdGuardHome

    grep -q '^adguardhome:' /etc/group || echo "adguardhome:x:853:" >> /etc/group
    grep -q '^adguardhome:' /etc/passwd || echo "adguardhome:x:853:853:AdGuard Home:/var/lib/adguardhome:/bin/false" >> /etc/passwd

    uci -q batch <<EOF
        set adguardhome.config.work_dir='/opt/AdGuardHome'
        set adguardhome.config.user='root'
        set adguardhome.config.group='root'
        commit adguardhome
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "UCI adguardhome применён" || log_err "Ошибка uci batch AdGuardHome (exit: $_RC)"

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
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Контроллер LuCI создан" || log_err "Ошибка создания контроллера (exit: $_RC)"

    run_cmd "Смена порта dnsmasq" uci set dhcp.@dnsmasq[0].port="54"
    run_cmd_ign "Удаление серверов dnsmasq" uci delete dhcp.@dnsmasq[0].server
    run_cmd "Сохранение dhcp" uci commit dhcp

    run_cmd "Настройка лога adguardhome" sed -i 's|--logfile syslog|--logfile /var/AdGuardHome.log|' /etc/init.d/adguardhome
    run_cmd "Включение adguardhome" /etc/init.d/adguardhome enable
    run_cmd "Запуск adguardhome" /etc/init.d/adguardhome start
else
    log_info "AdGuardHome не найден"
fi

# SQM (исправленный патч)
if [ -f "/usr/lib/sqm/run.sh" ]; then
    log_info "Настройка SQM"
    mkdir -p /opt
    CUSTOM_CONF="/opt/sqm_custom.conf"
    cat > "$CUSTOM_CONF" <<EOF
option iqdisc_opts 'nat dual-dsthost diffserv4 nowash'
option eqdisc_opts 'nat dual-srchost diffserv4 nowash'
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Конфиг SQM создан" || log_err "Ошибка создания $CUSTOM_CONF (exit: $_RC)"

    if ! grep -q "sqm_custom.conf" /usr/lib/sqm/run.sh; then
        cat <<'EOF' > /tmp/sqm_loader.txt

    # --- Load Custom Config (/opt/sqm_custom.conf) ---
    if [ -f "/opt/sqm_custom.conf" ]; then
        cust_i=$(grep "^option iqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        cust_e=$(grep "^option eqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        [ -n "$cust_i" ] && export IQDISC_OPTS="$cust_i"
        [ -n "$cust_e" ] && export EQDISC_OPTS="$cust_e"
    fi
EOF
        sed -i '/export EQDISC_OPTS/r /tmp/sqm_loader.txt' /usr/lib/sqm/run.sh
        _RC=$?; rm /tmp/sqm_loader.txt
        [ $_RC -eq 0 ] && log_ok "run.sh пропатчен" || log_err "Ошибка патча run.sh (exit: $_RC)"
    else
        log_ok "run.sh уже пропатчен"
    fi

    SQM_ENABLED=$(uci -q get sqm.@queue[0].enabled)
    if [ "$SQM_ENABLED" = "1" ]; then
        run_cmd "Перезапуск SQM" /etc/init.d/sqm restart
    else
        /etc/init.d/sqm disable 2>/dev/null
    fi
else
    log_info "SQM не установлен"
fi

# Очистка временных файлов конфигурации
find /etc/config/ -type f \( -name '*-opkg' -o -name '*apk-new' \) -delete 2>/dev/null
log_info "Временные файлы удалены"

# Широкий CSS
if ! grep -q "LuCI Bootstrap: Custom Fullwidth CSS" /www/luci-static/bootstrap/cascade.css; then
    cat << 'EOF' >> /www/luci-static/bootstrap/cascade.css

/* LuCI Bootstrap: Custom Fullwidth CSS */
@media only screen and (max-width: 1199px), (hover: none) and (pointer: coarse) {
	#maincontent, .container, .main-content, .wrapper {
		width: 100% !important; max-width: 100% !important; margin: 0 !important; padding: 0 !important;
	}
}
@media only screen and (min-width: 1200px) and (hover: hover) {
	#maincontent, .container, .main-content, .wrapper {
		width: 50% !important; max-width: 50% !important; margin: 0 auto !important; padding: 0 !important;
	}
}
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "CSS обновлён" || log_err "Ошибка добавления CSS (exit: $_RC)"
fi

# FullCone NAT
if [ -f "/lib/modules/$(uname -r)/nft_fullcone.ko" ] || lsmod | grep -q nft_fullcone; then
    run_cmd "Включение FullCone NAT" uci set firewall.@defaults[0].fullcone='1'
    uci commit firewall
fi

# TCP BBR
if [ -f "/lib/modules/$(uname -r)/tcp_bbr.ko" ] || grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    sed -i '/# TCP BBR/d; /net\.core\.default_qdisc.*fq/d; /net\.ipv4\.tcp_congestion_control.*bbr/d' /etc/sysctl.conf
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/sysctl.conf
	echo -e "\n# TCP BBR\nnet.core.default_qdisc = fq_codel\nnet.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    log_ok "TCP BBR включён"
fi

[ -x "/etc/init.d/phy-leds" ] && run_cmd "Отключение phy-leds" /etc/init.d/phy-leds disable

# =========================================================
# SWITCH MODE
# =========================================================
if [ ! -f "$LOCK_FILE" ] && [ "$CURRENT_VARIANT" = "switch" ]; then
    log_info "Активация режима коммутатора"
    run_cmd_ign "Удаление lan"   uci delete network.lan
    run_cmd_ign "Удаление wan"   uci delete network.wan
    run_cmd_ign "Удаление wan6"  uci delete network.wan6

    RAW_PORTS=$(ls /sys/class/net/)
    EXCLUDE_PATTERN="^lo$|^sit|^tun|^br-|^wlan|^phy|^mon|^bond|^veth|^docker"
    if echo "$RAW_PORTS" | grep -qE "^p[0-9]+"; then
        FILTERED_PORTS=$(echo "$RAW_PORTS" | grep -vE "$EXCLUDE_PATTERN|^eth0$" | tr '\n' ' ')
    else
        FILTERED_PORTS=$(echo "$RAW_PORTS" | grep -vE "$EXCLUDE_PATTERN" | tr '\n' ' ')
    fi
    FILTERED_PORTS=$(echo $FILTERED_PORTS)

    uci set network.@device[0].name='br-lan'
    uci set network.@device[0].type='bridge'
    uci set network.@device[0].ports="$FILTERED_PORTS"
    uci set network.@device[0].stp='1'
    uci set network.@device[0].igmp_snooping='1'
    uci set network.@device[0].multicast_querier='1'
    uci set network.@device[0].ipv6='0'
    uci set network.lan=interface
    uci set network.lan.device='br-lan'
    uci set network.lan.proto='dhcp'
    uci set network.lan.ip6assign='0'
    uci set network.globals.packet_steering='2'
    run_cmd_ign "Удаление ULA" uci delete network.globals.ula_prefix

    uci set dhcp.lan.ignore='1'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ra='disabled'
    uci -q delete dhcp.odhcpd
    uci set dhcp.odhcpd=odhcpd
    uci set dhcp.odhcpd.disabled='1'
    run_cmd "Отключение odhcpd" /etc/init.d/odhcpd disable

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
    run_cmd_ign "Удаление dhcp.wan" uci delete dhcp.wan
    run_cmd "Сохранение switch" uci commit
fi

[ "$CURRENT_VARIANT" = "switch" ] && HOSTNAME_PATTERN="${ROUTER_MODEL_NAME}-${CURRENT_VARIANT}"

# =========================================================
# СИНХРОНИЗАЦИЯ ВРЕМЕНИ И БАННЕР
# =========================================================
if command -v hwclock >/dev/null 2>&1; then
    run_cmd "Синхронизация RTC" hwclock -s -u
fi

if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    log_info "Интернет есть, принудительная NTP синхронизация"
    /etc/init.d/sysntpd stop 2>/dev/null
    ntpd -q -n -p ru.pool.ntp.org 2>/dev/null && log_ok "NTP синхронизировано" || log_err "Ошибка ntpd"
    /etc/init.d/sysntpd start 2>/dev/null
    hwclock -w -u 2>/dev/null && log_ok "RTC обновлён"
else
    /etc/init.d/sysntpd restart 2>/dev/null
fi
sleep 2

cp /etc/banner /etc/banner.bak
sed -i 's/W I R E L E S S/N E T W O R K/g' /etc/banner
sed -i "/Build Variant:/d; /Kernel Version:/d" /etc/banner

if [ -f "/etc/build_date" ]; then
    DATE_STR=$(cat /etc/build_date)
else
    CURRENT_YEAR=$(date +%Y)
    if [ "$CURRENT_YEAR" -ge 2025 ] && [ "$CURRENT_YEAR" -le 2050 ]; then
        DATE_STR=$(date +'%Y-%m-%d')
    else
        DATE_STR="***"
    fi
fi
echo " Kernel Version: $KERNEL_VERSION" >> /etc/banner
echo " Build Variant: $CURRENT_VARIANT ($DATE_STR)" >> /etc/banner
log_ok "Баннер обновлён"

# Имя хоста
run_cmd "Установка hostname" uci set system.@system[0].hostname="$HOSTNAME_PATTERN"
run_cmd "Сохранение system" uci commit system
run_cmd "Установка commonname" uci set uhttpd.defaults.commonname="$HOSTNAME_PATTERN"
uci commit uhttpd

sed -i "s/File Manager/Файловый менеджер/" /usr/share/luci/menu.d/luci-app-filemanager.json

touch "$LOCK_FILE"

# Гарантированная запись лога перед уходом в фон
sync
log_info "Отложенная перезагрузка через 120 секунд (процесс в фоне)"
(sleep 120; sync; reboot) &

ERROR_COUNT=$(grep -c '\[ERR\]' "$SETUP_LOGFILE")
log_info "Настройка завершена. Количество ошибок в логе: $ERROR_COUNT"
exit 0
