import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../backend/agent_backend.dart';
import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../connection/transport_resolver.dart';
import '../diagnostics/diagnostics.dart';
import '../protocol/protocol_frame_log.dart';
import '../queue/prompt_queue.dart';
import '../restore/workspace_restorer.dart';
import '../restore/workspace_snapshot.dart';
import '../session/session_views.dart';
import '../session/subagent_rows.dart';
import '../transcript/transcript_item.dart';
import '../transcript/transcript_projector.dart';
import '../usage/usage_decoder.dart';
import '../usage/usage_fold.dart';
import '../usage/usage_ledger_decoder.dart';
import '../usage/usage_ledger_models.dart';
import '../usage/usage_models.dart';
import 'client_workspace_exception.dart';
import 'workspace_state.dart';

/// Рабочее пространство клиента ACP: одно соединение с агентом и его сессии.
///
/// Почему: подключение, переподключение и сессии раньше жили в Flutter-Cubit
/// app, и CLI не мог их переиспользовать (`09-10`, этап 5). Kit держит эту
/// логику на чистом Dart, а хосты только отображают [WorkspaceState].
///
/// Для чего: владелец состояния соединения и списка сессий; публикует
/// [state] при каждом изменении и выдаёт [SessionHandle] для работы с
/// сессией.
///
/// Как использовать: composition root создаёт `ClientWorkspace(backend:
/// AcpClientBackend(application), resolvers: [...])`; затем [connect] →
/// [newSession] / [activate]; [dispose] при закрытии хоста. Ошибки
/// транспорта и агента уходят вызывающему исключениями `codelab_client_acp`
/// после публикации `ConnectionFailed`; отказы самого kit —
/// [ClientWorkspaceException].
abstract interface class ClientWorkspace {
  /// [snapshots] включает восстановление после перезапуска хоста
  /// ([restoreProject], design D6 change `add-session-list-and-reload`).
  factory ClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
    WorkspaceSnapshotStore? snapshots,

    /// Часы kit для времени работающих строк панели Agents (D49 Т3); по
    /// умолчанию `DateTime.now`, тесты передают поддельные.
    DateTime Function()? clock,

    /// Журнал kit (D14, D21 Т5): `usage.stale`, `usage.decode_failed` и отброс
    /// снимка неизвестной сессии. По умолчанию — `StructuredLogLogger`, как у
    /// `AcpClientApplication`; секретов, сумм и текста уведомлений в записях
    /// нет.
    Logger? logger,
  }) = DefaultClientWorkspace;

  WorkspaceState get current;

  /// Изменения [current]; доставляются синхронно, чтобы хост видел переход
  /// соединения сразу после события транспорта.
  Stream<WorkspaceState> get state;

  /// Подключается к агенту [profile]; [projectDirectory] — папка проекта,
  /// `cwd` новых сессий и, если профиль просит, процесса агента (корень
  /// процесса [WorkspaceState.agentDirectory] тоже становится ею — путь CLI,
  /// design D15 change `require-project-folder`). Агенту со
  /// `sessionCapabilities.list` после `initialize` отправляется первый
  /// `session/list` проекта — `Future` завершается после него; сбой списка
  /// — диагностика, а не ошибка подключения (design D3 change
  /// `add-session-list-and-reload`).
  ///
  /// Если сессии уже открыты (повторный Connect, в том числе к другому
  /// агенту), они, как после [reconnect], загружаются заново через
  /// `session/load` или становятся [SessionStatusView.detached].
  ///
  /// Повторный [connect] или [reconnect], пока прежний ещё идёт (например,
  /// долгий `open` встроенного агента), вытесняет прежнюю попытку: её
  /// `Future` завершается **без ошибки и без изменения состояния**, а итог
  /// читается из [state] / [current] (AGENTS.md §9).
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  });

  /// Агент профиля окна по требованию хоста: триггеры D13 (выбор проекта,
  /// «New session», фокус на `notLoaded` / `detached`, «Retry») вызывают её
  /// одинаково (design D15 change `require-project-folder`).
  ///
  /// Почему: хост не подключает агента кнопкой, а стартует его сам, и
  /// параллельные триггеры не должны открывать второй транспорт.
  ///
  /// Для чего и как:
  /// * [profile] — профиль старта, иначе профиль текущего или последнего
  ///   соединения; без профиля — [ClientWorkspaceException], резолверы не
  ///   вызываются.
  /// * `Connected` — no-op для любой [directory], без запросов к агенту.
  /// * Идёт попытка (`Connecting`, `Reconnecting`) — возвращается её
  ///   `Future` (single-flight, `concurrency.md` §29–§30); корень процесса
  ///   задаёт первый триггер, [directory] повторного вызова не важна. Если
  ///   попытку вытеснил явный [connect] / [reconnect], `Future` завершается
  ///   без ошибки (Q25).
  /// * Иначе (`Disconnected`, `ConnectionFailed`, `ConnectionLost`) —
  ///   новая попытка как у [connect]: [directory] становится
  ///   [WorkspaceState.agentDirectory] и отдаётся резолверу, а
  ///   [WorkspaceState.projectDirectory] (выбранный проект, снимок) не
  ///   меняется. Открытые сессии загружаются заново.
  /// * Без `projectDirectory` `session/list` не запрашивается: ACP без `cwd`
  ///   вернул бы сессии всех папок.
  ///
  /// Сам kit попытки не повторяет: после сбоя новую попытку начинает только
  /// действие пользователя (D13).
  Future<void> ensureAgent(String directory, {ConnectionProfile? profile});

  /// Одна попытка переподключения, без повторов (design D4).
  ///
  /// После неё открытые сессии загружаются заново через `session/load`,
  /// начиная с активной; агент без `loadSession` или ошибка загрузки —
  /// сессия [SessionStatusView.detached] с уведомлением в транскрипте. Пока
  /// идёт переподключение, сессии не отправляют промпты и не сливают
  /// очередь. Затем список сессий запрашивается заново, как после [connect]
  /// (design D5 change `add-session-list-and-reload`).
  ///
  /// [profile] заменяет текущий, если передан: хост мог изменить форму
  /// подключения после [connect]. Папки (design D15 change
  /// `require-project-folder`):
  /// * [projectDirectory] задаёт обе — проект и корень процесса (путь CLI);
  /// * [agentDirectory] задаёт только корень процесса и не меняет проект и
  ///   список («Restart agent» с корнем из папки сессии);
  /// * без обоих корень — прежний `agentDirectory`, а без него —
  ///   `projectDirectory`.
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
    String? agentDirectory,
  });

  /// Создаёт сессию в [cwd] (по умолчанию — папка проекта).
  ///
  /// [activate] ложно — сессия попадает в список и снимок, но
  /// `WorkspaceState.activeSessionId` не меняется: по нему работают Files и
  /// терминал, и сессия устаревшего намерения не должна переключать их
  /// мимо фокуса чата (D15, D17). По умолчанию сессия становится активной.
  Future<SessionHandle> newSession({String? cwd, bool activate = true});

  SessionHandle? session(SessionId id);

  /// Открывает сессию агента [id] через `session/load`: транскрипт строится
  /// из реплея с нуля, строка списка из [SessionStatusView.notLoaded]
  /// становится открытой. Сессию не активирует — это решает хост.
  ///
  /// Для [SessionStatusView.detached]-сессии успешная загрузка снимает
  /// `detached`: она снова принимает промпты и сливает очередь (D16 change
  /// `require-project-folder`); ошибка оставляет её `detached` с прежним
  /// уведомлением.
  ///
  /// Повторный вызов для той же сессии, пока загрузка в полёте, возвращает
  /// тот же `Future`. Без соединения или без `loadSession` у агента —
  /// [ClientWorkspaceException] без запроса к агенту; ошибка агента —
  /// диагностика и исключение вызывающему, строка остаётся `notLoaded`
  /// (design D4 change `add-session-list-and-reload`).
  Future<SessionHandle> loadSession(SessionId id, {required String cwd});

  /// Запрашивает следующую страницу `session/list`, если
  /// `WorkspaceState.hasMoreSessions`; повторный вызов, пока запрос в
  /// полёте, — no-op. Ошибка — диагностика, список остаётся прежним
  /// (design D3).
  Future<void> loadMoreSessions();

  /// Делает сессию [id] активной; неизвестный id игнорируется.
  void activate(SessionId id);

  /// Шаг 1 восстановления: читает снимок прошлого запуска и возвращает его
  /// проект — хост выбирает его до подключения. Вызывается один раз при
  /// старте хоста; до завершения чтения снимок не пишется, а изменения,
  /// пришедшие во время чтения, записываются после него. Повторный вызов
  /// возвращает результат того же чтения. Без хранилища снимка или
  /// без снимка — `null`; битый снимок — диагностика, снимок удаляется.
  ///
  /// Остальное восстановление идёт само при первом успешном [connect] в
  /// запуске: сессии снимка — в список, активная — через `session/load`;
  /// агент без `loadSession` или ошибка загрузки — новая сессия с
  /// уведомлением `NoticeKind.reconnected` (design D6).
  Future<String?> restoreProject();

  /// Старт без восстановления (D9 change `add-app-general-page`): альтернатива
  /// [restoreProject], когда хост не хочет открывать проект прошлого запуска.
  ///
  /// Снимок не читается, проект не выбирается, первое подключение не
  /// добавляет сессии снимка и не шлёт `session/load`. Запись снимка при этом
  /// разрешена: первая запись заменяет снимок прошлого запуска текущим.
  ///
  /// Хост вызывает при старте ровно один из двух методов; повторный вызов,
  /// вызов после [restoreProject] и [restoreProject] после него — пустая
  /// операция (последний возвращает `null`). Без хранилища снимка — пусто.
  void startWithoutRestore();

  /// Выбирает папку проекта: `WorkspaceState.projectDirectory` и снимок.
  ///
  /// При `Connected` и другой папке сбрасывает список и курсор и запрашивает
  /// первую страницу `session/list` нового проекта (агенту с
  /// `sessionCapabilities.list`); запрос прежнего проекта, пришедший позже,
  /// список не меняет (D15). Агента выбор проекта не трогает: стартует его
  /// хост через [ensureAgent].
  void selectProject(String path);

  /// Дожидается записи снимка, начатой до вызова; если снимок ещё читается —
  /// и записи, которую начнёт конец чтения, но чтение ждёт не дольше 2 с
  /// (зависшее хранилище не держит закрытие). Без хранилища — сразу.
  Future<void> flushSnapshot();

  /// Запрашивает журнал usage сессии [id] (`_codelab/session/usage/ledger`,
  /// change `add-usage-ledger`, D10) и ведёт `SessionView.usageLedger`.
  ///
  /// Без объявленного `usageLedger` запрос не уходит, состояние остаётся
  /// `unavailable`. На сессию — не больше одного запроса в полёте; вызовы
  /// во время полёта сливаются в один следующий, `rebuild` побеждает. Ответ
  /// применяется, только если не сменились поколение соединения и поколение
  /// загрузки сессии. Ошибки агента не бросаются: они — состояние `failed`.
  Future<void> refreshUsageLedger(SessionId id, {bool rebuild = false});

  /// Исходы ходов всех сессий — и отправленных хостом, и ушедших из
  /// очереди сами; доставляются синхронно.
  Stream<PromptOutcome> get promptOutcomes;

  /// Диагностика событий, которыми владеет kit: исходы ходов, отмена,
  /// ответы на одобрения, опции, неожиданная потеря соединения. Уже без
  /// секретов; доставляется синхронно, после публикации состояния.
  Stream<WorkspaceDiagnostic> get diagnostics;

  /// Буфер кадров ACP соединения: создаётся вместе с рабочим пространством и
  /// закрывается в [dispose]. Кадры не входят в [WorkspaceState] (design.md
  /// change `redesign-protocol-pane`, D5).
  ProtocolFrameLog get protocolFrames;

  /// Отписывается от бэкенда и закрывает потоки; бэкенд закрывает его
  /// владелец.
  Future<void> dispose();
}

