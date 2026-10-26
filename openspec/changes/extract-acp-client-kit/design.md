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

Тесты утверждают только публичную поверхность и конечные состояния (`expectLater(cubit.stream, emitsThrough(...))`, проверка `cubit.state` после событий), а не точное число `emit`. Исключение — `reconnect_test`: «одно событие — один `emit`» проверяется сравнением числа состояний с одинаковым содержимым подряд, а не общим числом. Причина — перенос в kit может законно изменить последовательность промежуточных `emit` (например, публикацию из двух источников вместо одного), а конечные состояния — нет.

Альтернатива — `bloc_test`: удобнее `blocTest(..., expect: [...])`, но это новая dev-зависимость ради синтаксиса, и она подталкивает к проверке точной последовательности состояний, которая хрупка при переносе. Отклонено.

Исключение (а) правила TDD (`09-00` §9.0, п. 3): тесты 5.0 пишутся на текущее поведение и зелёные сразу; коммитятся отдельным PR до первого переноса, код app не меняется.

### D2. Пакеты и границы

- `packages/dart/acp_client_kit`: `dependencies` ⊆ `{acp_client_core, acp_protocol, acp_transports, freezed_annotation, meta, collection, async}`; правило сторожа — `webUnsafe` (без `dart:io`, Flutter и `acp_transports/io.dart`). Модели — freezed, как в `acp_client_core`.
- `packages/dart/acp_client_io`: `dependencies` ⊆ `{acp_client_kit, acp_client_core, acp_protocol, acp_transports, path, meta}`; правило — `['package:flutter/']`. Единственное место вне app, где импортируется `acp_transports/io.dart` для клиента.
- `apps/codelab_app` зависит от обоих; `acp_ui` их не импортирует (UI-модели строятся мапперами app, D10).
- Публичный API — `lib/acp_client_kit.dart` и `lib/acp_client_io.dart`; реализации — `lib/src/<область>/` (`AGENTS.md` §15).

### D3. Порт `AgentBackend` и `AcpClientBackend`

`AgentBackend` — внутренний порт источника данных kit (эскиз `09-10`), реализация `AcpClientBackend` — тонкая обёртка над `AcpClientApplication`: те же потоки (`connectionStates`, `sessionChanges`, `diagnostics`) и методы. Члены порта появляются вместе с итерацией, которая переносит их потребителя в kit (D12): итерация 2 — `connectionStates`, `sessionChanges`, `connect`, `reconnect`, `createSession`. Поздние события старого поколения отбрасывает сам `AcpClientApplication` (отписка от старого транспорта при замене), kit на это опирается и проверяет тестом. `ClientWorkspace.dispose` отписывается от бэкенда, но не закрывает его: `AcpClientApplication` закрывает его владелец (в app — `CodeLabRootLifecycle`). Ошибки — исключения `AcpClientApplication`, как сейчас; kit переводит их в `WorkspaceDiagnostic` через `describeFailure` (D9). Use case-ы `acp_client_core` в kit не используются: они добавляют только `TaskEither` вокруг тех же вызовов, а политика (когда слать, что делать при ошибке) теперь в kit.

На этом change в `AgentBackend` и `ClientWorkspace` нет `listSessions` и `loadSession`: их добавляет `add-session-list-and-reload` вместе с поведением.

### D4. `ClientWorkspace`, `SessionHandle`, `ConnectionView`

Форма API — эскиз `09-10` без членов «после MVP», `loadSession`/`listSessions` (D3) и `EmbeddedProfile`. Явный конечный автомат `ConnectionView` (`Disconnected`, `Connecting`, `Connected`, `Reconnecting`, `ConnectionFailed`) вместо флагов (`AGENTS.md` §8). `Reconnecting` на этом change всегда `attempt: 1`: повторов нет, как сейчас.

