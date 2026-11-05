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
        StdioProfile,
        UnsupportedTokenRef,
        WebSocketProfile,
        WorkspaceState,
        describeFailure,
        secretMissingWarning;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabConnectionStatus;

import '../../../core/platform/connection_preferences.dart';
import '../../settings/application/connection_commands.dart';
import '../../settings/application/default_profile_resolver.dart';
import '../../settings/application/embedded_profile.dart';
import '../../settings/application/profile_view.dart'
    show profileOrigin, profileTitle;
import 'active_session_cubit.dart';
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

/// Профиль текущего окна и статус соединения.
///
/// Почему: раньше состояние держало черновик формы (тип, команда, адрес,
/// токен); теперь подключение идёт по профилю, а форму заменил диалог
/// «Add connection profile» (design.md change `add-app-settings-shell`, D6).
/// Состояния — статус и профиль, а не набор независимых флагов (AGENTS.md §8).
///
/// Для чего: [profile] — профиль окна: тот, который workspace принял при
/// последнем успешном подключении, а до первого подключения — профиль по
/// умолчанию (D5) или выбранный, но ещё не подключённый (D6); подписи и
/// деталь для экрана подключения и баннера выводятся из него.
final class WindowConnectionState {
  const WindowConnectionState({
    required this.connectionStatus,
    required this.profile,
    this.connectionMessage,
  });

  final CodeLabConnectionStatus connectionStatus;
  final ConnectionProfile profile;

  /// Причина из `ConnectionLost` или `ConnectionFailed` kit — текст баннера
  /// соединения (design D6 change `add-connection-and-error-states`);
  /// `null` в остальных состояниях.
  final String? connectionMessage;

  /// Тип подключения для подписи («stdio», «WebSocket», «Embedded agent»).
  String get transportLabel => switch (profile) {
    StdioProfile() => 'stdio',
    WebSocketProfile() => 'WebSocket',
    EmbeddedProfile() => 'Embedded agent',
  };

  String get selectedProfileLabel => profileTitle(profile);

  /// Деталь для подписи и диагностики: команда stdio без аргументов или
  /// `scheme://host:port` WebSocket без userinfo, пути и query — аргументы и
  /// адрес могут нести токен (D17, находка L1 ревью итерации 2).
  String get selectedConnectionDetail => _detailOf(profile);

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
    Object? connectionMessage = _unset,
  }) => WindowConnectionState(
    connectionStatus: connectionStatus ?? this.connectionStatus,
    profile: profile ?? this.profile,
    // `null` здесь — «причины нет», а не «не менять».
    connectionMessage: identical(connectionMessage, _unset)
        ? this.connectionMessage
        : connectionMessage as String?,
  );

  static const Object _unset = Object();
}

