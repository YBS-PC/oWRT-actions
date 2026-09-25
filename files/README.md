Все, что положите в эту директорию, будет в точности скопировано в корень файловой системы (/) прошивки в самом конце сборки, перезаписывая любые существующие файлы.
files: Корневая папка для кастомных файлов.
usr/bin/: Структура внутри files должна точно повторять путь в итоговой прошивки.

# Справочник изменений uci-defaults скрипта

Скрипт: `/etc/uci-defaults/zz1-final-offline-setup.sh`.

## 0. Режимы работы
| Режим | Когда | Лог |
|-------|-------|-----|
| `firstboot` | первая загрузка после прошивки (нет `/root/.setup_completed`) | `/root/setup_log.txt` |
| `maintenance` | ручной запуск сохранённой копии, например после `apk upgrade` | `/root/setup_log_maintenance.txt` |

Пометка **(firstboot)** ниже означает, что пункт выполняется только на первой загрузке.
В обоих режимах скрипт в конце создаёт `/root/.setup_completed` и перезагружает роутер через 120 секунд.

---

## 1. `/etc/config/firewall`
**Всегда:**
- Удаляется строка `option fullcone '1'`; если модуль `nft_fullcone` есть в ядре — `defaults.fullcone='1'` ставится обратно
- Создаются наборы адресов (ipset) fw4, если их ещё нет:

| Имя | match | loadfile | Назначение |
|-----|-------|----------|------------|
| `dpi_ips` | `dest_net` | `/etc/luci-uploads/dpi_ip_list.txt` | адреса для youtubeUnblock |
| `bypass_ips` | `dest_net` | `/etc/luci-uploads/bypass_ips.txt` | обход homeproxy (метка `0x64`) и очереди youtubeUnblock |
| `bypass_local` | `src_net` | — | обход очереди youtubeUnblock по адресу источника |

  Все наборы `family 'ipv4'`. Пустые loadfile-файлы создаются заранее: fw4 читает их на каждом reload.
  Если секция осталась от старой версии скрипта без `loadfile` — он дописывается.

**Если homeproxy НЕ установлен:**
- Удаляются include-секции `homeproxy_post`, `homeproxy_forward`, `homeproxy_input` (остаются после sysupgrade с другого варианта)

**Только в режиме `switch` (firstboot):**
- Удаляется вся зона WAN (`zone[1]`) и правило `forwarding[0]`
- Удаляются все `rule` секции
- В зоне LAN устанавливается `input/output/forward = ACCEPT`
- Включается `flow_offloading='1'` и `flow_offloading_hw='1'`

**Чтобы откатить ipset:** `uci delete firewall.cfgXXXXXX` (id смотреть в `uci show firewall | grep ipset`), затем `uci commit firewall`.

## 2. `/etc/config/system`
**Всегда:**
```
option zonename 'Europe/Moscow'
```
**(firstboot):**
```
option hostname 'R6S-oWRT'        ← <модель>-oWRT / -iWRT; в switch: <модель>-switch
```

**Чтобы откатить:**
```sh
uci set system.@system[0].zonename='UTC'
uci set system.@system[0].hostname='OpenWrt'
uci commit system
```

## 3. `/etc/config/uhttpd`
**(firstboot):**
```
option commonname 'R6S-oWRT'      ← имя в самоподписанном сертификате HTTPS
```

**Чтобы откатить:**
```sh
uci set uhttpd.defaults.commonname='OpenWrt'
uci commit uhttpd
```

## 4. `/etc/config/dhcp`
**Если установлен AdGuardHome:**
- `dnsmasq[0].port` меняется с `53` на `54` — dnsmasq уступает порт 53 AdGuardHome
- Удаляется список `server` у dnsmasq (если был)

**Только в режиме `switch` (firstboot):**
- `lan.ignore = '1'` — отключает выдачу DHCP на LAN
- `lan.dhcpv6 = 'disabled'`, `lan.ra = 'disabled'`
- `odhcpd.disabled = '1'`, сервис odhcpd отключается
- Удаляется секция `dhcp.wan`

**Чтобы откатить (если AGH удалён):**
```sh
uci set dhcp.@dnsmasq[0].port='53'
uci commit dhcp
```

## 5. `/etc/config/network` — только `switch` (firstboot)
- Удаляются интерфейсы `lan`, `wan`, `wan6`
- Все физические порты собираются в мост `br-lan` (STP, IGMP snooping, multicast querier, без IPv6)
- `lan` получает адрес по DHCP, `packet_steering='2'`, ULA-префикс удаляется

