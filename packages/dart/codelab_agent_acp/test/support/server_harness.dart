import 'dart:async';
import 'dart:collection';

import 'package:acp_protocol/acp_protocol.dart' hide SessionId;
import 'package:acp_testing/acp_testing.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Модель тестов сервера: провайдер `scripted`, как в фикстурах (§14.7).
final scriptedModel = ModelRef(
  provider: 'scripted',
  id: 'scripted-1',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

/// `agentInfo` сервера в тестах (§13.2).
const testAgentInfo = Implementation(
  name: 'codelab-agent',
  title: 'CodeLab Agent',
  version: '0.1.0',
);

/// Сервер на агентском конце `InProcessAcpLink` и клиент на другом.
///
/// Ядро собирается так же, как хост собрал бы его для `agent-serve`:
/// журнал — [JournalStore] (постоянное хранилище для сборки, в памяти для
/// теста), env хоста — [HostEnv], сессии получают env соединения.
final class ServerHarness {
  ServerHarness._(this.core, this.server, this.client, this.logger, this.store);

  static Future<ServerHarness> start({
    String profile = 'agent-serve',
    Map<HostCapability, CapabilityState> narrow = const {},
    List<Map<String, Object?>> steps = const [],
    ExecutionEnv Function(String cwd)? localListing,
    JournalStore? sessions,
  }) async {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final store = sessions ?? JournalStore();
    final model = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    final core = buildAgentCore(
      profile: HostProfile.of(profile).narrowed({
        if (localListing == null)
          HostCapability.fileListing: const CapabilityOff(
            'клиент не на этой машине',
          ),
        ...narrow,
      }),
      services: AgentCoreServices(
        baseEnv: HostEnv(MemoryExecutionEnv(cwd: '/', clock: clock)),
        gate: const UnusedGate(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
      ),
      config: CoreConfig(defaultModel: scriptedModel),
      streamFunction: model.call,
    );
    final server = AcpAgentServer(
      core: core,
      config: AcpServerConfig(
        agentInfo: testAgentInfo,
        localListing: localListing,
      ),
      logger: logger,
      clock: clock,
    );
    final link = InProcessAcpLink();
    unawaited(server.serve(link.agent));
    final client = TestClient(link.client);
    await client.start();
    return ServerHarness._(core, server, client, logger, store);
  }

  final BuiltAgentCore core;
  final AcpAgentServer server;
  final TestClient client;
  final RecordingLogger logger;
  final JournalStore store;

  /// `initialize` с fs и terminal, как codelab-app.
  Future<JsonRpcResponse> initialize({Object? clientCapabilities}) =>
      client.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities':
            clientCapabilities ??
            {
              'fs': {'readTextFile': true, 'writeTextFile': true},
              'terminal': true,
            },
        'clientInfo': {'name': 'codelab-app', 'version': '0.4.0'},
      });

  Future<void> dispose() => server.shutdown(grace: Duration.zero);
}

/// Клиент теста над концом транспорта: запросы с ожиданием ответа по id и
/// очередь остальных входящих кадров.
final class TestClient {
  TestClient(this.transport);

  final AcpTransport transport;

  /// Все кадры агента в порядке прихода, включая ответы.
  final received = <JsonRpcMessage>[];
  final _pending = <JsonRpcId, Completer<JsonRpcResponse>>{};
  final _frames = Queue<JsonRpcMessage>();
  final _waiting = Queue<Completer<JsonRpcMessage>>();
  var _nextId = 100;

  Future<void> start() async {
    transport.inbound.listen(_onMessage);
    await transport.start();
  }

  void _onMessage(JsonRpcMessage message) {
    received.add(message);
    if (message case JsonRpcResponse(:final id)) {
      final pending = _pending.remove(id);
      if (pending != null) {
        pending.complete(message);
        return;
      }
    }
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(message);
    } else {
      _frames.add(message);
    }
  }

  /// Запрос с новым числовым id; ответ — по этому id.
  Future<JsonRpcResponse> request(String method, [Object? params]) {
    final id = JsonRpcId.integer(_nextId++);
    return send(
      JsonRpcMessage.request(id: id, method: method, params: params)
          as JsonRpcRequest,
    );
  }

  /// Отправляет запрос как есть и ждёт ответ на его id.
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    final completer = Completer<JsonRpcResponse>();
    _pending[request.id] = completer;
    await transport.send(request);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  Future<void> notify(String method, [Object? params]) => transport.send(
    JsonRpcMessage.notification(method: method, params: params),
  );

  Future<void> raw(JsonRpcMessage message) => transport.send(message);

  /// Следующий кадр агента, кроме ответов на запросы этого клиента.
  Future<JsonRpcMessage> next() {
    if (_frames.isNotEmpty) {
      return Future.value(_frames.removeFirst());
    }
    final completer = Completer<JsonRpcMessage>();
    _waiting.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Кадры, пришедшие к этому моменту, без ожидания.
  Future<List<JsonRpcMessage>> drain() async {
    await pumpEventQueue();
    final all = [..._frames];
    _frames.clear();
    return all;
  }
}

/// `SessionStore` с журналом в памяти, который сборка считает постоянным:
/// так тест проверяет `agent-serve` с включённой `sessionPersistence`.
final class JournalStore implements SessionStore {
  final inner = MemorySessionStore();

  @override
  Future<void> create(SessionHeader header) => inner.create(header);

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) => inner.append(id, record, durable: durable);

  @override
  Future<void> flush(SessionId id) => inner.flush(id);

  @override
  Future<SessionSnapshot> open(SessionId id) => inner.open(id);

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => inner.close(id);
}

/// Env хоста для сборки: сессии сервера его не используют — они получают env
/// соединения (design.md, D5), но сборка проверяет, что `shellExec` и
/// `fileListing` есть у хоста.
final class HostEnv implements ExecutionEnv, DirectoryListing {
  HostEnv(this._inner);

  final MemoryExecutionEnv _inner;

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      _inner.listDir(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}

/// Gate хоста для сборки: сессии сервера спрашивают через
/// `AcpPermissionGate` соединения.
final class UnusedGate implements PermissionGate {
  const UnusedGate();

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) => throw StateError('the server must use AcpPermissionGate');
}

/// Тело ответа или ошибка JSON-RPC — для коротких проверок.
extension ResponseParts on JsonRpcResponse {
  Map<String, Object?> get resultMap => result! as Map<String, Object?>;

  int? get errorCode => error?.code;
}