/// Сессия рабочего пространства.
///
/// Почему: хосту нужен объект сессии, а не id и выборка из общего списка.
///
/// Для чего: текущее [SessionView] и его изменения, отправка промптов с
/// очередью, отмена хода, ответы на одобрения и опции конфигурации.
/// [current] обновляется синхронно с изменением сессии в ядре клиента, до
/// остальных подписчиков `sessionChanges`, подписанных позже рабочего
/// пространства (design D6).
///
/// Как использовать: [send] — свободная сессия отправляет `session/prompt`
/// сразу, занятая (`SessionView.status` — `running` или `cancelling`) ставит
/// промпт в [queue]. Future [send] завершается после конца хода и слива
/// очереди сессии, которую этот ход освободил, — как прежний
/// `CodeLabShellCubit.submitPrompt`.
abstract interface class SessionHandle {
  SessionId get id;

  String get cwd;

  SessionView get current;

  Stream<SessionView> get view;

  PromptQueue get queue;

  Future<PromptOutcome> send(String text);

  /// Отправляет `session/cancel`; ход остаётся `cancelling`, пока агент не
  /// ответит на его `session/prompt` (fix-prompt-cancel-tool-calls/design.md,
  /// D2). Ошибки — исключения `codelab_client_acp`.
  Future<PromptTurn> cancel();

  /// Повторяет последний сорвавшийся ход: его `prompt` уходит новым
  /// `session/prompt`, прежние ходы не меняются (design D4 change
  /// `add-connection-and-error-states`). Исход публикуется в
  /// `ClientWorkspace.promptOutcomes`, как у [send]. При ложном
  /// `SessionView.canRetry` — [ClientWorkspaceException] без запроса.
  Future<PromptOutcome> retry();

  /// Отвечает на одобрение [approval] этой сессии вариантом [option]
  /// (отказ — тоже вариант: в ACP нет отдельного «отклонить»). Одобрение
  /// другой сессии отклоняет ядро клиента (PERM-003,
  /// `docs/architecture/permissions.md`).
  Future<ApprovalRequest> respond(
    ApprovalRequestId approval,
    PermissionOptionId option,
  );

  /// Отправляет `session/set_config_option`; пока запрос в полёте,
  /// `SessionView.configOptionInFlight` — [configId], а повторный вызов —
  /// no-op. Показываемое значение приходит из ответа агента, а не
  /// выставляется заранее. Ошибка — диагностика и исключение вызывающему.
  Future<void> setConfigOption(String configId, String valueId);
}

