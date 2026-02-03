#!/bin/bash

echo ">>>>>>>>> WRT-part3 start. Использование: до make defconfig"
####################################################################
##echo ">>> Force-disabling unwanted packages..."
# Список пакетов, которые нужно принудительно отключить. Например:
# apk-mbedtls libmbedtls libwolfssl libustream-mbedtls wpad-basic-mbedtls mbedtls-util
# autocore automount block-mount bridger cpufreq luci-app-cpufreq default-settings-chn 
##DELLIST=(
##    bind
##    automount
##    bridger
##)
##
##for pkg in "${DELLIST[@]}"; do
##    # Удаляем все существующие строки для этого пакета (с любым значением) и добавляем с =n
##    sed -i "/CONFIG_${pkg}/Id" ./.config
##    sed -i "/CONFIG_PACKAGE_${pkg}/Id" ./.config
##    echo "CONFIG_PACKAGE_${pkg}=n" >> ./.config
##done
####################################################################

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление пакетов из их репозиториев
# =========================================================
# Создаем общие папки (флаг -p чтобы не было ошибок если папка уже есть)
mkdir -p ./package/luci-app-log-viewer

# Клонируем общие пакеты
git clone -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/

# =========================================================
# УСЛОВНАЯ УСТАНОВКА facinstall
# Выполняется только если ax59u
# =========================================================
if [ "$CURRENT_MATRIX_TARGET" == "ax59u" ]; then
    mkdir -p ./package/facinstall
    git clone -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
    echo ">>> [Git] Устройство ax59u - исходники facinstall добавлены"
else
    echo ">>> [Git] Устройство не ax59u - исходники facinstall не добавлены"
fi

# =========================================================
# УСЛОВНАЯ УСТАНОВКА ZAPRET
# Выполняется только если в .config есть строка CONFIG_PACKAGE_zapret=y
# =========================================================
if [ -f ./.config ] && grep -q "^CONFIG_PACKAGE_zapret=y" ./.config; then
    echo ">>> [Zapret] В конфиге включен 'zapret'. Скачиваем исходники..."
    mkdir -p ./package/zapret-openwrt
    git clone -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
else
    echo ">>> [Zapret] Пакет 'zapret' не выбран в конфиге (или закомментирован). Скачивание пропущено."
fi

# =========================================================
# УСЛОВНЫЙ БЛОК: Добавление HomeProxy
# Если в фидах нет репозитория 'immortalwrt/luci'
# =========================================================
if ! grep -q "immortalwrt/luci" feeds.conf.default; then
    echo ">>> [HomeProxy] В фидах НЕ найден ImmortalWrt LuCI. Считаем, что это Official OpenWrt."
    echo ">>> [HomeProxy] Добавляем HomeProxy вручную..."
    mkdir -p ./package/luci-app-homeproxy
    git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
else
    echo ">>> [HomeProxy] Обнаружен фид ImmortalWrt LuCI. HomeProxy должен быть встроен."
fi

# =========================================================
# Установка всех фидов (включая только что клонированные пакеты)
./scripts/feeds install -a

# =========================================================
# ЗАМЕНА ПАКЕТОВ НА ВЕРСИИ ИЗ PASSWALL
# =========================================================
PW_FEED_DIR="./feeds/passwall_packages"
PW_PACKAGES="v2ray-geodata chinadns-ng"
if [ -d "$PW_FEED_DIR" ]; then
    echo "======================================================="
    echo ">>> [Passwall] Фид Passwall найден. Начинаем замену пакетов..."
    if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then
        PW_PACKAGES="$PW_PACKAGES xray-plugin v2ray-plugin sing-box geoview tcping"
        echo ">>> [Passwall] Ветка $REPO_BRANCH: $PW_PACKAGES добавлен в список замены."
    else
        echo ">>> [Passwall] Ветка $REPO_BRANCH: $PW_PACKAGES ИСКЛЮЧЕН из замены."
    fi
    echo ">>> [Passwall] Список для обработки: $PW_PACKAGES"
    for PKG in $PW_PACKAGES; do
        STD_PKG_PATH="./package/feeds/packages/$PKG"
        if [ -d "$STD_PKG_PATH" ] && [ -d "$PW_FEED_DIR/$PKG" ]; then
            echo "   > Замена [$PKG]..."
            rm -rf "$STD_PKG_PATH"
            ./scripts/feeds install -p passwall_packages -f "$PKG"
        else
            echo "   . Пропуск [$PKG] (не установлен в системе или нет в Passwall)"
        fi
    done
    echo ">>> [Passwall] Все пакеты обработаны."
    echo "======================================================="
