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
mkdir -p ./package/facinstall

# Клонируем общие пакеты
git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/

# =========================================================
# УСЛОВНЫЙ БЛОК: Только для официального OpenWrt
# Проверяем, содержит ли REPO_URL строку "git.openwrt.org"
# =========================================================
if [[ "$REPO_URL" == *"git.openwrt.org"* ]]; then
    echo ">>> Обнаружена сборка Official OpenWrt. Добавляем HomeProxy..."
    mkdir -p ./package/luci-app-homeproxy
    git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
else
    echo ">>> Сборка ImmortalWrt (или другая). HomeProxy пропускаем (он обычно встроен)."
fi

# =========================================================
# Установка всех фидов (включая только что клонированные пакеты)
./scripts/feeds install -a

# =========================================================
# ЗАМЕНА XRAY-CORE НА ВЕРСИЮ ИЗ PASSWALL
# Выполняется ПОСЛЕ install -a, чтобы перезаписать стандартный пакет
# =========================================================
if ./scripts/feeds list -s | grep -q "passwall_packages"; then
    echo "======================================================="
    echo ">>> Фид passwall_packages найден. Заменяем xray-core..."
    
    # 1. Удаляем стандартные пакеты (чтобы разорвать симлинки)
    rm -rf ./package/feeds/packages/xray-core
    rm -rf ./package/feeds/packages/xray-plugin
    
    # 2. Принудительно (-f) устанавливаем версию из Passwall (Xiaorouji)
    ./scripts/feeds install -p passwall_packages -f xray-core
    ./scripts/feeds install -p passwall_packages -f xray-plugin
    
    echo ">>> xray-core успешно заменен на версию от Xiaorouji."
    echo "======================================================="
else
    echo ">>> Фид passwall_packages НЕ найден. Оставлен стандартный xray-core."
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
