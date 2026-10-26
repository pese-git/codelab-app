import 'dart:async';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';

import '../backend/agent_backend.dart';
import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../connection/transport_resolver.dart';
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
/// транспорта и агента уходят вызывающему исключениями `acp_client_core`
/// после публикации `ConnectionFailed`; отказы самого kit —
/// [ClientWorkspaceException].
abstract interface class ClientWorkspace {
  factory ClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
  }) = DefaultClientWorkspace;

  WorkspaceState get current;

  /// Изменения [current]; доставляются синхронно, чтобы хост видел переход
  /// соединения сразу после события транспорта.
  Stream<WorkspaceState> get state;

  /// Подключается к агенту [profile]; [projectDirectory] — папка проекта,
  /// `cwd` новых сессий и, если профиль просит, процесса агента.
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  });

  /// Одна попытка переподключения без `session/load` (design D4).
  ///
  /// [profile] и [projectDirectory] заменяют текущие, если переданы: хост
  /// мог изменить форму подключения после [connect].
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
  });

  /// Создаёт сессию в [cwd] (по умолчанию — папка проекта) и делает её
  /// активной.
  Future<SessionHandle> newSession({String? cwd});

  SessionHandle? session(SessionId id);

  /// Делает сессию [id] активной; неизвестный id игнорируется.
  void activate(SessionId id);

  /// Отписывается от бэкенда и закрывает потоки; бэкенд закрывает его
  /// владелец.
  Future<void> dispose();
}

/// Сессия рабочего пространства.
///
/// Почему: хосту нужен объект сессии, а не id и выборка из общего списка.
///
/// Для чего: текущее [SessionView] и его изменения. Отправку промптов,
/// отмену, одобрения и опции переносят следующие итерации change
/// (design D12).
abstract interface class SessionHandle {
  SessionId get id;

  String get cwd;

  SessionView get current;

  Stream<SessionView> get view;
}

