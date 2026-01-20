#!/bin/bash

echo ">>>>>>>>> WRT-part1 start"
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>

# This is free software, licensed under the MIT License.
# See /LICENSE for more information.

# https://github.com/P3TERX/Actions-OpenWrt
# Description: OpenWrt DIY script part 1 (Before Update feeds)

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
# rm -rf feeds.conf.default
# touch feeds.conf.default

# =========================================================
echo -e "\nsrc-git youtubeUnblock https://github.com/Waujito/youtubeUnblock.git;openwrt" >> feeds.conf.default
echo -e "\nsrc-git internetdetector https://github.com/gSpotx2f/luci-app-internet-detector.git" >> feeds.conf.default
# =========================================================

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление репозиториев
# =========================================================
if [ "$CURRENT_MATRIX_TARGET" == "slateax" ]; then
    echo -e "\nsrc-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >> feeds.conf.default
    echo ">>> [Feeds] Устройство slateax - fancontrol git добавлен"
else
    echo ">>> [Feeds] Устройство не slateax - fancontrol git отключен"
fi
# =========================================================
echo ">>>>>>>>> WRT-part1 end"
