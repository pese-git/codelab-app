// Текст ошибки агента в диагностике kit (change `redesign-protocol-pane`,
// tasks 7.3; design.md D3, «Текст ошибки агента»; spec acp-client-kit
// «Диагностика без текста ошибки агента»).
//
// При базовой `metadataOnly` `WorkspaceDiagnostic` о сбое хода, загрузки и
// списка сессий, отмены, ответа на одобрение и опции конфигурации несёт
// префикс CodeLab и код, но не текст `JsonRpcError.message` и `data`; текст для
// пользователя (`PromptFailed.error`, заметка транскрипта, баннер соединения)
// сохраняет текст агента после маскирования. При `full` диагностика несёт
// замаскированный текст.
//
// Бэкенд — тонкая обёртка над настоящим `AcpClientBackend` на
// `FakeAcpTransport`: она отдаёт политику ядра через порт и по запросу теста
// роняет отдельные операции исключением `AcpClientApplicationException` с
// причиной `JsonRpcError`. Без `Future.delayed`.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _msgMarker = 'AGENT_MSG_MARKER';
const _dataMarker = 'AGENT_DATA_MARKER';
const _token = 'sk-LEAKEDTOKEN123456';
const _agentMessage = '$_msgMarker /home/u/secret.txt api_key=$_token';

const _agentError = JsonRpcError(
  code: -32603,
  message: _agentMessage,
  data: {'detail': _dataMarker},
);

// Агент без `session/list`: иначе `connect` ждал бы ответа на список. Для
// сценария «список сессий» ответ подменяет бэкенд-обёртка.
const _loadOnly = AgentCapabilities(loadSession: true);
const _withList = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

/// Исключение ядра клиента с ответом-ошибкой агента, как его бросает
/// `AcpClientApplication` (`_completePendingRequest`).
const _agentFailure = AcpClientApplicationException(
  'ACP request x failed: $_agentMessage',
  cause: _agentError,
);

