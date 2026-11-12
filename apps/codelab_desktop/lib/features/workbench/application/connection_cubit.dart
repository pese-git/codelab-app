import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        Connecting,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        EmbeddedProfile,
        ProfileSecretSource,
        ProfileTokenRef,
        Reconnecting,
        SessionStatusView,
        StdioProfile,
        UnsupportedTokenRef,
        WebSocketProfile,
        WorkspaceState,
        describeFailure,
        describeConnectFailureByToken,
        secretMissingWarning;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabConnectionStatus;

import '../../../app/provider_setup_offer.dart';
import '../../settings/application/connection_commands.dart';
import '../../settings/application/default_profile_resolver.dart';
import '../../settings/application/embedded_profile.dart';
import '../../settings/application/profile_view.dart'
    show profileOrigin, profileTitle;
import 'active_session_cubit.dart';
import 'project_paths.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

typedef CodeLabStdioTransportFactory =
    AcpTransport Function(StdioAcpTransportConfig config);

typedef CodeLabWebSocketTransportFactory =
    AcpTransport Function(WebSocketAcpTransportConfig config);

/// stdio-профиль по встроенному в app описанию агента.
///
/// Почему: фасад `CodeLabShellCubit` без графа cherrypick (тесты
/// `widget_test.dart`) принимает прежний `StdioAcpAgentProfile`, а окно
/// подключается по `ConnectionProfile` (design.md change
/// `add-app-settings-shell`, D6). Процесс запускается в папке проекта, как
/// раньше при включённом переключателе «Run agent from project directory».
ConnectionProfile stdioConnectionProfileOf(
  StdioAcpAgentProfile profile, {
  String id = 'codelab_desktop.stdio',
}) => StdioProfile(
  id: id,
  label: profile.name,
  command: profile.command,
  args: profile.args,
  env: profile.env,
  runInProjectDirectory: true,
);

/// Метка сбоя попытки встроенного агента: «не настроен провайдер».
///
/// Почему отдельный объект: баннер предлагает «Add provider», а после записи
/// конфига окно должно переподключить встроенного агента, но только если с
/// момента сбоя не началась другая попытка (AGENTS.md §9; design.md change
/// `add-provider-setup-ui`, D21, D26). Непрозрачность и сравнение по
/// тождеству (`identical`) заменяют номер попытки, который наружу не
/// выходит.
///
/// Как использовать: `ConnectionCubit` создаёт метку при сбое попытки
/// встроенного агента с истинным признаком и публикует в
/// `WindowConnectionState.providerSetupNotice`; UI передаёт её обратно в
/// `ConnectionCubit.connectAfterProviderSetup`. [cwd] — папка проекта сбоя,
/// по ней мастер решает, доступно ли «This project only».
final class ProviderSetupNotice {
  const ProviderSetupNotice._(this.cwd);

  final String cwd;

  @override
  String toString() => 'ProviderSetupNotice';
}

/// Диалог подтверждения «Restart agent» (D22): что будет прервано.
///
/// Почему: перезапуск обрывает ходы, и решение «прерывать ли» принадлежит
/// пользователю, а какие сессии в работе — знает `ConnectionCubit`, а не
/// виджет (корневой `AGENTS.md` §10).
///
/// Как использовать: виджет показывает [message] и возвращает ответ
/// `ConnectionCubit.confirmRestart` / `cancelRestart`.
final class RestartConfirmation {
  const RestartConfirmation({required this.title, required this.sessions});

  /// Название профиля, который будет перезапущен.
  final String title;

  /// Названия сессий в ходе, ждущих одобрения или отменяемых.
  final List<String> sessions;

  /// Текст диалога из спецификации app-settings (D22).
  String get message {
    final n = sessions.length;
    return 'Restart $title? This interrupts $n running '
        '${n == 1 ? 'session' : 'sessions'}: ${sessions.join(', ')}. '
        'Queued prompts stay.';
  }

  @override
  bool operator ==(Object other) =>
      other is RestartConfirmation &&
      other.title == title &&
      _sameList(other.sessions, sessions);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(sessions));

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Текст отказа: папки сессии или проекта нет на диске (D2).
///
/// Почему отдельная функция: тот же текст нужен `SessionsCubit` для сессии
/// исчезнувшей папки (spec agent-workbench-ui «Исчезнувшая папка сессии»);
/// ручного Connect больше нет, поэтому «connect again» из текста убран.
String projectFolderMissingMessage(String path) =>
    'Project folder not found: $path. '
    'Choose an existing folder with Open folder….';

/// Профиль текущего окна и статус соединения.
///
/// Почему: раньше состояние держало черновик формы (тип, команда, адрес,
/// токен); теперь подключение идёт по профилю, а форму заменил диалог
/// «Add connection profile» (design.md change `add-app-settings-shell`, D6).
/// Состояния — статус и профиль, а не набор независимых флагов (AGENTS.md §8).
///
/// Для чего: два профиля окна раздельно (design.md change
/// `require-project-folder`, D18): [profile] — выбранный («Selected», для
/// следующего старта агента; «Use»), [runningProfile] — профиль работающего
/// агента («Current»), `null` до первого принятого старта. Подписи бейджа и
/// доступность Files берутся по [shownProfile]: работающий агент, а до
/// первого старта — выбранный.
final class WindowConnectionState {
  const WindowConnectionState({
    required this.connectionStatus,
    required this.profile,
    this.runningProfile,
    this.connectionMessage,
    this.providerSetupNotice,
    this.failureRepeat = 0,
    this.pendingRestart,
  });

