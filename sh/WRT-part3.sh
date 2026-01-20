#!/bin/bash
#=================================================
# Скрипт тюнинга ядра (Kernel config)
# Запускается перед make defconfig
#=================================================

# Проверяем, что переменная KERNEL_PATH установлена (она передается из YML)
# Если нет, выходим (защита от локального запуска без контекста)
if [ -z "$KERNEL_PATH" ]; then
    echo ">>> [Kernel Tweak] KERNEL_PATH не обнаружен. Пропускаем."
    exit 0
fi

# Проверяем, что мы собираем именно Rockchip (NanoPi R5S и др.)
if [[ "$KERNEL_PATH" == *"rockchip"* ]]; then
    
    # Ищем файл конфигурации ядра.
    # Обычно это target/linux/rockchip/armv8/config-6.12 (или 6.6, 6.1)
    # Используем find, чтобы не зависеть от версии ядра.

# Ищем файл конфигурации ядра
KERNEL_CFG_FILE=$(find target/linux/rockchip/armv8 -name "config-*" | head -n 1)

if [ -n "$KERNEL_CFG_FILE" ]; then
    echo ">>> [Kernel Tweak] Применяем твики к: $KERNEL_CFG_FILE"

    # --- 1. Latency & Timer ---
    # Удаляем старые записи, чтобы не было конфликтов
    sed -i '/CONFIG_PREEMPT/d' "$KERNEL_CFG_FILE"
    sed -i '/CONFIG_HZ/d' "$KERNEL_CFG_FILE"
    
    # Добавляем свои
    echo "CONFIG_PREEMPT=y" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_HZ_250=y" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_HZ=250" >> "$KERNEL_CFG_FILE"

    # --- 2. BBR & Network ---
    # Чистим все упоминания TCP алгоритмов и шедулеров
    sed -i '/CONFIG_TCP_CONG/d' "$KERNEL_CFG_FILE"
    sed -i '/CONFIG_NET_SCH_FQ/d' "$KERNEL_CFG_FILE"
    sed -i '/CONFIG_DEFAULT_TCP_CONG/d' "$KERNEL_CFG_FILE"

    # Добавляем свои
    echo "CONFIG_TCP_CONG_BBR=y" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_TCP_CONG_CUBIC=m" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_NET_SCH_FQ=y" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_DEFAULT_BBR=y" >> "$KERNEL_CFG_FILE"
    echo "CONFIG_DEFAULT_TCP_CONG=\"bbr\"" >> "$KERNEL_CFG_FILE"

    # --- 3. CPU Governor ---
    sed -i '/CONFIG_CPU_FREQ_GOV_SCHEDUTIL/d' "$KERNEL_CFG_FILE"
    echo "CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y" >> "$KERNEL_CFG_FILE"

    echo ">>> [Kernel Tweak] Сделано!"
else
    echo ">>> [Kernel Tweak] ОШИБКА: Файл конфигурации не найден!"
fi

else
    echo ">>> [Kernel Tweak] Устройство '$KERNEL_PATH' не Rockchip. Пропускаем твики."
fi
