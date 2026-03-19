Все, что положите в эту директорию, будет в точности скопировано в корень файловой системы (/) прошивки в самом конце сборки, перезаписывая любые существующие файлы.
files: Корневая папка для кастомных файлов.
usr/bin/: Структура внутри files должна точно повторять путь в итоговой прошивки.

# Справочник изменений uci-defaults скрипта

## 1. `/etc/config/firewall`

**Всегда:**
- Удаляется строка `option fullcone '1'` если она есть

**Если модуль `nft_fullcone` найден в ядре:**
- Добавляется обратно `option fullcone '1'` в секцию `defaults`

**Если ipset `dpi_ips` не существует — создаётся секция:**
```
config ipset
    option name 'dpi_ips'
    option match 'net'
    option family 'ipv4'
```
Аналогично для `no_dpi_ips` и `dpi_guest_ips`.

**Только в режиме `switch`:**
- Удаляется вся зона WAN (`zone[1]`)
- Удаляется правило forwarding (`forwarding[0]`)
- Удаляются все `rule` секции
- В зоне LAN устанавливается `input/output/forward = ACCEPT`
- Включается `flow_offloading='1'` и `flow_offloading_hw='1'`

**Чтобы откатить:** восстановить из `/etc/config/firewall` до состояния без этих секций, либо удалить ipset-секции через `uci delete firewall.cfgXXXXXX`.

---

## 2. `/etc/config/system`

**Всегда:**
```
option zonename 'Europe/Moscow'
option hostname 'R6S-oWRT'        ← зависит от модели роутера
```

**Чтобы откатить:**
```sh
uci set system.@system[0].zonename='UTC'
uci set system.@system[0].hostname='OpenWrt'
uci commit system
```

---

## 3. `/etc/config/uhttpd`

**Всегда:**
```
option commonname 'R6S-oWRT'      ← имя в самоподписанном сертификате HTTPS
```

**Чтобы откатить:**
```sh
uci set uhttpd.defaults.commonname='OpenWrt'
uci commit uhttpd
```

---

## 4. `/etc/config/dhcp`

**Если установлен AdGuardHome:**
- `dnsmasq[0].port` меняется с `53` на `54` — dnsmasq уступает порт 53 AdGuardHome
- Удаляется список `server` у dnsmasq (если был)

**Только в режиме `switch`:**
- `lan.ignore = '1'` — отключает выдачу DHCP на LAN
- `lan.dhcpv6 = 'disabled'`
- `lan.ra = 'disabled'`
- `odhcpd.disabled = '1'`
- Удаляется секция `dhcp.wan`

**Чтобы откатить (если AGH удалён):**
```sh
uci set dhcp.@dnsmasq[0].port='53'
uci commit dhcp
```

---

## 5. `/etc/config/adguardhome`

**Если файл существует и бинарник `/usr/bin/AdGuardHome` есть:**
```
option work_dir '/opt/AdGuardHome'
option user 'root'
option group 'root'
```

**Чтобы откатить:**
```sh
uci set adguardhome.config.work_dir='/var/lib/adguardhome'
uci commit adguardhome
```

---

## 6. `/etc/config/attendedsysupgrade`

**Если роутер на OpenWrt** — URL меняется на:
```
option url 'https://sysupgrade.openwrt.org'
```

**Если роутер на ImmortalWrt** — URL меняется на:
```
option url 'https://asu-2.kyarucloud.moe'
```

---

## 7. `/etc/sysctl.conf`

**Если модуль `tcp_bbr` найден в ядре** — в конец файла добавляется:
```
# TCP BBR
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
```
Предварительно удаляются любые старые строки с этими же параметрами.

**Если модуль НЕ найден** — эти строки удаляются из файла (если были).

**Чтобы откатить:**
```sh
sed -i '/# TCP BBR/d; /net\.core\.default_qdisc/d; /net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
```

---

## 8. `/etc/banner`

**Всегда:**
- Бэкап сохраняется в `/etc/banner.bak`
- Слово `WIRELESS` заменяется на `NETWORK`
- Удаляются старые строки `Kernel Version:` и `Build Variant:`
- В конец добавляется:
```
 Kernel Version: 6.12.74
 Build Variant: minimal (2026-03-19)
```

**Чтобы откатить:**
```sh
cp /etc/banner.bak /etc/banner
```

---

## 9. `/etc/apk/repositories.d/distfeeds.list`

**Всегда (если APK):**
- Бэкап в `distfeeds.list.bak`
- Из файла удаляются все строки кроме:
  - строки с `targets` (пакеты для конкретного железа)
  - строки с `base`, `luci`, `packages`, `routing`, `telephony`, `video`
- В конец добавляется строка репозитория kmods вида:
```
https://.../kmods/6.12.74-1-e30f543625.../packages.adb
```

**Чтобы откатить:**
```sh
cp /etc/apk/repositories.d/distfeeds.list.bak /etc/apk/repositories.d/distfeeds.list
```

---

## 10. `/etc/apk/repositories.d/customfeeds.list`

**Всегда (если APK):**
- Файл полностью перезаписывается пустым шаблоном с комментарием

---

## 11. `/etc/init.d/homeproxy`