  final CodeLabConnectionStatus connectionStatus;

  /// Выбранный профиль окна (D18).
  final ConnectionProfile profile;

  /// Профиль последнего принятого старта; `null` — агент ещё не стартовал.
  final ConnectionProfile? runningProfile;

  /// Профиль для подписей и Files: работающий агент или, пока его не было,
  /// выбранный профиль.
  ConnectionProfile get shownProfile => runningProfile ?? profile;

  /// Метка последнего сбоя встроенного агента «не настроен провайдер»;
  /// `null` — сбой другой или попытки были позже (D26).
  final ProviderSetupNotice? providerSetupNotice;

  /// Причина из `ConnectionLost` или `ConnectionFailed` kit — текст баннера
  /// соединения (design D6 change `add-connection-and-error-states`);
  /// `null` в остальных состояниях.
  final String? connectionMessage;

  /// Сколько раз подряд повторился тот же сбой старта (`Failed again (n)`,
  /// D13); `0` — сбой первый или его нет.
  final int failureRepeat;

  /// Диалог «Restart agent» ждёт ответа пользователя (D22); `null` — нет.
  final RestartConfirmation? pendingRestart;

  /// Тип подключения для подписи («stdio», «WebSocket», «Embedded agent»).
  String get transportLabel => switch (shownProfile) {
    StdioProfile() => 'stdio',
    WebSocketProfile() => 'WebSocket',
    EmbeddedProfile() => 'Embedded agent',
  };

  String get selectedProfileLabel => profileTitle(shownProfile);

  /// Деталь для подписи и диагностики: команда stdio без аргументов или
  /// `scheme://host:port` WebSocket без userinfo, пути и query — аргументы и
  /// адрес могут нести токен (D17, находка L1 ревью итерации 2).
  String get selectedConnectionDetail => _detailOf(shownProfile);

  static String _detailOf(ConnectionProfile profile) => switch (profile) {
    StdioProfile(:final command) => command,
    WebSocketProfile(:final uri) => profileOrigin(uri),
    EmbeddedProfile() => embeddedConnectionDetail,
  };

  /// Деталь встроенного подключения: пакет и профиль хоста (D9).
  static const embeddedConnectionDetail =
      'codelab_embedded ($embeddedHostProfile)';

  WindowConnectionState _copyWith({
    CodeLabConnectionStatus? connectionStatus,
    ConnectionProfile? profile,
    ConnectionProfile? runningProfile,
    Object? connectionMessage = _unset,
    Object? providerSetupNotice = _unset,
    int? failureRepeat,
    Object? pendingRestart = _unset,
  }) => WindowConnectionState(
    connectionStatus: connectionStatus ?? this.connectionStatus,
    profile: profile ?? this.profile,
    runningProfile: runningProfile ?? this.runningProfile,
    // `null` здесь — «причины нет», а не «не менять».
    connectionMessage: identical(connectionMessage, _unset)
        ? this.connectionMessage
        : connectionMessage as String?,
    providerSetupNotice: identical(providerSetupNotice, _unset)
        ? this.providerSetupNotice
        : providerSetupNotice as ProviderSetupNotice?,
    failureRepeat: failureRepeat ?? this.failureRepeat,
    pendingRestart: identical(pendingRestart, _unset)
        ? this.pendingRestart
        : pendingRestart as RestartConfirmation?,
  );

  static const Object _unset = Object();
}

