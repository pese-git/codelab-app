## 1. Характеризационные тесты (5.0, итерация 1)

- [x] 1.1 `shell_cubit_characterization/connection_test.dart`: `connect()` проходит `connecting` → `connected`; закрытие `FakeAcpTransport` → `failed`, сообщение без секретов; `close()` отписывается, поздние события не вызывают `emit` (testing-quality «Характеризационные тесты фасада приложения»)
- [x] 1.2 `sessions_test.dart`: `createSession()` шлёт `session/new` с `cwd` выбранного проекта, сессия активна; `selectSession` пересчитывает `isPromptSubmitting`/`canCancel`; очередь у каждой сессии своя
- [x] 1.3 `prompt_test.dart`: флаги во время хода и после `stopReason`; промпт во время хода — в очередь; `editQueuedPrompt`, `deleteQueuedPrompt`, `sendQueuedPromptNow`, `clearQueuedPrompts`; слив очереди после хода
- [x] 1.4 `cancel_test.dart`: `cancelTurn()` шлёт `session/cancel`, флаги сбрасываются только по событию сессии; после отмены очередь сливается; без активной сессии — диагностика и ни одного запроса
- [x] 1.5 `config_option_test.dart`: `isRespondingToConfigOption` на время запроса, сброс после успеха и ошибки, второй вызов игнорируется, `configOptions` из `sessionChanges`
- [x] 1.6 `permission_test.dart`: запрос разрешения — запись с ожидающим одобрением по `toolCallId`; `respondToApproval` шлёт `optionId`; ответ в одной сессии не меняет другую
- [x] 1.7 `reconnect_test.dart`: `reconnect()` увеличивает `generation`; поздние `session/update` старого поколения не меняют состояние; одно событие — одно состояние (D1)
- [x] 1.8 Проверка: тесты зелёные, `apps/codelab_app/lib` не изменён; PR итерации 1

## 2. Пакет acp_client_kit и фасад (5.1, итерация 2)

- [x] 2.1 Тест сторожа: правила `acp_client_kit` (`webUnsafe`) и allowlist его `dependencies` (D2, D11); тест-нарушение на временном пакете (красный, пока правила нет)
- [x] 2.2 Пакет `packages/dart/acp_client_kit` в `workspace:`; `AGENTS.md` вложенный — назначение и границы; правило в `rules.dart`, allowlist в `pubspec_allowlist_test.dart` — 2.1 зелёный
- [x] 2.3 Тесты kit: `ClientWorkspace` подключается через тестовый резолвер, `ConnectionView` проходит `Connecting` → `Connected`, сбой → `ConnectionFailed`; профиль без резолвера → `ConnectionFailed`, транспорт не открывается; `reconnect` — одна попытка, `Reconnecting` → `Connected`; `newSession`/`activate`; позднее событие старого поколения игнорируется; `ConfigTransportResolver` (`cwd` по `runInProjectDirectory`, токен по ссылке из `SecretSource`) (acp-client-kit «Явный автомат соединения», «Профили и резолверы транспорта»)
- [x] 2.4 `AgentBackend`, `AcpClientBackend`, `ClientWorkspace`, `SessionHandle` (без очереди и проектора — они в 3–4), `WorkspaceState`, `ConnectionView`, `ConnectionProfile`, `TransportResolver`, `ConfigTransportResolver`, `SecretSource`, `InMemorySecretSource` — 2.3 зелёный
- [x] 2.5 Фасад: привязка `CodeLabShellCubit` в `app_scope.dart` получает `ClientWorkspace`; подключение, переподключение, создание и выбор сессии идут через kit; тесты 5.0 и `widget_test.dart` без правок; PR итерации 2

## 3. Проекция транскрипта (5.3, итерация 3)

- [x] 3.1 Тест `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture` (драйвер `ClientFixtureUser` вынесен в `acp_testing`) и случаи алгоритма (дельты, пустой отрезок, повторный `tool_call`, `tool_call_update`, привязка одобрения и фокус, одобрение без `tool_call` в конце хода, `NoticeItem` для ошибки и пустого хода, повтор снимка — no-op) (acp-client-kit «Инкрементальная проекция транскрипта»)
- [x] 3.2 `TranscriptProjector`, `projectTranscript`, `TranscriptItem`, `SessionView.transcript` с синхронной публикацией (D5, D6) — 3.1 зелёный
- [x] 3.3 Фасад строит `transcriptEntries` из `SessionView.transcript`; `_agentTranscriptEntries`, `_toolCallTranscriptEntry` и вспомогательные функции проекции удалены, `_transcriptEntriesForSession` только отображает элементы kit; тесты 5.0 и `widget_test.dart` без правок; PR итерации 3

## 4. Очередь промптов и отмена (5.4, итерация 4)

