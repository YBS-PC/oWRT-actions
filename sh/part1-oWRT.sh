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
echo -e "\nsrc-git youtubeUnblock https://github.com/Waujito/youtubeUnblock.git;openwrt" >> feeds.conf.default
echo -e "\nsrc-git internetdetector https://github.com/gSpotx2f/luci-app-internet-detector.git" >> feeds.conf.default
#echo "src-git mihomo https://github.com/morytyann/OpenWrt-mihomo.git;main" >> feeds.conf.default
#echo "src-git luciappxray https://github.com/yichya/luci-app-xray.git" >> feeds.conf.default
#echo "src-git argon https://github.com/jerrykuku/luci-theme-argon.git" >> feeds.conf.default
#echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" >> feeds.conf.default
#echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default
#echo "src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git" >> feeds.conf.default
