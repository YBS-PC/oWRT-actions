#!/bin/sh

# ===============================================
#      UCI-DEFAULTS ОФЛАЙН-СКРИПТ НАСТРОЙКИ
# ===============================================
# Имя файла: /etc/uci-defaults/zz1-final-offline-setup.sh
# ===============================================

# Функции логирования (без local для POSIX-совместимости)
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"; }
log_ok()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]   $*"; }
ERROR_COUNT=0
log_err()   { ERROR_COUNT=$((ERROR_COUNT+1)); echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERR]  $*"; }

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

# Проверка, что sed-патч по чужому (пакетному) файлу реально лёг.
# sed возвращает 0 даже когда ничего не совпало, поэтому run_cmd тут слеп.
patch_check() {   # <файл> <строка-после-правки> <описание>
    if grep -qF -- "$2" "$1" 2>/dev/null; then
        log_ok "$3: патч на месте"
    else
        log_err "$3: ПАТЧ НЕ ПРИМЕНЁН — якорь изменился в $1"
    fi
}

hp_insert() {   # <файл> <якорь-подстрока> <before|after> <файл-вставки>
    # Вставляет файл-вставку перед/после первой строки с якорем. Права и
    # владельца файла сохраняет (пишет поверх через cat, а не mv).
    grep -qF -- "$2" "$1" 2>/dev/null || return 1
    awk -v a="$2" -v w="$3" -v s="$4" '
        !done && index($0, a) {
            if (w == "after") print
            while ((getline l < s) > 0) print l
            close(s); done = 1
            if (w == "after") next
        }
        { print }' "$1" > "$1.zz1" && cat "$1.zz1" > "$1"
    _rc=$?; rm -f "$1.zz1"; return $_rc
}

# ========== НАЧАЛО СКРИПТА ==========

# Не включаем set -x, чтобы не дублировать структурированный лог
# set -x   # раскомментировать при отладке

# --- РЕЖИМ РАБОТЫ ---------------------------------------------------------
# firstboot   — запуск из /etc/uci-defaults на первой загрузке после прошивки
# maintenance — ручной запуск сохранённой копии после apk upgrade
# Признак — lock-файл; на первой загрузке после прошивки его нет.
# Лежит в /etc, а не в /root: /root часто целиком вписан в
# /etc/sysupgrade.conf, и тогда lock переживал бы прошивку с сохранением
# настроек — zz1 на новой прошивке шёл бы как maintenance. Синтаксиса
# исключений в sysupgrade.conf нет, а /etc целиком в бэкап не попадает
# (только конфиги пакетов и пути из sysupgrade.conf), поэтому lock здесь
# сбрасывается любой прошивкой и сохраняется при ручных запусках.
LOCK_FILE="/etc/zz1_setup_completed"
# Старое место lock-файла: он больше ни на что не влияет, убираем.
rm -f /root/.setup_completed
if [ -f "$LOCK_FILE" ]; then
    MODE="maintenance"
    SETUP_LOGFILE="/root/setup_log_maintenance.txt"
else
    MODE="firstboot"
    SETUP_LOGFILE="/root/setup_log.txt"
fi
: > "$SETUP_LOGFILE"
exec > >(tee -a "$SETUP_LOGFILE") 2>&1
log_info "Запуск zz1-final-offline-setup.sh (режим: $MODE)"

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
CURRENT_VARIANT=$(cat /etc/build_variant 2>/dev/null | head -n 1)
log_ok "Build Variant: ${CURRENT_VARIANT:-unknown}"

# forkop 2.x (ushan0v/forkop 2.0+, ядро sing-box-forkop) или ветка 1.x
# (forkop-mod; внутри сборки оба — вариант forkop). У 2.x другие настройки:
# dont_touch_dhcp, exclude_ntp и intercept_device_dns убраны, DNS вне секций —
# unmatched_dns_mode. Признак — эта опция в конфиге по умолчанию из пакета.
forkop_v2() {
    grep -qs "option unmatched_dns_mode" /usr/share/forkop/default-config
}

# --- БЛОК ЗАЩИТЫ ОТ ПОВТОРНОГО ЗАПУСКА ---
# LOCK_FILE определён выше, вместе с MODE
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
    # Ключи подписи сторонних репозиториев: всё, что положено в
    # files/root/apps/*.pem, ставится в /etc/apk/keys/. Нет файлов — нет шага.
    for key in /root/apps/*.pem; do
        [ -f "$key" ] || continue
        key_name=$(basename "$key")
        if [ -f "/etc/apk/keys/$key_name" ]; then
            log_ok "Ключ $key_name уже установлен"
        else
            run_cmd "Установка ключа $key_name" cp "$key" /etc/apk/keys/
        fi
    done
elif command -v opkg >/dev/null 2>&1; then
    log_info "Пакетный менеджер OPKG"
    DISTFEEDS_FILE="/etc/opkg/distfeeds.conf"
    CUSTOMFEEDS_FILE="/etc/opkg/customfeeds.conf"
else
    log_err "Пакетный менеджер не найден"
fi

if [ -f "$DISTFEEDS_FILE" ]; then
    # Бэкап делаем один раз: на повторном прогоне в .bak лёг бы уже
    # отфильтрованный файл и оригинал был бы потерян навсегда.
    [ -f "${DISTFEEDS_FILE}.bak" ] || cp "$DISTFEEDS_FILE" "${DISTFEEDS_FILE}.bak"
    # Имя фида должно кончаться «/» (apk: …/luci/packages.adb) или концом
    # строки (opkg: …/luci). Без этого «luci» ловил и luciappbandix,
    # luciappbandixplus — фиды из feeds.conf сборки, которых на сервере нет.
    FILTERED_CONTENT=$(grep -E "targets|packages/${ARCH_VERSION}/(base|luci|packages|routing|telephony|video)(/|\$)" "$DISTFEEDS_FILE")
    if [ -n "$FILTERED_CONTENT" ]; then
        echo "$FILTERED_CONTENT" > "$DISTFEEDS_FILE"
        log_ok "Репозитории очищены"
    else
        log_err "Фильтрация не дала результатов"
    fi

    if command -v apk >/dev/null 2>&1; then
        KERNEL_PKG=$(apk list -I kernel 2>/dev/null | head -n1 | awk '{print $1}')
        # Откуда при сборке взят хеш ядра (шаг Kernel Hash): server, cache,
        # snapshot или local. С локальным хешем официальной папки kmods нет —
        # строку не добавляем, иначе apk update падал бы на ней.
        KHASH_SRC=$(awk 'NR == 1 {print $1}' /etc/build_kernel_hash 2>/dev/null)
        if [ "$KHASH_SRC" = local ]; then
            sed -i '\|/kmods/|d' "$DISTFEEDS_FILE"
            log_info "Прошивка собрана с локальным хешем ядра: репозиторий kmods не добавлен (официальные kmod-пакеты на неё не встанут)"
            KERNEL_PKG=""
        fi
        if [ -n "$KERNEL_PKG" ]; then
            # kernel-<версия>~<хеш>-r<release> -> <версия>-<release>-<хеш>
            # (имя папки kmods, как в include/feeds.mk OpenWrt)
            K_REL=${KERNEL_PKG##*-r}
            K_VER_TEMP=${KERNEL_PKG#kernel-}
            K_VER_TEMP=${K_VER_TEMP%-r*}
            K_MODS_DIR="${K_VER_TEMP%%~*}-${K_REL}-${K_VER_TEMP#*~}"
            BASE_REPO_URL=$(grep "/targets/.*/packages/packages.adb" "$DISTFEEDS_FILE" | head -n1)
            if [ -n "$BASE_REPO_URL" ]; then
                TARGET_BASE=$(echo "$BASE_REPO_URL" | sed 's|/packages/packages\.adb||')
                KMODS_URL="${TARGET_BASE}/kmods/${K_MODS_DIR}/packages.adb"
                # Строки kmods содержат /targets/ и переживают фильтр выше,
                # поэтому после смены ядра старые хеши копятся. Сносим их.
                sed -i '\|/kmods/|d' "$DISTFEEDS_FILE"
                if ! grep -q "$KMODS_URL" "$DISTFEEDS_FILE"; then
                    echo "$KMODS_URL" >> "$DISTFEEDS_FILE"
                    log_ok "Репозиторий kmods добавлен"
                fi
            fi
        fi
    fi
fi

# Создание customfeeds с проверкой (только firstboot — иначе затрёт добавленные фиды)
if [ "$MODE" = "firstboot" ]; then
cat << 'EOF' > "$CUSTOMFEEDS_FILE"
# add your custom package feeds here
#
# http://www.example.com/path/to/files/packages.adb
EOF
_RC=$?; [ $_RC -eq 0 ] && log_ok "$CUSTOMFEEDS_FILE создан" || log_err "Ошибка создания $CUSTOMFEEDS_FILE (exit: $_RC)"
else
    log_info "$CUSTOMFEEDS_FILE не трогаем (maintenance)"
fi

# Установка локальных пакетов
# Архив удаляем только после успешной установки: иначе падение tar
# оставило бы и без бинарника, и без исходного архива.
# Ядро forkop 2.x (пакет sing-box-forkop) не подменяем: forkop не запускается
# на другом sing-box. Файлы в /root/apps тогда остаются как есть.
if [ -f /usr/share/sing-box-forkop/version ] && { [ -f /root/apps/sing-box.tar.gz ] || [ -f /root/apps/sing-box ]; }; then
    log_info "sing-box из /root/apps не ставим: установлен sing-box-forkop $(cat /usr/share/sing-box-forkop/version), ядро forkop 2.x"
