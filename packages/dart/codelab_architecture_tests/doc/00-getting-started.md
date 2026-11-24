# Начало работы со сторожем

Эта глава для разработчика, у которого упал `melos run guard` или который впервые открыл пакет. Она отвечает на практические вопросы: как запустить сторож целиком, как прогнать один тест, как прочитать сообщение о нарушении и что делать с каждым видом нарушения. Что именно проверяет каждый тест и как добавить правило, объясняет [следующая глава](01-rules-and-extending.md).

## Что такое сторож

Сторож — пакет `codelab_architecture_tests`. В нём нет кода в `lib/`, только тесты. Они читают исходники и `pubspec.yaml` других пакетов как текст и падают, если пакет нарушает границу из [`AGENTS.md`](../../../../AGENTS.md) §5: импортирует запрещённое, тянет лишнюю зависимость или назван не по схеме. Так границы проверяет машина, а не ревью.

Сторож не компилирует проверяемый код. Поэтому ему не нужна ни генерация кода (`build_runner`), ни собранные бинари: достаточно `fvm dart pub get` или `melos bootstrap`.

Где сторож запускается:

- локально — `melos run guard`;
- в составе `melos run check`: шаг `guard` идёт сразу после `analyze`;
- в GitHub CI — джоб `guard`. Он есть в каждом пакетном прогоне: сторож дешёвый, а импорт, который его ломает, может добавить любой файл (`ci_scope.dart`, `docs/architecture/testing.md` §74).

## Запуск

Скрипт `guard` объявлен в секции `melos:` корневого `pubspec.yaml` и запускает все тесты пакета. Из корня репозитория:

```bash
fvm dart run melos run guard
```

Melos печатает команду, а затем вывод `dart test`:

```text
melos run guard
  └> fvm dart test packages/dart/codelab_architecture_tests
     └> RUNNING
…
00:08 +366 ~3: All tests passed!
```

