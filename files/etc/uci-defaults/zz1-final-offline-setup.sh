#!/bin/sh

# ===============================================
#      UCI-DEFAULTS ОФЛАЙН-СКРИПТ НАСТРОЙКИ
# ===============================================
# Имя файла: /etc/uci-defaults/zz1-final-offline-setup.sh
# ===============================================

# Логирование теперь можно направить в системный лог или оставить в файле
echo "Running zz1-final-offline-setup.sh" > /root/setup_log.txt
SETUP_LOGFILE="/root/setup_log.txt"
exec > >(tee -a "$SETUP_LOGFILE") 2>&1

# ... (весь ваш код без изменений) ...
# ... (функции, переменные, настройка) ...

# ----------------- НАЧАЛО ВАШЕГО СКРИПТА -----------------
# (Я не буду вставлять весь код снова, он остается тем же)
# --------------------------------------------------------

#################### Проверка служб ####################
color_output magenta "Проверка статуса служб..."
date
sleep 3
color_output yellow "youtubeUnblock:"
service | grep youtubeUnblock | awk '{print $2, $3}'
color_output yellow "adguardhome:"
service | grep adguardhome | awk '{print $2, $3}'
color_output yellow "sqm:"
service | grep sqm | awk '{print $2, $3}'

cat /tmp/sysinfo/model && . /etc/openwrt_release

color_output green "Первоначальная настройка завершена успешно."

# ВАЖНО: Завершаем скрипт с кодом 0 для его автоматического удаления
exit 0