/// Реализация [ClientWorkspace] по умолчанию.
final class DefaultClientWorkspace implements ClientWorkspace {
  DefaultClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
    WorkspaceSnapshotStore? snapshots,
    DateTime Function()? clock,
    Logger? logger,
  }) : clock = clock ?? DateTime.now,
       _backend = backend,
       _resolvers = List.unmodifiable(resolvers),
       _logger = (logger ?? StructuredLogLogger('codelab_client_core')).bind({
         logComponentKey: clientComponent,
       }) {
    if (snapshots != null) {
      _restorer = WorkspaceRestorer(snapshots, _RestoreHostAdapter(this));
    }
    _connectionSubscription = backend.connectionStates.listen(
      _handleConnectionState,
    );
    _sessionSubscription = backend.sessionChanges.listen(_handleSession);
    _usageSubscription = backend.usageNotifications.listen(_handleUsage);
    protocolFrames = ProtocolFrameLog(backend: backend, logger: _logger);
  }

  /// Часы kit: момент первого появления вызова `agent` для времени строк
  /// панели Agents (D49 Т3); в `_SessionHandle` передаются при создании.
  final DateTime Function() clock;
  final AgentBackend _backend;
  final List<TransportResolver> _resolvers;

  /// Восстановление и запись снимка; `null` — хранилища снимка нет.
  WorkspaceRestorer? _restorer;
  var _disposed = false;
  final _states = StreamController<WorkspaceState>.broadcast(sync: true);
  final _outcomes = StreamController<PromptOutcome>.broadcast(sync: true);
  final _diagnostics = StreamController<WorkspaceDiagnostic>.broadcast(
    sync: true,
  );

  /// Счётчик id элементов очереди: общий для всех сессий, чтобы id не
  /// повторялись в пределах рабочего пространства.
  var _nextQueuedPromptId = 0;
  final _handles = <SessionId, _SessionHandle>{};

  /// Порядок открытых сессий: от новой к старой.
  final _order = <SessionId>[];

  /// Ещё не открытые сессии агента из `session/list` в его порядке.
  final _listed = <SessionId, SessionInfo>{};

  /// `nextCursor` последней страницы; непрозрачен и наружу не отдаётся
  /// (`04-Session List.md`, «Pagination»).
  String? _nextCursor;

  /// Запрос следующей страницы ([loadMoreSessions]) в полёте. Защищает только
  /// от повторного `loadMoreSessions`: первая страница нового проекта или
  /// соединения его не ждёт и сбрасывает (D15).
  Future<void>? _listing;

  /// Номер запроса `session/list`: растёт на каждой первой странице
  /// (подключение, `selectProject`). Ответ с устаревшим номером после `await`
  /// не трогает [_listed], курсор и `hasMoreSessions` — late events прежнего
  /// проекта или соединения не меняют актуальный список (AGENTS.md §9; D15,
  /// D17 change `require-project-folder`).
  var _listRequest = 0;

  /// `Future` идущей попытки подключения (`connect`, `reconnect` или
  /// `ensureAgent`): single-flight для [ensureAgent] (D15). Вытесненная
  /// попытка в поле заменяется следующей; чистит поле завершившаяся попытка,
  /// если её не заменили.
  Future<void>? _attemptFuture;

  /// Возможности агента из ответа `initialize` текущего соединения.
  AgentCapabilities _capabilities = const AgentCapabilities();

  final _loading = <SessionId, Future<SessionHandle>>{};

  /// Сессии, загружаемые через `session/load`: их следующий снимок из ядра —
  /// реплей, и проекция транскрипта строится заново (design D4).
  final _reloading = <SessionId>{};

  /// Снимки `_codelab/session/usage`, пришедшие для сессии, которую ещё
  /// грузят и которой нет в рабочем пространстве (change `add-usage-ledger`,
  /// D10): порядок потока сессий и потока уведомлений ядра клиента не
  /// гарантирован (§9), поэтому снимок `trigger: "load"` ждёт регистрации
  /// сессии. Хранится последний по `seq`; применяется в [_track], при сбое
  /// загрузки отбрасывается с `usage.unknown_session`.
  final _pendingUsage = <SessionId, _PendingUsage>{};

  /// Запросы журнала usage в полёте по сессиям: слияние вызовов (D10).
  final _ledgerFlights = <SessionId, _LedgerFlight>{};

  /// Пары «сессия, поле», по которым `usage.ledger.decode_failed` уже записан
  /// (не чаще раза на сессию и поле); очищается со сбросом соединения.
  final _ledgerWarned = <String>{};

  static const _ledgerDecoder = UsageLedgerDecoder();

  late final StreamSubscription<ClientConnectionState> _connectionSubscription;
  late final StreamSubscription<AcpSession> _sessionSubscription;

  /// Подписка на `_codelab/session/usage`: владелец — рабочее пространство,
  /// `dispose` её отменяет (`AGENTS.md` §9).
  late final StreamSubscription<UsageNotification> _usageSubscription;
  final Logger _logger;
  static const _usageDecoder = UsageDecoder();

  /// Пары «сессия, поле», по которым `usage.decode_failed` уже записан:
  /// предупреждение не чаще раза на сессию и поле (D14), иначе агент с
  /// постоянным дефектом заливал бы журнал на каждом шаге.
  final _usageWarned = <String>{};
  var _current = const WorkspaceState();

  /// Какой переход ведёт явный вызов: промежуточные состояния ядра
  /// (`disconnected`, `connecting`, `initializing`) при переподключении
  /// остаются `Reconnecting`, а не мигают `Connecting`.
  _Transition _transition = _Transition.none;

  /// Номер последней начатой попытки подключения (поколение): растёт на
  /// каждом `connect`/`reconnect` и на `dispose`. Устаревшая попытка не
  /// публикует состояние, не трогает сессии и не сбрасывает [_transition]
  /// (AGENTS.md §9; см. [_isStale]).
  var _attempt = 0;

  /// Номер попытки kit, которая последней передала транспорт бэкенду.
  ///
  /// Почему: ядро ведёт попытку на своём поколении и не знает про [_attempt].
  /// События ядра принадлежат текущей попытке, только если она сама отдала
  /// транспорт бэкенду (`_backendAttempt == _attempt`); иначе это хвост
  /// вытесненной попытки, пока новая ещё открывает транспорт или уже упала на
  /// `open` (`_transition == none`), и [_handleConnectionState] отбрасывает
  /// любое такое состояние. Начальные значения равны (0): хост, ведущий ядро
  /// сам без `connect` kit, события не теряет. `dispose` увеличивает
  /// [_attempt], и события после него отбрасываются.
  var _backendAttempt = 0;

  /// Последний сбой соединения, объявленный ядром во время явной попытки
  /// подключения, с поколением ядра на этот момент.
  ///
  /// Почему поле: в окне явной попытки [_handleConnectionState] сбой не
  /// публикует (см. там), а причина (`reason`, `message` ядра) нужна
  /// [_publishFailure]. Поколение отличает сбой текущей попытки от сбоя
  /// вытесненной: сбой новой попытки возникает после замены транспорта, то
  /// есть на поколении выше того, что было при её старте.
  ({int generation, ConnectionView failure})? _coreFailure;

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => _states.stream;

  @override
  Stream<PromptOutcome> get promptOutcomes => _outcomes.stream;

  @override
  Stream<WorkspaceDiagnostic> get diagnostics => _diagnostics.stream;

  @override
  late final ProtocolFrameLog protocolFrames;

  @override
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) => _begin(
    _connect(
      profile,
      agentDirectory: projectDirectory,
      projectDirectory: projectDirectory,
    ),
  );

  @override
  Future<void> ensureAgent(String directory, {ConnectionProfile? profile}) {
    final target = profile ?? _current.profile;
    if (target == null) {
      return Future.error(
        const ClientWorkspaceException(
          'Select a connection profile before starting the agent.',
        ),
      );
    }
    switch (_current.connection) {
      case Connected():
        return Future.value();
      case Connecting() || Reconnecting():
        // Параллельные триггеры (D13) ждут одну попытку; корень процесса
        // задал первый из них (D15, `concurrency.md` §29–§30).
        return _attemptFuture ?? Future.value();
      case Disconnected() || ConnectionFailed() || ConnectionLost():
        // Проект не перезаписывается: `ensureAgent` не выбирает проект, а
        // только поднимает агента (D15).
        return _begin(_connect(target, agentDirectory: directory));
    }
  }

  /// Запоминает [attempt] как идущую попытку для single-flight.
  ///
  /// Почему не `whenComplete`: он создал бы производный `Future` с той же
  /// ошибкой, которого никто не ждёт (необработанное исключение); ошибку
  /// получает только вызывающий.
  Future<void> _begin(Future<void> attempt) {
    _attemptFuture = attempt;
    unawaited(
      attempt
          .then<void>((_) {}, onError: (Object _) {})
          .then<void>(
            (_) => identical(_attemptFuture, attempt)
                ? _attemptFuture = null
                : null,
          ),
    );
    return attempt;
  }

  /// Общее тело [connect] и [ensureAgent].
  ///
  /// [agentDirectory] — корень процесса, его получает резолвер;
  /// [projectDirectory] `null` — проект не меняется (путь `ensureAgent`).
  Future<void> _connect(
    ConnectionProfile profile, {
    required String agentDirectory,
    String? projectDirectory,
  }) async {
    final resolver = _resolverFor(profile);
    if (resolver == null) {
      throw _rejectUnsupported(profile, agentDirectory, projectDirectory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.connecting(),
        profile: profile,
        agentDirectory: agentDirectory,
        projectDirectory: projectDirectory ?? _current.projectDirectory,
      ),
    );
    _transition = _Transition.connecting;
    final attempt = ++_attempt;
    final baseGeneration = _backend.generation;
    _coreFailure = null;
    // Повторный Connect — новый процесс агента, а то и другой агент из
    // диалога подключения: открытые сессии он не знает. Как при Reconnect,
    // они не шлют промпты, пока не перезагружены, а после подключения
    // загружаются заново или становятся detached; иначе промпт уходил агенту
    // и падал «Session not found».
    final reattach = _handles.isNotEmpty;
    for (final handle in _handles.values) {
      handle.suspend();
    }
    try {
      final transport = await resolver.open(
        profile,
        projectDirectory: agentDirectory,
      );
      if (_isStale(attempt)) {
        // Транспорт ещё не передан бэкенду, владельца у него нет (§9).
        await _closeSuperseded(transport);
        return;
      }
      _backendAttempt = attempt;
      final connectionState = await _backend.connect(transport);
      if (_isStale(attempt)) {
        // Транспорт уже у бэкенда: следующая попытка заменит и закроет его.
        return;
      }
      _capabilities = _capabilitiesOf(connectionState);
      _resetUsage();
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      if (_isStale(attempt)) {
        return;
      }
      for (final handle in _handles.values) {
        handle.resume();
      }
      _publishFailure(error, baseGeneration);
      _transition = _Transition.none;
      rethrow;
    }
    _transition = _Transition.none;
    if (reattach) {
      await _reattachSessions(attempt);
    }
    if (_isStale(attempt)) {
      return;
    }
    await _listFirstPage();
    if (_isStale(attempt)) {
      return;
    }
    await _restorer?.restoreAfterConnect();
  }

  @override
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
    String? agentDirectory,
  }) => _begin(
    _reconnect(
      profile: profile,
      projectDirectory: projectDirectory,
      agentDirectory: agentDirectory,
    ),
  );

  Future<void> _reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
    String? agentDirectory,
  }) async {
    final target = profile ?? _current.profile;
    // Корень процесса (D15): явный `agentDirectory`, затем папка проекта из
    // параметра (путь CLI задаёт обе), затем прежний корень и проект.
    final directory =
        agentDirectory ??
        projectDirectory ??
        _current.agentDirectory ??
        _current.projectDirectory;
    if (target == null || directory == null) {
      throw const ClientWorkspaceException(
        'Connect an agent before reconnecting.',
      );
    }
    final resolver = _resolverFor(target);
    if (resolver == null) {
      throw _rejectUnsupported(target, directory, projectDirectory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.reconnecting(attempt: 1),
        profile: target,
        agentDirectory: directory,
        projectDirectory: projectDirectory ?? _current.projectDirectory,
      ),
    );
    _transition = _Transition.reconnecting;
    final attempt = ++_attempt;
    final baseGeneration = _backend.generation;
    _coreFailure = null;
    // Ход, оборванный заменой транспорта, не должен слить очередь в новое
    // соединение раньше, чем сессия загружена в нём.
    for (final handle in _handles.values) {
      handle.suspend();
    }
    try {
      final connectionState = await _backend.reconnect(
        ReconnectCommand(
          transportFactory: () async {
            final transport = await resolver.open(
              target,
              projectDirectory: directory,
            );
            if (_isStale(attempt)) {
              // Бэкенд ещё не принял транспорт: закрываем его сами и
              // прерываем попытку до замены текущего транспорта.
              await _closeSuperseded(transport);
              throw const _SupersededAttempt();
            }
            // Транспорт уходит бэкенду: дальше события ядра — этой попытки.
            _backendAttempt = attempt;
            return transport;
          },
        ),
      );
      if (_isStale(attempt)) {
        return;
      }
      _capabilities = _capabilitiesOf(connectionState);
      _resetUsage();
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      if (_isStale(attempt)) {
        return;
      }
      for (final handle in _handles.values) {
        handle.resume();
      }
      _publishFailure(error, baseGeneration);
      _transition = _Transition.none;
      rethrow;
    }
    _transition = _Transition.none;
    await _reattachSessions(attempt);
    if (_isStale(attempt)) {
      return;
    }
    await _listFirstPage();
  }

  /// Попытка подключения [attempt] вытеснена более новой или `dispose`.
  ///
  /// Почему: повторный `connect`/`reconnect` во время долгого `open`
  /// (встроенный агент, решение L4 `add-embedded-agent-mode`) — штатный способ
  /// прервать подключение, а завершение старой попытки не должно менять
  /// состояние новой (AGENTS.md §9: late events старого request не меняют
  /// актуальный state).
  bool _isStale(int attempt) => attempt != _attempt;

  /// Закрывает транспорт вытесненной попытки, который не достался бэкенду.
  ///
  /// Ошибка закрытия не важна: транспорт уже не нужен никому, а сбой не
  /// должен подменить результат актуальной попытки.
  Future<void> _closeSuperseded(AcpTransport transport) async {
    try {
      await transport.close();
    } on Object {
      // Намеренно проглочено, см. выше.
    }
  }

  /// Загружает открытые сессии в новом соединении, активную первой: её
  /// транскрипт пользователь видит сразу, а фоновые его не задерживают.
  Future<void> _reattachSessions(int attempt) async {
    final active = _current.activeSessionId;
    final ids = [
      if (active != null && _handles.containsKey(active)) active,
      for (final id in _order)
        if (id != active) id,
    ];
    for (final id in ids) {
      if (_isStale(attempt)) {
        // Новая попытка сама приостановила сессии и перезагрузит их.
        return;
      }
      final handle = _handles[id]!;
      if (!_capabilities.loadSession) {
        handle.detach(
          'The agent cannot restore sessions after reconnecting.',
          const SessionRestoreReason(SessionRestoreCause.agentCannotRestore),
        );
        continue;
      }
      try {
        await _load(id, handle.cwd);
        if (!_isStale(attempt)) {
          handle.resume();
        }
      } on Object {
        if (_isStale(attempt)) {
          return;
        }
        handle.detach(
          'Session ${id.value} could not be restored after reconnecting.',
          SessionRestoreReason(
            SessionRestoreCause.restoreFailed,
            sessionId: id,
          ),
        );
      }
    }
    _publish(_current.copyWith(sessions: _summaries()));
  }

  @override
  Future<SessionHandle> newSession({String? cwd, bool activate = true}) async {
    if (_current.connection is! Connected) {
      throw const ClientWorkspaceException(
        'Connect an agent before creating a session.',
      );
    }
    // `cwd` без проекта допустим: сессия `ensureAgent` без выбранного проекта
    // (D13, триггер 3) живёт в своей папке.
    final directory = cwd ?? _current.projectDirectory;
    if (directory == null) {
      throw const ClientWorkspaceException(
        'Select a project folder before creating a session.',
      );
    }

    final session = await _backend.createSession(
      CreateSessionCommand(cwd: directory),
    );
    final handle = _track(session);
    _publish(
      _current.copyWith(
        sessions: _summaries(),
        // Сессия устаревшего намерения не забирает фокус Files и терминала
        // (D17).
        activeSessionId: activate ? session.id : _current.activeSessionId,
      ),
    );
    return handle;
  }

  @override
  SessionHandle? session(SessionId id) => _handles[id];

  @override
  Future<void> refreshUsageLedger(SessionId id, {bool rebuild = false}) {
    final handle = _handles[id];
    if (handle == null) {
      return Future.error(
        ClientWorkspaceException('Unknown session ${id.value}.'),
      );
    }
    // Без объявленного `usageLedger` кадр не уходит, состояние — `unavailable`.
    if (!_ledgerDeclared || _disposed) {
      return Future.value();
    }
    final flight = _ledgerFlights[id];
    if (flight != null) {
      // Вызов во время полёта сливается в один следующий запрос; `rebuild`
      // побеждает (D10).
      flight.queuedRebuild = flight.queuedRebuild || rebuild;
      // Контекст последнего слитого вызова: перед запросом он сверяется с
      // текущим (соединение и загрузка сессии могли смениться за полёт).
      flight.queuedEpoch = handle.ledgerEpoch;
      flight.queuedGeneration = _backend.generation;
      return (flight.queued ??= Completer<void>()).future;
    }
    return _driveLedger(handle, rebuild);
  }

  /// Цикл запросов журнала сессии: текущий, затем (если во время него были
  /// вызовы) один слитый следующий.
  Future<void> _driveLedger(_SessionHandle handle, bool rebuild) async {
    final flight = _ledgerFlights[handle.id] = _LedgerFlight();
    var next = rebuild;
    Completer<void>? waiter;
    try {
      while (true) {
        try {
          await _requestLedger(handle, next);
        } finally {
          waiter?.complete();
        }
        waiter = flight.queued;
        if (waiter == null) {
          return;
        }
        next = flight.queuedRebuild;
        final epoch = flight.queuedEpoch;
        final generation = flight.queuedGeneration;
        flight.queued = null;
        flight.queuedRebuild = false;
        // Слитый запрос уходит, только если условия вызова всё ещё верны
        // (D10, §9): не закрыто рабочее пространство, не сменились эпоха
        // журнала и поколение соединения. Иначе ожидающие завершаются без
        // кадра, а состояние — `idle` или `unavailable`, не `failed`.
        // Проверка `_ledgerDeclared` ЗАЩИТНАЯ и дублирует проверку поколения:
        // возможности агента меняются только с новым `Ready`, а каждый
        // `connect`/`reconnect` ядра клиента сначала заменяет транспорт и
        // увеличивает поколение, поэтому объявление не может пропасть при том
        // же поколении. Оставлена на случай будущего источника возможностей
        // без смены поколения; отдельного теста у неё нет (недостижима).
        if (_disposed ||
            !_ledgerDeclared ||
            handle.ledgerEpoch != epoch ||
            _backend.generation != generation) {
          if (!_disposed) {
            _logger
                .withCorrelation(
                  sessionId: handle.id.value,
                  connectionGeneration: _backend.generation,
                )
                .debug('usage.ledger.stale');
            if (handle.ledgerEpoch == epoch) {
              handle.setLedger(handle.ledgerBase());
            }
          }
          waiter.complete();
          return;
        }
      }
    } finally {
      _ledgerFlights.remove(handle.id);
      flight.queued?.complete();
    }
  }

  /// Один запрос журнала: `loading` → `loaded` | `failed` | отброс как
  /// устаревшего (поколение соединения или загрузка сессии сменились).
  Future<void> _requestLedger(_SessionHandle handle, bool rebuild) async {
    final id = handle.id;
    final epoch = handle.ledgerEpoch;
    final generation = _backend.generation;
    final log = _logger.withCorrelation(
      sessionId: id.value,
      connectionGeneration: generation,
    );
    handle.setLedger(UsageLedgerState.loading(previous: handle.ledgerView));
    log.debug('usage.ledger.requested', context: {'rebuild': rebuild});

    bool stale() =>
        handle.ledgerEpoch != epoch || _backend.generation != generation;
    void drop() {
      log.debug('usage.ledger.stale');
      // Сброс уже вернул `idle`; если соединение сменилось, а сброс ещё не
      // дошёл (ошибка ожидавшего запроса приходит раньше), не оставляем
      // вечный `loading`.
      if (handle.ledgerEpoch == epoch) {
        handle.setLedger(handle.ledgerBase());
      }
    }

    final UsageLedgerReply reply;
    try {
      reply = await _backend.requestUsageLedger(
        sessionId: id,
        rebuild: rebuild,
      );
    } on Object catch (error) {
      if (stale() || _disposed) {
        if (!_disposed) {
          drop();
        }
        return;
      }
      final cause = error is AcpClientApplicationException ? error.cause : null;
      final code = cause is JsonRpcError ? cause.code : null;
      // Ответ не объектом ядро клиента отвергает как нарушение формы: для
      // хоста это сбой разбора, а не сбой запроса.
      final malformed = cause is JsonRpcProtocolException;
      handle.setLedger(
        UsageLedgerState.failed(
          UsageLedgerFailure(
            kind: malformed
                ? UsageLedgerFailureKind.decode
                : code == null
                ? UsageLedgerFailureKind.request
                : UsageLedgerFailureKind.agentError,
            code: code,
          ),
          previous: handle.ledgerView,
        ),
      );
      log.warning(
        'usage.ledger.failed',
        context: {
          'code': ?code,
          if (code == null) 'reason': malformed ? 'malformed' : 'request',
        },
      );
      return;
    }
    if (stale() || reply.generation != _backend.generation || _disposed) {
      if (!_disposed) {
        drop();
      }
      return;
    }
    void warn(String field, String reason) {
      if (_ledgerWarned.add('${id.value}|$field')) {
        log.warning(
          'usage.ledger.decode_failed',
          context: {'field': field, 'reason': reason},
        );
      }
    }

    final view = _ledgerDecoder.decode(reply.result, onWarning: warn);
    // Ответ о другой сессии не применяется (значение в запись не попадает).
    if (view != null && view.sessionId != id) {
      warn('sessionId', 'mismatch');
    }
    if (view == null || view.sessionId != id) {
      handle.setLedger(
        UsageLedgerState.failed(
          const UsageLedgerFailure(kind: UsageLedgerFailureKind.decode),
          previous: handle.ledgerView,
        ),
      );
      return;
    }
    handle.setLedger(UsageLedgerState.loaded(view));
    log.debug(
      'usage.ledger.received',
      context: {'seq': view.seq, 'turns': view.turns.length},
    );
  }

  @override
  Future<SessionHandle> loadSession(SessionId id, {required String cwd}) {
    final inFlight = _loading[id];
    if (inFlight != null) {
      return inFlight;
    }
    if (_current.connection is! Connected) {
      return Future.error(
        const ClientWorkspaceException(
          'Connect an agent before loading a session.',
        ),
      );
    }
    if (!_capabilities.loadSession) {
      return Future.error(
        const ClientWorkspaceException('The ACP agent cannot load sessions.'),
      );
    }
    final loading = _loadAndResume(id, cwd);
    _loading[id] = loading;
    return loading.whenComplete(() => _loading.remove(id));
  }

  /// Загрузка по запросу хоста. `detached`-сессия после успешного
  /// `session/load` снова связана с агентом: принимает промпты и сливает
  /// очередь (D16). Ошибка загрузки идёт вызывающему, сессия остаётся
  /// `detached` с прежним уведомлением.
  Future<SessionHandle> _loadAndResume(SessionId id, String cwd) async {
    final attempt = _attempt;
    final wasDetached = _handles[id]?.isDetached ?? false;
    final handle = await _load(id, cwd);
    // Соединение могло смениться во время загрузки: новая попытка сама
    // перезагрузит сессию (§9).
    if (wasDetached && !_isStale(attempt)) {
      _handles[id]?.resume();
      _publish(_current.copyWith(sessions: _summaries()));
    }
    return handle;
  }

  Future<SessionHandle> _load(SessionId id, String cwd) async {
    _reloading.add(id);
    // Сброс расхода и журнала — В НАЧАЛЕ загрузки, до отправки запроса (D10):
    // снимок `load` приходит после ответа, но может быть обработан раньше
    // обновления сессии по ответу, и сброс по ответу его стёр бы.
    _handles[id]?.beginLoad();
    try {
      final session = await _backend.loadSession(
        LoadSessionCommand(sessionId: id, cwd: cwd),
      );
      // Строка `session/list` остаётся: из неё заголовок и время изменения,
      // а дубля нет — открытая сессия в [_summaries] вытесняет её.
      final handle = _track(session);
      _publish(_current.copyWith(sessions: _summaries()));
      return handle;
    } on Object catch (error) {
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'session',
          message:
              'Failed to load ACP session ${id.value}: '
              '${_diagnosticFailureText(error)}',
        ),
      );
      rethrow;
    } finally {
      _reloading.remove(id);
      // Сессия не зарегистрирована (сбой загрузки): ожидавший снимок
      // отбрасывается, состояние рабочего пространства не меняется (D10).
      final dropped = _pendingUsage.remove(id);
      if (dropped != null) {
        _logger
            .withCorrelation(
              sessionId: id.value,
              connectionGeneration: dropped.generation,
            )
            .debug('usage.unknown_session');
      }
    }
  }

  @override
  Future<void> loadMoreSessions() async {
    final cursor = _nextCursor;
    if (cursor == null || _listing != null) {
      return;
    }
    final listing = _fetchPage(cursor, _listRequest);
    _listing = listing;
    try {
      await listing;
    } finally {
      // Первая страница нового проекта могла уже сбросить защиту (D15).
      if (identical(_listing, listing)) {
        _listing = null;
      }
    }
  }

  /// Первая страница списка после подключения или смены проекта: прежний
  /// список и курсор принадлежали старому соединению или проекту (design D3).
  ///
  /// Без `projectDirectory` запроса нет: ACP без `cwd` вернул бы сессии всех
  /// папок, а сайдбар показывает список проекта (D15).
  Future<void> _listFirstPage() async {
    final request = ++_listRequest;
    _listing = null;
    _listed.clear();
    _nextCursor = null;
    if (_capabilities.sessionCapabilities.list == null ||
        _current.projectDirectory == null) {
      _publish(
        _current.copyWith(sessions: _summaries(), hasMoreSessions: false),
      );
      return;
    }
    await _fetchPage(null, request);
  }

  Future<void> _fetchPage(String? cursor, int request) async {
    try {
      final page = await _backend.listSessions(
        cwd: _current.projectDirectory,
        cursor: cursor,
      );
      if (request != _listRequest) {
        return;
      }
      for (final info in page.sessions) {
        _listed.putIfAbsent(info.sessionId, () => info);
      }
      _nextCursor = page.nextCursor;
    } on Object catch (error) {
      if (request != _listRequest) {
        return;
      }
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'session',
          message:
              'Failed to list ACP sessions: ${_diagnosticFailureText(error)}',
        ),
      );
    }
    _publish(
      _current.copyWith(
        sessions: _summaries(),
        hasMoreSessions: _nextCursor != null,
      ),
    );
  }

  @override
  void activate(SessionId id) {
    if (!_handles.containsKey(id) || _current.activeSessionId == id) {
      return;
    }
    _publish(_current.copyWith(activeSessionId: id));
  }

  @override
  Future<String?> restoreProject() async => await _restorer?.readProject();

  @override
  void startWithoutRestore() => _restorer?.skip();

  @override
  void selectProject(String path) {
    final changed = _current.projectDirectory != path;
    _publish(_current.copyWith(projectDirectory: path));
    // Агент уже работает: список нового проекта нужен сразу. Без агента его
    // запросит подключение (`ensureAgent` / `connect`) по `projectDirectory`
    // на момент запроса, поэтому A -> B -> A во время старта даёт один список.
    if (changed && !_disposed && _current.connection is Connected) {
      unawaited(_listFirstPage());
    }
  }

  @override
  Future<void> flushSnapshot() => _restorer?.flush() ?? Future<void>.value();

  /// Добавляет сессии снимка строками `notLoaded`, если их нет в списке.
  void _rememberSessions(List<SessionRef> sessions) {
    for (final session in sessions) {
      if (!_handles.containsKey(session.id)) {
        _listed.putIfAbsent(
          session.id,
          () => SessionInfo(sessionId: session.id, cwd: session.cwd),
        );
      }
    }
    _publish(_current.copyWith(sessions: _summaries()));
  }

  Future<SessionHandle> _newSessionWithNotice(
    String cwd,
    String text, {
    required SessionRestoreReason reason,
  }) async {
    final handle = await newSession(cwd: cwd);
    _handles[handle.id]!.notify(
      NoticeItem(
        id: '${handle.id.value}/reconnected',
        kind: NoticeKind.reconnected,
        text: text,
        reason: reason,
      ),
    );
    return handle;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _attempt++;
    // Последняя запись снимка не теряется при закрытии хоста (design D6).
    await _restorer?.flush();
    await _connectionSubscription.cancel();
    await _sessionSubscription.cancel();
    await _usageSubscription.cancel();
    await protocolFrames.dispose();
    for (final handle in _handles.values) {
      await handle.close();
    }
    await _states.close();
    await _outcomes.close();
    await _diagnostics.close();
  }

  TransportResolver? _resolverFor(ConnectionProfile profile) {
    for (final resolver in _resolvers) {
      if (resolver.supports(profile)) {
        return resolver;
      }
    }
    return null;
  }

  /// Публикует сбой профиля без резолвера и возвращает исключение для
  /// вызывающего; транспорт не открывается.
  UnsupportedConnectionProfileException _rejectUnsupported(
    ConnectionProfile profile,
    String agentDirectory,
    String? projectDirectory,
  ) {
    final error = UnsupportedConnectionProfileException(profile);
    _publish(
      _current.copyWith(
        connection: ConnectionView.failed(
          reason: ConnectionFailureReason.startFailed,
          message: error.message,
        ),
        profile: profile,
        agentDirectory: agentDirectory,
        projectDirectory: projectDirectory ?? _current.projectDirectory,
      ),
    );
    return error;
  }

  /// Принимает состояния соединения ядра и публикует их как вид соединения.
  ///
  /// Состояние ядра не несёт поколения, поэтому принадлежность определяется
  /// двумя признаками (§9, спецификация `acp-client-kit`, «Явный автомат
  /// соединения»):
  ///  * `_backendAttempt != _attempt` — транспорт текущей попытки бэкенду ещё
  ///    не передан (идёт `resolver.open` или он упал), любое состояние ядра —
  ///    хвост вытесненной попытки (`disconnect`/`connect`/`initialize` так же
  ///    затёрли бы сбой новой попытки, как `ready`/`fail`); оно отбрасывается
  ///    целиком независимо от [_transition];
  ///  * `_transition != none` — идёт явная попытка kit, которая уже отдала
  ///    транспорт: её исход публикует вызывающий (`_connect`/`_reconnect`,
  ///    [_publishFailure]), `ready`/`fail` не публикуются, а сбой ядра
  ///    запоминается в [_coreFailure]; промежуточные состояния проходят.
  /// Ветка «хост ведёт ядро сам» и `ConnectionLost` не затронуты:
  /// `_backendAttempt == _attempt` и `_transition == none`. Вдобавок ядро не
  /// делает переходов вытесненной попытке после замены транспорта
  /// (`AcpClientApplication._establishConnection`).
  void _handleConnectionState(ClientConnectionState connectionState) {
    if (_backendAttempt != _attempt) {
      return;
    }
    if (_transition != _Transition.none) {
      if (connectionState is ClientConnectionFailed) {
        _coreFailure = (
          generation: _backend.generation,
          failure: _viewFor(connectionState),
        );
      }
      if (connectionState is ClientConnectionReady ||
          connectionState is ClientConnectionFailed) {
        return;
      }
    }
    // Возможности агента берутся и из потока состояний: хост может вести
    // `AcpClientApplication` сам (прогон фикстур), без `connect` kit, а
    // объявление `usage` и `usageLedger` нужно операциям kit (D10).
    if (connectionState is ClientConnectionReady) {
      _capabilities = _capabilitiesOf(connectionState);
    }
    final wasConnected = _current.connection is Connected;
    final view = _viewFor(connectionState);
    // Сбой явного connect/reconnect сообщает вызывающий; здесь — только
    // неожиданная потеря установленного соединения. Она публикуется как
    // `ConnectionLost`, а не `ConnectionFailed` (design D1 change
    // `add-connection-and-error-states`).
    if (view is ConnectionFailed &&
        wasConnected &&
        _transition == _Transition.none) {
      _publishConnection(
        ConnectionView.lost(reason: view.reason, message: view.message),
      );
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'transport',
          message: 'Connection to ACP agent lost: ${view.message}',
        ),
      );
      return;
    }
    _publishConnection(view);
  }

  /// Текст сбоя для записи диагностики ([WorkspaceDiagnostic]), а не для
  /// пользователя (design.md change `redesign-protocol-pane`, D3, «Текст
  /// ошибки агента»).
  ///
  /// Почему: `JsonRpcError.message` и `data` агента — payload (пути,
  /// фрагменты данных). При базовой `metadataOnly` диагностика несёт только
  /// метаданные (`describeFailureMetadata`), при `full` — замаскированный
  /// текст (`describeFailure`). Политику читает порт у ядра клиента — второго
  /// источника нет. Текст для пользователя (`PromptFailed.error`, заметка
  /// транскрипта, баннер) по-прежнему строит `describeFailure`.
  String _diagnosticFailureText(Object error) =>
      describeFailureForDiagnostic(error, _backend.protocolPayloads);

  /// Публикует диагностику после редакции секретов.
  void _report(WorkspaceDiagnostic diagnostic) {
    if (_diagnostics.isClosed) {
      return;
    }
    _diagnostics.add(
      WorkspaceDiagnostic(
        severity: diagnostic.severity,
        source: diagnostic.source,
        message: _redactor.redactText(diagnostic.message),
      ),
    );
  }

  /// Объявил ли агент текущего соединения `usage` (D3, D21 Т4).
  bool get _usageDeclared => CodelabExtensions.parse(_capabilities.meta).usage;

  /// Объявил ли агент текущего соединения `usageLedger` (D7, D10).
  bool get _ledgerDeclared =>
      CodelabExtensions.parse(_capabilities.meta).usageLedger;

  /// Новое соединение — новый агент: расход каждой открытой сессии
  /// сбрасывается, даже если сессию новое соединение не загрузило
  /// (`detached`). Сброс идёт здесь, по готовому `initialize` нового
  /// соединения, а не в `suspend()` начала `reconnect`: до замены транспорта
  /// старый агент ещё может прислать снимок (D21 Т2); дальше поколение
  /// снимка защищает от него в `UsageFold`.
  ///
  /// В окне до сброса (между новым соединением и готовым `initialize`) агент
  /// CodeLab снимков не шлёт — первый снимок идёт только после первого хода
  /// (Q7), поэтому там нечего терять. Ключи [_usageWarned] очищаются
  /// вместе со сбросом: набор не растёт за жизнь рабочего пространства, а
  /// новый агент снова вправе получить одну запись `usage.decode_failed`.
  void _resetUsage() {
    _usageWarned.clear();
    _ledgerWarned.clear();
    for (final handle in _handles.values) {
      handle.resetUsage();
    }
  }

  /// Снимок `_codelab/session/usage` (D7, D14, D21 Т4, Т5): разбор, свёртка
  /// по `seq` и поколению, одна ревизия `SessionView` на применённый снимок.
  void _handleUsage(UsageNotification notification) {
    final sessionId = notification.sessionId.value;
    final handle = _handles[notification.sessionId];
    // Поколение соединения снимка — в каждую запись kit (D14, §16).
    final log = _logger.withCorrelation(
      sessionId: sessionId,
      connectionGeneration: notification.generation,
    );
    final loading =
        handle == null && _reloading.contains(notification.sessionId);
    if (handle == null && !loading) {
      log.debug('usage.unknown_session');
      return;
    }
    final snapshot = _usageDecoder.decode(
      notification.params,
      onWarning: (field, reason) {
        if (_usageWarned.add('$sessionId|$field')) {
          log.warning(
            'usage.decode_failed',
            context: {'field': field, 'reason': reason},
          );
        }
      },
    );
    if (snapshot == null) {
      return;
    }
    if (handle == null) {
      // Загрузка идёт, сессии ещё нет: хранится последний снимок по `seq`.
      final waiting = _pendingUsage[notification.sessionId];
      if (waiting == null ||
          notification.generation > waiting.generation ||
          (notification.generation == waiting.generation &&
              snapshot.seq > waiting.snapshot.seq)) {
        _pendingUsage[notification.sessionId] = _PendingUsage(
          snapshot,
          notification.generation,
        );
      }
      return;
    }
    final lastSeq = handle.current.usage.lastSeq;
    if (!handle.applyUsage(snapshot, generation: notification.generation)) {
      log.debug(
        'usage.stale',
        context: {'seq': snapshot.seq, 'last_seq': lastSeq},
      );
    }
  }

  void _handleSession(AcpSession session) {
    final previous = _handles[session.id];
    final previousStatus = previous?.current.status;
    final previousTitle = previous?.title;
    final handle = _track(session);
    if (previousStatus != handle.current.status ||
        previousTitle != handle.title) {
      _publish(_current.copyWith(sessions: _summaries()));
    }
  }

  /// Регистрирует сессию, если она новая, и возвращает её handle.
  _SessionHandle _track(AcpSession session) {
    final existing = _handles[session.id];
    final reloaded = _reloading.remove(session.id);
    if (existing != null) {
      if (reloaded) {
        existing.reload(session);
      } else {
        existing.update(session);
      }
      return existing;
    }
    final handle = _SessionHandle(
      session,
      backend: _backend,
      nextQueuedPromptId: () => 'queued-${_nextQueuedPromptId++}',
      onOutcome: (outcome) {
        if (!_outcomes.isClosed) {
          _outcomes.add(outcome);
        }
      },
      onDiagnostic: _report,
      failureText: _diagnosticFailureText,
      isConnected: () => _current.connection is Connected,
      clock: clock,
      usageDeclared: () => _usageDeclared,
      ledgerDeclared: () => _ledgerDeclared,
    );
    _handles[session.id] = handle;
    _order.insert(0, session.id);
    // Снимок `load`, пришедший до регистрации сессии (D10).
    final waiting = _pendingUsage.remove(session.id);
    if (waiting != null) {
      handle.applyUsage(waiting.snapshot, generation: waiting.generation);
    }
    return handle;
  }

  /// Строки списка: открытые сессии, затем неоткрытые из `session/list`;
  /// сессия, которая есть и там и там, показывается один раз — открытой.
  List<SessionSummaryView> _summaries() => [
    for (final id in _order)
      SessionSummaryView(
        id: id,
        cwd: _handles[id]!.cwd,
        status: _handles[id]!.current.status,
        title: _handles[id]!.title ?? _listed[id]?.title,
        updatedAt: _parseTime(_listed[id]?.updatedAt),
      ),
    for (final info in _listed.values)
      if (!_handles.containsKey(info.sessionId))
        SessionSummaryView(
          id: info.sessionId,
          cwd: info.cwd,
          status: SessionStatusView.notLoaded,
          title: info.title,
          updatedAt: _parseTime(info.updatedAt),
        ),
  ];

  static DateTime? _parseTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static AgentCapabilities _capabilitiesOf(ClientConnectionState state) =>
      switch (state) {
        ClientConnectionReady(:final capabilities) => capabilities,
        _ => const AgentCapabilities(),
      };

  ConnectionView _viewFor(ClientConnectionState connectionState) {
    final reconnecting = _transition == _Transition.reconnecting;
    return switch (connectionState) {
      ClientConnectionReady() => const ConnectionView.connected(),
      ClientConnectionFailed(:final reason, :final message) =>
        ConnectionView.failed(reason: reason, message: message),
      ClientConnectionDisconnected() ||
      ClientConnectionConnecting() ||
      ClientConnectionInitializing() when reconnecting => _current.connection,
      ClientConnectionDisconnected()
          when _transition == _Transition.connecting =>
        _current.connection,
      ClientConnectionDisconnected() => const ConnectionView.disconnected(),
      ClientConnectionConnecting() ||
      ClientConnectionInitializing() => const ConnectionView.connecting(),
    };
  }

  /// Ошибка явного подключения: если ядро объявило сбой этой попытки
  /// ([_coreFailure] на поколении выше [baseGeneration]), публикуется он, с
  /// причиной ядра; иначе (резолвер не открыл транспорт) — сбой запуска с
  /// сообщением [error]. Сбой вытесненной попытки сюда не попадает: поколение
  /// её сбоя не выше [baseGeneration].
  void _publishFailure(Object error, int baseGeneration) {
    final core = _coreFailure;
    if (core != null && core.generation > baseGeneration) {
      _publishConnection(core.failure);
      return;
    }
    _publishConnection(
      ConnectionView.failed(
        reason: ConnectionFailureReason.startFailed,
        // Текст для пользователя (баннер): `describeFailure` берёт сообщение
        // известных исключений и маскирует секреты в любом тексте, в том
        // числе в `toString()` прочего объекта (D3).
        message: describeFailure(error),
      ),
    );
  }

  void _publishConnection(ConnectionView connection) {
    if (connection == _current.connection) {
      return;
    }
    _publish(_current.copyWith(connection: connection));
  }

  void _publish(WorkspaceState next) {
    if (next == _current) {
      return;
    }
    _current = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
    _restorer?.observe(next);
  }
}

