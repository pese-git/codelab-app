import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/http.dart' as web;
import 'package:test/test.dart';

import 'support/acp_client.dart';

/// Встроенный агент отвечает на ход в памяти процесса (embedded-agent
/// «Сборка встроенного агента», «Локальное исполнение и containment»,
/// «Разрешения во встроенном режиме»; design.md change
/// `add-embedded-agent-mode`, D2, D4).
///
/// Агент открывается `scriptedEmbeddedAgentOpener` со сценарием модели и
/// временным `CODELAB_HOME`; клиент — `TestAcpClient` на клиентском конце пары
/// `InProcessAcpLink`. Сети и процессов, кроме `exec` сценария, нет.
void main() {
  late Directory temp;
  late Directory project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_embedded_');
    project = Directory('${temp.path}/project')..createSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  Map<String, Object?> text(String text) => {
    'reply': [
      {'text': text},
    ],
  };

  Map<String, Object?> toolStep(String id, String name, Object arguments) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': arguments},
      },
    ],
  };

  /// Открывает агента, инициализирует соединение и создаёт сессию в проекте.
  Future<String> open(
    List<Map<String, Object?>> steps, {
    String hostProfile = 'embedded-cli',
    String? permissionMode,
  }) async {
    final opener = scriptedEmbeddedAgentOpener(
      llm: {'steps': steps},
      codelabHome: '${temp.path}/home',
      permissionMode: permissionMode,
      logger: logger,
    );
    agent = await opener(cwd: project.path, hostProfile: hostProfile);
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();
    await client!.initialize();
    return client!.newSession(project.path);
  }

  test('a turn through the embedded agent: hello and end_turn', () async {
    final opener = scriptedEmbeddedAgentOpener(
      llm: {
        'steps': [text('hello')],
      },
      codelabHome: '${temp.path}/home',
      logger: logger,
    );
    agent = await opener(cwd: project.path, hostProfile: 'embedded-cli');
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();

    final init = await client!.initialize();
    final sessionId = await client!.newSession(project.path);
    final stop = await client!.prompt(sessionId, 'hi');

    expect((init['agentInfo']! as Map)['name'], 'codelab-agent');
    expect((init['agentInfo']! as Map)['title'], 'CodeLab Agent');
    expect(stop, 'end_turn');
    expect(client!.agentText, 'hello');
    expect(logger.eventsOf('host.plan'), hasLength(1));
  });

  test('embedded profiles are assembled by their own names', () async {
    for (final name in ['embedded-cli', 'embedded-app-desktop']) {
      final sessionId = await open([text('ok')], hostProfile: name);

      expect(await client!.prompt(sessionId, 'hi'), 'end_turn', reason: name);
      expect(
        logger.eventsOf('host.plan').last.fields['profile'],
        name,
        reason: name,
      );
      await client!.close();
      await agent!.dispose();
    }
    agent = client = null;
  });

  group('local execution (D4)', () {
    test('read and exec run on the host: no fs/* and terminal/*', () async {
      File('${project.path}/README.md').writeAsStringSync('# marker-readme\n');
      final sessionId = await open(permissionMode: 'bypass', [
        toolStep('call_r', 'read', {'path': 'README.md'}),
        toolStep('call_e', 'exec', {'command': 'echo marker-exec'}),
        text('done'),
      ]);

      final stop = await client!.prompt(sessionId, 'read and run');

      expect(stop, 'end_turn');
      expect(
        client!.agentRequests.where(
          (m) => m.startsWith('fs/') || m.startsWith('terminal/'),
        ),
        isEmpty,
      );
      expect(client!.lastUpdateOf('call_r')['status'], 'completed');
      expect('${client!.lastUpdateOf('call_r')}', contains('marker-readme'));
      expect(client!.lastUpdateOf('call_e')['status'], 'completed');
      expect('${client!.lastUpdateOf('call_e')}', contains('marker-exec'));
    });

    test('a path outside the project is outsideWorkspace and nothing is '
        'read', () async {
      File('${temp.path}/outside.txt').writeAsStringSync('marker-secret');
      final sessionId = await open(permissionMode: 'bypass', [
        toolStep('call_1', 'read', {'path': '../outside.txt'}),
        text('next'),
      ]);

      final stop = await client!.prompt(sessionId, 'read outside');

      // Ход продолжается: ошибка инструмента (`FileErrorCode.outsideWorkspace`)
      // — результат для модели, текст — «Path is outside the workspace».
      expect(stop, 'end_turn');
      final update = client!.lastUpdateOf('call_1');
      expect(update['status'], 'failed');
      expect('$update', isNot(contains('marker-secret')));
      expect('$update', contains('outside the workspace'));
    });

    test(
      'a symlink pointing outside the project is outside the workspace',
      () async {
        File('${temp.path}/outside.txt').writeAsStringSync('marker-secret');
        Link('${project.path}/link.txt').createSync('${temp.path}/outside.txt');
        final sessionId = await open(permissionMode: 'bypass', [
          toolStep('call_1', 'read', {'path': 'link.txt'}),
          text('next'),
        ]);

        final stop = await client!.prompt(sessionId, 'read the link');

        expect(stop, 'end_turn');
        final update = client!.lastUpdateOf('call_1');
        expect(update['status'], 'failed');
        expect('$update', isNot(contains('marker-secret')));
        expect('$update', contains('outside the workspace'));
      },
    );
  });

  group('local execution: containment of write and exec (ENV-2)', () {
    test('write ../x and exec with cwd outside are refused', () async {
      final sessionId = await open(permissionMode: 'bypass', [
        toolStep('call_w', 'write', {'path': '../x.txt', 'content': 'x'}),
        toolStep('call_e', 'exec', {'command': 'echo hi', 'cwd': '..'}),
        text('next'),
      ]);

      final stop = await client!.prompt(sessionId, 'escape');

      expect(stop, 'end_turn');
      for (final id in ['call_w', 'call_e']) {
        final update = client!.lastUpdateOf(id);
        expect(update['status'], 'failed', reason: id);
        expect('$update', contains('outside the workspace'), reason: id);
      }
      expect(File('${temp.path}/x.txt').existsSync(), isFalse);
    });

    test('profile agent-serve sends files to the client: fs/read_text_file '
        'and no local read', () async {
      File('${project.path}/README.md').writeAsStringSync('local-content');
      final sessionId = await open(
        permissionMode: 'bypass',
        hostProfile: 'agent-serve',
        [
          toolStep('call_r', 'read', {'path': 'README.md'}),
          text('done'),
        ],
      );
      client!.handlers['fs/read_text_file'] = (_) => {'content': 'from-client'};

      final stop = await client!.prompt(sessionId, 'read');

      expect(stop, 'end_turn');
      expect(client!.agentRequests, contains('fs/read_text_file'));
      expect('${client!.lastUpdateOf('call_r')}', contains('from-client'));
    });
  });

  group('permissions (PERM-4)', () {
    test(
      'reject_once leaves the file unchanged and the turn goes on',
      () async {
        final sessionId = await open([
          toolStep('call_w', 'write', {'path': 'new.txt', 'content': 'x'}),
          text('understood'),
        ]);
        client!.handlers['session/request_permission'] = (_) => {
          'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
        };

        final stop = await client!.prompt(sessionId, 'write new.txt');

        expect(stop, 'end_turn');
        expect(File('${project.path}/new.txt').existsSync(), isFalse);
        expect(client!.lastUpdateOf('call_w')['status'], 'failed');
        expect(client!.agentRequests, ['session/request_permission']);
      },
    );

    test('allow_once writes the file and the next call asks again', () async {
      final sessionId = await open([
        toolStep('call_1', 'write', {'path': 'a.txt', 'content': 'a'}),
        toolStep('call_2', 'write', {'path': 'b.txt', 'content': 'b'}),
        text('done'),
      ]);
      final asked = <String>[];
      client!.handlers['session/request_permission'] = (request) {
        final toolCall = (request.params! as Map)['toolCall']! as Map;
        asked.add(toolCall['toolCallId']! as String);
        return {
          'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
        };
      };

      final stop = await client!.prompt(sessionId, 'write both');

      expect(stop, 'end_turn');
      expect(File('${project.path}/a.txt').readAsStringSync(), 'a');
      expect(File('${project.path}/b.txt').readAsStringSync(), 'b');
      expect(asked, ['call_1', 'call_2']);
    });
  });

  test('dispose with a pending permission request ends the turn, completes '
      'closed and a late client answer changes nothing', () async {
    final sessionId = await open([
      toolStep('call_w', 'write', {'path': 'late.txt', 'content': 'x'}),
      text('never'),
    ]);
    final asked = Completer<void>();
    final answer = Completer<Object?>();
    client!.handlers['session/request_permission'] = (_) {
      asked.complete();
      return answer.future;
    };
    final turn = client!
        .call('session/prompt', {
          'sessionId': sessionId,
          'prompt': [
            {'type': 'text', 'text': 'write'},
          ],
        })
        .then<Object?>((r) => r, onError: (Object e) => e);
    await asked.future;

    await agent!.dispose();
    await agent!.closed;
    final outcome = await turn.timeout(const Duration(seconds: 10));
    answer.complete({
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    });
    await pumpEventQueue();

    // Ход закончился отказом/отменой, а не записью файла.
    expect(
      outcome,
      isNot(
        isA<Map<String, Object?>>().having(
          (m) => m['stopReason'],
          'stopReason',
          'end_turn',
        ),
      ),
    );
    expect(File('${project.path}/late.txt').existsSync(), isFalse);
    // Поздний ответ ушёл в закрытую пару и был отброшен ровно один раз.
    expect(client!.droppedResponses, 1);
    agent = null;
  });

  test('a failing dispose step does not leave closed pending', () async {
    final failing = _ThrowingCloseClient();
    final embedded = await createEmbeddedAgent(
      config: _config(),
      services: _services(logger, failing),
    );

    await embedded.dispose();
    await embedded.dispose();

    await embedded.closed.timeout(const Duration(seconds: 10));
    expect(failing.closeCalls, 1);
    expect(logger.eventsOf('embedded.agent.dispose_failed'), hasLength(1));
    // Текст исключения (может содержать данные) в запись не попадает.
    expect(
      logger.eventsOf('embedded.agent.dispose_failed').single.error,
      isNull,
    );
  });

  test('createEmbeddedAgent reports a non-embedded profile through the '
      'Future', () async {
    final future = createEmbeddedAgent(
      config: _config(profile: 'agent-serve'),
      services: _services(logger, _ThrowingCloseClient()),
    );

    await expectLater(future, throwsA(isA<HostWiringException>()));
  });

  test(
    'a failing server constructor releases the built core and http',
    () async {
      final http = _CountingCloseClient();
      final base = _services(logger, http);
      final services = EmbeddedHostServices(
        baseEnv: base.baseEnv,
        // Без DirectoryListing при включённой fileListing конструктор
        // AcpAgentServer бросает HostWiringException после buildAgentCore.
        localEnv: (cwd) => _NoListingEnv(),
        sessions: base.sessions,
        secrets: base.secrets,
        http: http,
        closeHttpOnDispose: true,
        logger: logger,
        clock: base.clock,
        ids: base.ids,
        random: base.random,
        platform: 'test',
      );

      final future = createEmbeddedAgent(config: _config(), services: services);

      await expectLater(future, throwsA(isA<HostWiringException>()));
      expect(http.closeCalls, 1);
    },
  );

  test('dispose is idempotent and completes closed', () async {
    await open([text('ok')]);
    final embedded = agent!;

    await embedded.dispose();
    await embedded.dispose();

    await embedded.closed;
    agent = null;
  });

  test('Logger and LogLevel come from the main barrel', () {
    // Адаптер логгера хоста (app, CLI) строится на реэкспорте, без импорта
    // ядра клиентом (D2).
    expect(LogLevel.values, isNotEmpty);
    expect(RecordingLogger(), isA<Logger>());
  });
}

