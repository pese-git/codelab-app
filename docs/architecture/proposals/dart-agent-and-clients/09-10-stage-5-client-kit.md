# 9.10. Этап 5 — Общий клиентский слой

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) · [Оглавление](../dart-agent-and-clients.md) · [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) →

**Цель.** Логика клиента без UI — в пакете `acp_client_kit` на чистом Dart, `dart:io`-адаптеры —
в `acp_client_io`. `CodeLabShellCubit` становится фасадом над kit, поведение app не меняется.
Этот же слой затем использует codelab_cli.

**Подход — «душитель» (strangler).** Интеграционные тесты app читают
`codeLabDependenciesOf(...).shellCubit.state` и ищут виджеты по ключам. Поэтому этап идёт в два
шага: сначала публичный API и `CodeLabShellState` сохраняются, а реализация методов переносится в
kit (каждая задача — отдельный PR под защитой 8 тестов). Разделение на несколько Cubit-ов
(`ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`, `SettingsCubit`, `LayoutCubit`) — после
переноса логики, отдельной задачей 5.9, с обновлением тестов.

**Задачи.**

1. **5.1. Пакет `packages/dart/acp_client_kit`** с публичным API ниже, `AcpClientBackend` поверх
   `AcpClientApplication` и правилом в стороже (без Flutter и `dart:io`).
2. **5.2. Дополнения `acp_client_core`:** `listSessions({String? cwd})` (`session/list`, только
   если агент объявил возможность); таймаут на JSON-RPC запрос (`requestTimeout`, по умолчанию
   60 с, кроме `session/prompt`); при сбое транспорта все ожидающие запросы завершаются
   типизированной ошибкой. Тесты в `packages/dart/acp_client_core/test/application/`.
3. **5.3. Проекция транскрипта** `acp_client_kit/lib/src/transcript/transcript_projector.dart` —
   инкрементальная (алгоритм ниже) вместо пересчёта всей сессии; перенос логики
   `_agentTranscriptEntries`, `_toolCallTranscriptEntry`, `_transcriptEntriesForSession`. Тест на
   фикстурах `test/fixtures/kit_fixture_projection_test.dart` и свойство «пересчёт с нуля ==
   инкрементальный результат» на всех фикстурах.
4. **5.4. Очередь промптов** `lib/src/queue/prompt_queue.dart` — перенос `submitPrompt`,
   `_dispatchPrompt`, `_drainQueueIfFree`, операций редактирования; очередь своя у каждой сессии.
5. **5.5. Подключение и профили:** `lib/src/connection/` (`ConnectionProfile`, `TransportResolver`,
   переподключение с `session/load`, алгоритм ниже), `lib/src/profiles/profile_store.dart` (порт).
6. **5.6. Команды и опции:** `lib/src/commands/command_catalog.dart` (клиентские команды +
   `available_commands_update`, нечёткий поиск по подпоследовательности),
   `lib/src/config/config_option_view.dart`.
7. **5.7. Инспектор и диагностика:** `lib/src/inspector/inspector_projection.dart` (перенос
   `_inspectorEntriesFor*`), `lib/src/diagnostics/`.
