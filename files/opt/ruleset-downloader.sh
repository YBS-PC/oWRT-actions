#!/bin/sh

# Скрипт для скачивания SRS файлов на OpenWrt
# Автор: Created for OpenWrt 24.10
# Версия: 1.0

# Настройки
DOWNLOAD_DIR="/opt/Rulesets"
BASE_URL="https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/srs"
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
    URL="$BASE_URL/$file"
    DEST_FILE="$DOWNLOAD_DIR/$file"
    TEMP_FILE="$DEST_FILE.tmp"
    
    log_message "Скачивание $file..."
    
    # Скачивание во временный файл (с повторными попытками)
    download_success=0
    for attempt in 1 2 3; do
        # Используем curl с обработкой SSL проблем
        if curl -sS --connect-timeout 30 --max-time 60 -k -L -o "$TEMP_FILE" "$URL" 2>/dev/null; then
            download_success=1
            break
        else
            log_message "Попытка $attempt неудачна для $file"
            sleep 2
        fi
    done
    
    if [ $download_success -eq 1 ]; then
        # Проверка размера файла
        if [ -s "$TEMP_FILE" ]; then
            # Проверка, изменился ли файл
            if [ -f "$DEST_FILE" ]; then
                if cmp -s "$TEMP_FILE" "$DEST_FILE"; then
                    log_message "$file не изменился"
                    rm -f "$TEMP_FILE"
                else
                    mv "$TEMP_FILE" "$DEST_FILE"
                    log_message "$file успешно обновлен"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                fi
            else
                mv "$TEMP_FILE" "$DEST_FILE"
                log_message "$file успешно скачан"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
        else
            log_message "ОШИБКА: Скачанный файл $file пуст"
            rm -f "$TEMP_FILE"
        fi
    else
        log_message "ОШИБКА: Не удалось скачать $file после 3 попыток"
        rm -f "$TEMP_FILE"
    fi
done

log_message "Завершено. Успешно обработано: $SUCCESS_COUNT из $TOTAL_COUNT файлов"

# Вывод информации о файлах
if [ -d "$DOWNLOAD_DIR" ]; then
    log_message "Содержимое папки $DOWNLOAD_DIR:"
    ls -la "$DOWNLOAD_DIR"/*.srs 2>/dev/null | while read line; do
        log_message "$line"
    done
fi

cleanup 0