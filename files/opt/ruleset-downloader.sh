#!/bin/sh

# Скрипт для скачивания SRS файлов на OpenWrt (HomeProxy compatible)
# Версия: 3.2 - Отключено создание .backup файлов по запросу

# --- НАСТРОЙКИ ---
# Папка для сохранения правил
DOWNLOAD_DIR="/opt/Rulesets"

# Зеркала для скачивания (указаны в строке через пробел)
MIRRORS="https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/srs https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs https://fastly.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs"

# Файлы для скачивания (через пробел)
FILES="twitter.srs telegram.srs facebook.srs"

# Системные файлы
LOG_FILE="/var/log/srs_downloader.log"
LOCK_FILE="/var/run/srs_downloader.lock"

# Настройки обслуживания
MAX_LOG_SIZE_KB=500 # Максимальный размер лог-файла в КБ перед ротацией

# --- ФУНКЦИИ ---

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция ротации лог-файла
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        size_bytes=$(ls -l "$LOG_FILE" | awk '{print $5}')
        max_size_bytes=$((MAX_LOG_SIZE_KB * 1024))
        
        if [ "$size_bytes" -gt "$max_size_bytes" ]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
            log_message "Лог-файл достиг максимального размера, старый лог сохранен как $LOG_FILE.old"
        fi
    fi
}

# Функция очистки при выходе
cleanup() {
    rm -f "$LOCK_FILE"
    exit "$1"
}

# Функция проверки доступности зеркала
test_mirror() {
    base_url="$1"
    test_file="twitter.srs"
    test_url="$base_url/$test_file"
    
    if curl -sS --connect-timeout 10 --max-time 15 -k -I "$test_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Функция выбора первого рабочего зеркала
select_working_mirror() {
    log_message "Проверка доступности зеркал..."
    for mirror in $MIRRORS; do
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

# Функция создания пустых файлов для стабильности HomeProxy
create_empty_files() {
    log_message "Проверка наличия SRS файлов для HomeProxy..."
    for file in $FILES; do
        DEST_FILE="$DOWNLOAD_DIR/$file"
        if [ ! -f "$DEST_FILE" ]; then
            touch "$DEST_FILE"
            log_message "Создан пустой файл-заглушка: $file"
        fi
    done
}

# Функция безопасного обновления файла (БЕЗ СОЗДАНИЯ .BACKUP)
safe_update_file() {
    temp_file="$1"
    dest_file="$2" 
    filename="$3"
    
    if [ ! -s "$temp_file" ]; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Скачанный файл $filename пуст, обновление отменено."
        rm -f "$temp_file"
        return 1
    fi
    
    if [ -f "$dest_file" ]; then
        if cmp -s "$temp_file" "$dest_file"; then
            log_message "$filename не изменился, обновление не требуется."
            rm -f "$temp_file"
            return 0
        fi
        
        # Строки создания бэкапа удалены
        mv "$temp_file" "$dest_file"
        log_message "$filename успешно обновлен."
    else
        mv "$temp_file" "$dest_file"
        log_message "$filename успешно скачан."
    fi
    return 0
}

# --- ОСНОВНОЙ СКРИПТ ---

if [ -f "$LOCK_FILE" ]; then
    echo "Скрипт уже запущен. Выход."
    exit 1
fi
echo $$ > "$LOCK_FILE"
trap 'cleanup 1' INT TERM

rotate_log

log_message "======================================="
log_message "Запуск скрипта скачивания SRS файлов"

if [ ! -d "$DOWNLOAD_DIR" ]; then
    log_message "Создание папки $DOWNLOAD_DIR..."
    mkdir -p "$DOWNLOAD_DIR"
    if [ $? -ne 0 ]; then
        log_message "ОШИБКА: Не удалось создать папку $DOWNLOAD_DIR"
        cleanup 1
    fi
fi

create_empty_files

FIRST_WORKING_MIRROR=$(select_working_mirror)
if [ $? -ne 0 ]; then
    log_message "КРИТИЧЕСКАЯ ОШИБКА: Нет доступных зеркал. Проверьте подключение к интернету."
    cleanup 1
fi

if ! command -v curl >/dev/null 2>&1; then
    log_message "ОШИБКА: curl не найден. Установите его: opkg update && opkg install curl"
    cleanup 1
fi

SUCCESS_COUNT=0
TOTAL_COUNT=0

for file in $FILES; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    DEST_FILE="$DOWNLOAD_DIR/$file"
    TEMP_FILE="$DEST_FILE.tmp"
    download_success=0
    
    log_message "--- Скачивание $file ---"
    
    for mirror in $MIRRORS; do
        URL="$mirror/$file"
        log_message "Попытка скачивания с $mirror"
        
        if curl -sS --connect-timeout 20 --max-time 60 -k -L -o "$TEMP_FILE" "$URL"; then
            log_message "Скачивание с $mirror успешно."
            download_success=1
            break
        else
            log_message "Неудача со скачиванием с $mirror."
        fi
    done
    
    if [ $download_success -eq 1 ]; then
        if safe_update_file "$TEMP_FILE" "$DEST_FILE" "$file"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    else
        log_message "ОШИБКА: Не удалось скачать $file со всех доступных зеркал."
        rm -f "$TEMP_FILE"
    fi
done

log_message "--- Итоги ---"
log_message "Завершено. Успешно обновлено/проверено: $SUCCESS_COUNT из $TOTAL_COUNT файлов."

log_message "Текущее состояние SRS файлов в $DOWNLOAD_DIR:"
ls -lh "$DOWNLOAD_DIR" | grep ".srs"

# Функция очистки бэкапов удалена, так как они больше не создаются

if pgrep -f "homeproxy" >/dev/null 2>&1; then
    log_message "HomeProxy запущен, обновленные файлы правил могут быть использованы."
else
    log_message "HomeProxy не запущен (это нормально, если он не настроен для автозапуска)."
fi

log_message "Скрипт завершил работу."
log_message "======================================="

cleanup 0
