# ADR-0002: Name workspace packages by the `codelab_<side>_<layer>` scheme

Status: Proposed

Date: 2026-10-26

## Context

В monorepo 13 пакетов в двух семействах имён, которые сложились в разное время:

* `acp_*` — пакеты первого коммита (`fa13e72`, 2026-08-20), когда репозиторий был только ACP-клиентом: `acp_protocol`, `acp_transports`, `acp_client_core`, `acp_testing`, `acp_ui`; позже к ним добавились `acp_client_kit` и `acp_client_io` (этап 5, change `extract-acp-client-kit`);
* `codelab_*` — пакеты Dart-агента и инфраструктуры (ADR-0001, с `89df306`, 2026-10-23): `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_architecture_tests`, приложения `codelab_app` и `codelab_agent`.

Префикс `acp_` задумывался как граница переиспользования: «реализация ACP, не привязанная к CodeLab» (`layers-and-dependencies.md` §8, «`acp_ui` должен оставаться reusable»). На практике эта граница не выдерживается:

* в `acp_*` есть код продукта: `codelabAgentStdioProfile` в `acp_transports/lib/src/transport_configs.dart`, `configureCodeLabLogging` в `acp_client_core`; `acp_client_kit` по своему `AGENTS.md` — «общий клиентский слой CodeLab» для `codelab_app` и `codelab_cli`;
* `acp_ui` не зависит ни от одного ACP-пакета: это дизайн-система рабочего места CodeLab на `fluent_ui`;
* ни один пакет не публикуется (`publish_to: none` у всех), поэтому переиспользование вне репозитория пока не подтверждено.

Кроме того, имена не передают устройство слоёв:

* `core` значит разное: в `codelab_agent_core` — встраиваемое ядро без IO, в `acp_client_core` — протокольный клиент (`AcpClientApplication`) и его состояние;
* `acp_client_core` и `acp_client_kit` по именам не различить, хотя роли у них разные: протокольный клиент и политика рабочего пространства для хостов;
* семейство агента уже следует схеме «ядро / IO-адаптеры / ACP-адаптер» (`codelab_agent_core`, `_io`, `_acp`), а клиентская сторона — нет;
* с появлением `codelab_cli` (этап 6) имя `codelab_app` перестаёт различать клиентов;
* короткие общие имена (`acp_protocol`, `acp_ui`) могут совпасть с пакетами pub.dev, если понадобится сторонний пакет с тем же именем или публикация.

Почему решать сейчас:

* change `extract-acp-client-kit` завершён (архивирование — PR #86), клиентский слой стабилизировался;
* активные changes `add-file-preview-and-tree` и `add-integrated-terminal` ещё не начаты (0 из 21 и 0 из 20 задач): после их старта rename превратится в долгий конфликт по коду;
* по ADR-0001 впереди новые пакеты (`codelab_agent_mcp`, `codelab_embedded`, `codelab_setup`, `codelab_cli`): чем раньше схема зафиксирована, тем меньше переименований.

`docs/architecture/adr/README.md` §3 не требует ADR для переименования, но здесь меняется схема имён всех package boundaries, правила тест-сторожа опираются на префиксы имён (`package:acp_`, `package:codelab_agent_`), а публичный API пакетов (`package:` URI) меняется у всех потребителей.

Затрагиваемые boundaries:

* package boundaries monorepo и их имена;
* правила тест-сторожа `codelab_architecture_tests` и allowlist зависимостей;
* `AGENTS.md`, `docs/architecture/`, `openspec/specs/`.

---

## Decision

### 1. Схема имён

Пакеты-библиотеки называются `codelab_<сторона>_<слой>`:

* **сторона** — `acp` (общий протокольный слой обеих сторон), `client` (клиенты), `agent` (Dart-агент);
* **слой** — назначение пакета внутри стороны:
  * `core` — логика стороны без IO и Flutter;
  * `io` — адаптеры `dart:io`;
  * `acp` — проекция стороны в протокол ACP;
  * для общего слоя `acp` — предметное имя: `protocol`, `transports`, `testing`.

Пакеты без стороны называются `codelab_<назначение>`: `codelab_ui`, `codelab_architecture_tests`, а также пакеты-мосты между сторонами из ADR-0001 — `codelab_embedded` и `codelab_setup`. Мосты НЕ ДОЛЖНЫ получать префикс `codelab_agent_`: клиентам запрещено импортировать `package:codelab_agent_*` (`AGENTS.md` §5), а мосты клиенты импортируют.

Приложения в `apps/` называются по продукту, который получает пользователь: `codelab_desktop`, `codelab_cli`, `codelab_agent`. Что это приложение, а не библиотека, видно по каталогу.

### 2. Таблица переименований

| Сейчас | Новое имя | Роль |
|---|---|---|
| `acp_protocol` | `codelab_acp_protocol` | Типизированные модели ACP JSON-RPC, кодеки, валидация |
| `acp_transports` | `codelab_acp_transports` | Транспорты ACP; `io.dart` — IO-транспорты |
| `acp_testing` | `codelab_acp_testing` | Фикстуры, fake-транспорты, conformance обеих сторон |
| `acp_client_core` | `codelab_client_acp` | Протокольный клиент `AcpClientApplication` — зеркало `codelab_agent_acp` |
| `acp_client_kit` | `codelab_client_core` | Политика клиента без UI и IO для всех хостов — зеркало `codelab_agent_core` |
| `acp_client_io` | `codelab_client_io` | `dart:io`-адаптеры клиента — зеркало `codelab_agent_io` |
| `acp_ui` | `codelab_ui` | Fluent UI дизайн-система рабочего места |
| `apps/codelab_app` | `apps/codelab_desktop` | Десктопный клиент |
| `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp` | без изменений | Уже в схеме |
| `codelab_architecture_tests`, `apps/codelab_agent`, корневой `codelab_workspace` | без изменений | Уже в схеме |

Запланированные пакеты получают имена по схеме сразу: `codelab_agent_mcp`, `codelab_embedded`, `codelab_setup`, `apps/codelab_cli` — как в ADR-0001.

### 3. Что переименовывается вместе с пакетом

* каталог, `name:` в `pubspec.yaml`, barrel-файл `lib/<name>.dart` и все `package:` импорты;
* список `workspace:` и скрипты Melos в корневом `pubspec.yaml`;
* правила сторожа: `PackageRule(dir, ...)` и запрещённые префиксы. Префикс `package:acp_` заменяется двумя — `package:codelab_acp_` и `package:codelab_client_`; префикс `package:codelab_agent_` остаётся;
* `AGENTS.md` (корневой и вложенные), `docs/architecture/`, `openspec/specs/` и активные changes.

### 4. Что НЕ переименовывается

* **Типы с префиксом `Acp` в протокольных и клиентских пакетах** (`AcpTransport`, `AcpClientApplication`, `AcpClientBackend`): там `Acp` — термин протокола, а не имя пакета.
* **Идентичность установленного приложения**: `PRODUCT_NAME = codelab_app` и `PRODUCT_BUNDLE_IDENTIFIER` в `apps/<app>/macos/Runner/Configs/AppInfo.xcconfig`, имя `codelab_app.app`. От bundle identifier зависят пользовательские данные `shared_preferences` (`AGENTS.md` §2, приоритет 3 — целостность пользовательских данных). Имя и идентификатор продукта меняются отдельным решением на этапе релиза (задача 9.4 ADR-0001).
* **Пути и форматы данных** (`~/.codelab/`, журналы сессий, `config.yaml`) и ACP wire protocol.
* **Архив OpenSpec** `openspec/changes/archive/`: это история, имена в нём остаются как были.
* **Имена spec'ов OpenSpec** (`acp-client-kit` и другие) — переименовываются отдельно, если понадобится: это не package boundary.

### 5. Классы `codelab_ui`

Префикс `Acp` у виджетов бывшего `acp_ui` (`AcpButton`, `AcpBadge`, `AcpIcon` и ещё 33 класса) не обозначает термин протокола и после переименования пакета вводит в заблуждение. Целевой префикс — `CodeLab`, как у типов приложения (`CodeLabShellCubit`). Замена выполняется отдельным шагом миграции после переименования пакетов, чтобы диф переименования оставался механическим.

---

## Alternatives

### Alternative 1 — Оставить `acp_*` и зафиксировать границу

Сохранить два семейства, записать правило «`acp_*` не содержит CodeLab-специфики», вынести `codelabAgentStdioProfile` и `configureCodeLabLogging` в приложение и переименовать только `acp_ui`.

Почему не выбран:

* граница уже нарушена в трёх пакетах (`acp_transports`, `acp_client_core`, `acp_client_kit`), а `acp_client_kit` и `acp_client_io` по назначению — клиентский слой CodeLab, а не переиспользуемая реализация ACP;
* публикация ACP-пакетов не запланирована ни в ADR-0001, ни в дорожной карте, поэтому выгода от нейтральных имён не подтверждена;
* не устраняет неразличимость `acp_client_core` / `acp_client_kit` и несимметричность клиентской и агентской сторон.

### Alternative 2 — Добавить префикс `codelab_` к текущим именам

`codelab_acp_protocol`, `codelab_acp_client_core`, `codelab_acp_client_kit`, `codelab_acp_ui` и так далее.

Почему не выбран:

* сохраняет неразличимость `core` и `kit` и разный смысл `core` в двух семействах;
* клиентские пакеты попадают под префикс `codelab_acp_`, поэтому правило сторожа «агентский IO не импортирует протокол» нельзя выразить одним префиксом без захвата клиента;
* `codelab_acp_ui` закрепляет неверное утверждение, что UI зависит от ACP.

### Alternative 3 — Назвать kit `codelab_client_workspace` или `codelab_client`

Оставить слово `core` только агенту, а kit назвать по главной сущности (`ClientWorkspace`).

Почему не выбран:

* kit уже выполняет роль ядра клиента: политика «когда слать, как реагировать на сбой» живёт в нём, а use case-ы бывшего `acp_client_core` он не использует (design D3 change `extract-acp-client-kit`);
* `codelab_client` без слоя выбивается из схемы и плохо сочетается с `codelab_client_io`.

Компромисс выбранного варианта описан в Consequences / Negative.

### Alternative 4 — Сгруппировать пакеты по каталогам сторон

`packages/acp/`, `packages/client/`, `packages/agent/` вместо `packages/dart/` и `packages/flutter/`.

Почему не выбран сейчас:

* текущее деление `dart/` / `flutter/` закреплено в `AGENTS.md` §5 правилом «пакеты в `packages/dart/` не зависят от Flutter»; перегруппировка меняет это правило и не нужна для схемы имён;
* может быть рассмотрен отдельным решением.

---

## Consequences

### Positive

* имя пакета говорит, к какой стороне и к какому слою он относится; клиентская и агентская стороны устроены одинаково: `core` / `io` / `acp`;
* правила сторожа выражаются префиксами сторон: `package:codelab_agent_` — запрет для клиентов, `package:codelab_acp_` и `package:codelab_client_` — запрет для агентского IO;
* `codelab_ui` честно описывает содержимое: дизайн-систему без зависимости от ACP;
* все пакеты под одним префиксом продукта — нет риска совпадения имён с пакетами pub.dev;
* запланированные пакеты ADR-0001 получают имена по схеме без дополнительных решений.

### Negative

* одно механическое изменение примерно в 300 файлах вне архива OpenSpec (около 2000 строк со старыми именами на develop, включая архив);
* одинаковые имена слоёв не означают одинакового направления зависимостей: у агента `codelab_agent_acp` зависит от `codelab_agent_core`, у клиента `codelab_client_core` зависит от `codelab_client_acp`. Направление выровняется, если протокольный клиент спрятать за портом `AgentBackend`; до этого правило описывается в `layers-and-dependencies.md`;
* ссылки в архиве OpenSpec и в старых коммитах остаются со старыми именами; для поиска по истории нужна таблица соответствия из этого ADR;
* открытые ветки и PR со старыми именами требуют ручного обновления после слияния.

### Risks

* **Конфликты с параллельной работой.** Снижение: переименование одним PR сразу после слияния PR #86 и до начала реализации `add-file-preview-and-tree` и `add-integrated-terminal`; открытые PR с документацией (#78, #47) обновляются при следующем слиянии develop.
* **Пропущенное старое имя** в строке, скрипте Melos или CI. Снижение: `git grep` по старым именам вне `openspec/changes/archive/` должен давать пустой результат; `melos run check` и `melos run guard`.
* **Сторож молча ослабнет**, если префикс `package:acp_` заменить не полностью. Снижение: сторож уже падает на `PackageRule` с несуществующим каталогом (`import_guard_test.dart`); вместе с переименованием в него добавляется такая же проверка для запрещённых префиксов `package:` — каждый должен совпадать с именем хотя бы одного пакета workspace.
* **Потеря пользовательских данных** при смене bundle identifier. Снижение: идентичность приложения не меняется (Decision §4).

---

## Migration

Предусловия: PR #86 слит, CI на develop зелёный, ADR принят (`Status: Accepted`).

1. Ветка `feature/rename-packages` от актуального `develop`.
2. Переименование снизу вверх по графу зависимостей, после каждого шага — `melos bootstrap`, `melos analyze`, `melos run guard`:
   1. `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing`;
   2. `codelab_client_acp`, `codelab_client_core`, `codelab_client_io`;
   3. `codelab_ui`;
   4. `apps/codelab_desktop`.
3. Правила сторожа и allowlist зависимостей — вместе с пакетом, которого они касаются; первым шагом — проверка сторожа, что каждый запрещённый префикс `package:` совпадает с именем пакета workspace (Risks).
4. `AGENTS.md` (корневой §5 и вложенные), `docs/architecture/`, `openspec/specs/`, активные changes, `README.md`.
5. Отдельным коммитом той же ветки — префикс `Acp` → `CodeLab` у виджетов `codelab_ui` (Decision §5).
6. `melos run check` на обновлённой ветке, затем PR в `develop`.

Совместимость: пакеты не публикуются, внешних потребителей нет; ACP wire protocol, форматы данных и идентичность приложения не меняются.

Откат: revert PR переименования. Миграции данных нет.

---

## Validation

* `melos run check` — format, analyze, tests, protocol conformance, клиентский и агентский прогон golden ACP-фикстур;
* `melos run guard` — правила сторожа с новыми именами и префиксами;
* `git grep -wE 'acp_(protocol|transports|client_core|client_kit|client_io|testing|ui)|codelab_app'` вне `openspec/changes/archive/` и вне `PRODUCT_NAME`/имени `.app` даёт пустой результат;
* сборка `codelab_desktop` под macOS открывает сохранённые настройки и недавние проекты прежней установки (bundle identifier не изменился).

---

## Related

### Architecture

* `AGENTS.md` §5 — структура monorepo и правила пакетов
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/technology-stack.md`
* `docs/architecture/proposals/dart-agent-and-clients.md`

### OpenSpec

* `openspec/specs/workspace-architecture/spec.md`
* `openspec/specs/acp-client-kit/spec.md`
* `openspec/changes/add-file-preview-and-tree/`, `openspec/changes/add-integrated-terminal/` — обновляются при переименовании

### ADR

* ADR-0001 — пакеты агента и клиентов, запланированные `codelab_agent_mcp`, `codelab_embedded`, `codelab_setup`, `codelab_cli`

### Code

* `pubspec.yaml` — workspace и скрипты Melos
* `packages/dart/codelab_architecture_tests/test/support/rules.dart`
* `packages/dart/acp_*`, `packages/flutter/acp_ui`, `apps/codelab_app`