/// Ожидающий регистрации сессии снимок usage с поколением соединения (D10).
final class _PendingUsage {
  const _PendingUsage(this.snapshot, this.generation);

  final UsageSnapshot snapshot;
  final int generation;
}

/// Запрос журнала usage в полёте и слитый следующий (D10).
final class _LedgerFlight {
  /// Ждущие слитые вызовы; `null` — следующего запроса нет.
  Completer<void>? queued;
  bool queuedRebuild = false;

  /// Эпоха журнала сессии и поколение соединения на момент последнего
  /// слитого вызова.
  int queuedEpoch = 0;
  int queuedGeneration = 0;
}

/// [RestoreHost] поверх закрытых операций рабочего пространства.
final class _RestoreHostAdapter implements RestoreHost {
  _RestoreHostAdapter(this._workspace);

  final DefaultClientWorkspace _workspace;

  @override
  WorkspaceState get current => _workspace.current;

  @override
  AgentCapabilities get capabilities => _workspace._capabilities;

  @override
  void rememberSessions(List<SessionRef> sessions) =>
      _workspace._rememberSessions(sessions);

  @override
  Future<SessionHandle> loadSession(SessionId id, {required String cwd}) =>
      _workspace.loadSession(id, cwd: cwd);

  @override
  void activate(SessionId id) => _workspace.activate(id);