`reconnect({profile, projectDirectory})` повторяет текущее поведение Cubit: одна попытка через `AgentBackend.reconnect` с транспортом от резолвера профиля, без `session/load`. Переданные `profile` и `projectDirectory` заменяют текущие: Cubit переподключается с профилем из формы, которую пользователь мог изменить после `connect()` (характеризационный тест `cwd` при переключателе «Run agent from project directory»). Без аргументов — профиль последнего подключения; без него — `ClientWorkspaceException`. Отказы kit (нет соединения, нет профиля, нет резолвера) — `ClientWorkspaceException` и наследник `UnsupportedConnectionProfileException`; ошибки транспорта и агента — исключения `acp_client_core`, их kit пробрасывает после публикации `ConnectionFailed`.

Конструктор фасада сохраняет прежние параметры: `widget_test.dart` создаёт `CodeLabShellCubit` напрямую, а его текст не меняется. Граф cherrypick передаёт `workspace` и `secrets`; без них Cubit строит `ClientWorkspace` сам поверх `application` и фабрик транспорта и закрывает его в `close()`. Параметры `createSessionUseCase` и `reconnectUseCase` после итерации 2 не используются и удаляются вместе с фасадом после этапа 9. Алгоритм с повторами и загрузкой сессий (`09-10`, «Алгоритм переподключения») — в `add-session-list-and-reload`.

Флаги совместимости `CodeLabShellState` (таблица переноса, строка «Флаги состояния») считает фасад: `isPromptSubmitting = canCancel = SessionView.status` активной сессии `running` (в том числе с ожидающими одобрениями) или `cancelling`; повторный `SessionHandle.setConfigOption` во время запроса — no-op (`configOptionInFlight`). Флаги `isRespondingToConfigOption` и `isRespondingToApproval` фасад держит сам, как раньше: они глобальны для окна и сбрасываются при потере соединения, а запрос в полёте при неожиданном сбое транспорта ядро не завершает — флаг из `configOptionInFlight` остался бы поднятым.

### D5. Инкрементальная проекция транскрипта

`TranscriptProjector` (`lib/src/transcript/`) — инкрементальная проекция по снимкам `AcpSession` из `sessionChanges`. Состояние — проекции ходов: элементы из обновлений хода, индекс `toolCallId → позиция`, число обработанных обновлений и открытый отрезок потокового текста. На очередной снимок обрабатываются только новые `session/update` изменившегося хода (неизменный объект хода — no-op, `AGENTS.md` §9); статус вызовов и одобрения перечитываются из read-модели хода, как и раньше (embed-approval-in-thread/design.md, Decision 1). `TranscriptItem` — `UserItem`, `AgentTextItem`, `ThoughtItem`, `ToolCallItem` (`details`: вид, статус, команда; встроенное одобрение `ApprovalStateView`), `NoticeItem` — в объёме, который сегодня показывает app; новые поля (`markdown`, `startedAt`, `attachments`) — вместе с функциями, которые их показывают.

Поведение совпадает с `_transcriptEntriesForSession` до переноса и требованием «Схлопывание потоковых сообщений агента в transcript» спецификации `agent-workbench-ui`, поэтому алгоритм `09-10` уточняется там, где он расходится с текущим поведением app:

- `tool_call_update` без `tool_call` элемента не создаёт (шаг 4 `09-10`); одобрение такого вызова — элемент вызова в конце хода, после всех обновлений хода.
- `NoticeItem` — только `error` («Failed to send prompt: …», без префикса типа исключения) и `emptyTurn` («Completed with stopReason …» для завершённого хода без вывода агента); отдельного уведомления об отмене нет (шаг 7 `09-10`): отмену показывает статус вызова `cancelled`.
- Пустой после `trim` отрезок текста элемента не даёт.

Эталон — `projectTranscript(AcpSession)`: перенос алгоритма Cubit, пересчёт с нуля. Доказательство — тест `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`: каждая фикстура корпуса с ролью `client` проигрывается `runClientFixture`, и на каждом изменении сессии инкрементальная проекция сравнивается с эталоном. Драйвер действий пользователя `ClientFixtureUser` вынесен из теста `acp_client_core` в `acp_testing` и общий для обоих тестов.

