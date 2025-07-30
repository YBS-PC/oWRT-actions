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
mkdir ./package/luci-app-log-viewer
mkdir ./package/zapret-openwrt
mkdir ./package/facinstall
git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
./scripts/feeds install -a

#
#sed -i 's/192.168.1.1/10.10.0.1/g' ./package/base-files/files/bin/config_generate
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
