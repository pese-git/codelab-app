# codelab_architecture_tests

Сторож границ monorepo: пакет без кода в `lib/`, только тесты. Они падают, если пакет или приложение импортирует запрещённое, тянет лишнюю зависимость или нарушает схему имён. Так границы из [`AGENTS.md`](../../../AGENTS.md) §5 проверяются автоматически, а не на ревью.

Устройство сторожа, таблица правил, разбор сообщений о нарушениях и рецепты описывает [руководство разработчика](doc/README.md).

## Что проверяют тесты

| Файл теста | Что проверяет |
|---|---|
| `test/import_guard_test.dart` | В `lib/` каждого пакета из таблицы `rules` нет запрещённых импортов (`dart:io`, `package:flutter/`, IO-бареля `package:codelab_acp_transports/io.dart` и т. п.). Рядом лежат негативные тесты: они создают временный пакет с нарушением и проверяют, что сторож его находит |
| `test/import_scanner_test.dart` | Сам сканер: `import`, `export`, `part`, условные импорты, исключения `exclude` и запечатывание `sealExclude` |
| `test/pubspec_allowlist_test.dart` | Секция `dependencies` в `pubspec.yaml` ядра агента, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `apps/codelab_agent`, `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli`, `codelab_setup`, `codelab_embedded` содержит только разрешённые пакеты. У `apps/codelab_desktop` проверяются только зависимости `codelab_*`: пакеты `codelab_agent_*` туда не попадают |
| `test/package_naming_test.dart` | Каждый член pub workspace называется `codelab_…`, а имя пакета совпадает с именем каталога (ADR-0002). Запрещённые префиксы `package:codelab_…` в правилах указывают на существующие пакеты: после переименования устаревший префикс иначе молча перестал бы что-либо запрещать |
| `test/host_assembly_guard_test.dart` | HOST-6: `apps/codelab_agent` и `codelab_embedded` собирают ядро агента только через `buildAgentCore`, без ручных `ToolRegistry(`, `Agent(`, `AgentRuntime(` |
| `test/parity_evidence_test.dart` | Каждая строка Must матрицы `docs/architecture/proposals/agent-parity-goals.md` ссылается на существующее доказательство. Проверку статуса по отчётам ночного прогона включает переменная `CODELAB_PARITY_RESULTS` |
| `test/ci_scope_test.dart` | Логика `tool/ci/ci_scope.dart`: какие джобы CI запускать по списку изменённых файлов. Ещё две проверки: «Полный прогон CI совпадает с check» (шаги `check` из `pubspec.yaml` равны скриптам полного прогона CI, среди них нет `test:e2e:app:*` и `test:e2e:cli:python-agent`) и «Джобов на macOS нет» (все `runs-on` в `.github/workflows/ci.yml` — `ubuntu-latest`) |
| `test/legal_documents_test.dart` | Форма корневых `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md`: первая строка с датой редакции, порядок заголовков, одна дата у пары, нет слов согласия; корневой `README.md` ссылается на документы |
| `test/ui_literals_test.dart` | В `apps/codelab_desktop/lib/app` целиком, в `presentation/` фич desktop и в `codelab_ui` нет английских литералов интерфейса мимо каталога ARB, кроме записей `test/support/ui_literals_allowlist.txt` с причиной |
| `test/report_leaks_test.dart` | Отчёты прогонов не содержат секретов. Без `CODELAB_REPORT_LEAKS_DIR` тест пропускается |

Среди правил `rules.dart`: `package:codelab_setup/io.dart` запрещён во всём `apps/codelab_cli/lib`, кроме `src/run.dart`, и в `apps/codelab_cli/bin`; `packages/flutter/codelab_ui/lib` не импортирует `package:desktop_drop/`.

Правила импортов собраны в одной таблице `rules` (`test/support/rules.dart`). Каждое правило — `PackageRule`:

| Поле | Значение |
|---|---|
| `dir` | пакет (сканируется его `lib/`) или каталог внутри `lib/`, `bin/` — путь от корня репозитория |
| `forbidden` | запрещённые префиксы URI |
| `exclude` | файлы и каталоги (с `/` на конце), на которые запрет не действует: IO-барель и его реализация, сценарный слой |
| `sealExclude` | `true` (по умолчанию) — остальной код пакета не может ссылаться на файлы из `exclude`; `false` — `exclude` только снимает запрет |