Id элементов kit стабильны (`<turnId>/text-<i>`, `<turnId>/tool-<toolCallId>`): растущий текст сохраняет id. Фасад отдаёт `acp_ui` прежние позиционные id (`prompt-N`, `agent-N`, `tool-N`, `prompt-error-N`).

### D6. Публикация `SessionView` и `WorkspaceState`

`WorkspaceState` и `SessionView` публикуются синхронно (`StreamController.broadcast(sync: true)`): одно изменение сессии в ядре клиента → один `SessionView` с `revision + 1`. Склейки в микрозадаче на этом change нет: фасад и тесты 5.0 читают транскрипт сразу после `session/update`, без ожидания, и тексты тестов меняться не должны. Выигрыш производительности даёт сама инкрементальная проекция; «не чаще одного раза за кадр» (`09-10`, шаг 8) — забота UI-слоя (`TranscriptViewCubit` после 5.9). Фасад читает `SessionHandle.current` из своего обработчика `sessionChanges`: рабочее пространство подписано на поток раньше Cubit, а синхронный широковещательный поток доставляет события в порядке подписки. Поздние события старого поколения отбрасывает `AcpClientApplication` до проектора (`AGENTS.md` §9).

### D7. Очередь промптов

`PromptQueue` на сессию (`lib/src/queue/`): перенос `submitPrompt`, `_dispatchPrompt`, `_drainQueueIfFree`, `editQueuedPrompt`, `deleteQueuedPrompt`, `sendQueuedPromptNow`, `clearQueuedPrompts`. Элемент — `QueuedPrompt(id, text)`; id `queued-N` монотонны в пределах `ClientWorkspace` и не переиспользуются (как `_nextQueuedPromptId`). Очередь — поле `SessionView.queue`; каждое изменение публикует новый `SessionView`. Очереди не сохраняются и в агент не отправляются (`add-prompt-queue/design.md`, Non-Goals).

- `SessionHandle.send(text)`: сессия свободна → `session/prompt`, занята (`SessionView.status` — `running` или `cancelling`) → элемент очереди и исход `PromptQueued`. Future завершается после конца хода и слива очереди, которую этот ход освободил, — как прежний `submitPrompt`; на это опираются тесты 5.0, которые ждут `submitPrompt` после ответа агента.
- Слив — как в Cubit: после каждого `session/prompt` kit заново проверяет «сессия свободна и очередь не пуста» и отправляет первый элемент. Слив по событию статуса из `sessionChanges` отклонён: отправка из обработчика синхронного потока вызвала бы вложенную публикацию в тот же поток.
- Исход каждого хода — и отправленного хостом, и ушедшего из очереди — `PromptCompleted(turn)` или `PromptFailed(error)` в `ClientWorkspace.promptOutcomes` (синхронно); фасад пишет по нему прежнюю диагностику `Prompt completed with stopReason …` / `Failed to send prompt: …` и обновляет `queuedPrompts`.
- `PromptQueue.remove(id)` возвращает элемент: «редактировать» в app — убрать из очереди и вернуть текст в композер, это делает Cubit. `edit(id, text)` из эскиза `09-10` не нужен ни app, ни CLI этапа 6 и не вводится.
- `PromptQueue.sendNow(id)` отправляет элемент вне очереди только в свободной сессии; в занятой — no-op, элемент на месте (поведение `sendQueuedPromptNow`). Отмена хода с отправкой элемента (эскиз `09-10`) — новое поведение, вне этого change.
- `SessionHandle.cancel()` — `session/cancel`; сессия остаётся `cancelling`, пока агент не ответит на отменённый `session/prompt`, и тогда очередь сливает завершившийся `send` этого хода. Слив после ответа на одобрение (`respondToApproval`) не нужен: пока одобрение ожидает, сессия занята, а конец хода сливает очередь сам.
- Флаги фасада `isPromptSubmitting = status ∈ {running, cancelling}`, `canCancel = status == running` (D4).

### D8. Профили и резолверы транспорта