/// Сбой с текстом секрета, не относящийся к исключениям kit.
final class _OddFailure implements Exception {
  @override
  String toString() => 'odd failure api_key=$_token';
}

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication application;
  late _Backend backend;
  late ClientWorkspace workspace;
  late List<WorkspaceDiagnostic> diagnostics;
  late StreamSubscription<WorkspaceDiagnostic> subscription;

  Future<void> start(
    ProtocolPayloadPolicy policy, {
    Object? listFailure,
    TransportResolver? resolver,
    WorkspaceSnapshotStore? snapshots,
  }) async {
    transport = FakeAcpTransport()
      ..initializeAgentCapabilities = listFailure == null
          ? _loadOnly
          : _withList;
    application = AcpClientApplication(
      transport: FakeAcpTransport(),
      protocolPayloads: policy,
    );
    backend = _Backend(AcpClientBackend(application))
      ..failures['list'] = listFailure;
    workspace = ClientWorkspace(
      backend: backend,
      resolvers: [resolver ?? ConfigTransportResolver(stdio: (_) => transport)],
      snapshots: snapshots,
    );
    diagnostics = [];
    subscription = workspace.diagnostics.listen(diagnostics.add);
  }

  Future<void> connect() => workspace.connect(
    const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
    projectDirectory: '/work',
  );

  Future<SessionHandle> newSession(String id) async {
    final request = transport.sent.firstWhere(
      (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
    );
    final handle = workspace.newSession();
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (await request as JsonRpcRequest).id,
        result: NewSessionResponse(sessionId: SessionId(id)).toJson(),
      ),
    );
    return handle;
  }

  tearDown(() async {
    await subscription.cancel();
    await workspace.dispose();
    await application.dispose();
  });

  String diagnosticText() => diagnostics.map((d) => d.message).join('\n');

  void expectMetadataOnly(String prefix) {
    final entry = diagnostics.singleWhere((d) => d.message.startsWith(prefix));
    expect(entry.message, contains('-32603'));
    expect(entry.message, isNot(contains(_msgMarker)));
    expect(entry.message, isNot(contains(_dataMarker)));
    expect(entry.message, isNot(contains('secret.txt')));
    expect(entry.message, isNot(contains(_token)));
  }

  void expectFull(String prefix) {
    final entry = diagnostics.singleWhere((d) => d.message.startsWith(prefix));
    expect(entry.message, contains(_msgMarker));
    expect(entry.message, isNot(contains(_token)));
  }

  group('metadataOnly', () {
    test('ход: диагностика без текста, пользователь видит текст', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      final handle = await newSession('s-1');
      final request = transport.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionPromptMethod,
      );
      final done = handle.send('go');
      transport.emitInbound(
        JsonRpcMessage.response(
          id: (await request as JsonRpcRequest).id,
          error: _agentError,
        ),
      );
      final outcome = await done;

      expectMetadataOnly('Failed to send prompt');
      expect(outcome, isA<PromptFailed>());
      expect(
        describeFailure((outcome as PromptFailed).error),
        contains(_msgMarker),
      );
      final notices = handle.current.transcript.whereType<NoticeItem>();
      expect(notices.any((n) => n.text.contains(_msgMarker)), isTrue);
      expect(notices.any((n) => n.text.contains(_token)), isFalse);
    });

    test('NoticeItem.failure.message без токена, с маркером', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      final handle = await newSession('s-1');
      final request = transport.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionPromptMethod,
      );
      final done = handle.send('go');
      transport.emitInbound(
        JsonRpcMessage.response(
          id: (await request as JsonRpcRequest).id,
          error: _agentError,
        ),
      );
      await done;

      final failure = handle.current.transcript
          .whereType<NoticeItem>()
          .map((n) => n.failure)
          .whereType<RequestPromptFailure>()
          .single;
      expect(failure.message, contains(_msgMarker));
      expect(failure.message, isNot(contains(_token)));
    });

    test('загрузка сессии', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      backend.failures['load'] = _agentFailure;
      await expectLater(
        workspace.loadSession(const SessionId('s-2'), cwd: '/work'),
        throwsA(isA<AcpClientApplicationException>()),
      );

      expectMetadataOnly('Failed to load ACP session s-2');
    });

    test('список сессий', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        listFailure: _agentFailure,
      );
      await connect();

      expectMetadataOnly('Failed to list ACP sessions');
    });

    test('отмена хода', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      final handle = await newSession('s-1');
      backend.failures['cancel'] = _agentFailure;
      await expectLater(handle.cancel(), throwsA(isA<Object>()));

      expectMetadataOnly('Failed to cancel prompt turn');
    });

    test('ответ на одобрение', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      final handle = await newSession('s-1');
      backend.failures['respond'] = _agentFailure;
      await expectLater(
        handle.respond(
          const ApprovalRequestId('a-1'),
          const PermissionOptionId('allow'),
        ),
        throwsA(isA<Object>()),
      );

      expectMetadataOnly('Failed to respond to approval request');
    });

    test('опция конфигурации', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await connect();
      final handle = await newSession('s-1');
      backend.failures['config'] = _agentFailure;
      await expectLater(
        handle.setConfigOption('model', 'fast'),
        throwsA(isA<Object>()),
      );

      expectMetadataOnly('Failed to set config option model');
    });

    test('прочий сбой подключения: баннер без токена', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        resolver: ConfigTransportResolver(stdio: (_) => throw _OddFailure()),
      );
      await expectLater(connect(), throwsA(isA<_OddFailure>()));

      final view = workspace.current.connection;
      expect(view, isA<ConnectionFailed>());
      final message = (view as ConnectionFailed).message;
      expect(message, contains('odd failure'));
      expect(message, isNot(contains(_token)));
    });
  });

  group('восстановление: диагностика restore (D3)', () {
    const snapshot =
        '{"version":1,"windows":{"main":{"projectDirectory":"/work",'
        '"activeSessionId":"s-42","openSessions":[{"id":"s-42","cwd":"/work"}]}}}';

    test('metadataOnly: сбой чтения снимка без текста', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        snapshots: _ThrowingStore(readError: _OddFailure()),
      );
      await workspace.restoreProject();

      final entry = diagnostics.singleWhere(
        (d) => d.message.startsWith('Failed to read workspace snapshot'),
      );
      expect(entry.message, contains('_OddFailure'));
      expect(entry.message, isNot(contains('odd failure')));
      expect(entry.message, isNot(contains(_token)));
    });

    test('full: сбой чтения снимка с замаскированным текстом', () async {
      await start(
        ProtocolPayloadPolicy.full,
        snapshots: _ThrowingStore(readError: _OddFailure()),
      );
      await workspace.restoreProject();

      final entry = diagnostics.singleWhere(
        (d) => d.message.startsWith('Failed to read workspace snapshot'),
      );
      expect(entry.message, contains('odd failure'));
      expect(entry.message, isNot(contains(_token)));
    });

    test('metadataOnly: сбой записи снимка без текста', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        snapshots: _ThrowingStore(writeError: _OddFailure()),
      );
      await workspace.restoreProject();
      await connect();
      await workspace.flushSnapshot();

      final entry = diagnostics.firstWhere(
        (d) => d.message.startsWith('Failed to save workspace snapshot'),
      );
      expect(entry.message, contains('_OddFailure'));
      expect(entry.message, isNot(contains(_token)));
    });

    test('metadataOnly: сбой восстановления без текста агента', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        snapshots: InMemoryWorkspaceSnapshotStore(snapshot),
      );
      backend.failures['load'] = _agentFailure;
      backend.failures['create'] = _agentFailure;
      await workspace.restoreProject();
      await connect();

      expectMetadataOnly('Failed to restore the workspace');
    });

    test('full: сбой восстановления с замаскированным текстом', () async {
      await start(
        ProtocolPayloadPolicy.full,
        snapshots: InMemoryWorkspaceSnapshotStore(snapshot),
      );
      backend.failures['load'] = _agentFailure;
      backend.failures['create'] = _agentFailure;
      await workspace.restoreProject();
      await connect();

      expectFull('Failed to restore the workspace');
    });
  });

  group('full', () {
    test('ход: диагностика с замаскированным текстом', () async {
      await start(ProtocolPayloadPolicy.full);
      await connect();
      final handle = await newSession('s-1');
      final request = transport.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionPromptMethod,
      );
      final done = handle.send('go');
      transport.emitInbound(
        JsonRpcMessage.response(
          id: (await request as JsonRpcRequest).id,
          error: _agentError,
        ),
      );
      await done;

      expectFull('Failed to send prompt');
    });

    test('загрузка, отмена, одобрение и опция', () async {
      await start(ProtocolPayloadPolicy.full);
      await connect();
      final handle = await newSession('s-1');
      backend.failures['load'] = _agentFailure;
      backend.failures['cancel'] = _agentFailure;
      backend.failures['respond'] = _agentFailure;
      backend.failures['config'] = _agentFailure;
      await expectLater(
        workspace.loadSession(const SessionId('s-2'), cwd: '/work'),
        throwsA(isA<Object>()),
      );
      await expectLater(handle.cancel(), throwsA(isA<Object>()));
      await expectLater(
        handle.respond(
          const ApprovalRequestId('a-1'),
          const PermissionOptionId('allow'),
        ),
        throwsA(isA<Object>()),
      );
      await expectLater(
        handle.setConfigOption('model', 'fast'),
        throwsA(isA<Object>()),
      );

      expectFull('Failed to load ACP session s-2');
      expectFull('Failed to cancel prompt turn');
      expectFull('Failed to respond to approval request');
      expectFull('Failed to set config option model');
      expect(diagnosticText(), isNot(contains(_token)));
    });

    test('список сессий', () async {
      await start(ProtocolPayloadPolicy.full, listFailure: _agentFailure);
      await connect();

      expectFull('Failed to list ACP sessions');
    });
  });
}

