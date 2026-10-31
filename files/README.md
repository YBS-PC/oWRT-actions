Все, что положите в эту директорию, будет в точности скопировано в корень файловой системы (/) прошивки в самом конце сборки, перезаписывая любые существующие файлы. Исключение — описания `README.md` (этот файл и `root/apps/README.md`): workflow их в образ не кладёт.
files: Корневая папка для кастомных файлов.
usr/bin/: Структура внутри files должна точно повторять путь в итоговой прошивки.

# Справочник изменений uci-defaults скрипта

Скрипт: `/etc/uci-defaults/zz1-final-offline-setup.sh`.

## 0. Режимы работы
| Режим | Когда | Лог |
|-------|-------|-----|
| `firstboot` | первая загрузка после прошивки (нет `/etc/zz1_setup_completed`), в том числе после прошивки с сохранением настроек | `/root/setup_log.txt` |
| `maintenance` | ручной запуск сохранённой копии, например после `apk upgrade` | `/root/setup_log_maintenance.txt` |

Пометка **(firstboot)** ниже означает, что пункт выполняется только на первой загрузке.
В обоих режимах скрипт в конце создаёт `/etc/zz1_setup_completed` и перезагружает роутер через 120 секунд.
Lock-файл лежит в `/etc`, а не в `/root`: `/root` часто целиком вписан в `/etc/sysupgrade.conf`
(исключений этот файл не поддерживает), и lock переживал бы прошивку. Файл в `/etc` в бэкап не
попадает, поэтому после любой прошивки (с сохранением настроек или без) скрипт идёт как `firstboot`.
Старый `/root/.setup_completed` скрипт удаляет.

---

## 1. `/etc/config/firewall`
**Всегда:**
- Удаляется строка `option fullcone '1'`; если модуль `nft_fullcone` есть в ядре — `defaults.fullcone='1'` ставится обратно
- Создаются наборы адресов (ipset) fw4, если их ещё нет:

| Имя | match | loadfile | Назначение |
|-----|-------|----------|------------|
| `dpi_ips` | `dest_net` | `/etc/luci-uploads/dpi_ip_list.txt` | адреса для youtubeUnblock |
| `bypass_ips` | `dest_net` | `/etc/luci-uploads/bypass_ips.txt` | исключения: метка `0x64` (мимо homeproxy) и пропуск очереди youtubeUnblock для UDP кроме 443 (порт 443 идёт в очередь всегда) |
| `bypass_local` | `src_net` | — | пропуск очереди youtubeUnblock по адресу источника |

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
- Все физические порты собираются в мост `br-lan` (IGMP snooping, multicast querier, без IPv6; STP выключен —
  у коммутатора один uplink, а с STP каждый поднявшийся порт ~17 с не пропускает трафик)
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
- `/etc/init.d/adguardhome`: `--logfile syslog` (или `/var/AdGuardHome.log` прежних версий) → `--logfile /tmp/log/AdGuardHome.log` — журнал в файл, а не в syslog
- `/etc/config/adguardhome`: `list jail_mount_rw '/tmp/log'` — каталог журнала доступен для записи из песочницы ujail
- `/etc/adguardhome/adguardhome.yaml` — upstream DNS зависит от варианта:
  - `forkop`, `trafira`, `podkop`, `netshift` → `127.0.0.42:53` (DNS их sing-box), плюс `<вариант>.settings.dont_touch_dhcp='1'`
  - forkop 2.x вместо `dont_touch_dhcp` (опции нет: dnsmasq он не трогает) получает `forkop.settings.intercept_device_dns='0'` (наш патч 002) и `forkop.settings.unmatched_dns_mode='router'`. Без перехвата запросы клиентов идут в AGH, и он видит каждого; AGH пересылает их на `127.0.0.42:53`, где домены секций получают FakeIP, а остальные отвечают DNS-серверы forkop (правило «вне секций → роутер» на этом входе не действует, петли нет). Запросы на чужой DNS (8.8.8.8 и т.п.) патч тоже отправляет в AGH. Перехватываются только устройства из фильтров секций (им нужен ответ по адресу клиента) и сам роутер; их DNS вне секций с `router` уходит в AGH. FakeIP-соединения исключённых устройств патч 002 отправляет через sing-box напрямую. Без патча (сборка без `apply_patches`) опция ни на что не влияет, и клиенты в журнале AGH видны как `127.0.0.1`. forkop 2.x отличается от forkop-mod (ветка 1.x) по опции `unmatched_dns_mode` в `/usr/share/forkop/default-config`
  - `xray` → `127.0.0.1:5300` (DNS-вход Xray luci-app-xray)
  - `passwall`, `v2raya` → `127.0.0.1:54` (dnsmasq): passwall2 при `dns_redirect=0` вписывает в dnsmasq свои правила (по умолчанию — DNS-вход своего Xray, порт которого выбирается при каждом запуске); v2rayA при занятом AGH порте 53 свой DNS не поднимает
  - остальные → `127.0.0.1:5333` (DNS homeproxy sing-box)
  - адрес, оставшийся от другого варианта (любой из четырёх), заменяется. Меняется только пункт списка `upstream_dns` целиком: `local_ptr_upstreams` и правило `[/lan/arpa/local/]127.0.0.1:54` не трогаются
