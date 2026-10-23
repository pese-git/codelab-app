# 9.10. Этап 5 — Общий клиентский слой

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) · [Оглавление](../dart-agent-and-clients.md) · [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) →

**Цель.** Логика клиента без UI — в пакете `acp_client_kit` на чистом Dart, `dart:io`-адаптеры —
в `acp_client_io`. `CodeLabShellCubit` становится фасадом над kit, поведение app не меняется.
Этот же слой затем использует codelab_cli.

**Подход — «душитель» (strangler).** Интеграционные тесты app читают
`codeLabDependenciesOf(...).shellCubit.state` и ищут виджеты по ключам. Поэтому сначала
поведение фиксируется характеризационными тестами (задача 5.0), затем реализация методов
переносится в kit (каждая задача — отдельный PR под защитой 8 интеграционных тестов и тестов 5.0).
Разделение на несколько Cubit-ов (`ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`,
`SettingsCubit`, `LayoutCubit`) — после переноса логики, задачей 5.9.

**Что остаётся неизменным.** Этап меняет код app (перенос логики в kit), но сохраняет публичную
поверхность `CodeLabShellCubit`: публичные методы, поля `CodeLabShellState`, которые читают тесты
и виджеты (`connectionStatus`, `sessions`, `activeSessionId`, `transcriptEntries`,
`isPromptSubmitting`, `canCancel`, `isRespondingToConfigOption`), ключи виджетов и доступ
`codeLabDependenciesOf(...).shellCubit`. Поэтому тексты 8 интеграционных тестов и тестов 5.0 на
этапе 5 не меняются — ни при переносе (5.1–5.8), ни при разделении (5.9: `CodeLabShellCubit`
остаётся фасадом, который собирает `CodeLabShellState` из новых Cubit-ов). Перевод тестов на новые
Cubit-ы и удаление фасада — после этапа 9, отдельным change. Это же условие — «без изменений кода
app» для контракта e2e этапа 4 (D6, задача 4.9): параметризация тестов по
`CODELAB_E2E_AGENT` — работа этапа 4, этап 5 её не трогает.

**Задачи.**

0. **5.0. Характеризационные тесты `CodeLabShellCubit`** (исключение (а) правила TDD §9.0 п.3:
   рефакторинг существующего кода начинается с тестов на текущее поведение, а не с красного
   теста). Делается до первого переноса, отдельным PR, код app не меняется. Тесты проверяют только
   публичную поверхность (методы и поля `CodeLabShellState`), а не приватные методы — поэтому
   переживают перенос в kit без правок. Cubit создаётся через настоящий граф cherrypick:
   `CodeLabTestBinding` (`apps/codelab_app/test/support/test_app_scope.dart`) вызывает
   `createCodeLabRootScope` с `FakeAcpTransport` из `acp_testing`, а `CodeLabShellCubit`
   разрешается из привязки `bind<CodeLabShellCubit>()` в `lib/app/app_scope.dart` (~строка 244).
   Так тесты закрывают и проводку DI: на этапе 5 меняются аргументы этой привязки (`ClientWorkspace`
   вместо use case-ов), и тесты должны остаться зелёными. Инструмент — `flutter_test`
   (`expectLater(cubit.stream, emitsInOrder(...))`); `bloc_test` сейчас нет в `dev_dependencies`,
   его добавление — решение в `design.md` change. Файлы в
   `apps/codelab_app/test/features/workbench/application/shell_cubit_characterization/`:

   | Файл | Что утверждает |
   |---|---|
   | `connection_test.dart` | `connect()`: `connectionStatus` проходит `connecting` → `connected`; сбой транспорта (закрытие `FakeAcpTransport`) → `failed` с сообщением после редакции секретов; `close()` отписывается, поздние события не вызывают `emit` |
   | `sessions_test.dart` | `createSession()`: `session/new` с `cwd` выбранного проекта, новая сессия в `sessions` и активна; `selectSession(id)`: меняется `activeSessionId`, флаги `isPromptSubmitting`/`canCancel` пересчитываются по статусу выбранной сессии; очередь промптов у каждой сессии своя |
   | `prompt_test.dart` | `submitPrompt()`: во время хода `isPromptSubmitting == true` и `canCancel == true` (в том числе при ожидании одобрения), после `stopReason` — оба `false`; промпт во время хода попадает в очередь; `editQueuedPrompt`, `deleteQueuedPrompt`, `sendQueuedPromptNow` (отмена хода и отправка), `clearQueuedPrompts`; очередь сливается после конца хода |
   | `cancel_test.dart` | `cancelTurn()`: уходит `session/cancel`, ход завершается `stopReason: cancelled`, `canCancel` и `isPromptSubmitting` становятся `false` только по событию сессии (а не сразу после вызова); после отмены очередь сливается; без активной сессии — диагностика и ни одного запроса |
   | `config_option_test.dart` | `setSessionConfigOption()`: `isRespondingToConfigOption == true` на время запроса и `false` после успеха и после ошибки; второй вызов во время запроса игнорируется; `configOptions` берутся из следующего `sessionChanges`, а не выставляются заранее |
   | `permission_test.dart` | запрос `session/request_permission` даёт запись с ожидающим одобрением в `transcriptEntries`, привязанную к `toolCallId`; `respondToApproval` отправляет выбранный `optionId`; ответ в одной сессии не меняет другую (как в `multi_session_concurrency_flow_test`) |
   | `reconnect_test.dart` | `reconnect()` увеличивает `AcpClientApplication.generation`; поздние `session/update` старого поколения не меняют `CodeLabShellState`; подписки не дублируются (одно событие — один `emit`) |

   Загрузки и списка сессий в Cubit сейчас нет (есть только `createSession`/`selectSession`), поэтому
   `session/list` и `session/load` — новое поведение задач 5.2, 5.10 и 5.12, они идут по обычному
   TDD, а не характеризацией.
