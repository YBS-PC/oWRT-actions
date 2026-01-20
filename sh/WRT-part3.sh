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
##    # Удаляем все существующие строки для этого пакета (с любым значением) sed -i -e "/CONFIG_PACKAGE_.*${pkg}/Id" -e "/CONFIG_.*${pkg}/Id" ./.config
##    sed -i "/CONFIG_${pkg}/Id" ./.config
##    sed -i "/CONFIG_PACKAGE_${pkg}/Id" ./.config
##done
####################################################################
##echo ">>> Adding packages with =n..."
# Список пакетов, которые нужно добавить с элементом =n
# 
##ADDnLIST=(
##    bind
##    automount
##    bridger
##)
##
##for pkg in "${ADDnLIST[@]}"; do
##    # Добавляем новую строку, которая явно отключает пакет
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
        PW_PACKAGES="$PW_PACKAGES xray-core xray-plugin v2ray-plugin sing-box geoview tcping"
        echo ">>> [Passwall] Ветка $REPO_BRANCH: xray-core xray-plugin v2ray-plugin sing-box geoview tcping добавлен в список замены."
    else
        echo ">>> [Passwall] Ветка $REPO_BRANCH: xray-core xray-plugin v2ray-plugin sing-box geoview tcping ИСКЛЮЧЕН из замены."
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
echo ">>> [Heavy packages] Тяжелые пакеты отключены."
fi

# =========================================================
# Настройка сети и часового пояса
sed -i "s/192.168.1.1/192.168.2.1/g" ./package/base-files/files/bin/config_generate
sed -i "s#zonename='UTC'#zonename='Europe/Moscow'#g" ./package/base-files/files/bin/config_generate
sed -i "s#timezone='GMT0'#timezone='MSK-3'#g" ./package/base-files/files/bin/config_generate
# =========================================================

#mkdir ./package/custom
#git clone https://github.com/sbwml/autocore-arm.git ./package/custom/
#./scripts/feeds install -a
#
#echo ">>> Setting default timezone to Europe/Moscow (MSK-3)"
#CONFIG_GEN_SCRIPT="./package/base-files/files/bin/config_generate"
#if [ -f "$CONFIG_GEN_SCRIPT" ]; then
#    sed -i "s#zonename='UTC'#zonename='Europe/Moscow'#g" "$CONFIG_GEN_SCRIPT"
#    sed -i "s#timezone='GMT0'#timezone='MSK-3'#g" "$CONFIG_GEN_SCRIPT"
#else
#    echo ">>> Timezone not set at compile time."
#fi
echo ">>>>>>>>> WRT-part3 end"
