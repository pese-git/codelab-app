## Context

Источник решений — принятые документы (ADR-0001, Status: Accepted):

- `docs/architecture/proposals/dart-agent-and-clients/09-05-stage-0-foundation.md` — задачи 0.1–0.11, артефакты (скрипты melos, CI, сторож, скелеты `pubspec.yaml`), Definition of Done этапа;
- `docs/architecture/proposals/agent-core/01-layers-and-packages.md` — пакеты ядра, инварианты PKG-1…PKG-6, алгоритм сторожа (§1.4);
- `docs/architecture/proposals/dart-agent-and-clients/09-00-migration-plan.md` §9.0 — правила этапов: TDD (правило 3), архивация change в конце этапа (правило 6), вложенные `AGENTS.md` (правило 7), итерации feature first (правило 8);
- `docs/architecture/proposals/dart-agent-and-clients/07-decision-sources.md` §7а — политика стороннего кода;
- `AGENTS.md` §5 (структура), §21 (проверки), §22 (git flow).

Scope — только Flutter/Dart-проект этого репозитория; соседний репозиторий `codelab-agent` (Python) не затрагивается.

Текущее состояние: шесть пакетов в `workspace:` корневого `pubspec.yaml`; скрипты melos продублированы в `melos.yaml` и секции `melos:` (в `melos.yaml` на три e2e-скрипта больше); `.github/` нет; `acp_transports.dart` экспортирует `stdio_acp_transport.dart` и `websocket_acp_transport.dart`, которые импортируют `dart:io`; `LICENSE` и корневого `README.md` нет. На GitHub `develop` — ветка по умолчанию, ruleset на `master` и `develop` требует pull request, обязательных проверок пока нет.

## Goals / Non-Goals

**Goals:**

- каждый pull request проверяется CI: формат, анализ, тесты, protocol conformance, сторож, компиляция ядра для web;
- нарушение границ пакетов (IO в ядре, Flutter в чистом Dart, прямой импорт агентских пакетов клиентами) ловится тестом, а не ревью;
- `package:acp_transports/acp_transports.dart` пригоден для web-безопасного кода;
- в репозитории есть пакет ядра, в который этап 1 добавляет код по TDD;
- правила агентских пакетов и TDD записаны в `AGENTS.md` до первой строки кода ядра.

**Non-Goals:**

- код ядра агента (этапы 1–3), ACP-адаптер и бинарь агента (этап 4);
- корпус golden-фикстур и клиентский прогон — change `add-acp-golden-fixture-corpus`;
- сценарий выпуска `release.yml` (§12.7.8, задача 9.4);
- изменение поведения `codelab_app` и ACP-контрактов.

## Decisions

### D1. Монорепозиторий

Агентские пакеты добавляются в этот репозиторий (допущение 1, `dart-agent-and-clients/11-assumptions-and-open-questions.md`). Contract test клиент ↔ агент и сторож работают в одном workspace без git-зависимостей и согласования версий.

Альтернатива — отдельный репозиторий агента с `acp_protocol` как git-зависимостью: contract test требует публикации или пина ревизии, сторож пришлось бы дублировать. Отклонено. Переименование репозитория в `codelab` вне scope.

### D2. Одна конфигурация melos в `pubspec.yaml`

melos 8 (`melos: ^8.3.0` в корневом `pubspec.yaml`) читает секцию `melos:`; `melos.yaml` — дубль, который уже разошёлся. Недостающие скрипты переносятся, файл удаляется. Проверка — вывод `fvm dart run melos list` и список скриптов до и после совпадают; `melos run check` работает. Если melos не читает секцию (допущение 6 не подтвердилось), `melos.yaml` остаётся единственным источником, а дубль удаляется из `pubspec.yaml` — решение фиксируется в этом файле.

### D3. Разделение `acp_transports` через вторую точку входа

`lib/acp_transports.dart` — порт `AcpTransport` и классы конфигурации (без `dart:io`); `lib/io.dart` — `StdioAcpTransport`, `WebSocketAcpTransport`. Реализации остаются в `lib/src/`, конфиги переезжают в `lib/src/transport_configs.dart` с собственным `part 'transport_configs.freezed.dart'`; генерация — `fvm dart run build_runner build --delete-conflicting-outputs` в пакете, сгенерированные файлы коммитятся. После переноса перегенерируется и `app_scope.module.cherrypick.g.dart` в приложении.

Альтернативы: условный импорт (`if (dart.library.io)`) — скрывает зависимость от IO и усложняет сторож; отдельный пакет `acp_transports_io` — лишний пакет ради двух классов. Отклонены. Сторож закрепляет раскладку правилом `PackageRule('packages/dart/acp_transports', forbidden: webUnsafe, exclude: ['lib/io.dart', 'lib/src/io/'])` с `sealExclude`: файлы основного бареля не ссылаются на исключённые.

Транспорты физически остаются в `lib/src/stdio_acp_transport.dart` и `lib/src/websocket_acp_transport.dart`, поэтому до их переноса в `lib/src/io/` они перечисляются в `exclude` поимённо. Перенос в `lib/src/io/` делается в этой же задаче, если он механический; иначе — поимённый `exclude` и пометка в tasks.

