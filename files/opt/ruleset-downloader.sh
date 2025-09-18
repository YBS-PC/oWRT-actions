#!/bin/sh

# Скрипт для скачивания SRS файлов на OpenWrt (HomeProxy compatible)
# Автор: Created for OpenWrt 24.10 + HomeProxy
# Версия: 2.0 - с поддержкой пустых файлов для стабильности

# Настройки
DOWNLOAD_DIR="/opt/Rulesets"
# Зеркала для скачивания (в порядке приоритета)
MIRRORS=(
    "https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/srs"
    "https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs"
    "https://fastly.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs"
)
LOG_FILE="/var/log/srs_downloader.log"
LOCK_FILE="/var/run/srs_downloader.lock"

# Файлы для скачивания
FILES="twitter.srs telegram.srs facebook.srs"

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# Проверка блокировки (предотвращение одновременного запуска)
if [ -f "$LOCK_FILE" ]; then
    log_message "Скрипт уже запущен. Выход."
    exit 1
fi

# Создание файла блокировки
echo $$ > "$LOCK_FILE"

# Функция очистки при выходе
cleanup() {
    rm -f "$LOCK_FILE"
    exit $1
}

# Обработчик сигналов
trap 'cleanup 1' INT TERM

# Функция проверки доступности зеркала
test_mirror() {
    local base_url="$1"
    local test_file="twitter.srs"
    local test_url="$base_url/$test_file"
    
    # Быстрая проверка доступности (только заголовки)
    if curl -sS --connect-timeout 10 --max-time 15 -k -I "$test_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Функция выбора рабочего зеркала
select_working_mirror() {
    log_message "Проверка доступности зеркал..."
    
    for mirror in "${MIRRORS[@]}"; do
        log_message "Тестирование зеркала: $mirror"
        if test_mirror "$mirror"; then
            log_message "Выбрано рабочее зеркало: $mirror"
            echo "$mirror"
            return 0
        else
            log_message "Зеркало недоступно: $mirror"
        fi
    done
    
    log_message "ОШИБКА: Все зеркала недоступны"
    return 1
}
create_empty_files() {
    log_message "Создание пустых SRS файлов для HomeProxy..."
    for file in $FILES; do
        DEST_FILE="$DOWNLOAD_DIR/$file"
        if [ ! -f "$DEST_FILE" ]; then
            touch "$DEST_FILE"
            log_message "Создан пустой файл: $file"
        fi
    done
}

# Функция безопасного обновления файла
safe_update_file() {
    local temp_file="$1"
    local dest_file="$2" 
    local filename="$3"
    
    # Проверка размера файла
    if [ ! -s "$temp_file" ]; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Скачанный файл $filename пуст, оставляем старый"
        rm -f "$temp_file"
        return 1
    fi
    
    # Проверка, что файл содержит корректные данные (начинается с правильного заголовка)
    if ! head -c 10 "$temp_file" | grep -q "^SRS" 2>/dev/null; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Файл $filename не содержит корректный SRS заголовок"
        # Но все равно обновляем, так как формат может отличаться
    fi
    
    # Проверка, изменился ли файл
    if [ -f "$dest_file" ] && [ -s "$dest_file" ]; then
        if cmp -s "$temp_file" "$dest_file"; then
            log_message "$filename не изменился"
            rm -f "$temp_file"
            return 0
        else
            # Создаем резервную копию
            cp "$dest_file" "$dest_file.backup"
            mv "$temp_file" "$dest_file"
            log_message "$filename успешно обновлен (создана резервная копия)"
            return 0
        fi
    else
        mv "$temp_file" "$dest_file"
        log_message "$filename успешно скачан"
        return 0
    fi
}

log_message "Запуск скрипта скачивания SRS файлов"

# Проверка существования папки назначения
if [ ! -d "$DOWNLOAD_DIR" ]; then
    log_message "Создание папки $DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"
    if [ $? -ne 0 ]; then
        log_message "ОШИБКА: Не удалось создать папку $DOWNLOAD_DIR"
        cleanup 1
    fi
fi

# Создание пустых файлов при первом запуске
create_empty_files

# Выбор рабочего зеркала
WORKING_MIRROR=$(select_working_mirror)
if [ $? -ne 0 ]; then
    log_message "КРИТИЧЕСКАЯ ОШИБКА: Нет доступных зеркал для скачивания"
    log_message "Проверьте подключение к интернету или настройки DNS"
    log_message "Файлы остаются в текущем состоянии"
    cleanup 1
fi

# Проверка наличия curl
if ! command -v curl >/dev/null 2>&1; then
    log_message "ОШИБКА: curl не найден. Установите его: opkg install curl"
    cleanup 1
fi

# Счетчики
SUCCESS_COUNT=0
TOTAL_COUNT=0

# Скачивание файлов
for file in $FILES; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    URL="$WORKING_MIRROR/$file"
    DEST_FILE="$DOWNLOAD_DIR/$file"
    TEMP_FILE="$DEST_FILE.tmp"
    
    log_message "Скачивание $file из $WORKING_MIRROR..."
    
    # Скачивание во временный файл с переключением зеркал при неудаче
    download_success=0
    current_mirror="$WORKING_MIRROR"
    
    for attempt in 1 2 3; do
        # При неудачных попытках пробуем другие зеркала
        if [ $attempt -gt 1 ]; then
            log_message "Попытка $attempt: пробуем следующее зеркало..."
            for mirror in "${MIRRORS[@]}"; do
                if [ "$mirror" != "$current_mirror" ]; then
                    if test_mirror "$mirror"; then
                        current_mirror="$mirror"
                        URL="$current_mirror/$file"
                        log_message "Переключились на зеркало: $current_mirror"
                        break
                    fi
                fi
            done
        fi
        
        # Используем curl с обработкой SSL проблем
        if curl -sS --connect-timeout 30 --max-time 60 -k -L -o "$TEMP_FILE" "$URL" 2>/dev/null; then
            download_success=1
            break
        else
            log_message "Попытка $attempt неудачна для $file (зеркало: $current_mirror)"
            sleep 2
        fi
    done
    
    if [ $download_success -eq 1 ]; then
        # Безопасное обновление файла
        if safe_update_file "$TEMP_FILE" "$DEST_FILE" "$file"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    else
        log_message "ОШИБКА: Не удалось скачать $file после 3 попыток, оставляем существующий файл"
        rm -f "$TEMP_FILE"
    fi
done

log_message "Завершено. Успешно обновлено: $SUCCESS_COUNT из $TOTAL_COUNT файлов"

# Вывод информации о файлах
if [ -d "$DOWNLOAD_DIR" ]; then
    log_message "Текущее состояние SRS файлов в $DOWNLOAD_DIR:"
    for file in $FILES; do
        filepath="$DOWNLOAD_DIR/$file"
        if [ -f "$filepath" ]; then
            size=$(ls -lh "$filepath" | awk '{print $5}')
            mtime=$(ls -l "$filepath" | awk '{print $6, $7, $8}')
            log_message "$file: $size, изменен $mtime"
        else
            log_message "$file: ОТСУТСТВУЕТ"
        fi
    done
    
    # Проверка резервных копий
    backup_count=$(ls "$DOWNLOAD_DIR"/*.backup 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 0 ]; then
        log_message "Найдено $backup_count резервных копий в $DOWNLOAD_DIR"
    fi
fi

# Проверка работоспособности HomeProxy (если процесс запущен)
if pgrep -f "homeproxy" >/dev/null 2>&1; then
    log_message "HomeProxy запущен, SRS файлы доступны для использования"
else
    log_message "HomeProxy не запущен (это нормально, если он не настроен для автозапуска)"
fi

cleanup 0