/// Обёртка над настоящим бэкендом: политика — ядра, отдельные операции падают
/// по запросу теста (`failures[<операция>]`).
final class _Backend implements AgentBackend {
  _Backend(this._inner);

  final AcpClientBackend _inner;
  final failures = <String, Object?>{};

  Future<T> _maybeFail<T>(String key, Future<T> Function() run) async {
    final failure = failures[key];
    if (failure != null) {
      throw failure;
    }
    return run();
  }

  @override
  ProtocolPayloadPolicy get protocolPayloads => _inner.protocolPayloads;

  @override
  Stream<ClientConnectionState> get connectionStates => _inner.connectionStates;

  @override
  Stream<AcpSession> get sessionChanges => _inner.sessionChanges;

  @override
  Stream<UsageNotification> get usageNotifications => _inner.usageNotifications;

  @override
  Stream<ProtocolFrame> get protocolFrames => _inner.protocolFrames;

  @override
  bool get traceAvailable => _inner.traceAvailable;

  @override
  void setFrameTrace(bool enabled) => _inner.setFrameTrace(enabled);

  @override
  int get generation => _inner.generation;

  @override
  Future<ClientConnectionState> connect(AcpTransport transport) =>
      _inner.connect(transport);

  @override
  Future<ClientConnectionState> reconnect(ReconnectCommand command) =>
      _inner.reconnect(command);

  @override
  Future<AcpSession> createSession(CreateSessionCommand command) =>
      _maybeFail('create', () => _inner.createSession(command));

  @override
  Future<SessionListPage> listSessions({String? cwd, String? cursor}) =>
      _maybeFail('list', () => _inner.listSessions(cwd: cwd, cursor: cursor));

  @override
  Future<AcpSession> loadSession(LoadSessionCommand command) =>
      _maybeFail('load', () => _inner.loadSession(command));

  @override
  Future<PromptTurn> sendPrompt(SendPromptCommand command) =>
      _inner.sendPrompt(command);

  @override
  Future<PromptTurn> cancelTurn(CancelTurnCommand command) =>
      _maybeFail('cancel', () => _inner.cancelTurn(command));

  @override
  Future<ApprovalRequest> respondToPermission(
    RespondToPermissionCommand command,
  ) => _maybeFail('respond', () => _inner.respondToPermission(command));

  @override
  Future<AcpSession> setSessionConfigOption(
    SetSessionConfigOptionCommand command,
  ) => _maybeFail('config', () => _inner.setSessionConfigOption(command));

  @override
  Future<UsageLedgerReply> requestUsageLedger({
    required SessionId sessionId,
    bool rebuild = false,
  }) => _inner.requestUsageLedger(sessionId: sessionId, rebuild: rebuild);
}

/// Хранилище снимка, которое падает на чтении или записи.
final class _ThrowingStore implements WorkspaceSnapshotStore {
  _ThrowingStore({this.readError, this.writeError});

  final Object? readError;
  final Object? writeError;

  @override
  Future<String?> read() async => readError == null ? null : throw readError!;

  @override
  Future<void> write(String snapshot) async {
    if (writeError != null) {
      throw writeError!;
    }
  }

  @override
  Future<void> clear() async {}
}
