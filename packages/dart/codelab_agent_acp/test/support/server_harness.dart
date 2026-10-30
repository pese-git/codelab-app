import 'dart:async';
import 'dart:collection';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' hide SessionId;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
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
  ServerHarness._(
    this.core,
    this.server,
    this.client,
    this.logger,
    this.store,
    this.clock,
    this.model,
    this.toolsSeen,
  );

  /// [mcp] — коннектор MCP для `AgentCoreServices.mcp` (design.md change
  /// `add-agent-mcp-client`, D11); без него capability `mcp` выключена и
  /// `mcpCapabilities.http` — `false`.
  ///
  /// [projectFiles] — порт файлов проекта для `AgentCoreServices` (design.md
  /// change `add-agent-project-files`, D1); без него сессии без файлов.
  ///
  /// [slow] — агентский конец отдаёт каждый кадр с задержкой: проверка
  /// порядка «уведомления → ответ» на медленном транспорте (ACP-3).
  static Future<ServerHarness> start({
    String profile = 'agent-serve',
    Map<HostCapability, CapabilityState> narrow = const {},
    List<Map<String, Object?>> steps = const [],
    ExecutionEnv Function(String cwd)? localListing,
    JournalStore? sessions,
    TurnBudget budget = const TurnBudget(),
    bool slow = false,
    ModelCatalog? models,
    Duration detachGrace = const Duration(seconds: 30),
    McpConnector Function(Clock clock)? mcp,
    ProjectFilesSource? projectFiles,
  }) async {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final store = sessions ?? JournalStore();
    final model = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    // Имена инструментов каждого запроса к модели: так тесты MCP видят,
    // что получила модель, не зная точного состава встроенных инструментов.
    final toolsSeen = <List<String>>[];
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
        models: models,
        mcp: mcp?.call(clock),
        projectFiles: projectFiles,
      ),
      config: CoreConfig(defaultModel: scriptedModel, budget: budget),
      streamFunction: (model_, context, {cancel}) {
        toolsSeen.add([for (final tool in context.tools) tool.name]);
        return model.call(model_, context, cancel: cancel);
      },
    );
    final server = AcpAgentServer(
      core: core,
      config: AcpServerConfig(
        agentInfo: testAgentInfo,
        localListing: localListing,
        detachGrace: detachGrace,
      ),
      logger: logger,
      clock: clock,
    );
    final link = InProcessAcpLink();
    unawaited(server.serve(slow ? SlowTransport(link.agent) : link.agent));
    final client = TestClient(link.client);
    await client.start();
    return ServerHarness._(
      core,
      server,
      client,
      logger,
      store,
      clock,
      model,
      toolsSeen,
    );
  }

  final BuiltAgentCore core;
  final AcpAgentServer server;
  final TestClient client;
  final RecordingLogger logger;
  final JournalStore store;
  final FakeClock clock;
  final ScriptedStreamFunction model;

  /// Имена инструментов в каждом запросе к модели, по порядку запросов.
  final List<List<String>> toolsSeen;

  /// Новое соединение к тому же серверу, уже после `initialize`.
  Future<TestClient> connect() async {
    final link = InProcessAcpLink();
    unawaited(server.serve(link.agent));
    final other = TestClient(link.client);
    await other.start();
    await other.request('initialize', initializeParams());
    return other;
  }

  /// `initialize` с fs и terminal, как codelab-app.
  Future<JsonRpcResponse> initialize({Object? clientCapabilities}) =>
      client.request(
        'initialize',
        initializeParams(clientCapabilities: clientCapabilities),
      );

  static Map<String, Object?> initializeParams({Object? clientCapabilities}) =>
      {
        'protocolVersion': 1,
        'clientCapabilities':
            clientCapabilities ??
            {
              'fs': {'readTextFile': true, 'writeTextFile': true},
              'terminal': true,
            },
        'clientInfo': {'name': 'codelab-app', 'version': '0.4.0'},
      };

  /// `session/new` в `/work/demo`; возвращает `sessionId`, уведомление
  /// `available_commands_update` после ответа снимается из очереди.
  Future<String> newSession({String cwd = '/work/demo'}) async {
    final response = await client.request('session/new', {
      'cwd': cwd,
      'mcpServers': <Object?>[],
    });
    await client.next();
    return response.resultMap['sessionId']! as String;
  }

  /// `session/prompt` с одним текстовым блоком.
  Future<JsonRpcResponse> prompt(String sessionId, String text) =>
      client.request('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': text},
        ],
      });

  Future<void> dispose() => server.shutdown(grace: Duration.zero);
}

/// Транспорт, который отправляет каждый кадр после паузы в цикле событий.
final class SlowTransport implements AcpTransport {
  SlowTransport(this._inner);

  final AcpTransport _inner;

  @override
  Stream<JsonRpcMessage> get inbound => _inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => _inner.events;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> send(JsonRpcMessage message) async {
    await Future<void>.delayed(Duration.zero);
    await _inner.send(message);
  }

