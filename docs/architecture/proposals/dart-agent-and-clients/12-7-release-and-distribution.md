# 12.7. Выпуск и распространение

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [12.6. Удобства CLI и десктопа](12-6-cli-desktop-extras.md) · [Оглавление](../dart-agent-and-clients.md) · [12.8. Смартфон и планшет](12-8-phone-and-tablet.md) →

## 12.7.1. Назначение и охват

Раздел закрывает строки Should матрицы целей ([`agent-parity-goals.md`](../agent-parity-goals.md)
§3.8 — U-29, §3.9 — D-16, D-18), без которых нельзя выпустить первый публичный релиз:

| Цель | Что даёт | Подраздел |
|---|---|---|
| U-29 | скрипт первой установки с проверкой подписанного `SHA256SUMS`, каналы `stable`/`beta`/`pinned`, происхождение сборки | §12.7.3–§12.7.6 |
| D-16 | подписанные и нотаризованные дистрибутивы app для macOS, Windows, Linux | §12.7.2, §12.7.4 |
| D-18 | политика конфиденциальности, общая для CLI и app | §12.7.7 |

Раздел описывает источник релизов, на который опирается самообновление (U-20, §12.6.4):
формат манифеста канала, проверка ed25519 и алгоритм замены бинаря остаются там и здесь не
повторяются. Агент и ACP не меняются. Все сценарии выпуска живут в `tool/release/` и
`.github/workflows/release.yml`; ни один публичный артефакт не собирается на машине
разработчика. Задача 9.4 этапа 9 (поставка) выполняется по этому разделу.

