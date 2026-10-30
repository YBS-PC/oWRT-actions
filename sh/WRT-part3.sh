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
echo ">>> Клонируем тему luci-app-log-viewer..."
# --depth=1: история пакета сборке не нужна (как у темы ниже)
git clone --depth=1 -b master https://github.com/gSpotx2f/luci-app-log.git ./package/luci-app-log-viewer/

echo ">>> Клонируем тему Proton2025..."
git clone --depth=1 https://github.com/ChesterGoodiny/luci-theme-proton2025.git ./package/luci-theme-proton2025/

# =========================================================
# УСЛОВНАЯ УСТАНОВКА facinstall
# Выполняется только если ax59u
# =========================================================
if [ "$CURRENT_MATRIX_TARGET" == "ax59u" ]; then
    mkdir -p ./package/facinstall
    git clone --depth=1 -b main https://github.com/openwrt-xiaomi/facinstall.git ./package/facinstall/
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
    # Ветка по умолчанию у remittor/zapret-openwrt теперь zap1; master
    # остаётся, но новые изменения автор ведёт в zap1 — проверьте, какая
    # нужна, прежде чем включать zapret в WRT.config.
    git clone --depth=1 -b master https://github.com/remittor/zapret-openwrt.git ./package/zapret-openwrt/
else
    echo ">>> [Zapret] Пакет 'zapret' не выбран в конфиге (или закомментирован). Скачивание пропущено."
fi

# checkout_variant_commit <каталог клона> <имя для лога>
# Коммит из patches/packages/<пакет>/BASE (галочка use_base_commit,
# VARIANT_COMMIT, только hex): клон переключается на этот коммит. Нет такого коммита — сборка
# останавливается: молча собрать последний код вместо заказанного нельзя.
checkout_variant_commit() {
    [ -n "$VARIANT_COMMIT" ] || return 0
    if git -C "$1" checkout -q "$VARIANT_COMMIT" 2>/dev/null; then
        echo ">>> [$2] Коммит $(git -C "$1" rev-parse --short HEAD) из BASE ($(git -C "$1" log -1 --format=%cd --date=short))"
    else
        echo "::error title=$2::Коммит $VARIANT_COMMIT (из BASE) не найден в репозитории"
        exit 1
    fi
}

# =========================================================
# УСЛОВНЫЙ БЛОК: HomeProxy из immortalwrt/homeproxy (master)
# На OpenWrt его нет в фидах. В ImmortalWrt LuCI он есть, но в ветках
# релизов (openwrt-25.12, openwrt-24.10) — старый: generate_client.uc ещё
# пишет legacy-поля sniff, которых нет в sing-box 1.13+, и патчи
# patches/packages/luci-app-homeproxy (сняты с master) на него не ложатся.
# Поэтому master ставится и на ImmortalWrt вместо копии из фида: один код,
# одна серия патчей, и сверка с исходниками работает на обеих платформах.
# =========================================================
if [[ "$VARIANT" != "clear" && "$VARIANT" != "crystal_clear" && "$VARIANT" != "switch" && "$VARIANT" != "passwall" && "$VARIANT" != "xray" && "$VARIANT" != "v2raya" && "$VARIANT" != "podkop" && "$VARIANT" != "netshift" && "$VARIANT" != "forkop" && "$VARIANT" != "trafira" && "$VARIANT" != "rehomeproxy" ]]; then
    if ! grep -q "immortalwrt/luci" feeds.conf.default; then
        echo ">>> [HomeProxy] В фидах НЕ найден ImmortalWrt LuCI. Считаем, что это Official OpenWrt."
        echo ">>> [HomeProxy] Добавляем HomeProxy вручную..."
        mkdir -p ./package/luci-app-homeproxy
        git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/
        checkout_variant_commit ./package/luci-app-homeproxy HomeProxy
    else
        echo ">>> [HomeProxy] Обнаружен фид ImmortalWrt LuCI: его копия заменяется на immortalwrt/homeproxy (master), как на OpenWrt."
        mkdir -p ./package/luci-app-homeproxy
        if git clone -b master https://github.com/immortalwrt/homeproxy.git ./package/luci-app-homeproxy/; then
            checkout_variant_commit ./package/luci-app-homeproxy HomeProxy
            # feeds install уже сделал ссылку package/feeds/luci/luci-app-homeproxy:
            # без её удаления пакет был бы в дереве дважды.
            rm -rf ./feeds/luci/applications/luci-app-homeproxy ./package/feeds/luci/luci-app-homeproxy
        else
            rm -rf ./package/luci-app-homeproxy
            if [ -n "$VARIANT_COMMIT" ]; then
                echo "::error title=HomeProxy::Клон immortalwrt/homeproxy не получен, а задан коммит $VARIANT_COMMIT из BASE (use_base_commit)"
                exit 1
            fi
            echo "::warning title=HomeProxy::Клон immortalwrt/homeproxy не получен, остаётся копия из фида ImmortalWrt LuCI: патчи patches/packages/luci-app-homeproxy на неё могут не лечь"
        fi
    fi
