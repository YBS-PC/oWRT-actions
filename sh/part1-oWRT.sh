#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
# rm -rf feeds.conf.default
# touch feeds.conf.default
#
echo "src-git youtubeUnblock https://github.com/Waujito/youtubeUnblock.git;openwrt" >> feeds.conf.default
echo "src-git internetdetector https://github.com/gSpotx2f/luci-app-internet-detector.git" >> feeds.conf.default
# echo "src-git logviewer https://github.com/gSpotx2f/luci-app-log.git" >> feeds.conf.default
echo "src-git chinadns https://github.com/zfl9/chinadns-ng.git" >> feeds.conf.default
# echo "src-git immortalwrt https://github.com/immortalwrt/luci.git" >> feeds.conf.default
# echo "src-git immortalwrt https://github.com/immortalwrt/packages.git" >> feeds.conf.default
echo "src-git homeproxy https://github.com/immortalwrt/homeproxy.git" >> feeds.conf.default