  @override
  Future<SessionHandle> newSessionWithNotice(
    String cwd,
    String notice, {
    required SessionRestoreReason reason,
  }) => _workspace._newSessionWithNotice(cwd, notice, reason: reason);

  @override
  void report(WorkspaceDiagnostic diagnostic) => _workspace._report(diagnostic);

  @override
  String diagnosticFailureText(Object error) =>
      _workspace._diagnosticFailureText(error);
}

enum _Transition { none, connecting, reconnecting }

/// Внутренний сигнал: попытка вытеснена, пока `open` ещё шёл. Прерывает
/// `ReconnectCommand.transportFactory` до замены транспорта; наружу не
/// выходит — `reconnect` распознаёт устаревшую попытку по номеру.
final class _SupersededAttempt implements Exception {
  const _SupersededAttempt();
}

/// Связь открытой сессии с соединением агента.
enum _Link {
  /// Сессия работает в текущем соединении.
  attached,

  /// Идёт переподключение: сессия ждёт `session/load` в новом соединении.
  reattaching,

  /// Новое соединение сессию не знает.
  detached,
}

const _redactor = SecretRedactor();

final class _SessionHandle implements SessionHandle, PromptQueue {
  _SessionHandle(
    AcpSession session, {
    required AgentBackend backend,
    required String Function() nextQueuedPromptId,
    required void Function(PromptOutcome outcome) onOutcome,
    required void Function(WorkspaceDiagnostic diagnostic) onDiagnostic,
    required String Function(Object error) failureText,
    required bool Function() isConnected,
    required DateTime Function() clock,
    required bool Function() usageDeclared,
    required bool Function() ledgerDeclared,
  }) : id = session.id,
       cwd = session.cwd,
       _session = session,
       _backend = backend,
       _nextQueuedPromptId = nextQueuedPromptId,
       _onOutcome = onOutcome,
       _onDiagnostic = onDiagnostic,
       _failureText = failureText,
       _isConnected = isConnected,
       _clock = clock,
       _usageDeclared = usageDeclared,
       _ledgerDeclared = ledgerDeclared,
       _usage = UsageFold.initial(declared: usageDeclared()) {
    _projector.apply(session);
    _current = _sessionFields(
      SessionView(
        revision: 0,
        status: SessionStatusView.idle,
        usage: _usage.view,
        usageLedger: ledgerBase(),
      ),
      session,
    );
  }

