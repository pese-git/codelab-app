import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        InMemorySecretSource,
        WorkspaceState,
        describeFailure,
        parseEnvLines,
        parseShellWords;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabConnectionStatus;

import 'active_session_cubit.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

typedef CodeLabStdioTransportFactory =
    AcpTransport Function(StdioAcpTransportConfig config);

typedef CodeLabWebSocketTransportFactory =
    AcpTransport Function(WebSocketAcpTransportConfig config);

/// Тип подключения формы.
///
/// [embedded] — агент в процессе приложения (`codelab_embedded`): полей у типа
/// нет, проект выбирается «Open Project», а конфигурация читается из файлов
/// агента (design.md change `add-embedded-agent-mode`, D9; agent-workbench-ui
/// «Тип подключения «Встроенный агент»»).
enum CodeLabTransportType {
  stdio(label: 'stdio'),
  webSocket(label: 'WebSocket'),
  embedded(label: 'Embedded agent');

  const CodeLabTransportType({required this.label});

  final String label;
}

/// Профиль хоста встроенного агента в приложении (design.md change
/// `add-embedded-agent-mode`, D9): локальное исполнение, режим разрешений
/// из конфигурации агента.
const embeddedHostProfile = 'embedded-app-desktop';

/// Черновик профиля подключения из формы и статус соединения.
final class ConnectionFormState {
  const ConnectionFormState({
    required this.connectionStatus,
    required this.transportType,
    required this.stdioProfileName,
    required this.stdioCommand,
    required this.stdioArgs,
    required this.stdioEnv,
    required this.webSocketEndpoint,
    required this.webSocketToken,
    this.connectionMessage,
  });

  /// Форма по профилю встроенного агента; WebSocket — локальный адрес.
  factory ConnectionFormState.initial(StdioAcpAgentProfile profile) =>
      ConnectionFormState(
        connectionStatus: CodeLabConnectionStatus.disconnected,
        transportType: CodeLabTransportType.stdio,
        stdioProfileName: profile.name,
        stdioCommand: profile.command,
        stdioArgs: profile.args.join(' '),
        stdioEnv: profile.env.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('\n'),
        webSocketEndpoint: 'ws://localhost:8765/acp',
        webSocketToken: '',
      );

  final CodeLabConnectionStatus connectionStatus;
  final CodeLabTransportType transportType;
  final String stdioProfileName;
  final String stdioCommand;
  final String stdioArgs;
  final String stdioEnv;
  final String webSocketEndpoint;
  final String webSocketToken;

  /// Причина из `ConnectionLost` или `ConnectionFailed` kit — текст баннера
  /// соединения (design D6 change `add-connection-and-error-states`);
  /// `null` в остальных состояниях.
  final String? connectionMessage;

  String get selectedProfileLabel => switch (transportType) {
    CodeLabTransportType.stdio => stdioProfileName,
    CodeLabTransportType.webSocket => 'Remote ACP Agent',
    CodeLabTransportType.embedded => 'Embedded agent',
  };

  String get selectedConnectionDetail => switch (transportType) {
    CodeLabTransportType.stdio => [
      stdioCommand,
      stdioArgs,
    ].where((part) => part.trim().isNotEmpty).join(' '),
    CodeLabTransportType.webSocket => webSocketEndpoint,
    CodeLabTransportType.embedded => embeddedConnectionDetail,
  };

  /// Деталь встроенного подключения: пакет и профиль хоста (D9).
  static const embeddedConnectionDetail =
      'codelab_embedded ($embeddedHostProfile)';

  ConnectionFormState _copyWith({
    CodeLabConnectionStatus? connectionStatus,
    CodeLabTransportType? transportType,
    String? stdioProfileName,
    String? stdioCommand,
    String? stdioArgs,
    String? stdioEnv,
    String? webSocketEndpoint,
    String? webSocketToken,
    Object? connectionMessage = _unset,
  }) => ConnectionFormState(
    connectionStatus: connectionStatus ?? this.connectionStatus,
    transportType: transportType ?? this.transportType,
    stdioProfileName: stdioProfileName ?? this.stdioProfileName,
    stdioCommand: stdioCommand ?? this.stdioCommand,
    stdioArgs: stdioArgs ?? this.stdioArgs,
    stdioEnv: stdioEnv ?? this.stdioEnv,
    webSocketEndpoint: webSocketEndpoint ?? this.webSocketEndpoint,
    webSocketToken: webSocketToken ?? this.webSocketToken,
    // `null` здесь — «причины нет», а не «не менять».
    connectionMessage: identical(connectionMessage, _unset)
        ? this.connectionMessage
        : connectionMessage as String?,
  );

  static const Object _unset = Object();
}

