#!/bin/bash

# загрузить скрипт
#source /root/pkg_functions.sh

# Определение типа пакетного менеджера
detect_package_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        echo "Обнаружен APK пакетный менеджер"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        echo "Обнаружен OPKG пакетный менеджер"
    else
        echo "Ошибка: Пакетный менеджер не найден"
        return 1
    fi
    export PKG_MANAGER
}

# Универсальная функция для получения информации о пакете
pkg_info() {
    local package="$1"
    if [ -z "$package" ]; then
        echo "Использование: pkg_info <имя_пакета>"
        return 1
    fi
    
    case "$PKG_MANAGER" in
        "apk")
            apk info "$package"
            ;;
        "opkg")
            opkg info "$package"
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для установки пакетов
pkg_install() {
    local packages="$@"
    if [ -z "$packages" ]; then
        echo "Использование: pkg_install <пакет1> [пакет2] ..."
        return 1
    fi
    
    case "$PKG_MANAGER" in
        "apk")
            apk add $packages
            ;;
        "opkg")
            opkg install $packages
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для установки пакетов с игнорированием подписи
pkg_install_untrusted() {
    local packages="$@"
    if [ -z "$packages" ]; then
        echo "Использование: pkg_install_untrusted <пакет1> [пакет2] ..."
        return 1
    fi
    
    case "$PKG_MANAGER" in
        "apk")
            apk add --allow-untrusted $packages
            ;;
        "opkg")
            # OPKG по умолчанию не проверяет подписи так строго
            opkg install --force-signature $packages
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для обновления списка пакетов
pkg_update() {
    case "$PKG_MANAGER" in
        "apk")
            apk update
            ;;
        "opkg")
            opkg update
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для списка установленных пакетов
pkg_list_installed() {
    case "$PKG_MANAGER" in
        "apk")
            apk list -I
            ;;
        "opkg")
            opkg list-installed
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для удаления пакетов
pkg_remove() {
    local packages="$@"
    if [ -z "$packages" ]; then
        echo "Использование: pkg_remove <пакет1> [пакет2] ..."
        return 1
    fi
    
    case "$PKG_MANAGER" in
        "apk")
            apk del $packages
            ;;
        "opkg")
            opkg remove $packages
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для поиска пакетов
pkg_search() {
    local pattern="$1"
    if [ -z "$pattern" ]; then
        echo "Использование: pkg_search <шаблон>"
        return 1
    fi
    
    case "$PKG_MANAGER" in
        "apk")
            apk search "$pattern"
            ;;
        "opkg")
            opkg find "*$pattern*"
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для обновления пакетов
pkg_upgrade() {
    case "$PKG_MANAGER" in
        "apk")
            apk upgrade
            ;;
        "opkg")
            opkg upgrade
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Универсальная функция для полного обновления (update + upgrade)
pkg_full_upgrade() {
    echo "Обновление списка пакетов..."
    pkg_update
    if [ $? -eq 0 ]; then
        echo "Обновление установленных пакетов..."
        pkg_upgrade
    else
        echo "Ошибка при обновлении списка пакетов"
        return 1
    fi
}

# Универсальная функция для показа версии пакетного менеджера
pkg_version() {
    case "$PKG_MANAGER" in
        "apk")
            apk --version
            ;;
        "opkg")
            opkg --version
            ;;
        *)
            echo "Ошибка: Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Функция помощи
pkg_help() {
    echo "Доступные универсальные функции пакетного менеджера:"
    echo ""
    echo "pkg_info <пакет>              - Информация о пакете"
    echo "pkg_install <пакеты>          - Установка пакетов"
    echo "pkg_install_untrusted <пакеты> - Установка без проверки подписи"
    echo "pkg_update                    - Обновление списка пакетов"
    echo "pkg_list_installed            - Список установленных пакетов"
    echo "pkg_remove <пакеты>           - Удаление пакетов"
    echo "pkg_search <шаблон>           - Поиск пакетов"
    echo "pkg_upgrade                   - Обновление установленных пакетов"
    echo "pkg_full_upgrade              - Полное обновление (update + upgrade)"
    echo "pkg_version                   - Версия пакетного менеджера"
    echo "pkg_help                      - Эта справка"
    echo ""
    echo "Текущий пакетный менеджер: $PKG_MANAGER"
}

# Инициализация при загрузке скрипта
detect_package_manager

# Примеры использования (закомментированы)
# Обновить список пакетов
#pkg_update
# Установить пакеты
#pkg_install curl wget nano
# Установить пакет без проверки подписи
#pkg_install_untrusted /tmp/my-package.ipk
# Показать установленные пакеты
#pkg_list_installed
# Получить информацию о пакете
#pkg_info curl
# Найти пакеты по шаблону
#pkg_search "kernel"
# Удалить пакеты
#pkg_remove wget nano
# Полное обновление системы
#pkg_full_upgrade