else
    echo ">>> [Passwall] Фид passwall_packages не найден. Замена passwall_packages не требуется."
fi

# =========================================================
# ОЧИСТКА ОТ ТЯЖЕЛЫХ GNU УТИЛИТ (Coreutils и др.)
# Экономит место, ускоряет сборку, предотвращает ошибки
# =========================================================
if [[ "$CURRENT_MATRIX_TARGET" == "slateax" ]] || [[ "$CURRENT_MATRIX_TARGET" == "ax59u" ]]; then
echo ">>> [Heavy packages] Отключаем ненужные тяжелые пакеты (GNU utils)..."
# Список пакетов для удаления (оставляем только BusyBox аналоги)
REMOVE_LIST=(
    # Основной пакет coreutils
    "coreutils" 
    # Отдельные утилиты
    "coreutils-base64" "coreutils-cat" "coreutils-chmod" "coreutils-chown"
    "coreutils-cp" "coreutils-cut" "coreutils-date" "coreutils-df"
    "coreutils-du" "coreutils-expand" "coreutils-head" "coreutils-ls"
    "coreutils-md5sum" "coreutils-mkdir" "coreutils-mv" "coreutils-nohup"
    "coreutils-numfmt" "coreutils-paste" "coreutils-rm" "coreutils-sha256sum"
    "coreutils-sleep" "coreutils-sort" "coreutils-stat" "coreutils-strings"
    "coreutils-tail" "coreutils-timeout" "coreutils-touch" "coreutils-tr"
    "coreutils-unexpand" "coreutils-uniq" "coreutils-wc"
    # Другие тяжелые утилиты (уже есть в BusyBox)
    "grep" "sed" "gawk" "tar" "gzip" "unzip" "bzip2"
    "findutils" "findutils-find" "findutils-locate" "findutils-xargs"
    "diffutils"
    # Управление пользователями (не нужно для роутера)
    "shadow-groupadd" "shadow-useradd"
)
for PKG in "${REMOVE_LIST[@]}"; do
    # 1. Удаляем строку включения (если она есть)
    sed -i "/CONFIG_PACKAGE_${PKG}=y/d" ./.config
    # 2. Явно прописываем отключение
    # echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
done
# Приоритет встроенных applets над внешними программами
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_PREFER_APPLETS=y' >> ./.config
# Встроенные команды shell для максимальной производительности
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_ECHO=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_PRINTF=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_ASH_BUILTIN_TEST=y' >> ./.config
# Дополнительные оптимизации
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_FAST_TOP=y' >> ./.config
echo 'CONFIG_BUSYBOX_DEFAULT_FEATURE_USE_INITTAB=y' >> ./.config
echo ">>> [Heavy packages] Тяжелые пакеты отключены."
        # Для standart и minimal ставим Tiny версию sing-box.
        if [[ "$VARIANT" == "standart" || "$VARIANT" == "minimal" ]]; then
            echo ">>> [Heavy packages] Sing-box Tiny for $VARIANT compatibility..."
            sed -i '/sing-box/Id' ./.config
            echo '# CONFIG_PACKAGE_sing-box is not set' >> ./.config
            echo 'CONFIG_PACKAGE_sing-box-tiny=y' >> ./.config
            # Удаляем скачанный в YML "жирный" бинарник из files/
            if [ -f "files/usr/bin/sing-box" ]; then
                echo ">>> [Heavy packages] Удаляем скачанный в YML sing-box."
                rm -f files/usr/bin/sing-box
            fi
        fi
fi

# =========================================================
# ЦЕНТРАЛИЗОВАННАЯ ОЧИСТКА (Варианты minimal, clear и crystal_clear)
# =========================================================

# Списки "Прокси-мусора" (для варианта clear и crystal_clear)

MINIMAL_BLOAT=(
"luci-app-sqm"
"sqm"
"sqm-scripts"
)

CLEAR_BLOAT=(
"homeproxy"
"sing-box"
"youtubeUnblock"
"adguardhome"
)