  @override
  final SessionId id;

  @override
  final String cwd;

  final AgentBackend _backend;
  final String Function() _nextQueuedPromptId;
  final void Function(PromptOutcome outcome) _onOutcome;
  final void Function(WorkspaceDiagnostic diagnostic) _onDiagnostic;

  /// Текст сбоя для диагностики по базовой политике payload (D3);
  /// `ClientWorkspace._diagnosticFailureText`.
  final String Function(Object error) _failureText;

  /// Установлено ли соединение рабочего пространства.
  ///
  /// Почему: ход, прерванный обрывом, завершается сбоем и освобождает
  /// сессию; без этой проверки очередь сразу уходила бы в оборванное
  /// соединение и срывалась, хотя должна дождаться переподключения
  /// (артборд States, «Detached session»; fix к change
  /// `add-connection-and-error-states`).
  final bool Function() _isConnected;
  final _views = StreamController<SessionView>.broadcast(sync: true);
  final _projector = TranscriptProjector();

  /// Часы и память строк панели Agents (D49 Т3, Т4): первое появление вызова
  /// и защёлка итога живут столько же, сколько сессия, и переживают
  /// `reload`, чтобы реплей не сдвигал время.
  final DateTime Function() _clock;
  final _rowMemory = SubagentRowMemory();
  late SessionView _current;
  AcpSession _session;

