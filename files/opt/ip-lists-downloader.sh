#!/bin/sh

# IP Lists Updater для OpenWrt 24.10 с fw4
# Скрипт для загрузки и объединения IP списков от различных сервисов

# Конфигурация
OUTPUT_DIR="/etc/luci-uploads"
OUTPUT_FILE="${OUTPUT_DIR}/ip_lists.txt"
TEMP_DIR="/tmp/ip_lists_temp"
LOCK_FILE="/tmp/ip_lists_updater.lock"
LOG_FILE="/var/log/ip_lists_updater.log"

# URL списков IP адресов
URLS="
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/cloudflare.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/cloudfront.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/facebook.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/google.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/telegram.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/twitter.txt
https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/fastly.txt
"

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция очистки при выходе
cleanup() {
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
}

# Проверка доступности инструментов загрузки
check_download_tools() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_TOOL="curl"
        log_message "INFO: Используется curl для загрузки"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_TOOL="wget"
        log_message "INFO: Используется wget для загрузки"
    else
        log_message "ERROR: Не найден curl или wget для загрузки файлов"
        exit 1
    fi
}

# Функция фильтрации IPv4 (убирает IPv6 адреса)
filter_ipv4_only() {
    local input_file="$1"
    local output_file="$2"
    
    # Фильтруем только IPv4 адреса и CIDR блоки
    # Используем более простое регулярное выражение для BusyBox grep
    grep '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' "$input_file" | \
    grep -v ':' > "$output_file"
}

# Функция загрузки файла
download_file() {
    local url="$1"
    local output_file="$2"
    
    if [ "$DOWNLOAD_TOOL" = "curl" ]; then
        curl -fsSL --connect-timeout 30 --max-time 60 --retry 3 --retry-delay 2 \
             --retry-connrefused --location --max-redirs 5 \
             -o "$output_file" "$url"
    else
        # Fallback на wget с повторными попытками
        local attempt=1
        local max_attempts=3
        
        while [ $attempt -le $max_attempts ]; do
            if [ $attempt -gt 1 ]; then
                log_message "INFO: Попытка $attempt из $max_attempts для $url"
                sleep 2
            fi
            
            if wget -q -T 30 -O "$output_file" "$url"; then
                return 0
            fi
            attempt=$((attempt + 1))
        done
        return 1
    fi
}

# Установка обработчика сигналов
trap cleanup EXIT INT TERM

# Проверка на запущенный экземпляр
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if [ -d "/proc/$PID" ]; then
        log_message "ERROR: Скрипт уже запущен (PID: $PID)"
        exit 1
    else
        rm -f "$LOCK_FILE"
    fi
fi

# Создание lock файла
echo $$ > "$LOCK_FILE"

log_message "INFO: Запуск обновления IP списков"

# Проверка доступности инструментов загрузки
check_download_tools

# Создание необходимых директорий
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Счетчик успешных загрузок
SUCCESS_COUNT=0
TOTAL_COUNT=0

# Загрузка каждого списка
for url in $URLS; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    # Извлечение имени файла из URL для временного хранения
    filename=$(basename "$url")
    temp_file="${TEMP_DIR}/${filename}"
    
    log_message "INFO: Загрузка $url"
    
    # Загрузка с помощью выбранного инструмента
    if download_file "$url" "$temp_file"; then
        # Проверка, что файл не пустой и содержит валидные данные
        if [ -s "$temp_file" ] && grep -q '^[0-9]' "$temp_file"; then
            # Фильтрация только IPv4 адресов
            filtered_file="${temp_file}.ipv4"
            filter_ipv4_only "$temp_file" "$filtered_file"
            
            # Проверяем, что после фильтрации остались данные
            if [ -s "$filtered_file" ]; then
                mv "$filtered_file" "$temp_file"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                ipv4_count=$(wc -l < "$temp_file")
                log_message "INFO: Успешно загружен $filename ($ipv4_count IPv4 адресов)"
            else
                log_message "WARNING: После фильтрации IPv4 в файле $filename не осталось данных"
                rm -f "$temp_file" "$filtered_file"
            fi
        else
            log_message "WARNING: Файл $filename пуст или содержит некорректные данные"
            rm -f "$temp_file"
        fi
    else
        log_message "ERROR: Ошибка загрузки $url"
    fi
done

# Проверка успешности загрузок
if [ $SUCCESS_COUNT -eq 0 ]; then
    log_message "ERROR: Не удалось загрузить ни одного списка"
    exit 1
fi

log_message "INFO: Успешно загружено $SUCCESS_COUNT из $TOTAL_COUNT списков"

# Создание временного объединенного файла
TEMP_OUTPUT="${TEMP_DIR}/combined_ip_lists.txt"

# Добавление заголовка с информацией об обновлении
cat > "$TEMP_OUTPUT" << EOF
# IP Lists Combined File (IPv4 Only)
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Sources loaded: $SUCCESS_COUNT/$TOTAL_COUNT
# IPv6 addresses filtered out
# Auto-generated by ip_lists_updater.sh
#
EOF

# Объединение всех загруженных файлов
for temp_file in "$TEMP_DIR"/*.txt; do
    if [ -f "$temp_file" ] && [ "$temp_file" != "$TEMP_OUTPUT" ]; then
        filename=$(basename "$temp_file")
        echo "" >> "$TEMP_OUTPUT"
        echo "# Source: $filename" >> "$TEMP_OUTPUT"
        cat "$temp_file" >> "$TEMP_OUTPUT"
    fi
done

# Подсчет общего количества IPv4 записей
TOTAL_IPS=$(grep -c '^[0-9]' "$TEMP_OUTPUT" 2>/dev/null || echo 0)

# Атомарное обновление основного файла
if mv "$TEMP_OUTPUT" "$OUTPUT_FILE"; then
    log_message "INFO: Файл успешно обновлен: $OUTPUT_FILE ($TOTAL_IPS IPv4 записей)"
    
    # Установка корректных прав доступа
    chmod 644 "$OUTPUT_FILE"
    
    # Опционально: перезагрузка fw4 если используется файл в правилах
    # fw4 reload
    
else
    log_message "ERROR: Ошибка при обновлении файла $OUTPUT_FILE"
    exit 1
fi

log_message "INFO: Обновление завершено успешно"

# Очистка старых логов (оставляем последние 1000 строк)
if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt 1000 ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exit 0

# ============================================================================
# УСТАНОВКА И НАСТРОЙКА:
# ============================================================================

# 1. Сохраните этот скрипт как /opt/ip-lists-downloader.sh
# chmod +x /opt/ip-lists-downloader.sh

# 2. Создайте cron задачу для автоматического обновления:
# echo "0 */6 * * * /opt/ip-lists-downloader.sh" >> /etc/crontabs/root
# /etc/init.d/cron restart

# 3. Для немедленного запуска:
# /opt/ip-lists-downloader.sh

# 4. Просмотр логов:
# tail -f /var/log/ip_lists_updater.log

# 5. Использование в fw4 правилах (пример):
# В /etc/config/firewall добавьте:
# 
# config ipset
#     option name 'blocked_services'
#     option match 'src_net'
#     option loadfile '/etc/luci-uploads/ip_lists.txt'
#
# config rule
#     option name 'Block Services'
#     option src 'lan'
#     option dest '*'
#     option ipset 'blocked_services'
#     option target 'REJECT'