- `/usr/lib/lua/luci/controller/adguardhome_net.lua` — пункт меню `Network → AdGuardHome` (редирект на `http://IP_роутера:8080`)

**Чтобы откатить:**
```sh
uci set adguardhome.config.work_dir='/var/lib/adguardhome'
uci commit adguardhome
rm /usr/lib/lua/luci/controller/adguardhome_net.lua
```

## 7. homeproxy
**Если установлен (`/etc/init.d/homeproxy`, в том числе Re:HomeProxy):**
- `/etc/homeproxy/scripts/firewall_post.ut`: строка
  `const dns_hijacked = uci.get('dhcp', '@dnsmasq[0]', 'dns_redirect') || '0'`
  заменяется на `const dns_hijacked = '1'` — homeproxy не трогает правила dnsmasq
- Доработки патчей 010 и 011 проверяются по меткам в файлах: если пакет
  собран без патчей или обновлён из фида (zz1 запускают и после
  `apk upgrade`), в файлы вписывается тот же код, что и в патчах; если
  доработка уже есть, файл не трогается. Повторный запуск ничего не меняет.
- Clash API (панель YACD на `:9090`):
  - luci-app-homeproxy: в `/etc/homeproxy/scripts/generate_client.uc` нет
    `clash_api_controller` → вписывается код патча 010 (чтение опций
    `clash_api_controller` / `clash_api_ui` / `clash_api_secret` и блок
    `config.experimental.clash_api`); строка `clash_api: {...}` прежних
    версий zz1 удаляется. В `/etc/init.d/homeproxy` нет `clash_api_ui` →
    после первой строки `procd_add_jail_mount "/etc/TZ"` (клиент)
    вписывается подключение каталога панели в ujail;
  - затем задаются опции `homeproxy.infra.clash_api_controller='0.0.0.0:9090'`
    и `homeproxy.infra.clash_api_ui='/opt/yacd'`, если адрес ещё не задан
    (свой адрес или `clash_api_secret` не перезаписываются);
  - Re:HomeProxy (вариант `rehomeproxy`): блок `clash_api` у него уже есть с
    `127.0.0.1:9090` — адрес меняется на `0.0.0.0:9090` и добавляется
    `external_ui: '/opt/yacd'`.
- Include-секции fw4 `homeproxy_forward` / `homeproxy_input` (в том числе
  Re:HomeProxy): в `/etc/init.d/homeproxy` нет `: > "$RUN_DIR/fw4_forward.nft"`
  → перед `ucode "$HP_DIR/scripts/firewall_pre.uc"` вписывается код патча 011
  (пустые `fw4_forward.nft`, `fw4_input.nft`, `fw4_post.nft`). Вызовы
  `update_firewall_rules.sh` прежних версий zz1 убираются из init, сам
  скрипт удаляется; секции добавляются, если их удалил этот скрипт.
- `/etc/nftables.d/bypass_homeproxy_ips.nft` (если нет): цепочка ставит метку `0x64` пакетам к адресам из `@bypass_ips`

**Если НЕ установлен:** файл `/etc/nftables.d/bypass_homeproxy_ips.nft` удаляется.

