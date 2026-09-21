#!/bin/bash

echo ">>>>>>>>> WRT-part2 start. Использование: после feeds update, но до feeds install"
# =========================================================
# Скрипт обновления пакетов и применения фиксов
#
# Использование: запустить после feeds update, перед feeds install
# =========================================================

# --------------------------------------------------------------------------
# Версии пакетов, собираемых из git
#
# Makefile'ы forkop и luci-theme-proton2025 читают версию из окружения:
#   forkop/Makefile       FORKOP_VERSION  -> без неё PKG_VERSION=0.0.0
#   proton2025/Makefile   PROTON_VERSION  -> без неё зашитый дефолт 1.4.0
#
# Тег тянем через git ls-remote: не требует ни токена, ни клона. Фолбэк —
# GitHub API (с токеном, если он проброшен в шаг). part2 вызывается из yml
# как подпроцесс, поэтому export не доживает до шага компиляции — пишем
# в $GITHUB_ENV.
# --------------------------------------------------------------------------

# resolve_latest_tag <git-url> -> печатает x.y.z либо ничего
resolve_latest_tag() {
    local _repo="$1" _api _ver _auth=()

    # Основной путь: ls-remote. sed срезает refs/tags/ и ведущую v,
    # grep отбрасывает нечисловые теги (nightly, 1.4.1-rc1) — Makefile
    # forkop падает с $(error), если версия не в формате x.y.z.
    _ver=$(git ls-remote --tags --refs "$_repo" 2>/dev/null \
        | awk '{print $2}' | sed 's|refs/tags/||; s|^v||' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)

    if [ -z "$_ver" ]; then
        _api=$(echo "$_repo" | sed 's|https://github.com/||; s|\.git$||')
        [ -n "$GITHUB_TOKEN" ] && _auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
        _ver=$(curl -sL --max-time 15 "${_auth[@]}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${_api}/tags" 2>/dev/null \
            | grep -m1 '"name"' | sed 's/.*: "\(.*\)",/\1/; s/^v//' \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$')
    fi

    [ -n "$_ver" ] && printf '%s\n' "$_ver"
}

# export_build_var <ИМЯ> <значение> — в текущий процесс и в шаги workflow
export_build_var() {
    export "$1=$2"
    [ -n "$GITHUB_ENV" ] && echo "$1=$2" >> "$GITHUB_ENV"
}

echo "=================================================="
echo "Определение версий пакетов из git"
echo "=================================================="

if [[ "$VARIANT" == "forkop" ]]; then
    FORKOP_VER=$(resolve_latest_tag "https://github.com/Gavr1024/forkop-mod.git")
    if [ -n "$FORKOP_VER" ]; then
        export_build_var FORKOP_VERSION "$FORKOP_VER"
        echo "✓ forkop: $FORKOP_VER"
    else
        # Makefile распознаёт dev и уходит в PKG_VERSION=0.0.0 без ошибки
        export_build_var FORKOP_VERSION "dev"
        echo "⚠ forkop: тег не определён, ставлю dev (PKG_VERSION=0.0.0)"
    fi
else
    echo ">>> Variant '$VARIANT': forkop не собирается, версия не нужна."
fi

PROTON_VER=$(resolve_latest_tag "https://github.com/ChesterGoodiny/luci-theme-proton2025.git")
if [ -n "$PROTON_VER" ]; then
    export_build_var PROTON_VERSION "$PROTON_VER"
    echo "✓ luci-theme-proton2025: $PROTON_VER"
else
    # Переменную НЕ задаём: сработает PROTON_VERSION?= из Makefile темы
    echo "⚠ luci-theme-proton2025: тег не определён, останется дефолт из Makefile."
fi

# --------------------------------------------------------------------------
# Обновление youtubeUnblock
# --------------------------------------------------------------------------

if [[ "$VARIANT" == "clear" || "$VARIANT" == "crystal_clear" || "$VARIANT" == "switch" || "$VARIANT" == "forkop" ]]; then
    echo ">>> Variant is '$VARIANT'. Skipping youtubeUnblock update."
else
    echo "=================================================="
    echo "Блок обновления youtubeUnblock до latest main..."
    echo "=================================================="
    # Поиск Makefile
    PKG_FILE_YTB=""
    for path in \
        "feeds/youtubeUnblock/youtubeUnblock/Makefile" \
        "package/feeds/youtubeUnblock/youtubeUnblock/Makefile" \
        "feeds/packages/net/youtubeUnblock/Makefile"; do
        if [ -f "$path" ]; then
            PKG_FILE_YTB="$path"
            break
        fi
    done
    if [ -z "$PKG_FILE_YTB" ]; then
        echo "⚠ ВНИМАНИЕ: Makefile youtubeUnblock не найден."
        echo "  Возможно, фид не был добавлен. Пропускаем обновление."
    else
        echo "✓ Найден Makefile: $PKG_FILE_YTB"
        # Получаем последний коммит
        echo "Получение последнего коммита из GitHub..."
        LATEST_COMMIT_YTB=$(curl -sL "https://api.github.com/repos/Waujito/youtubeUnblock/commits/main" | grep -m 1 '"sha"' | sed 's/.*"sha": "\([^"]*\)".*/\1/')
        # Fallback на git ls-remote
        if [ -z "$LATEST_COMMIT_YTB" ]; then
            echo "GitHub API недоступен, использую git ls-remote..."
            LATEST_COMMIT_YTB=$(git ls-remote https://github.com/Waujito/youtubeUnblock.git main | cut -f1)
        fi
        if [ -z "$LATEST_COMMIT_YTB" ]; then
            echo "✗ Ошибка: не удалось получить хеш коммита. Пропуск."
        else
            echo "✓ Последний коммит: $LATEST_COMMIT_YTB"
            # Получаем текущий PKG_REV из файла
            CURRENT_REV_YTB=$(grep "^PKG_REV" "$PKG_FILE_YTB" | cut -d'=' -f2 | tr -d ' :' | head -1)
            if [ "$CURRENT_REV_YTB" = "$LATEST_COMMIT_YTB" ]; then
                echo "✓ PKG_REV уже актуален."
            else
                echo "Обновление PKG_REV..."
                echo "  Было: ${CURRENT_REV_YTB:0:12}..."
                echo "  Стало: ${LATEST_COMMIT_YTB:0:12}..."
                # 1. Обновляем переменную коммита
                if grep -q "^PKG_REV:=" "$PKG_FILE_YTB"; then
                    sed -i "s|^PKG_REV:=.*|PKG_REV:=$LATEST_COMMIT_YTB|" "$PKG_FILE_YTB"
                elif grep -q "^PKG_SOURCE_VERSION:=" "$PKG_FILE_YTB"; then
                    sed -i "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=$LATEST_COMMIT_YTB|" "$PKG_FILE_YTB"
                fi
                # 2. Получаем реальную версию из upstream Makefile
                # Улучшенный grep: ищет PKG_VERSION или VERSION с возможными пробелами перед =
                REAL_VER=$(curl -sL "https://raw.githubusercontent.com/Waujito/youtubeUnblock/main/Makefile" | grep -E "^(PKG_)?VERSION[: ]*=" | cut -d'=' -f2 | tr -d ' ')
                if [ -z "$REAL_VER" ]; then
                    REAL_VER="1.0"
                fi
                # Формируем версию: 1.3.0.20260203
                FINAL_VER="${REAL_VER}.$(date +%Y%m%d)"
                echo "  Новая версия: $FINAL_VER"
                sed -i "s|^PKG_VERSION:=.*|PKG_VERSION:=$FINAL_VER|" "$PKG_FILE_YTB"
                # 3. Сбрасываем PKG_RELEASE в 1 (так как версия изменилась)
                # Это стандарт OpenWrt: новая версия = релиз 1
                sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=1|" "$PKG_FILE_YTB"
                echo "✓ PKG_RELEASE сброшен в 1"
                # 4. Хак хешей (отключаем проверку)
                sed -i '/^PKG_HASH:=/d' "$PKG_FILE_YTB"
                sed -i '/^PKG_MIRROR_HASH:=/d' "$PKG_FILE_YTB"
                if ! grep -q "PKG_MIRROR_HASH:=skip" "$PKG_FILE_YTB"; then
                    sed -i '/PKG_SOURCE_VERSION:=/a PKG_MIRROR_HASH:=skip' "$PKG_FILE_YTB"
                fi
                echo "✓ Обновление успешно завершено!"
            fi
        fi
    fi
fi

# --------------------------------------------------------------------------
# --- Фикс Rust 1.90.0: download-ci-llvm=true несовместим с GitHub Actions (CI=true) ---
#-----#RUST_MK="feeds/packages/lang/rust/Makefile"
#-----#if [ -f "$RUST_MK" ]; then
#-----#    echo ">>> [Rust fix] Patching $RUST_MK..."
#-----#    sed -i 's/--set=llvm.download-ci-llvm=true/--set=llvm.download-ci-llvm=if-unchanged/' "$RUST_MK"
#-----#    echo ">>> [Rust fix] Done."
#-----#fi

# --------------------------------------------------------------------------
# Фиксы Python (ТОЛЬКО ДЛЯ ВЕТКИ MASTER или MAIN)
# --------------------------------------------------------------------------

#---#echo "=================================================="
#---#echo "Блок фикса Python"
#---#echo "=================================================="

# Проверяем, равна ли переменная REPO_BRANCH значению master или main
#---#if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then

#---#    echo ""
#---#    echo "=========================================="
#---#    echo "Ветка '$REPO_BRANCH': Применение фикса Python PGO..."
#---#    echo "=========================================="

#---#    PYTHON_MAKEFILE=""
#---#    if [ -f "feeds/packages/lang/python/python3/Makefile" ]; then
#---#        PYTHON_MAKEFILE="feeds/packages/lang/python/python3/Makefile"
#---#    elif [ -f "package/feeds/packages/lang/python/python3/Makefile" ]; then
#---#        PYTHON_MAKEFILE="package/feeds/packages/lang/python/python3/Makefile"
#---#    fi

#---#    if [ -z "$PYTHON_MAKEFILE" ]; then
#---#        echo "⚠ Python 3 Makefile не найден."
#---#    else
#---#        echo "Нашел Makefile: $PYTHON_MAKEFILE"
        
        # Отключаем PGO и оптимизации
#---#        sed -i 's/PYTHON_PGO:=1/PYTHON_PGO:=0/' "$PYTHON_MAKEFILE"
#---#        sed -i 's/PYTHON_PGO=1/PYTHON_PGO=0/' "$PYTHON_MAKEFILE"
#---#        sed -i 's/--enable-optimizations/--disable-optimizations/' "$PYTHON_MAKEFILE"
        
        # Отключаем тесты
#---#        sed -i 's/PYTHON_RUN_TESTS:=1/PYTHON_RUN_TESTS:=0/' "$PYTHON_MAKEFILE"
#---#        sed -i 's/PYTHON_RUN_TESTS=1/PYTHON_RUN_TESTS=0/' "$PYTHON_MAKEFILE"

#---#        echo "=========================================="
#---#        echo "✓ PGO, тесты и оптимизации отключены для ускорения сборки master или main."
#---#        echo "=========================================="
#---#    fi

#---#else
#---#    echo ""
#---#    echo "=========================================="
#---#    echo "Ветка '$REPO_BRANCH' (не master или main). Фикс Python пропущен."
#---#    echo "=========================================="
#---#fi

# --------------------------------------------------------------------------
# Фикс Contiguous PTE mappings for user memory (ARM64_CONTPTE) (ТОЛЬКО ДЛЯ nanopi-r5s ВЕТКИ MASTER или MAIN)
# --------------------------------------------------------------------------

#--#echo "=================================================="
#--#echo "Блок для исправления ошибки интерактивности ядра ARM64_CONTPTE"
#--#echo "=================================================="

# Проверяем, что цель — nanopi-r5s И что мы собираем из нестабильной ветки (master/main).
#--#if [ "$CURRENT_MATRIX_TARGET" == "nanopi-r5s" ]; then
#--#    if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then
        
#--#        echo ">>> Target is nanopi-r5s on branch $REPO_BRANCH. Applying kernel config patch."
        
        # 1. Определяем путь, где лежат конфиги Rockchip/ARMv8
#--#        TARGET_CONFIG_PATH="target/linux/rockchip/armv8"
        
        # 2. Ищем актуальный файл конфигурации ядра (например, config-6.12 или config-6.13)
#--#        TARGET_CONFIG_FILE=$(find $TARGET_CONFIG_PATH -name "config-*" -type f | head -n 1)

#--#        if [ -n "$TARGET_CONFIG_FILE" ]; then
#--#            echo "Found kernel config file: $TARGET_CONFIG_FILE"
            
            # 3. Проверяем, отсутствует ли опция (устранение интерактивного запроса)
#--#            if ! grep -q "CONFIG_ARM64_CONTPTE" "$TARGET_CONFIG_FILE"; then
#--#                echo "CONFIG_ARM64_CONTPTE=y" >> "$TARGET_CONFIG_FILE"
#--#                echo "=========================================="
#--#                echo "Patch applied successfully to prevent interactive prompt."
#--#                echo "=========================================="
#--#            else
#--#                echo "CONFIG_ARM64_CONTPTE=y already exists. Skipping patch."
#--#            fi
#--#        else
#--#            echo "Could not find kernel config file in $TARGET_CONFIG_PATH. Skipping patch."
#--#        fi
#--#    else
#--#        echo "=========================================="
#--#        echo "Target is nanopi-r5s, but branch is stable ($REPO_BRANCH). Skipping kernel patch."
#--#        echo "=========================================="
#--#    fi
#--#else
#--#    echo "=========================================="
#--#    echo "Target is not nanopi-r5s. Skipping kernel patch."
#--#    echo "=========================================="
#--#fi
echo ">>>>>>>>> WRT-part2 end"
