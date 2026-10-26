## Context

Этап 5 плана `dart-agent-and-clients` (`09-10-stage-5-client-kit.md`) выносит логику клиента из app в общий слой. Сейчас:

- `CodeLabShellCubit` (`apps/codelab_app/lib/features/workbench/application/shell_cubit.dart`, ~2300 строк) держит всё: формы профилей, подключение и переподключение, сессии, очередь промптов (`_queuedPromptsBySession`), отмену, одобрения, опции конфигурации, палитру, план, проекцию транскрипта (пересчёт всей `AcpSession` на каждое изменение), инспектор, диагностику с редакцией секретов, ширины панелей.
- Источник истины протокола — `AcpClientApplication` из `acp_client_core`: `sessionChanges`, `connectionStateChanges`, `generation`, методы `connect`/`createSession`/`sendPrompt`/`cancelTurn`/`reconnect`/`respondToPermission`/`setSessionConfigOption`. Cubit обращается к ним через use case-ы (`CreateSession`, `SendPrompt`, … — `TaskEither`).
- DI — cherrypick: `CodeLabPresentationModule` в `apps/codelab_app/lib/app/app_scope.dart` собирает Cubit из 13 зависимостей.
- `dart:io`-адаптеры (`IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`) лежат в `apps/codelab_app/lib/core/platform/`, хотя Flutter им не нужен.
- Тесты: 8 интеграционных тестов `integration_test/` (прогон на устройстве — только `release/<version>`, `AGENTS.md` §21) и `test/widget_test.dart` (~4700 строк, 31 `testWidgets`, читают `shellCubit.state`).
- Сторож уже содержит заготовку правил этапа 5 (`codelab_architecture_tests/test/support/rules.dart`: `acp_client_kit — webUnsafe; acp_client_io — ['package:flutter/']`).

Этап 5 разбит на четыре change (`09-10`, «OpenSpec change»). Этот — `extract-acp-client-kit`: задачи 5.0, 5.1, 5.3–5.9, только перенос без изменения поведения.

## Goals / Non-Goals

**Goals:**
- Логика клиента без UI — в `acp_client_kit` (чистый Dart, web-безопасный), `dart:io`-адаптеры — в `acp_client_io`; оба готовы для codelab_cli (этап 6).
- Поведение app и публичная поверхность `CodeLabShellCubit` неизменны: публичные методы, поля `CodeLabShellState`, ключи виджетов, `codeLabDependenciesOf(...).shellCubit`.
- Каждый перенос защищён характеризационными тестами 5.0, `widget_test.dart` и сборкой 8 интеграционных тестов.
- После 5.9 в `shell_cubit.dart` нет логики из левого столбца таблицы переноса `09-10` (цель — меньше 600 строк).

**Non-Goals:**
- `session/list`, `session/load` в UI, таймауты запросов, переподключение с повторами и загрузкой сессий, восстановление после перезапуска (задачи 5.2, 5.10, 5.12) — change `add-session-list-and-reload`.
- Тест палитры R-20, режим `withAvailableCommands`, нечёткий поиск по подпоследовательности — change `add-command-palette-agent-commands`.
- Сторож запуска (5.11) — change `add-app-boot-watchdog`.
- Члены API «после MVP» (`restart`, `steer`, `openSessionSearch`, `recordId`, …) — их нет в коде, заглушек тоже нет (`09-10`, «Правило для членов „после MVP“»).
- `EmbeddedProfile` — появляется с этапом 7 (§9.12): до встроенного агента резолвера для него нет.
- Сохранение профилей app в `ProfileStore`: app продолжает держать профиль в состоянии формы, как сейчас; `JsonFileProfileStore` нужен CLI.
- Перевод тестов на новые Cubit-ы и удаление фасада — после этапа 9, отдельным change.

## Decisions

### D1. Характеризационные тесты 5.0 — `flutter_test`, без `bloc_test`

Файлы `apps/codelab_app/test/features/workbench/application/shell_cubit_characterization/` по таблице `09-10` (задача 5.0): `connection_test`, `sessions_test`, `prompt_test`, `cancel_test`, `config_option_test`, `permission_test`, `reconnect_test`. Cubit создаётся через `CodeLabTestBinding` (`test/support/test_app_scope.dart`) → `createCodeLabRootScope` с `FakeAcpTransport` и разрешается из `bind<CodeLabShellCubit>()`: так тесты закрывают и проводку DI, которая меняется в 5.1–5.9.