Число тестов растёт вместе с правилами, поэтому ориентируйтесь на последнюю строку: `All tests passed!` и три пропуска `~3`. Пропускаются `report_leaks_test.dart` без `CODELAB_REPORT_LEAKS_DIR` и две проверки статуса в `parity_evidence_test.dart` без `CODELAB_PARITY_RESULTS` ([глава 01](01-rules-and-extending.md#доказательства-матрицы-целей-и-отчёты-прогонов)). Чистый прогон занимает около десяти секунд.

Тот же набор запускается из каталога пакета:

```bash
cd packages/dart/codelab_architecture_tests
fvm dart test
```

### Один файл и один тест

Файл:

```bash
fvm dart test test/import_guard_test.dart
```

Одно правило импорта. Для каждой строки таблицы `rules` `import_guard_test.dart` создаёт тест с именем `<dir>: no forbidden imports in lib/`, где `<dir>` — каталог правила:

```bash
fvm dart test test/import_guard_test.dart --plain-name "packages/dart/codelab_agent_mcp: no forbidden imports in lib/" -r expanded
```

```text
00:00 +0: loading test/import_guard_test.dart
00:00 +0: packages/dart/codelab_agent_mcp: no forbidden imports in lib/
00:00 +1: All tests passed!
```

У одного каталога бывает несколько правил (`apps/codelab_cli/lib` — три): тесты называются одинаково, и `--plain-name` запустит их все. Это нормально: нужное правило видно по запретам в `rules.dart`, а нарушение называет файл и URI.

Тесты по части имени — `--name` (регулярное выражение):

```bash
fvm dart test test/import_guard_test.dart --name "codelab_client_core"
fvm dart test test/pubspec_allowlist_test.dart --name "codelab_agent_core depends"
```

Флаг `-r expanded` печатает по строке на тест и полный текст ошибки, без перезаписи строки статуса. Он удобен в логах и при отладке.

## Как читать нарушение

Каждый тест при падении пишет в `reason` список нарушений. Формат зависит от теста. Ниже — реальный вывод; нарушение каждый раз вносилось временно и откатывалось.

### Запрещённый импорт

В `packages/dart/codelab_agent_core/lib/src/` добавлен файл с `import 'dart:io';` на первой строке и `import 'package:codelab_acp_protocol/…';` на второй. Тест правила ядра:

```text
00:00 +0 -1: packages/dart/codelab_agent_core: no forbidden imports in lib/ [E]
  Expected: empty
    Actual: [
              'packages/dart/codelab_agent_core/lib/src/tmp_violation.dart:1 -> dart:io',
              'packages/dart/codelab_agent_core/lib/src/tmp_violation.dart:2 -> package:codelab_acp_protocol/codelab_acp_protocol.dart'
            ]
  packages/dart/codelab_agent_core/lib/src/tmp_violation.dart:1 -> dart:io
  packages/dart/codelab_agent_core/lib/src/tmp_violation.dart:2 -> package:codelab_acp_protocol/codelab_acp_protocol.dart
```

Строка нарушения — `путь:номер строки -> URI`. Путь идёт от корня репозитория, URI записан как в исходнике. Список `Expected: empty / Actual: [...]` печатает `package:test`, а ниже стоит `reason` — те же строки, по одной на нарушение. Заголовок теста называет правило: ищите его по `dir` в `test/support/rules.dart`.

### Ссылка на запечатанный файл

Если после URI стоит `(excluded file)`, это не запрещённый пакет, а нарушение запечатывания. Файл `packages/dart/codelab_embedded/lib/src/` импортирует `package:codelab_embedded/io.dart`:

```text
00:00 +0 -1: packages/dart/codelab_embedded: no forbidden imports in lib/ [E]
  Expected: empty
    Actual: [
              'packages/dart/codelab_embedded/lib/src/tmp_seal.dart:1 -> package:codelab_embedded/io.dart (excluded file)'
            ]
```

`io.dart` разрешено то, что запрещено остальному пакету (`dart:io`, IO-пакет агента). Чтобы запрет не обходился, основной код не должен ссылаться на `io.dart` ни пакетным, ни относительным путём. Правило называется `sealExclude` ([глава 01](01-rules-and-extending.md#как-сканер-читает-правило)).

### Зависимость вне allowlist

В `dependencies` `packages/dart/codelab_agent_core/pubspec.yaml` добавлен пакет `path`:

```text
00:00 +0 -1: codelab_agent_core depends only on the allowlist (PKG-2) [E]
  Expected: empty
    Actual: Set:['path']
  not in allowlist: path
```

Сообщение называет лишние пакеты через запятую. Список допустимых лежит в константе `*Allowlist` начала `test/pubspec_allowlist_test.dart`.

### Ручная сборка ядра

В `apps/codelab_agent/lib/src/` добавлен файл с `ToolRegistry()` (HOST-6):

```text
00:00 +0 -1: apps/codelab_agent builds the core only through buildAgentCore [E]
  Expected: empty
    Actual: ['lib/src/tmp_host.dart:2 -> ToolRegistry(']
  lib/src/tmp_host.dart:2 -> ToolRegistry(
```

Здесь путь идёт от каталога пакета, а не от корня репозитория: так печатает `scanHostAssembly`. Остальной формат тот же — `файл:строка -> конструктор(`.

### Литерал интерфейса

В `apps/codelab_desktop/lib/features/workbench/presentation/` добавлен файл с `const Text('Hello world')`:

```text
00:00 +0 -1: в presentation нет литералов интерфейса вне allowlist [E]
  Expected: empty
    Actual: [
              'apps/codelab_desktop/lib/features/workbench/presentation/tmp_page.dart:3 -> \'Hello world\''
            ]
  1 литералов вне каталога ARB. Вынесите их в ARB (`context.l10n`) или добавьте в ui_literals_allowlist.txt с причиной:
  apps/codelab_desktop/lib/features/workbench/presentation/tmp_page.dart:3 -> 'Hello world'
```

### Устаревший префикс и несуществующий каталог

Если в `forbidden` правила остался префикс переименованного пакета, падает `package_naming_test.dart` и печатает префикс:

```text
00:00 +0 -1: forbidden codelab_ prefixes name existing packages (ADR-0002) [E]
  Expected: empty
    Actual: Set:['package:codelab_acp_old/']
```

Если в `rules.dart` указан каталог, которого нет, падает тест правила:

```text
00:00 +0 -1: packages/dart/codelab_agent_typo: no forbidden imports in lib/ [E]
  Expected: true
    Actual: <false>
  packages/dart/codelab_agent_typo is listed in rules.dart but does not exist
```

### Матрица целей, правовые документы, отчёты

Переименована фикстура, на которую ссылается строка Must матрицы (`parity_evidence_test.dart`):

```text
00:02 +1 -1: matrix evidence exists every Must row has existing evidence [E]
  Expected: empty
    Actual: ['L-01 acp/prompt-streaming-txt missing']
  A matrix row names evidence that does not exist (design.md change switch-default-agent-to-dart, D3–D4). Restore the name or fix the matrix row.
```

Разошлись даты редакций `TERMS.md` и `TERMS.ru.md` (`legal_documents_test.dart`):

```text
  даты редакций TERMS.md (2026-11-21) и TERMS.ru.md (2026-11-20) разошлись: у пары одна дата
```

В каталоге отчётов есть значение секретной переменной (`report_leaks_test.dart`); значение в сообщение не попадает, только файл и имя переменной:

```text
00:00 +0 -1: report directory contains no secrets [E]
  Expected: empty
    Actual: ['secret leak: cli-dart.json contains the value of DEMO_API_KEY']
```

## Как воспроизвести нарушение

Чтобы понять правило или проверить, что оно работает, внесите нарушение сами. Порядок безопасен: сторож только читает файлы.

1. Создайте файл с нарушением в каталоге правила, например:

   ```bash
   printf "import 'dart:io';\n" > packages/dart/codelab_agent_core/lib/src/tmp_violation.dart
   ```

2. Запустите тест этого правила:

   ```bash
   fvm dart test packages/dart/codelab_architecture_tests/test/import_guard_test.dart --name "codelab_agent_core: no forbidden" -r expanded
   ```

   Тест падает и печатает `packages/dart/codelab_agent_core/lib/src/tmp_violation.dart:1 -> dart:io`.
3. Удалите файл и проверьте `git status`: в нём не должно остаться временных файлов.

Пакет-источник импортов не обязан собираться: сторож не вызывает анализатор. Но `dart test` сам запускает `pub get`, если вы меняли `pubspec.yaml`: при несовместимой зависимости тест упадёт с `version solving failed` ещё до сторожа. Для проверки allowlist берите пакет, который уже есть в `pubspec.lock` (например, `path`).

## Частые проблемы

### Падает правило импорта: что чинить

**Симптом.** `import_guard_test.dart` падает со строкой `путь:строка -> URI`.

**Причина.** Файл нарушает границу пакета: ядро агента импортирует `dart:io`, `codelab_client_*` тянет Flutter, виджет приложения импортирует плагин платформы.

**Что сделать.** Правьте код, а не правило. Обычно нужен порт: ядру агента файловую систему даёт хост, виджету плагин платформы — адаптер из `lib/core/platform/`. Если импорт действительно нужен, граница меняется отдельным решением: OpenSpec change, затем правило. Правила сторожа правит тот инженер, чью границу меняет задача (`CLAUDE.md`); править правило, чтобы «позеленело», нельзя.

### Нарушение в сгенерированном файле

**Симптом.** В списке файл `*.freezed.dart` или `*.g.dart`.

**Причина.** Сканер читает все `*.dart` в каталоге правила, в том числе сгенерированные и `part`-файлы.

**Что сделать.** Исправьте исходник, из которого генератор написал импорт, и перегенерируйте код. Править сгенерированный файл вручную бесполезно.

### `(excluded file)` после URI

**Симптом.** Нарушение вида `<файл>:<строка> -> <URI> (excluded file)`.

**Причина.** Основной барель или другой файл вне `exclude` ссылается на запечатанный файл: IO-барель, `testing.dart`, слой `src/io/`.

**Что сделать.** Уберите ссылку. Клиент получает IO-часть через собственный `import 'package:…/io.dart'` в composition root, а не через реэкспорт основного бареля.

### `is listed in rules.dart but does not exist`

**Симптом.** Тест правила падает с этим текстом.

**Причина.** Каталог из `PackageRule.dir` переименован, перенесён или удалён, либо в `dir` опечатка. Тест нарочно красный: сканер молча пропускает отсутствующий каталог, и правило перестало бы что-либо проверять.

**Что сделать.** Исправьте `dir` в `test/support/rules.dart`. Если пакет переименован, поправьте и префиксы `package:codelab_…` в `forbidden` (следующий случай).

### Префикс в `forbidden` указывает на несуществующий пакет

**Симптом.** `package_naming_test.dart` печатает `package:codelab_<имя>/`.

**Причина.** Пакет переименован, а запрет остался под старым именем. Запрет по префиксу не падает на ровном месте: он просто перестаёт ловить нужное (ADR-0002, раздел Risks).

**Что сделать.** Замените префикс на актуальное имя пакета. Префикс без `/` на конце (`package:codelab_agent_`) требует хотя бы один пакет, имя которого с него начинается.

### Новый пакет не прошёл проверку имён

**Симптом.** `every workspace package follows the codelab_ scheme` печатает строку `<каталог> -> <имя>`.

**Причина.** Имя в `pubspec.yaml` не начинается с `codelab_` или не совпадает с именем каталога.

**Что сделать.** Приведите имя к схеме `codelab_<сторона>_<слой>` ([ADR-0002](../../../../docs/architecture/adr/0002-name-packages-codelab-side-layer.md), `AGENTS.md` §5). Каталоги берутся из секции `workspace:` корневого `pubspec.yaml`.

### `not in allowlist`

**Симптом.** `pubspec_allowlist_test.dart` называет лишний пакет.

**Причина.** В `dependencies` появился пакет, которого нет в `*Allowlist` этого пакета.

**Что сделать.** Убрать зависимость или вынести код туда, где она разрешена. Расширение allowlist — архитектурное решение и идёт через OpenSpec change (`workspace-architecture`, «Расширение allowlist»; `AGENTS.md` §4). Сторож проверяет только секцию `dependencies`: перенос пакета в `dev_dependencies` нарушением не считается.

### Ручная сборка ядра (HOST-6)

**Симптом.** `host_assembly_guard_test.dart` называет `ToolRegistry(`, `Agent(` или `AgentRuntime(`.

**Причина.** Хост (`apps/codelab_agent`, `codelab_embedded`) создаёт части ядра вручную, в обход `buildAgentCore`.

**Что сделать.** Соберите ядро через `buildAgentCore` ([руководство ядра агента, сборка и хосты](../../codelab_agent_core/doc/02-assembly-and-hosts.md)). Сторож сканирует `lib/` и `bin/` бинаря агента и `lib/` моста `codelab_embedded`; тесты в `test/` ручную сборку делать могут. Строки, начинающиеся с `//`, пропускаются, хвостовой комментарий после кода — нет.

### Литерал интерфейса

**Симптом.** `ui_literals_test.dart` называет `файл:строка -> 'текст'`.

**Причина.** В `presentation/` или в ките `codelab_ui` строка интерфейса написана литералом мимо каталога ARB, и при русском языке она осталась бы английской.

**Что сделать.** Вынесите текст в ARB и берите его через `context.l10n`. Если строка — не язык интерфейса (имя продукта, протокол, пример значения поля), добавьте её в `test/support/ui_literals_allowlist.txt` с причиной ([глава 01](01-rules-and-extending.md#как-разрешить-литерал-интерфейса)). Тот же тест падает, если запись allowlist без причины или в коде её больше нет: мёртвые исключения не копятся.

### Строка матрицы целей без доказательства

**Симптом.** `matrix evidence exists` печатает `<строка> <доказательство> missing`.

**Причина.** Переименована или удалена фикстура `acp/<id>`, e2e-сценарий `cli/<id>`, тест `core/<id>` или файл теста, на который ссылается ячейка «Критерий приёмки» матрицы.

**Что сделать.** Верните имя или поправьте ячейку матрицы. Для `cli/<id>` и `core/<id>` id должен быть началом первого строкового литерала внешнего `test(` или `group(`: вложенный `test('core/x…')` доказательством не считается (`docs/architecture/testing.md` §74.1).

### Правовой документ

**Симптом.** `legal_documents_test.dart` называет файл и ожидаемый заголовок или дату.

**Причина.** Нарушена форма `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md` или `TERMS.ru.md` в корне репозитория: первая строка не дата редакции, нарушен порядок обязательных заголовков второго уровня, в тексте есть слова согласия, у пары разные даты.

**Что сделать.** Приведите документ к форме из теста. Меняя одну редакцию, меняйте дату в обеих. Сверку копий документов внутри приложения делает `legal_assets_test.dart` в `apps/codelab_desktop/test/app/`, а не сторож.

### CI посчитал полный прогон, хотя изменён один пакет

**Симптом.** В Step Summary джоба `scope` строка `Reason: changed outside workspace packages: …`.

**Причина.** Изменённый файл лежит вне пакетов workspace, документации и `site/`: например, `.github/pull_request_template.md`. Для такого файла CI не знает, что он затрагивает, и запускает всё. Правило записано в `ciScope`, его проверяет `ci_scope_test.dart`.

**Что сделать.** Ничего, если файл действительно общий. Посмотреть расчёт локально можно командой `fvm dart run tool/ci/affected.dart --base origin/develop`: она печатает матрицу джобов и Step Summary в stdout. Пример на настоящем коммите репозитория:

```bash
fvm dart run tool/ci/affected.dart --base 7583f34b~1
```

```text
### CI scope: full

Reason: changed outside workspace packages: .github/pull_request_template.md

site: yes
…
```

### Тест зелёный, но нарушение есть

**Симптом.** Запрещённый импорт в репозитории, а сторож молчит.

**Причина.** Сторож — построчный сканер, а не анализатор. Он не видит то, что лежит вне зоны правила:

- правило пакета сканирует только `lib/` (каталоги правил с `lib` или `bin` в пути сканируются целиком); `test/`, `integration_test/`, `tool/` не проверяются;
- директива должна начинаться со строки (`import`, `export`, `part` после пробелов); условная альтернатива `if (…) 'uri'` ищется отдельно в той же строке;
- правило `apps/codelab_cli/lib/src` для `codelab_acp_testing` и `dart_tui` не охватывает `lib/codelab_cli.dart` и `bin/` (в отличие от правил `codelab_setup/io.dart` и `codelab_embedded`, которые заданы на весь `lib/`);
- для ряда ограничений правила нет вовсе: общий запрет Flutter для всех `packages/dart/`, импорты `package:*/src/*` между пакетами, циклы зависимостей, зависимость `codelab_ui` от приложения (`docs/architecture/layers-and-dependencies.md` §42, таблица «что сторож проверяет и чего нет»).

**Что сделать.** Не считайте зелёный сторож заменой ревью. Нужное правило добавляется по рецепту из [главы 01](01-rules-and-extending.md#как-добавить-правило-для-нового-пакета).

## Что дальше

- [Устройство и расширение](01-rules-and-extending.md) — что проверяет каждый тест, таблица правил и рецепты.
- [README пакета](../README.md) — краткий обзор и порядок добавления правила.
