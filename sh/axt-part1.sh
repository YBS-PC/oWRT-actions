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
# echo 'src-git mosdns https://github.com/sbwml/luci-app-mosdns' >> feeds.conf.default
## echo "src-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >>feeds.conf.default
# echo 'src-git kiddin9 https://github.com/kiddin9/openwrt-packages' >> feeds.conf.default
# echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default
# echo 'src-git smoothwan https://github.com/SmoothWAN/SmoothWAN-feeds' >> feeds.conf.default
#
# echo 'src/gz iwrt-base https://downloads.immortalwrt.org/releases/packages-23.05/aarch64_cortex-a53/base' >> feeds.conf.default
# echo 'src/gz iwrt-packages https://downloads.immortalwrt.org/releases/packages-23.05/aarch64_cortex-a53/packages' >> feeds.conf.default
# echo 'src/gz iwrt-luci https://downloads.immortalwrt.org/releases/packages-23.05/aarch64_cortex-a53/luci' >> feeds.conf.default
# echo 'src/gz iwrt-routing https://downloads.immortalwrt.org/releases/packages-23.05/aarch64_cortex-a53/routing' >> feeds.conf.default
# echo 'src/gz iwrt-telephony https://downloads.immortalwrt.org/releases/packages-23.05/aarch64_cortex-a53/telephony' >> feeds.conf.default
# echo 'src/gz fantastic-luci https://fantastic-packages.github.io/packages/releases/23.05/packages/aarch64_cortex-a53/luci' >> feeds.conf.default
# echo 'src/gz fantastic-packages https://fantastic-packages.github.io/packages/releases/23.05/packages/aarch64_cortex-a53/packages' >> feeds.conf.default
# echo "src-git log-viewer https://github.com/gSpotx2f/luci-app-log.git" >>feeds.conf.default
# echo "src-git fantastic-packages https://github.com/fantastic-packages/packages.git" >>feeds.conf.default
# sed -i "s|github.com/immortalwrt|git.openwrt.org/feed|" feeds.conf.default
# echo "src-git iwrt_packages https://github.com/immortalwrt/packages.git" >> feeds.conf.default
# echo "src-git iwrt_luci https://github.com/immortalwrt/luci.git" >> feeds.conf.default
##echo "src-git kiddin9 https://github.com/kiddin9/openwrt-packages" >> feeds.conf.default
echo "src-git youtubeUnblock https://github.com/Waujito/youtubeUnblock.git;openwrt" >> feeds.conf.default
echo "src-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >> feeds.conf.default
##echo "src-git fantastic https://github.com/fantastic-packages/packages.git" >> feeds.conf.default
echo "src-git internetdetector https://github.com/gSpotx2f/luci-app-internet-detector.git" >> feeds.conf.default
#echo "src-git logviewer https://github.com/gSpotx2f/luci-app-log.git" >> feeds.conf.default
#echo "src-git logviewer https://github.com/fantastic-packages/packages/blob/master/feeds/luci/luci-app-log-viewer" >> feeds.conf.default
echo "src-git logviewer https://github.com/fantastic-packages/packages/tree/master/feeds/luci" >> feeds.conf.default
