#!/bin/bash
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
mkdir -p ./package/zapret-openwrt

# Клонируем общие пакеты
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/

if [ "$CURRENT_MATRIX_TARGET" == "ax59u" ]; then
    mkdir -p ./package/facinstall
    git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
else
    echo "=========================================="
fi

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление HomeProxy
# Логика: Если в фидах нет репозитория 'immortalwrt/luci',
# значит HomeProxy там нет (это Official OpenWrt или старый коммит),
# и его нужно скачать вручную.
# =========================================================

# Проверяем файл feeds.conf.default на наличие строки "immortalwrt/luci"
if ! grep -q "immortalwrt/luci" feeds.conf.default; then
    echo ">>> В фидах НЕ найден ImmortalWrt LuCI. Считаем, что это Official OpenWrt."
    echo ">>> Добавляем HomeProxy вручную..."
    
    mkdir -p ./package/luci-app-homeproxy
    git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
else
    echo ">>> Обнаружен фид ImmortalWrt LuCI. HomeProxy должен быть встроен."
fi

# =========================================================
# Установка всех фидов (включая только что клонированные пакеты)
./scripts/feeds install -a

# =========================================================
# ЗАМЕНА ПАКЕТОВ НА ВЕРСИИ ИЗ PASSWALL
# =========================================================
# 1. Формируем базовый список пакетов для замены
PW_PACKAGES="v2ray-geodata chinadns-ng"

# 2. Добавляем проблемные пакеты ТОЛЬКО для ветки Master/Main (например geoview)
if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then
    PW_PACKAGES="$PW_PACKAGES xray-core xray-plugin v2ray-plugin sing-box geoview tcping"
    echo ">>> Ветка $REPO_BRANCH: geoview добавлен в список замены."
else
    echo ">>> Ветка $REPO_BRANCH: geoview ИСКЛЮЧЕН из замены (требует Go 1.24+)."
fi

# Путь к исходникам Passwall
PW_FEED_DIR="./feeds/passwall_packages"

if [ -d "$PW_FEED_DIR" ]; then
    echo "======================================================="
    echo ">>> Фид Passwall найден. Начинаем замену пакетов..."
    echo ">>> Список для обработки: $PW_PACKAGES"

    for PKG in $PW_PACKAGES; do
        # Путь, куда установился стандартный пакет (ссылка)
        STD_PKG_PATH="./package/feeds/packages/$PKG"
        
        # Проверяем:
        # 1. Установлен ли стандартный пакет (есть ли папка в package/...)
        # 2. Существует ли такой пакет в фиде Passwall (есть ли исходник)
        if [ -d "$STD_PKG_PATH" ] && [ -d "$PW_FEED_DIR/$PKG" ]; then
            echo "   > Замена [$PKG]..."
            
            # 1. Удаляем стандартную ссылку
            rm -rf "$STD_PKG_PATH"
            
            # 2. Устанавливаем версию из Passwall
            ./scripts/feeds install -p passwall_packages -f "$PKG"
        else
            echo "   . Пропуск [$PKG] (не установлен в системе или нет в Passwall)"
        fi
    done
    
    echo ">>> Все пакеты обработаны."
    echo "======================================================="
else
    echo ">>> ВНИМАНИЕ: Фид passwall_packages не найден. Замена отменена."
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
