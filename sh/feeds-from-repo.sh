#!/bin/bash
#=================================================
# Фиды packages / luci / routing / telephony / video на тех коммитах, из
# которых собран репозиторий пакетов релизной ветки (то, что роутер получит
# через «apk upgrade»), вместо коммитов, закреплённых в релизном теге.
#
# Запускается из openwrt/ ПОСЛЕ того, как feeds.conf.default собран целиком
# (part1, фиды варианта, замена git.openwrt.org на GitHub) и ДО
# «feeds update».
#
# Источник: <сервер>/releases/packages-<ветка>/<arch>/feeds.conf, строки
#   src-git packages https://git.openwrt.org/feed/packages.git^<коммит>
# Из файла берётся только коммит; адрес фида остаётся тем, что уже стоит в
# feeds.conf.default (с заменой на GitHub). Другие фиды (свои из part1,
# варианта: podkop, forkop, passwall ...) не трогаются. Фида, которого нет в
# скачанном файле (video в 24.10 и в ImmortalWrt), — коммит из тега.
#
# Каждый коммит перед заменой проверяется (git fetch по хешу с того
# адреса, откуда его потом возьмёт «feeds update»):
#   - есть ли он там: зеркало GitHub может отставать от git.openwrt.org, и
#     без проверки такой коммит уронил бы feeds update;
#   - новее ли он закреплённого: тег, выпущенный после последней сборки
#     пакетов, бывает новее репозитория — тогда фид не откатывается назад.
# Не прошёл проверку — фид остаётся на коммите тега.
#
# Окружение: REPO_URL, REPO_BRANCH, PKG_ARCH. Сбой скачивания — не ошибка:
# сборка идёт на коммитах тега с предупреждением.
#=================================================

FEEDS_FILE="feeds.conf.default"
FEED_NAMES="packages luci routing telephony video"

echo "=================================================="
echo "Фиды из репозитория пакетов (feeds.conf сервера)"
echo "=================================================="

if [ ! -f "$FEEDS_FILE" ]; then
    echo "::warning title=Фиды из репозитория пакетов::$FEEDS_FILE не найден, пропуск"
    exit 0
fi

case "$REPO_BRANCH" in
    openwrt-[0-9]*.[0-9]*) BRANCH_VER="${REPO_BRANCH#openwrt-}" ;;
    *)
        echo ">>> Ветка $REPO_BRANCH: фиды и так берутся с головы ветки (snapshots). Пропуск."
        exit 0
        ;;
esac

if [ -z "$PKG_ARCH" ]; then
    echo "::warning title=Фиды из репозитория пакетов::Не определена архитектура пакетов (CONFIG_TARGET_ARCH_PACKAGES), остаются коммиты тега"
    exit 0
fi

# FEEDS_REPO_SERVERS — только для проверки скрипта на своём сервере
if [ -n "$FEEDS_REPO_SERVERS" ]; then
    SERVERS="$FEEDS_REPO_SERVERS"
elif [[ "$REPO_URL" == *immortalwrt* ]]; then
    SERVERS="https://downloads.immortalwrt.org https://immortalwrt.kyarucloud.moe"
else
    SERVERS="https://downloads.openwrt.org"
fi

REMOTE_CONF=$(mktemp)
TMP_GIT=$(mktemp -d)
trap 'rm -rf "$REMOTE_CONF" "$TMP_GIT"' EXIT

SRC_URL=""
for _srv in $SERVERS; do
    _url="$_srv/releases/packages-${BRANCH_VER}/${PKG_ARCH}/feeds.conf"
    echo ">>> Загрузка $_url"
    if curl -fsSL --retry 3 --max-time 30 -o "$REMOTE_CONF" "$_url" && [ -s "$REMOTE_CONF" ]; then
        SRC_URL="$_url"
        break
    fi
done
if [ -z "$SRC_URL" ]; then
    echo "::warning title=Фиды из репозитория пакетов::feeds.conf не скачан (packages-${BRANCH_VER}/${PKG_ARCH}), остаются коммиты тега"
    exit 0
fi
sed -i 's/\r$//' "$REMOTE_CONF"

# Коммит OpenWrt/ImmortalWrt, на котором сервер собирал пакеты, — для сводки
BASE_COMMIT=$(awk '$1 ~ /^src-git/ && $2 == "base" { n = split($3, a, "^"); if (n == 2) print a[2] }' "$REMOTE_CONF")

git -C "$TMP_GIT" init -q