Вне охвата: Mac App Store (D-26 — Won't), магазины Windows и Linux, apt/rpm-репозитории,
самообновление app (app обновляется скачиванием нового дистрибутива или менеджером пакетов),
формулы Homebrew и Scoop (могут появиться позже; для них §12.6.4 шаг 1 уже даёт подсказку).

## 12.7.2. Артефакты релиза

Одна версия на релиз для всех артефактов: `codelab`, `codelab-agent` и app выпускаются вместе из
одного тега `vX.Y.Z` (версия ACP и схемы конфигурации — отдельные и в номер не входят).

**Раскладка источника релизов.** `<base>` — константа сборки `kUpdateBaseUrl` (§12.6.4),
статический HTTPS-хостинг без серверной логики (конкретный домен — открытый вопрос, [§11](11-assumptions-and-open-questions.md)).

```text
<base>/
  install.sh, install.sh.sha256, install.ps1, install.ps1.sha256   # скрипты текущего stable
  stable/manifest.json, stable/manifest.json.sig                   # U-20, ed25519
  stable/latest.txt, stable/latest.txt.sig                         # для скрипта, P-256
  beta/…                                                           # те же четыре файла
  releases/<version>/
    SHA256SUMS, SHA256SUMS.sig                                     # P-256, §12.7.4
    manifest.json, manifest.json.sig                               # манифест версии, для --version
    codelab-<version>-<target>[.exe]                               # 5 целей
    codelab-agent-<version>-<target>[.exe]
    CodeLab-<version>-macos-universal.dmg
    CodeLab-<version>-windows-x64-setup.exe
    codelab-app-<version>-linux-x64.tar.gz, codelab-app_<version>_amd64.deb
    install.sh, install.ps1                                        # с вшитой версией по умолчанию
    provenance.intoto.jsonl, RELEASE_NOTES.md, PRIVACY.md
```

Тот же набор файлов прикрепляется к GitHub Release тега; источник истины для установщика и
самообновления — `<base>`. Файлы в `releases/<version>/` после публикации не меняются (REL-5).

**CLI и агент.** `dart compile exe` на нативном раннере каждой цели (кросс-компиляции нет):

| `target` | Раннер | Подпись ОС |
|---|---|---|
| `macos-arm64` | `macos-14` | Developer ID Application, `--options runtime`, нотаризация |
| `macos-x64` | `macos-13` | то же |
| `linux-x64` | `ubuntu-22.04` (glibc 2.35 — нижняя граница) | — |
| `linux-arm64` | `ubuntu-22.04-arm` | — |
| `windows-x64` | `windows-2022` | Authenticode |

Артефакт — сам бинарь без архива (так его скачивает §12.6.4, шаг 4). Голый Mach-O нельзя
сшить (`stapler`) с тикетом нотаризации: бинарь отправляется в `notarytool` в zip, тикет
проверяется Gatekeeper онлайн; `curl` не ставит атрибут карантина, поэтому установка скриптом
без сети тикета не требует. Windows на ARM64 получает `windows-x64` (эмуляция). musl (Alpine)
не поддерживается: бинарь `dart compile exe` связан с glibc.

**App.** До первого релиза: идентификатор пакета `com.example.codelabApp` и
`PRODUCT_COPYRIGHT` в `apps/codelab_desktop/macos/Runner/Configs/AppInfo.xcconfig` заменяются
постоянными (обратный домен владельца — [§11](11-assumptions-and-open-questions.md)); каталоги `windows/` и `linux/` создаются
`flutter create --platforms windows,linux`.

* **macOS** — `flutter build macos --release` (universal), подпись `codesign --deep` запрещена:
  подписываются по порядку вложенные фреймворки, затем `.app`, с `--options runtime --timestamp`
  и `macos/Runner/Release.entitlements` без песочницы (app запускает агентов и терминалы, D-26);
  JIT и `disable-library-validation` не включаются. `.app` нотаризуется и сшивается, затем
  собирается `.dmg` (`hdiutil create -format UDZO`), подписывается, нотаризуется
  (`xcrun notarytool submit --wait`) и сшивается (`xcrun stapler staple`). `.pkg` не выпускается,
  пока нет установки в системные каталоги.
* **Windows** — `flutter build windows --release`, установщик Inno Setup
  (`tool/release/windows/codelab.iss`): установка для текущего пользователя в
  `%LOCALAPPDATA%\Programs\CodeLab` без прав администратора, ярлык в меню «Пуск», удаление
  через «Приложения». Authenticode (SHA-256, отметка времени RFC 3161) ставится на
  `codelab_app.exe`, собственные DLL, сам установщик и деинсталлятор (`SignTool` в `.iss`).
  MSIX отклонён: виртуализация файловой системы и идентичность пакета мешают запуску внешних
  агентов, `codelab` из `PATH` и записи в `~/.codelab`; Inno Setup — инструмент сборки, не
  зависимость рантайма.
* **Linux** — `flutter build linux --release`; `.tar.gz` с каталогом `bundle/` и `.deb`
  (`Depends: libgtk-3-0, libstdc++6`, установка в `/opt/codelab`, `.desktop` и значок). Подписи
  уровня ОС нет: целостность — подписанный `SHA256SUMS` и происхождение (§12.7.6). AppImage —
  Could, после первого релиза.

App (`apps/codelab_desktop`) не использует `google_fonts` с загрузкой шрифтов во время работы: шрифты — ассеты
сборки (иначе app делает сетевой запрос, не описанный в политике, §12.7.7).

## 12.7.3. Каналы

| Канал | Что получает пользователь | Фоновая проверка (§12.6.4, шаг 9) | `codelab update` без `--version` |
|---|---|---|---|
| `stable` | версии `X.Y.Z` | да, если `update.check: true` | ставит последнюю `stable` |
| `beta` | `X.Y.Z-beta.N` и все `stable` (манифест `beta` указывает на более новую из двух) | да | ставит последнюю из `beta` |
| `pinned` | одна версия, выбранная при установке или командой | нет | не меняет версию: `codelab is pinned to 1.4.0. Run "codelab update --version <x.y.z>" or "codelab update --channel stable".`, код `0` (`--check` — `0`) |

* Канал по умолчанию — `stable`. Источник канала: `update.channel` в `~/.codelab/cli.yaml`,
  иначе `channel` из `install.json`, иначе `stable` (слой проекта канал не задаёт, UX-14).
* `codelab update --version 1.5.0` на `pinned` ставит эту версию и закрепляет её (в
  `install.json` меняется `version`); понижение — только с `--allow-downgrade` (§12.6.4, шаг 3).
* `codelab update --channel stable|beta|pinned` переключает канал и пишет его в `install.json`;
  `--channel pinned` закрепляет текущую версию без загрузки.
* Манифест для `--version` — `releases/<version>/manifest.json` той же схемы 1; поле `channel`
  — канал, в котором версия вышла; `sequence` — общий счётчик релизов. Защита от отката по
  `sequence` действует для манифестов каналов, а явный `--version` — выбор пользователя.
* Отозванная версия (найдена уязвимость) удаляется из манифестов каналов; её каталог
  остаётся, а в `RELEASE_NOTES.md` следующей версии — запись об отзыве. `pinned` на отозванной
  версии фоновой проверкой не уведомляется: это осознанный выбор, см. риск в [§10](10-risks.md).
* `codelab --version --output-format json` (H-09) показывает канал, включая `pinned`, и
  `install_method` (`script`, менеджер пакетов, `dev`).

Формат `install.json` (рядом с бинарём, расширяет §12.6.4, шаг 1):

```json
{"schema": 1, "method": "script", "channel": "pinned", "version": "1.4.0",
 "installed_at": "2026-10-20T09:00:00Z", "bin_dir": "/Users/u/.local/share/codelab/bin",
 "path_entry": {"kind": "rc", "file": "/Users/u/.zshrc"}, "agent": true}
```

`path_entry` нужен `codelab uninstall` (U-20): удаляется ровно блок между маркерами
`# >>> codelab >>>` и `# <<< codelab <<<` или значение из пользовательского `Path` Windows.

## 12.7.4. Подпись и проверка

**Два семейства ключей, одна политика хранения.**

| Семейство | Что подписывает | Кто проверяет | Где открытый ключ |
|---|---|---|---|
| `release-ed25519` (U-20) | `manifest.json` каналов и версий, каждый артефакт CLI | бинарь `codelab` (`package:cryptography`) | `kUpdateTrustedKeys` в бинаре; `docs/release/keys.md` |
| `sums-p256` (U-29) | `SHA256SUMS`, `latest.txt` каналов | `install.sh`, `install.ps1`, пользователь вручную | вшит в оба скрипта; `docs/release/keys.md`; страница загрузки |

**Выбор схемы для `SHA256SUMS`.** Рассмотрены minisign, Sigstore (cosign) и ECDSA P-256
с отделённой подписью. Скрипт установки должен проверять подпись **до** записи бинаря, на
чистой системе и без установки сторонних программ.

* minisign — Ed25519 и простой формат, но утилиты `minisign` нет ни в macOS, ни в Windows, ни
  в большинстве дистрибутивов; системный LibreSSL macOS не проверяет Ed25519
  (`pkeyutl -rawin`), а Windows PowerShell 5.1 (.NET Framework) не умеет Ed25519.
* cosign — нужен бинарь `cosign`, проверка подписи без ключа ходит в Rekor и Fulcio при
  каждой установке (лишние сетевые запросы, §12.7.7) и привязывает доверие к OIDC-идентичности
  CI-платформы.
* **Выбрано: ECDSA P-256 + SHA-256, подпись DER.** Проверяется штатно:
  `openssl dgst -sha256 -verify pub.pem -signature SHA256SUMS.sig SHA256SUMS` работает и с
  LibreSSL macOS, и с OpenSSL Linux; в `install.ps1` — `[System.Security.Cryptography.ECDsa]`
  из .NET Framework 4.7+ (Windows 10 1709+) с ключом из параметров кривой и переводом DER в
  форму `r‖s`. Sigstore используется только для аттестаций происхождения (§12.7.6), не как
  условие установки.

Ed25519 для U-20 остаётся: бинарь проверяет его своим кодом, внешних программ не нужно.

**Форматы.** `SHA256SUMS` — вывод `shasum -a 256` (`<hex>  <имя файла>`, LF, сортировка по
имени) для **всех** файлов `releases/<version>/`, кроме самих `SHA256SUMS*`. `latest.txt` —
одна строка `codelab-latest-v1 <channel> <version> <sequence>`. Подписи — над точными байтами
файла. Скрипт перебирает вшитые ключи (не больше трёх); подходящий ключ один.

**Хранение закрытых ключей.** Закрытые ключи обоих семейств, сертификат Developer ID
(`.p12`), ключ API App Store Connect для `notarytool` и учётные данные облачной подписи
Authenticode (ключ сертификата OV/EV живёт в HSM провайдера, не в CI) — только секреты окружения
GitHub `release` с обязательным ручным одобрением (required reviewers ≥ 1, только теги `v*`).
Ни в репозитории, ни в логах, ни в артефактах сборки (REL-10). Резервная копия ключей
`release-ed25519` и `sums-p256` — офлайн у двух владельцев (кто — [§11](11-assumptions-and-open-questions.md)).

**Ротация.** Плановая — раз в два года, `key_id` вида `2026-a`:

1. Новый ключ добавляется в `kUpdateTrustedKeys` и в скрипты как дополнительный и выходит
   хотя бы в одном `stable`-релизе, подписанном ещё старым ключом.
2. Следующие релизы подписываются новым ключом; старый остаётся доверенным для проверки уже
   выпущенных версий ещё 12 месяцев, затем удаляется из бинаря и скриптов.

**Компрометация.** Ключ сразу удаляется из скриптов `<base>/install.*` и из следующего бинаря;
`SHA256SUMS` поддерживаемых версий пересчитываются CI из записей сборки, сверяются с
опубликованными и переподписываются новым ключом (единственное допустимое изменение
опубликованного каталога, REL-5); запись в `SECURITY.md` и `RELEASE_NOTES.md`. Бинари, которые
доверяют только скомпрометированному ключу `release-ed25519`, самообновиться не смогут —
пользователь переустанавливает скриптом (сообщение `unknownKey` в §12.6.4 подсказывает это).

## 12.7.5. Скрипт первой установки

Шаблоны `tool/release/install.sh.tmpl` и `tool/release/install.ps1.tmpl`; генератор
`tool/release/gen_installers.dart` подставляет `<base>`, открытые ключи `sums-p256` и версию по
умолчанию. Тестовый вариант (локальный `<base>`, тестовый ключ) генерируется только в тестах и
не публикуется: в опубликованных скриптах нет переменных окружения, меняющих доверие или
источник (REL-2).

```text
curl -fsSL <base>/install.sh | sh -s -- [--version <x.y.z>] [--channel stable|beta|pinned]
        [--bin-dir <dir>] [--no-modify-path] [--cli-only] [--dry-run]
& ([scriptblock]::Create((irm <base>/install.ps1))) [-Version <x.y.z>] [-Channel …] [-BinDir …]
        [-NoModifyPath] [-CliOnly] [-DryRun]
```

Коды: `0` — установлено или уже установлено; `1` — сеть, подпись, сумма, запись; `2` —
неподдерживаемая платформа; `64` — ошибка использования. Ошибки печатаются с кодом в начале:
`E_SIGNATURE_INVALID`, `E_CHECKSUM_MISMATCH`, `E_NOT_LISTED`, `E_UNSUPPORTED_PLATFORM`,
`E_TOOL_MISSING`, `E_NOT_WRITABLE`, и всегда заканчиваются `Nothing was installed.`, если
ничего не записано.

**Алгоритм** (`install.ps1` — те же шаги):

1. **Платформа.** `uname -s`/`uname -m`: `Darwin`→`macos`, `Linux`→`linux`; `x86_64|amd64`→`x64`,
   `arm64|aarch64`→`arm64`. macOS под Rosetta (`sysctl -n sysctl.proc_translated` = `1`) →
   `arm64`. Linux с musl → `E_UNSUPPORTED_PLATFORM`, код `2`. Нужны `curl` или `wget`,
   `openssl`, `shasum` или `sha256sum`; нет — `E_TOOL_MISSING` с именем программы.
2. **Версия.** `--version` — как есть (формат semver, иначе код `64`). Иначе канал (`--channel`,
   по умолчанию `stable`; `pinned` без версии берёт текущий `stable`): скачать
   `<channel>/latest.txt` и `.sig`, проверить подпись, взять версию. Скрипт из
   `releases/<v>/` по умолчанию ставит `<v>`.
3. **Загрузка во временную папку** (`mktemp -d`, удаляется по `trap … EXIT`): `SHA256SUMS`,
   `SHA256SUMS.sig`, `codelab-<v>-<target>` и, без `--cli-only`, `codelab-agent-<v>-<target>`.
   Только `https://`, `curl --proto '=https' --tlsv1.2 -fsSL`, таймаут 300 с на файл.
4. **Проверка до записи.** Подпись `SHA256SUMS` вшитым ключом → строка файла есть в
   `SHA256SUMS` (иначе `E_NOT_LISTED`) → SHA-256 совпадает. Любая неудача — код `1`.
5. **Идемпотентность.** Если в `<bin-dir>` уже лежит файл с той же суммой — запись
   пропускается, шаги 7–8 всё равно выполняются (починка `PATH` и `install.json`), вывод
   `codelab <v> is already installed.`
6. **Запись.** `<bin-dir>` по умолчанию: `${XDG_DATA_HOME:-~/.local/share}/codelab/bin`
   (Windows — `%LOCALAPPDATA%\Programs\codelab\bin`). Копия во временный файл в `<bin-dir>`,
   `chmod 0755`, smoke `--version` (вывод содержит `<v>`), `mv` поверх. Unix: символическая
   ссылка `~/.local/bin/codelab` → бинарь (U-20 заменяет файл по `Platform.resolvedExecutable`,
   ссылка остаётся). `sudo`, `Start-Process -Verb RunAs` и запись вне домашнего каталога не
   используются; нет права записи — `E_NOT_WRITABLE`.
7. **`PATH`.** Каталог уже в `PATH` — ничего. Иначе, без `--no-modify-path`, блок с маркерами в
   rc-файл текущей оболочки (`zsh` → `~/.zshrc`; `bash` → `~/.bashrc`, на macOS ещё
   `~/.bash_profile`; `fish` → `~/.config/fish/conf.d/codelab.fish`; иначе `~/.profile`).
   Блок уже есть — не дублируется. Windows —
   `[Environment]::SetEnvironmentVariable('Path', …, 'User')`, если записи ещё нет.
8. **`install.json`** (§12.7.3) пишется атомарно последним. Итог:
   `Installed codelab <v> (<channel>) to <bin-dir>. Privacy: <url политики>`, и, если менялся
   `PATH`, — `Restart your shell or run: export PATH="$HOME/.local/bin:$PATH"`.

`--dry-run` выполняет шаги 1–4 и печатает, что было бы записано. Повторный запуск с другой
версией — это ручное обновление: тот же путь, что шаги 4–8.

## 12.7.6. Происхождение сборки

**Цель — SLSA Build L2** к первому публичному релизу: сборка на хостируемых раннерах GitHub
Actions из тега, подписанное происхождение, которое нельзя подделать без доступа к CI.
**L3** (изолированная сборка, ключи подписи недоступны шагам сборки) — после первого релиза:
сборка выносится в отдельный переиспользуемый workflow без секретов, подпись — в джоб окружения
`release`, который получает только артефакты.

* Происхождение — in-toto statement с предикатом SLSA v1 через
  `actions/attest-build-provenance` на каждый файл из `SHA256SUMS`: коммит, тег, путь и ref
  workflow, id запуска, образ раннера, версии Flutter и Dart из `.fvmrc`, SHA-256 `pubspec.lock`.
* Файл `provenance.intoto.jsonl` лежит в каталоге релиза и попадает в `SHA256SUMS`.
  Проверка пользователем — `gh attestation verify <файл> --repo <владелец>/<репозиторий>`
  (документирована в `docs/release/verify.md`); установщик и самообновление её не вызывают.
* Тег — аннотированный, на коммит в `main` с зелёными обязательными джобами CI (§9.5);
  иначе `release.yml` падает до сборки.
* Побитовая воспроизводимость не обещается; ночной джоб `release-rebuild-diff` пересобирает
  CLI из последнего тега и публикует отличия как отчёт без блокировки.

## 12.7.7. Конфиденциальность

**Документ.** `PRIVACY.md` в корне репозитория, текст общий для CLI и app (D-18), с датой
редакции в первой строке. Публикуется: страница `<сайт>/privacy` (на том же хостинге, что
`<base>`), копия в каждом каталоге релиза, ассет app `assets/legal/PRIVACY.md` (читается
офлайн). Ссылки: экран «Privacy» onboarding (D-11, §12.4.9), диалог «О программе» app (версия,
канал сборки, лицензия MIT, ссылки на политику и `THIRD_PARTY_NOTICES.md`), последняя строка
`codelab --help`, итог установщика (§12.7.5, шаг 8), README репозитория.

**Содержание (разделы обязательны, проверяет `privacy_policy_test.dart`).**

1. **Телеметрии нет** (E-21): ни CLI, ни агент, ни app не отправляют аналитику использования,
   отчёты о сбоях и идентификаторы установки; нет SDK аналитики.
2. **Сетевые запросы** — полный перечень:

   | Куда | Когда | Что уходит | Как выключить |
   |---|---|---|---|
   | провайдер модели, настроенный пользователем | каждый ход | промпт, история сессии, содержимое файлов и вывод команд, которые агент прочитал, ключ API | не настраивать провайдера; локальная модель (Ollama) |
   | MCP-серверы из конфигурации | вызов инструмента сервера | аргументы вызова | убрать сервер |
   | web-инструменты (`web_fetch`, `web_search`) | по одобрению пользователя | URL или запрос | режим одобрения, запрет инструмента |
   | `<base>` | фоновая проверка обновления — не чаще раза в 24 ч при старте REPL; `codelab update`; установщик | обычный HTTP-запрос файла манифеста (IP, `User-Agent: codelab/<версия> (<target>)`), без идентификаторов | `update.check: false`, канал `pinned`; headless и app не проверяют |

   Команды `!<cmd>` и инструменты терминала выполняют то, что запросил пользователь или
   одобрил он же; их сетевые запросы — запросы этих программ. Внешние ACP-агенты — со своей
   политикой.
3. **Что хранится локально:** `~/.codelab` — конфигурация, сессии и журналы, логи (E-16),
   `update_state.json`; ключи API — в хранилище ОС (§12.4); app — `shared_preferences`. Ничего
   не отправляется наружу, кроме перечисленного в п. 2.
4. **Сторонние политики:** данные, ушедшие провайдеру модели или MCP-серверу, обрабатываются по
   их правилам.
5. **Контакт и изменения:** адрес для вопросов (из `SECURITY.md`), история редакций.

**Синхронизация с кодом.** `docs/release/network-inventory.yaml` — перечень всех мест, где
код открывает сетевое соединение (`HttpClient(`, `http.Client(`, `IOClient(`,
`WebSocket.connect`, `Socket.connect`), с пунктом политики и `policy_sha256` — хешем
`PRIVACY.md`. Тест-сторож находит такие вызовы в `lib/` всех пакетов и приложений; вызов без
записи, запись без вызова или неверный хеш — падение. Изменение сетевого поведения поэтому
всегда требует правки `PRIVACY.md` в том же PR (REL-9).

## 12.7.8. Процесс релиза

* **Версии** — semver: `X.Y.Z` для `stable`, `X.Y.Z-beta.N` для `beta`. Ломающее изменение CLI,
  конфигурации или `stream-json` (§12.5) — major; новая цель или команда — minor.
* **CHANGELOG.md** в формате Keep a Changelog: раздел `## [X.Y.Z] - YYYY-MM-DD` обязателен для
  тега; `RELEASE_NOTES.md` релиза — этот раздел. Раздел «Privacy» — при любой правке
  `PRIVACY.md`.
* **Тег.** Мейнтейнер ставит `git tag -a vX.Y.Z` на зелёный коммит `main` и пушит.

`.github/workflows/release.yml` (на `push: tags: ['v*']`):

| Джоб | Окружение | Что делает |
|---|---|---|
| `verify-tag` | — | тег аннотированный, коммит в `main`, CI зелёный, версия в `pubspec.yaml` CLI и app = тег, раздел CHANGELOG есть |
| `build` (матрица 5 целей + app ×3) | — | `fvm` из `.fvmrc`, `melos run test`, `dart compile exe`, `flutter build`; артефакты — в `actions/upload-artifact` |
| `sign` (матрица macOS, Windows) | `release`, ручное одобрение | `codesign`, `notarytool`, `stapler`; облачный Authenticode; сборка `.dmg` и установщика |
| `assemble` | `release` | `SHA256SUMS` + подпись P-256, подписи ed25519 артефактов CLI, `manifest.json` версии, скрипты из шаблонов, `PRIVACY.md` |
| `attest` | — (`id-token: write`, `attestations: write`) | происхождение §12.7.6 |
| `publish-staging` | `release` | загрузка в `<base>/releases/<v>/` и GitHub Release (черновик) |
| `smoke` (macOS, Ubuntu, Windows) | — | установка опубликованным скриптом с `--version <v>`, `codelab --version`, `codelab update --check` на тестовом канале |
| `promote` | `release`, ручное одобрение | `sequence` = `sequence` текущего манифеста канала + 1; новые `manifest.json`, `latest.txt` канала и `install.*` в корне (только `stable`); GitHub Release перестаёт быть черновиком |

Каталог версии публикуется до указателей канала, указатели — только после зелёного `smoke`
(REL-6). Неудача любого джоба оставляет каналы прежними; каталог версии, не дошедшей до `promote`,
удаляется из `<base>` этим же workflow.

## 12.7.9. Инварианты

1. **REL-1.** Установщик не пишет в `<bin-dir>`, rc-файлы и `install.json`, пока подпись
   `SHA256SUMS` вшитым ключом и SHA-256 загруженного файла не проверены; при любой ошибке
   прежняя установка остаётся байт в байт прежней, временная папка удалена.
2. **REL-2.** Доверенные ключи установщика — только вшитые в опубликованный скрипт; ни
   переменные окружения, ни аргументы не меняют ключи и `<base>` опубликованного скрипта.
3. **REL-3.** Установщик не повышает права и не пишет вне домашнего каталога пользователя.
4. **REL-4.** Публичный релиз не выпускается, если хотя бы один артефакт macOS не подписан
   Developer ID с hardened runtime и не нотаризован (для `.app` и `.dmg` — со сшитым тикетом)
   или хотя бы один исполняемый файл Windows не подписан Authenticode с отметкой времени.
5. **REL-5.** Каждый файл каталога версии перечислен в `SHA256SUMS`; `sha256` в
   `manifest.json` совпадает со строкой `SHA256SUMS`; опубликованный каталог не меняется, кроме
   переподписи `SHA256SUMS.sig` при компрометации ключа.
6. **REL-6.** Указатели каналов (`manifest.json`, `latest.txt`) обновляются только после
   публикации каталога версии и успешного `smoke`; `sequence` канала строго растёт.
7. **REL-7.** Публичный артефакт собран CI из аннотированного тега на коммите `main` и имеет
   аттестацию происхождения; локальные сборки не публикуются.
8. **REL-8.** На канале `pinned` версия меняется только командой с явным `--version` или сменой
   канала; фоновая проверка обновлений не выполняется.
9. **REL-9.** Каждое место открытия сетевого соединения в коде описано в
   `network-inventory.yaml` и в `PRIVACY.md`; телеметрии нет (E-21).
10. **REL-10.** Закрытые ключи и сертификаты подписи доступны только джобам окружения `release`
    после ручного одобрения и не попадают в репозиторий, логи и артефакты.
11. **REL-11.** Повторный запуск установщика с той же версией не меняет файлы и не дублирует
    запись `PATH`.

## 12.7.10. Тесты и проверки

| Проверка | Где | Критерий (строка матрицы) |
|---|---|---|
| `cli/install-script-rejects-bad-sums` | `apps/codelab_cli/test/e2e/install_script_test.dart` | U-29: «бинарь без пройденной проверки не устанавливается» |
| `cli/install-script-pins-version` | то же | U-29: «каналы: `stable` … `pinned` — версия закреплена» |
| `cli/update-respects-pinned` | `apps/codelab_cli/test/e2e/update_test.dart` | U-29: «`codelab update` без `--version` её не меняет» |
| `release/macos-signature-and-notarization` | джоб `sign`, шаг проверки | D-16: «подпись и нотаризация macOS-сборки» |
| `release/windows-authenticode` | джоб `sign`, шаг проверки | D-16: «подпись установщика Windows» |
| `release/sums-and-provenance` | джоб `assemble`, `attest` | U-29, D-16: «суммы SHA-256 и происхождение сборки» |
| `release/privacy-policy-published` | джоб `smoke` | D-18: «документ опубликован, ссылки в app и CLI ведут на него» |
| `privacy_network_inventory_test` | `packages/dart/codelab_architecture_tests/test/` | D-18, E-21 |

* **`install-script-rejects-bad-sums`** запускает тестовый вариант `install.sh` (на Windows —
  `install.ps1` через `powershell -NoProfile`) против локального HTTPS-сервера
  (самоподписанный сертификат передаётся `curl --cacert` только в тестовом варианте) и
  временного `HOME`. Случаи: подпись чужим ключом, испорченный байт `SHA256SUMS`, верная подпись
  и неверная сумма бинаря, файла нет в `SHA256SUMS`, обрыв загрузки, musl. Каждый: код `1`
  (musl — `2`), `<bin-dir>`, rc-файлы и `install.json` байт в байт прежние, временных файлов
  нет. Положительный случай: бинарь на месте, `install.json` по §12.7.3, второй запуск ничего не
  меняет (REL-11), блок `PATH` один.
* **`install-script-pins-version`**: `--channel pinned` без версии ставит версию из
  `stable/latest.txt`; `--version` ставит указанную; подменённый `latest.txt` без верной подписи
  → код `1`.
* **`update-respects-pinned`**: `install.json` с `pinned` — `codelab update` код `0`, бинарь не
  тронут, HTTP-сервер не получил ни одного запроса; `--version` ставит и закрепляет новую
  версию.
* **macOS**: `codesign --verify --strict --deep -vv` для `.app`, `codesign -dvv` содержит
  `flags=0x10000(runtime)` и `Authority=Developer ID Application`, `spctl -a -vv -t exec` для
  `.app` и `spctl -a -vv -t open --context context:primary-signature` для `.dmg` — `accepted`,
  `xcrun stapler validate` для обоих, `codesign --verify` и запуск `--version` для бинарей CLI.
* **Windows**: `signtool verify /pa /all /tsp /v` для `codelab.exe`, `codelab-agent.exe`,
  `codelab_app.exe`, установщика и деинсталлятора.
* **Суммы и происхождение**: каждый файл каталога есть в `SHA256SUMS`, подпись проверяется
  `openssl` опубликованным ключом из `docs/release/keys.md`, `sha256` манифеста совпадает с
  `SHA256SUMS`, `gh attestation verify` проходит для каждого файла.
* **Политика**: `<сайт>/privacy` отвечает `200` и совпадает с `PRIVACY.md` тега;
  `codelab --help` содержит её URL; integration test app `app:about_dialog_test.dart` открывает
  «О программе» и находит ту же ссылку и ассет; `privacy_policy_test.dart` проверяет наличие
  пяти разделов §12.7.7.
* **Модульно**: `tool/release/test/gen_installers_test.dart` (подстановка ключей и версии,
  опубликованный вариант не содержит тестовых ключей и `--cacert`),
  `tool/release/test/sums_format_test.dart` (сортировка, LF, исключение `SHA256SUMS*`).

---

← [12.6. Удобства CLI и десктопа](12-6-cli-desktop-extras.md) · [Оглавление](../dart-agent-and-clients.md) · [12.8. Смартфон и планшет](12-8-phone-and-tablet.md) →