Тесты утверждают только публичную поверхность и конечные состояния (`expectLater(cubit.stream, emitsThrough(...))`, проверка `cubit.state` после событий), а не точное число `emit`. Исключение — `reconnect_test`: «одно событие — один `emit`» проверяется сравнением числа состояний с одинаковым содержимым подряд, а не общим числом. Причина — D6: kit склеивает изменения в микрозадаче, и точная последовательность промежуточных `emit` может законно измениться.

Альтернатива — `bloc_test`: удобнее `blocTest(..., expect: [...])`, но это новая dev-зависимость ради синтаксиса, и она подталкивает к проверке точной последовательности состояний, которая хрупка при переносе. Отклонено.

Исключение (а) правила TDD (`09-00` §9.0, п. 3): тесты 5.0 пишутся на текущее поведение и зелёные сразу; коммитятся отдельным PR до первого переноса, код app не меняется.

### D2. Пакеты и границы

- `packages/dart/acp_client_kit`: `dependencies` ⊆ `{acp_client_core, acp_protocol, acp_transports, freezed_annotation, meta, collection, async}`; правило сторожа — `webUnsafe` (без `dart:io`, Flutter и `acp_transports/io.dart`). Модели — freezed, как в `acp_client_core`.
- `packages/dart/acp_client_io`: `dependencies` ⊆ `{acp_client_kit, acp_client_core, acp_protocol, acp_transports, path, meta}`; правило — `['package:flutter/']`. Единственное место вне app, где импортируется `acp_transports/io.dart` для клиента.
- `apps/codelab_app` зависит от обоих; `acp_ui` их не импортирует (UI-модели строятся мапперами app, D10).
- Публичный API — `lib/acp_client_kit.dart` и `lib/acp_client_io.dart`; реализации — `lib/src/<область>/` (`AGENTS.md` §15).

### D3. Порт `AgentBackend` и `AcpClientBackend`

`AgentBackend` — внутренний порт источника данных kit (эскиз `09-10`), реализация `AcpClientBackend` — тонкая обёртка над `AcpClientApplication`: те же потоки (`connectionStates`, `sessionChanges`, `diagnostics`) и методы. Ошибки — исключения `AcpClientApplication`, как сейчас; kit переводит их в `WorkspaceDiagnostic` через `describeFailure` (D9). Use case-ы `acp_client_core` в kit не используются: они добавляют только `TaskEither` вокруг тех же вызовов, а политика (когда слать, что делать при ошибке) теперь в kit.

На этом change в `AgentBackend` нет `listSessions` и `loadSession` в UI-смысле: `loadSession` объявлен, потому что он уже есть в ядре клиента, но `ClientWorkspace.loadSession` и `listSessions` добавляет `add-session-list-and-reload` вместе с поведением.

### D4. `ClientWorkspace`, `SessionHandle`, `ConnectionView`

Форма API — эскиз `09-10` без членов «после MVP», `loadSession`/`listSessions` (D3) и `EmbeddedProfile`. Явный конечный автомат `ConnectionView` (`Disconnected`, `Connecting`, `Connected`, `Reconnecting`, `ConnectionFailed`) вместо флагов (`AGENTS.md` §8). `Reconnecting` на этом change всегда `attempt: 1`: повторов нет, как сейчас.

`reconnect()` повторяет текущее поведение Cubit: одна попытка через `AgentBackend.reconnect` с фабрикой транспорта текущего профиля, без `session/load`. Алгоритм с повторами и загрузкой сессий (`09-10`, «Алгоритм переподключения») — в `add-session-list-and-reload`.

Флаги совместимости `CodeLabShellState` (таблица переноса, строка «Флаги состояния») считает фасад: `isPromptSubmitting = canCancel = SessionView.status` активной сессии `running` (в том числе с ожидающими одобрениями) или `cancelling`; `isRespondingToConfigOption = configOptionInFlight != null`; повторный `setConfigOption` во время запроса — no-op.

### D5. Инкрементальная проекция транскрипта

`TranscriptProjector` (`lib/src/transcript/`) — алгоритм `09-10` («Алгоритм инкрементальной проекции транскрипта»), шаги 1–7. Состояние — список `TranscriptItem` и индекс `toolCallId → позиция`; номер последнего обработанного обновления на сессию: повтор — no-op (`AGENTS.md` §9). `TranscriptItem` — `UserItem`, `AgentTextItem`, `ThoughtItem`, `ToolCallItem`, `NoticeItem` с полями из `§12.1.1` в объёме, который сегодня показывает app; новые поля (`markdown`, `startedAt`, `attachments`) — вместе с функциями, которые их показывают.