fi

# =========================================================
# Re:HomeProxy (вариант rehomeproxy): форк homeproxy от 1andrevich
# (github.com/1andrevich/homeproxy-hiddify), пакет luci-app-re-homeproxy.
# Ставит файлы по тем же путям, что luci-app-homeproxy (/etc/config/homeproxy,
# /etc/init.d/homeproxy ...), поэтому homeproxy в этом варианте вырезается
# (workflow). Ядро — /usr/bin/sing-box из сборки (или hiddify-core /
# sing-box-extended, которые приложение ставит само во вкладке Core & Tools).
# =========================================================
if [ "$VARIANT" == "rehomeproxy" ]; then
    REHP_DIR="./package/luci-app-re-homeproxy"
    echo ">>> [Re:HomeProxy] Клонируем 1andrevich/homeproxy-hiddify..."
    git clone -b master https://github.com/1andrevich/homeproxy-hiddify.git "$REHP_DIR/"
    [ -d "$REHP_DIR/.git" ] && checkout_variant_commit "$REHP_DIR" Re:HomeProxy
    # В Makefile форка PKG_VERSION:=1; его собственные сборки получают версию
    # <дата коммита>-r<число коммитов>. Делаем так же, чтобы версия пакета
    # в прошивке показывала, из какого состояния репозитория он собран.
    if [ -f "$REHP_DIR/Makefile" ]; then
        REHP_VER=$(git -C "$REHP_DIR" log -1 --format=%cd --date=format:%Y.%m.%d 2>/dev/null)
        REHP_REL=$(git -C "$REHP_DIR" rev-list --count HEAD 2>/dev/null)
        if [ -n "$REHP_VER" ] && [ -n "$REHP_REL" ]; then
            sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$REHP_VER/; s/^PKG_RELEASE:=.*/PKG_RELEASE:=$REHP_REL/" "$REHP_DIR/Makefile"
            echo ">>> [Re:HomeProxy] Версия пакета: $REHP_VER-r$REHP_REL ($(git -C "$REHP_DIR" rev-parse --short HEAD))"
        fi
    else
        echo "::warning title=Re:HomeProxy::Клон homeproxy-hiddify не получен, пакета в прошивке не будет"
    fi
fi

# =========================================================
# Патчи пакетов: patches/packages/<пакет>/*.patch
# Для пакетов, которые клонируются в package/ выше (их нет на этапе
# патчей фидов в part2). Каталог пакета ищется в package/<пакет>, затем
# в фидах (ImmortalWrt LuCI держит luci-app-homeproxy в
# feeds/luci/applications/). Пути в патче — от корня репозитория пакета
# (a/htdocs/..., a/root/...). Правила те же, что у patches/feeds:
# уже есть в исходниках — пропуск, не подходит — ::warning и сборка
# дальше (FEED_PATCH_STRICT=1 — остановка).
# Сверка с исходниками (sh/patch-drift.sh) — только для пакетов, которые
# клонированы из репозитория автора в package/: патчи сняты с него
# (luci-app-homeproxy теперь клонируется и на ImmortalWrt, см. выше). Пакет
# из чужого фида — отдельная копия со своей историей, сравнение с эталонами
# давало бы ложные остановки; для него прежнее поведение.
# =========================================================
# shellcheck source=sh/patch-drift.sh
if ! . "$GITHUB_WORKSPACE/sh/patch-drift.sh" 2>/dev/null; then
    echo "::warning::sh/patch-drift.sh не найден — сверка патчей пакетов с исходниками выключена"
    PATCH_DRIFT_CHECK=0