### D4. Сторож — тест на регулярных выражениях

`codelab_architecture_tests` обходит все `lib/**/*.dart` пакетов из таблицы `test/support/rules.dart`, разбирает `import`/`export`/`part` и каждую альтернативу условного импорта, сравнивает с префиксами запретов. Таблица — одна на весь репозиторий; правила будущих пакетов добавляются в их этапах (комментарии в таблице, `09-05` «Артефакт: тест-сторож архитектуры»). Отдельный тест `pubspec_allowlist_test.dart` проверяет, что `dependencies` ядра — подмножество `{http, meta, collection, async, crypto}` (PKG-2).

Альтернатива — `package:analyzer` или `custom_lint`: точнее, но тяжелее и медленнее; переход на `parseString` — только если появятся директивы, которые выражение не распознаёт. `dart analyze` с `implementation_imports` не ловит `dart:io` в чистом пакете — не подходит.

Правило клиентов «не импортировать `package:codelab_agent_`» (PKG-4) добавляется в таблицу сразу для `apps/codelab_app`: нарушения сейчас нет, правило защищает от него с первого агентского пакета.

### D5. Скрипты melos и `check`

Добавляются `test:dart`, `guard`, `web-compile`; `check` — `check-format, analyze, guard, test, protocol-conformance, web-compile`. `conformance:client` добавляет change `add-acp-golden-fixture-corpus` вместе с тестом, который он запускает: скрипт без каталога тестов падал бы в `check`. Скрипты пакетов будущих этапов (`conformance:agent`, `build:agent`, `build:cli`, `test:e2e:cli`, `test:e2e:app:dart-agent`, `test:e2e:app:embedded`) не добавляются.

### D6. CI под git flow

Эскиз `09-05` написан для ветки `main`; в репозитории ветки `master` и `develop` (`AGENTS.md` §22). Триггеры: `push` в `master` и `develop`, `pull_request` (любой целевой ветки), ночной `schedule`. Матрица из шести джобов на `ubuntu-latest`; `e2e-macos` — ночью, на push в `develop`/`master` и на PR с меткой `e2e`; он не блокирует PR без метки. Общая подготовка — составное действие `.github/actions/prepare` (FVM из `.fvmrc`, кэш `~/fvm` и `~/.pub-cache` по `hashFiles('.fvmrc', 'pubspec.lock')`).

Обязательные проверки в ruleset `master`/`develop` включаются вручную после первого зелёного прогона на `develop`: имя проверки появляется в GitHub только после запуска джоба.

### D7. TDD и порядок задач

`tasks.md` — пары «тест → реализация» (§9.0, правило 3). Исключения правила 3, применимые здесь: (а) задачи 0.1 и 0.2 — изменение существующего кода, сначала фиксируется зелёное текущее состояние (характеризация: `melos list`, `melos run check`, тесты `acp_transports` и app), потом правка; (д) CI — инфраструктура, проверяется прогоном workflow, а не unit-тестом. Сторож пишется test-first буквально: негативный тест `reports dart:io imported by a core library` красный до реализации сканера.

### D8. Итерации

Change выполняется тремя итерациями feature first (§9.0, правило 8), каждая — один pull request из `feature/add-workspace-ci-and-architecture-guards` в `develop` или отдельная ветка `feature/add-workspace-ci-and-architecture-guards-<n>`:

1. melos (0.1) и разделение `acp_transports` (0.2) — существующий код, зелёные тесты app;
2. пакеты `codelab_agent_core`, `codelab_architecture_tests`, скрипты (0.3–0.5), `AGENTS.md` (0.11);
3. CI (0.6), лицензия (0.9).

После каждой итерации `fvm dart run melos run check` зелёный.

## Risks / Trade-offs

- [Разделение `acp_transports` ломает импорты в app и тестах] → изменение механическое; восемь интеграционных тестов app и `widget_test.dart` прогоняются до и после.
- [melos 8 не читает секцию `melos:`] → проверка `melos list` до удаления `melos.yaml`; запасной вариант в D2.
- [FVM в CI долго ставит SDK] → кэш `~/fvm` и `~/.pub-cache`.
- [macOS-раннеры дороги и медленны] → `e2e-macos` не в каждом PR, только по метке и ночью.
- [Регулярное выражение сторожа пропустит экзотическую директиву] → негативные тесты на условный импорт и `part`; переход на `package:analyzer` описан в D4.
- [`web-compile` wasm требует свежий SDK] → версия SDK закреплена `.fvmrc`; при отказе wasm-компилятора джоб падает явно, а не пропускается.

## Migration Plan

Изменение затрагивает только сборку и импорты. Откат — revert pull request итерации; ruleset не зависит от CI до включения обязательных проверок.

## Open Questions

- Нет. Правообладатель в `LICENSE` — Sergey Penkovsky (подтверждено владельцем репозитория). Задача 0.10 отложена и в change не входит.