/// Подключение окна к агенту по профилю.
///
/// Почему: старт, перезапуск, выбор транспорта по профилю — в
/// `codelab_client_core` (`ClientWorkspace`, `ConfigTransportResolver`); в app
/// остаются профили окна и статус в модели `codelab_ui` (таблица переноса
/// `09-10`; design D10 change `extract-acp-client-kit`; design.md change
/// `add-app-settings-shell`, D6). Ручного Connect нет: агент стартует по
/// триггерам D13 (design.md change `require-project-folder`, D11–D13, D18).
///
/// Для чего: владелец профилей окна, статуса соединения, намерения старта
/// (функция-повтор для «Retry»), счётчика повторов сбоя и диалога перезапуска
/// D22; единственная реализация [ConnectionCommands] — через неё страница
/// «Connection» выбирает профиль и перезапускает агента, не дублируя номер
/// попытки и диагностику. Сообщает о неожиданной потере соединения части
/// показываемой сессии.
///
/// Как использовать: создаётся после [ActiveSessionCubit] и [SettingsCubit]
/// (`CodeLabShellParts`). [startAgent] зовут триггеры (выбор проекта, «New
/// session», фокус на сессии, «Retry»); [startOnLaunch] зовёт app после
/// первого кадра (D19). [use] выбирает профиль для следующего старта и агента
/// не трогает; [restart] — единственный перезапуск (D22). Токен профиля —
/// только ссылка: значение читает резолвер транспорта в момент открытия (D13,
/// D15).
final class ConnectionCubit extends ShellPartCubit<WindowConnectionState>
    implements ConnectionCommands {
  ConnectionCubit({
    required super.changes,
    required ConnectionProfile initialProfile,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
    required SettingsCubit settings,
    required ActiveSessionCubit activeSession,
    DefaultProfileResolver? defaultProfiles,
    Logger? eventLogger,
    ProfileSecretSource? tokenSecrets,
    ProviderSetupOffer? providerSetupOffer,
  }) : _tokenSecrets = tokenSecrets,
       _setupOffer = providerSetupOffer,
       _workspace = workspace,
       _diagnostics = diagnostics,
       _settings = settings,
       _activeSession = activeSession,
       _eventLogger = eventLogger,
       super(
         WindowConnectionState(
           connectionStatus: CodeLabConnectionStatus.disconnected,
           profile: initialProfile,
         ),
       ) {
    _workspaceSubscription = _workspace.state.listen(_handleWorkspaceChange);
    if (defaultProfiles == null) {
      // Без выбора по умолчанию (фасад без графа) профиль окна — начальный.
      _defaultResolved = true;
      _defaultLoaded = Future<void>.value();
    } else {
      _defaultLoaded = _loadDefault(defaultProfiles);
    }
  }

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final SettingsCubit _settings;
  final ActiveSessionCubit _activeSession;
  final Logger? _eventLogger;

  /// Источник токенов профилей: только чтобы предупредить о пустом секрете
  /// до подключения (D13); значение не сохраняется.
  final ProfileSecretSource? _tokenSecrets;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Признак «нужен провайдер», который выставил резолвер встроенного агента
  /// (D26); читается синхронно в обработчике сбоя своей попытки.
  final ProviderSetupOffer? _setupOffer;

  /// Метка текущего сбоя; источник правды для [connectAfterProviderSetup],
  /// `state.providerSetupNotice` её отражает. Любая новая попытка сбрасывает.
  ProviderSetupNotice? _notice;

  /// Профиль по умолчанию уже подставлен (или не нужен): старт не ждёт.
  late final Future<void> _defaultLoaded;
  var _defaultResolved = false;

  /// Пользователь уже выбрал профиль окна: позднее чтение профиля по
  /// умолчанию его не заменяет (AGENTS.md §9, поздний результат).
  var _profileChosen = false;

  /// Профиль последней попытки, которую workspace принял. До неё `null`.
  ConnectionProfile? _accepted;
  final _restartTargets = StreamController<ConnectionProfile?>.broadcast();
  (ConnectionProfile?, ConnectionProfile?)? _announced;

  /// Выбранный профиль («Selected», D18): им стартует агент и перезапускается.
  @override
  ConnectionProfile? get restartTarget => state.profile;

  /// Профиль работающего агента («Current»); `null` — агента не было.
  @override
  ConnectionProfile? get runningProfile => _accepted;

  @override
  Stream<ConnectionProfile?> get restartTargets => _restartTargets.stream;

  void _announceTarget() {
    final pair = (state.profile, _accepted);
    if (pair != _announced && !_restartTargets.isClosed) {
      _announced = pair;
      _restartTargets.add(state.profile);
    }
  }

  /// Номер последней начатой попытки старта или перезапуска. Попытка, которую
  /// вытеснила более новая («Restart agent» во время старта, Q25), не вправе
  /// менять статус: иначе её отмена мелькнула бы `failed` посреди успешного
  /// подключения (`AGENTS.md` §9; design.md change `add-embedded-agent-mode`,
  /// D6). Он же — поколение соединения для намерений `SessionsCubit` (D17):
  /// ответы старого поколения фокус не меняют.
  var _attempt = 0;

  /// Поколение соединения: растёт с каждой начатой попыткой (D17).
  int get generation => _attempt;

  /// Причина отказа по токену текущей попытки (`the agent rejected the token
  /// (HTTP 401)`) вместо текста kit «Failed to start ACP transport.»; `null` —
  /// отказа по токену нет. Одно поле вместо флага: текст и есть признак.
  /// Живёт, пока workspace остаётся в `ConnectionFailed` этой попытки; новая
  /// попытка его сбрасывает.
  String? _tokenRejection;

  /// Номер последнего вызова старта/перезапуска до обращения к kit: им
  /// отбрасываются устаревшие ожидания (проверка папки). Отказ намерения
  /// [_attempt] не меняет.
  var _intent = 0;

  /// Идущая попытка старта или перезапуска (single-flight на стороне app:
  /// параллельные триггеры ждут её, D13, D17). Kit держит такой же `Future`
  /// (`ensureAgent`, D15), но app проверяет папку и секрет до обращения к
  /// kit, и без своего `Future` два триггера успели бы пройти эти проверки.
  Future<void>? _inFlight;

  /// Функция-повтор намерения, вызвавшего неудавшийся старт (D13, п. 4);
  /// `null` — после успеха и до первого старта.
  Future<void> Function()? _retry;

  /// Ключ последнего сбоя старта «профиль|корень|текст»: одинаковый сбой не
  /// плодит записи в диагностике (D13).
  String? _lastFailureKey;

  /// Выбирает [profile] профилем окна для следующего старта (D18 «Use»).
  ///
  /// Агента не трогает и профиль по умолчанию не меняет: работающий агент
  /// остаётся прежним до «Restart agent» (D22).
  @override
  Future<void> use(ConnectionProfile profile) async {
    _profileChosen = true;
    emit(state._copyWith(profile: profile));
    _announceTarget();
  }

  /// Корень процесса для «Restart agent» (D18, Q27): папка сессии в фокусе,
  /// иначе выбранный проект, иначе прежний корень. Корень диска берётся только
  /// без других кандидатов. `null` — перезапускать некуда.
  @override
  String? get restartDirectory {
    final workspace = _workspace.current;
    final focus =
        _activeSession.state.sessionId ?? workspace.activeSessionId?.value;
    String? sessionCwd;
    if (focus != null) {
      for (final summary in workspace.sessions) {
        if (summary.id.value == focus && summary.cwd.trim().isNotEmpty) {
          sessionCwd = summary.cwd;
        }
      }
    }
    final project = _settings.projectDirectory;
    for (final candidate in [
      if (sessionCwd != null && !isFilesystemRoot(sessionCwd)) sessionCwd,
      project,
      workspace.agentDirectory,
      sessionCwd,
    ]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  /// Запускает агента выбранным профилем в [directory], если он не работает
  /// (триггеры D13). Работающий агент — no-op; идущая попытка — ожидание её
  /// (single-flight, D17).
  ///
  /// [retry] — намерение для «Retry» после сбоя; по умолчанию — повтор этого
  /// же старта. Ошибки наружу не бросаются: итог — `connectionStatus`.
  Future<void> startAgent(String directory, {Future<void> Function()? retry}) {
    final connection = _workspace.current.connection;
    if (connection is Connected) {
      return Future<void>.value();
    }
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    _retry = retry ?? () => startAgent(directory);
    return _track(_run(directory, restart: false));
  }

  /// «Retry» экрана и баннера (D13, п. 4): повторяет намерение, вызвавшее
  /// старт; без него (баннер `lost`) — новый старт с прежним корнем процесса.
  Future<void> retryStart() {
    final retry = _retry;
    if (retry != null) {
      return retry();
    }
    final directory =
        _workspace.current.agentDirectory ?? _settings.projectDirectory;
    if (directory == null) {
      return Future<void>.value();
    }
    return startAgent(directory);
  }

  /// Триггер запуска (D19): после восстановления проекта стартует агента в его
  /// папке; без проекта агент не стартует. App зовёт его один раз после
  /// первого кадра; тесты без виджета приложения — явно.
  Future<void> startOnLaunch() async {
    // Та же функция ожидания, что у «New session» (D3): не дольше
    // `projectRestoreTimeout`, зависшее чтение снимка не держит триггер вечно.
    final restored = await _settings.awaitProject();
    if (!_defaultResolved) {
      // Чтение профиля по умолчанию тоже ограничено тем же сроком.
      await _defaultLoaded.timeout(
        _settings.projectRestoreTimeout,
        onTimeout: () {},
      );
    }
    // Пока ждали профиль, пользователь мог выбрать другой проект и его старт
    // мог не удаться: стартовать в восстановленной папке уже нельзя.
    if (isClosed ||
        restored == null ||
        _settings.projectDirectory != restored) {
      return;
    }
    if (_workspace.current.connection is! Connected) {
      _eventLogger?.info(
        'connection.start_on_launch',
        context: {'profile_id': state.profile.id},
      );
    }
    await startAgent(restored);
  }

  /// «Restart agent» (D22): единственный перезапуск. При ходе, ждущем
  /// одобрения или отмене, сначала [WindowConnectionState.pendingRestart] и
  /// ответ пользователя; во время старта (Q25) и в покое — сразу.
  @override
  Future<void> restart() async {
    if (state.pendingRestart != null) {
      // Пока диалог открыт, другие перезапуски игнорируются (droppable,
      // `concurrency.md` §62).
      return;
    }
    // Как «New session» и триггер запуска (D3): пока проект восстанавливается,
    // ждём его не дольше `projectRestoreTimeout` (spec «Ожидание
    // восстановления»).
    if (restartDirectory == null && !_settings.projectRestoreFinished) {
      await _settings.awaitProject();
      if (isClosed) return;
    }
    if (restartDirectory == null) {
      // Корня нет: ни проекта, ни прежнего корня. Событие без пути.
      _eventLogger?.info(
        'connection.connect_rejected',
        context: {'reason': 'no_project', 'profile_id': state.profile.id},
      );
      _diagnostics.record(
        'Open a project before restarting the agent: choose a folder with '
        'Open folder….',
        severity: DiagnosticSeverity.warning,
        source: 'project',
      );
      return;
    }
    final working = _runningSessionTitles();
    final connection = _workspace.current.connection;
    if (working.isNotEmpty &&
        connection is! Connecting &&
        connection is! Reconnecting) {
      emit(
        state._copyWith(
          pendingRestart: RestartConfirmation(
            title: profileTitle(state.profile),
            sessions: working,
          ),
        ),
      );
      return;
    }
    await _restartNow(interrupted: 0);
  }

  /// Пользователь подтвердил диалог D22: перезапуск без `session/cancel`,
  /// очередь сохранена.
  Future<void> confirmRestart() async {
    final pending = state.pendingRestart;
    if (pending == null) {
      return;
    }
    emit(state._copyWith(pendingRestart: null));
    await _restartNow(interrupted: pending.sessions.length);
  }

  /// «Cancel» диалога D22: ничего не меняется.
  void cancelRestart() {
    if (state.pendingRestart != null) {
      emit(state._copyWith(pendingRestart: null));
    }
  }

  /// Названия сессий окна в ходе, ждущих одобрения или отмены.
  List<String> _runningSessionTitles() => [
    for (final summary in _workspace.current.sessions)
      if (summary.status == SessionStatusView.running ||
          summary.status == SessionStatusView.cancelling)
        summary.title?.trim().isNotEmpty ?? false
            ? summary.title!.trim()
            : summary.id.value,
  ];

  Future<void> _restartNow({required int interrupted}) {
    final directory = restartDirectory;
    if (directory == null) {
      return Future<void>.value();
    }
    final reason = switch (state.connectionStatus) {
      CodeLabConnectionStatus.failed ||
      CodeLabConnectionStatus.lost => 'failure',
      _ when _accepted != null && _accepted != state.profile =>
        'profile_changed',
      _ => 'manual',
    };
    // Без пути (AGENTS.md §16): причина и число прерванных сессий.
    _eventLogger?.info(
      'connection.restart',
      context: {'reason': reason, 'interrupted': interrupted},
    );
    _retry = () => startAgent(directory);
    return _track(_run(directory, restart: true));
  }

  /// Запоминает идущую попытку и снимает её по завершению.
  ///
  /// Почему не `whenComplete`: он создал бы производный `Future`, ошибка
  /// которого осталась бы необработанной; `_run` ошибок не бросает, но
  /// паттерн kit (`_begin`) надёжнее при будущих правках.
  Future<void> _track(Future<void> attempt) {
    _inFlight = attempt;
    unawaited(
      attempt
          .then<void>((_) {}, onError: (Object _) {})
          .then<void>(
            (_) => identical(_inFlight, attempt) ? _inFlight = null : null,
          ),
    );
    return attempt;
  }

  /// Тело старта и перезапуска: проверки до kit, затем `ensureAgent` или
  /// `reconnect(agentDirectory:)`. Исход читается из состояния, ошибок нет.
  Future<void> _run(String directory, {required bool restart}) async {
    // Намерение, а не попытка: номер попытки `_attempt` растёт только когда
    // проверки до `ClientWorkspace` пройдены. Отказ B (пустая команда, нет
    // папки) тогда не вытесняет попытку A, которая уже в kit.
    final intent = ++_intent;
    _dropSetupNotice();
    if (!_defaultResolved) {
      // Профиль по умолчанию ещё читается: стартуем уже им, а не начальным.
      // Ожидание ограничено тем же сроком, что у `startOnLaunch`: зависшее
      // чтение не должно навсегда занять `_inFlight` (все следующие старты
      // вернули бы эту же попытку).
      await _defaultLoaded.timeout(
        _settings.projectRestoreTimeout,
        onTimeout: () {},
      );
      if (isClosed || intent != _intent) return;
    }
    final target = state.profile;
    _profileChosen = true;
    final detail = WindowConnectionState._detailOf(target);
    final action = restart ? 'reconnecting' : 'connecting';
    if (!_validate(target, action: action)) {
      _rejectBeforeConnect();
      return;
    }
    emit(
      state._copyWith(
        connectionStatus: restart
            ? CodeLabConnectionStatus.reconnecting
            : CodeLabConnectionStatus.connecting,
      ),
    );
    if (await _failIfProjectDirectoryMissing(target, intent, directory)) {
      return;
    }
    await _warnIfSecretMissing(target);
    if (isClosed || intent != _intent) {
      return;
    }
    // Все проверки пройдены: с этого места попытка принадлежит kit.
    final attempt = ++_attempt;
    // Текст отказа прошлой попытки к новой не относится: kit может отклонить
    // её до `connecting` (`_rejectUnsupported`).
    _tokenRejection = null;
    _announceTarget();
    _warnIfTokenUnsupported(target);
    _diagnostics.record(
      _byType(
        target,
        stdio: restart
            ? 'Reconnecting stdio ACP agent: $detail.'
            : 'Starting stdio ACP agent: $detail.',
        webSocket: restart
            ? 'Reconnecting WebSocket ACP agent: $detail.'
            : 'Connecting WebSocket ACP agent: $detail.',
        embedded: restart
            ? 'Reconnecting embedded ACP agent: $detail.'
            : 'Starting embedded ACP agent: $detail.',
      ),
      source: 'transport',
    );

    try {
      if (restart) {
        await _workspace.reconnect(profile: target, agentDirectory: directory);
      } else {
        await _workspace.ensureAgent(directory, profile: target);
      }
      // Вытесненная попытка завершается нормально и ничего не публикует
      // (контракт `ClientWorkspace`): итог — у новой попытки.
      if (isClosed || attempt != _attempt) {
        return;
      }
      _accepted = target;
      _lastFailureKey = null;
      _announceTarget();
      emit(
        state._copyWith(
          runningProfile: target,
          failureRepeat: 0,
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      if (_workspace.current.connection is Connected) {
        _retry = null;
      }
      _diagnostics.record(
        _byType(
          target,
          stdio: restart
              ? 'Stdio ACP agent reconnected: $detail.'
              : 'Stdio ACP agent started: $detail.',
          webSocket: restart
              ? 'WebSocket ACP agent reconnected: $detail.'
              : 'WebSocket ACP agent connected: $detail.',
          embedded: restart
              ? 'Embedded ACP agent reconnected: $detail.'
              : 'Embedded ACP agent started: $detail.',
        ),
        source: 'transport',
      );
    } on UnsupportedProtocolVersionException catch (error) {
      if (isClosed) return;
      if (attempt != _attempt) {
        _recordStaleAttempt(error);
        return;
      }
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        'Incompatible ACP agent: ${error.message}',
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    } on Object catch (error) {
      if (isClosed) return;
      // Текст отказа по токену строится до проверки номера попытки:
      // чтение источника токена асинхронно, а после `await` вытесненная
      // попытка уже не вправе менять состояние (§9).
      final rejection = await _tokenRejectionText(error, target);
      if (isClosed) return;
      if (attempt != _attempt) {
        _recordStaleAttempt(error);
        return;
      }
      final message =
          rejection ??
          _byType(
            target,
            stdio: restart
                ? 'Failed to reconnect stdio ACP agent: ${describeFailure(error)}'
                : 'Failed to start stdio ACP agent: $error',
            webSocket: restart
                ? 'Failed to reconnect WebSocket ACP agent: ${describeFailure(error)}'
                : 'Failed to connect WebSocket ACP agent: $error',
            embedded: restart
                ? 'Failed to reconnect embedded ACP agent: ${describeFailure(error)}'
                : 'Failed to start embedded ACP agent: $error',
          );
      // Одинаковый сбой старта не плодит записи (D13): счётчик растёт в
      // состоянии экрана, в журнал уходит debug-событие. Перезапуск пишет
      // каждый сбой, как прежний reconnect.
      final key = '${target.id}|$directory|$message';
      final repeat = !restart && key == _lastFailureKey
          ? state.failureRepeat + 1
          : 0;
      _lastFailureKey = restart ? null : key;
      _publishFailure(
        rejection,
        profile: target,
        intent: intent,
        repeat: repeat,
      );
      if (!restart) {
        _eventLogger?.debug(
          'connection.start_failed',
          context: {'profile_id': target.id, 'repeat': repeat},
        );
      }
      if (repeat == 0) {
        _diagnostics.record(
          message,
          severity: DiagnosticSeverity.error,
          source: 'transport',
        );
      }
    }
  }

  /// Повтор после записи провайдера из баннера встроенного агента, если с
  /// момента сбоя [notice] не началась другая попытка (D21, D26, D13 п. 4).
  ///
  /// Почему сравнение по тождеству: диалог мастера модальный, но попытку могут
  /// начать без пользователя, а подключение к чужому профилю нельзя перебивать
  /// встроенным агентом (AGENTS.md §9). Новая попытка метку сбрасывает; тогда
  /// пишется `provider_wizard.reconnect_skipped` и ничего не делается.
  Future<void> connectAfterProviderSetup(ProviderSetupNotice notice) async {
    if (isClosed || !identical(_notice, notice)) {
      _eventLogger?.debug('provider_wizard.reconnect_skipped');
      return;
    }
    _eventLogger?.info('provider_wizard.reconnect');
    await retryStart();
  }

  var _setupActionOpen = false;

  /// Выполняет [action] мастера из баннера не более одного раза одновременно:
  /// второй клик, пока первый открывает мастер, игнорируется (владелец —
  /// Cubit, а не виджет; D26).
  Future<void> runProviderSetup(Future<void> Function() action) async {
    if (_setupActionOpen) {
      return;
    }
    _setupActionOpen = true;
    try {
      await action();
    } finally {
      _setupActionOpen = false;
    }
  }

  /// Сбрасывает метку «нужен провайдер»: началась новая попытка (D26).
  void _dropSetupNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    emit(state._copyWith(providerSetupNotice: null));
  }

  @override
  Future<void> close() async {
    await _workspaceSubscription.cancel();
    await _restartTargets.close();
    return super.close();
  }

  /// Подставляет профиль по умолчанию, пока пользователь ничего не выбрал.
  Future<void> _loadDefault(DefaultProfileResolver resolver) async {
    final resolved = await resolver.resolve();
    _defaultResolved = true;
    if (isClosed || _profileChosen) {
      return;
    }
    emit(state._copyWith(profile: resolved));
  }

  /// Держит причину сбоя для баннера и реагирует на неожиданную потерю
  /// соединения, пока оно считается установленным: исход явного
  /// [connect]/[reconnect] сообщают сами эти методы, второй записи здесь
  /// быть не должно. Запись `Connection to ACP agent lost` даёт диагностика
  /// kit; потерю kit публикует как `ConnectionLost` (design D1 change
  /// `add-connection-and-error-states`).
  void _handleWorkspaceChange(WorkspaceState workspace) {
    // Отказ по токену живёт только пока kit в `ConnectionFailed`: любой иной
    // статус (новая попытка, соединение) сбрасывает его.
    if (workspace.connection is! ConnectionFailed) {
      _tokenRejection = null;
      _dropSetupNotice();
    }
    final message = switch (workspace.connection) {
      ConnectionFailed() when _tokenRejection != null => _tokenRejection,
      ConnectionLost(:final message) ||
      ConnectionFailed(:final message) => message,
      _ => null,
    };
    final lost =
        workspace.connection is ConnectionLost &&
        state.connectionStatus == CodeLabConnectionStatus.connected;
    if (message == state.connectionMessage && !lost) {
      return;
    }
    batch(() {
      emit(
        state._copyWith(
          connectionMessage: message,
          connectionStatus: lost ? CodeLabConnectionStatus.lost : null,
        ),
      );
      if (lost) {
        _activeSession.resetAfterConnectionLoss();
      }
    });
  }

  /// Текст отказа 401/403 для [profile] или `null`, если ошибка другая.
  ///
  /// Почему: kit отдаёт `ConnectionFailed.message` без причины, и баннер
  /// показывал бы «Failed to start ACP transport.» (design.md change
  /// `add-app-settings-shell`, D12). `tokenSent` берётся у того же
  /// [ProfileSecretSource], которым composition root открывает транспорт;
  /// значение токена читается и отбрасывается внутри [describeConnectFailureByToken].
  Future<String?> _tokenRejectionText(
    Object error,
    ConnectionProfile profile,
  ) async {
    final text = await describeConnectFailureByToken(
      error,
      profile,
      _tokenSecrets,
    );
    if (text == null || text.isEmpty) {
      return text;
    }
    // Kit отдаёт строчный текст для CLI; остальные тексты баннера — с
    // заглавной и точкой, поэтому app приводит его к тому же виду.
    return '${text[0].toUpperCase()}${text.substring(1)}.';
  }

  String? _kitMessage(WorkspaceState workspace) =>
      switch (workspace.connection) {
        ConnectionLost(:final message) ||
        ConnectionFailed(:final message) => message,
        _ => null,
      };

  /// Ставит `failed` и запоминает [rejection]: баннер показывает его, а не
  /// текст kit, который `_handleWorkspaceChange` уже мог записать (kit
  /// публикует `ConnectionFailed` до того, как `connect` бросит ошибку).
  void _publishFailure(
    String? rejection, {
    required ConnectionProfile profile,
    required int intent,
    int repeat = 0,
  }) {
    _tokenRejection = rejection;
    // Метка принадлежит этой попытке встроенного агента: порт читается
    // синхронно, пока его значение не перезаписала более поздняя попытка
    // резолвера (D26). Отказ по токену к встроенному агенту не относится.
    // Намерение могло смениться, пока попытка ждала предварительные `await`
    // (проверка папки): тогда метка чужая и её выставлять нельзя (D21).
    final needed = profile is EmbeddedProfile && intent == _intent
        ? _setupOffer?.value
        : null;
    _notice = needed == null ? null : ProviderSetupNotice._(needed.cwd);
    emit(
      state._copyWith(
        providerSetupNotice: _notice,
        failureRepeat: repeat,
        connectionStatus: CodeLabConnectionStatus.failed,
        // Без отказа по токену — текст kit текущего состояния, а не прежний
        // `connectionMessage`: он мог остаться от прошлой попытки.
        connectionMessage: rejection ?? _kitMessage(_workspace.current),
      ),
    );
  }

  /// Сбой вытесненной попытки: статус не меняется, в журнал — уровнем info.
  void _recordStaleAttempt(Object error) => _diagnostics.record(
    'A superseded connection attempt ended: ${describeFailure(error)}',
    source: 'transport',
  );

  /// Вызывается сразу после перехода в `connecting`/`reconnecting`, а не
  /// до него: статус меняется синхронно, и повторное нажатие во время
  /// проверки не запускает второе подключение.
  ///
  /// Останавливает подключение локального агента, если папки проекта нет:
  /// статус `failed` и понятная причина в `connectionMessage` вместо ошибки
  /// запуска процесса или отказа `session/new`. Встроенный агент тоже
  /// локальный: ему папка нужна для слоёв конфигурации и журнала. Для
  /// WebSocket папка — путь на стороне удалённого агента, локально её не
  /// проверить.
  ///
  /// `true` — продолжать нельзя: папки нет или намерение [intent] уже
  /// вытеснено более новым (или Cubit закрыт). Вытесненное намерение не ставит
  /// `failed` и не доходит до `ClientWorkspace`, иначе оно затёрло бы
  /// подключение новой попытки (M1, AGENTS.md §9).
  Future<bool> _failIfProjectDirectoryMissing(
    ConnectionProfile profile,
    int intent,
    String project,
  ) async {
    if (profile is WebSocketProfile) {
      return false;
    }
    final missing = await _settings.missingProjectDirectory(project);
    if (isClosed || intent != _intent) {
      return true;
    }
    if (missing == null) {
      return false;
    }
    final message = projectFolderMissingMessage(missing);
    _rejectBeforeConnect(message: message);
    _diagnostics.record(
      message,
      severity: DiagnosticSeverity.error,
      source: 'project',
    );
    return true;
  }

  /// Отказ до обращения к `ClientWorkspace` (пустая команда, нет папки).
  ///
  /// Отказ не вытесняет попытку, уже переданную в kit, и не затрагивает
  /// живое соединение: при `Connected` статус остаётся `connected`, пока
  /// попытка в kit идёт (`Connecting`/`Reconnecting`) — прежним. Иначе `failed`
  /// поверх соединения скрыл бы его потерю (`lost` ставится только из
  /// `connected`, `_handleWorkspaceChange`). [message] (причина) попадает в
  /// `connectionMessage` только когда статус действительно `failed`: баннер
  /// ошибки не ложится поверх рабочего или идущего соединения, причина тогда
  /// только в диагностике.
  void _rejectBeforeConnect({String? message}) {
    final connection = _workspace.current.connection;
    final busy =
        connection is Connected ||
        connection is Connecting ||
        connection is Reconnecting;
    emit(
      state._copyWith(
        connectionStatus: busy
            ? connectionStatusOf(connection)
            : CodeLabConnectionStatus.failed,
        connectionMessage: busy || message == null
            ? state.connectionMessage
            : message,
      ),
    );
  }

  /// Проверка профиля до подключения: `false` — профиль непригоден, причина
  /// записана в диагностику с [action] в тексте.
  ///
  /// Профили из файла могли быть правлены вручную (пустая команда или адрес):
  /// такой профиль — сбой подключения с понятной причиной, а не исключение
  /// из Cubit.
  bool _validate(ConnectionProfile profile, {required String action}) {
    switch (profile) {
      case StdioProfile(:final command) when command.trim().isEmpty:
        _recordFormError('Stdio command is required before $action.');
        return false;
      case WebSocketProfile(:final uri) when uri.host.isEmpty:
        _recordFormError('WebSocket endpoint is required before $action.');
        return false;
      default:
        return true;
    }
  }

  /// Предупреждение D13 о `secret:` без значения: подключение пойдёт без
  /// токена, и причину отказа сервера пользователь должен увидеть. Только id
  /// профиля. Вызывается до начала попытки (`await` внутри попытки позволил бы
  /// двум подключениям перемешаться).
  Future<void> _warnIfSecretMissing(ConnectionProfile profile) async {
    if (await _tokenSecrets?.isSecretMissing(profile) ?? false) {
      _diagnostics.record(
        secretMissingWarning(profile.id),
        severity: DiagnosticSeverity.warning,
        source: 'transport',
      );
      _eventLogger?.warning(
        'connection_profile.token_secret_missing',
        context: {'profile_id': profile.id},
      );
    }
  }

  /// Ссылка на токен не вида `env:` — подключение идёт без токена, и это
  /// видно в диагностике (D13). Пишется только id профиля: сама ссылка могла
  /// быть вставлена вместо имени переменной и оказаться значением токена
  /// (M2). Формулировка не содержит «Token <слово>», которое `SecretRedactor`
  /// принимает за значение секрета.
  void _warnIfTokenUnsupported(ConnectionProfile profile) {
    if (profile is! WebSocketProfile || profile.tokenRef == null) {
      return;
    }
    if (ProfileTokenRef.parse(profile.tokenRef!) is UnsupportedTokenRef) {
      _diagnostics.record(
        'The token-reference format of profile ${profile.id} is not supported '
        'in this version; connecting without a token.',
        severity: DiagnosticSeverity.warning,
        source: 'transport',
      );
    }
  }

  /// Текст диагностики по типу подключения: формулировки stdio, WebSocket и
  /// встроенного агента различаются (прежние тексты первых двух сохранены).
  String _byType(
    ConnectionProfile profile, {
    required String stdio,
    required String webSocket,
    required String embedded,
  }) => switch (profile) {
    StdioProfile() => stdio,
    WebSocketProfile() => webSocket,
    EmbeddedProfile() => embedded,
  };

  void _recordFormError(String message) => _diagnostics.record(
    message,
    severity: DiagnosticSeverity.error,
    source: 'transport',
  );
}
