#!/bin/bash
#=================================================
# Скрипт обновления пакетов и применения фиксов
#
# Использование: запустить после feeds update, перед feeds install
#=================================================


# --------------------------------------------------------------------------
# ЧАСТЬ 1: Обновление youtubeUnblock (Выполняется ВСЕГДА)
# --------------------------------------------------------------------------
echo "=================================================="
echo "Обновление youtubeUnblock до latest main..."
echo "=================================================="

# Получаем последний коммит из main
echo "Получение последнего коммита из GitHub..."
LATEST_COMMIT=$(curl -sL "https://api.github.com/repos/Waujito/youtubeUnblock/commits/main" | grep -m 1 '"sha"' | sed 's/.*"sha": "\([^"]*\)".*/\1/')

# Fallback на git ls-remote если API не сработал
if [ -z "$LATEST_COMMIT" ]; then
    echo "GitHub API недоступен, использую git ls-remote..."
    LATEST_COMMIT=$(git ls-remote https://github.com/Waujito/youtubeUnblock.git main | cut -f1)
fi

if [ -z "$LATEST_COMMIT" ]; then
    echo "✗ Ошибка: не удалось получить последний коммит"
    exit 1
fi

echo "✓ Последний коммит: $LATEST_COMMIT"

# Находим Makefile (проверяем возможные расположения) PKG_FILE=$(find feeds -name "Makefile" | grep "/youtubeUnblock/Makefile" | head -n 1)
PKG_FILE=""
for path in \
    "feeds/youtubeUnblock/youtubeUnblock/Makefile" \
    "package/feeds/youtubeUnblock/youtubeUnblock/Makefile" \
    "feeds/packages/net/youtubeUnblock/Makefile"; do
    if [ -f "$path" ]; then
        PKG_FILE="$path"
        break
    fi
done

if [ -z "$PKG_FILE" ]; then
    echo "✗ Ошибка: Makefile youtubeUnblock не найден"
    echo "  Проверьте что feeds обновлены (./scripts/feeds update -a)"
    exit 1
fi

echo "✓ Найден Makefile: $PKG_FILE"

# Получаем текущий PKG_REV
CURRENT_REV=$(grep "^PKG_REV" "$PKG_FILE" | cut -d'=' -f2 | tr -d ' :' | head -1)

if [ "$CURRENT_REV" = "$LATEST_COMMIT" ]; then
    echo "✓ PKG_REV уже актуален, обновление не требуется"
    exit 0
fi

echo "Обновление PKG_REV..."
echo "  Было: ${CURRENT_REV:0:12}..."
echo "  Стало: ${LATEST_COMMIT:0:12}..."

# Обновляем PKG_REV
sed -i "s|^PKG_REV:=.*|PKG_REV:=$LATEST_COMMIT|" "$PKG_FILE"
#sed -i "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=$LATEST_COMMIT|" "$PKG_FILE"

# Увеличиваем PKG_RELEASE
CURRENT_RELEASE=$(grep "^PKG_RELEASE" "$PKG_FILE" | cut -d'=' -f2 | tr -d ' :')
if [ ! -z "$CURRENT_RELEASE" ] && [ "$CURRENT_RELEASE" -eq "$CURRENT_RELEASE" ] 2>/dev/null; then
    NEW_RELEASE=$((CURRENT_RELEASE + 1))
    sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=$NEW_RELEASE|" "$PKG_FILE"
    echo "✓ PKG_RELEASE: $CURRENT_RELEASE → $NEW_RELEASE"
fi

# Удаляем старые строки с хешами, если они есть
sed -i '/^PKG_HASH:=/d' "$PKG_FILE"
sed -i '/^PKG_MIRROR_HASH:=/d' "$PKG_FILE"

# Добавляем инструкцию пропускать проверку хеша
# Вставляем это после PKG_RELEASE или PKG_SOURCE_VERSION
sed -i '/PKG_SOURCE_VERSION:=/a PKG_MIRROR_HASH:=skip' "$PKG_FILE"

#grep -E "PKG_REV|PKG_SOURCE_VERSION|PKG_MIRROR_HASH" "$PKG_FILE"

# Проверяем результат
UPDATED_REV=$(grep "^PKG_REV" "$PKG_FILE" | cut -d'=' -f2 | tr -d ' :')
if [ "$UPDATED_REV" = "$LATEST_COMMIT" ]; then
    echo "=================================================="
    echo "✓ Обновление youtubeUnblock успешно завершено!"
    echo "=================================================="
else
    echo "✗ Ошибка при обновлении"
    exit 1
fi


# --------------------------------------------------------------------------
# ЧАСТЬ 2: Фиксы Python (ТОЛЬКО ДЛЯ ВЕТКИ MASTER или MAIN)
# --------------------------------------------------------------------------

# Проверяем, равна ли переменная REPO_BRANCH значению master или main
if [[ "$REPO_BRANCH" == "master" || "$REPO_BRANCH" == "main" ]]; then

    echo ""
    echo "=========================================="
    echo "Ветка '$REPO_BRANCH': Применение фикса Python PGO..."
    echo "=========================================="

    PYTHON_MAKEFILE=""
    if [ -f "feeds/packages/lang/python/python3/Makefile" ]; then
        PYTHON_MAKEFILE="feeds/packages/lang/python/python3/Makefile"
    elif [ -f "package/feeds/packages/lang/python/python3/Makefile" ]; then
        PYTHON_MAKEFILE="package/feeds/packages/lang/python/python3/Makefile"
    fi

    if [ -z "$PYTHON_MAKEFILE" ]; then
        echo "⚠ Python 3 Makefile не найден."
    else
        echo "Нашел Makefile: $PYTHON_MAKEFILE"
        
        # Отключаем PGO и оптимизации
        sed -i 's/PYTHON_PGO:=1/PYTHON_PGO:=0/' "$PYTHON_MAKEFILE"
        sed -i 's/PYTHON_PGO=1/PYTHON_PGO=0/' "$PYTHON_MAKEFILE"
        sed -i 's/--enable-optimizations/--disable-optimizations/' "$PYTHON_MAKEFILE"
        
        # Отключаем тесты
        sed -i 's/PYTHON_RUN_TESTS:=1/PYTHON_RUN_TESTS:=0/' "$PYTHON_MAKEFILE"
        sed -i 's/PYTHON_RUN_TESTS=1/PYTHON_RUN_TESTS=0/' "$PYTHON_MAKEFILE"

        echo "✓ PGO, тесты и оптимизации отключены для ускорения сборки master или main."
    fi

else
    echo ""
    echo "=========================================="
    echo "Ветка '$REPO_BRANCH' (не master или main). Фикс Python пропущен."
    echo "=========================================="
fi