SUMMARY=""
CHANGED=0
for _name in $FEED_NAMES; do
    # Текущая строка фида в feeds.conf.default: тип, адрес, закрепление
    _line=$(grep -E "^src-git(-full)?[[:space:]]+${_name}[[:space:]]" "$FEEDS_FILE" | head -n1)
    if [ -z "$_line" ]; then
        continue
    fi
    _type=$(echo "$_line" | awk '{print $1}')
    _spec=$(echo "$_line" | awk '{print $3}')
    _url="${_spec%%[;^]*}"
    _old="${_spec#"$_url"}"; _old="${_old#[;^]}"
    # Для вывода: хеш — первые 12 символов, ветка — целиком
    if [[ "$_old" =~ ^[0-9a-f]{40}$ ]]; then _show="${_old:0:12}"; else _show="${_old:-ветка по умолчанию}"; fi

    # Коммит из файла сервера: строго 40 hex после «^»
    _new=$(awk -v n="$_name" '$1 ~ /^src-git/ && $2 == n { k = split($3, a, "^"); if (k == 2) print a[2] }' "$REMOTE_CONF" | head -n1)
    if ! [[ "$_new" =~ ^[0-9a-f]{40}$ ]]; then
        SUMMARY="${SUMMARY}  ${_name}: нет в feeds.conf сервера — без изменений (${_show})\n"
        continue
    fi
    if [ "$_new" = "$_old" ]; then
        SUMMARY="${SUMMARY}  ${_name}: совпадает с тегом (${_new:0:12})\n"
        continue
    fi

    # Текущее закрепление как коммит: «^хеш» в теге, «;ветка» (сборка с
    # головы ветки) или без закрепления — голова ветки по умолчанию.
    _old_ref="$_old"
    if ! [[ "$_old" =~ ^[0-9a-f]{40}$ ]]; then
        if [ -n "$_old" ]; then
            _old_ref=$(git ls-remote "$_url" "refs/heads/$_old" 2>/dev/null | awk 'NR == 1 {print $1}')
        else
            _old_ref=$(git ls-remote "$_url" HEAD 2>/dev/null | awk 'NR == 1 {print $1}')
        fi
    fi

    # Оба коммита с историей (только объекты коммитов, без деревьев и
    # файлов — секунды). Заодно проверка, что коммит есть на этом адресе:
    # зеркало GitHub может отставать от git.openwrt.org.
    if ! git -C "$TMP_GIT" fetch -q --filter=tree:0 "$_url" "$_new" ${_old_ref:+"$_old_ref"} >/dev/null 2>&1; then
        echo "::warning title=Фиды из репозитория пакетов::${_name}: коммит ${_new:0:12} недоступен на ${_url}, остаётся коммит тега"
        SUMMARY="${SUMMARY}  ${_name}: ${_new:0:12} недоступен — без изменений (${_show})\n"
        continue
    fi

    # Только вперёд: коммит сервера должен быть новее закреплённого. Сервер
    # собирает пакеты периодически, и тег, выпущенный после последней сборки,
    # бывает новее (так было с luci ImmortalWrt 25.12.2) — тогда остаётся тег.
    if [ -n "$_old_ref" ] && [ "$_old_ref" != "$_new" ]; then
        if git -C "$TMP_GIT" merge-base --is-ancestor "$_new" "$_old_ref" 2>/dev/null; then
            SUMMARY="${SUMMARY}  ${_name}: закреплённый ${_show} новее, чем в репозитории (${_new:0:12}) — без изменений\n"
            continue
        fi
        if ! git -C "$TMP_GIT" merge-base --is-ancestor "$_old_ref" "$_new" 2>/dev/null; then
            echo "::warning title=Фиды из репозитория пакетов::${_name}: ${_new:0:12} не продолжает ${_old_ref:0:12} (истории разошлись), остаётся коммит тега"
            SUMMARY="${SUMMARY}  ${_name}: истории разошлись — без изменений (${_show})\n"
            continue
        fi
    elif [ "$_old_ref" = "$_new" ]; then
        SUMMARY="${SUMMARY}  ${_name}: совпадает с текущим (${_new:0:12})\n"
        continue
    fi

    _repl="${_type} ${_name} ${_url}^${_new}"
    awk -v n="$_name" -v r="$_repl" '
        !done && $1 ~ /^src-git(-full)?$/ && $2 == n { print r; done = 1; next }
        { print }
    ' "$FEEDS_FILE" > "$FEEDS_FILE.new" && mv "$FEEDS_FILE.new" "$FEEDS_FILE"
    CHANGED=$((CHANGED + 1))
    SUMMARY="${SUMMARY}  ${_name}: ${_show} -> ${_new:0:12}\n"
done

echo "Источник       : $SRC_URL"
echo "Сборка пакетов : base ${BASE_COMMIT:-?}"
printf '%b' "$SUMMARY"
echo ">>> Заменено фидов: $CHANGED"
echo "=================================================="
exit 0