/// Форма подключения и подключение к агенту.
///
/// Почему: подключение, переподключение, выбор транспорта по профилю и
/// разбор аргументов — в `codelab_client_core` (`ClientWorkspace`,
/// `ConfigTransportResolver`, `parseShellWords`); в app остаётся черновик
/// профиля из формы и статус в модели `codelab_ui` (таблица переноса `09-10`,
/// строки «Выбор транспорта» и «Подключение»; design D10 change
/// `extract-acp-client-kit`).
///
/// Для чего: владелец формы подключения и статуса соединения; сообщает о
/// неожиданной потере соединения части показываемой сессии.
///
/// Как использовать: создаётся после [ActiveSessionCubit] и
/// [SettingsCubit] (`CodeLabShellParts`). [secrets] — тот же
/// `InMemorySecretSource`, что у резолвера WebSocket: токен из формы
/// попадает в профиль только ссылкой (design D8).
final class ConnectionCubit extends ShellPartCubit<ConnectionFormState> {
  ConnectionCubit({
    required super.changes,
    required StdioAcpAgentProfile profile,
    required ClientWorkspace workspace,
    required InMemorySecretSource secrets,
    required ShellDiagnostics diagnostics,
    required SettingsCubit settings,
    required ActiveSessionCubit activeSession,
  }) : _workspace = workspace,
       _secrets = secrets,
       _diagnostics = diagnostics,
       _settings = settings,
       _activeSession = activeSession,
       super(ConnectionFormState.initial(profile)) {
    _workspaceSubscription = _workspace.state.listen(_handleWorkspaceChange);
  }

  final ClientWorkspace _workspace;
  final InMemorySecretSource _secrets;
  final ShellDiagnostics _diagnostics;
  final SettingsCubit _settings;
  final ActiveSessionCubit _activeSession;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Номер последней начатой попытки [connect]/[reconnect]. Попытка, которую
  /// вытеснила более новая (повторный Connect, пока встроенный агент
  /// открывается), не вправе менять статус: иначе её отмена мелькнула бы
  /// `failed` посреди успешного подключения (`AGENTS.md` §9; design.md change
  /// `add-embedded-agent-mode`, D6, «Отмена подключения в app»).
  var _attempt = 0;

  /// Ссылка на токен WebSocket в [_secrets].
  static const _webSocketTokenRef = 'codelab_desktop.websocket.token';

  void selectTransport(CodeLabTransportType value) =>
      emit(state._copyWith(transportType: value));

  void updateStdioProfileName(String value) =>
      emit(state._copyWith(stdioProfileName: value));

  void updateStdioCommand(String value) =>
      emit(state._copyWith(stdioCommand: value));

  void updateStdioArgs(String value) => emit(state._copyWith(stdioArgs: value));

  void updateStdioEnv(String value) => emit(state._copyWith(stdioEnv: value));

  void updateWebSocketEndpoint(String value) =>
      emit(state._copyWith(webSocketEndpoint: value));

  void updateWebSocketToken(String value) =>
      emit(state._copyWith(webSocketToken: value));

