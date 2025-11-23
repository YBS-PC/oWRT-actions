#!/bin/bash
#=================================================
# Скрипт для автоматического обновления PKG_REV
# в Makefile пакета youtubeUnblock до последнего коммита
#=================================================

set -e

echo "=================================================="
echo "Обновление PKG_REV для youtubeUnblock..."
echo "=================================================="

# Путь к Makefile пакета youtubeUnblock в feeds
MAKEFILE_PATH="feeds/youtubeUnblock/youtubeUnblock/Makefile"

# Проверка существования Makefile
if [ ! -f "$MAKEFILE_PATH" ]; then
    echo "ОШИБКА: Makefile не найден по пути: $MAKEFILE_PATH"
    echo "Возможно feeds еще не обновлены или путь неверный"
    exit 1
fi

echo "Найден Makefile: $MAKEFILE_PATH"

# Получаем последний коммит из ветки main репозитория youtubeUnblock
echo "Получаем последний коммит из github.com/Waujito/youtubeUnblock (ветка main)..."
LATEST_COMMIT=$(curl -s "https://api.github.com/repos/Waujito/youtubeUnblock/commits/main" | grep '"sha"' | head -n 1 | sed 's/.*"sha": "\(.*\)".*/\1/')

if [ -z "$LATEST_COMMIT" ]; then
    echo "ОШИБКА: Не удалось получить последний коммит из GitHub API"
    exit 1
fi

echo "Последний коммит: $LATEST_COMMIT"

# Получаем текущее значение PKG_REV из Makefile
CURRENT_REV=$(grep "^PKG_REV" "$MAKEFILE_PATH" | cut -d':=' -f2 | tr -d ' ')

if [ -z "$CURRENT_REV" ]; then
    echo "ПРЕДУПРЕЖДЕНИЕ: PKG_REV не найден в Makefile"
    echo "Файл может использовать другой формат"
else
    echo "Текущий PKG_REV: $CURRENT_REV"
fi

# Сравниваем коммиты
if [ "$CURRENT_REV" = "$LATEST_COMMIT" ]; then
    echo "✓ PKG_REV уже актуален, обновление не требуется"
    exit 0
fi

# Создаем резервную копию
echo "Создание резервной копии Makefile..."
cp "$MAKEFILE_PATH" "${MAKEFILE_PATH}.backup"

# Обновляем PKG_REV в Makefile
echo "Обновление PKG_REV в Makefile..."
sed -i "s/^PKG_REV:=.*/PKG_REV:=$LATEST_COMMIT/" "$MAKEFILE_PATH"

# Проверяем результат
NEW_REV=$(grep "^PKG_REV" "$MAKEFILE_PATH" | cut -d':=' -f2 | tr -d ' ')

if [ "$NEW_REV" = "$LATEST_COMMIT" ]; then
    echo "✓ PKG_REV успешно обновлен!"
    echo "  Старый: $CURRENT_REV"
    echo "  Новый:  $NEW_REV"
else
    echo "✗ ОШИБКА: Не удалось обновить PKG_REV"
    echo "Восстановление из резервной копии..."
    mv "${MAKEFILE_PATH}.backup" "$MAKEFILE_PATH"
    exit 1
fi

# Также обновляем версию пакета (опционально)
# Это поможет OpenWRT понять, что пакет изменился
CURRENT_VERSION=$(grep "^PKG_VERSION" "$MAKEFILE_PATH" | cut -d':=' -f2 | tr -d ' ')
CURRENT_RELEASE=$(grep "^PKG_RELEASE" "$MAKEFILE_PATH" | cut -d':=' -f2 | tr -d ' ')

if [ ! -z "$CURRENT_RELEASE" ]; then
    NEW_RELEASE=$((CURRENT_RELEASE + 1))
    sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$NEW_RELEASE/" "$MAKEFILE_PATH"
    echo "✓ Увеличен PKG_RELEASE: $CURRENT_RELEASE -> $NEW_RELEASE"
fi

# Показываем изменения
echo ""
echo "Сводка изменений:"
echo "-------------------------------------------"
diff -u "${MAKEFILE_PATH}.backup" "$MAKEFILE_PATH" || true
echo "-------------------------------------------"

# Удаляем резервную копию
rm -f "${MAKEFILE_PATH}.backup"

echo ""
echo "=================================================="
echo "✓ Обновление завершено успешно!"
echo "=================================================="
