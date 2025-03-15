#!/bin/bash

#sed -i 's/192.168.1.1/10.10.0.1/g' ./package/base-files/files/bin/config_generate
#mkdir ./package/custom
#git clone https://github.com/sbwml/autocore-arm.git ./package/custom/
#./scripts/feeds install -a
git clone -b master https://github.com/immortalwrt/homeproxy.git ./feeds/luci/applications/luci-app-homeproxy/
mkdir ./package/luci-app-log-viewer
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/
./scripts/feeds install -a