  @override
  Future<void> close({Duration? timeout}) => _inner.close(timeout: timeout);
}

/// Клиент теста над концом транспорта: запросы с ожиданием ответа по id и
/// очередь остальных входящих кадров.
final class TestClient {
  TestClient(this.transport);

  final AcpTransport transport;

  /// Ответы на запросы агента по методу; запрос без обработчика попадает в
  /// очередь [next], и тест отвечает [respond].
  final handlers = <String, FutureOr<Object?> Function(JsonRpcRequest)>{};

  /// Все кадры агента в порядке прихода, включая ответы.
  final received = <JsonRpcMessage>[];
  final _pending = <JsonRpcId, Completer<JsonRpcResponse>>{};
  final _frames = Queue<JsonRpcMessage>();
  final _waiting = Queue<Completer<JsonRpcMessage>>();
  var _nextId = 100;

  final _closed = Completer<void>();

  /// Агент закрыл соединение: входящий поток завершён.
  Future<void> get closed => _closed.future;

  Future<void> start() async {
    transport.inbound.listen(_onMessage, onDone: _closed.complete);
    await transport.start();
  }

  void _onMessage(JsonRpcMessage message) {
    received.add(message);
    if (message case JsonRpcRequest(
      :final method,
    ) when handlers.containsKey(method)) {
      unawaited(_answer(message, handlers[method]!));
      return;
    }
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

  /// Ответ на запрос агента.
  Future<void> respond(JsonRpcRequest request, Object? result) =>
      transport.send(JsonRpcMessage.response(id: request.id, result: result));

  Future<void> _answer(
    JsonRpcRequest request,
    FutureOr<Object?> Function(JsonRpcRequest) handler,
  ) async {
    JsonRpcMessage response;
    try {
      response = JsonRpcMessage.response(
        id: request.id,
        result: await handler(request),
      );
    } on JsonRpcError catch (error) {
      // Обработчик бросает JsonRpcError, чтобы ответить ошибкой.
      response = JsonRpcMessage.response(id: request.id, error: error);
    }
    await transport.send(response);
  }

  /// Файлы клиента в памяти для `fs/*` (как codelab-app по рабочей папке).
  void serveFiles(MemoryExecutionEnv files) {
    handlers['fs/read_text_file'] = (request) async {
      final params = request.params! as Map<String, Object?>;
      final read = await files.readText(
        params['path']! as String,
        line: params['line'] as int?,
        limit: params['limit'] as int?,
      );
      return switch (read) {
        Ok(:final value) => {'content': value},
        Err(:final error) => throw JsonRpcError(
          code: error.code == FileErrorCode.notFound ? -32002 : -32603,
          message: '${error.code.name}: ${error.path}',
        ),
      };
    };
    handlers['fs/write_text_file'] = (request) async {
      final params = request.params! as Map<String, Object?>;
      await files.writeText(
        params['path']! as String,
        params['content']! as String,
      );
      return <String, Object?>{};
    };
  }

  /// Уведомления `session/update` из [frames] — их `update`.
  static List<Map<String, Object?>> updates(
    Iterable<JsonRpcMessage> frames,
  ) => [
    for (final frame in frames)
      if (frame case JsonRpcNotification(
        method: 'session/update',
        :final params,
      ))
        (params! as Map<String, Object?>)['update']! as Map<String, Object?>,
  ];

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

/// Коннектор MCP для тестов: записывает запросы ядра и ничего не подключает
/// (design.md change `add-agent-mcp-client`, D11).
///
/// Для чего: проверить отображение `acp.McpServer` в `McpServerConfig` и
/// вызовы `replaceServers`, не поднимая клиент MCP.
final class SpyMcpConnector implements McpConnector {
  SpyMcpConnector({this.transports = const {'stdio', 'http'}});

  /// Если задан, `replaceServers` ждёт его завершения (медленное
  /// подключение серверов).
  Completer<void>? replaceGate;

  @override
  final Set<String> transports;

  /// Запросы `connect` в порядке прихода.
  final requests = <McpConnectRequest>[];

  /// Серверы сессий, уже закрытых или заменённых, — для проверки порядка.
  final sessions = <SpyMcpSession>[];

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    requests.add(request);
    final session = SpyMcpSession(this);
    sessions.add(session);
    return session;
  }
}

/// Подключённые серверы одной сессии для [SpyMcpConnector].
final class SpyMcpSession implements McpSessionTools {
  SpyMcpSession(this._owner);

  final SpyMcpConnector _owner;

  /// Аргументы каждого вызова `replaceServers`.
  final replaced = <List<McpServerConfig>>[];
  var closed = false;

  @override
  List<AgentTool> get tools => const [];

  @override
  List<McpServerSummary> get servers => const [];

  @override
  McpToolsUpdate? takeUpdate() => null;

  @override
  Future<void> replaceServers(List<McpServerConfig> servers) async {
    replaced.add(servers);
    if (_owner.replaceGate case final gate?) {
      await gate.future;
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