elif [ -f /root/apps/sing-box.tar.gz ]; then
    [ -x /etc/init.d/sing-box ] && run_cmd "Остановка sing-box" /etc/init.d/sing-box stop
    if run_cmd "Распаковка sing-box" tar -xzf /root/apps/sing-box.tar.gz -C /tmp/ \
       && run_cmd "Копирование sing-box" cp /tmp/sing-box /usr/bin/sing-box; then
        run_cmd "Права sing-box" chmod +x /usr/bin/sing-box
        rm -f /root/apps/sing-box.tar.gz /tmp/sing-box
    else
        log_err "sing-box не установлен, архив сохранён"
    fi
fi

if [ -f /root/apps/speedtest.tar.gz ]; then
    if run_cmd "Распаковка speedtest" tar -xzf /root/apps/speedtest.tar.gz -C /tmp/ \
       && run_cmd "Копирование speedtest" cp /tmp/speedtest /usr/bin/speedtest; then
        run_cmd "Права speedtest" chmod +x /usr/bin/speedtest
        rm -f /root/apps/speedtest.tar.gz /tmp/speedtest
    else
        log_err "speedtest не установлен, архив сохранён"
    fi
fi

# Установка неархивированных локальных пакетов
if [ -f /root/apps/sing-box ] && [ ! -f /usr/share/sing-box-forkop/version ]; then
    [ -x /etc/init.d/sing-box ] && run_cmd "Остановка sing-box" /etc/init.d/sing-box stop
    run_cmd "Копирование sing-box" cp /root/apps/sing-box /usr/bin/sing-box
    run_cmd "Права sing-box" chmod +x /usr/bin/sing-box
    rm /root/apps/sing-box
fi

if [ -f /root/apps/AdGuardHome ]; then
    [ -x /etc/init.d/adguardhome ] && run_cmd "Остановка AdGuardHome" /etc/init.d/adguardhome stop
    run_cmd "Копирование AdGuardHome" cp /root/apps/AdGuardHome /usr/bin/AdGuardHome
    run_cmd "Права AdGuardHome" chmod +x /usr/bin/AdGuardHome
    rm /root/apps/AdGuardHome
fi

if [ -f /root/apps/speedtest ]; then
    run_cmd "Копирование speedtest" cp /root/apps/speedtest /usr/bin/speedtest
    run_cmd "Права speedtest" chmod +x /usr/bin/speedtest
    rm /root/apps/speedtest
fi

# Закрепление пакетов с подменённым бинарником
# Скачанный при сборке sing-box (sb=версия, extended, podkop-engine) и
# AdGuard Home (agh=latest) лежат поверх пакета из фида: пакет в базе своей
# версии, а /usr/bin — другой. apk upgrade (opkg upgrade) поставил бы новый
# пакет из репозитория и вернул бинарник фида: пропали бы extended и патчи
# podkop-engine (вместе с его init-скриптом), AGH откатился бы. Поэтому пакет,
# у которого версия бинарника не совпадает с версией пакета, закрепляется на
# установленной: apk — строкой «имя=версия» в /etc/apk/world (так же OpenWrt
# закрепляет в образе kernel, libc и base-files), opkg — флагом hold.
# Остальные пакеты обновляются как обычно. Снять закрепление:
#   apk add sing-box          (строка в world снова без версии)
#   opkg flag user sing-box
pin_replaced() {   # <пакет> <версия бинарника>
    if command -v apk >/dev/null 2>&1; then
        _ver=$(apk list --manifest "$1" 2>/dev/null | awk -v n="$1" '$1 == n {print $2; exit}')
    else
        _ver=$(opkg status "$1" 2>/dev/null | sed -n 's/^Version: //p')
    fi
    if [ -z "$_ver" ]; then
        log_info "$1: пакет не установлен — закреплять нечего"
        return 0
    fi
    if [ -z "$2" ]; then
        log_err "$1: версию бинарника получить не удалось — пакет не закреплён"
        return 1
    fi
    # 1.13.21-r1 -> 1.13.21 (opkg до 24.10: 1.13.21-1)
    if [ "$2" = "$(echo "$_ver" | sed -E 's/-r?[0-9]+$//')" ]; then
        log_ok "$1 $_ver: бинарник из пакета, закреплять не нужно"
        return 0
    fi
    if ! command -v apk >/dev/null 2>&1; then
        run_cmd "Закрепление $1 $_ver (бинарник $2)" opkg flag hold "$1"
        return
    fi
    _world=/etc/apk/world
    if grep -qxF "$1=$_ver" "$_world" 2>/dev/null; then
        log_ok "$1 уже закреплён на $_ver (бинарник $2)"
        return 0
    fi
    # Прежняя строка пакета (без версии, с другой версией или тегом) уходит
    awk -v n="$1" '{ d = $0; sub(/[<>=~@].*/, "", d); if (d != n) print }' "$_world" > "$_world.zz1" \
        && echo "$1=$_ver" >> "$_world.zz1" && cat "$_world.zz1" > "$_world"
    _rc=$?; rm -f "$_world.zz1"
    if [ $_rc -eq 0 ]; then
        log_ok "$1 закреплён на $_ver в $_world (бинарник $2)"
    else
        log_err "$1: не удалось закрепить в $_world (exit: $_rc)"
    fi
}

[ -x /usr/bin/sing-box ] && pin_replaced sing-box \
    "$(/usr/bin/sing-box version 2>/dev/null | awk 'NR == 1 {print $3}')"
# Сборка из фида: «AdGuard Home, version 0.107.79», релиз — «… v0.107.79»
[ -x /usr/bin/AdGuardHome ] && pin_replaced adguardhome \
    "$(/usr/bin/AdGuardHome --version 2>/dev/null | awk 'NR == 1 {sub(/^v/, "", $NF); print $NF}')"

# homeproxy
if [ -f "/etc/init.d/homeproxy" ]; then
    log_info "Настройка homeproxy"
    # dns_hijacked='1' — только в связке с AdGuard Home: DNS клиентов принимает
    # AGH и сам шлёт его в sing-box (127.0.0.1:5333). Без AGH (поле формы
    # agh=no) оставляем штатную схему homeproxy: иначе DNS шёл бы мимо sing-box.
    if [ -x /usr/bin/AdGuardHome ]; then
        run_cmd "Отключение dns_hijacked" sed -i "s/const dns_hijacked = uci\.get('dhcp', '@dnsmasq\[0\]', 'dns_redirect') || '0'/const dns_hijacked = '1'/" /etc/homeproxy/scripts/firewall_post.ut
        patch_check /etc/homeproxy/scripts/firewall_post.ut "const dns_hijacked = '1'" "firewall_post.ut"
    else
        log_info "AdGuard Home нет — dns_hijacked homeproxy не трогаем"
    fi

    # --- Clash API + панель YACD -----------------------------------------
    # Clash API включается опциями UCI (патч 010, без него zz1 вписывает
    # тот же код в генератор сам — см. ниже).
    # Каталог /opt/yacd НИКОГДА не должен быть пустым: при пустом каталоге
    # sing-box на каждом старте лезет качать панель с GitHub через дефолтный
    # outbound. Поэтому кладём заглушку сразу, а настоящую панель догружает
    # cron, когда появится интернет. Первая загрузка не тормозит.
    if [ ! -f /opt/yacd/index.html ]; then
        mkdir -p /opt/yacd
        cat << 'Y_STUB_EOF' > /opt/yacd/index.html
<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">
<title>YACD</title><meta http-equiv="refresh" content="60"></head>
<body style="font-family:sans-serif;padding:2em">
<h2>YACD ещё не установлена</h2>
<p>Панель догружается автоматически, как только появится интернет.
Проверка раз в 10 минут, страница обновится сама.</p>
</body></html>
Y_STUB_EOF
        touch /opt/yacd/.stub
        log_ok "Заглушка /opt/yacd создана"
    fi

    if [ -f /opt/yacd/.stub ]; then
    cat << 'Y_INST_EOF' > /usr/bin/yacd-install.sh
#!/bin/sh
# Догружает YACD в /opt/yacd, когда появится интернет.
# Снимает себя из cron после успеха. Вызывается из /etc/crontabs/root.
CRON_FILE="/etc/crontabs/root"
URL="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"
TMP_ZIP="/tmp/yacd.zip"
TMP_DIR="/tmp/yacd-unpack"

unhook() {
    sed -i '/yacd-install/d' "$CRON_FILE" 2>/dev/null
    /etc/init.d/cron reload 2>/dev/null
    rm -f /usr/bin/yacd-install.sh
}
cleanup() { rm -rf "$TMP_ZIP" "$TMP_DIR" /opt/yacd.new /opt/yacd.old; }
trap cleanup EXIT

# Настоящая панель уже стоит (метки заглушки нет) - больше делать нечего
if [ -f /opt/yacd/index.html ] && [ ! -f /opt/yacd/.stub ]; then
    unhook
    exit 0
fi

curl -fsSL --max-time 120 -o "$TMP_ZIP" "$URL" || exit 1
mkdir -p "$TMP_DIR"
unzip -qo "$TMP_ZIP" -d "$TMP_DIR" || exit 1