`ConnectionProfile` — `StdioProfile`, `WebSocketProfile` (`lib/src/connection/`, итерация 2: без них нет `ClientWorkspace.connect`); `parseShellWords` и `parseEnvLines` (перенос `_splitShellWords` и `_parseEnv`, без разбора кавычек, как в форме app) — чистые функции kit (итерация 5). `describeProfile` не вводится: `selectedProfileLabel`/`selectedConnectionDetail` описывают черновик формы app (в том числе незаполненный), а не профиль, и у функции описания профиля на этом change нет потребителя; её добавит CLI этапа 6 вместе с `codelab profiles list`. `TransportResolver` — порт kit. Перевод профиля в `StdioAcpTransportConfig`/`WebSocketAcpTransportConfig` одинаков для всех хостов, поэтому он в kit: `ConfigTransportResolver(stdio:, webSocket:, secrets:)` принимает фабрики транспортов по конфигурации; `runInProjectDirectory` превращается в `cwd` процесса только здесь. `acp_client_io` даёт `ioTransportResolver({secrets})` — `ConfigTransportResolver` с фабриками `StdioAcpTransport`/`WebSocketAcpTransport` (итерация 5): отдельные `StdioTransportResolver` и `WebSocketTransportResolver` дублировали бы перевод профиля в конфигурацию. App по-прежнему передаёт свои фабрики, чтобы тестовый граф подставлял `FakeAcpTransport`. Фабрики app `CodeLabStdioTransportFactory`/`CodeLabWebSocketTransportFactory` передаются в `ConfigTransportResolver`; `CodeLabTestBinding` подставляет `FakeAcpTransport`.

Токен WebSocket в `WebSocketProfile` — ссылка `tokenRef`, значение даёт порт `SecretSource` (kit), который вызывает резолвер. App держит токен в состоянии формы, как сейчас, и передаёт его через `InMemorySecretSource` (kit: тот же источник нужен тестам и CLI) по ссылке профиля; в файлы и логи значение не попадает. CLI на этапе 6 подставит источник из переменной окружения.