CRYSTAL_CLEAR_BLOAT=(
# "${CLEAR_BLOAT[@]}"
# СПИСОК ПАКЕТОВ НА УДАЛЕНИЕ для задачи "чистый L2 switch"
## 1. VPN, PROXY, DNS ФИЛЬТРАЦИЯ
"adguardhome"
"sing-box"
"youtubeUnblock"
"luci-app-homeproxy"
"luci-app-youtubeUnblock"
## 2. ВСЕ COREUTILS (заменяются busybox)
"coreutils-base64"
"coreutils-cat"
"coreutils-chmod"
"coreutils-chown"
"coreutils-cp"
"coreutils-cut"
"coreutils-date"
"coreutils-df"
"coreutils-du"
"coreutils-expand"
"coreutils-head"
"coreutils-ls"
"coreutils-md5sum"
"coreutils-mkdir"
"coreutils-mv"
"coreutils-nohup"
"coreutils-numfmt"
"coreutils-paste"
"coreutils-rm"
"coreutils-sha256sum"
"coreutils-sleep"
"coreutils-sort"
"coreutils-stat"
"coreutils-strings"
"coreutils-tail"
"coreutils-timeout"
"coreutils-touch"
"coreutils-tr"
"coreutils-unexpand"
"coreutils-uniq"
"coreutils-wc"
"coreutils"
## 3. FINDUTILS (заменяются busybox)
"findutils-find"
"findutils-locate"
"findutils-xargs"
"findutils"
## 4. АРХИВАТОРЫ (заменяются busybox)
"bsdtar"
"gzip"
"xz-utils"
"xz"
"unzip"
## 5. ФАЙЛОВЫЕ СИСТЕМЫ (если не используете USB накопители)
"kmod-fs-exfat"
"kmod-fs-ext4"
"kmod-fs-f2fs"
"kmod-fs-ntfs3"
"kmod-fs-vfat"
"kmod-nls-base"
"kmod-nls-cp437"
"kmod-nls-iso8859-1"
"kmod-nls-utf8"
## 6. УТИЛИТЫ РАЗМЕТКИ ДИСКОВ
"blkid"
"cfdisk"
"fdisk"
"gdisk"
"lsblk"
"parted"
"libparted"
## 7. USB STORAGE (если не используете USB накопители)
"kmod-usb-storage"
"kmod-usb-storage-extras"
"kmod-usb-storage-uas"
"kmod-scsi-core"
## 8. USB NETWORK АДАПТЕРЫ
"kmod-usb-net"
"kmod-usb-net-asix"
"kmod-usb-net-asix-ax88179"
"kmod-usb-net-cdc-ether"
"kmod-usb-net-rtl8150"
"kmod-usb-net-rtl8152"
"r8152-firmware"
## 9. CRYPTO МОДУЛИ (для VPN, не нужны для L2 switch)
"kmod-crypto-aead"
"kmod-crypto-arc4"
"kmod-crypto-authenc"
"kmod-crypto-crc32"
"kmod-crypto-ctr"
"kmod-crypto-ecb"
"kmod-crypto-gcm"
"kmod-crypto-geniv"
"kmod-crypto-gf128"
"kmod-crypto-ghash"
"kmod-crypto-hmac"
"kmod-crypto-kpp"
"kmod-crypto-manager"
"kmod-crypto-null"
"kmod-crypto-rng"
"kmod-crypto-seqiv"
"kmod-crypto-sha1"
"kmod-crypto-sha256"
"kmod-crypto-sha3"
"kmod-crypto-sha512"
"kmod-crypto-user"
"kmod-cryptodev"
"kmod-asn1-decoder"
## 10. VPN/TUNNEL МОДУЛИ
"kmod-tun"
"kmod-mppe"
"kmod-tls"
## 11. QoS И TRAFFIC SHAPING
"sqm-scripts"
"luci-app-sqm"
"luci-i18n-sqm-ru"
"kmod-sched-cake"
"kmod-ifb"
"tc-full"
"kmod-sched-core"
## 12. NAT HELPERS (не нужны без NAT)
"kmod-nf-nathelper"
"kmod-nf-nathelper-extra"
## 13. IPSET (не нужен без firewall правил)
"ipset"
"libipset13"
"kmod-ipt-ipset"
## 14. ДОПОЛНИТЕЛЬНЫЕ IPTABLES/NFT МОДУЛИ
"iptables-mod-ipopt"
"kmod-ipt-ipopt"
"kmod-nft-fullcone"
"kmod-nft-queue"
"kmod-nfnetlink-queue"
## 15. MACVLAN
"kmod-macvlan"
## 16. SOCKET/TPROXY (не нужно для L2)
"kmod-nf-socket"
"kmod-nf-tproxy"
"kmod-nft-socket"
"kmod-nft-tproxy"
## 17. ДОПОЛНИТЕЛЬНЫЕ LUCI ПРИЛОЖЕНИЯ
"luci-app-internet-detector"
"luci-i18n-internet-detector-ru"
## 18. УТИЛИТЫ (избыточные или ненужные)
"bind-dig"
"dnslookup"
"drill"
"gawk"
"internet-detector"
"mtr-json"
"procps-ng-watch"
"resolveip"
"shadow-groupadd"
"shadow-useradd"
"sysstat"
## 19. PCI/USB УТИЛИТЫ (если не нужна диагностика)
"pciids"
"pciutils"
"usbids"
"usbutils"
## 20. БИБЛИОТЕКИ (зависимости удалённых пакетов)
"libarchive"
"libbz2"
"libelf1"
"libevdev"
"libexpat"
"libfdisk1"
"libgpiod"
"liblzma"
"libmagic"
"libmount1"
"libparted"
"libpcap1"
"libpci"
"libtirpc"
"libudev-zero"
"libusb"
## 21. LUA ДОПОЛНЕНИЯ (не нужны)
"lua-bit32"
"luaposix"
## 22. OPENSSL УТИЛИТЫ (если не используете вручную)
"openssl-util"
## 23. UCODE МОДУЛИ (если не используете)
"ucode-mod-digest"
"ucode-mod-lua"
)

