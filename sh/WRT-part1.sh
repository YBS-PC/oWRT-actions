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
# echo "src-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >>feeds.conf.default
# echo 'src-git kiddin9 https://github.com/kiddin9/openwrt-packages' >> feeds.conf.default
# echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default
# echo 'src-git smoothwan https://github.com/SmoothWAN/SmoothWAN-feeds' >> feeds.conf.default
#
echo -e "\nsrc-git youtubeUnblock https://github.com/Waujito/youtubeUnblock.git;openwrt" >> feeds.conf.default
echo -e "\nsrc-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >> feeds.conf.default
echo -e "\nsrc-git internetdetector https://github.com/gSpotx2f/luci-app-internet-detector.git" >> feeds.conf.default
#echo -e "\nsrc-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git;main" >> feeds.conf.default
#echo "src-git logviewer https://github.com/gSpotx2f/luci-app-log.git" >> feeds.conf.default
#echo "src-git logviewer https://github.com/fantastic-packages/packages/blob/master/feeds/luci/luci-app-log-viewer" >> feeds.conf.default
#echo "src-git fantastic https://github.com/fantastic-packages/fantastic-packages-feeds.git" >> feeds.conf.default
#echo "src-git logviewer https://github.com/fantastic-packages/packages.git;feeds/luci/luci-app-log-viewer" >> feeds.conf.default
#echo "src-git logviewer https://github.com/gSpotx2f/luci-app-log.git" >> feeds.conf.default
#echo "src-git mihomo https://github.com/morytyann/OpenWrt-mihomo.git;main" >> feeds.conf.default
#echo "src-git luciappxray https://github.com/yichya/luci-app-xray.git" >> feeds.conf.default
#echo "src-git argon https://github.com/jerrykuku/luci-theme-argon.git" >> feeds.conf.default
#echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" >> feeds.conf.default
#echo -e "\nsrc-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git" >> feeds.conf.default
#echo -e "\nsrc-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default