/// Подключение окна к агенту по профилю.
///
/// Почему: подключение, переподключение, выбор транспорта по профилю —
/// в `codelab_client_core` (`ClientWorkspace`, `ConfigTransportResolver`); в
/// app остаётся профиль окна и статус в модели `codelab_ui` (таблица переноса
/// `09-10`; design D10 change `extract-acp-client-kit`; design.md change
/// `add-app-settings-shell`, D6).
///
/// Для чего: владелец профиля окна и статуса соединения; единственная
/// реализация [ConnectionCommands] — через неё страница «Connection»
/// подключает окно, не дублируя номер попытки и диагностику. Сообщает о
/// неожиданной потере соединения части показываемой сессии.
///
/// Как использовать: создаётся после [ActiveSessionCubit] и [SettingsCubit]
/// (`CodeLabShellParts`). [connect] без профиля подключает профиль окна, а до
/// первого подключения — профиль по умолчанию ([defaultProfiles]; без выбора —
/// встроенный агент, D5); [connect] с профилем делает его профилем окна;
/// [reconnect] — тот же профиль. [connectOnStart] зовёт app после первого
/// кадра (D8). Токен профиля — только ссылка: значение читает резолвер
/// транспорта в момент открытия (D13, D15).
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
    ConnectionPreferences? preferences,
    Logger? eventLogger,
    ProfileSecretSource? tokenSecrets,
  }) : _tokenSecrets = tokenSecrets,
       _workspace = workspace,
       _diagnostics = diagnostics,
       _settings = settings,
       _activeSession = activeSession,
       _preferences = preferences,
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
  final ConnectionPreferences? _preferences;
  final Logger? _eventLogger;

  /// Источник токенов профилей: только чтобы предупредить о пустом секрете
  /// до подключения (D13); значение не сохраняется.
  final ProfileSecretSource? _tokenSecrets;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Профиль по умолчанию уже подставлен (или не нужен): `connect()` без
  /// профиля не ждёт.
  late final Future<void> _defaultLoaded;
  var _defaultResolved = false;

  /// Пользователь уже выбрал профиль окна: позднее чтение профиля по
  /// умолчанию его не заменяет (AGENTS.md §9, поздний результат).
  var _profileChosen = false;

  var _connectOnStartDone = false;

  /// Профиль последней попытки, которую workspace принял (`connect` или
  /// `reconnect` завершились без ошибки). До неё `null`. «Restart agent»
  /// переподключает именно его (L5).
  ConnectionProfile? _accepted;

  /// Профиль последнего начатого подключения, даже если оно не удалось:
  /// до первого принятого подключения «Restart agent» повторяет его.
  ConnectionProfile? _selected;
  final _restartTargets = StreamController<ConnectionProfile?>.broadcast();
  ConnectionProfile? _announcedTarget;

  @override
  ConnectionProfile? get restartTarget => _accepted ?? _selected;

  @override
  Stream<ConnectionProfile?> get restartTargets => _restartTargets.stream;

  void _announceTarget() {
    final target = restartTarget;
    if (target != _announcedTarget && !_restartTargets.isClosed) {
      _announcedTarget = target;
      _restartTargets.add(target);
    }
  }

  /// Номер последней начатой попытки [connect]/[reconnect]. Попытка, которую
  /// вытеснила более новая (повторный Connect, пока встроенный агент
  /// открывается), не вправе менять статус: иначе её отмена мелькнула бы
  /// `failed` посреди успешного подключения (`AGENTS.md` §9; design.md change
  /// `add-embedded-agent-mode`, D6, «Отмена подключения в app»). Он же
  /// отличает «Connect on start» от ручного Connect (D8).
  var _attempt = 0;

  /// Номер последнего вызова [connect]/[reconnect] до обращения к kit: им
  /// отбрасываются устаревшие ожидания (профиль по умолчанию, проверка
  /// папки). Отказ намерения [_attempt] не меняет.
  var _intent = 0;

  /// Подключает окно к [profile], а без него — к профилю окна (до первого
  /// подключения — к профилю по умолчанию).
  @override
  Future<void> connect([ConnectionProfile? profile]) async {
    // Намерение, а не попытка: номер попытки `_attempt` растёт только когда
    // проверки до `ClientWorkspace` пройдены. Отказ B (пустая команда, нет
    // папки) тогда не вытесняет попытку A, которая уже в kit (safety MEDIUM,
    // AGENTS.md §9).
    final intent = ++_intent;
    var target = profile;
    if (target == null) {
      if (!_defaultResolved) {
        await _defaultLoaded;
        if (isClosed || intent != _intent) {
          return;
        }
      }
      target = state.profile;
    }
    _profileChosen = true;
    // Профиль фиксируется на старте: подписи и диагностика описывают начатое
    // подключение, а не то, что выберут позже.
    final detail = WindowConnectionState._detailOf(target);
    // Пока workspace не принял ни одного подключения, профиль окна — тот,
    // что выбран (на нём работают «Connect» и «Reconnect» экрана
    // подключения); дальше он меняется только после принятой попытки (L5).
    final shown = _accepted == null ? target : null;
    if (!_validate(target, action: 'connecting')) {
      _rejectBeforeConnect(shown: shown);
      return;
    }

    emit(
      state._copyWith(
        profile: shown,
        connectionStatus: CodeLabConnectionStatus.connecting,
      ),
    );
    if (await _failIfProjectDirectoryMissing(target, intent, shown: shown)) {
      return;
    }
    await _warnIfSecretMissing(target);
    if (isClosed || intent != _intent) {
      return;
    }
    // Все проверки пройдены: с этого места попытка принадлежит kit.
    final attempt = ++_attempt;
    _selected = target;
    _announceTarget();
    _warnIfTokenUnsupported(target);
    _diagnostics.record(
      _byType(
        target,
        stdio: 'Starting stdio ACP agent: $detail.',
        webSocket: 'Connecting WebSocket ACP agent: $detail.',
        embedded: 'Starting embedded ACP agent: $detail.',
      ),
      source: 'transport',
    );

    try {
      await _workspace.connect(
        target,
        projectDirectory: _settings.projectDirectory,
      );
      // Вытесненная попытка завершается нормально и ничего не публикует
      // (контракт `ClientWorkspace`): итог — у новой попытки, а «started» от
      // старой был бы ложной диагностикой.
      if (isClosed || attempt != _attempt) {
        return;
      }
      _accepted = target;
      _announceTarget();
      emit(
        state._copyWith(
          profile: target,
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        _byType(
          target,
          stdio: 'Stdio ACP agent started: $detail.',
          webSocket: 'WebSocket ACP agent connected: $detail.',
          embedded: 'Embedded ACP agent started: $detail.',
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
      if (attempt != _attempt) {
        _recordStaleAttempt(error);
        return;
      }
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        _byType(
          target,
          stdio: 'Failed to start stdio ACP agent: $error',
          webSocket: 'Failed to connect WebSocket ACP agent: $error',
          embedded: 'Failed to start embedded ACP agent: $error',
        ),
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// Одна попытка переподключения через kit с профилем окна; проект мог
  /// измениться после [connect] (design D4).
  @override
  Future<void> reconnect() async {
    // Переподключается профиль, который держал workspace, а не тот, к
    // которому только что неудачно пытались подключиться (L5, D9).
    final profile = _accepted ?? state.profile;
    final detail = WindowConnectionState._detailOf(profile);
    final intent = ++_intent;
    _profileChosen = true;
    if (!_validate(profile, action: 'reconnecting')) {
      _rejectBeforeConnect();
      return;
    }

    emit(
      state._copyWith(connectionStatus: CodeLabConnectionStatus.reconnecting),
    );
    if (await _failIfProjectDirectoryMissing(profile, intent)) {
      return;
    }
    await _warnIfSecretMissing(profile);
    if (isClosed || intent != _intent) {
      return;
    }
    final attempt = ++_attempt;
    _selected = profile;
    _announceTarget();
    _warnIfTokenUnsupported(profile);
    _diagnostics.record(
      _byType(
        profile,
        stdio: 'Reconnecting stdio ACP agent: $detail.',
        webSocket: 'Reconnecting WebSocket ACP agent: $detail.',
        embedded: 'Reconnecting embedded ACP agent: $detail.',
      ),
      source: 'transport',
    );

    try {
      await _workspace.reconnect(
        profile: profile,
        projectDirectory: _settings.projectDirectory,
      );
      if (isClosed || attempt != _attempt) return;
      _accepted = profile;
      _announceTarget();
      emit(
        state._copyWith(
          profile: profile,
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        _byType(
          profile,
          stdio: 'Stdio ACP agent reconnected: $detail.',
          webSocket: 'WebSocket ACP agent reconnected: $detail.',
          embedded: 'Embedded ACP agent reconnected: $detail.',
        ),
        source: 'transport',
      );
    } on Object catch (error) {
      if (isClosed) return;
      if (attempt != _attempt) {
        _recordStaleAttempt(error);
        return;
      }
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        _byType(
          profile,
          stdio:
              'Failed to reconnect stdio ACP agent: ${describeFailure(error)}',
          webSocket:
              'Failed to reconnect WebSocket ACP agent: ${describeFailure(error)}',
          embedded:
              'Failed to reconnect embedded ACP agent: ${describeFailure(error)}',
        ),
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// «Connect on start» (D8): один раз после первого кадра и восстановления
  /// проекта подключает профиль по умолчанию. Обычный [connect]: сбой —
  /// `ConnectionFailed` и баннер, повторов нет.
  ///
  /// Ручное подключение, начатое раньше, имеет приоритет: номер попытки
  /// сравнивается после каждого ожидания, чтобы запуск не гонялся с ним.
  Future<void> connectOnStart() async {
    final preferences = _preferences;
    if (_connectOnStartDone || preferences == null) {
      return;
    }
    _connectOnStartDone = true;
    final started = _intent;
    final bool enabled;
    try {
      enabled = await preferences.loadConnectOnStart();
    } on Object {
      return;
    }
    if (!enabled) {
      return;
    }
    try {
      await _settings.projectRestored;
    } on Object {
      // Проект не восстановился: подключаемся к папке по умолчанию.
    }
    await _defaultLoaded;
    if (isClosed || _intent != started) {
      return;
    }
    final profile = state.profile;
    _eventLogger?.info(
      'connection.connect_on_start',
      context: {'profile_id': profile.id, 'type': _typeNameOf(profile)},
    );
    await connect(profile);
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
    final message = switch (workspace.connection) {
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
    int intent, {
    ConnectionProfile? shown,
  }) async {
    if (profile is WebSocketProfile) {
      return false;
    }
    final missing = await _settings.missingProjectDirectory();
    if (isClosed || intent != _intent) {
      return true;
    }
    if (missing == null) {
      return false;
    }
    final message =
        'Project folder not found: $missing. '
        'Choose an existing folder with Open folder… and connect again.';
    _rejectBeforeConnect(message: message, shown: shown);
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
  void _rejectBeforeConnect({String? message, ConnectionProfile? shown}) {
    final connection = _workspace.current.connection;
    final busy =
        connection is Connected ||
        connection is Connecting ||
        connection is Reconnecting;
    emit(
      state._copyWith(
        profile: shown,
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

  /// Тип профиля для событий журнала (D17).
  static String _typeNameOf(ConnectionProfile profile) => switch (profile) {
    StdioProfile() => 'stdio',
    WebSocketProfile() => 'webSocket',
    EmbeddedProfile() => 'embedded',
  };

  void _recordFormError(String message) => _diagnostics.record(
    message,
    severity: DiagnosticSeverity.error,
    source: 'transport',
  );
}