final class _CountingCloseClient extends web.BaseClient {
  int closeCalls = 0;

  @override
  Future<web.StreamedResponse> send(web.BaseRequest request) =>
      throw StateError('no network');

  @override
  void close() => closeCalls++;
}

/// Окружение без `DirectoryListing`. Конструктор сервера проверяет только тип
/// значения, методы не вызываются, поэтому `noSuchMethod` достаточно.
final class _NoListingEnv implements ExecutionEnv {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _ThrowingCloseClient extends web.BaseClient {
  int closeCalls = 0;

  @override
  Future<web.StreamedResponse> send(web.BaseRequest request) =>
      throw StateError('no network');

  @override
  void close() {
    closeCalls++;
    throw StateError('close failed: secret-text');
  }
}

EmbeddedAgentConfig _config({String profile = 'embedded-cli'}) =>
    EmbeddedAgentConfig(
      hostProfile: profile,
      core: CoreConfig(
        defaultModel: ModelRef(
          provider: 'p',
          id: 'm',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://p.invalid/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
      ),
      host: const HostSettings(
        profileNarrowing: {
          'embedded-cli': {
            HostCapability.shellExec: CapabilityOff('test'),
            HostCapability.sessionPersistence: CapabilityOff('test'),
          },
        },
      ),
    );

EmbeddedHostServices _services(Logger logger, web.Client http) {
  final clock = FakeClock();
  return EmbeddedHostServices(
    baseEnv: MemoryExecutionEnv(cwd: '/t', clock: clock),
    localEnv: (cwd) => MemoryExecutionEnv(cwd: cwd, clock: clock),
    sessions: MemorySessionStore(),
    secrets: SecretResolver(
      store: MemorySecretStore(),
      environment: const {},
      logger: logger,
    ),
    http: http,
    closeHttpOnDispose: true,
    logger: logger,
    clock: clock,
    ids: SequentialIdGenerator(),
    random: Random(0),
    platform: 'test',
  );
}