# --- ЛОГИКА ДЛЯ ВАРИАНТА 'minimal' ---
if [ "$VARIANT" == "minimal" ]; then
    echo ">>> [Variant: $VARIANT] Performing cleanup..."
    # Вычищаем пакеты из конфига
    for PKG in "${MINIMAL_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
fi

# --- ЛОГИКА ДЛЯ ВАРИАНТА 'clear' ---
if [ "$VARIANT" == "clear" ]; then
    echo ">>> [Variant: $VARIANT] Performing aggressive cleanup..."
    # Удаляем тяжелые бинарники, которые скачались в YML
    rm -f "./files/usr/bin/sing-box"
    rm -f "./files/usr/bin/AdGuardHome"
    echo "   > Removed Sing-box binaries from files"
    # Вычищаем пакеты из конфига
    for PKG in "${CLEAR_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
    sed -i '/CONFIG_PACKAGE_kmod-tcp-bbr=y/d' ./.config
    sed -i '/CONFIG_TCP_CONG_BBR=y/d' ./.config
    echo "# BBR disabled for clear build"
fi

# --- ЛОГИКА ДЛЯ ВАРИАНТА 'crystal_clear' ---
if [ "$VARIANT" == "crystal_clear" ]; then
    echo ">>> [Variant: $VARIANT] Performing aggressive cleanup..."
    # Удаляем тяжелые бинарники, которые скачались в YML
    rm -f "./files/usr/bin/sing-box"
    rm -f "./files/usr/bin/AdGuardHome"
    echo "   > Removed AdGuardHome and Sing-box binaries from files/"
    # Удаляем основной скрипт настройки
    # rm -f "./files/etc/uci-defaults/zz1-final-offline-setup.sh"
    # Вычищаем пакеты из конфига
    for PKG in "${CRYSTAL_CLEAR_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        # echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
    sed -i '/CONFIG_PACKAGE_kmod-tcp-bbr=y/d' ./.config
    sed -i '/CONFIG_TCP_CONG_BBR=y/d' ./.config
    echo "# BBR disabled for clear build"
fi

# =========================================================
# ФИКСЫ ЗАВИСИМОСТЕЙ (В самом конце!)
# =========================================================
# Удаляем зависимость +sing-box из Makefile.
# Это позволяет нам ставить любую версию (Full или Tiny) через .config без ошибок рекурсии.
echo ">>> [HomeProxy] Удаляем зависимость sing-box, так как он уже включен в /config/WRT.config"
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box //g'
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box//g'
echo ">>> [HomeProxy] Makefile patched to fix recursion dependency."

# =========================================================
# Настройка сети и часового пояса
# sed -i "s/192.168.1.1/192.168.2.1/g" ./package/base-files/files/bin/config_generate
sed -i "s#zonename='UTC'#zonename='Europe/Moscow'#g" ./package/base-files/files/bin/config_generate
sed -i "s#timezone='GMT0'#timezone='MSK-3'#g" ./package/base-files/files/bin/config_generate

# =========================================================
# ЗАПИСЬ ИНФОРМАЦИИ О ВАРИАНТЕ СБОРКИ
# =========================================================
echo ">>> Recording build variant: $VARIANT"
mkdir -p ./files/etc
# Просто сохраняем название варианта в файл.
# Дата тут может быть неправильной из-за среды сборки, поэтому пишем только вариант.
echo "$VARIANT" > ./files/etc/build_variant
echo ">>> Build variant recorded successfully."

# =========================================================
echo ">>>>>>>>> WRT-part3 end"