SRC_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
[ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/index.html" ] || exit 1

rm -rf /opt/yacd.new
mkdir -p /opt/yacd.new
cp -r "$SRC_DIR"/. /opt/yacd.new/
[ -f /opt/yacd.new/index.html ] || exit 1

mv /opt/yacd /opt/yacd.old 2>/dev/null
mv /opt/yacd.new /opt/yacd
rm -rf /opt/yacd.old
logger -t yacd-install "YACD установлена в /opt/yacd"
unhook
exit 0
Y_INST_EOF
    chmod +x /usr/bin/yacd-install.sh
    log_ok "Установщик YACD создан"

    CRON_FILE="/etc/crontabs/root"
    mkdir -p /etc/crontabs && touch "$CRON_FILE"
    if ! grep -q 'yacd-install' "$CRON_FILE"; then
        echo '*/10 * * * * /usr/bin/yacd-install.sh >/dev/null 2>&1' >> "$CRON_FILE"
        log_ok "Задание cron для догрузки YACD добавлено"
    fi
    run_cmd_ign "Включение cron" /etc/init.d/cron enable
    fi

    grep -q '^/opt/yacd$' /etc/sysupgrade.conf 2>/dev/null || echo '/opt/yacd' >> /etc/sysupgrade.conf

    GEN_UC="/etc/homeproxy/scripts/generate_client.uc"
    HOMEPROXY_INIT="/etc/init.d/homeproxy"
    if [ -f "$GEN_UC" ] && grep -q 'hiddify' "$GEN_UC"; then
        # Re:HomeProxy (вариант rehomeproxy, генератор знает hiddify-core):
        # у него свой многострочный блок clash_api с 127.0.0.1:9090, им
        # пользуются его страницы LuCI. Строки clash_api не удаляем (это
        # сломало бы синтаксис файла), а открываем тот же контроллер в LAN и
        # подключаем панель YACD. При повторном запуске адрес уже заменён.
        if grep -q "external_controller: '127.0.0.1:9090'" "$GEN_UC"; then
            run_cmd "Clash API в generate_client.uc (Re:HomeProxy)" \
                sed -i "s|external_controller: '127.0.0.1:9090'|external_controller: '0.0.0.0:9090', external_ui: '/opt/yacd'|" "$GEN_UC"
        fi
        patch_check "$GEN_UC" "external_ui: '/opt/yacd'" "generate_client.uc (Clash API)"
    elif [ -f "$GEN_UC" ]; then
        # luci-app-homeproxy: Clash API включается опциями UCI (патч 010).
        # zz1 запускают и после обновления пакетов: если пакет собран без
        # патчей или обновлён из фида, вписываем тот же код, что и патч 010;
        # если доработка уже есть, файлы не трогаем.
        if grep -q 'clash_api_controller' "$GEN_UC"; then
            log_info "generate_client.uc: опция Clash API уже есть"
        else
            # Строка clash_api, которую вписывали прежние версии zz1
            sed -i "/clash_api: { external_controller: '0.0.0.0:9090', external_ui: '\/opt\/yacd' },/d" "$GEN_UC"
            if grep -qF '/* UCI config end */' "$GEN_UC" && grep -qF '/* Experimental end */' "$GEN_UC"; then
                cat << 'HP_EOF' > /tmp/zz1-hp.snip

/* Clash API, off unless a controller address is set */
const clash_api_controller = uci.get(uciconfig, uciinfra, 'clash_api_controller'),
      clash_api_ui = uci.get(uciconfig, uciinfra, 'clash_api_ui'),
      clash_api_secret = uci.get(uciconfig, uciinfra, 'clash_api_secret');
HP_EOF
                hp_insert "$GEN_UC" '/* UCI config end */' before /tmp/zz1-hp.snip
                cat << 'HP_EOF' > /tmp/zz1-hp.snip

/* The Clash API serves YACD-like panels and the connection list; it does
 * not depend on the routing mode. */
if (clash_api_controller) {
	config.experimental ||= {};
	config.experimental.clash_api = {
		external_controller: clash_api_controller,
		external_ui: clash_api_ui,
		secret: clash_api_secret
	};
}
HP_EOF
                hp_insert "$GEN_UC" '/* Experimental end */' before /tmp/zz1-hp.snip &&
                    log_ok "Опция Clash API добавлена в generate_client.uc (как патч 010)"
                rm -f /tmp/zz1-hp.snip
            fi
            patch_check "$GEN_UC" "config.experimental.clash_api = {" "generate_client.uc (Clash API)"
        fi
        # Каталог панели должен быть виден sing-box внутри ujail
        if [ -f "$HOMEPROXY_INIT" ] && ! grep -q 'clash_api_ui' "$HOMEPROXY_INIT"; then
            cat << 'HP_EOF' > /tmp/zz1-hp.snip
			# The panel files of the Clash API (external_ui) must be seen in the jail.
			local clash_api_ui
			config_get clash_api_ui "infra" "clash_api_ui"
			[ -z "$clash_api_ui" ] || procd_add_jail_mount "$clash_api_ui"
HP_EOF
            hp_insert "$HOMEPROXY_INIT" 'procd_add_jail_mount "/etc/TZ"' after /tmp/zz1-hp.snip &&
                log_ok "Каталог панели Clash API добавлен в jail init homeproxy (как патч 010)"
            rm -f /tmp/zz1-hp.snip
            patch_check "$HOMEPROXY_INIT" 'procd_add_jail_mount "$clash_api_ui"' "homeproxy init (Clash API в jail)"
        fi
        # Свой адрес или секрет, заданные вручную, не трогаем.
        if ! grep -q 'clash_api_controller' "$GEN_UC"; then
            :   # генератор не удалось доработать, ошибка уже в логе
        elif [ -z "$(uci -q get homeproxy.infra.clash_api_controller)" ]; then
            uci -q set homeproxy.infra.clash_api_controller='0.0.0.0:9090'
            uci -q set homeproxy.infra.clash_api_ui='/opt/yacd'
            run_cmd "Clash API homeproxy (опции UCI)" uci commit homeproxy
        else
            log_info "Clash API homeproxy уже задан: $(uci -q get homeproxy.infra.clash_api_controller)"
        fi
    fi

    # Пункт меню LuCI -> YACD. Адрес берётся из SERVER_ADDR, то есть из того,
    # по которому открыт сам LuCI. hostname/port в query-параметрах избавляют
    # от ручного добавления бэкенда: по умолчанию YACD предлагает 127.0.0.1,
    # а это адрес браузера, а не роутера.
    # В 25.12 каталога controller в образе нет: luci-lua-runtime его не
    # содержит, а ни один включённый пакет не ставит Lua-контроллеры.
    # Поэтому проверяем сам Lua-рантайм и создаём каталог.
    if [ -f /usr/lib/lua/luci/dispatcher.lua ]; then
        mkdir -p /usr/lib/lua/luci/controller
        cat << 'EOF' > /usr/lib/lua/luci/controller/yacd.lua
module("luci.controller.yacd", package.seeall)
function index()
	entry({"admin", "network", "yacd"}, call("redirectToYACD"), _("YACD"), 41)
end
function redirectToYACD()
	-- Серверный 302, а не window.open: всплывающее окно блокируется
	-- браузерами (в частности Chrome на iOS), если открывается не по
	-- касанию пользователя. Фрагмент #/home Location-заголовок сохраняет.
	local router_ip = luci.http.getenv("SERVER_ADDR")
	luci.http.redirect("http://" .. router_ip .. ":9090/ui/?hostname=" .. router_ip .. "&port=9090#/home")
end
EOF
        _RC=$?; [ $_RC -eq 0 ] && log_ok "Контроллер LuCI для YACD создан" || log_err "Ошибка создания контроллера YACD (exit: $_RC)"
        rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
    fi

    run_cmd "Отключение homeproxy" /etc/init.d/homeproxy disable

    HOMEPROXY_INIT="/etc/init.d/homeproxy"
    if [ -f "$HOMEPROXY_INIT" ]; then
        # Скрипт-помощник update_firewall_rules.sh прежних версий zz1 больше
        # не нужен: его заменяет правка init ниже (как патч 011).
        if grep -q 'update_firewall_rules' "$HOMEPROXY_INIT"; then
            sed -i '/update_firewall_rules\.sh/d' "$HOMEPROXY_INIT"
            log_ok "Вызовы старого скрипта-помощника убраны из init homeproxy"
        fi
        rm -f /etc/homeproxy/scripts/update_firewall_rules.sh

        # uci-defaults пакета всегда добавляет include-секции fw4, а файлы
        # для них init создаёт, только когда есть правила (TUN, сервер).
        # Без файлов fw4 на каждом reload пишет «unreachable path». Патч 011
        # создаёт их пустыми перед генераторами; без патча (сборка без патчей,
        # обновление из фида, Re:HomeProxy) вписываем те же строки сами.
        if grep -qF ': > "$RUN_DIR/fw4_forward.nft"' "$HOMEPROXY_INIT"; then
            log_info "Init homeproxy: пустые файлы include fw4 уже создаются"
        else
            cat << 'HP_EOF' > /tmp/zz1-hp.snip
	# The uci-defaults of the package always add the fw4 includes
	# homeproxy_forward, homeproxy_input and homeproxy_post. For a file that
	# does not exist fw4 prints "specifies unreachable path ..., ignoring
	# section" on every reload, and firewall_pre.uc writes its files only
	# when there are rules (TUN, server). Start from empty files, the
	# generators below fill them.
	: > "$RUN_DIR/fw4_forward.nft"
	: > "$RUN_DIR/fw4_input.nft"
	: > "$RUN_DIR/fw4_post.nft"
HP_EOF
            hp_insert "$HOMEPROXY_INIT" 'ucode "$HP_DIR/scripts/firewall_pre.uc"' before /tmp/zz1-hp.snip &&
                log_ok "Init homeproxy: пустые файлы include fw4 (как патч 011)"
            rm -f /tmp/zz1-hp.snip
            patch_check "$HOMEPROXY_INIT" ': > "$RUN_DIR/fw4_forward.nft"' "homeproxy init (include fw4)"
        fi

        # Секции возвращаем, если их удалял помощник прежних прошивок
        # (как их создаёт uci-defaults пакета).
        for _inc in forward input; do
            if [ -z "$(uci -q get firewall.homeproxy_${_inc})" ]; then
                uci -q batch <<-E_O_F
					set firewall.homeproxy_${_inc}=include
					set firewall.homeproxy_${_inc}.type=nftables
					set firewall.homeproxy_${_inc}.path="/var/run/homeproxy/fw4_${_inc}.nft"
					set firewall.homeproxy_${_inc}.position="chain-pre"
					set firewall.homeproxy_${_inc}.chain="${_inc}"
				E_O_F
                run_cmd "Include-секция firewall.homeproxy_${_inc}" uci commit firewall
            fi
        done
    fi
    run_cmd "Включение homeproxy" /etc/init.d/homeproxy enable

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
else
    # /etc/nftables.d/ — conffiles пакета firewall4: каталог переживает
    # sysupgrade с сохранением настроек. После перехода на вариант без
    # homeproxy цепочка обхода работала бы вхолостую на каждом пакете —
    # метку 0x64 читают только цепочки homeproxy.
    # Набор @bypass_ips при этом остаётся (см. «Наборы адресов fw4» ниже).
    if [ -f /etc/nftables.d/bypass_homeproxy_ips.nft ]; then
        run_cmd "Удаление bypass_homeproxy_ips.nft (homeproxy не установлен)" \
            rm -f /etc/nftables.d/bypass_homeproxy_ips.nft
    fi

    # Include-секции homeproxy в /etc/config/firewall тоже переживают
    # sysupgrade. homeproxy_post создаёт uci-defaults пакета (luci-homeproxy),
    # homeproxy_forward/_input — скрипт-помощник выше в режимах TUN/сервер.
    # Без homeproxy их файлы в /var/run/homeproxy/ не появятся, и fw4 на каждом
    # reload пишет «specifies unreachable path ..., ignoring section».
    # При возврате на homeproxy его uci-defaults пересоздаст секцию сам.
    _FW_INC_DEL=0
    for _inc in homeproxy_post homeproxy_forward homeproxy_input; do
        if uci -q get "firewall.$_inc" >/dev/null; then
            uci -q delete "firewall.$_inc" && _FW_INC_DEL=1
        fi
    done
    if [ "$_FW_INC_DEL" = "1" ]; then
        run_cmd "Удаление include-секций homeproxy из firewall" uci commit firewall
    fi
fi

# Passwall
if [ ! -f "$LOCK_FILE" ] && [ "$CURRENT_VARIANT" = "passwall" ] && [ -f "/etc/init.d/passwall2" ]; then
    log_info "Настройка Passwall2"
    run_cmd "Остановка passwall2" /etc/init.d/passwall2 stop
    run_cmd "Отключение passwall2" /etc/init.d/passwall2 disable

    uci -q batch <<-EOF
        set passwall2.@global[0].dns_redirect='0'
        set passwall2.@global[0].enabled='1'
        commit passwall2
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Конфигурация passwall2 обновлена" || log_err "Ошибка uci batch passwall2 (exit: $_RC)"

    run_cmd "Включение passwall2" /etc/init.d/passwall2 enable
fi
# dns_redirect=0: passwall2 не перехватывает DNS клиентов, а вписывает свои
# правила в dnsmasq (:54), к которому обращается AGH (см. блок AdGuardHome).
# Удалённый DNS passwall2 ходит через узел (remote_dns_detour=remote), поэтому
# адрес роутера 127.0.0.1:53, который раньше ставил сюда zz1, через узел
# недоступен, а с AGH → dnsmasq → Xray дал бы петлю. Возвращаем значение
# passwall2 по умолчанию; dns_shunt, china_dns и adblock — опции passwall 1,
# в passwall2 их нет.
if [ "$CURRENT_VARIANT" = "passwall" ] && [ -f "/etc/config/passwall2" ]; then
    _PW2_CHANGED=0
    if [ "$(uci -q get passwall2.@global[0].remote_dns)" = "127.0.0.1:53" ]; then
        uci -q set passwall2.@global[0].remote_dns='1.1.1.1' && _PW2_CHANGED=1
    fi
    for _o in dns_shunt china_dns adblock; do
        uci -q get "passwall2.@global[0].$_o" >/dev/null && uci -q delete "passwall2.@global[0].$_o" && _PW2_CHANGED=1
    done
    if [ "$_PW2_CHANGED" = "1" ]; then
        uci -q commit passwall2 && log_ok "passwall2: удалённый DNS 1.1.1.1 через узел, лишние опции убраны"
    fi
fi

# luci-app-xray: заводские настройки пакета рассчитаны на Китай — напрямую
# идут только адреса GeoIP «cn», «Fast DNS» по умолчанию 223.5.5.5 (Alibaba),
# напрямую через него разрешаются geosite:cn. На роутере в России это значит:
# весь российский трафик — через сервер, DNS имени сервера — через китайский
# резолвер. Меняем только нетронутые заводские значения и только на первой
# загрузке: напрямую — GeoIP «ru» и домены geosite:category-ru (их же
# разрешает Яндекс DNS напрямую), остальное — по правилам пакета.
# Нужны geoip.dat/geosite.dat (пакеты v2ray-geoip, v2ray-geosite в сборке):
# без них luci-app-xray молча отбрасывает все geoip:/geosite: правила.
if [ ! -f "$LOCK_FILE" ] && [ "$CURRENT_VARIANT" = "xray" ] && [ -f /etc/config/xray_core ]; then
    if [ "$(uci -q get xray_core.@general[0].geoip_direct_code_list)" = "cn" ] \
        && [ "$(uci -q get xray_core.@general[0].bypassed_domain_rules)" = "geosite:cn" ] \
        && [ -z "$(uci -q get xray_core.@general[0].fast_dns)" ]; then
        uci -q batch <<-EOF
            delete xray_core.@general[0].geoip_direct_code_list
            add_list xray_core.@general[0].geoip_direct_code_list='ru'
            delete xray_core.@general[0].geoip_direct_code_list_v6
            add_list xray_core.@general[0].geoip_direct_code_list_v6='ru'
            delete xray_core.@general[0].bypassed_domain_rules
            add_list xray_core.@general[0].bypassed_domain_rules='geosite:category-ru'
            set xray_core.@general[0].fast_dns='77.88.8.8:53'
            commit xray_core
EOF
        _RC=$?; [ $_RC -eq 0 ] && log_ok "xray_core: напрямую GeoIP ru и geosite:category-ru, Fast DNS 77.88.8.8" || log_err "Ошибка uci batch xray_core (exit: $_RC)"
    else
        log_info "xray_core уже настроен вручную — заводские правила не меняем"
    fi
    [ -s /usr/share/xray/geosite.dat ] && [ -s /usr/share/xray/geoip.dat ] \
        || log_err "xray: нет /usr/share/xray/geoip.dat или geosite.dat — правила geoip:/geosite: работать не будут"
fi

# Версия sing-box — вне вариантных блоков: бинарник ставится и в podkop,
# netshift, forkop, trafira, passwall, где homeproxy нет.
if [ -x /usr/bin/sing-box ]; then
    SB_version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP -m 1 'v?\K[\d.]+')
    [ -n "$SB_version" ] && log_ok "Версия sing-box: $SB_version" || log_info "sing-box есть, версию определить не удалось"