- [x] 4.1 Тесты `prompt_queue_test.dart: queued prompt is sent after the turn ends`, `send` ждёт слива очереди, независимость очередей сессий, `remove`/`sendNow`/`clear` по стабильному id, `SessionHandle.cancel`, `PromptFailed` (acp-client-kit «Очередь промптов на сессию»)
- [x] 4.2 `PromptQueue`, `QueuedPrompt`, `PromptOutcome`, `SessionHandle.send`/`cancel`, `ClientWorkspace.promptOutcomes`, `SessionView.queue` (D4, D7) — 4.1 зелёный
- [x] 4.3 Фасад: `submitPrompt`, операции очереди и `cancelTurn` делегируют kit, флаги `isPromptSubmitting`/`canCancel` — из `SessionView.status`; поле `_queuedPromptsBySession` удалено; привязки `SendPrompt`/`CancelTurn` убраны из графа; тесты 5.0 без правок; PR итерации 4

## 5. Профили, резолверы и acp_client_io (5.5 + 5.8, итерация 5)

- [x] 5.1 Тесты kit: `parseShellWords`, `parseEnvLines` (acp-client-kit «Профили и резолверы транспорта»); тест сторожа для `acp_client_io` (`package:flutter/` запрещён, `dart:io` разрешён, allowlist)
- [x] 5.2 `parseShellWords`, `parseEnvLines`, порты `ProfileStore`, `RecentProjectsStore` (с `RecentProject`, `recentProjectsLimit`) в kit; `describeProfile` не вводится — нет потребителя (D8) — тесты kit 5.1 зелёные
- [x] 5.3 Тесты `acp_client_io`: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `JsonFileProfileStore` (файл без значения токена), `JsonFileRecentProjectsStore`, `ConfigTransportResolver` с фабриками stdio и WebSocket против процесса и сокета на Dart VM (acp-client-kit «IO-адаптеры клиента»)
- [x] 5.4 Пакет `packages/dart/acp_client_io` и вложенный `AGENTS.md`: перенос `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider` из `apps/codelab_app/lib/core/platform/` (в app у них не было тестов — тесты новые), `ioTransportResolver`, `JsonFile*Store`; правило сторожа и allowlist — 5.3 зелёный
- [x] 5.5 Фасад: формы профиля пишут черновик, профиль строится через `parseShellWords`/`parseEnvLines` kit, подключение — через резолверы; app импортирует адаптеры из `acp_client_io`, прежние пути `core/platform/` — реэкспорт для тестов; тесты 5.0 без правок; PR итерации 5

## 6. Команды, опции, инспектор, диагностика (5.6 + 5.7, итерация 6)

- [x] 6.1 Тесты kit: `ConfigOptionView`, `setConfigOption` в полёте и при ошибке, `agentCommands`, `pendingApprovals` и `respond` по сессиям, `InspectorProjection` (записи сессии, одобрения, вызова, протокола, хода; редакция сырых аргументов), `describeFailure` с редакцией токена, диагностика kit (потеря соединения без дубля и без токена, исходы хода, отмена) (acp-client-kit «Диагностика без секретов», «Одобрения привязаны к вызову»)
- [x] 6.2 `AgentCommandView`, `ConfigOptionView`, `SessionHandle.setConfigOption`/`respond`, `SessionView.pendingApprovals`, `InspectorProjection`, `WorkspaceDiagnostic`, `ClientWorkspace.diagnostics`, `describeFailure`, `formatRedactedJson` — 6.1 зелёный; `CommandCatalog` и сопоставление запроса палитры — `add-command-palette-agent-commands` (D9)
- [x] 6.3 Фасад: команды агента, опции, одобрения, инспектор и диагностика через kit; логика `_inspectorEntriesFor*`, `_failureMessage`, `_agentCommandAction`, `_configOptionUiModel` удалена, привязки use case-ов `acp_client_core` убраны из графа; тесты 5.0 без правок; PR итерации 6

## 7. Разделение Cubit-ов (5.9, итерация 7)

- [x] 7.1 Тесты `ui_mappers.dart`: `SessionView`/`WorkspaceState` → модели `acp_ui` совпадают с прежними значениями для сессий тестов 5.0
- [x] 7.2 `ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`, `SettingsCubit`, `LayoutCubit`, `ui_mappers.dart`; `CodeLabShellCubit` — фасад, собирающий `CodeLabShellState` (D10)
- [x] 7.3 Проверка: в `shell_cubit.dart` нет логики из левого столбца таблицы переноса `09-10`, файл меньше 600 строк; тесты 5.0, `widget_test.dart` без правок

## 8. Документы и Definition of Done

- [ ] 8.1 `AGENTS.md` §5 (структура и назначение `acp_client_kit`, `acp_client_io`), `docs/architecture/technology-stack.md`, `docs/architecture/state-management.md` (владелец клиентского состояния — kit), `09-10-stage-5-client-kit.md` (уточнения D3, D4, D8, D9 этого change)
- [ ] 8.2 Definition of Done: `fvm dart run melos run check` зелёный; `fvm dart test packages/dart/acp_client_kit packages/dart/acp_client_io packages/dart/acp_client_core` зелёный; `melos run guard` — kit без Flutter и `dart:io`; тексты 8 интеграционных тестов не изменены и собираются; в kit нет членов «после MVP»; PR итерации 7
- [ ] 8.3 Перед архивированием: `openspec validate extract-acp-client-kit --strict`; заполнить Purpose новой спецификации `acp-client-kit`