**Если homeproxy установлен:**
- В функцию `start_service()` добавляется первой строкой:
```sh
. /etc/homeproxy/scripts/update_firewall_rules.sh
```
- То же самое в `stop_service()`

**Чтобы проверить:**
```sh
grep -n 'update_firewall_rules' /etc/init.d/homeproxy
```

**Чтобы откатить:**
```sh
sed -i '/update_firewall_rules/d' /etc/init.d/homeproxy
```

---

## 12. `/etc/homeproxy/scripts/firewall_post.ut`

**Если homeproxy установлен:**
- Строка `const dns_hijacked = uci.get('dhcp', '@dnsmasq[0]', 'dns_redirect') || '0'`
- Заменяется на: `const dns_hijacked = '1'`

Смысл: homeproxy считает что DNS-перехват всегда активен и не трогает правила dnsmasq.

---

## 13. `/etc/homeproxy/scripts/update_firewall_rules.sh`

**Если homeproxy установлен:**
- Файл создаётся целиком (или перезаписывается)
- Содержит логику: если режим TUN или включён Server — добавляет в firewall правила для `fw4_forward.nft` и `fw4_input.nft`, иначе удаляет их

---

## 14. `/usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft`

**Если `/usr/bin/youtubeUnblock` существует:**
- Файл создаётся или перезаписывается целиком
- Содержит правила: блокировка QUIC, цепочка youtubeUnblock с очередью NFQUEUE 537, исключение гостевой сети (`0x42`), исключение `no_dpi_ips`, правило `0x8000` в output

**Чтобы проверить текущее содержимое:**
```sh
cat /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
```

---

## 15. `/usr/share/firewall4/templates/ruleset.uc`

**Если youtubeUnblock настраивается:**
- Строка:
```
meta l4proto { tcp, udp } flow offload @ft;
```
- Меняется на:
```
meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;
```

Смысл: flow offload включается только после 30 пакетов, давая youtubeUnblock время обработать начало соединения.

**Чтобы откатить:**
```sh
sed -i 's/ct original packets ge 30 flow offload @ft/flow offload @ft/' /usr/share/firewall4/templates/ruleset.uc
```

---

## 16. `/etc/init.d/adguardhome`

**Если AdGuardHome установлен — Jail-вариант** (если в файле есть `procd_add_jail`):
- После строки `local verbose=0` добавляется:
```sh
local log_file='/var/AdGuardHome.log'
```
- Строка `--logfile syslog` заменяется на `--logfile "$log_file"`

**Если AdGuardHome установлен — Classic-вариант:**
- После `config_get PID_FILE` добавляется:
```sh
config_get LOG_FILE config logfile '/var/AdGuardHome.log'
```
- К строке запуска добавляется `--logfile "$LOG_FILE"`

---

## 17. `/usr/lib/lua/luci/controller/adguardhome_net.lua`

**Если AdGuardHome установлен:**
- Файл создаётся целиком
- Добавляет пункт меню `Network → AdGuardHome` в LuCI, который открывает `http://IP_роутера:8080`

**Чтобы откатить:**
```sh
rm /usr/lib/lua/luci/controller/adguardhome_net.lua
```

---

## 18. `/usr/lib/sqm/run.sh`

**Если SQM установлен:**
- После строки `export EQDISC_OPTS` вставляется блок который читает `/opt/sqm_custom.conf` и применяет оттуда `iqdisc_opts` и `eqdisc_opts`

---

## 19. `/opt/sqm_custom.conf`

**Если SQM установлен:**
- Файл создаётся с содержимым:
```
option iqdisc_opts 'nat dual-dsthost diffserv4 nowash'
option eqdisc_opts 'nat dual-srchost diffserv4 nowash'
```

---

## 20. `/www/luci-static/bootstrap/cascade.css`

**Всегда (если блок ещё не добавлен):**
- В конец файла добавляется CSS: мобильные устройства получают 100% ширину интерфейса, ПК — 50%

**Чтобы откатить** — удалить блок начиная со строки `/* LuCI Bootstrap: Custom Fullwidth CSS */` до конца файла.

---

## 21. `/usr/share/luci/menu.d/luci-app-filemanager.json`

**Если файл существует:**
- Текст `File Manager` заменяется на `Файловый менеджер`

---

## 22. Файлы создаваемые как побочный эффект

| Файл | Когда | Что |
|------|-------|-----|
| `/root/.setup_completed` | всегда | пустой lock-файл |
| `/root/setup_log.txt` | всегда | лог выполнения скрипта |
| `/etc/banner.bak` | всегда | бэкап оригинального баннера |
| `/opt/AdGuardHome/` | если AGH есть | директория для данных |
| `/etc/group` | если AGH есть и записи нет | строка `adguardhome:x:853:` |
| `/etc/passwd` | если AGH есть и записи нет | строка пользователя adguardhome |

---

## Быстрая проверка после прошивки

``sh
# Лог выполнения
cat /root/setup_log.txt

# Что реально применилось в nftables
nft list ruleset | grep -A5 youtubeUnblock

# Порт dnsmasq (должен быть 54 если AGH установлен)
uci get dhcp.@dnsmasq[0].port

# Hostname
uci get system.@system[0].hostname

# BBR
sysctl net.ipv4.tcp_congestion_control

# kmods в репозиториях
cat /etc/apk/repositories.d/distfeeds.list
``