else
    log_info "sing-box не установлен"
fi

# --- Наборы адресов fw4 -------------------------------------------------------
# Создаются ВСЕГДА, независимо от варианта сборки. Причина: файлы в
# /etc/nftables.d/ переживают sysupgrade, и ссылка на несуществующий набор
# роняет весь fw4 reload. Пустой набор безопаснее отсутствующего.
#   dpi_ips      — youtubeUnblock: reject UDP/443 и очередь UDP на прочие порты
#                  (TCP/443 и UDP/443 идут в очередь к любым адресам)
#                  (наполняет fwlist-dpi.sh)
#   bypass_ips   — обход homeproxy по метке 0x64 (RU-трафик мимо VPN)
#                  И обход очереди youtubeUnblock для UDP кроме 443 (наполняет fwlist-bypass.sh)
#   bypass_local — обход очереди youtubeUnblock по адресу ИСТОЧНИКА, отсюда
#                  match=src_net, а не dest_net
# loadfile обязателен: без него набор создаётся пустым и файлы из
# /etc/luci-uploads/ не читаются никогда — обход молча не работает.
mkdir -p /etc/luci-uploads
FIREWALL_CONFIG_CHANGED=0

add_fw_ipset() {   # <имя> <match> <loadfile|-> <комментарий>
    local _name="$1" _match="$2" _file="$3" _cmt="$4" _sec _h
    # fw4 читает loadfile при каждом reload; пустой файл безопаснее отсутствующего
    [ "$_file" != "-" ] && [ ! -f "$_file" ] && : > "$_file"
    # cut по точкам даёт id секции и для анонимной (@ipset[0]), и для именованной
    _sec=$(uci show firewall | grep -F ".name='${_name}'" | head -n 1 | cut -d. -f2)
    if [ -z "$_sec" ]; then
        _h=$(uci add firewall ipset)
        uci set firewall."$_h".name="$_name"
        uci set firewall."$_h".match="$_match"
        uci set firewall."$_h".family="ipv4"
        uci set firewall."$_h".comment="$_cmt"
        [ "$_file" != "-" ] && uci set firewall."$_h".loadfile="$_file"
        FIREWALL_CONFIG_CHANGED=1
        log_ok "ipset $_name создан"
    elif [ "$_file" != "-" ] && [ -z "$(uci -q get "firewall.${_sec}.loadfile")" ]; then
        # секция осталась от старой версии скрипта — дополняем, не пересоздаём
        uci set firewall."$_sec".loadfile="$_file"
        FIREWALL_CONFIG_CHANGED=1
        log_ok "ipset $_name: добавлен loadfile"
    fi
}