  /// Объявил ли агент текущего соединения `usage`: читается при каждом
  /// сбросе, потому что соединение меняется быстрее сессии.
  final bool Function() _usageDeclared;

  /// Объявил ли агент текущего соединения `usageLedger` (D7, D10).
  final bool Function() _ledgerDeclared;

  /// Номер «эпохи» журнала: растёт при сбросе (смена соединения,
  /// `session/load`). Ответ запроса, отправленного в прежней эпохе, не
  /// применяется (D10, §9).
  int ledgerEpoch = 0;

  /// Свёртка снимков расхода сессии (D8, D21 Т4); в `SessionView` попадает
  /// её `view`. Не выводится из `AcpSession`, поэтому `_sessionFields` поле
  /// `usage` не трогает.
  UsageFold _usage;

  @override
  SessionView get current => _current;

  /// Заголовок сессии в ядре клиента (`session_info_update`).
  String? get title => _session.title;

  @override
  Stream<SessionView> get view => _views.stream;

  @override
  PromptQueue get queue => this;

  @override
  List<QueuedPrompt> get items => _current.queue;

  /// Связь сессии с текущим соединением агента (design D5 change
  /// `add-session-list-and-reload`).
  _Link _link = _Link.attached;

  /// Уведомление о связи сессии с агентом: потеря связи ([_Link.detached])
  /// или новая сессия вместо невосстановленной.
  NoticeItem? _notice;

  /// Сколько элементов ходов было в транскрипте, когда пришло [_notice]:
  /// уведомление стоит на этом месте, а не в конце.
  ///
  /// Почему: транскрипт пересобирается из проекции ходов при каждой
  /// публикации, и уведомление, дописанное в конец, уезжало бы под ответы,
  /// пришедшие после него.
  int _noticeAt = 0;

  /// Занята ли сессия: идёт ход (в том числе с ожидающими одобрениями) или
  /// отмена ждёт ответа агента (design D4).
  bool get _isBusy => switch (_current.status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    SessionStatusView.idle ||
    SessionStatusView.failed ||
    SessionStatusView.notLoaded ||
    SessionStatusView.detached => false,
  };

  /// Переподключение началось: промпты ставятся в очередь, она не сливается.
  void suspend() {
    if (_link == _Link.attached) {
      _link = _Link.reattaching;
    }
  }

  /// Новое соединение сессию не знает ([_Link.detached]).
  bool get isDetached => _link == _Link.detached;

  /// Сессия снова связана с агентом: очередь сливается, если сессия
  /// свободна.
  ///
  /// Из `detached` (загрузка по фокусу, D16) статус в представлении надо
  /// пересобрать: `reload` публикуется до этого вызова, пока связь ещё
  /// `detached`.
  void resume() {
    final wasDetached = _link == _Link.detached;
    _link = _Link.attached;
    _notice = null;
    if (wasDetached) {
      _publish(
        _sessionFields(
          _current.copyWith(revision: _current.revision + 1),
          _session,
        ),
      );
    }
    unawaited(_drainIfFree());
  }

  /// Новое соединение не знает сессию: статус `detached` и уведомление
  /// [text] в конце транскрипта; [reason] — типизированная причина, по
  /// которой хост строит текст на своём языке (D6 change
  /// `add-desktop-localization`, сценарий «Сессия не восстановлена после
  /// переподключения»).
  void detach(String text, SessionRestoreReason reason) {
    _link = _Link.detached;
    notify(
      NoticeItem(
        id: '${id.value}/detached',
        kind: NoticeKind.detached,
        text: text,
        reason: reason,
      ),
    );
  }

  /// Ставит [notice] в транскрипт после уже пришедших элементов ходов;
  /// элементы следующих ходов идут ниже него.
  void notify(NoticeItem notice) {
    _notice = notice;
    _noticeAt = _projector.items.length;
    _publish(
      _sessionFields(
        _current.copyWith(revision: _current.revision + 1),
        _session,
      ),
    );
  }

  @override
  Future<PromptOutcome> send(String text) async {
    if (_link == _Link.detached) {
      final error = ClientWorkspaceException(
        'Session ${id.value} is detached from the agent.',
      );
      final outcome = PromptFailed(id, error);
      // Оба места `Failed to send prompt` идут через метаданные (D3).
      _error('prompt', 'Failed to send prompt: ${_failureText(error)}');
      _onOutcome(outcome);
      return outcome;
    }
    if (_isBusy || _link == _Link.reattaching) {
      final item = QueuedPrompt(id: _nextQueuedPromptId(), text: text);
      _setQueue([..._current.queue, item]);
      return PromptQueued(id, item);
    }
    return _dispatch([ContentBlock.text(text: text)]);
  }

  @override
  Future<PromptOutcome> retry() async {
    if (!_current.canRetry || _link != _Link.attached) {
      throw ClientWorkspaceException(
        'Session ${id.value} has no failed turn to retry.',
      );
    }
    return _dispatch(_session.turns.last.prompt);
  }

  @override
  Future<PromptTurn> cancel() async {
    try {
      final turn = await _backend.cancelTurn(CancelTurnCommand(sessionId: id));
      _info('prompt', 'Cancelled prompt turn ${turn.id.value}.');
      return turn;
    } on Object catch (error) {
      _error('prompt', 'Failed to cancel prompt turn: ${_failureText(error)}');
      rethrow;
    }
  }

