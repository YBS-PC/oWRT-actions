#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
#
mkdir ./package/luci-app-homeproxy
mkdir ./package/luci-app-log-viewer
mkdir ./package/zapret-openwrt
mkdir ./package/facinstall
git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
./scripts/feeds install -a

# Исправление прав для всех uci-defaults файлов
find . -path "*/etc/uci-defaults/*" -type f -exec chmod +x {} \; 2>/dev/null || true
echo ">>> uci-defaults permissions fixed"
