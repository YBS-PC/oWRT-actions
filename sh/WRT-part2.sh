#!/bin/bash

echo ">>>>>>>>> WRT-part2 start. Использование: после feeds update, но до feeds install"
# =========================================================
# Скрипт обновления пакетов и применения фиксов
#
# Использование: запустить после feeds update, перед feeds install
# =========================================================

# --------------------------------------------------------------------------
# Обновление youtubeUnblock
# --------------------------------------------------------------------------

# Проверка: Нужно ли нам это обновление?
# Если вариант "чистый", то youtubeUnblock будет удален в part3, нет смысла его обновлять.
if [[ "$VARIANT" == "clear" || "$VARIANT" == "crystal_clear" ]]; then
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

    # Если файл найден — обновляем, если нет — просто пропускаем (БЕЗ ОШИБКИ)
    if [ -z "$PKG_FILE_YTB" ]; then
        echo "⚠ ВНИМАНИЕ: Makefile youtubeUnblock не найден."
        echo "  Возможно, фид не был добавлен. Пропускаем обновление."
    else
        echo "✓ Найден Makefile: $PKG_FILE_YTB"

        # Получаем последний коммит из main
        echo "Получение последнего коммита из GitHub..."
        LATEST_COMMIT_YTB=$(curl -sL "https://api.github.com/repos/Waujito/youtubeUnblock/commits/main" | grep -m 1 '"sha"' | sed 's/.*"sha": "\([^"]*\)".*/\1/')

        # Fallback
        if [ -z "$LATEST_COMMIT_YTB" ]; then
            echo "GitHub API недоступен, использую git ls-remote..."
            LATEST_COMMIT_YTB=$(git ls-remote https://github.com/Waujito/youtubeUnblock.git main | cut -f1)
        fi

        if [ -z "$LATEST_COMMIT_YTB" ]; then
            echo "✗ Ошибка: не удалось получить хеш коммита. Пропуск."
        else
            echo "✓ Последний коммит: $LATEST_COMMIT_YTB"
            
            # Получаем текущий PKG_REV
            CURRENT_REV_YTB=$(grep "^PKG_REV" "$PKG_FILE_YTB" | cut -d'=' -f2 | tr -d ' :' | head -1)

            if [ "$CURRENT_REV_YTB" = "$LATEST_COMMIT_YTB" ]; then
                echo "✓ PKG_REV уже актуален."
            else
                echo "Обновление PKG_REV..."
                echo "  Было: ${CURRENT_REV_YTB:0:12}..."
                echo "  Стало: ${LATEST_COMMIT_YTB:0:12}..."

                # Обновляем PKG_REV
                sed -i "s|^PKG_REV:=.*|PKG_REV:=$LATEST_COMMIT_YTB|" "$PKG_FILE_YTB"

                # Увеличиваем PKG_RELEASE
                CURRENT_RELEASE=$(grep "^PKG_RELEASE" "$PKG_FILE_YTB" | cut -d'=' -f2 | tr -d ' :')
                if [ ! -z "$CURRENT_RELEASE" ]; then
                    NEW_RELEASE=$((CURRENT_RELEASE + 1))
                    sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=$NEW_RELEASE|" "$PKG_FILE_YTB"
                    echo "✓ PKG_RELEASE: $CURRENT_RELEASE → $NEW_RELEASE"
                fi

                # Хак хешей
                sed -i '/^PKG_HASH:=/d' "$PKG_FILE_YTB"
                sed -i '/^PKG_MIRROR_HASH:=/d' "$PKG_FILE_YTB"
                sed -i '/PKG_SOURCE_VERSION:=/a PKG_MIRROR_HASH:=skip' "$PKG_FILE_YTB"

                echo "✓ Обновление успешно завершено!"
            fi
        fi
    fi
fi

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
