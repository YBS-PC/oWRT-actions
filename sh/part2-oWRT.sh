#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
#
mkdir ./package/homeproxy
mkdir ./package/logviewer
git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/homeproxy/
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/logviewer/
./scripts/feeds install -a
