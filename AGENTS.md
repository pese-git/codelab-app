# AGENTS.md — ACP Client

Инструкции для AI coding agents, разработчиков и CI, работающих в этом monorepo.

Проект: **Flutter Desktop клиент для взаимодействия с AI agents по ACP (Agent Client Protocol)**.

Основной технологический стек:

* Dart
* Flutter Desktop
* FVM
* Melos
* Monorepo
* OpenSpec

Подробный технологический стек описан в:

`docs/architecture/technology-stack.md`

---

## 1. Терминология требований

В этом документе используются нормативные формулировки:

* **ОБЯЗАН / ДОЛЖЕН** — обязательное требование.
* **НЕ ДОЛЖЕН / ЗАПРЕЩЕНО** — запрещённое действие.
* **СЛЕДУЕТ** — предпочтительное решение; отклонение должно иметь причину.
* **МОЖЕТ** — допустимый вариант.

AI-agent обязан интерпретировать эти формулировки как архитектурные ограничения проекта.

---

## 2. Приоритеты

При конфликте требований использовать следующий порядок:

1. Безопасность.
2. Корректность протокола ACP.
3. Целостность пользовательских данных.
4. Корректность состояния приложения.
5. Наблюдаемость и возможность диагностики.
6. Архитектурные границы.
7. UX.
8. Производительность.
9. Простота реализации.
10. Скорость разработки.

Нижестоящий приоритет НЕ ДОЛЖЕН достигаться ценой нарушения вышестоящего.

Например:

* нельзя обходить permission flow ради удобства UX;
* нельзя нарушать ACP ради упрощения реализации;
* нельзя связывать domain с Flutter ради сокращения количества кода;
* нельзя скрывать protocol error ради визуально стабильного UI.

---

## 3. Источники истины

### 3.1. Поведение продукта

Источник истины:

`openspec/specs/`

Код ДОЛЖЕН соответствовать утверждённым спецификациям.

Если код и спецификация противоречат друг другу, агент НЕ ДОЛЖЕН автоматически считать существующий код правильным.

---

### 3.2. Активные изменения

Активные изменения находятся в:

`openspec/changes/<change-name>/`

Перед реализацией change агент ОБЯЗАН прочитать существующие:

* `proposal.md`
* `specs/`
* `design.md`
* `tasks.md`

`design.md` конкретного change МОЖЕТ уточнять общую архитектуру в рамках этого изменения.

---

### 3.3. Архитектура

Источники архитектурных правил:

* `AGENTS.md`
* `docs/architecture/`

Этот файл содержит обязательные repository-wide правила.

`docs/architecture/` содержит подробное описание архитектуры и обоснование решений.

Вложенный `AGENTS.md` МОЖЕТ уточнять правила для своей директории и её поддиректорий.

---

### 3.4. ACP

ЗАПРЕЩЕНО придумывать методы, сообщения, поля, состояния или semantics ACP.

Источники истины:

* `openspec/specs/`
* `packages/acp_protocol/`

Если требуемое поведение ACP не определено, агент ДОЛЖЕН остановиться и запросить уточнение либо предложить OpenSpec change.

---

## 4. Технологический стек

Утверждённый стек описан в:

`docs/architecture/technology-stack.md`

Агент ОБЯЗАН переиспользовать существующие технологии проекта.

НЕ СЛЕДУЕТ добавлять новый framework или library для:

* state management;
* dependency injection;
* routing;
* persistence;
* networking;
* serialization;
* logging;

если в проекте уже существует утверждённое решение той же задачи.

Добавление технологии, меняющей архитектуру приложения, требует явного архитектурного решения.

Если изменение также влияет на поведение или контракт продукта, оно требует OpenSpec change.

Точные версии зависимостей определяются конфигурацией репозитория:

* `.fvm/fvm_config.json`
* `pubspec.yaml`
* `pubspec.lock`

Версии НЕ СЛЕДУЕТ дублировать в `AGENTS.md`.

---

## 5. Структура monorepo

Базовая структура:

```text id="52u0iq"
.
├── AGENTS.md
├── pubspec.yaml          # pub workspace и секция melos:
├── .fvm/
│   └── fvm_config.json
├── docs/
│   └── architecture/
├── openspec/
│   ├── specs/
│   └── changes/
├── apps/
│   └── codelab_app/
└── packages/
    ├── dart/
    │   ├── acp_protocol/
    │   ├── acp_transports/
    │   ├── acp_client_core/
    │   ├── acp_testing/
    │   ├── codelab_agent_core/
    │   └── codelab_architecture_tests/
    └── flutter/
        └── acp_ui/
```

Назначение пакетов:

* `acp_protocol` — типизированные модели ACP JSON-RPC, codecs и validation.
* `acp_transports` — заменяемые ACP transports (stdio, WebSocket, тестовые).
* `acp_client_core` — domain, application state и use cases ACP-клиента.
* `acp_testing` — fixtures, fake transports и helpers для conformance-тестов.
* `codelab_agent_core` — встраиваемое ядро Dart-агента на чистом Dart (LLM, цикл, инструменты, разрешения, сессии); правила — во вложенном `AGENTS.md` пакета.
* `codelab_architecture_tests` — только тесты: сторож импортов и allowlist зависимостей ядра (`melos run guard`).
* `acp_ui` — Fluent UI widgets рабочего места CodeLab.

Правила:

* `apps/*` МОГУТ зависеть от `packages/*`.
* Пакеты НЕ ДОЛЖНЫ зависеть от приложений.
* Циклические зависимости между пакетами запрещены.
* Пакеты в `packages/dart/` ДОЛЖНЫ оставаться pure Dart и НЕ ДОЛЖНЫ зависеть от Flutter.
* Пакеты в `packages/flutter/` МОГУТ зависеть от Flutter.
* `acp_ui` НЕ ДОЛЖЕН содержать application/business logic.
* `acp_testing` МОЖЕТ использоваться другими пакетами только как `dev_dependency`.
* `package:acp_transports/acp_transports.dart` ДОЛЖЕН оставаться web-безопасным; IO-транспорты (`StdioAcpTransport`, `WebSocketAcpTransport`) импортируются из `package:acp_transports/io.dart` только composition root и тестами.
* Клиенты (`apps/*`) НЕ ДОЛЖНЫ импортировать `package:codelab_agent_*` напрямую.
* Границы пакетов проверяет тест-сторож `packages/dart/codelab_architecture_tests` (`melos run guard`): правило нового пакета добавляется в `test/support/rules.dart` вместе с пакетом.

Архитектура Dart-агента — `docs/architecture/proposals/agent-core-architecture.md` (принята ADR-0001); план по этапам — `docs/architecture/proposals/dart-agent-and-clients.md`, дорожная карта — `docs/architecture/proposals/delivery-roadmap.md`.

Сторонний код НЕ ДОЛЖЕН копироваться — ни файлы, ни функции, ни тесты, ни промпты, ни фикстуры, в том числе из проектов с разрешительной лицензией. Если реализация близко воспроизводит внешний алгоритм, список или таблицу, источник указывается в документе и в комментарии кода, а запись добавляется в `THIRD_PARTY_NOTICES.md` (`docs/architecture/proposals/dart-agent-and-clients/07-decision-sources.md` §7а).

---

## 6. Архитектура приложения

Используется **feature-first architecture**.

Предпочтительная структура:

```text id="srlg2c"
apps/codelab_app/lib/
├── app/
├── core/
└── features/
    └── <feature>/
        ├── domain/
        ├── application/
        ├── infrastructure/
        └── presentation/
```

Не требуется создавать все слои для каждой feature.

ЗАПРЕЩЕНО создавать пустые слои и abstractions только ради формального соответствия архитектуре.

Основное направление зависимостей:

```text id="sjd6sn"
presentation
     ↓
application
     ↓
domain

infrastructure
     ↓
application / domain
```

Обязательные правила:

* `domain` НЕ ДОЛЖЕН зависеть от Flutter.
* `domain` НЕ ДОЛЖЕН зависеть от `infrastructure` или `presentation`.
* `application` НЕ ДОЛЖЕН зависеть от Flutter widgets или `BuildContext`.
* `presentation` НЕ ДОЛЖЕН напрямую обращаться к ACP transport, filesystem, storage, network или native APIs.
* `infrastructure` содержит adapters для внешних систем.
* Widgets НЕ ДОЛЖНЫ создавать repositories, ACP clients, storage clients или platform adapters.