  @override
  Future<ApprovalRequest> respond(
    ApprovalRequestId approval,
    PermissionOptionId option,
  ) async {
    try {
      final resolved = await _backend.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: id,
          approvalId: approval,
          optionId: option,
        ),
      );
      _info(
        'approval',
        'Resolved approval ${resolved.id.value} (${resolved.status.name}).',
      );
      return resolved;
    } on Object catch (error) {
      _error(
        'approval',
        'Failed to respond to approval request: ${_failureText(error)}',
      );
      rethrow;
    }
  }

  @override
  Future<void> setConfigOption(String configId, String valueId) async {
    if (_current.configOptionInFlight != null) {
      return;
    }
    _publish(
      _current.copyWith(
        revision: _current.revision + 1,
        configOptionInFlight: configId,
      ),
    );
    try {
      await _backend.setSessionConfigOption(
        SetSessionConfigOptionCommand(
          sessionId: id,
          configId: SessionConfigId(configId),
          value: SessionConfigValueId(valueId),
        ),
      );
      _clearConfigOptionInFlight();
      _info('session', 'Set config option $configId to $valueId.');
    } on Object catch (error) {
      _clearConfigOptionInFlight();
      _error(
        'session',
        'Failed to set config option $configId: ${_failureText(error)}',
      );
      rethrow;
    }
  }

  void _clearConfigOptionInFlight() => _publish(
    _current.copyWith(
      revision: _current.revision + 1,
      configOptionInFlight: null,
    ),
  );

  void _info(String source, String message) => _onDiagnostic(
    WorkspaceDiagnostic(
      severity: DiagnosticSeverity.info,
      source: source,
      message: message,
    ),
  );

  void _error(String source, String message) => _onDiagnostic(
    WorkspaceDiagnostic(
      severity: DiagnosticSeverity.error,
      source: source,
      message: message,
    ),
  );

  @override
  QueuedPrompt? remove(String itemId) {
    final item = _current.queue.where((q) => q.id == itemId).firstOrNull;
    if (item == null) {
      return null;
    }
    _setQueue([
      for (final queued in _current.queue)
        if (queued.id != itemId) queued,
    ]);
    return item;
  }

  @override
  Future<PromptOutcome?> sendNow(String itemId) async {
    if (!_canDrain) {
      return null;
    }
    final item = remove(itemId);
    if (item == null) {
      return null;
    }
    return _dispatch([ContentBlock.text(text: item.text)]);
  }

  @override
  void clear() {
    if (_current.queue.isNotEmpty) {
      _setQueue(const []);
    }
  }

  /// Один `session/prompt`: исход публикуется в
  /// `ClientWorkspace.promptOutcomes`, затем, если сессия освободилась,
  /// уходит первый элемент очереди — и так, пока очередь не опустеет.
  ///
  /// Слив проверяет условие заново после каждого хода, а не реагирует на
  /// событие статуса: отправка из обработчика синхронного `sessionChanges`
  /// вызвала бы вложенную публикацию в тот же поток.
  Future<PromptOutcome> _dispatch(List<ContentBlock> prompt) async {
    PromptOutcome outcome;
    try {
      final turn = await _backend.sendPrompt(
        SendPromptCommand(sessionId: id, prompt: prompt),
      );
      outcome = PromptCompleted(id, turn);
      _info(
        'prompt',
        'Prompt completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
      );
    } on Object catch (error) {
      outcome = PromptFailed(id, error);
      _error('prompt', 'Failed to send prompt: ${_failureText(error)}');
    }
    _onOutcome(outcome);
    await _drainIfFree();
    return outcome;
  }

  /// Можно ли отправлять из очереди: сессия свободна, связана с агентом,
  /// и соединение установлено. После переподключения очередь сливает
  /// `resume`, когда сессия загружена.
  bool get _canDrain => !_isBusy && _link == _Link.attached && _isConnected();

  Future<void> _drainIfFree() async {
    if (!_canDrain || _current.queue.isEmpty) {
      return;
    }
    final next = _current.queue.first;
    _setQueue(_current.queue.skip(1).toList());
    await _dispatch([ContentBlock.text(text: next.text)]);
  }

  /// Каждое изменение сессии в ядре — новое представление с `revision + 1`;
  /// повтор того же снимка (`identical`) — no-op.
  void update(AcpSession session) {
    if (identical(session, _session)) {
      return;
    }
    _session = session;
    _projector.apply(session);
    _publish(
      _sessionFields(
        _current.copyWith(revision: _current.revision + 1),
        session,
      ),
    );
  }

  /// Снимок после `session/load`: проекция транскрипта строится заново,
  /// очередь и флаги представления сохраняются (design D4).
  void reload(AcpSession session) {
    // `detached`-сессия, которую загружают по фокусу (D16), держит
    // уведомление до успеха: его снимает `resume`; при ошибке загрузки оно
    // остаётся прежним.
    if (_link != _Link.detached) {
      _notice = null;
    }
    _projector.reset();
    _session = session;
    _projector.apply(session);
    // Расход и журнал сброшены в начале загрузки ([beginLoad], D10): снимок
    // `load` мог прийти и быть применён до этого обновления.
    _publish(
      _sessionFields(
        _current.copyWith(revision: _current.revision + 1),
        session,
      ),
    );
  }

  /// Начало `session/load` этой сессии: расход и журнал usage — в исходное
  /// состояние (агент считает сумму заново, D8, D10); ревизия растёт, только
  /// если вид изменился.
  void beginLoad() => resetUsage();

  /// Сброс расхода и журнала при смене соединения или `session/load`
  /// (D21 Т2, Т4; change `add-usage-ledger`, D10); ревизия растёт, только если
  /// вид изменился.
  void resetUsage() {
    _usage = UsageFold.initial(declared: _usageDeclared());
    ledgerEpoch++;
    final next = _current.copyWith(
      usage: _usage.view,
      usageLedger: ledgerBase(),
    );
    if (next == _current) {
      return;
    }
    _publish(next.copyWith(revision: _current.revision + 1));
  }

  /// Состояние журнала без запросов: `idle` или `unavailable` по объявлению
  /// соединения.
  UsageLedgerState ledgerBase() => _ledgerDeclared()
      ? const UsageLedgerState.idle()
      : const UsageLedgerState.unavailable();

  /// Журнал, показанный последним (`loaded`, а при `loading` и `failed` —
  /// предыдущий), если был.
  UsageLedgerView? get ledgerView => switch (_current.usageLedger) {
    UsageLedgerLoaded(:final view) => view,
    UsageLedgerLoading(:final previous) => previous,
    UsageLedgerFailed(:final previous) => previous,
    _ => null,
  };

  /// Публикует [state] журнала одной ревизией.
  void setLedger(UsageLedgerState state) {
    if (state == _current.usageLedger) {
      return;
    }
    _publish(
      _current.copyWith(revision: _current.revision + 1, usageLedger: state),
    );
  }

  /// Применяет [snapshot] соединения поколения [generation]; `false` —
  /// дубль или опоздание, ревизия не растёт (D7, VIEW-6).
  bool applyUsage(UsageSnapshot snapshot, {required int generation}) {
    // Момент применения — по часам рабочего пространства (D9, «Часы»); у
    // снимка, отложенного до регистрации сессии, это время применения.
    final next = _usage.apply(
      snapshot,
      generation: generation,
      receivedAt: _clock(),
    );
    if (next == null) {
      return false;
    }
    _usage = next;
    _publish(
      _current.copyWith(revision: _current.revision + 1, usage: next.view),
    );
    return true;
  }

  /// [items] с [notice] на месте [_noticeAt]; проекция могла стать короче
  /// (например, после сброса), тогда уведомление — в конце.
  List<TranscriptItem> _withNotice(
    List<TranscriptItem> items,
    NoticeItem notice,
  ) {
    final at = _noticeAt.clamp(0, items.length);
    return List.unmodifiable([...items.take(at), notice, ...items.skip(at)]);
  }

  /// Поля представления, которые выводятся из снимка сессии ядра.
  SessionView _sessionFields(SessionView view, AcpSession session) {
    final status = _link == _Link.detached
        ? SessionStatusView.detached
        : SessionStatusView.of(session.status);
    final plan = planOf(session);
    return view.copyWith(
      status: status,
      canRetry: _canRetry(session, status),
      transcript: switch (_notice) {
        null => _projector.items,
        final notice => _withNotice(_projector.items, notice),
      },
      // Строки по проекции без уведомления: оно не вызов (D49 Т2).
      subagents: subagentRowsOf(
        session: session,
        transcript: _projector.items,
        plan: plan,
        memory: _rowMemory,
        clock: _clock,
      ),
      configOptions: [
        for (final option in session.configOptions ?? const [])
          ConfigOptionView.of(option),
      ],
      agentCommands: [
        for (final command in session.availableCommands)
          AgentCommandView.of(command),
      ],
      pendingApprovals: pendingApprovalViews(session),
      approvalWaits: approvalWaitViews(session),
      plan: plan,
    );
  }

  /// Правила повтора — spec `acp-client-kit` «Повтор сорвавшегося хода».
  bool _canRetry(AcpSession session, SessionStatusView status) {
    if (_link != _Link.attached ||
        status == SessionStatusView.running ||
        status == SessionStatusView.cancelling ||
        session.turns.isEmpty) {
      return false;
    }
    final last = session.turns.last;
    if (last.status != PromptTurnStatus.failed) {
      return false;
    }
    return switch (last.failure) {
      ConnectionLostPromptFailure() => false,
      AgentPromptFailure(retryable: false) => false,
      _ => true,
    };
  }

  void _setQueue(List<QueuedPrompt> queue) => _publish(
    _current.copyWith(
      revision: _current.revision + 1,
      queue: List.unmodifiable(queue),
    ),
  );

  void _publish(SessionView next) {
    _current = next;
    if (!_views.isClosed) {
      _views.add(next);
    }
  }

  Future<void> close() => _views.close();
}