8. **5.8. Пакет `packages/dart/acp_client_io`:** перенос `IoTextFileIo`, `IoTerminalProcessRunner`,
   `IoWorkingDirectoryProvider` из `apps/codelab_app/lib/core/platform/`; новые
   `JsonFileProfileStore` (`~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore` (для CLI).
   `SharedPreferencesRecentProjectsStore` и `FileSelectorProjectFolderPicker` остаются в app
   (Flutter-плагины).
9. **5.9. Разделение Cubit-ов** app (после 5.1–5.8): Cubit-ы получают `ClientWorkspace` и
   отображают `WorkspaceState`/`SessionView` в модели `acp_ui`; маппинг в UI-модели — в
   `apps/codelab_app/lib/features/workbench/application/ui_mappers.dart`. Разделение готовит
   место для `TranscriptViewCubit` (UI-состояние ленты: раскрытие блоков, форма diff) и
   `ComposerCubit` (черновик и вложения) из спецификации десктопа (§12.3.2).
10. **5.10. Список и загрузка сессий в UI** (сайдбар): новый интеграционный тест
    `apps/codelab_app/integration_test/session_list_load_flow_test.dart` и режим scripted-агента
    `withSessionList` в `acp_testing`.
11. **5.11. Сторож запуска app** (D-15): `apps/codelab_app/lib/app/boot/` — `BootHost`,
    `BootWatchdog`, шаги `window` → `services` → `stores` → `logging` → `routes` с таймаутами и
    экран диагностики с кнопкой «запустить без автоподключения» (алгоритм — §12.4.7); новый
    интеграционный тест `apps/codelab_app/integration_test/boot_watchdog_flow_test.dart`.

**Артефакт: публичный API `acp_client_kit`.** Эскиз: конструкторы, `==` и `copyWith` опущены;
неизменяемые модели — freezed, как в `acp_client_core`.

```dart
// packages/dart/acp_client_kit/lib/acp_client_kit.dart

// ---------- Профили подключения ----------
sealed class ConnectionProfile {
  String get id;                          // стабильный ключ в ~/.codelab/profiles.json
  String get label;                       // имя для UI и `codelab profiles list`
}
final class StdioProfile implements ConnectionProfile {
  final String command; final List<String> args; final Map<String, String> env;
  final bool runInProjectDirectory;       // cwd процесса = папка проекта (как сейчас в app)
}
final class WebSocketProfile implements ConnectionProfile {
  final Uri uri; final Map<String, String> headers;
  final String? tokenRef;                 // ссылка на секрет; сам токен в профиле не хранится
}
final class EmbeddedProfile implements ConnectionProfile {
  final String hostProfile;               // embedded-app-desktop | embedded-cli | mobile | web
  final String? provider; final String? model;
}

/// Превращает профиль в транспорт. Реализации регистрирует composition root:
/// stdio и WebSocket — из acp_transports/io.dart, встроенный — поверх codelab_embedded (§9.12).
abstract interface class TransportResolver {
  bool supports(ConnectionProfile profile);
  Future<AcpTransport> open(ConnectionProfile profile, {required String projectDirectory});
}

// ---------- Рабочее пространство ----------
abstract interface class ClientWorkspace {
  factory ClientWorkspace({required AgentBackend backend, required List<TransportResolver> resolvers,
      ProfileStore? profiles, Logger? logger}) = DefaultClientWorkspace;

  WorkspaceState get current;
  Stream<WorkspaceState> get state;                 // соединение, сессии, активная сессия
  Stream<WorkspaceDiagnostic> get diagnostics;      // уже без секретов

  Future<void> connect(ConnectionProfile profile, {required String projectDirectory});
  Future<void> reconnect();                         // + session/load открытых сессий (алгоритм ниже)
  Future<void> disconnect();
  // после MVP (U-26, §12.6.7): отменить ход, завершить агента, подключиться заново, загрузить сессии
  Future<RestartOutcome> restart({Duration cancelGrace = const Duration(seconds: 5),
      Duration terminateGrace = const Duration(seconds: 3)});

  Future<SessionHandle> newSession({String? cwd});  // по умолчанию cwd = projectDirectory
  Future<SessionHandle> loadSession(SessionId id, {required String cwd});
  Future<List<SessionSummaryView>> listSessions({String? cwd});
  // после MVP (D-17, §12.6.12): фильтр по заголовку и дате над session/list и поиск по тексту
  SessionSearch openSessionSearch();
  SessionHandle? session(SessionId id);
  void activate(SessionId id);

  CommandCatalog get commands;                      // клиентские + агентские команды активной сессии
  Future<void> dispose();
}

// после MVP (§12.6.7): итог restart и резолвер, умеющий завершить агента профиля
sealed class RestartOutcome {}                      // Restarted | ReconnectedOnly | RestartFailed
abstract interface class TerminatingTransportResolver implements TransportResolver {
  Future<void> terminate(ConnectionProfile profile, {required Duration grace});
}

final class WorkspaceState {
  final ConnectionView connection;
  final ConnectionProfile? profile; final String? projectDirectory;
  final AgentInfoView? agent;                       // имя, версия, loadSession, list, image
  final List<SessionSummaryView> sessions; final SessionId? activeSessionId;
}

sealed class ConnectionView {}                      // явный конечный автомат, без набора bool
final class Disconnected extends ConnectionView {}
final class Connecting extends ConnectionView {}
final class Connected extends ConnectionView {}
final class Reconnecting extends ConnectionView { final int attempt; }
final class ConnectionFailed extends ConnectionView { final ConnectionFailureReason reason; final String message; }

// ---------- Сессия ----------
abstract interface class SessionHandle {
  SessionId get id;
  String get cwd;
  SessionView get current;
  Stream<SessionView> get view;
  Stream<PendingApproval> get approvals;            // новые запросы одобрения (CLI спрашивает по ним)

  /// Сессия свободна — отправляет сразу; идёт ход — кладёт в очередь.
  /// Вложения — PromptAttachment (§12.1.1); блоки строит PromptContentBuilder.build (§12.1.7).
  Future<PromptSubmission> send(String text,
      {List<PromptAttachment> attachments = const [], bool allowOutsideCwd = false});
  PromptQueue get queue;
  Future<void> cancel();
  Future<void> respond(ApprovalRequestId approval, PermissionOptionId option);
  Future<void> setConfigOption(String configId, String valueId);
  Future<CommandResult> runCommand(String input);   // "/mode plan": клиентская или агентская команда
  /// После MVP (C-03, agent-core-architecture §17.7.4): направить сообщение в идущий ход.
  /// Без agentCapabilities._meta.codelab.steering, без хода или при отказе агента — как send().
  Future<SteerSubmission> steer(String text,
      {List<PromptAttachment> attachments = const [], bool allowOutsideCwd = false});
  // После MVP (S-06…S-09): access, rename, branches, switchBranch, rewind, fork, label — §12.1.1.
}

final class SessionView {
  final int revision;                               // растёт с каждым изменением: дешёвое сравнение в UI
  final SessionStatusView status;                   // idle | running | cancelling | failed | detached
  final SessionStatusBar statusBar;                 // модель, режим, usage, ветка, очередь (§12.1.5)
  final List<TranscriptItem> transcript;
  final List<PlanEntryView>? plan;
  final List<ConfigOptionView> configOptions;
  final List<AgentCommandView> agentCommands;
  final List<QueuedPrompt> queue;                   // QueuedPrompt с attachments (§12.1.1)
  final List<PendingApproval> pendingApprovals;
  final List<PendingSteerView> pendingSteers;       // после MVP (C-03): принятые, не доставленные (§12.1.1)
}

sealed class TranscriptItem {
  String get id;
  String? get recordId;                             // после MVP: id записи журнала (_meta.codelab.recordId), §12.1.1
}
// Поля для отображения — §12.1.1 (единый источник; здесь только эскиз).
final class UserItem implements TranscriptItem { /* text, attachments: List<PromptAttachmentView>, origin: user | steer */ }
final class AgentTextItem implements TranscriptItem { /* text, streaming, markdown: MarkdownDocument */ }
final class ThoughtItem implements TranscriptItem { /* text, streaming, startedAt, endedAt */ }
final class ToolCallItem implements TranscriptItem {
  /* toolCallId, title, kind, status: ToolCallStatusView, rawInput, locations,
     content: List<ToolContentView> (text | diff | terminal | other), progressText,
     startedAt, finishedAt, approval: ApprovalStateView? — §12.1.1 */
}
final class NoticeItem implements TranscriptItem { /* kind: error | cancelled | reconnected | detached, text; после MVP — rateLimit (§12.1.1) */ }

final class PendingApproval {
  /* id, toolCallId, title, kind, rawInput, locations, diffs (по одному на файл), risk,
     options: List<ApprovalOptionView>(optionId, label, kind: allowOnce | allowAlways | rejectOnce | rejectAlways) */
}

abstract interface class PromptQueue {
  List<QueuedPrompt> get items;
  void edit(String id, String text);
  void remove(String id);
  Future<void> sendNow(String id);                  // отменяет текущий ход и отправляет
  /// После MVP (C-03): направить элемент в идущий ход, не отменяя его (рядом с sendNow, R-18).
  Future<SteerSubmission> steer(String id);
  void clear();
}

// После MVP (C-03, agent-core-architecture §17.7.4): исход SessionHandle.steer и PromptQueue.steer.
sealed class SteerSubmission {}
final class Steered extends SteerSubmission { final String steerId; final int position; }
final class FellBackToPrompt extends SteerSubmission { final PromptSubmission submission; final SteerFallbackReason reason; }
enum SteerFallbackReason { unsupported, idle, command, noActiveTurn, steerLimit, steerTooLarge, sessionBusy, steeringDisabled }

// ---------- Внутренний порт источника данных ----------
/// Сейчас единственная реализация — AcpClientBackend поверх AcpClientApplication.
/// DirectBackend поверх AgentRuntime можно добавить без изменения UI (§4.5).
abstract interface class AgentBackend {
  Stream<ClientConnectionState> get connectionStates;
  Stream<AcpSession> get sessionChanges;
  Stream<DiagnosticEntry> get diagnostics;
  Future<ClientConnectionState> connect(AcpTransport transport);
  Future<ClientConnectionState> reconnect(ReconnectCommand command);  // transportFactory — поле команды, как в acp_client_core
  Future<AcpSession> createSession(CreateSessionCommand command);
  Future<AcpSession> loadSession(LoadSessionCommand command);
  Future<List<SessionInfo>> listSessions({String? cwd});          // новый метод ядра клиента (5.2)
  // после MVP (D-17): _codelab/session/search, только при agentCapabilities._meta.codelab.sessionSearch
  Future<SessionSearchResultDto> searchSessions(SessionSearchParamsDto params);
  Future<PromptTurn> sendPrompt(SendPromptCommand command);
  Future<PromptTurn> cancelTurn(CancelTurnCommand command);
  Future<ApprovalRequest> respondToPermission(RespondToPermissionCommand command);
  Future<AcpSession> setSessionConfigOption(SetSessionConfigOptionCommand command);
  Future<void> dispose();
}
```

**После MVP (C-03).** `SessionHandle.steer` и `PromptQueue.steer` реализуют алгоритм
agent-core-architecture §17.7.4: ожидающее steering — в `SessionView.pendingSteers`, доставленное
(`user_message_chunk` с `_meta.codelab.steer`) — `UserItem(origin: steer)` на текущем месте
транскрипта, возвращённое (`steerReturned`) — в голову очереди без автоотправки после `cancelled`.
Каждый вызов заканчивается ровно одним исходом: доставка, промпт или элемент очереди (STEER-10).
Тест kit — `test/steer/session_steer_test.dart`: каждый откат (`unsupported`, `idle`, `command`,
`noActiveTurn`, `steerLimit`) даёт ровно один промпт или элемент очереди; `steerReturned` кладёт
сообщение в голову очереди; переподключение с реплеем доставленного id убирает его из
`pendingSteers`.

**Артефакт: перенос ответственности из `CodeLabShellCubit`.**

| Ответственность сегодня (методы `shell_cubit.dart`) | Новый дом | Что остаётся в Cubit |
|---|---|---|
| Выбор транспорта и редактирование профиля: `selectTransport`, `updateStdioProfileName`, `updateStdioCommand`, `updateStdioArgs`, `updateStdioEnv`, `updateWebSocketEndpoint`, `updateWebSocketToken`, `_splitShellWords`, `selectedProfileLabel`, `selectedConnectionDetail` | kit: `ConnectionProfile`, `parseShellWords`, `describeProfile`; acp_client_io: `JsonFileProfileStore` | состояние формы (черновик профиля до сохранения) |
| Подключение: `connect`, `reconnect`, `_stdioConfigFromState`, `_webSocketConfigFromState`, фабрики `CodeLabStdioTransportFactory`/`CodeLabWebSocketTransportFactory`, `_handleConnectionStateChange`, `_connectionStatusForConnection` | kit: `ClientWorkspace.connect/reconnect`, `TransportResolver`, `ConnectionView` | маппинг `ConnectionView` → `AcpConnectionStatus` |
| Проект: `selectProject`, `browseForProject`, `toggleRunAgentFromProjectDirectory`, `_loadRecentProjects`, `_selectedProjectPath` | kit: `projectDirectory` в `WorkspaceState`, порт `RecentProjectsStore`; acp_client_io: `IoWorkingDirectoryProvider`, `JsonFileRecentProjectsStore` | вызов `ProjectFolderPicker` (плагин `file_selector`), реализация на `shared_preferences` |
| Сессии: `createSession`, `selectSession`, `_handleSessionChange`, `_sessionListItem`, `_sessionStatus` | kit: `newSession`, `activate`, `SessionSummaryView`, `SessionStatusView` | маппинг в `AcpSessionListItem` |
| Очередь промптов: `submitPrompt`, `_dispatchPrompt`, `_queueFor`, `_setQueueFor`, `editQueuedPrompt`, `deleteQueuedPrompt`, `sendQueuedPromptNow`, `clearQueuedPrompts`, `_drainQueueIfFree`, `_isSessionBusy`, `_isBusyLifecycleStatus`, `_newQueuedPromptId`, поле `_queuedPromptsBySession` | kit: `SessionHandle.send`, `PromptQueue` | — |
| Отмена: `cancelTurn` | kit: `SessionHandle.cancel` | — |
| Одобрения: `respondToApproval`, `_approvalRisk`, `_approvalOption`, `_approvalOptionKind`, `_approvalForToolCall`, `_earliestPendingApprovalId`, `_transcriptApproval`, `_resolvedLabel` | kit: `PendingApproval`, `ApprovalStateView`, `SessionHandle.respond` | маппинг в `AcpApprovalOption`, `AcpTranscriptApproval` |
| Опции конфигурации: `setSessionConfigOption`, `_configOptionsFor`, `_configOptionUiModel` | kit: `ConfigOptionView`, `SessionHandle.setConfigOption` | маппинг в `AcpConfigOption` |
| Палитра и команды: `openCommandPalette`, `closeCommandPalette`, `selectCommand`, `insertAgentCommand`, `paletteActions`, `_agentCommandsFor`, `_agentCommandAction` | kit: `CommandCatalog` (поиск, слияние, разрешение конфликтов имён), `SessionHandle.runCommand` | флаг «палитра открыта», вставка текста в композер |
| План: `dismissPlan`, `_currentPlanForSession`, `_planEntryUiModel` | kit: `SessionView.plan`, `PlanEntryView` | флаг «план скрыт» |
| Транскрипт: `_agentTranscriptEntries`, `_toolCallTranscriptEntry`, `_transcriptEntriesForSession`, `_textFrom`, `_toolCallStatus`, `_commandFromToolCall`, `_StreamingChunkKind` | kit: `TranscriptProjector`, `TranscriptItem` | маппинг в `AcpTranscriptEntry` |
| Инспектор: `_inspectorEntriesForSession`, `_inspectorEntriesForTurn`, `_approvalInspectorEntry`, `_toolCallInspectorEntry`, `_protocolInspectorEntry`, `_contentInspectorEntry`, `_toolCallContentDetails`, `_toolCallLocationDetails`, `_contentSummary`, `_prettyJson` | kit: `InspectorProjection` (используется и командой CLI `/inspect`) | маппинг в `CodeLabInspectorEntry` |
| Диагностика и ошибки: `_recordDiagnostic`, `_failureMessage`, `_cleanDomainFailureMessage`, `_redactor` | kit: `WorkspaceDiagnostic`, `describeFailure` (с редакцией секретов) | — |
| Панели: `resizeSessionsPane`, `resizeInspectorPane`, константы ширины | — | целиком (чисто презентационное состояние) |
| Жизненный цикл: `close`, подписки `_sessionSubscription`, `_connectionStateSubscription` | kit: `ClientWorkspace.dispose` | отписка Cubit от `WorkspaceState` |

**Алгоритм инкрементальной проекции транскрипта.** Вход — поток изменений `AcpSession` из
`acp_client_core`; состояние проектора — список `TranscriptItem` и индекс `toolCallId → позиция`.

1. Для каждого нового `session/update` текущего хода (обрабатываются только обновления с номером
   больше последнего обработанного; повтор того же обновления — no-op, `AGENTS.md` §9):
2. `agent_message_chunk` / `agent_thought_chunk`: если последний элемент того же вида и помечен
   `streaming` — дописать текст; иначе закрыть предыдущий потоковый элемент и открыть новый.
3. `tool_call`: закрыть потоковый элемент; если `toolCallId` уже есть в индексе — обновить его поля
   (повторная доставка), иначе добавить `ToolCallItem` и запомнить позицию.
4. `tool_call_update`: закрыть потоковый элемент; найти элемент по индексу и заменить только
   пришедшие поля (по ACP `content` и `locations` заменяются целиком). Если `tool_call` не
   приходил — создать элемент на этом месте (защитный путь).
5. `plan`: заменить `SessionView.plan` целиком. `available_commands_update`,
   `config_option_update`, `current_mode_update` — обновить соответствующие списки.
6. Запрос разрешения привязывается к `ToolCallItem` по `toolCallId`; ответ клиента меняет
   `ApprovalStateView`, не трогая порядок элементов.
7. Конец хода (`stopReason`) закрывает потоковые элементы; `cancelled` и ошибка добавляют `NoticeItem`.
8. Новый `SessionView` публикуется с `revision + 1` не чаще одного раза за кадр UI (склейка
   изменений в микрозадаче).

Свойство для тестов: для любой фикстуры проекция с нуля по полному списку обновлений совпадает с
инкрементальной.

**Алгоритм переподключения с восстановлением сессий.**

1. `reconnect()` переводит `ConnectionView` в `Reconnecting(attempt)` и запоминает открытые
   сессии `(id, cwd)` и активную сессию.
2. `AgentBackend.reconnect` с фабрикой транспорта из текущего профиля; попытки с паузой 1, 2, 4,
   8 с (не больше 5), отмена — `disconnect()`.
3. После `initialize`: если агент объявил `loadSession`, для каждой открытой сессии —
   `loadSession(id, cwd)`; реплей `session/update` приходит до ответа и проходит через проектор с
   нуля (старый транскрипт заменяется, а не дополняется).
4. Если `loadSession` не поддерживается или вернул ошибку — сессия получает статус `detached` и
   `NoticeItem`; очередь промптов сохраняется, но не отправляется до явного действия.
5. Ожидающие одобрения старого соединения закрываются как отменённые; поздние события старого
   поколения отбрасываются (`AcpClientApplication.generation`).

Перезапуск агента — §12.6.7.

**OpenSpec change.** `extract-acp-client-kit` (задачи 5.1, 5.3–5.9; scope: новый пакет и его
публичный API, переход app на kit без изменения поведения) и `add-session-list-and-reload`
(задачи 5.2, 5.10; scope: `session/list`, таймауты запросов, `session/load` после reconnect —
меняет наблюдаемое поведение app); сторож запуска (задача 5.11) — отдельный change
`add-app-boot-watchdog`.

**Что прочитать.** `docs/architecture/state-management.md` §61, §80–§82;
`docs/architecture/session-lifecycle.md`; `docs/architecture/streaming.md`;
`docs/architecture/platform-integration.md`; `docs/acp/protocol/04-Session List.md`,
`12-Session Model.md`. Документ ядра для этого этапа не нужен.

**Definition of Done.**

* Все 8 интеграционных тестов app проходят без изменений (`melos run test:e2e:app:*`).
* `fvm dart test packages/dart/acp_client_kit` зелёный; среди тестов:
  `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`,
  `prompt_queue_test.dart: queued prompt is sent after the turn ends`,
  `reconnect_test.dart: open sessions are reloaded after reconnect when agent supports loadSession`.
* `fvm dart test packages/dart/acp_client_io packages/dart/acp_client_core` зелёный.
* `melos run guard`: `acp_client_kit` не импортирует Flutter и `dart:io` (в том числе транзитивно).
* `shell_cubit.dart` не содержит логики из левого столбца таблицы (проверка на ревью; цель —
  меньше 600 строк после 5.9).
* Новые тесты `session_list_load_flow_test.dart` и `boot_watchdog_flow_test.dart` зелёные.

**Зависимости.** Этап 0 (разделение `acp_transports`, сторож). Не зависит от агентской ветки.

**Риски.** Рефакторинг ломает поведение app — шаг «фасад» под защитой интеграционных тестов,
каждая задача отдельным PR; исправления поведения (5.2, 5.10) — отдельным change. Логика снова
расползается по UI — сторож и правило ревью «логика — в kit, в Cubit и REPL — только
отображение».

---

← [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) · [Оглавление](../dart-agent-and-clients.md) · [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) →
