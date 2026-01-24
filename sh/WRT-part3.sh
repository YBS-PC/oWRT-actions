#!/bin/bash

echo ">>>>>>>>> WRT-part3 start. Использование: до make defconfig"
####################################################################
##echo ">>> Force-disabling unwanted packages..."
# Список пакетов, которые нужно принудительно отключить. Например:
# apk-mbedtls libmbedtls libwolfssl libustream-mbedtls wpad-basic-mbedtls mbedtls-util
# autocore automount block-mount bridger cpufreq luci-app-cpufreq default-settings-chn 
##DELLIST=(
##    bind
##    automount
##    bridger
##)
##
##for pkg in "${DELLIST[@]}"; do
##    # Удаляем все существующие строки для этого пакета (с любым значением) и добавляем с =n
##    sed -i "/CONFIG_${pkg}/Id" ./.config
##    sed -i "/CONFIG_PACKAGE_${pkg}/Id" ./.config
##    echo "CONFIG_PACKAGE_${pkg}=n" >> ./.config
##done
####################################################################

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление пакетов из их репозиториев
# =========================================================
# Создаем общие папки (флаг -p чтобы не было ошибок если папка уже есть)
mkdir -p ./package/luci-app-log-viewer

# Клонируем общие пакеты
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/

# =========================================================
# УСЛОВНАЯ УСТАНОВКА facinstall
# Выполняется только если ax59u
# =========================================================
if [ "$CURRENT_MATRIX_TARGET" == "ax59u" ]; then
    mkdir -p ./package/facinstall
    git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
    echo ">>> [Git] Устройство ax59u - исходники facinstall добавлены"
else
    echo ">>> [Git] Устройство не ax59u - исходники facinstall не добавлены"
fi

# =========================================================
# УСЛОВНАЯ УСТАНОВКА ZAPRET
# Выполняется только если в .config есть строка CONFIG_PACKAGE_zapret=y
# =========================================================
if [ -f ./.config ] && grep -q "^CONFIG_PACKAGE_zapret=y" ./.config; then
    echo ">>> [Zapret] В конфиге включен 'zapret'. Скачиваем исходники..."
    mkdir -p ./package/zapret-openwrt
    git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
else
    echo ">>> [Zapret] Пакет 'zapret' не выбран в конфиге (или закомментирован). Скачивание пропущено."
fi

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление HomeProxy
# Если в фидах нет репозитория 'immortalwrt/luci'
# =========================================================
if ! grep -q "immortalwrt/luci" feeds.conf.default; then
    echo ">>> [HomeProxy] В фидах НЕ найден ImmortalWrt LuCI. Считаем, что это Official OpenWrt."
    echo ">>> [HomeProxy] Добавляем HomeProxy вручную..."
    mkdir -p ./package/luci-app-homeproxy
    git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
else
    echo ">>> [HomeProxy] Обнаружен фид ImmortalWrt LuCI. HomeProxy должен быть встроен."
fi

# =========================================================
# Установка всех фидов (включая только что клонированные пакеты)
./scripts/feeds install -a

# =========================================================
# ЗАМЕНА ПАКЕТОВ НА ВЕРСИИ ИЗ PASSWALL
# =========================================================
PW_FEED_DIR="./feeds/passwall_packages"
PW_PACKAGES="v2ray-geodata chinadns-ng"
if [ -d "$PW_FEED_DIR" ]; then
    echo "======================================================="
    echo ">>> [Passwall] Фид Passwall найден. Начинаем замену пакетов..."
    if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then
        PW_PACKAGES="$PW_PACKAGES xray-plugin v2ray-plugin sing-box geoview tcping"
        echo ">>> [Passwall] Ветка $REPO_BRANCH: $PW_PACKAGES добавлен в список замены."
    else
        echo ">>> [Passwall] Ветка $REPO_BRANCH: $PW_PACKAGES ИСКЛЮЧЕН из замены."
    fi
    echo ">>> [Passwall] Список для обработки: $PW_PACKAGES"
    for PKG in $PW_PACKAGES; do
        STD_PKG_PATH="./package/feeds/packages/$PKG"
        if [ -d "$STD_PKG_PATH" ] && [ -d "$PW_FEED_DIR/$PKG" ]; then
            echo "   > Замена [$PKG]..."
            rm -rf "$STD_PKG_PATH"
            ./scripts/feeds install -p passwall_packages -f "$PKG"
        else
            echo "   . Пропуск [$PKG] (не установлен в системе или нет в Passwall)"
        fi
    done
    echo ">>> [Passwall] Все пакеты обработаны."
    echo "======================================================="
else
    echo ">>> [Passwall] Фид passwall_packages не найден. Замена passwall_packages не требуется."
fi