1. **5.1. Пакет `packages/dart/acp_client_kit`** с публичным API ниже, `AcpClientBackend` поверх
   `AcpClientApplication` и правилом в стороже (без Flutter и `dart:io`).
2. **5.2. Дополнения `acp_client_core`:** `listSessions({String? cwd, String? cursor})`
   (`session/list`, только если агент объявил `sessionCapabilities.list`) возвращает страницу
   `SessionListPage(sessions, nextCursor)`; курсор непрозрачен, не разбирается и не сохраняется
   между запусками (`docs/acp/protocol/04-Session List.md`, «Pagination»), отсутствие `nextCursor` —
   конец списка; таймаут на JSON-RPC запрос (`requestTimeout`, по умолчанию
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
   `lib/src/config/config_option_view.dart`. Здесь же создаётся интеграционный тест R-20 (Must,
   этап 5) `apps/codelab_app/integration_test/command_palette_flow_test.dart` и режим
   scripted-агента `withAvailableCommands` в `acp_testing` (объявляет `/compact` и `/plan` через
   `available_commands_update`): Cmd/Ctrl+K открывает палитру с командами app и агента; выбор
   `/compact` отправляет `session/prompt` с текстом `/compact` и показывает ответ агента в
   транскрипте; выбор клиентской команды выполняет её без `session/prompt`. Тест пишется первым,
   до переноса палитры в `CommandCatalog` (критерий матрицы R-20).
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
12. **5.12. Восстановление после перезапуска app** (D-03, Must): `lib/src/restore/` в kit
    (`WorkspaceRestorer`, порт `WorkspaceSnapshotStore`) и реализация порта на
    `shared_preferences` в app; алгоритм — «Алгоритм восстановления после перезапуска app» ниже.
    Сценарий «перезапуск» добавляется в `session_list_load_flow_test.dart` (5.10).

**Артефакт: публичный API `acp_client_kit`.** Эскиз: конструкторы, `==` и `copyWith` опущены;
неизменяемые модели — freezed, как в `acp_client_core`.

**Правило для членов «после MVP».** Члены с комментарием «после MVP» (`restart`, `RestartOutcome`,
`TerminatingTransportResolver`, `openSessionSearch`, `AgentBackend.searchSessions`,
`SessionHandle.steer`, `PromptQueue.steer`, `SteerSubmission`, `SessionView.pendingSteers`,
`TranscriptItem.recordId`) после MVP — не реализуются на этапе 5; в интерфейсе появляются вместе
со своими целями (U-26, D-17, C-03, S-06…S-09) в change соответствующей цели. В эскизе они
показаны, чтобы форма API этапа 5 не мешала их добавлению; в коде этапа 5 их нет, заглушек
`UnimplementedError` тоже нет.

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
  /// Одна страница session/list; nextCursor == null — конец списка (курсор не сохраняется).
  Future<SessionPage> listSessions({String? cwd, String? cursor});
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
  final String? configOptionInFlight;               // configId запроса session/set_config_option в полёте
}