/// Реализация [ClientWorkspace] по умолчанию.
final class DefaultClientWorkspace implements ClientWorkspace {
  DefaultClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
  }) : _backend = backend,
       _resolvers = List.unmodifiable(resolvers) {
    _connectionSubscription = backend.connectionStates.listen(
      _handleConnectionState,
    );
    _sessionSubscription = backend.sessionChanges.listen(_handleSession);
  }

  final AgentBackend _backend;
  final List<TransportResolver> _resolvers;
  final _states = StreamController<WorkspaceState>.broadcast(sync: true);
  final _handles = <SessionId, _SessionHandle>{};

  /// Порядок списка сессий: от новой к старой.
  final _order = <SessionId>[];

  late final StreamSubscription<ClientConnectionState> _connectionSubscription;
  late final StreamSubscription<AcpSession> _sessionSubscription;
  var _current = const WorkspaceState();

  /// Какой переход ведёт явный вызов: промежуточные состояния ядра
  /// (`disconnected`, `connecting`, `initializing`) при переподключении
  /// остаются `Reconnecting`, а не мигают `Connecting`.
  _Transition _transition = _Transition.none;

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => _states.stream;

  @override
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    final resolver = _resolverFor(profile);
    if (resolver == null) {
      throw _rejectUnsupported(profile, projectDirectory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.connecting(),
        profile: profile,
        projectDirectory: projectDirectory,
      ),
    );
    _transition = _Transition.connecting;
    try {
      final transport = await resolver.open(
        profile,
        projectDirectory: projectDirectory,
      );
      final connectionState = await _backend.connect(transport);
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
  }

  @override
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
  }) async {
    final target = profile ?? _current.profile;
    final directory = projectDirectory ?? _current.projectDirectory;
    if (target == null || directory == null) {
      throw const ClientWorkspaceException(
        'Connect an agent before reconnecting.',
      );
    }
    final resolver = _resolverFor(target);
    if (resolver == null) {
      throw _rejectUnsupported(target, directory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.reconnecting(attempt: 1),
        profile: target,
        projectDirectory: directory,
      ),
    );
    _transition = _Transition.reconnecting;
    try {
      final connectionState = await _backend.reconnect(
        ReconnectCommand(
          transportFactory: () =>
              resolver.open(target, projectDirectory: directory),
        ),
      );
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
  }

  @override
  Future<SessionHandle> newSession({String? cwd}) async {
    final directory = _current.projectDirectory;
    if (_current.connection is! Connected || directory == null) {
      throw const ClientWorkspaceException(
        'Connect an agent before creating a session.',
      );
    }

    final session = await _backend.createSession(
      CreateSessionCommand(cwd: cwd ?? directory),
    );
    final handle = _track(session);
    _publish(
      _current.copyWith(sessions: _summaries(), activeSessionId: session.id),
    );
    return handle;
  }

  @override
  SessionHandle? session(SessionId id) => _handles[id];

  @override
  void activate(SessionId id) {
    if (!_handles.containsKey(id) || _current.activeSessionId == id) {
      return;
    }
    _publish(_current.copyWith(activeSessionId: id));
  }

  @override
  Future<void> dispose() async {
    await _connectionSubscription.cancel();
    await _sessionSubscription.cancel();
    for (final handle in _handles.values) {
      await handle.close();
    }
    await _states.close();
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
    String projectDirectory,
  ) {
    final error = UnsupportedConnectionProfileException(profile);
    _publish(
      _current.copyWith(
        connection: ConnectionView.failed(
          reason: ConnectionFailureReason.startFailed,
          message: error.message,
        ),
        profile: profile,
        projectDirectory: projectDirectory,
      ),
    );
    return error;
  }

  void _handleConnectionState(ClientConnectionState connectionState) {
    _publishConnection(_viewFor(connectionState));
  }

  void _handleSession(AcpSession session) {
    final previous = _handles[session.id]?.current.status;
    final status = _track(session).current.status;
    if (previous != status) {
      _publish(_current.copyWith(sessions: _summaries()));
    }
  }

  /// Регистрирует сессию, если она новая, и возвращает её handle.
  _SessionHandle _track(AcpSession session) {
    final existing = _handles[session.id];
    if (existing != null) {
      existing.update(session);
      return existing;
    }
    final handle = _SessionHandle(session);
    _handles[session.id] = handle;
    _order.insert(0, session.id);
    return handle;
  }

  List<SessionSummaryView> _summaries() => [
    for (final id in _order)
      SessionSummaryView(
        id: id,
        cwd: _handles[id]!.cwd,
        status: _handles[id]!.current.status,
      ),
  ];

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

  /// Ошибка явного подключения: если ядро уже опубликовало сбой, он
  /// остаётся; иначе (резолвер не открыл транспорт) — сбой запуска.
  void _publishFailure(Object error) {
    if (_current.connection is ConnectionFailed) {
      return;
    }
    _publishConnection(
      ConnectionView.failed(
        reason: ConnectionFailureReason.startFailed,
        message: switch (error) {
          AcpClientApplicationException(:final message) ||
          AcpTransportException(:final message) ||
          ClientWorkspaceException(:final message) => message,
          _ => '$error',
        },
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
  }
}

enum _Transition { none, connecting, reconnecting }

final class _SessionHandle implements SessionHandle {
  _SessionHandle(AcpSession session)
    : id = session.id,
      cwd = session.cwd,
      _current = SessionView(
        revision: 0,
        status: SessionStatusView.of(session.status),
      ),
      _session = session;

  @override
  final SessionId id;

  @override
  final String cwd;

  final _views = StreamController<SessionView>.broadcast(sync: true);
  SessionView _current;
  AcpSession _session;

  @override
  SessionView get current => _current;

  @override
  Stream<SessionView> get view => _views.stream;

  /// Каждое изменение сессии в ядре — новое представление с `revision + 1`;
  /// повтор того же снимка (`identical`) — no-op.
  void update(AcpSession session) {
    if (identical(session, _session)) {
      return;
    }
    _session = session;
    _current = SessionView(
      revision: _current.revision + 1,
      status: SessionStatusView.of(session.status),
    );
    if (!_views.isClosed) {
      _views.add(_current);
    }
  }

  Future<void> close() => _views.close();
}
