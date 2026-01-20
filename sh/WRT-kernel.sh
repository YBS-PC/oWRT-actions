#!/bin/bash
#=================================================
# Скрипт тюнинга ядра (Kernel config)
# Запускается перед make defconfig
#=================================================

# Проверяем, что переменная KERNEL_PATH установлена (она передается из YML)
# Если нет, выходим (защита от локального запуска без контекста)
if [ -z "$KERNEL_PATH" ]; then
    echo ">>> [Kernel Tweak] KERNEL_PATH not defined. Skipping."
    exit 0
fi

# Проверяем, что мы собираем именно Rockchip (NanoPi R5S и др.)
if [[ "$KERNEL_PATH" == *"rockchip"* ]]; then
    
    # Ищем файл конфигурации ядра.
    # Обычно это target/linux/rockchip/armv8/config-6.12 (или 6.6, 6.1)
    # Используем find, чтобы не зависеть от версии ядра.
    KERNEL_CFG_FILE=$(find target/linux/rockchip/armv8 -name "config-*" | head -n 1)

    if [ -n "$KERNEL_CFG_FILE" ]; then
        echo ">>> [Kernel Tweak] Found config: $KERNEL_CFG_FILE"
        echo ">>> [Kernel Tweak] Applying performance settings..."

        cat <<EOF >> "$KERNEL_CFG_FILE"

# --- CUSTOM PERFORMANCE TWEAKS (Applied by WRT-kernel.sh) ---

# 1. Latency & Timer (Отзывчивость)
CONFIG_PREEMPT=y
# CONFIG_PREEMPT_VOLUNTARY is not set
CONFIG_HZ_250=y
CONFIG_HZ_1000=n

# 2. BBR & Network (Скорость и буферы)
CONFIG_TCP_CONG_BBR=y
CONFIG_NET_SCH_FQ=y
CONFIG_TCP_CONG_CUBIC=m
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"

# 3. CPU Governor (Управление частотой)
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y

# ------------------------------------------------------------
EOF
        echo ">>> [Kernel Tweak] Done."
    else
        echo ">>> [Kernel Tweak] WARNING: Rockchip kernel config file not found!"
    fi
else
    echo ">>> [Kernel Tweak] Target '$KERNEL_PATH' is not Rockchip. Skipping tweaks."
fi