`ProfileStore` и `RecentProjectsStore` (с `RecentProject` и `recentProjectsLimit`) — порты kit. `JsonFileProfileStore` (`{"version": 1, "profiles": [...]}`, путь задаёт хост: у CLI — `~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore` — в `acp_client_io`; нет файла — пустой список, битый файл — `FormatException`, запись — через временный файл и переименование. App подключает только `RecentProjectsStore` на `shared_preferences` (как сейчас), `ProfileStore` app не использует (Non-Goals). `WorkingDirectoryProvider` вместе с `IoWorkingDirectoryProvider` переезжает в `acp_client_io`: порт нужен только хостам на `dart:io`.

Прежние пути app `core/platform/recent_projects_store.dart` и `core/platform/working_directory_provider.dart` остаются реэкспортом kit и `acp_client_io`: по ним импортируют `widget_test.dart` и интеграционный тест, тексты которых не меняются до конца change. Код `lib/` app импортирует пакеты напрямую.

### D9. Команды, опции, инспектор, диагностика

- Команды агента — `SessionView.agentCommands` (`AgentCommandView`: имя, описание, подсказка; `lib/src/session/`) — перенос `_agentCommandsFor`. `CommandCatalog` (клиентские команды + команды агента, разрешение конфликтов имён, поиск) на этом change не вводится: клиентские команды палитры заданы в `acp_ui` вместе с иконками (`AcpCommandAction.defaults`), конфликтов app сегодня не разрешает — обе команды видны в палитре, а сопоставление запроса — подстрока `AcpCommandAction.filter`. Каталог, нечёткий поиск и тест R-20 — change `add-command-palette-agent-commands`; поведение палитры здесь не меняется.
- `ConfigOptionView` (`lib/src/session/`) — перенос `_configOptionsFor`; `SessionView.configOptions`, `configOptionInFlight` и `SessionHandle.setConfigOption` (D4).
- Одобрения — `SessionView.pendingApprovals` (тот же `PendingApprovalView`, что в транскрипте) и `SessionHandle.respond`, перенос `respondToApproval`: ядро клиента отклоняет ответ на одобрение другой сессии (PERM-003).
- `InspectorProjection` (`lib/src/inspector/`) — перенос `_inspectorEntriesFor*`; проекция по запросу хоста, а не поле `SessionView`: пересчёт на каждое изменение каждой сессии вернул бы стоимость O(обновлений хода) на каждый фрагмент ответа. Используется и командой CLI `/inspect` (этап 6). Фасад сохраняет прежние имена `CodeLabInspectorEntry`/`CodeLabInspectorCategory`/`CodeLabInspectorDetail` как `typedef` моделей kit.
- `describeFailure` (`lib/src/diagnostics/`) — перенос `_failureMessage`; текст проходит `SecretRedactor` (`AGENTS.md` §10, §16). `formatRedactedJson` — сырые аргументы для инспектора и одобрений.
- `WorkspaceDiagnostic` и `ClientWorkspace.diagnostics` — диагностика событий, которыми владеет kit: исход хода (в том числе из очереди), отмена, ответ на одобрение, опция конфигурации, неожиданная потеря соединения; важность — `DiagnosticSeverity` ядра клиента, `source` — прежний ключ лога app. Сообщения подключения и создания сессии зависят от формы хоста (команда, адрес), поэтому их по-прежнему пишет фасад, тоже через `describeFailure`.

### D10. Разделение Cubit-ов (5.9) и мапперы

После 5.1–5.8 `CodeLabShellCubit` делится на `ConnectionCubit` (профиль-черновик, подключение), `SessionsCubit` (список, выбор), `ActiveSessionCubit` (транскрипт, очередь, одобрения, опции, план), `SettingsCubit` (проект, недавние проекты, запуск из папки проекта), `LayoutCubit` (ширины панелей, палитра открыта). Каждый получает `ClientWorkspace` (или его часть) из cherrypick. `CodeLabShellCubit` остаётся фасадом: подписывается на них и собирает прежний `CodeLabShellState`, публичные методы делегирует. Маппинг `SessionView`/`WorkspaceState` → модели `acp_ui` (`AcpTranscriptEntry`, `AcpSessionListItem`, `AcpApprovalOption`, `AcpConfigOption`, `CodeLabInspectorEntry`) — `features/workbench/application/ui_mappers.dart`. Виджеты на этом change продолжают читать фасад.

Уточнения при реализации (итерация 7):

- **Синхронная сборка и пакеты.** Поток `Cubit.stream` асинхронный, а виджеты и тесты читают `shellCubit.state` сразу после вызова, и одно событие — изменение сессии, её создание или выбор, потеря соединения — меняет несколько частей, тогда как фасад выпускал на него одно состояние (тест 5.0 «one session/update produces one state»). Поэтому части наследуют `ShellPartCubit`: после каждого `emit` он синхронно сигналит общему `ShellChanges`, а изменение нескольких частей в одном событии обёрнуто в `ShellChanges.batch` — фасад собирает и выпускает `CodeLabShellState` один раз в конце пакета.
- **Зависимости частей.** `SettingsCubit` и `LayoutCubit` ни от кого не зависят; `ActiveSessionCubit` — от `ClientWorkspace` (подписан на `promptOutcomes`); `ConnectionCubit` — от `SettingsCubit` (папка проекта, запуск из неё) и `ActiveSessionCubit` (сброс флагов при неожиданной потере соединения, подписан на `WorkspaceState`); `SessionsCubit` — от всех трёх, он единственный подписчик `sessionChanges` и решает, какую сессию показывать (`ActiveSessionCubit.show`/`showCreated`/`showMissing`). `ActiveSessionState.sessionId` совпадает с `SessionsState.activeSessionId`: обе меняются одним пакетом.
- **Сборка и владение.** `CodeLabShellParts.build` создаёт части в этом порядке после `ClientWorkspace` (D6); граф cherrypick держит `CodeLabShellParts` синглтоном и передаёт фасаду, без графа (`widget_test.dart`) фасад строит их сам. Закрывает части фасад: на этом change он их единственный потребитель. Журнал — общий `ShellDiagnostics` (логгер `codelab_app.shell`, маскирование секретов); диагностику kit пишет фасад.
- **Поверхность фасада.** `CodeLabShellState` вынесен в `shell_state.dart` и реэкспортируется из `shell_cubit.dart` вместе с `CodeLabTransportType`, фабриками транспорта, константами ширины панелей и типами инспектора; `copyWith` остаётся — им готовят состояние тесты виджетов `widget_test.dart`.

### D11. Сторож

`rules.dart`: `PackageRule('packages/dart/acp_client_kit', forbidden: webUnsafe)`, `PackageRule('packages/dart/acp_client_io', forbidden: ['package:flutter/'])` (строки-заготовки этапа 5 заменяются правилами); allowlist зависимостей обоих пакетов — в `pubspec_allowlist_test.dart` (D2). Транзитивная проверка «kit без `dart:io`» следует из правил: все пакеты в `dependencies` kit сами под `webUnsafe` (`acp_client_core`, `acp_protocol`, `acp_transports` без `io.dart`).

### D12. Итерации и PR

Каждая итерация — PR в `develop` из `feature/extract-acp-client-kit`, ветка заново от `develop` после слияния; красный тест — отдельным коммитом до реализации (кроме 5.0, D1).

1. **5.0** — характеризационные тесты; код app не меняется.
2. **5.1** — пакет `acp_client_kit` с API (D4), `AcpClientBackend`, профили, `TransportResolver`, `ConfigTransportResolver`, `SecretSource`/`InMemorySecretSource` (D8), сторож; фасад: Cubit получает `ClientWorkspace` и переводит на него подключение и сессии.
3. **5.3** — `TranscriptProjector` и тест на фикстурах.
4. **5.4** — `PromptQueue` и отмена.
5. **5.5 + 5.8** — `parseShellWords`, `describeProfile`, порты хранилищ, `acp_client_io` (перенос адаптеров, фабрики настоящих транспортов, `JsonFile*Store`): фабрики живут в `acp_client_io`, поэтому задачи идут одним PR.
6. **5.6 + 5.7** — команды агента, `ConfigOptionView`, одобрения, `InspectorProjection`, диагностика (`CommandCatalog` — `add-command-palette-agent-commands`, D9).
7. **5.9** — разделение Cubit-ов, `ui_mappers.dart`, проверка размера `shell_cubit.dart`.

После каждой итерации: тесты 5.0 и `widget_test.dart` зелёные без правок, `melos run check` зелёный, 8 интеграционных тестов собираются (`analyze`).

## Risks / Trade-offs

- **[Перенос меняет поведение незаметно для тестов]** → тесты 5.0 пишутся первыми и не правятся до конца change; `widget_test.dart` уже читает `shellCubit.state` в 31 сценарии; свойство «инкрементальная проекция == пересчёт» на всём клиентском корпусе фикстур (D5).
- **[Фасад читает `SessionView` до обновления kit]** → рабочее пространство подписывается на `sessionChanges` раньше Cubit (D6); тесты 5.0 читают транскрипт сразу после события и упадут при нарушении порядка.
- **[Логика снова расползается по Cubit-ам]** → правило ревью «логика — в kit, в Cubit — только отображение»; сторож запрещает Flutter в kit; цель < 600 строк для `shell_cubit.dart` после 5.9.
- **[Изменения `add-file-preview-and-tree` и `add-integrated-terminal` (не начаты) спроектированы поверх нынешнего `shell_cubit.dart`]** → при их реализации логика добавляется в kit; их `design.md` получают ссылку на этот change при старте.
- **[Долгая серия PR]** → итерации мелкие (D12), каждая сохраняет зелёный `develop`; фасад позволяет остановиться после любой итерации.

## Migration Plan

Внешних контрактов нет: ACP-поведение клиента не меняется, данные пользователя (недавние проекты в `shared_preferences`) остаются на месте. Откат — revert PR итерации: фасад сохраняет прежнюю поверхность после каждой итерации.

## Open Questions

Нет — решения по `bloc_test` (D1), объединению итераций (D12) и поиску палитры (D9) приняты выше и подтверждаются при ревью change.
