#!/bin/bash

echo ">>>>>>>>> WRT-part1 start. Использование: до feeds update"
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
# bandix и bandix-plus: со сборкой с патчами (apply_patches) — с коммита из
# patches/feeds/<фид>/BASE, на котором сняты патчи; без патчей — последний
# коммит автора.
bandix_feed() {   # <фид> <URL>
    local _c=""
    [ "$M_PATCHES" = "true" ] && _c=$(grep -m1 -oE '^[0-9a-f]{40}' "$GITHUB_WORKSPACE/patches/feeds/$1/BASE" 2>/dev/null)
    if [ -n "$_c" ]; then
        echo -e "\nsrc-git $1 $2^$_c" >> feeds.conf.default
        echo ">>> [Feeds] $1: коммит ${_c:0:12} из patches/feeds/$1/BASE"
    else
        echo -e "\nsrc-git $1 $2" >> feeds.conf.default
    fi
}
bandix_feed bandix https://github.com/timsaya/openwrt-bandix.git
bandix_feed luciappbandix https://github.com/timsaya/luci-app-bandix.git
bandix_feed bandixplus https://github.com/timsaya/openwrt-bandix-plus.git
bandix_feed luciappbandixplus https://github.com/timsaya/luci-app-bandix-plus.git
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
