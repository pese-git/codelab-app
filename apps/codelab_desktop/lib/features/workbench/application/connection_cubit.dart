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

enum CodeLabTransportType {
  stdio(label: 'stdio'),
  webSocket(label: 'WebSocket');

  const CodeLabTransportType({required this.label});

  final String label;
}

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
  };

  String get selectedConnectionDetail => switch (transportType) {
    CodeLabTransportType.stdio => [
      stdioCommand,
      stdioArgs,
    ].where((part) => part.trim().isNotEmpty).join(' '),
    CodeLabTransportType.webSocket => webSocketEndpoint,
  };

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
    final isWebSocket = state.transportType == CodeLabTransportType.webSocket;
    final profile = _profileFromForm();
    if (profile == null) {
      _diagnostics.record(
        isWebSocket
            ? 'WebSocket endpoint is required before connecting.'
            : 'Stdio command is required before connecting.',
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      return;
    }

    emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.connecting));
    if (await _failIfProjectDirectoryMissing()) {
      return;
    }
    _diagnostics.record(
      isWebSocket
          ? 'Connecting WebSocket ACP agent: ${state.selectedConnectionDetail}.'
          : 'Starting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    try {
      await _workspace.connect(
        profile,
        projectDirectory: _settings.projectDirectory,
      );
      emit(
        state._copyWith(
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        isWebSocket
            ? 'WebSocket ACP agent connected: ${state.selectedConnectionDetail}.'
            : 'Stdio ACP agent started: ${state.selectedConnectionDetail}.',
        source: 'transport',
      );
    } on UnsupportedProtocolVersionException catch (error) {
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        'Incompatible ACP agent: ${error.message}',
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    } on Object catch (error) {
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        isWebSocket
            ? 'Failed to connect WebSocket ACP agent: $error'
            : 'Failed to start stdio ACP agent: $error',
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// Одна попытка переподключения через kit с профилем из текущей формы:
  /// пользователь мог изменить команду, адрес или проект после [connect]
  /// (design D4).
  Future<void> reconnect() async {
    final isWebSocket = state.transportType == CodeLabTransportType.webSocket;
    final profile = _profileFromForm();
    if (profile == null) {
      _diagnostics.record(
        isWebSocket
            ? 'WebSocket endpoint is required before reconnecting.'
            : 'Stdio command is required before reconnecting.',
        severity: DiagnosticSeverity.error,
        source: 'transport',
      );
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
      isWebSocket
          ? 'Reconnecting WebSocket ACP agent: ${state.selectedConnectionDetail}.'
          : 'Reconnecting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    try {
      await _workspace.reconnect(
        profile: profile,
        projectDirectory: _settings.projectDirectory,
      );
      if (isClosed) return;
      emit(
        state._copyWith(
          connectionStatus: connectionStatusOf(_workspace.current.connection),
        ),
      );
      _diagnostics.record(
        isWebSocket
            ? 'WebSocket ACP agent reconnected: ${state.selectedConnectionDetail}.'
            : 'Stdio ACP agent reconnected: ${state.selectedConnectionDetail}.',
        source: 'transport',
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(state._copyWith(connectionStatus: CodeLabConnectionStatus.failed));
      _diagnostics.record(
        isWebSocket
            ? 'Failed to reconnect WebSocket ACP agent: ${describeFailure(error)}'
            : 'Failed to reconnect stdio ACP agent: ${describeFailure(error)}',
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

  /// Вызывается сразу после перехода в `connecting`/`reconnecting`, а не
  /// до него: статус меняется синхронно, и повторное нажатие во время
  /// проверки не запускает второе подключение.
  ///
  /// Останавливает подключение локального агента, если папки проекта нет:
  /// статус `failed` и понятная причина в `connectionMessage` вместо ошибки
  /// запуска процесса или отказа `session/new`. Для WebSocket папка — путь
  /// на стороне удалённого агента, локально её не проверить.
  Future<bool> _failIfProjectDirectoryMissing() async {
    if (state.transportType != CodeLabTransportType.stdio) {
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

  /// Профиль из формы; `null` — форма не заполнена (нет команды stdio или
  /// корректного адреса WebSocket). Токен WebSocket кладётся в [_secrets],
  /// профиль хранит только ссылку на него (design D8).
  ConnectionProfile? _profileFromForm() {
    switch (state.transportType) {
      case CodeLabTransportType.stdio:
        final command = state.stdioCommand.trim();
        if (command.isEmpty) {
          return null;
        }
        return ConnectionProfile.stdio(
          id: 'codelab_desktop.stdio',
          label: state.selectedProfileLabel,
          command: command,
          args: parseShellWords(state.stdioArgs),
          env: parseEnvLines(state.stdioEnv),
          runInProjectDirectory: _settings.state.runAgentFromProjectDirectory,
        );
      case CodeLabTransportType.webSocket:
        final endpoint = state.webSocketEndpoint.trim();
        final uri = endpoint.isEmpty ? null : Uri.tryParse(endpoint);
        if (uri == null) {
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
    }
  }
}