fi

# «Build-If: <ключ>=<значение> ...» в заголовке патча (до первого diff):
# патч только для сборок, где совпадают все значения. Ключи: variant
# (VARIANT), sb (SB_MODE). Например, x01 и x02 у homeproxy — только
# «Build-If: variant=homeproxy sb=extended». Печатает невыполненные условия;
# неизвестный ключ — условие не выполнено (патч не применяется).
# Такие патчи ставятся последними в серии: если они пропущены, у следующих
# патчей не совпал бы «хеш до» (sh/patch-drift.sh). Поэтому их номер
# начинается с буквы (x01, x02): в порядке имён буква идёт после цифр.
patch_build_if() {
    local _c _cur
    for _c in $(sed -n '/^diff --git /q; s/^Build-If:[[:space:]]*//p' "$1"); do
        case "${_c%%=*}" in
            variant) _cur="${VARIANT:-}" ;;
            sb)      _cur="${SB_MODE:-}" ;;
            *)       _cur="" ;;
        esac
        [ "$_cur" = "${_c#*=}" ] || printf '%s ' "$_c"
    done
}

apply_package_patches() {
    local _dir _name _pkg _p _pp _patch _applied _present _failed _failed_names _ok
    local _f _q _tmp _later _still _rev _d _skipf _cond _other
    local -A _drift

    for _dir in "$GITHUB_WORKSPACE"/patches/packages/*/; do
        [ -d "$_dir" ] || continue
        _name=$(basename "$_dir")
        _pkg=""
        if [ -d "package/$_name" ]; then
            _pkg="package/$_name"
        else
            _pkg=$(find feeds -mindepth 2 -maxdepth 3 -type d -name "$_name" 2>/dev/null | head -n 1)
        fi
        if [ -z "$_pkg" ]; then
            echo ">>> Пакет '$_name' не найден, патчи patches/packages/$_name пропущены."
            continue
        fi

        _applied=0; _present=0; _failed=0; _failed_names=""; _ok=" "; _drift=(); _skipf=""; _other=0
        _pp="/tmp/pkgpatch.$$.patch"
        for _p in "$_dir"*.patch; do
            [ -f "$_p" ] || continue
            _patch=$(basename "$_p" .patch)
            sed 's/\r$//' "$_p" > "$_pp"

            _cond=$(patch_build_if "$_pp")
            if [ -n "$_cond" ]; then
                echo "  $_name: $_patch не для этой сборки (нужно: ${_cond% }), пропуск"
                _other=$((_other + 1))
                continue
            fi

            _d=""
            if [ "${PATCH_DRIFT_CHECK:-1}" = "1" ] && [ "$_pkg" = "package/$_name" ]; then
                _d=$(patch_drift "$_pp" "$_pkg" "$_skipf")
            fi
            if patch -p1 -d "$_pkg" -R -F 0 -f -s --dry-run < "$_pp" >/dev/null 2>&1; then
                echo "✓ $_name: $_patch уже есть в исходниках, пропуск"
                _ok="$_ok$_patch "; _present=$((_present + 1))
            elif [ -n "$_d" ]; then
                # Файлы патча изменились у автора — не применяем (см. patch-drift.sh)
                _drift[$_patch]="$_d"
                _skipf="$_skipf$(patch_files "$_pp")
"
                _failed=$((_failed + 1)); _failed_names="$_failed_names $_patch"
            elif patch -p1 -d "$_pkg" -F 0 -f -s --dry-run < "$_pp" >/dev/null 2>&1 &&
                patch -p1 -d "$_pkg" -F 0 -f -s --no-backup-if-mismatch < "$_pp" >/dev/null; then
                echo "✓ $_name: применён $_patch"
                _ok="$_ok$_patch "; _applied=$((_applied + 1))
            else
                # Предупреждение — после уточнения ниже.
                _failed=$((_failed + 1)); _failed_names="$_failed_names $_patch"
            fi
        done
        rm -f "$_pp"

        # Повторная проверка (как в WRT-part2.sh): патч, чьи строки правит
        # более поздний патч (006 рядом с 004), не узнаётся обратным прогоном,
        # даже если автор пакета уже внёс оба. Во временной копии пакета
        # откатываем более поздние найденные/применённые патчи и проверяем
        # его снова. Сам пакет не меняется.
        _still=""; _rev=""
        for _f in $_failed_names; do _rev="$_f $_rev"; done
        for _f in $_rev; do
            _tmp=$(mktemp -d) || break
            tar -C "$_pkg" --exclude=.git -cf - . | tar -C "$_tmp" -xf -
            _later=""
            for _p in "$_dir"*.patch; do
                _q=$(basename "$_p" .patch)
                [[ "$_q" > "$_f" ]] || continue
                case "$_ok" in *" $_q "*) _later="$_q $_later" ;; esac
            done
            for _q in $_later; do
                sed 's/\r$//' "$_dir$_q.patch" | patch -p1 -d "$_tmp" -R -F 0 -f -s --no-backup-if-mismatch >/dev/null 2>&1 || break
            done
            if sed 's/\r$//' "$_dir$_f.patch" | patch -p1 -d "$_tmp" -R -F 0 -f -s --dry-run >/dev/null 2>&1; then
                echo "✓ $_name: $_f уже есть в исходниках (под изменениями более поздних патчей)"
                _ok="$_ok$_f "; _failed=$((_failed - 1)); _present=$((_present + 1))
            else
                _still="$_f $_still"
            fi
            rm -rf "$_tmp"
        done
        for _f in $_still; do
            if [ -n "${_drift[$_f]:-}" ]; then
                patch_drift_record "пакет" "$_name" "$_f" "${_drift[$_f]}"
                continue
            fi
            echo "::warning::$_name: $_f не применяется (код пакета изменился или исправление уже внесено в другом виде), пропущен"
        done
        _failed_names=" $_still"

        echo ">>> $_name ($_pkg): применено $_applied, уже было $_present, пропущено $_failed$([ "$_other" -gt 0 ] && echo ", не для этой сборки $_other")"
        if [ "$_failed" -gt 0 ]; then
            echo "::warning title=Патчи пакета $_name::Не применены:$_failed_names"
            if [ "${FEED_PATCH_STRICT:-0}" = "1" ]; then
                echo "::error::FEED_PATCH_STRICT=1: сборка остановлена из-за непримененных патчей пакета $_name"
                exit 1
            fi
        fi
    done
}

echo "=================================================="
echo "Патчи пакетов (patches/packages/*)"
echo "=================================================="
apply_package_patches

# =========================================================
# Установка всех фидов (включая только что клонированные пакеты)
# Повторная установка фидов для регистрации локально склонированных 
# в ./package/ пакетов и разрешения их скрытых зависимостей.
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
    "bzip2"
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
        # Для сборок с homeproxy и podkop/netshift/forkop/trafira ставим Tiny версию sing-box
        # (если sing-box не отключён полем sb; job setup тогда пишет sb=tiny).
        # forkop 2.x — на своём ядре (sb=forkop-tiny), его ставит блок
        # «ВЫБОР КОМПОНЕНТОВ» ниже.
        if [[ "$VARIANT" == "homeproxy" || "$VARIANT" == "rehomeproxy" || "$VARIANT" == "podkop" || "$VARIANT" == "netshift" || "$VARIANT" == "forkop" || "$VARIANT" == "trafira" ]] && [ "${SB_MODE:-feed}" != "no" ] && [[ "${SB_MODE:-feed}" != forkop-* ]]; then
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
# ЦЕНТРАЛИЗОВАННАЯ ОЧИСТКА (Варианты homeproxy, switch, clear и crystal_clear)
# И добавление индивидуальных пакетов
# =========================================================

# Пакеты SQM. Вырезаются во всех прокси-вариантах (homeproxy, rehomeproxy, podkop,
# netshift, forkop, trafira, xray, passwall, v2raya); SQM остаётся только в clear.
SQM_BLOAT=(
"sqm"
"sqm-scripts"
"luci-app-sqm"
"luci-i18n-sqm-ru"
"kmod-sched-ctinfo"
)

# Свой SQM-скрипт из files/usr/lib/sqm (cake_ctinfo.qos) — без sqm-scripts он не нужен
drop_sqm_files() {
    rm -f ./files/usr/lib/sqm/cake_ctinfo.qos ./files/usr/lib/sqm/cake_ctinfo.qos.help
    rmdir ./files/usr/lib/sqm 2>/dev/null || true
}

CLEAR_BLOAT=(
"adguardhome"
"sing-box"
"homeproxy"
"luci-app-homeproxy"
"youtubeUnblock"
"luci-app-youtubeUnblock"
"avahi-nodbus-daemon"
"libavahi-nodbus-support"
"bandix"
)


CRYSTAL_CLEAR_BLOAT=(
# "${CLEAR_BLOAT[@]}"
# СПИСОК ПАКЕТОВ НА УДАЛЕНИЕ для задачи "чистый L2 switch"
## 1. VPN, PROXY, DNS ФИЛЬТРАЦИЯ
"adguardhome"
"sing-box"
"homeproxy"
"luci-app-homeproxy"
"youtubeUnblock"
"luci-app-youtubeUnblock"
"avahi-nodbus-daemon"
"libavahi-nodbus-support"
"bandix"
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
"xz-utils"
"xz"
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
"sqm"
"sqm-scripts"
"luci-app-sqm"
"luci-i18n-sqm-ru"
"kmod-sched-ctinfo"
"irqbalance"
"luci-app-irqbalance"
"luci-i18n-irqbalance-ru"
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
"internet-detector"
"luci-app-internet-detector"
"luci-i18n-internet-detector-ru"
## 18. УТИЛИТЫ (избыточные или ненужные)
"drill"
"mtr-json"
"procps-ng-watch"
"resolveip"
"shadow-groupadd"
"shadow-useradd"
"sysstat"
# "lm-sensors"
# "sysfsutils"
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

SWITCH_BLOAT=(
"${CRYSTAL_CLEAR_BLOAT[@]}"
)

# --- ЛОГИКА ДЛЯ ПРОКСИ-ВАРИАНТОВ: без SQM ---
# forkop-mod сюда приходит как VARIANT=forkop (setup в workflow), отдельно
# его перечислять не нужно.
if [[ "$VARIANT" == "homeproxy" || "$VARIANT" == "rehomeproxy" || "$VARIANT" == "podkop" || "$VARIANT" == "netshift" || "$VARIANT" == "forkop" || "$VARIANT" == "trafira" || "$VARIANT" == "xray" || "$VARIANT" == "passwall" || "$VARIANT" == "v2raya" ]]; then
    echo ">>> [Variant: $VARIANT] Performing cleanup..."
    # Вычищаем пакеты из конфига. В SQM_BLOAT уже перечислены полные имена
    # (luci-app-sqm, luci-i18n-sqm-ru), поэтому префиксы не добавляем.
    for PKG in "${SQM_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
    drop_sqm_files
fi

# trafira дополнительно без youtubeUnblock (свои Zapret/ByeDPI). forkop-mod
# (ветка 1.x, тоже с Zapret/ByeDPI) сюда приходит как VARIANT=forkop с ytb=false
# от job setup и выключается общим блоком YTB ниже; в forkop 2.x Zapret и ByeDPI
# убраны, youtubeUnblock ему можно.
if [[ "$VARIANT" == "trafira" ]]; then
    sed -i '/youtubeUnblock/Id' ./.config
    echo "# CONFIG_PACKAGE_youtubeUnblock is not set" >> ./.config
    echo "# CONFIG_PACKAGE_luci-app-youtubeUnblock is not set" >> ./.config
    echo "# CONFIG_PACKAGE_luci-i18n-youtubeUnblock-ru is not set" >> ./.config
fi

# --- ЛОГИКА ДЛЯ ВАРИАНТА 'clear' ---
if [ "$VARIANT" == "clear" ]; then
    echo ">>> [Variant: $VARIANT] Performing aggressive cleanup..."
    # Удаляем тяжелые бинарники, которые скачались в YML
    # И добавляем индивидуальные
    # Они вообще не скачиватся согласно условию в yml
    rm -f "./files/usr/bin/sing-box"
    rm -f "./files/usr/bin/AdGuardHome"
    echo "   > Cleaned up binary files (if any were present)"
    # Вычищаем пакеты из конфига
    for PKG in "${CLEAR_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
        # LuCI-обвязку достраиваем только для «голых» имён: для luci-app-homeproxy
        # получилось бы luci-app-luci-app-homeproxy
        case "$PKG" in
            luci-*) ;;
            *)
                echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
                echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
                ;;
        esac
    done
    # echo "CONFIG_PACKAGE_bandix-plus=y" >> ./.config
    # echo "CONFIG_PACKAGE_luci-app-bandix-plus=y" >> ./.config
    # echo "CONFIG_PACKAGE_luci-i18n-bandix-plus-ru=y" >> ./.config
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
    echo "   > Cleaned up binary files (if any were present)"
    # Удаляем тяжелые файлы
    rm -f "./files/root/apps/speedtest.tar.gz"
    # Удаляем основной скрипт настройки
    rm -f "./files/etc/uci-defaults/zz1-final-offline-setup.sh"
    # Вычищаем пакеты из конфига
    for PKG in "${CRYSTAL_CLEAR_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        # echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
    drop_sqm_files
    sed -i '/CONFIG_PACKAGE_kmod-tcp-bbr=y/d' ./.config
    sed -i '/CONFIG_TCP_CONG_BBR=y/d' ./.config
    echo "# BBR disabled for clear build"
fi

# --- ЛОГИКА ДЛЯ ВАРИАНТА 'switch' ---
if [ "$VARIANT" == "switch" ]; then
    echo ">>> [Variant: $VARIANT] Performing aggressive cleanup..."
    # Удаляем тяжелые бинарники, которые скачались в YML
    rm -f "./files/usr/bin/sing-box"
    rm -f "./files/usr/bin/AdGuardHome"
    echo "   > Cleaned up binary files (if any were present)"
    # Удаляем тяжелые файлы
    rm -f "./files/root/apps/speedtest.tar.gz"
    # Удаляем основной скрипт настройки
    # rm -f "./files/etc/uci-defaults/zz1-final-offline-setup.sh"
    # Вычищаем пакеты из конфига
    for PKG in "${SWITCH_BLOAT[@]}"; do
        sed -i "/${PKG}/Id" ./.config
        # echo "# CONFIG_PACKAGE_luci-app-${PKG} is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_luci-i18n-${PKG}-ru is not set" >> ./.config
        # echo "# CONFIG_PACKAGE_${PKG} is not set" >> ./.config
    done
    drop_sqm_files
    sed -i '/CONFIG_PACKAGE_kmod-tcp-bbr=y/d' ./.config
    sed -i '/CONFIG_TCP_CONG_BBR=y/d' ./.config
    echo "# BBR disabled for clear build"
fi

# =========================================================
# ВЫБОР КОМПОНЕНТОВ (поля формы agh / sb / ytb / zz)
# Значения экспортирует workflow, job setup уже согласовал их с вариантом
# (clear/switch и т.п. вырезают своё выше сами). Без переменных — поведение
# по умолчанию: всё ставится, как было до появления этих полей.
# =========================================================
AGH_MODE="${AGH_MODE:-feed}"
SB_MODE="${SB_MODE:-feed}"
YTB="${YTB:-true}"
ZZ="${ZZ:-true}"
echo ">>> [Компоненты] agh=$AGH_MODE sb=$SB_MODE ytb=$YTB zz=$ZZ"

# drop_pkgs <шаблон для sed> <пакет>... — убрать все строки с шаблоном
# (без учёта регистра) и явно выключить перечисленные пакеты
drop_pkgs() {
    local pattern="$1"; shift
    sed -i "/${pattern}/Id" ./.config
    for _pkg in "$@"; do
        echo "# CONFIG_PACKAGE_${_pkg} is not set" >> ./.config
    done
}

if [ "$AGH_MODE" = "no" ]; then
    echo "   > AdGuard Home: убираем из прошивки"
    drop_pkgs adguardhome adguardhome luci-app-adguardhome luci-i18n-adguardhome-ru
    rm -f ./files/usr/bin/AdGuardHome
fi

if [ "$SB_MODE" = "no" ]; then
    echo "   > sing-box: убираем из прошивки"
    drop_pkgs sing-box sing-box sing-box-tiny
    rm -f ./files/usr/bin/sing-box
fi

# sing-box-forkop (sb=forkop-base/full/tiny, только forkop 2.x): пакет из
# релиза уже лежит в package/sing-box-forkop (workflow). Он ставит тот же
# /usr/bin/sing-box и /etc/init.d/sing-box, что sing-box и sing-box-tiny,
# поэтому они выключаются.
case "$SB_MODE" in
forkop-*)
    echo "   > sing-box: sing-box-forkop (${SB_MODE#forkop-}) вместо sing-box"
    drop_pkgs sing-box sing-box sing-box-tiny
    echo 'CONFIG_PACKAGE_sing-box-forkop=y' >> ./.config
    rm -f ./files/usr/bin/sing-box
    ;;
esac

if [ "$YTB" != "true" ]; then
    echo "   > youtubeUnblock: убираем из прошивки"
    drop_pkgs youtubeUnblock youtubeUnblock luci-app-youtubeUnblock luci-i18n-youtubeUnblock-ru
fi

if [ "$ZZ" != "true" ]; then
    echo "   > zz1: скрипт первой настройки не кладём"
    rm -f ./files/etc/uci-defaults/zz1-final-offline-setup.sh
    # speedtest ставит только zz1 — без него архив бесполезен
    rm -f ./files/root/apps/speedtest.tar.gz
fi

# =========================================================
# ФИКСЫ ЗАВИСИМОСТЕЙ (В самом конце!)
# =========================================================
# Удаляем зависимость +sing-box из Makefile.
# Это позволяет нам ставить любую версию (Full или Tiny) через .config без ошибок рекурсии.
echo ">>> [HomeProxy] Удаляем зависимость sing-box, так как он уже включен в /config/WRT.config для вариантов, где он используется"
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box //g'
find package/ feeds/ -name Makefile 2>/dev/null | grep "luci-app-homeproxy" | xargs -r sed -i 's/+sing-box//g'
echo ">>> [HomeProxy] Makefile patched to fix recursion dependency."

# forkop 2.x зависит от ip-tiny, а в WRT.config включён ip-full. В apk оба
# пакета дают ip=<версия> и конфликтуют: сборка доходила до установки пакетов
# в образ и падала на «unable to select packages: ip-tiny ... conflicts:
# ip-full». forkop нужна только команда ip, ip-full умеет всё то же, поэтому
# зависимость меняется на него (forkop-mod и trafira и так зависят от ip-full).
if grep -q '^CONFIG_PACKAGE_ip-full=y' ./.config; then
    for FK_MK in feeds/forkop*/forkop/Makefile; do
        [ -f "$FK_MK" ] && grep -q '+ip-tiny' "$FK_MK" || continue
        sed -i 's/+ip-tiny\([[:space:]]\|$\)/+ip-full\1/' "$FK_MK"
        if grep -q '+ip-tiny' "$FK_MK"; then
            echo "::warning title=forkop::$FK_MK: не удалось заменить +ip-tiny на +ip-full, образ не соберётся из-за конфликта ip-tiny и ip-full"
        else
            echo ">>> [forkop] $FK_MK: +ip-tiny -> +ip-full (с ip-full из WRT.config ip-tiny конфликтует)"
        fi
    done
fi

# sing-box фида ImmortalWrt (master, с 1.14.3) включает NaiveProxy без
# вопроса (def_bool y) и тянет libcronet: сборку сетевого стека Chromium
# (clang и PGO-профиль с серверов Google, gn, ninja) — часы сборки и
# гигабайты на диске. В прошивку и так кладётся свой бинарник sing-box,
# поэтому NaiveProxy в пакете фида выключаем. Тонкой версии это не
# касается: там пункт с вопросом и по умолчанию выключен.
for SB_MK in feeds/*/net/sing-box/Makefile; do
    [ -f "$SB_MK" ] || continue
    grep -q 'config SING_BOX_BUILD_NAIVE_OUTBOUND' "$SB_MK" || continue
    sed -i '/config SING_BOX_BUILD_NAIVE_OUTBOUND/,/def_bool/ s/def_bool y/def_bool n/' "$SB_MK"
    if sed -n '/config SING_BOX_BUILD_NAIVE_OUTBOUND/,/def_bool/p' "$SB_MK" | grep -q 'def_bool n'; then
        echo ">>> [sing-box] $SB_MK: NaiveProxy выключена, libcronet не собирается."
    else
        echo "::warning title=sing-box::$SB_MK: не удалось выключить NaiveProxy, libcronet может собираться часами"
    fi
done

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