add_fw_ipset dpi_ips      dest_net /etc/luci-uploads/dpi_ip_list.txt "youtubeUnblock"
add_fw_ipset bypass_ips   dest_net /etc/luci-uploads/bypass_ips.txt  "Bypass HomeProxy and youtubeUnblock"
add_fw_ipset bypass_local src_net  -                                 "Bypass youtubeUnblock"

[ "$FIREWALL_CONFIG_CHANGED" = 1 ] && uci commit firewall && log_ok "Firewall сохранён"

run_cmd "Правка ruleset.uc" sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' /usr/share/firewall4/templates/ruleset.uc
patch_check /usr/share/firewall4/templates/ruleset.uc 'ct original packets ge 30 flow offload @ft' "ruleset.uc"

if [ -x "/usr/bin/youtubeUnblock" ]; then
    run_cmd "Остановка youtubeUnblock" /etc/init.d/youtubeUnblock stop
    run_cmd "Отключение youtubeUnblock" /etc/init.d/youtubeUnblock disable
    # Метка и номер очереди — из настроек youtubeUnblock (packet_mark и
    # queue_num в /etc/config/youtubeUnblock): своей меткой youtubeUnblock
    # помечает отправленные им пакеты, и правила ниже должны совпадать с
    # ней. Пакет ставит правило на 0x8000, и с другой меткой (524288 —
    # обход для GL-iNet из issue #185) оно не срабатывало. Файл пишется
    # здесь: если метку или очередь потом поменять в LuCI, этот скрипт надо
    # запустить снова.
    # Метка в uci десятичная (youtubeUnblock читает её как %ld); ведущие
    # нули снимаются, иначе printf принял бы число за восьмеричное. Метка
    # пакета — 32 бита.
    YTB_MARK_RAW=$(uci -q get youtubeUnblock.youtubeUnblock.packet_mark)
    YTB_MARK=$(echo "${YTB_MARK_RAW:-32768}" | sed 's/^0*//; s/^$/0/')
    case "$YTB_MARK" in
    *[!0-9]*|???????????*) YTB_MARK=0 ;;
    esac
    [ "$YTB_MARK" -le 4294967295 ] || YTB_MARK=0
    YTB_MARK=$(printf '0x%x' "$YTB_MARK")
    if [ "$YTB_MARK" = 0x0 ]; then
        log_err "youtubeUnblock: packet_mark '$YTB_MARK_RAW' — не число от 1 до 4294967295, в правилах 0x8000"
        YTB_MARK=0x8000
    fi
    YTB_QUEUE=$(uci -q get youtubeUnblock.youtubeUnblock.queue_num)
    YTB_QUEUE=${YTB_QUEUE:-537}
    case "$YTB_QUEUE" in
    *[!0-9]*) YTB_QUEUE=-1 ;;
    esac
    if [ "$YTB_QUEUE" -lt 0 ] || [ "$YTB_QUEUE" -gt 65535 ]; then
        log_err "youtubeUnblock: queue_num — не число от 0 до 65535, в правилах 537"
        YTB_QUEUE=537
    fi
    log_info "youtubeUnblock: метка $YTB_MARK, очередь $YTB_QUEUE"
    cat << EOF > /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
#!/usr/sbin/nft -f
# This file will be applied automatically for nftables <table> <chain> position <number> <condition> <action>

# Drop (reject) UDP to dest port 443 to DPI IPs
add rule inet fw4 prerouting ip daddr @dpi_ips udp dport 443 reject with icmp port-unreachable

# DPI through youtubeUnblock
add chain inet fw4 youtubeUnblock { type filter hook postrouting priority mangle - 1; policy accept; }

# Packets of youtubeUnblock itself (its mark $YTB_MARK: fakes and resent
# originals) go out at once instead of waiting in the queue behind the packet
# being handled, so the fakes leave before the original
add rule inet fw4 youtubeUnblock meta mark and $YTB_MARK == $YTB_MARK counter return

# Exclusion of the guest network by tag (traffic will bypass the queue)
add rule inet fw4 youtubeUnblock meta mark 0x00000042 counter return

# Source IP in the bypass_local list: exit the chain
add rule inet fw4 youtubeUnblock ip saddr @bypass_local counter return

# TCP/443 and QUIC to any address, before the bypass_ips check: YouTube also
# serves video from Google caches inside Russian ISP networks (GGC), their
# addresses are in bypass_ips and not in dpi_ips. youtubeUnblock picks
# connections by SNI itself (--sni-domains; for QUIC with
# --udp-filter-quic=parse), the rest pass through unchanged.
add rule inet fw4 youtubeUnblock tcp dport 443 ct original packets < 20 counter queue num $YTB_QUEUE bypass
add rule inet fw4 youtubeUnblock udp dport 443 ct original packets < 9 counter queue num $YTB_QUEUE bypass

# Destination IP in the bypass_ips list: exit the chain
add rule inet fw4 youtubeUnblock ip daddr @bypass_ips counter return

# Other UDP ports only to DPI IPs
add rule inet fw4 youtubeUnblock ip daddr @dpi_ips meta l4proto udp ct original packets < 9 counter queue num $YTB_QUEUE bypass

# Packets of youtubeUnblock (mark $YTB_MARK) are accepted at the start of
# output: a fake is out of state for conntrack and must not be dropped
insert rule inet fw4 output mark and $YTB_MARK == $YTB_MARK counter accept

# ...and at the start of mangle_output, before a proxy that takes the
# router's own UDP: homeproxy in tproxy mode marks every such packet without
# its own mark for sing-box (mark 101, route to lo). It would overwrite the
# mark of a fake or resent original, which then went into sing-box instead
# of the internet, and youtubeUnblock, no longer seeing its mark, queued and
# faked its own packets again.
insert rule inet fw4 mangle_output mark and $YTB_MARK == $YTB_MARK counter accept
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Файл youtubeUnblock.nft записан" || log_err "Ошибка записи правил (exit: $_RC)"
    chmod 0644 /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
    # Перезапуск при падении: init пакета запускает youtubeUnblock без
    # respawn, и упавший процесс никто не поднимал — очередь 537 с bypass
    # пропускала трафик без обработки до перезагрузки или ручного старта.
    # procd перезапускает до 5 раз подряд (если процесс живёт меньше часа).
    if ! grep -q 'procd_set_param respawn' /etc/init.d/youtubeUnblock; then
        run_cmd "youtubeUnblock: перезапуск при падении" \
            sed -i '/procd_set_param stderr 1/a\	procd_set_param respawn' /etc/init.d/youtubeUnblock
    fi
    patch_check /etc/init.d/youtubeUnblock 'procd_set_param respawn' "init youtubeUnblock (respawn)"
    run_cmd "Включение youtubeUnblock" /etc/init.d/youtubeUnblock enable
else
    log_info "youtubeUnblock не установлен"
    # Файл пишет этот же скрипт; остаётся, если пакет удалили на живой системе.
    # Очередь 537 без youtubeUnblock никто не слушает.
    if [ -f /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft ]; then
        run_cmd "Удаление 537-youtubeUnblock.nft (youtubeUnblock не установлен)" \
            rm -f /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
    fi
fi

# internet-detector
# Служба выключена: детектор работает в режиме «Web UI only» (mode 2) — rpcd
# запускает его, пока открыт LuCI, и он сам выходит через 30 с после закрытия
# страницы. В режиме «Service» (mode 1, так в конфиге пакета) индикатор лишь
# читает статус работающей службы, и без неё в LuCI навсегда «Undefined», а
# модули (публичный IP и т.п.) не запускаются. Поэтому mode 1 -> 2; выбранные
# вручную 0 (выключен) и 2 не трогаем.
[ -f "/etc/init.d/internet-detector" ] && {
    run_cmd "Отключение internet-detector" /etc/init.d/internet-detector disable
    run_cmd "Смена START на 99" sed -i 's/START=[0-9][0-9]/START=99/' /etc/init.d/internet-detector
    if [ "$(uci -q get internet-detector.config.mode)" = "1" ]; then
        uci -q set internet-detector.config.mode='2' && uci commit internet-detector \
            && log_ok "internet-detector: режим Service -> Web UI only (служба выключена)" \
            || log_err "internet-detector: не удалось переключить режим на Web UI only"
    fi
}

