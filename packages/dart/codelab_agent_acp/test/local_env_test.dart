import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcRequest;
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «Локальное окружение сессии от хоста» (задача 1.3
/// change `add-embedded-agent-mode`; D4; `agent-core-architecture` §13.1).
void main() {
  late ServerHarness h;
  late MemoryExecutionEnv files;

  setUp(() async {
    files = MemoryExecutionEnv(cwd: '/work/demo');
    await files.writeText('/work/demo/README.md', '# foo\n');
  });

  Map<String, Object?> toolStep(String id, String name, Object arguments) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': arguments},
      },
    ],
  };

  Map<String, Object?> text(String text) => {
    'reply': [
      {'text': text},
    ],
  };

  /// Методы запросов агента к клиенту в порядке прихода.
  List<String> agentRequests() => [
    for (final m in h.client.received)
      if (m is JsonRpcRequest) m.method,
  ];

  Map<String, Object?> lastUpdateOf(String toolCallId) => TestClient.updates(
    h.client.received,
  ).lastWhere((u) => u['toolCallId'] == toolCallId);

  Future<String> ready({
    required List<Map<String, Object?>> steps,
    ExecutionEnv Function(String cwd)? localEnv,
    String? mode,
  }) async {
    h = await ServerHarness.start(steps: steps, localEnv: localEnv);
    await h.initialize();
    final sessionId = await h.newSession(cwd: '/work/demo');
    if (mode != null) {
      await h.client.request('session/set_mode', {
        'sessionId': sessionId,
        'modeId': mode,
      });
    }
    return sessionId;
  }

  tearDown(() => h.dispose());

  test(
    'with localEnv read and exec run on the host: no fs/* or terminal/*',
    () async {
      final env = _ExecEnv(files);
      final sessionId = await ready(
        mode: 'bypass',
        localEnv: (_) => env,
        steps: [
          toolStep('call_1', 'read', {'path': 'README.md'}),
          toolStep('call_2', 'exec', {'command': 'echo hi'}),
          text('Done'),
        ],
      );

      final response = await h.prompt(sessionId, 'Read and run');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      expect(
        agentRequests().where(
          (m) => m.startsWith('fs/') || m.startsWith('terminal/'),
        ),
        isEmpty,
      );
      expect(env.commands, ['echo hi']);
      expect(lastUpdateOf('call_1')['status'], 'completed');
      expect(lastUpdateOf('call_2')['status'], 'completed');
    },
  );

  test('with localEnv a write in standard still asks the client', () async {
    final sessionId = await ready(
      localEnv: (_) => files,
      steps: [
        toolStep('call_w', 'write', {'path': 'new.txt', 'content': 'x'}),
        text('Done'),
      ],
    );
    h.client.handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    };

    final before = await files.readText('/work/demo/new.txt');
    final response = await h.prompt(sessionId, 'Write new.txt');

    expect(before, isA<Err<String, FileError>>());
    expect(response.resultMap, {'stopReason': 'end_turn'});
    final permission = h.client.received
        .whereType<JsonRpcRequest>()
        .singleWhere((r) => r.method == 'session/request_permission');
    expect(
      ((permission.params! as Map)['toolCall']! as Map)['toolCallId'],
      'call_w',
    );
    expect(agentRequests().where((m) => m.startsWith('fs/')), isEmpty);
    expect(
      await files.readText('/work/demo/new.txt'),
      const Ok<String, FileError>('x'),
    );
  });

  test('with localEnv a rejected write does not touch the file', () async {
    final sessionId = await ready(
      localEnv: (_) => files,
      steps: [
        toolStep('call_w', 'write', {'path': 'new.txt', 'content': 'x'}),
        text('Understood'),
      ],
    );
    h.client.handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
    };

    await h.prompt(sessionId, 'Write new.txt');

    expect(lastUpdateOf('call_w')['status'], 'failed');
    expect(
      await files.readText('/work/demo/new.txt'),
      isA<Err<String, FileError>>(),
    );
  });

  test('with localEnv a missing cwd is -32602 in session/new', () async {
    h = await ServerHarness.start(localEnv: (_) => files);
    await h.initialize();

    final missing = await h.client.request('session/new', {
      'cwd': '/work/elsewhere',
      'mcpServers': <Object?>[],
    });

    expect(missing.errorCode, -32602);
    expect(missing.error?.message, contains('cwd does not exist'));
  });

  test('with localEnv a missing cwd is -32602 in session/load', () async {
    h = await ServerHarness.start(localEnv: (_) => files);
    await h.initialize();
    final sessionId = await h.newSession();

    final missing = await h.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/elsewhere',
      'mcpServers': <Object?>[],
    });

    expect(missing.errorCode, -32602);
    expect(missing.error?.message, contains('cwd does not exist'));
  });

  test('with localEnv exec in standard asks and reject runs nothing', () async {
    final env = _ExecEnv(files);
    final sessionId = await ready(
      localEnv: (_) => env,
      steps: [
        toolStep('call_x', 'exec', {'command': 'touch evil'}),
        text('Understood'),
      ],
    );
    h.client.handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
    };

    await h.prompt(sessionId, 'Run it');

    final permission = h.client.received
        .whereType<JsonRpcRequest>()
        .singleWhere((r) => r.method == 'session/request_permission');
    expect(
      ((permission.params! as Map)['toolCall']! as Map)['toolCallId'],
      'call_x',
    );
    expect(env.commands, isEmpty);
    expect(lastUpdateOf('call_x')['status'], 'failed');
  });

  test('with localEnv exec in standard runs only after allow_once', () async {
    final env = _ExecEnv(files);
    final sessionId = await ready(
      localEnv: (_) => env,
      steps: [
        toolStep('call_x', 'exec', {'command': 'echo hi'}),
        text('Done'),
      ],
    );
    // Снимок состояния env в момент запроса разрешения: команда ещё не
    // должна была стартовать (порядок «сначала вопрос, потом процесс»).
    List<String>? commandsAtRequest;
    h.client.handlers['session/request_permission'] = (_) {
      commandsAtRequest = List.of(env.commands);
      return {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      };
    };

    await h.prompt(sessionId, 'Run it');

    final permission = h.client.received
        .whereType<JsonRpcRequest>()
        .singleWhere((r) => r.method == 'session/request_permission');
    expect(
      ((permission.params! as Map)['toolCall']! as Map)['toolCallId'],
      'call_x',
    );
    expect(commandsAtRequest, isEmpty);
    expect(env.commands, ['echo hi']);
    expect(lastUpdateOf('call_x')['status'], 'completed');
  });

  test('localEnv does not change the initialize response', () async {
    h = await ServerHarness.start(localEnv: (_) => files);
    final withEnv = (await h.initialize()).resultMap;
    await h.dispose();
    h = await ServerHarness.start();
    final without = (await h.initialize()).resultMap;

    expect(withEnv, without);
  });

  test(
    'without localEnv read goes to the client as fs/read_text_file',
    () async {
      final sessionId = await ready(
        steps: [
          toolStep('call_1', 'read', {'path': 'README.md'}),
          text('Done'),
        ],
      );
      h.client.serveFiles(files);

      await h.prompt(sessionId, 'Read README.md');

      expect(agentRequests(), contains('fs/read_text_file'));
    },
  );

  group('fileListing', () {
    ModelCatalog? noModels;

    AcpAgentServer build(ExecutionEnv Function(String cwd)? localEnv) {
      final clock = FakeClock();
      final logger = RecordingLogger();
      final core = buildAgentCore(
        profile: HostProfile.of('agent-serve'),
        services: AgentCoreServices(
          baseEnv: HostEnv(MemoryExecutionEnv(cwd: '/', clock: clock)),
          gate: const UnusedGate(),
          logger: logger,
          clock: clock,
          ids: SequentialIdGenerator(),
          sessions: JournalStore(),
          models: noModels,
        ),
        config: CoreConfig(defaultModel: scriptedModel),
        streamFunction: (model, context, {cancel}) =>
            throw StateError('no model calls'),
      );
      return AcpAgentServer(
        core: core,
        config: AcpServerConfig(agentInfo: testAgentInfo, localEnv: localEnv),
        logger: logger,
        clock: clock,
      );
    }

    test('localEnv with listing replaces localListing', () {
      expect(() => build((_) => files), returnsNormally);
    });

    test('localEnv without listing is HostWiringException', () {
      expect(
        () => build((_) => _NoListingEnv(files)),
        throwsA(isA<HostWiringException>()),
      );
    });
  });
}

/// Env хоста с рабочим `exec`: `MemoryExecutionEnv` оболочки не имеет.
final class _ExecEnv implements ExecutionEnv, DirectoryListing {
  _ExecEnv(this._inner);

  final MemoryExecutionEnv _inner;

  /// Выполненные команды.
  final commands = <String>[];

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
  ) async {
    commands.add(command);
    return const Ok(
      ExecResult(
        exitCode: 0,
        output: 'hi\n',
        truncated: false,
        duration: Duration.zero,
      ),
    );
  }
}

/// Env без `DirectoryListing`: хост не умеет листинг.
final class _NoListingEnv implements ExecutionEnv {
  _NoListingEnv(this._inner);

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
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}
