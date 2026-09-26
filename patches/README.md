# patches/

Патчи, которые применяются во время сборки. Их два вида, и они применяются
на разных этапах.

| Где лежит | К чему применяется | Когда | Если не применился |
|---|---|---|---|
| `patches/*.patch` | к дереву исходников OpenWrt / ImmortalWrt (`openwrt/`) | шаг **Apply custom patches** в `Universal_WRT_Builder.yml`, до `feeds update` | сборка останавливается |
| `patches/feeds/<фид>/*.patch` | к фиду `feeds/<фид>/` | `sh/WRT-part2.sh`, между `feeds update` и `feeds install` | предупреждение в Actions, сборка идёт дальше без патча |

## Патчи дерева: `patches/*.patch`

Берутся только файлы в корне каталога, подпапки не просматриваются.
Применяются по алфавиту командой

```sh
patch -p1 -d openwrt < patches/<файл>.patch
```

то есть пути в патче считаются от корня дерева OpenWrt
(`a/package/...`, `a/include/...`). Пример имени:
`001-mbedtls-fix-build-when-disabled.patch`.

На этом шаге фидов ещё нет, поэтому **патч к пакету из фида сюда класть нельзя**:
он не найдёт файлы и остановит все варианты сборки.

## Патчи фидов: `patches/feeds/<фид>/*.patch`

Имя подпапки должно совпадать с именем фида в `feeds.conf`
(первое слово после `src-git`). Для каждой подпапки `WRT-part2.sh`:

- если фида `feeds/<фид>` нет (вариант его не подключает), пропускает все патчи подпапки;
- если патч уже есть в исходниках (например, автор исправил у себя), пропускает его;
- если патч применяется, применяет его командой `patch -p1 -d feeds/<фид>`;
- если патч не подходит (код фида изменился), выводит `::warning::` в Actions
  и продолжает сборку **без** этого патча. Чтобы в таком случае сборка падала,
  замените в `apply_feed_patches` строку с `::warning::` на `exit 1`.

Пути в патче считаются от корня репозитория фида (`a/forkop/Makefile`,
`a/luci-app-forkop/...`).

### Текущие патчи

| Файл | Фид (`feeds.conf`) | Что исправляет |
|---|---|---|
| `feeds/forkopmod/001-fix-ucode-forward-refs-and-apk-prerm.patch` | `forkopmod` → Gavr1024/forkop-mod (вариант `forkop`) | 1) Функции ucode, которые вызывались до объявления и падали с ошибкой `left-hand side is not a function`. Главная: падала генерация конфига sing-box для секций без выбранного ядра. Ещё не работало исключение устройств, статус для LuCI, установка sing-box-extended и др. 2) `prerm` пакета `forkop` был на ucode; в сборке с apk (25.12) он встраивается в `/bin/sh`-скрипт и ломал `apk del forkop`. |
| `feeds/forkop/001-fix-ucode-forward-refs-and-apk-prerm.patch` | `forkop` → ushan0v/forkop (в YML сейчас закомментирован) | То же для оригинала 1.0.5: 6 вызовов функций до объявления (блокировки, pid, mwan3, TLS) и `prerm` для apk. |
| `feeds/forkop/002-rpcd-acl-tmp-run.patch` | `forkop` → ushan0v/forkop | Права LuCI на `/tmp/run/forkop/*` в дополнение к `/var/run/forkop/*` для rpcd 2026-07-19 из OpenWrt 25.12 (перенесено из Gavr1024/forkop-mod). |

Проверить, что патч применился, можно в логе шага **Update Feeds & Config**:

```
Патчи фидов (patches/feeds/*)
>>> Фид 'forkop' не загружен, патчи patches/feeds/forkop пропущены.
✓ forkopmod: применён 001-fix-ucode-forward-refs-and-apk-prerm.patch
```

## Как сделать новый патч

К дереву OpenWrt:

```sh
git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git && cd openwrt
# правки…
git diff > ../patches/002-описание.patch
```

К фиду (пример для forkop-mod):

```sh
git clone https://github.com/Gavr1024/forkop-mod.git && cd forkop-mod
# правки…
git diff > ../patches/feeds/forkopmod/002-описание.patch
```

Проверка на свежем клоне фида, без правок:

```sh
patch -p1 --dry-run -d forkop-mod-clean < patches/feeds/forkopmod/002-описание.patch
```

Файлы применяются по алфавиту, поэтому начинайте имя с номера (`001-`, `002-`…).