**Чтобы проверить, что доработки на месте:**
```sh
grep -c 'clash_api_controller' /etc/homeproxy/scripts/generate_client.uc
grep -n 'clash_api_ui\|fw4_forward.nft' /etc/init.d/homeproxy
```

## 8. Панель YACD (вместе с homeproxy)
- `/opt/yacd/index.html` — заглушка «YACD ещё не установлена» (с меткой `/opt/yacd/.stub`), чтобы sing-box не качал панель сам
- `/usr/bin/yacd-install.sh` + задание cron `*/10` в `/etc/crontabs/root`: когда появится интернет, качает YACD-meta в `/opt/yacd` и снимает себя из cron
- `/opt/yacd` добавляется в `/etc/sysupgrade.conf`
- `/usr/lib/lua/luci/controller/yacd.lua` — пункт меню `Network → YACD` (редирект на `http://IP_роутера:9090/ui/`)

## 9. `/usr/share/nftables.d/ruleset-post/537-youtubeUnblock.nft`
**Если `/usr/bin/youtubeUnblock` существует** — файл перезаписывается целиком:
- reject UDP/443 к адресам `@dpi_ips` (клиент переходит с QUIC на TCP)
- метка и номер очереди берутся из настроек youtubeUnblock (`packet_mark`, `queue_num`; по умолчанию 32768 = `0x8000`
  и 537). Пакет ставит правило на `0x8000`, и с другой меткой (например 524288 из issue #185 пакета для GL-iNet)
  оно не срабатывало. Если метку или очередь потом поменять в LuCI, zz1 надо запустить снова
- цепочка `youtubeUnblock` по порядку: пропуск пакетов, которые youtubeUnblock отправляет сам (с его меткой: они
  уходят сразу, а не ждут в очереди за обрабатываемым пакетом, и порядок отправки сохраняется); пропуск гостевой сети (метка `0x42`) и `@bypass_local` (по адресу источника);
  очередь NFQUEUE для TCP/443 и UDP/443 (QUIC) к **любым** адресам; пропуск `@bypass_ips` (по адресу назначения);
  очередь для UDP на прочие порты к `@dpi_ips`.
  Порт 443 идёт в очередь до проверки `@bypass_ips`: адрес может быть в `@bypass_ips` и не быть в `@dpi_ips`.
  Какие соединения обрабатывать, приложение решает само по SNI (`--sni-domains`), остальные пропускает без
  изменений. В очередь уходят только первые пакеты соединения (TCP — 20, UDP — 8).
  Для QUIC по SNI фильтрует только режим `--udp-filter-quic=parse`; при `all` youtubeUnblock обрабатывает начало
  всех QUIC-соединений
- в начале `output` — приём пакетов с меткой youtubeUnblock: для conntrack они вне состояния и не должны отбрасываться
- в начале `mangle_output` — то же самое, до прокси, который забирает UDP самого роутера: homeproxy в режиме tproxy
  ставит такому UDP без своей метки метку 101 и заворачивает его в sing-box. Он перезаписывал метку пакетов
  youtubeUnblock: они уходили в sing-box, а не в WAN, а youtubeUnblock, не видя своей метки, снова брал свои же
  пакеты в очередь

В `/etc/init.d/youtubeUnblock` добавляется `procd_set_param respawn` (если его ещё нет): init пакета
запускает программу без перезапуска, и после падения очередь 537 (с `bypass`) пропускала трафик без
обработки до перезагрузки. procd перезапускает до 5 раз подряд, если процесс живёт меньше часа.

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
- **Passwall2** (вариант `passwall`, firstboot): `dns_redirect='0'`, `enabled='1'`. В обоих режимах: `remote_dns='127.0.0.1:53'`, который ставили прежние версии zz1, меняется на `1.1.1.1` (удалённый DNS ходит через узел, адрес роутера там недоступен), опции passwall 1 `dns_shunt`, `china_dns`, `adblock` удаляются
- **luci-app-xray** (вариант `xray`, firstboot, только если в `xray_core` остались значения пакета по умолчанию: GeoIP direct `cn`, bypassed `geosite:cn`, Fast DNS не задан): они заменяются на GeoIP direct `ru` (IPv4 и IPv6), `geosite:category-ru` и Fast DNS `77.88.8.8:53`; Forwarded/Blocked domain rules не трогаются. Если нет `/usr/share/xray/geoip.dat` или `geosite.dat`, в лог пишется ошибка
- **forkop, trafira, podkop, netshift** (если есть `/etc/config/forkop`, `/etc/config/trafira`, `/etc/config/podkop` или `/etc/config/netshift`): `<пакет>.settings.exclude_ntp='1'` — NTP мимо прокси (кроме forkop 2.x: опции нет, NTP-серверы роутера он резолвит через bootstrap DNS, а трафик роутера в секции не берёт без пункта «Система»); если установлен youtubeUnblock — ещё `<пакет>.settings.disable_quic='1'`: QUIC клиента к адресам FakeIP (198.18.0.0/15) не попадает под правило `reject` youtubeUnblock и шёл бы через sing-box в очередь 537, а так sing-box его отклоняет и браузер идёт по TCP
- **internet-detector**: сервис отключается, `START=99`; режим «Service» (`internet-detector.config.mode='1'`, так в конфиге пакета) меняется на «Web UI only» (`'2'`): без работающей службы в режиме Service индикатор в LuCI навсегда «Undefined», а в Web UI only детектор запускается, пока открыт LuCI. Выбранные вручную `0` и `2` не меняются
- **phy-leds**: сервис отключается
- **SQM** (если установлен, вариант `clear`). Скрипт очередей `/usr/lib/sqm/cake_ctinfo.qos` лежит в прошивке
  (`files/usr/lib/sqm/`), в пакет sqm-scripts не входит, поэтому `run.sh` не патчится и `apk upgrade` его не затирает:
  - во всех очередях `script='piece_of_cake.qos'` меняется на `cake_ctinfo.qos` (прежние zz1 и так превращали
    piece_of_cake в diffserv4 через `/opt/sqm_custom.conf`)
  - загрузчик `/opt/sqm_custom.conf`, вставленный в `/usr/lib/sqm/run.sh` прежними zz1, удаляется
  - если `/opt/sqm_custom.conf` есть — его строки переносятся в `iqdisc_opts`/`eqdisc_opts` очередей, где свои опции ещё
    не заданы (плюс `qdisc_advanced='1'`, `qdisc_really_really_advanced='1'`, иначе LuCI сотрёт опции при сохранении),
    файл переименовывается в `/opt/sqm_custom.conf.migrated`
  - `/etc/nftables.d/10-priority-mangle.nft` создаётся, если его нет: шаблон правил приоритета, все строки закомментированы
  - если модуля `act_ctinfo` нет — запись в лог (приоритеты останутся только на отдаче)
  - SQM перезапускается, если включён, иначе сервис отключается

  **Что делает `cake_ctinfo.qos`.** Это `piece_of_cake.qos` с опциями `diffserv4 dual-srchost` на отдаче и
  `diffserv4 dual-dsthost ingress` на загрузке (опции из LuCI «Qdisc options» идут после и перекрывают их).
  Фильтр на входе WAN перед перенаправлением в IFB выполняет
  `action ctinfo dscp 0xfc000000 0x01000000`: DSCP, сохранённый правилом nftables в `ct mark` соединения, ставится
  и входящим пакетам, поэтому загрузка делится по тем же уровням, что и отдача. Без `kmod-sched-ctinfo` фильтр
  ставится без ctinfo, как в piece_of_cake.

  | Уровень cake | DSCP | `ct mark` |
  |--------------|------|-----------|
  | Voice — высший, без очереди до 25% канала | EF | `0xb9000000` |
  | Video — нормальный, преимущество до 50% | AF21 | `0x49000000` |
  | Best Effort — низкий | CS0 | `0x01000000` |
  | Bulk — наименьший | LE | `0x05000000` |

  Пример правил (`/etc/nftables.d/10-priority-mangle.nft`, адреса свои; `comment` — последним, после `return`):
```
chain priority_mangle_prerouting_dscp {
	type filter hook prerouting priority mangle; policy accept;
	ip saddr 192.168.1.10 meta l4proto udp counter ip dscp set ef ct mark set 0xb9000000 return comment "Console games: Voice"
	ip saddr 192.168.1.0/24 counter ip dscp set af21 ct mark set 0x49000000 return comment "LAN: Video"
	ip saddr 192.168.2.0/24 counter ip dscp set cs0 ct mark set 0x01000000 return comment "Guest: Best Effort"
	ip saddr 192.168.3.0/24 counter ip dscp set lephb ct mark set 0x05000000 return comment "IoT: Bulk"
}
```
  Проверка: `fw4 check && service firewall restart`; `tc filter show dev <wan> parent ffff:` — есть `ctinfo`;
  `tc -s qdisc show dev ifb4<wan>` — под нагрузкой пакеты во всех четырёх колонках.

  **Чтобы откатить:** `uci set sqm.<очередь>.script='piece_of_cake.qos'; uci commit sqm; service sqm restart`.
- **`/etc/config/attendedsysupgrade`**: `server.url` через `uci set` — на OpenWrt `https://sysupgrade.openwrt.org`, на ImmortalWrt `https://sysupgrade.kyarucloud.moe` (адрес из пакета ImmortalWrt; прежний `asu-2.kyarucloud.moe` не отвечает)

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

**Если в ядре есть MPTCP** (`/proc/sys/net/mptcp/enabled`) и в файле ещё нет
строки `net.mptcp.enabled`, в конец добавляется:
```
# MPTCP
net.mptcp.enabled = 0
```
Самому роутеру Multipath TCP не нужен, а транзитный трафик устройств эта
настройка не затрагивает. Зато sing-box и Xray (Go 1.24+) по умолчанию слушают
с MPTCP, и MPTCP-соединение устройства из LAN (так делают, например, iPhone
для сервисов Apple), попавшее на вход redirect, обрывается: ядро не отдаёт для
него исходный адрес, в журнале `get redirect destination: operation not
supported`. Без MPTCP устройство само переходит на обычный TCP. Опция
«MultiPath TCP» в узлах и серверах homeproxy при этом не работает.

**Чтобы оставить MPTCP включённым:** заменить строку на
`net.mptcp.enabled = 1` (zz1 при следующей прошивке её не тронет) и выполнить
`sysctl -w net.mptcp.enabled=1`, затем перезапустить прокси.

## 13. Пакетный менеджер
**APK:**
- `/etc/apk/arch` — дописывается архитектура из `/etc/os-release`, если её нет
- Ключи `/root/apps/*.pem` копируются в `/etc/apk/keys/` (положите ключ стороннего репозитория в `files/root/apps/`)

**`distfeeds.list` / `distfeeds.conf`:**
- Бэкап `*.bak` делается один раз (на повторных прогонах оригинал не затирается)
- Оставляются только строки с `targets` и `packages/<arch>/(base|luci|packages|routing|telephony|video)`
- APK: старые строки `/kmods/` удаляются, добавляется актуальная для установленного ядра
  (`kernel-<версия>~<хеш>-r<release>` → папка `<версия>-<release>-<хеш>`, как в `include/feeds.mk` OpenWrt):
```
https://downloads.openwrt.org/releases/25.12.6/targets/rockchip/armv8/kmods/6.12.112-1-5eacf764.../packages.adb
```
  Адрес — тот же сервер, что в строке `targets` (его ставит сборка OpenWrt, `CONFIG_VERSION_REPO`), даже если хеш
  при сборке взят с зеркала: на зеркалах те же папки. Если в `/etc/build_kernel_hash` (пишет шаг Kernel Hash
  при сборке) стоит `local` — прошивка собрана с локальным хешем ядра, официальной папки kmods для неё нет, и
  строка не добавляется (иначе `apk update` падал бы на ней).

**`customfeeds.list` / `customfeeds.conf` (firstboot):** перезаписывается пустым шаблоном.

**Чтобы откатить:**
```sh
cp /etc/apk/repositories.d/distfeeds.list.bak /etc/apk/repositories.d/distfeeds.list
```

## 14. Локальные бинарники из `/root/apps/`
| Файл | Куда |
|------|------|
| `sing-box.tar.gz`, `sing-box` | `/usr/bin/sing-box` (сервис sing-box останавливается). Если стоит пакет `sing-box-forkop` (ядро forkop 2.x), не ставится: forkop на другом sing-box не запускается, файл остаётся в `/root/apps` |
| `AdGuardHome` | `/usr/bin/AdGuardHome` (сервис останавливается) |
| `speedtest.tar.gz`, `speedtest` | `/usr/bin/speedtest` |

Исходный файл удаляется только после успешной установки.

**Закрепление пакетов с подменённым бинарником.** Скачанный при сборке sing-box (`sb` = версия, extended,
podkop-engine) и AdGuard Home (`agh` = latest), как и бинарники из `/root/apps/`, лежат поверх пакета из
фида: пакет в базе своей версии, а `/usr/bin` — другой. `apk upgrade` поставил бы новый пакет и вернул бинарник
фида. Поэтому, если `sing-box version` / `AdGuardHome --version` не совпадает с версией пакета `sing-box` /
`adguardhome`, пакет закрепляется на установленной версии:
- APK: строка пакета в `/etc/apk/world` заменяется на `имя=версия` (так же OpenWrt закрепляет в образе `kernel`,
  `libc` и `base-files`), например `sing-box=1.13.21-r1`
- OPKG: `opkg flag hold <пакет>`

`apk upgrade` и кнопка «Обновить» в LuCI закреплённый пакет не трогают, остальные обновляются как обычно. Версии
совпадают — пакет не закрепляется. У forkop 2.x (`sb` = `forkop-*`) ядро — настоящий пакет `sing-box-forkop`, пакета
`sing-box` нет, закреплять нечего. Закрепление не действует на `apk upgrade --available` и `apk fix sing-box`: если в
репозитории есть та же версия пакета, они переставят его оттуда и вернут бинарник фида. Снять закрепление и обновить:
```sh
apk add sing-box && apk upgrade          # opkg: opkg flag user sing-box && opkg upgrade sing-box
```

## 15. `/etc/banner`
- Бэкап `/etc/banner.bak` (один раз)
- `W I R E L E S S` заменяется на `N E T W O R K`
- Старые строки `Kernel Version:` и `Build Variant:` заменяются новыми:
```
 Kernel Version: 6.12.74
 Build Variant: homeproxy (2026-03-19, feeds: tag)
```
- `feeds:` — откуда фиды packages/luci/routing/telephony/video: `repo` — хотя бы один заменён на коммит репозитория пакетов (поле `feeds` / `feeds_latest`), иначе `tag` — коммиты релизного тега. Берётся из первой строки `/etc/build_feeds`. Дальше в файле — строки feeds.conf всех фидов сборки с реально скачанными коммитами (годятся как feeds.conf для повторной сборки); без файла (старые сборки) часть не выводится.

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
| `/etc/zz1_setup_completed` | всегда | lock-файл, признак режима maintenance (в бэкап и при прошивке не сохраняется) |
| `/root/setup_log.txt` | firstboot | лог выполнения скрипта |
| `/root/setup_log_maintenance.txt` | maintenance | лог выполнения скрипта |
| `/etc/banner.bak` | всегда | бэкап оригинального баннера |
| `/etc/luci-uploads/*.txt` | всегда | пустые loadfile для ipset |
| `/opt/AdGuardHome/` | если AGH есть | директория для данных |
| `/opt/yacd/` | если homeproxy есть | панель YACD (или заглушка) |
| `/etc/group`, `/etc/passwd` | если AGH есть и записи нет | пользователь и группа adguardhome |
| `/etc/nftables.d/10-priority-mangle.nft` | если SQM есть и файла нет | шаблон правил приоритета (закомментирован) |
| `/opt/sqm_custom.conf.migrated` | если был `/opt/sqm_custom.conf` | старый файл после переноса в UCI |

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
### SQM (вариант clear)
```
uci show sqm | grep script; tc filter show dev pppoe-wan parent ffff: | grep ctinfo
```
### BBR
```
sysctl net.ipv4.tcp_congestion_control
```
### kmods в репозиториях
```
cat /etc/apk/repositories.d/distfeeds.list
```
### Закреплённые пакеты
```
grep = /etc/apk/world; sing-box version | head -n1          # opkg: opkg status sing-box | grep Status
```