final class SessionPage {
  final List<SessionSummaryView> sessions;
  final String? nextCursor;                         // непрозрачный курсор ACP; null — страниц больше нет
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
  Future<SessionListPage> listSessions({String? cwd, String? cursor}); // новый метод ядра клиента (5.2)
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
| Флаги состояния `CodeLabShellState`: `isPromptSubmitting`, `canCancel` (сегодня оба = `_isBusyLifecycleStatus`: `runningTurn` или `awaitingApproval`), `isRespondingToConfigOption` (защита от повторного `setSessionConfigOption`) | kit: `SessionView.status` активной сессии — `running` (в том числе с непустым `pendingApprovals`) и `cancelling` считаются «занята»; `SessionView.configOptionInFlight != null` — запрос опции в полёте, повторный `SessionHandle.setConfigOption` в это время — no-op, как сейчас | производные поля для совместимости: `isPromptSubmitting = canCancel = status is running или cancelling`; `isRespondingToConfigOption = configOptionInFlight != null`; тесты 5.0 проверяют, что значения совпадают с прежними |
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

**Алгоритм восстановления после перезапуска app (D-03, задача 5.12).** Переподключение выше
работает внутри одного запуска; после перезапуска app открытые сессии в памяти потеряны, поэтому
kit сохраняет снимок и восстанавливает по нему.

*Что сохраняется.* Порт `WorkspaceSnapshotStore` в kit; в app — реализация на
`shared_preferences`, ключ `codelab.workspace.snapshot` (значение — JSON с версией формата):

```json
{"version": 1, "windows": {"main": {
  "profileId": "codelab-agent-local",
  "projectDirectory": "/work/app",
  "activeSessionId": "sess_42",
  "openSessions": [{"id": "sess_42", "cwd": "/work/app"}, {"id": "sess_17", "cwd": "/work/app"}]
}}}
```

Ключ `windows` — по окну; сейчас окно одно (`main`), несколько окон (§12.3) добавляют свои ключи.
Не сохраняются: курсоры `session/list` (ACP запрещает их сохранять), транскрипт (его источник —
реплей агента), очередь промптов, секреты и сам профиль (он в `ProfileStore`, в снимке — только
`profileId`). Запись — после успешных `session/new`, `session/load`, `activate`, смены проекта и
закрытия сессии, со склейкой не чаще раза в секунду; ошибка записи — диагностика, а не отказ
операции.

*Когда запускается.* Один раз при старте app — шаг `routes` сторожа запуска (§12.4.7), если
включено автоподключение: шаги 1–3 идут внутри шага `routes` под его таймаутом, шаги 4–7 — после
`BootReady`. «Start without auto-connect» восстановление пропускает, снимок при этом
не удаляется. CLI снимок не читает (у него `--resume`/`--continue`, §9.11).

1. Прочитать снимок окна. Нет ключа — обычный старт. Неизвестная версия или битый JSON —
   диагностика `app.restore.snapshot_invalid`, ключ удаляется, обычный старт.
2. Найти профиль `profileId` в `ProfileStore`. Нет профиля — старт без подключения и баннер
   `The last connection profile no longer exists.`; проект `projectDirectory` всё равно выбран.
3. `ClientWorkspace.connect(profile, projectDirectory)`. Агент не запускается или не отвечает на
   `initialize` (бинарь удалён, процесс упал, таймаут шага `routes`) — `ConnectionFailed` и
   состояние ошибки workbench с кнопками «Retry» (повтор с шага 3 по тому же снимку) и «Choose
   another profile»; снимок не удаляется.
4. После `initialize`: если агент объявил `sessionCapabilities.list` — первая страница
   `listSessions(cwd: projectDirectory)` в сайдбар (дальше — по `nextCursor` при прокрутке).
5. Если агент объявил `loadSession` — `loadSession(id, cwd)` для активной сессии с тем же `cwd` и
   теми же `mcpServers`, что при `session/new` по этому профилю; реплей `session/update` приходит
   до ответа и проходит через проектор с нуля (как шаг 3 переподключения). Остальные
   `openSessions` загружаются лениво — при выборе в сайдбаре.
6. Агент без `loadSession` — `newSession(cwd)` и `NoticeItem(kind: reconnected)`
   `The agent cannot restore sessions; a new session was started.`. Ошибка `session/load`
   (агент не знает этот id) — то же с текстом `Session <id> could not be restored; a new session was
   started.`, id удаляется из снимка.
7. Ничего не отправляется автоматически: восстановление не повторяет промпты и не отвечает на
   одобрения.

Тесты: kit — `test/restore/workspace_restorer_test.dart` (по одному случаю на шаги 1–7: нет
снимка, битый снимок, нет профиля, агент не запустился и «Retry», агент с `loadSession`, без
`loadSession`, ошибка `session/load`, курсор в снимок не попадает); app — сценарий перезапуска в
`session_list_load_flow_test.dart`: две сессии, закрыть корневой scope, создать заново с теми же
значениями `SharedPreferences.setMockInitialValues`, после подключения активная сессия загружена,
её транскрипт совпадает с транскриптом до перезапуска, сайдбар показывает обе сессии (критерий
D-03).

**OpenSpec change.** `extract-acp-client-kit` (задачи 5.0, 5.1, 5.3–5.9; scope: новый пакет и
его публичный API, переход app на kit без изменения поведения) и `add-session-list-and-reload`
(задачи 5.2, 5.10, 5.12; scope: `session/list` с курсором, таймауты запросов, `session/load` после
reconnect и после перезапуска app — меняет наблюдаемое поведение app); палитра с командами агента
(R-20, тест из 5.6 и исправление поведения, если тест красный) — change
`add-command-palette-agent-commands`; сторож запуска (задача 5.11) — отдельный change
`add-app-boot-watchdog`. `tasks.md` — пары "тест → реализация" со ссылкой на критерий (§9.0,
правило 3); в `extract-acp-client-kit` первая пара — характеризационные тесты 5.0 (исключение (а)).

**Что прочитать.** `docs/architecture/state-management.md` §61, §80–§82;
`docs/architecture/session-lifecycle.md`; `docs/architecture/streaming.md`;
`docs/architecture/platform-integration.md`; `docs/acp/protocol/04-Session List.md`,
`12-Session Model.md`. Документ ядра для этого этапа не нужен.

**Definition of Done.**

* Тексты 8 существующих интеграционных тестов app этапом 5 не изменены, тесты собираются;
  публичная поверхность `CodeLabShellCubit` сохранена (см. «Что остаётся неизменным»). Их прогон
  на устройстве (`melos run test:e2e:app:*`) — в ветке `release/<version>` (`AGENTS.md` §21);
  в ветке этапа поведение подтверждают характеризационные тесты 5.0 на Dart VM.
* Характеризационные тесты 5.0 зелёные до первого переноса и после каждого PR этапа без правок.
* `fvm dart test packages/dart/acp_client_kit` зелёный; среди тестов:
  `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`,
  `prompt_queue_test.dart: queued prompt is sent after the turn ends`,
  `reconnect_test.dart: open sessions are reloaded after reconnect when agent supports loadSession`.
* `fvm dart test packages/dart/acp_client_io packages/dart/acp_client_core` зелёный.
* `melos run guard`: `acp_client_kit` не импортирует Flutter и `dart:io` (в том числе транзитивно).
* `shell_cubit.dart` не содержит логики из левого столбца таблицы (проверка на ревью; цель —
  меньше 600 строк после 5.9).
* Новые тесты `session_list_load_flow_test.dart` (включая сценарий перезапуска D-03),
  `command_palette_flow_test.dart` (R-20) и `boot_watchdog_flow_test.dart` зелёные;
  `workspace_restorer_test.dart` зелёный.
* В коде kit нет членов «после MVP» (правило над эскизом API).

**Зависимости.** Этап 0 (разделение `acp_transports`, сторож). Не зависит от агентской ветки.

**Риски.** Рефакторинг ломает поведение app — шаг «фасад» под защитой интеграционных тестов,
каждая задача отдельным PR; исправления поведения (5.2, 5.10) — отдельным change. Логика снова
расползается по UI — сторож и правило ревью «логика — в kit, в Cubit и REPL — только
отображение».

---

← [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) · [Оглавление](../dart-agent-and-clients.md) · [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) →