Подробности:

`docs/architecture/layers-and-dependencies.md`

---

## 7. ACP boundary

`packages/acp_protocol` представляет **wire protocol**, а не UI state приложения.

Входящий поток:

```text id="jmv7zf"
ACP wire
   ↓
acp_protocol
   ↓
transport / client
   ↓
application mapping
   ↓
application / domain state
   ↓
presentation
```

Правила:

* Widgets НЕ ДОЛЖНЫ парсить ACP messages.
* Widgets НЕ ДОЛЖНЫ создавать или отправлять raw ACP messages.
* ACP transport НЕ ДОЛЖЕН знать о Flutter UI.
* ACP transport НЕ ДОЛЖЕН показывать dialogs или выполнять navigation.
* Protocol DTO НЕ СЛЕДУЕТ использовать как долгоживущий presentation state.
* Изменения wire protocol СЛЕДУЕТ локализовать на ACP/application boundary.
* ACP messages ДОЛЖНЫ иметь типизированные модели.
* Forward compatibility ДОЛЖНА сохраняться там, где этого требует ACP.

Перед изменением ACP integration агент ОБЯЗАН прочитать:

`docs/architecture/acp-boundary.md`

---

## 8. State management

Агент ОБЯЗАН использовать уже установленный в проекте state-management подход.

ЗАПРЕЩЕНО добавлять второй state-management framework без отдельного архитектурного решения.

Правила:

* Application/business state ДОЛЖЕН находиться вне widgets.
* Widgets НЕ ДОЛЖНЫ быть source of truth для session state.
* State СЛЕДУЕТ делать immutable там, где это практически оправдано.
* State transitions ДОЛЖНЫ быть явными и тестируемыми.

Session lifecycle СЛЕДУЕТ моделировать как явную state machine.

Не использовать набор независимых boolean flags, если они позволяют представить невозможные состояния:

```dart id="g3f5kh"
bool isConnected;
bool isConnecting;
bool isRunning;
bool isCancelling;
bool hasError;
```

Перед изменением session state агент ОБЯЗАН прочитать:

* `docs/architecture/session-lifecycle.md`
* `docs/architecture/state-management.md`

---

## 9. Streaming и lifecycle соединения

Streaming updates ДОЛЖНЫ обрабатываться предсказуемо и, где это допускает ACP, идемпотентно.

Правила:

* Duplicate/replayed events НЕ ДОЛЖНЫ повреждать state.
* Late events старого request/session/connection НЕ ДОЛЖНЫ изменять актуальный state.
* Reconnect НЕ ДОЛЖЕН создавать duplicate subscriptions.
* Long-lived subscription ДОЛЖЕН иметь явного owner.
* Subscription ДОЛЖЕН корректно отменяться при dispose owner.
* Race между cancellation и completion ДОЛЖЕН обрабатываться явно.
* Disconnect/reconnect ДОЛЖНЫ иметь явные application states.

Перед изменением streaming, reconnect, cancellation или subscriptions агент ОБЯЗАН прочитать:

* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`

---

## 10. Permissions и безопасность

Опасные действия agent ДОЛЖНЫ проходить через application-level permission policy, за исключением явно перечисленных ниже ACP client-side RPC методов.

Правила:

* Protocol layer НЕ ДОЛЖЕН показывать permission dialogs.
* Infrastructure НЕ ДОЛЖЕН напрямую запрашивать подтверждение пользователя.
* Widget НЕ ДОЛЖЕН определять, является ли действие опасным.
* Presentation только получает решение пользователя.
* Permission policy принадлежит application/security boundary.
* Неизвестная потенциально опасная capability по умолчанию ДОЛЖНА быть запрещена, если спецификация явно не требует другого.
* Permission request ДОЛЖЕН быть связан с правильным session/request/tool call.
* Решение пользователя для одного tool call НЕ ДОЛЖНО применяться к другому.
* Secrets и tokens НЕ ДОЛЖНЫ хардкодиться или попадать в logs.

### Исключение: ACP `fs/*` и `terminal/*` client-side методы

`fs/read_text_file`, `fs/write_text_file` и `terminal/create`/`terminal/output`/`terminal/wait_for_exit`/`terminal/kill`/`terminal/release` — это ACP-методы agent → client, для которых сама спецификация ACP делает `session/request_permission` опциональным (`MAY`) решением агента, а не обязательным шагом клиента (`docs/acp/protocol/08-Tool Calls.md#requesting-permission`, `09-File System.md`, `10-Terminal.md`).

Для этих методов CodeLab НЕ ДОЛЖЕН вводить собственный client-side approval-гейт — permission остаётся ответственностью агента. Это сознательное, явно принятое отступление от общего правила этого раздела, а не пробел.

Компенсирующий контроль, обязательный вместо approval: working directory containment — `path`/`cwd` из этих запросов ДОЛЖНЫ быть ограничены рабочей директорией активной сессии; выход за её пределы ДОЛЖЕН отклоняться как protocol/security error, до выполнения операции.

См. `openspec/changes/add-acp-fs-client-support/design.md` и `openspec/changes/add-acp-terminal-client-support/design.md` для полного обоснования и рассмотренных альтернатив.

Перед изменением permission flow агент ОБЯЗАН прочитать:

`docs/architecture/permissions.md`

---

## 11. Platform и filesystem

СЛЕДУЕТ предпочитать platform-independent Dart/Flutter code.

Platform-specific behavior ДОЛЖНО быть изолировано за явной abstraction boundary.

Не распространять проверки:

```dart id="f3rw7w"
Platform.isWindows
Platform.isMacOS
Platform.isLinux
```

по feature-коду.

Filesystem, native APIs, secure storage и process execution являются infrastructure concerns.

Widgets и domain НЕ ДОЛЖНЫ обращаться к ним напрямую.

Перед изменением platform-specific поведения агент ОБЯЗАН прочитать:

`docs/architecture/platform-integration.md`

---

## 12. Async и concurrency

ЗАПРЕЩЕНО блокировать Flutter UI isolate.

Правила:

* Long-running async operation ДОЛЖНА иметь понятный lifecycle.
* Операция, способная пережить своего owner, ДОЛЖНА иметь cancellation или stale-result protection.
* Ошибки fire-and-forget операций НЕ ДОЛЖНЫ теряться.
* `unawaited(...)` допустим только для намеренного и безопасного fire-and-forget поведения.
* СЛЕДУЕТ использовать `async/await` вместо ненужных `.then(...)` chains.
* CPU-heavy операции СЛЕДУЕТ выполнять вне UI isolate, если они могут заметно блокировать rendering.

Перед реализацией нетривиальной concurrency агент ОБЯЗАН прочитать:

`docs/architecture/concurrency.md`

---

## 13. Пропорциональность архитектуры

Архитектурные boundaries должны быть строгими, но реализация НЕ ДОЛЖНА создавать лишнюю церемониальность.

Abstraction оправдана, если обеспечивает хотя бы одно из следующего:

* изоляцию ACP/network/filesystem/platform API;
* независимое тестирование значимой логики;
* несколько реализаций;
* стабильную package/feature boundary;
* изоляцию нестабильной внешней зависимости.

НЕ СЛЕДУЕТ автоматически создавать:

```text id="ps5oxr"
FooRepository
FooRepositoryImpl
FooService
FooServiceImpl
FooManager
FooUseCase
```

для простой операции.

Use case оправдан, если операция:

* содержит application policy;
* координирует несколько dependencies;
* переиспользуется;
* имеет самостоятельную application semantics;
* требует независимого тестирования.

НЕ СЛЕДУЕТ создавать repository для простого ephemeral UI state.

Избегать generic сущностей:

* `Manager`
* `Helper`
* `Utils`
* `Common`
* `Service`

без узкой и очевидной ответственности.

Предпочитать минимальную архитектуру, сохраняющую необходимые boundaries.

---

## 14. Сначала существующие паттерны

Перед созданием нового механизма агент ОБЯЗАН изучить существующие реализации аналогичного поведения.

СЛЕДУЕТ переиспользовать established patterns для:

* state management;
* dependency injection;
* error handling;
* navigation;
* logging;
* serialization;
* controllers/notifiers;
* repositories;
* testing.

ЗАПРЕЩЕНО вводить competing architectural pattern, если существующий подход уже решает задачу.

Consistency важнее локальной архитектурной "идеальности".

---

## 15. Dart и Flutter conventions

Использовать:

* `dart format`
* `dart analyze`
* правила из `analysis_options.yaml`.

Правила:

* соблюдать Dart naming conventions;
* предпочитать immutable data там, где это оправдано;
* использовать типизированные errors/failures;
* НЕ бросать `String`;
* НЕ использовать generic `Exception`, если существует осмысленный typed error;
* production code НЕ ДОЛЖЕН использовать `print`;
* использовать единый project logger;
* business logic НЕ ДОЛЖНА находиться в `build()`;
* widgets должны быть сфокусированы на presentation и user interaction.

Публичный cross-package API СЛЕДУЕТ экспортировать через:

`lib/<package>.dart`

Внутри одного package МОЖНО использовать прямые internal imports.

НЕ СЛЕДУЕТ импортировать public barrel package из его собственной реализации, если это создаёт cycles или скрывает реальные dependencies.

---

## 16. Наблюдаемость

ACP behavior ДОЛЖНО оставаться диагностируемым.

Логировать значимые:

* connection lifecycle events;
* session lifecycle events;
* inbound/outbound protocol events;
* protocol errors;
* cancellation;
* reconnect;
* permission flow.

Sensitive fields ДОЛЖНЫ маскироваться.

При наличии использовать correlation identifiers:

* `session_id`
* `request_id`
* `message_id`
* `tool_call_id`

Полный protocol payload МОЖЕТ логироваться в debug builds, если это безопасно.

Sensitive protocol dumps НЕ ДОЛЖНЫ быть включены в release по умолчанию.

Подробнее:

`docs/architecture/observability.md`

---

## 17. OpenSpec workflow

OpenSpec change требуется при изменении:

* поведения продукта;
* ACP contracts;
* public APIs;
* persistence semantics;
* security behavior;
* существенной архитектуры.

Небольшие implementation-only изменения МОГУТ выполняться напрямую, если они не меняют observable behavior или contracts.

Перед реализацией агент ОБЯЗАН:

1. Прочитать соответствующую specification.
2. Найти active change, если он существует.
3. Прочитать его `proposal`, `design`, `specs` и `tasks`.
4. Определить затрагиваемые architecture documents.

ЗАПРЕЩЕНО молча менять specification под существующую реализацию.

---

## 18. Перед изменением кода

Перед реализацией задачи агент ОБЯЗАН:

1. Определить затрагиваемые packages и features.
2. Найти и прочитать ближайший применимый `AGENTS.md`.
3. Изучить существующие реализации аналогичного поведения.
4. Прочитать релевантные OpenSpec specifications.
5. Прочитать active OpenSpec change, если применимо.
6. Прочитать architecture documents для затрагиваемой boundary.
7. Определить слой, которому принадлежит новое поведение.
8. Переиспользовать существующие patterns, если это возможно.

Если задача конфликтует с approved specification, security rule или архитектурным invariant, агент ДОЛЖЕН сообщить о конфликте до реализации.

---

## 19. Scope discipline

Агент ДОЛЖЕН выполнять минимальное целостное изменение, необходимое для задачи.

Без необходимости НЕ ДОЛЖЕН:

* рефакторить unrelated code;
* переименовывать unrelated API;
* форматировать unrelated files;
* обновлять dependencies;
* добавлять frameworks;
* менять public API;
* менять ACP contracts;
* создавать unrelated abstractions.

Агент НЕ ДОЛЖЕН выполнять `git commit`, если пользователь явно этого не запросил.

---

## 20. FVM и Melos

Flutter SDK управляется через FVM.

Использовать:

```bash id="e8qfbg"
fvm flutter ...
fvm dart ...
```

НЕ использовать global Flutter SDK напрямую.

Monorepo управляется через Melos.

Основные команды:

```bash id="sz9ay3"
melos bootstrap
melos analyze
melos format
melos test
```

После изменения packages или dependencies выполнить:

```bash id="nxg1z3"
melos bootstrap
```

НЕ редактировать вручную generated:

`pubspec_overrides.yaml`

НЕ коммитить FVM SDK binaries.

---

## 21. Проверка изменений

Перед завершением задачи агент ОБЯЗАН проверить затронутый код.

Минимум:

1. Отформатировать изменённые Dart files.
2. Запустить static analysis для затронутых packages.
3. Запустить релевантные tests.
4. Выполнить более широкую проверку monorepo, если изменены shared packages, ACP, public APIs или cross-package dependencies.

Типовые команды:

```bash id="0qfwwm"
melos format
melos analyze
melos test
```

Полная проверка monorepo (format, analyze, tests, protocol conformance и клиентский прогон golden-фикстур ACP) — одной командой:

```bash
melos run check
```

Для локальных изменений МОЖНО использовать targeted FVM/Melos commands.

### Интеграционные тесты по типу ветки

* В ветках `feature/*` и `hotfix/*` интеграционные тесты ДОЛЖНЫ выполняться только на Dart VM — локально и в GitHub CI: тесты пакетов с реальными процессами и сокетами, protocol conformance, корпус ACP-фикстур (всё это входит в `melos run check`).
* В этих ветках НЕ СЛЕДУЕТ запускать прогоны на реальном устройстве или симуляторе (`melos run test:e2e:app:*`), и они НЕ ДОЛЖНЫ быть условием merge в `develop`.
* Прогон на реальном устройстве или симуляторе добавляется только в ветке `release/<version>` как приёмка выпуска.
* GitHub CI НЕ ДОЛЖЕН содержать device-, simulator- или macOS-джобов тестов для pull request в `develop`.

Агент НЕ ДОЛЖЕН утверждать, что проверка прошла, если команда фактически не запускалась.

Если проверку невозможно выполнить, агент ОБЯЗАН сообщить, какие команды не запускались и почему.

---

## 22. Git flow

Разработка ведётся по git flow.

Постоянные ветки:

* `master` — только выпущенное состояние; каждый merge в `master` — релиз или hotfix.
* `develop` — интеграционная ветка; в неё вливается вся текущая работа.

Временные ветки:

| Ветка | Создаётся от | Вливается в | Назначение |
|---|---|---|---|
| `feature/<name>` | `develop` | `develop` | новая функциональность, документация, рефакторинг, OpenSpec changes |
| `release/<version>` | `develop` | `master` и `develop` | подготовка выпуска: версия, changelog, исправления только для выпуска, прогон тестов на устройстве или симуляторе (§21) |
| `hotfix/<name>` | `master` | `master` и `develop` | срочное исправление выпущенной версии |

Правила:

* Прямые commits в `master` и `develop` ЗАПРЕЩЕНЫ; изменения попадают туда только через pull request.
* Новая работа ДОЛЖНА начинаться в `feature/<name>` от актуального `develop`.
* Pull request из `feature/*` ДОЛЖЕН открываться в `develop`, а не в `master`.
* `<name>` — короткое kebab-case имя задачи; для работы по OpenSpec change СЛЕДУЕТ использовать имя change: `feature/<change-id>`.
* Одна ветка `feature/*` СЛЕДУЕТ одной задаче или одному OpenSpec change.
* Перед pull request ветку СЛЕДУЕТ обновить от `develop`; проверки §21 ДОЛЖНЫ проходить на обновлённой ветке.
* Слияние в `develop` выполняется после ревью; агент НЕ ДОЛЖЕН сливать pull request без явного разрешения пользователя.
* После слияния ветку `feature/*` СЛЕДУЕТ удалить локально и в `origin`.
* Выпуск: `release/<version>` вливается в `master`, merge commit в `master` помечается тегом версии, затем `release/<version>` вливается обратно в `develop`.
* `hotfix/*` после слияния в `master` ДОЛЖЕН быть влит и в `develop` (или в активную `release/*`, если она существует).
* Сообщения commits — Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`), как в существующей истории.

Правило §19 остаётся в силе: агент НЕ ДОЛЖЕН выполнять `git commit`, `git push` или открывать pull request, если пользователь явно этого не запросил.