  Future<void> connect() async {
    // Тип фиксируется на старте: форму можно менять, пока подключение идёт, а
    // тексты диагностики должны описывать начатое подключение.
    final type = state.transportType;
    final detail = state.selectedConnectionDetail;
    final attempt = ++_attempt;
    final profile = _profileFromForm(action: 'connecting');
    if (profile == null) {
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      return;
    }

    emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.connecting));
    if (await _failIfProjectDirectoryMissing()) {
      return;
    }
    _diagnostics.record(
      _byType(
        type,
        stdio: 'Starting stdio ACP agent: $detail.',
        webSocket: 'Connecting WebSocket ACP agent: $detail.',
        embedded: 'Starting embedded ACP agent: $detail.',
      ),
      source: 'transport',
    );

    try {
      await _workspace.connect(
        profile,
        projectDirectory: _settings.projectDirectory,
      );
      // Вытесненная попытка завершается нормально и ничего не публикует
      // (контракт `ClientWorkspace`): итог — у новой попытки, а «started» от
      // старой был бы ложной диагностикой.
      if (attempt != _attempt) {
        return;
      }
      emit(
        state._copyWith(
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        _byType(
          type,
          stdio: 'Stdio ACP agent started: $detail.',
          webSocket: 'WebSocket ACP agent connected: $detail.',
          embedded: 'Embedded ACP agent started: $detail.',
        ),
        source: 'transport',
      );
    } on UnsupportedProtocolVersionException catch (error) {
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
      if (attempt != _attempt) {
        _recordStaleAttempt(error);
        return;
      }
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        _byType(
          type,
          stdio: 'Failed to start stdio ACP agent: $error',
          webSocket: 'Failed to connect WebSocket ACP agent: $error',
          embedded: 'Failed to start embedded ACP agent: $error',
        ),
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// Одна попытка переподключения через kit с профилем из текущей формы:
  /// пользователь мог изменить команду, адрес или проект после [connect]
  /// (design D4).
  Future<void> reconnect() async {
    final type = state.transportType;
    final detail = state.selectedConnectionDetail;
    final attempt = ++_attempt;
    final profile = _profileFromForm(action: 'reconnecting');
    if (profile == null) {
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      return;
    }

    emit(
      state._copyWith(connectionStatus: CodeLabConnectionStatus.reconnecting),
    );
    if (await _failIfProjectDirectoryMissing()) {
      return;
    }
    _diagnostics.record(
      _byType(
        type,
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
      emit(
        state._copyWith(
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        _byType(
          type,
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
          type,
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

  @override
  Future<void> close() async {
    await _workspaceSubscription.cancel();
    return super.close();
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
  Future<bool> _failIfProjectDirectoryMissing() async {
    if (state.transportType == CodeLabTransportType.webSocket) {
      return false;
    }
    final missing = await _settings.missingProjectDirectory();
    if (missing == null) {
      return false;
    }
    if (isClosed) {
      return true;
    }
    final message =
        'Project folder not found: $missing. '
        'Choose an existing folder with Open folder… and connect again.';
    emit(
      state._copyWith(
        connectionStatus: CodeLabConnectionStatus.failed,
        connectionMessage: message,
      ),
    );
    _diagnostics.record(
      message,
      severity: DiagnosticSeverity.error,
      source: 'project',
    );
    return true;
  }

  /// Профиль из формы; `null` — форма не заполнена или неверна (нет команды
  /// stdio, незакрытая кавычка в аргументах, нет корректного адреса
  /// WebSocket), причина уже записана в диагностику с [action] в тексте.
  /// Токен WebSocket кладётся в [_secrets], профиль хранит только ссылку на
  /// него (design D8).
  ConnectionProfile? _profileFromForm({required String action}) {
    switch (state.transportType) {
      case CodeLabTransportType.stdio:
        final command = state.stdioCommand.trim();
        if (command.isEmpty) {
          _recordFormError('Stdio command is required before $action.');
          return null;
        }
        final List<String> args;
        try {
          args = parseShellWords(state.stdioArgs);
        } on FormatException catch (error) {
          // Аргументы разбираются как в shell (design.md change
          // `add-codelab-cli`, D14): незакрытая кавычка — ошибка формы, а не
          // исключение из Cubit.
          _recordFormError(
            'Stdio arguments are invalid before $action: ${error.message}.',
          );
          return null;
        }
        return ConnectionProfile.stdio(
          id: 'codelab_desktop.stdio',
          label: state.selectedProfileLabel,
          command: command,
          args: args,
          env: parseEnvLines(state.stdioEnv),
          runInProjectDirectory: _settings.state.runAgentFromProjectDirectory,
        );
      case CodeLabTransportType.webSocket:
        final endpoint = state.webSocketEndpoint.trim();
        final uri = endpoint.isEmpty ? null : Uri.tryParse(endpoint);
        if (uri == null) {
          _recordFormError('WebSocket endpoint is required before $action.');
          return null;
        }
        final token = state.webSocketToken.trim();
        _secrets.write(_webSocketTokenRef, token.isEmpty ? null : token);
        return ConnectionProfile.webSocket(
          id: 'codelab_desktop.websocket',
          label: state.selectedProfileLabel,
          uri: uri,
          tokenRef: token.isEmpty ? null : _webSocketTokenRef,
        );
      case CodeLabTransportType.embedded:
        // Полей у типа нет: конфигурацию агент читает сам из
        // `$CODELAB_HOME/config.yaml` и `.codelab/config.yaml` проекта (D5).
        return ConnectionProfile.embedded(
          id: 'embedded',
          label: state.selectedProfileLabel,
          hostProfile: embeddedHostProfile,
        );
    }
  }

  /// Текст диагностики по типу подключения: формулировки stdio, WebSocket и
  /// встроенного агента различаются (прежние тексты первых двух сохранены).
  String _byType(
    CodeLabTransportType type, {
    required String stdio,
    required String webSocket,
    required String embedded,
  }) => switch (type) {
    CodeLabTransportType.stdio => stdio,
    CodeLabTransportType.webSocket => webSocket,
    CodeLabTransportType.embedded => embedded,
  };

  void _recordFormError(String message) => _diagnostics.record(
    message,
    severity: DiagnosticSeverity.error,
    source: 'transport',
  );
}
