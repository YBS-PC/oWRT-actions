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
git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
./scripts/feeds install -a
