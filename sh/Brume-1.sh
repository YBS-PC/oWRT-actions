#!/bin/bash

# Удаляем ненужные mt2500 строки
sed -i '/CONFIG_TARGET/d' .config
sed -i '/fdisk/d' .config
sed -i '/kmod-r8125/d' .config
sed -i '/kmod-r8169/d' .config
sed -i '/partx-utils/d' .config
sed -i '/fitblk/d' .config
sed -i '/kmod-crypto-hw-safexcel/d' .config
sed -i '/mt76/d' .config
# Добавляем необходимые mt2500 строки
echo 'CONFIG_TARGET_mediatek=y' >> .config
echo 'CONFIG_TARGET_mediatek_filogic=y' >> .config
echo 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt2500=y' >> .config
echo 'CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"' >> .config
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=512' >> .config
echo 'CONFIG_PACKAGE_bridger=y' >> .config
echo 'CONFIG_PACKAGE_fitblk=y' >> .config
echo 'CONFIG_PACKAGE_kmod-crypto-hw-safexcel=y' >> .config
echo 'CONFIG_PACKAGE_kmod-usb3=y' >> .config
echo 'CONFIG_PACKAGE_eip197-mini-firmware=y' >> .config
echo 'CONFIG_PACKAGE_kmod-mt7981-firmware=y' >> .config
echo 'CONFIG_PACKAGE_mt7981-wo-firmware=y' >> .config
echo 'CONFIG_PACKAGE_kmod-mt76=m' >> .config