# attendedsysupgrade: сервер сборок (owut, LuCI) — по платформе.
# ImmortalWrt перенёс ASU на sysupgrade.kyarucloud.moe (так в его пакете
# attendedsysupgrade-common); прежний asu-2.kyarucloud.moe не отвечает
# (HTTP 530). Значение ставится через uci, а не заменой одного известного
# адреса sed'ом: тот молча ничего не делал, если в конфиге стоял третий адрес.
if [ -f /etc/config/attendedsysupgrade ]; then
    if [ "$NAME_VALUE" = "OpenWrt" ]; then
        ASU_URL="https://sysupgrade.openwrt.org"
    else
        ASU_URL="https://sysupgrade.kyarucloud.moe"
    fi
    if [ "$(uci -q get attendedsysupgrade.server.url)" = "$ASU_URL" ]; then
        log_ok "owut: сервер $ASU_URL уже задан"
    else
        run_cmd "Настройка owut ($NAME_VALUE): $ASU_URL" uci set attendedsysupgrade.server.url="$ASU_URL"
        uci commit attendedsysupgrade
    fi
else
    log_info "attendedsysupgrade не установлен, сервер owut не настраиваем"
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

    mkdir -p /usr/lib/lua/luci/controller   # в образе 25.12 каталога нет
    cat << 'EOF' > /usr/lib/lua/luci/controller/adguardhome_net.lua
module("luci.controller.adguardhome_net", package.seeall)

function index()
	entry({"admin", "network", "adguardhome"}, call("redirectToAdGuardHome"), _("AdGuardHome"), 40)
end

function redirectToAdGuardHome()
	-- Серверный 302 вместо window.open: всплывающее окно блокируется
	-- браузером, если открывается не по касанию пользователя.
	local router_ip = luci.http.getenv("SERVER_ADDR")
	luci.http.redirect("http://" .. router_ip .. ":8080")