Поведение должно совпасть с `_transcriptEntriesForSession` и требованием «Схлопывание потоковых сообщений агента в transcript» спецификации `agent-workbench-ui`. Доказательство — тест `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`: каждая фикстура корпуса с ролью `client` проигрывается `runClientFixture` (`acp_testing`), на каждом шаге проекция с нуля по полному списку обновлений сравнивается с инкрементальной.

### D6. Публикация `SessionView` и `WorkspaceState`

Изменения склеиваются в микрозадаче (`scheduleMicrotask`): одно `session/update` → один новый `SessionView` с `revision + 1`, пачка обновлений в одном событии цикла → один. Kit — чистый Dart и не знает о кадрах UI; «не чаще одного раза за кадр» (`09-10`, шаг 8) обеспечивает склейка в микрозадаче, а дальнейшая синхронизация с кадром — забота UI. Поздние события старого поколения (`AcpClientApplication.generation`) отбрасываются до проектора (`AGENTS.md` §9).

### D7. Очередь промптов

`PromptQueue` на сессию (`lib/src/queue/`): перенос `submitPrompt`, `_dispatchPrompt`, `_drainQueueIfFree`, `editQueuedPrompt`, `deleteQueuedPrompt`, `sendQueuedPromptNow`, `clearQueuedPrompts`. Id элементов монотонны в пределах `ClientWorkspace` и не переиспользуются (как `_nextQueuedPromptId`). `SessionHandle.send` — сессия свободна → `session/prompt`, занята → в очередь; конец хода → первый элемент уходит автоматически. Очереди не сохраняются и в агент не отправляются (`add-prompt-queue/design.md`, Non-Goals).

`editQueuedPrompt(id)` сегодня возвращает текст в композер и удаляет элемент — это поведение UI; в kit — `PromptQueue.remove(id)` и возврат текста, композер заполняет Cubit.

### D8. Профили и резолверы транспорта

`ConnectionProfile` — `StdioProfile`, `WebSocketProfile` (`lib/src/connection/`); `parseShellWords` (перенос `_splitShellWords`) и `describeProfile` (перенос `selectedProfileLabel`/`selectedConnectionDetail`) — чистые функции kit. `TransportResolver` — порт kit; `StdioTransportResolver` и `WebSocketTransportResolver` — в `acp_client_io` поверх `StdioAcpTransport`/`WebSocketAcpTransport`. Фабрики app `CodeLabStdioTransportFactory`/`CodeLabWebSocketTransportFactory` остаются только как обёртки для тестов (`CodeLabTestBinding` подставляет `FakeAcpTransport`): резолвер в тестах — тестовый, который отдаёт фейковый транспорт.

Токен WebSocket в `WebSocketProfile` — ссылка `tokenRef`, значение даёт порт `SecretSource` (kit), который вызывает резолвер. App держит токен в состоянии формы, как сейчас, и передаёт его через `InMemorySecretSource` по ссылке профиля; в файлы и логи значение не попадает. CLI на этапе 6 подставит источник из переменной окружения.