Списки допустимых зависимостей лежат не в `rules.dart`, а в константах `*Allowlist` в начале `test/pubspec_allowlist_test.dart`.

## Как запустить

Из корня репозитория:

```bash
fvm dart run melos run guard
```

Скрипт выполняет `fvm dart test packages/dart/codelab_architecture_tests`. Тот же набор можно запустить из каталога пакета:

```bash
cd packages/dart/codelab_architecture_tests
fvm dart test
```

Один файл или один тест:

```bash
fvm dart test test/import_guard_test.dart
fvm dart test test/import_guard_test.dart --name "codelab_client_core"
```

Чистый прогон занимает около десяти секунд и заканчивается строкой `All tests passed!` (число тестов растёт вместе с правилами):

```text
00:08 +366 ~3: All tests passed!
```

Три пропуска (`~3`): `report_leaks_test.dart` без `CODELAB_REPORT_LEAKS_DIR` и две проверки статуса в `parity_evidence_test.dart` без `CODELAB_PARITY_RESULTS`.

## Как читать нарушение

Нарушение импорта — это строка `файл:строка -> URI` с путём от корня репозитория. Тест падает с таким списком в `reason`. Формат зафиксирован в негативных тестах пакета:

```text
pkg/lib/a.dart:1 -> dart:io
pkg/lib/a.dart:2 -> package:flutter/widgets.dart
```

Суффикс `(excluded file)` значит нарушение запечатывания: файл ссылается на файл из `exclude` правила, которому такая ссылка запрещена. Например, основной барель `codelab_embedded` не должен подтягивать `lib/io.dart`.

Нарушение allowlist выглядит как `not in allowlist: <пакеты>`. Лишний пакет надо убрать из `dependencies`. Расширять allowlist без OpenSpec change нельзя.

Нарушение имён: строки вида `<каталог> -> <имя пакета>` или устаревший префикс `package:codelab_…`.

## Как добавить правило для нового пакета

Кратко:

1. Добавьте пакет в `workspace:` корневого `pubspec.yaml` под схемой имён `codelab_<сторона>_<слой>` (`AGENTS.md` §5).
2. Добавьте `PackageRule` в `test/support/rules.dart` и негативный тест в `test/import_guard_test.dart`.
3. Если пакет ограничивает зависимости, добавьте `*Allowlist` и тест в `test/pubspec_allowlist_test.dart`.
4. Обновите корневые `README.md` и `AGENTS.md` §5, выполните `melos bootstrap` и `melos run guard`.

Скелеты кода, проверенные запуском, и подробности — в [рецепте руководства](doc/01-rules-and-extending.md#как-добавить-правило-для-нового-пакета). Тест правила падает, если `dir` не существует, а `package_naming_test.dart` — если префикс в `forbidden` не указывает ни на один пакет.

## Место в архитектуре

Пакет не входит в граф зависимостей рабочего кода: его никто не импортирует. Он только читает исходники и `pubspec.yaml` других пакетов от корня репозитория. Корень находит `repoRoot()` — ближайший каталог вверх с `workspace:` в `pubspec.yaml`, поэтому тесты работают и из корня, и из каталога пакета. `ci_scope_test.dart` импортирует `tool/ci/ci_scope.dart` из корня репозитория.

Зависимости (`pubspec.yaml`): только `dev_dependencies` — `test`, `path`, `lints`.

## Смотрите также

- [`AGENTS.md`](../../../AGENTS.md) §5 — границы пакетов и список запретов, которые проверяет сторож.
- [`docs/architecture/layers-and-dependencies.md`](../../../docs/architecture/layers-and-dependencies.md) — слои и направление зависимостей.
- README защищаемых пакетов: [`codelab_agent_core`](../codelab_agent_core/README.md), [`codelab_embedded`](../codelab_embedded/README.md), [`codelab_setup`](../codelab_setup/README.md), [`codelab_client_core`](../codelab_client_core/README.md), [`codelab_client_io`](../codelab_client_io/README.md), [`codelab_agent_mcp`](../codelab_agent_mcp/README.md).