end
EOF
    _RC=$?; [ $_RC -eq 0 ] && log_ok "Контроллер LuCI создан" || log_err "Ошибка создания контроллера (exit: $_RC)"

    run_cmd "Смена порта dnsmasq" uci set dhcp.@dnsmasq[0].port="54"
    run_cmd_ign "Удаление серверов dnsmasq" uci delete dhcp.@dnsmasq[0].server
    run_cmd "Сохранение dhcp" uci commit dhcp

    # Журнал AdGuard Home — в файл, а не в syslog (он забивает системный
    # журнал). Файл лежит в /tmp/log (он же /var/log, создаётся при каждой
    # загрузке), и этот каталог подключается в песочницу ujail на запись:
    # прежний /var/AdGuardHome.log из песочницы недоступен. Без ujail
    # работает так же.
    run_cmd "Журнал adguardhome → /tmp/log/AdGuardHome.log" \
        sed -i -e 's|--logfile syslog|--logfile /tmp/log/AdGuardHome.log|' \
               -e 's|--logfile /var/AdGuardHome.log|--logfile /tmp/log/AdGuardHome.log|' /etc/init.d/adguardhome
    patch_check /etc/init.d/adguardhome '--logfile /tmp/log/AdGuardHome.log' "adguardhome init (журнал)"
    uci -q del_list adguardhome.config.jail_mount_rw='/tmp/log'
    uci -q add_list adguardhome.config.jail_mount_rw='/tmp/log'
    run_cmd "Каталог журнала в песочнице adguardhome" uci commit adguardhome
    # --- Upstream DNS в AGH yaml ------------------------------------------
    # Зависит от варианта сборки:
    #   forkop, trafira, podkop, netshift → 127.0.0.42:53 (DNS inbound их sing-box)
    #   xray            → 127.0.0.1:5300 (DNS-вход Xray luci-app-xray: FakeDNS,
    #                     Fast/Secure DNS и правила доменов работают в нём)
    #   passwall, v2raya → 127.0.0.1:54 (dnsmasq). passwall2 при
    #                     dns_redirect=0 вписывает в dnsmasq свои правила:
    #                     по умолчанию — DNS-вход своего Xray (порт выбирается
    #                     при каждом запуске), адреса узлов — DNS провайдера.
    #                     v2rayA свой DNS на :53 при AGH не поднимает (порт
    #                     занят), а трафик всё равно разводит по сниффингу.
    #   homeproxy и остальные → 127.0.0.1:5333 (DNS-порт sing-box homeproxy)
    # Любой из этих адресов, оставшийся от прошлого варианта, заменяется на
    # нужный. Правим yaml напрямую: AGH хранит upstream только там, не в UCI.
    # AGH должен быть остановлен в этот момент (выше есть stop).
    # Меняется только пункт списка upstream_dns целиком: 127.0.0.1:54 стоит
    # ещё в local_ptr_upstreams и в правиле [/lan/arpa/local/]127.0.0.1:54,
    # их трогать нельзя. Повтор нужного адреса в списке не оставляется.
    AGH_YAML="/etc/adguardhome/adguardhome.yaml"
    if [ -f "$AGH_YAML" ]; then
        case "$CURRENT_VARIANT" in
            forkop|trafira|podkop|netshift) _AGH_EXPECTED='127.0.0.42:53' ;;
            xray)          _AGH_EXPECTED='127.0.0.1:5300' ;;
            passwall|v2raya) _AGH_EXPECTED='127.0.0.1:54' ;;
            *)             _AGH_EXPECTED='127.0.0.1:5333' ;;
        esac
        # $1: файл; new — адрес для замены (пусто — только проверить наличие)
        agh_upstream() {
            awk -v new="$2" -v want="$_AGH_EXPECTED" -v q="'" '
                function val(s) { sub(/^[[:space:]]*-[[:space:]]*/, "", s); gsub(/[" \t]/, "", s); gsub(q, "", s); return s }
                /^[[:space:]]*upstream_dns:[[:space:]]*$/ { inb = 1; print; next }
                inb && /^[[:space:]]*-/ {
                    v = val($0)
                    if (new != "" && (v == "127.0.0.1:5333" || v == "127.0.0.42:53" || v == "127.0.0.1:5300" || v == "127.0.0.1:54")) {
                        if (done) next
                        sub(/-.*/, "- " new); v = new; done = 1
                    }
                    if (new == "" && v == want) found = 1
                    print; next
                }
                inb && !/^[[:space:]]*$/ { inb = 0 }
                { print }
                END { if (new == "") exit !found }
            ' "$1"
        }
        if agh_upstream "$AGH_YAML" "$_AGH_EXPECTED" > "$AGH_YAML.zz1" && [ -s "$AGH_YAML.zz1" ]; then
            cat "$AGH_YAML.zz1" > "$AGH_YAML"   # cat, а не mv: права и владелец файла остаются
        else
            log_err "adguardhome.yaml: не удалось заменить upstream DNS"
        fi
        rm -f "$AGH_YAML.zz1"
        if [ "$_AGH_EXPECTED" = '127.0.0.42:53' ] && [ "$CURRENT_VARIANT" = "forkop" ] && forkop_v2; then
            # forkop 2.x dnsmasq не трогает, а DNS клиентов (порт 53 с
            # интерфейсов источника) и самого роутера (127.0.0.1:53) забирает
            # себе nft-перенаправлением. Наш патч 002 (patches/feeds/forkop)
            # добавляет intercept_device_dns: с '0' запросы клиентов идут в AGH,
            # и он видит каждого; в forkop — только устройства из фильтров
            # секций, им нужен свой ответ. AGH отправляет запросы на 127.0.0.42:
            # там домены секций получают FakeIP, остальные отвечают DNS-серверы
            # forkop (правила «вне секций → роутер» на этом входе нет, петли
            # нет). FakeIP-соединения исключённых устройств патч 002 отправляет
            # напрямую. Без патча опция ни на что не влияет: клиенты в журнале
            # AGH видны как 127.0.0.1.
            # unmatched_dns_mode=router — для тех, кого forkop перехватывает
            # (устройства из фильтров, сам роутер): DNS вне секций — тоже через
            # AGH (его сокет помечен, повторно не перехватывается).
            uci -q set forkop.settings.intercept_device_dns='0' 2>/dev/null \
                && uci -q set forkop.settings.unmatched_dns_mode='router' 2>/dev/null \
                && uci commit forkop 2>/dev/null \
                && log_ok "forkop 2.x: intercept_device_dns=0 (AGH видит клиентов), unmatched_dns_mode=router"
            log_ok "AGH upstream → forkop sing-box ($_AGH_EXPECTED)"
        elif [ "$_AGH_EXPECTED" = '127.0.0.42:53' ]; then
            # Все они по умолчанию сами перенастраивают dnsmasq на 127.0.0.42
            # (dont_touch_dhcp=0). Хозяин :53 — AGH, dnsmasq на :54 — поэтому
            # выставляем флаг, чтобы они dnsmasq не трогали.
            uci -q set "$CURRENT_VARIANT".settings.dont_touch_dhcp='1' 2>/dev/null \
                && uci commit "$CURRENT_VARIANT" 2>/dev/null \
                && log_ok "$CURRENT_VARIANT: dont_touch_dhcp=1 (AGH остаётся хозяином на :53)"
            # trafira: опция есть (dns/apply.uc: dnsmasq не перенастраивается,
            # прежние правки trafira в нём откатываются). По умолчанию (Alice
            # Mode выключен, без секций с DNS по устройствам) он DNS клиентов
            # не перехватывает и AGH видит каждого. С включённым Alice Mode
            # DNS клиентов «в обход» уходит в DNS trafira мимо AGH
            # (статистика/фильтры AGH для них не работают) — это его штатное
            # поведение, здесь не меняется.
            log_ok "AGH upstream → $CURRENT_VARIANT sing-box ($_AGH_EXPECTED)"
        elif [ "$CURRENT_VARIANT" = "xray" ]; then
            # luci-app-xray сам кладёт dnsmasq «server=127.0.0.1#5300»; при AGH
            # dnsmasq живёт на :54 и клиентский DNS не видит, поэтому AGH
            # обращается к DNS-входу Xray напрямую. Локальные имена (PTR, .lan)
            # dnsmasq по-прежнему отдаёт сам.
            log_ok "AGH upstream → Xray DNS ($_AGH_EXPECTED)"
        elif [ "$_AGH_EXPECTED" = '127.0.0.1:54' ]; then
            log_ok "AGH upstream → dnsmasq ($_AGH_EXPECTED): DNS-правила $CURRENT_VARIANT"
        else
            log_ok "AGH upstream → homeproxy sing-box ($_AGH_EXPECTED)"
        fi
        if agh_upstream "$AGH_YAML" "" >/dev/null; then
            log_ok "adguardhome.yaml upstream DNS: $_AGH_EXPECTED на месте"
        else
            log_err "adguardhome.yaml upstream DNS: $_AGH_EXPECTED не найден в upstream_dns"
        fi
    else
        log_info "AGH yaml не найден ($AGH_YAML) — upstream DNS не настроен автоматически"
    fi

    run_cmd "Включение adguardhome" /etc/init.d/adguardhome enable
    run_cmd "Запуск adguardhome" /etc/init.d/adguardhome start
else
    log_info "AdGuardHome не найден"
fi

# Свои пункты меню LuCI (Lua-контроллеры) из /root/apps/luci-controllers/.
# Папка есть только на роутере (в репозитории её нет: там личные ссылки) и
# переживает sysupgrade через /etc/sysupgrade.conf. Копируются, только если
# в прошивке есть и AdGuardHome, и sing-box, и только те файлы, которых на
# роутере ещё нет: правки, сделанные на роутере, не затираются. Нужен
# Lua-рантайм LuCI (luci-lua-runtime / luci-compat).
LUCI_CTRL_SRC="/root/apps/luci-controllers"
LUCI_CTRL_DST="/usr/lib/lua/luci/controller"
if [ -d "$LUCI_CTRL_SRC" ]; then
    # Строка каталогом, а не списком файлов: новые файлы в папке попадут в
    # резервную копию сами. sysupgrade берёт каталог целиком через find.
    grep -qxE "$LUCI_CTRL_SRC/?" /etc/sysupgrade.conf 2>/dev/null \
        || { echo "$LUCI_CTRL_SRC" >> /etc/sysupgrade.conf && log_ok "$LUCI_CTRL_SRC добавлен в /etc/sysupgrade.conf"; }
fi
if ls "$LUCI_CTRL_SRC"/*.lua >/dev/null 2>&1; then
    if [ -x /usr/bin/AdGuardHome ] && [ -x /usr/bin/sing-box ] && [ -f /usr/lib/lua/luci/dispatcher.lua ]; then
        mkdir -p "$LUCI_CTRL_DST"
        _CTRL_NEW=0
        for _ctrl in "$LUCI_CTRL_SRC"/*.lua; do
            _ctrl_name=$(basename "$_ctrl")
            if [ -f "$LUCI_CTRL_DST/$_ctrl_name" ]; then
                log_ok "Контроллер LuCI $_ctrl_name уже есть, не трогаем"
            elif cp "$_ctrl" "$LUCI_CTRL_DST/$_ctrl_name"; then
                chmod 644 "$LUCI_CTRL_DST/$_ctrl_name"
                log_ok "Контроллер LuCI $_ctrl_name скопирован"
                _CTRL_NEW=1
            else
                log_err "Не удалось скопировать контроллер LuCI $_ctrl_name"
            fi
        done
        [ "$_CTRL_NEW" = 1 ] && rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
    else
        log_info "Свои контроллеры LuCI пропущены: нет AdGuardHome, sing-box или Lua-рантайма LuCI"
    fi
fi

# forkop/trafira/podkop/netshift: NTP мимо прокси. Штатная опция вставляет «udp dport
# 123 return» в цепочку mangle их nft-таблицы (у forkop и в mangle_output).
# Иначе NTP к адресам из списков прокси уходил бы в TPROXY — та же проблема,
# что была с ntpd на homeproxy.
for _pk in forkop trafira podkop netshift; do
    [ -f "/etc/config/$_pk" ] || continue
    # forkop 2.x: опции нет, NTP-серверы роутера он сам резолвит через
    # bootstrap DNS, а трафик роутера в секции не берёт без пункта «Система»
    if [ "$_pk" = "forkop" ] && forkop_v2; then
        log_info "forkop 2.x: exclude_ntp нет — пропуск"
        continue
    fi
    if [ "$(uci -q get "$_pk".settings.exclude_ntp)" = "1" ]; then
        log_ok "$_pk: exclude_ntp уже включён"
    elif uci -q set "$_pk".settings.exclude_ntp='1' && uci commit "$_pk"; then
        log_ok "$_pk: exclude_ntp=1 (NTP мимо прокси)"
    else
        log_err "$_pk: не удалось выставить exclude_ntp"
    fi
done

# forkop/trafira/podkop/netshift + youtubeUnblock: QUIC мимо sing-box не пускаем.
# Эти пакеты отдают доменам из своих списков (и из секций «Исключение» — в
# netshift они тоже идут через FakeIP) адреса FakeIP 198.18.0.0/15. Правило
# youtubeUnblock «ip daddr @dpi_ips udp dport 443 reject» видит только настоящие
# адреса, поэтому QUIC клиента к FakeIP проходил бы в sing-box, а оттуда — в
# очередь 537 как обычный UDP, и видео (googlevideo) могло тормозить. Штатная
# опция disable_quic ставит в sing-box правило reject для QUIC на входе tproxy:
# браузер сразу переходит на TCP, который youtubeUnblock обрабатывает. HTTP/3
# при этом не используется и для сайтов через VPS — для прокси это обычно лучше.
# Без youtubeUnblock (forkop-mod и trafira — у них свой Zapret; forkop 2.x —
# если youtubeUnblock не выбран) опцию не трогаем.
if [ -x /usr/bin/youtubeUnblock ]; then
    for _pk in forkop trafira podkop netshift; do
        [ -f "/etc/config/$_pk" ] || continue
        if [ "$(uci -q get "$_pk".settings.disable_quic)" = "1" ]; then
            log_ok "$_pk: disable_quic уже включён"
        elif uci -q set "$_pk".settings.disable_quic='1' && uci commit "$_pk"; then
            log_ok "$_pk: disable_quic=1 (QUIC через FakeIP отклоняется, браузер идёт по TCP для youtubeUnblock)"
        else
            log_err "$_pk: не удалось выставить disable_quic"
        fi
    done
fi

# SQM: diffserv4 и приоритеты на загрузке — скрипт cake_ctinfo.qos.
# Он лежит в прошивке (/usr/lib/sqm), в пакет sqm-scripts не входит, поэтому
# run.sh больше не патчится и apk upgrade sqm-scripts ничего не ломает.
if [ -f "/usr/lib/sqm/run.sh" ]; then
    log_info "Настройка SQM"

    # Прежние zz1 вставляли в run.sh загрузчик /opt/sqm_custom.conf. После
    # прошивки run.sh и так новый, а при ручном запуске на старой установке
    # загрузчик надо убрать: он перекрывал бы опции из LuCI.
    if grep -q "sqm_custom.conf" /usr/lib/sqm/run.sh; then
        sed -i '/# --- Load Custom Config (\/opt\/sqm_custom.conf) ---/,/^    fi$/d' /usr/lib/sqm/run.sh
        if grep -q "sqm_custom.conf" /usr/lib/sqm/run.sh; then
            log_err "Загрузчик /opt/sqm_custom.conf в run.sh не удалён"
        else
            log_ok "Загрузчик /opt/sqm_custom.conf удалён из run.sh"
        fi
    fi

    # /opt/sqm_custom.conf прежних zz1 → опции UCI (в LuCI: «Qdisc options»).
    # Переносим только в очереди, где свои опции ещё не заданы; файл
    # переименовывается, чтобы перенос не повторялся.
    if [ -f /opt/sqm_custom.conf ]; then
        cust_i=$(grep "^option iqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        cust_e=$(grep "^option eqdisc_opts" /opt/sqm_custom.conf | cut -d"'" -f2)
        for _q in $(uci -q show sqm | sed -n "s/^sqm\.\([^.=]*\)=queue$/\1/p"); do
            [ -z "$(uci -q get sqm.$_q.iqdisc_opts)$(uci -q get sqm.$_q.eqdisc_opts)" ] || continue
            [ -n "$cust_i" ] && uci set sqm.$_q.iqdisc_opts="$cust_i"
            [ -n "$cust_e" ] && uci set sqm.$_q.eqdisc_opts="$cust_e"
            # без этих флагов LuCI при сохранении формы удаляет опции
            uci set sqm.$_q.qdisc_advanced='1'
            uci set sqm.$_q.qdisc_really_really_advanced='1'
            log_ok "SQM $_q: опции из /opt/sqm_custom.conf перенесены в UCI"
        done
        uci commit sqm
        mv -f /opt/sqm_custom.conf /opt/sqm_custom.conf.migrated
    fi

    # piece_of_cake.qos у прежних zz1 и так работал как diffserv4 (через
    # загрузчик), cake_ctinfo.qos — то же самое плюс приоритеты на загрузке.
    if [ -f /usr/lib/sqm/cake_ctinfo.qos ]; then
        for _q in $(uci -q show sqm | sed -n "s/^sqm\.\([^.=]*\)=queue$/\1/p"); do
            if [ "$(uci -q get sqm.$_q.script)" = "piece_of_cake.qos" ]; then
                uci set sqm.$_q.script='cake_ctinfo.qos'
                log_ok "SQM $_q: piece_of_cake.qos → cake_ctinfo.qos"
            fi
        done
        uci commit sqm
    else
        log_err "Нет /usr/lib/sqm/cake_ctinfo.qos"
    fi

    if [ ! -d /sys/module/act_ctinfo ] && [ -z "$(find /lib/modules/$(uname -r) -name 'act_ctinfo.ko' 2>/dev/null)" ]; then
        log_info "kmod-sched-ctinfo не установлен: приоритеты будут только на отдаче"
    fi

    # Шаблон правил приоритета: все строки закомментированы, файл ничего не
    # делает, пока правила не включены. Свой файл с тем же именем не
    # трогается: /etc/nftables.d/ переживает sysupgrade.
    PRIO_NFT="/etc/nftables.d/10-priority-mangle.nft"
    if [ ! -f "$PRIO_NFT" ]; then
        mkdir -p /etc/nftables.d
        cat > "$PRIO_NFT" <<'NFT'
# Приоритеты для SQM (скрипт cake_ctinfo.qos, diffserv4). Уровни cake:
#   EF    → Voice       — высший, без очереди до 25% канала (игры, звонки)
#   AF21  → Video       — нормальный, преимущество до 50% канала
#   CS0   → Best Effort — низкий
#   LE    → Bulk        — наименьший (фоновые загрузки)
# ct mark = (DSCP << 26) | 0x01000000 сохраняет метку в соединении,
# cake_ctinfo.qos восстанавливает её для входящих пакетов (нужен
# kmod-sched-ctinfo). Значения: EF 0xb9000000, AF21 0x49000000,
# CS0 0x01000000, LE 0x05000000.
# Раскомментируйте цепочку, впишите свои адреса и выполните
#   fw4 check && service firewall restart
#
#chain priority_mangle_prerouting_dscp {
#	type filter hook prerouting priority mangle; policy accept;
#	ip saddr 192.168.1.10 meta l4proto udp counter ip dscp set ef ct mark set 0xb9000000 return comment "Console games: Voice"
#	ip saddr 192.168.1.0/24 counter ip dscp set af21 ct mark set 0x49000000 return comment "LAN: Video"
#	ip saddr 192.168.2.0/24 counter ip dscp set cs0 ct mark set 0x01000000 return comment "Guest: Best Effort"
#	ip saddr 192.168.3.0/24 counter ip dscp set lephb ct mark set 0x05000000 return comment "IoT: Bulk"
#}
NFT
        _RC=$?; [ $_RC -eq 0 ] && log_ok "Шаблон $PRIO_NFT создан" || log_err "Ошибка создания $PRIO_NFT (exit: $_RC)"
    else
        log_ok "$PRIO_NFT уже существует, не трогаем"
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
# -delete есть только в GNU find; в варианте switch findutils вырезан part3
find /etc/config/ -type f \( -name '*-opkg' -o -name '*apk-new' \) -exec rm -f {} + 2>/dev/null
log_info "Временные файлы удалены"

# FullCone NAT
if [ -f "/lib/modules/$(uname -r)/nft_fullcone.ko" ] || lsmod | grep -q nft_fullcone; then
    run_cmd "Включение FullCone NAT" uci set firewall.@defaults[0].fullcone='1'
    uci commit firewall
fi

# MPTCP
# Сам роутер Multipath TCP не использует (транзитный трафик устройств эта
# настройка не затрагивает), а мешает он так: Go 1.24+ (sing-box, Xray)
# по умолчанию слушает с MPTCP. MPTCP-соединение устройства из LAN
# (так делают, например, iPhone для сервисов Apple) попадает на вход
# redirect, а исходный адрес (SO_ORIGINAL_DST) ядро для MPTCP-сокета не
# отдаёт: соединение обрывается с «get redirect destination: operation not
# supported». Без MPTCP Go слушает обычный TCP, и устройство переходит на
# него само. Своя строка net.mptcp.enabled в sysctl.conf (например, = 1)
# не трогается; /etc/sysctl.conf сохраняется при перепрошивке.
if [ -f /proc/sys/net/mptcp/enabled ]; then
    if grep -q '^[[:space:]]*net\.mptcp\.enabled' /etc/sysctl.conf 2>/dev/null; then
        log_info "net.mptcp.enabled уже задан в /etc/sysctl.conf — оставлен как есть"
    else
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/sysctl.conf
        echo -e "\n# MPTCP\nnet.mptcp.enabled = 0" >> /etc/sysctl.conf
        log_ok "MPTCP выключен"
    fi
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
    # STP выключен: у коммутатора один uplink, колец нет. С STP мост Linux
    # держит каждый поднявшийся порт ~17 с в listening/learning (устройство
    # без сети после включения) и шлёт topology change, сбрасывающий таблицы
    # MAC. Если появятся два кабеля к одной сети (кольцо), включите stp='1'.
    uci set network.@device[0].stp='0'
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
    # IP-литералы, а не имя: AdGuardHome перезапущен секундой раньше
    # и ещё не слушает :53, DNS у роутера в этот момент недоступен
    if ntpd -q -n -p 162.159.200.123 -p 162.159.200.1 -p 216.239.35.0 2>/dev/null; then
        log_ok "NTP синхронизировано"; NTP_OK=1
    else
        log_err "Ошибка ntpd"; NTP_OK=0
    fi
    /etc/init.d/sysntpd start 2>/dev/null
    CUR_YEAR=$(date +%Y)
    if [ "$NTP_OK" = "1" ] || { [ "$CUR_YEAR" -ge 2025 ] && [ "$CUR_YEAR" -le 2050 ]; }; then
        hwclock -w -u 2>/dev/null && log_ok "RTC обновлён"
    else
        log_info "Часы недостоверны ($CUR_YEAR) — RTC не перезаписываем"
    fi
else
    /etc/init.d/sysntpd restart 2>/dev/null
    log_info "Пинг 8.8.8.8 пока не доступен"
fi

sleep 2

[ -f /etc/banner.bak ] || cp /etc/banner /etc/banner.bak
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
# Фиды: tag — коммиты релизного тега, repo — репозитория пакетов
# (поле feeds_latest); первая строка /etc/build_feeds пишется при сборке.
FEEDS_STR=$(head -n 1 /etc/build_feeds 2>/dev/null)
echo " Build Variant: $CURRENT_VARIANT ($DATE_STR${FEEDS_STR:+, feeds: $FEEDS_STR})" >> /etc/banner
log_ok "Баннер обновлён"

# Имя хоста — только на первой загрузке, чтобы ручной прогон не сбрасывал
# переименованный роутер обратно в шаблон
if [ "$MODE" = "firstboot" ]; then
    run_cmd "Установка hostname" uci set system.@system[0].hostname="$HOSTNAME_PATTERN"
    run_cmd "Сохранение system" uci commit system
    run_cmd "Установка commonname" uci set uhttpd.defaults.commonname="$HOSTNAME_PATTERN"
    uci commit uhttpd
else
    log_info "hostname/commonname не трогаем (maintenance)"
fi

FM_MENU="/usr/share/luci/menu.d/luci-app-filemanager.json"
if [ -f "$FM_MENU" ]; then
    sed -i "s/File Manager/Файловый менеджер/" "$FM_MENU"
    patch_check "$FM_MENU" 'Файловый менеджер' "filemanager menu"
else
    log_info "luci-app-filemanager не установлен, меню не правим"
fi

# --- Фикс mtime из будущего (иначе sysfixtime отбросит часы вперёд при загрузке) ---
# Область /etc выбрана верно: sysfixtime сканирует ровно её.
CUR_YEAR=$(date +%Y)
if [ "$CUR_YEAR" -ge 2025 ] && [ "$CUR_YEAR" -le 2050 ]; then
    MTIME_REF="/tmp/.zz1_mtime_ref"
    touch "$MTIME_REF"
    FUTURE=$(find /etc -type f -newer "$MTIME_REF")
    rm -f "$MTIME_REF"
    if [ -n "$FUTURE" ]; then
        echo "$FUTURE" | xargs touch
        log_ok "Исправлено mtime в будущем: $(echo "$FUTURE" | wc -l) файлов"
    else
        log_ok "Файлов с mtime в будущем нет"
    fi
else
    log_info "Часы не синхронизированы ($CUR_YEAR) — фикс mtime пропущен"
fi

touch "$LOCK_FILE"

# Гарантированная запись лога перед уходом в фон
sync
log_info "Отложенная перезагрузка через 120 секунд (процесс в фоне)"
(sleep 120; sync; reboot) &

log_info "Настройка завершена. Количество ошибок в логе: $ERROR_COUNT"
exit 0