# =========================================================
# ОЧИСТКА ОТ ТЯЖЕЛЫХ GNU УТИЛИТ (Coreutils и др.)
# Экономит место, ускоряет сборку, предотвращает ошибки
# =========================================================
if [[ "$CURRENT_MATRIX_TARGET" == "slateax" ]] || [[ "$CURRENT_MATRIX_TARGET" == "ax59u" ]]; then
echo ">>> [Heavy packages] Отключаем ненужные тяжелые пакеты (GNU utils)..."
# Список пакетов для удаления (оставляем только BusyBox аналоги)
REMOVE_LIST=(
    # Основной пакет coreutils
    "coreutils" 
    # Отдельные утилиты
    "coreutils-base64" "coreutils-cat" "coreutils-chmod" "coreutils-chown"
    "coreutils-cp" "coreutils-cut" "coreutils-date" "coreutils-df"
    "coreutils-du" "coreutils-expand" "coreutils-head" "coreutils-ls"
    "coreutils-md5sum" "coreutils-mkdir" "coreutils-mv" "coreutils-nohup"
    "coreutils-numfmt" "coreutils-paste" "coreutils-rm" "coreutils-sha256sum"
    "coreutils-sleep" "coreutils-sort" "coreutils-stat" "coreutils-strings"
    "coreutils-tail" "coreutils-timeout" "coreutils-touch" "coreutils-tr"
    "coreutils-unexpand" "coreutils-uniq" "coreutils-wc"
    # Другие тяжелые утилиты (уже есть в BusyBox)
    "grep" "sed" "gawk" "tar" "gzip" "unzip" "bzip2"
    "findutils" "findutils-find" "findutils-locate" "findutils-xargs"
    "diffutils"
    # Управление пользователями (не нужно для роутера)
    "shadow-groupadd" "shadow-useradd"
)
for PKG in "${REMOVE_LIST[@]}"; do
    # 1. Удаляем строку включения (если она есть)
    sed -i "/CONFIG_PACKAGE_${PKG}=y/d" ./.config
    # 2. Явно прописываем отключение
    # echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
done
# Приоритет встроенных applets над внешними программами
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_PREFER_APPLETS=y' >> ./.config
# Встроенные команды shell для максимальной производительности
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_ECHO=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_PRINTF=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_TEST=y' >> ./.config
# Дополнительные оптимизации
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_FAST_TOP=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_USE_INITTAB=y' >> ./.config
echo ">>> [Heavy packages] Тяжелые пакеты отключены."
        # Для 'minimal' ставим Tiny версию sing-box.
        if [ "$VARIANT" == "minimal" ]; then
            echo ">>> [Heavy packages] Sing-box Tiny for $VARIANT compatibility..."
            sed -i '/sing-box/Id' ./.config
            echo '# CONFIG_PACKAGE_sing-box is not set' >> ./.config
            echo 'CONFIG_PACKAGE_sing-box-tiny=y' >> ./.config
            # Удаляем скачанный в YML "жирный" бинарник из files/
            if [ -f "files/usr/bin/sing-box" ]; then
                echo ">>> [Heavy packages] Удаляем скачанный в YML sing-box."
                rm -f files/usr/bin/sing-box
            fi
        fi
fi

# =========================================================
# СПЕЦИАЛЬНАЯ ЛОГИКА ДЛЯ MIKROTIK RB5009
# =========================================================
if [ "$CURRENT_MATRIX_TARGET" == "mt-rb5009" ]; then
    echo ">>> [Mikrotik] Target RB5009 detected. Full Aggressive Cleanup..."

    # 1. Удаляем скрипт автонастройки и ВСЕ скачанные бинарники
    # Это самое важное, так как бинарники весят больше всего
    rm -f "./files/etc/uci-defaults/zz1-final-offline-setup.sh"
    rm -f "./files/usr/bin/sing-box"
    rm -f "./files/usr/bin/AdGuardHome"
    echo "   > Removed zz1-setup, sing-box and AdGuardHome from files"

    # 2. Список пакетов для полной зачистки из .config
    # Добавляем adguardhome в список
    PACKAGES_TO_REMOVE=(
        "adguardhome" "homeproxy" "sing-box" "youtubeUnblock" "zapret" 
        "xray-core" "v2ray-plugin" "xray-plugin"
        "v2ray-geoip" "v2ray-geosite" "v2ray-geodata" 
        "chinadns-ng" "geoview"
    )
    
    for PKG in "${PACKAGES_TO_REMOVE[@]}"; do
        # Удаляем любые строки, где упоминается пакет (регистронезависимо)
        sed -i "/${PKG}/Id" ./.config
        
        # Жестко прописываем отключение, чтобы зависимости не подтянули их обратно
        echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
        echo "# CONFIG_PACKAGE_kmod-${PKG} is not set" >> ./.config
    done
    
    # 3. Чистим остатки конфигурации AdGuardHome, если они были в WRT.config
    sed -i '/adguardhome/Id' ./.config

    echo ">>> [Mikrotik] RB5009 is now CLEAN. No proxy, no AGH."
fi

# =========================================================
# ФИКСЫ ЗАВИСИМОСТЕЙ (В самом конце!)
# =========================================================
# Удаляем зависимость +sing-box из Makefile.
# Это позволяет нам ставить любую версию (Full или Tiny) через .config без ошибок рекурсии.
echo ">>> [HomeProxy] Удаляем зависимость sing-box, так как он уже включен в /config/WRT.config"
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box //g'
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box//g'
echo ">>> [HomeProxy] Makefile patched to fix recursion dependency."

# =========================================================
# Настройка сети и часового пояса
sed -i "s/192.168.1.1/192.168.2.1/g" ./package/base-files/files/bin/config_generate
sed -i "s#zonename='UTC'#zonename='Europe/Moscow'#g" ./package/base-files/files/bin/config_generate
sed -i "s#timezone='GMT0'#timezone='MSK-3'#g" ./package/base-files/files/bin/config_generate
# =========================================================

echo ">>>>>>>>> WRT-part3 end"
