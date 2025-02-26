#!/bin/bash

# Удаляем ненужные mt2500 строки
sed -i '/CONFIG_TARGET/d' openwrt/.config
sed -i '/fdisk/d' openwrt/.config
sed -i '/kmod-r8125/d' openwrt/.config
sed -i '/kmod-r8169/d' openwrt/.config
sed -i '/partx-utils/d' openwrt/.config
sed -i '/fitblk/d' openwrt/.config
sed -i '/kmod-crypto-hw-safexcel/d' openwrt/.config
sed -i '/mt76/d' openwrt/.config
# Добавляем необходимые mt2500 строки
echo 'CONFIG_TARGET_mediatek=y' >> openwrt/.config
echo 'CONFIG_TARGET_mediatek_filogic=y' >> openwrt/.config
echo 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt2500=y' >> openwrt/.config
echo 'CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"' >> openwrt/.config
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=512' >> openwrt/.config
echo 'CONFIG_PACKAGE_bridger=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_fitblk=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_kmod-crypto-hw-safexcel=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_kmod-usb3=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_eip197-mini-firmware=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_kmod-mt7981-firmware=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_mt7981-wo-firmware=y' >> openwrt/.config
echo 'CONFIG_PACKAGE_kmod-mt76=m' >> openwrt/.config