`ProfileStore` и `RecentProjectsStore` — порты kit. `JsonFileProfileStore` (`~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore` — в `acp_client_io`; app подключает только `RecentProjectsStore` на `shared_preferences` (как сейчас), `ProfileStore` app не использует (Non-Goals).

### D9. Команды, опции, инспектор, диагностика

- `CommandCatalog` (`lib/src/commands/`): слияние клиентских команд и `available_commands_update` активной сессии, разрешение конфликтов имён — перенос `paletteActions`, `_agentCommandsFor`, `_agentCommandAction`. Сопоставление текста запроса остаётся в `acp_ui` (`AcpCommandAction.filter`, подстрока) — переносится в kit и заменяется нечётким поиском в `add-command-palette-agent-commands`, вместе с тестом R-20. Так поведение палитры на этом change не меняется.
- `ConfigOptionView` (`lib/src/config/`) — перенос `_configOptionsFor`.
- `InspectorProjection` (`lib/src/inspector/`) — перенос `_inspectorEntriesFor*`; используется и командой CLI `/inspect` (этап 6).
- `WorkspaceDiagnostic` и `describeFailure` (`lib/src/diagnostics/`) — перенос `_recordDiagnostic`, `_failureMessage`, `_cleanDomainFailureMessage`; редакция секретов — `SecretRedactor` из `acp_client_core` до публикации (`AGENTS.md` §10, §16).

### D10. Разделение Cubit-ов (5.9) и мапперы

После 5.1–5.8 `CodeLabShellCubit` делится на `ConnectionCubit` (профиль-черновик, подключение), `SessionsCubit` (список, выбор), `ActiveSessionCubit` (транскрипт, очередь, одобрения, опции, план), `SettingsCubit` (проект, недавние проекты, запуск из папки проекта), `LayoutCubit` (ширины панелей, палитра открыта). Каждый получает `ClientWorkspace` (или его часть) из cherrypick. `CodeLabShellCubit` остаётся фасадом: подписывается на них и собирает прежний `CodeLabShellState`, публичные методы делегирует. Маппинг `SessionView`/`WorkspaceState` → модели `acp_ui` (`AcpTranscriptEntry`, `AcpSessionListItem`, `AcpApprovalOption`, `AcpConfigOption`, `CodeLabInspectorEntry`) — `features/workbench/application/ui_mappers.dart`. Виджеты на этом change продолжают читать фасад.

### D11. Сторож

`rules.dart`: `PackageRule('packages/dart/acp_client_kit', forbidden: webUnsafe)`, `PackageRule('packages/dart/acp_client_io', forbidden: ['package:flutter/'])` (строки-заготовки этапа 5 заменяются правилами); allowlist зависимостей обоих пакетов — в `pubspec_allowlist_test.dart` (D2). Транзитивная проверка «kit без `dart:io`» следует из правил: все пакеты в `dependencies` kit сами под `webUnsafe` (`acp_client_core`, `acp_protocol`, `acp_transports` без `io.dart`).

### D12. Итерации и PR

Каждая итерация — PR в `develop` из `feature/extract-acp-client-kit`, ветка заново от `develop` после слияния; красный тест — отдельным коммитом до реализации (кроме 5.0, D1).

1. **5.0** — характеризационные тесты; код app не меняется.
2. **5.1** — пакет `acp_client_kit` с API (D4), `AcpClientBackend`, сторож; фасад: Cubit получает `ClientWorkspace` и переводит на него подключение и сессии.
3. **5.3** — `TranscriptProjector` и тест на фикстурах.
4. **5.4** — `PromptQueue` и отмена.
5. **5.5 + 5.8** — профили, резолверы, `acp_client_io` (перенос адаптеров, `JsonFile*Store`): резолверы stdio/WebSocket живут в `acp_client_io`, поэтому задачи идут одним PR.
6. **5.6 + 5.7** — `CommandCatalog`, `ConfigOptionView`, `InspectorProjection`, диагностика.
7. **5.9** — разделение Cubit-ов, `ui_mappers.dart`, проверка размера `shell_cubit.dart`.

После каждой итерации: тесты 5.0 и `widget_test.dart` зелёные без правок, `melos run check` зелёный, 8 интеграционных тестов собираются (`analyze`).

## Risks / Trade-offs

- **[Перенос меняет поведение незаметно для тестов]** → тесты 5.0 пишутся первыми и не правятся до конца change; `widget_test.dart` уже читает `shellCubit.state` в 31 сценарии; свойство «инкрементальная проекция == пересчёт» на всём клиентском корпусе фикстур (D5).
- **[Склейка в микрозадаче меняет порядок или число `emit`]** → тесты 5.0 проверяют конечные состояния (D1); виджеты читают итоговое состояние, а не промежуточные.
- **[Логика снова расползается по Cubit-ам]** → правило ревью «логика — в kit, в Cubit — только отображение»; сторож запрещает Flutter в kit; цель < 600 строк для `shell_cubit.dart` после 5.9.
- **[Изменения `add-file-preview-and-tree` и `add-integrated-terminal` (не начаты) спроектированы поверх нынешнего `shell_cubit.dart`]** → при их реализации логика добавляется в kit; их `design.md` получают ссылку на этот change при старте.
- **[Долгая серия PR]** → итерации мелкие (D12), каждая сохраняет зелёный `develop`; фасад позволяет остановиться после любой итерации.

## Migration Plan

Внешних контрактов нет: ACP-поведение клиента не меняется, данные пользователя (недавние проекты в `shared_preferences`) остаются на месте. Откат — revert PR итерации: фасад сохраняет прежнюю поверхность после каждой итерации.

## Open Questions

Нет — решения по `bloc_test` (D1), объединению итераций (D12) и поиску палитры (D9) приняты выше и подтверждаются при ревью change.