## 6. AdGuardHome
**Если есть `/usr/bin/AdGuardHome` и `/etc/config/adguardhome`:**
- `/etc/config/adguardhome`:
```
option work_dir '/opt/AdGuardHome'
option user 'root'
option group 'root'
```
- Создаются группа и пользователь `adguardhome` (uid/gid 853), если их нет
- `/etc/init.d/adguardhome`: `--logfile syslog` → `--logfile /var/AdGuardHome.log`
- `/etc/adguardhome/adguardhome.yaml` — upstream DNS зависит от варианта:
  - `forkop` → `127.0.0.42:53` (DNS forkop sing-box), плюс `forkop.settings.dont_touch_dhcp='1'`
  - остальные → `127.0.0.1:5333` (DNS homeproxy sing-box)
- `/usr/lib/lua/luci/controller/adguardhome_net.lua` — пункт меню `Network → AdGuardHome` (редирект на `http://IP_роутера:8080`)

**Чтобы откатить:**
```sh
uci set adguardhome.config.work_dir='/var/lib/adguardhome'
uci commit adguardhome
rm /usr/lib/lua/luci/controller/adguardhome_net.lua
```

## 7. homeproxy
**Если установлен (`/etc/init.d/homeproxy`):**
- `/etc/homeproxy/scripts/firewall_post.ut`: строка
  `const dns_hijacked = uci.get('dhcp', '@dnsmasq[0]', 'dns_redirect') || '0'`
  заменяется на `const dns_hijacked = '1'` — homeproxy не трогает правила dnsmasq
- `/etc/homeproxy/scripts/generate_client.uc`: в `config.experimental` добавляется
  `clash_api: { external_controller: '0.0.0.0:9090', external_ui: '/opt/yacd' }`
- `/etc/homeproxy/scripts/update_firewall_rules.sh` создаётся целиком: в режиме TUN или при включённом Server добавляет в firewall include `fw4_forward.nft` / `fw4_input.nft`, иначе удаляет их
- `/etc/init.d/homeproxy`: в `start_service()` и `stop_service()` добавляется строка
```sh
. /etc/homeproxy/scripts/update_firewall_rules.sh
```
- `/etc/nftables.d/bypass_homeproxy_ips.nft` (если нет): цепочка ставит метку `0x64` пакетам к адресам из `@bypass_ips`

**Если НЕ установлен:** файл `/etc/nftables.d/bypass_homeproxy_ips.nft` удаляется.

**Чтобы проверить / откатить init:**
```sh
grep -n 'update_firewall_rules' /etc/init.d/homeproxy
sed -i '/update_firewall_rules/d' /etc/init.d/homeproxy
```

## 8. Панель YACD (вместе с homeproxy)
- `/opt/yacd/index.html` — заглушка «YACD ещё не установлена» (с меткой `/opt/yacd/.stub`), чтобы sing-box не качал панель сам
- `/usr/bin/yacd-install.sh` + задание cron `*/10` в `/etc/crontabs/root`: когда появится интернет, качает YACD-meta в `/opt/yacd` и снимает себя из cron
- `/opt/yacd` добавляется в `/etc/sysupgrade.conf`
- `/usr/lib/lua/luci/controller/yacd.lua` — пункт меню `Network → YACD` (редирект на `http://IP_роутера:9090/ui/`)

## 9. `/usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft`
**Если `/usr/bin/youtubeUnblock` существует** — файл перезаписывается целиком:
- reject UDP/443 к адресам `@dpi_ips` (блокировка QUIC)
- цепочка `youtubeUnblock`: пропуск гостевой сети (метка `0x42`), пропуск `@bypass_ips` (по адресу назначения) и `@bypass_local` (по адресу источника), очередь NFQUEUE 537 для TCP/443 и UDP к `@dpi_ips`
- правило `0x8000` в `output`

**Если НЕ установлен** — файл удаляется (очередь 537 никто не слушает).

**Чтобы проверить текущее содержимое:**
```sh
cat /usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft
```

## 10. `/usr/share/firewall4/templates/ruleset.uc`
**Всегда:**
- Строка `meta l4proto { tcp, udp } flow offload @ft;`
- Меняется на `meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;`

Смысл: flow offload включается только после 30 пакетов, давая youtubeUnblock время обработать начало соединения.

**Чтобы откатить:**
```sh
sed -i 's/ct original packets ge 30 flow offload @ft/flow offload @ft/' /usr/share/firewall4/templates/ruleset.uc
```

## 11. Прочие сервисы
- **Passwall2** (вариант `passwall`, firstboot): `dns_redirect='0'`, `dns_shunt='closed'`, `remote_dns` и `china_dns` = `127.0.0.1:53`, `adblock='0'`, `enabled='1'`
- **forkop** (если есть `/etc/config/forkop`): `forkop.settings.exclude_ntp='1'` — NTP мимо прокси
- **internet-detector**: сервис отключается, `START=99`
- **phy-leds**: сервис отключается
- **SQM** (если установлен):
  - `/opt/sqm_custom.conf` создаётся, если его ещё нет:
```
option iqdisc_opts 'nat dual-dsthost diffserv4 nowash'
option eqdisc_opts 'nat dual-srchost diffserv4 nowash'
```
  - `/usr/lib/sqm/run.sh`: после `export EQDISC_OPTS` вставляется блок, читающий этот файл
  - SQM перезапускается, если включён, иначе сервис отключается
- **`/etc/config/attendedsysupgrade`**: на OpenWrt URL → `https://sysupgrade.openwrt.org`, на ImmortalWrt → `https://asu-2.kyarucloud.moe`

## 12. `/etc/sysctl.conf`
**Если модуль `tcp_bbr` найден в ядре** — старые строки с этими параметрами удаляются, в конец файла добавляется:
```
# TCP BBR
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
```

**Чтобы откатить:**
```sh
sed -i '/# TCP BBR/d; /net\.core\.default_qdisc/d; /net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
```

## 13. Пакетный менеджер
**APK:**
- `/etc/apk/arch` — дописывается архитектура из `/etc/os-release`, если её нет
- Ключи `/root/apps/*.pem` копируются в `/etc/apk/keys/` (положите ключ стороннего репозитория в `files/root/apps/`)

**`distfeeds.list` / `distfeeds.conf`:**
- Бэкап `*.bak` делается один раз (на повторных прогонах оригинал не затирается)
- Оставляются только строки с `targets` и `packages/<arch>/(base|luci|packages|routing|telephony|video)`
- APK: старые строки `/kmods/` удаляются, добавляется актуальная для установленного ядра:
```
https://.../kmods/6.12.74-1-e30f543625.../packages.adb
```

**`customfeeds.list` / `customfeeds.conf` (firstboot):** перезаписывается пустым шаблоном.

**Чтобы откатить:**
```sh
cp /etc/apk/repositories.d/distfeeds.list.bak /etc/apk/repositories.d/distfeeds.list
```

## 14. Локальные бинарники из `/root/apps/`
| Файл | Куда |
|------|------|
| `sing-box.tar.gz`, `sing-box` | `/usr/bin/sing-box` (сервис sing-box останавливается) |
| `AdGuardHome` | `/usr/bin/AdGuardHome` (сервис останавливается) |
| `speedtest.tar.gz`, `speedtest` | `/usr/bin/speedtest` |

Исходный файл удаляется только после успешной установки.

## 15. `/etc/banner`
- Бэкап `/etc/banner.bak` (один раз)
- `W I R E L E S S` заменяется на `N E T W O R K`
- Старые строки `Kernel Version:` и `Build Variant:` заменяются новыми:
```
 Kernel Version: 6.12.74
 Build Variant: homeproxy (2026-03-19)
```

**Чтобы откатить:**
```sh
cp /etc/banner.bak /etc/banner
```

## 16. Время
- `hwclock -s -u` (если есть RTC)
- При доступном интернете — разовая синхронизация `ntpd` по IP-адресам, затем `hwclock -w -u`
- Файлы в `/etc` с mtime из будущего получают текущее время (иначе sysfixtime отбросит часы вперёд)

## 17. `/usr/share/luci/menu.d/luci-app-filemanager.json`
**Если файл существует:** `File Manager` → `Файловый менеджер`

## 18. Файлы, создаваемые как побочный эффект
| Файл | Когда | Что |
|------|-------|-----|
| `/root/.setup_completed` | всегда | lock-файл, признак режима maintenance |
| `/root/setup_log.txt` | firstboot | лог выполнения скрипта |
| `/root/setup_log_maintenance.txt` | maintenance | лог выполнения скрипта |
| `/etc/banner.bak` | всегда | бэкап оригинального баннера |
| `/etc/luci-uploads/*.txt` | всегда | пустые loadfile для ipset |
| `/opt/AdGuardHome/` | если AGH есть | директория для данных |
| `/opt/yacd/` | если homeproxy есть | панель YACD (или заглушка) |
| `/etc/group`, `/etc/passwd` | если AGH есть и записи нет | пользователь и группа adguardhome |

Также в прошивке лежит `/root/pkg_functions.sh` — универсальные функции для apk/opkg:
```sh
. /root/pkg_functions.sh
pkg_help
```

## Быстрая проверка после прошивки
### Лог выполнения
```
cat /root/setup_log.txt
```
### Что реально применилось в nftables
```
nft list ruleset | grep -A5 youtubeUnblock
```
### Порт dnsmasq (должен быть 54 если AGH установлен)
```
uci get dhcp.@dnsmasq[0].port
```
### Hostname
```
uci get system.@system[0].hostname
```
### BBR
```
sysctl net.ipv4.tcp_congestion_control
```
### kmods в репозиториях
```
cat /etc/apk/repositories.d/distfeeds.list
```
