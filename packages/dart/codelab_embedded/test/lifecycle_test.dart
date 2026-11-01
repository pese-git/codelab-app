import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart' show AcpAgentServer;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:codelab_embedded/src/assemble.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/http.dart' as web;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';
import 'support/memory_host.dart';

/// Жизненный цикл встроенного агента (embedded-agent «Жизненный цикл
/// встроенного агента», сценарии «dispose при ожидающем разрешении», «Клиент
/// закрыл соединение», «Ошибка внутри агента»; design.md change
/// `add-embedded-agent-mode`, D6).
///
/// Синхронизация — событиями (Completer, `agent.closed`, события транспорта),
/// а не `Future.delayed`. Временный `CODELAB_HOME`, сети нет (`MockClient`).
void main() {
  late Directory temp;
  late Directory project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_lifecycle_');
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

  /// Коды `failure` клиентского конца: `disconnected` — агент закрыл свой.
  List<AcpTransportErrorCode> failuresOf(AcpTransport transport) {
    final codes = <AcpTransportErrorCode>[];
    transport.events.listen((event) {
      if (event is AcpTransportFailure) {
        codes.add(event.error.code);
      }
    });
    return codes;
  }

  test(
    'dispose with a pending permission: write refused, turn cancelled, '
    'the turn outcome is in the journal, a repeated dispose is quiet',
    () async {
      final sessions = '${temp.path}/home/sessions';
      final opener = scriptedEmbeddedAgentOpener(
        llm: {
          'steps': [
            {
              'reply': [
                {
                  'toolCall': {
                    'id': 'call_w',
                    'name': 'write',
                    'arguments': {'path': 'late.txt', 'content': 'x'},
                  },
                },
              ],
            },
            text('never'),
          ],
        },
        codelabHome: '${temp.path}/home',
        sessionsDir: sessions,
        logger: logger,
      );
      agent = await opener(cwd: project.path, hostProfile: 'embedded-cli');
      final failures = failuresOf(agent!.clientTransport);
      client = TestAcpClient(agent!.clientTransport);
      await client!.start();
      await client!.initialize();
      final sessionId = await client!.newSession(project.path);
      final asked = Completer<void>();
      client!.handlers['session/request_permission'] = (_) {
        asked.complete();
        return Completer<Object?>().future;
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
      await agent!.dispose();
      await turn.timeout(const Duration(seconds: 10));

      expect(File('${project.path}/late.txt').existsSync(), isFalse);
      final journals = [
        for (final entity in Directory(sessions).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.jsonl')) entity,
      ];
      expect(journals, hasLength(1));
      // Итог хода дописан в журнал до закрытия: ход завершён отменой, а вызов
      // `write` — отказом (§13.10).
      final journal = journals.single.readAsStringSync();
      expect(journal, contains('call_w'));
      expect(journal, contains('cancelled'));
      expect(failures, [AcpTransportErrorCode.disconnected]);
      expect(agent!.clientTransport.state, AcpTransportState.failed);
      expect(logger.eventsOf('embedded.agent.failed'), isEmpty);
      expect(logger.eventsOf('embedded.agent.late_error'), isEmpty);
      agent = null;
    },
  );

  test('the client closing its end during a turn: the turn is cancelled, '
      'closed completes and the MCP server process is stopped', () async {
    final home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
    // Ответ провайдера не заканчивается: ход «висит» до закрытия клиентом.
    final requested = Completer<void>();
    final body = StreamController<List<int>>();
    addTearDown(() async {
      if (!body.isClosed) {
        await body.close();
      }
    });
    final http = MockClient.streaming((request, _) async {
      if (!requested.isCompleted) {
        requested.complete();
      }
      return web.StreamedResponse(
        body.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final pidFile = File('${temp.path}/server.pid');
    agent = await localEmbeddedAgentOpener(
      environment: {
        'CODELAB_HOME': home,
        'CODELAB_SECRET_CODELAB_P': 'sk-test-0123456789abcdef',
      },
      logger: logger,
      httpClient: http,
    )(cwd: project.path, hostProfile: 'embedded-cli');
    addTearDown(() {
      if (pidFile.existsSync()) {
        final pid = int.tryParse(pidFile.readAsStringSync());
        if (pid != null) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
      }
    });
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();
    await client!.initialize();
    final created = await client!.call('session/new', {
      'cwd': project.path,
      'mcpServers': [
        {
          'name': 'fake',
          'command': Platform.resolvedExecutable,
          'args': [
            '${await _packageRoot()}/test/support/fake_mcp_stdio_server.dart',
            pidFile.path,
          ],
          'env': <Object?>[],
        },
      ],
    });
    final serverPid = int.parse(pidFile.readAsStringSync());
    expect(_alive(serverPid), isTrue, reason: 'the MCP server is running');
    // Ответа на `session/prompt` клиент не получает: свой конец он закрывает
    // сам, поэтому ошибка ожидания игнорируется.
    unawaited(
      client!
          .call('session/prompt', {
            'sessionId': created['sessionId'],
            'prompt': [
              {'type': 'text', 'text': 'hi'},
            ],
          })
          .then<void>((_) {}, onError: (_) {}),
    );
    await requested.future;

    await agent!.clientTransport.close();
    await agent!.closed.timeout(const Duration(seconds: 30));

    expect(_alive(serverPid), isFalse, reason: 'the MCP server must be dead');
    expect(logger.eventsOf('embedded.agent.failed'), isEmpty);
    expect(logger.eventsOf('embedded.agent.late_error'), isEmpty);
    agent = null;
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('failure of the agent', () {
    const secretText = 'secret-text-with-a-path /home/user/key';

    /// Агент на памяти; [stream] оборачивает функцию модели сценария.
    Future<EmbeddedAgent> assemble({
      StreamFunction Function(StreamFunction scripted)? wrap,
      Future<void> Function(AcpAgentServer server, AcpTransport transport)?
      serve,
    }) async {
      final script = LlmScript.fromJson(
        {
          'steps': [text('ok')],
        },
        models: const [],
        clock: FakeClock(),
        cwdOf: (_) => null,
      );
      final scripted = script.function.call;
      return assembleEmbeddedAgent(
        config: memoryConfig(model: script.models.first),
        services: memoryServices(
          logger,
          MockClient((_) async => throw StateError('no network')),
        ),
        models: FixedModelCatalog(script.models),
        streamFunction: wrap == null ? scripted : wrap(scripted),
        serve: serve,
      );
    }

    /// Выполняет [body] в «зоне приложения» с обработчиком ошибок: всё, что
    /// дошло до него, — ошибка агента, просочившаяся наружу (D6).
    Future<List<Object>> inAppZone(Future<void> Function() body) async {
      final leaked = <Object>[];
      await runZonedGuarded(body, (error, _) => leaked.add(error));
      return leaked;
    }

    test('an asynchronous error outside the turn Future: client failed with '
        'disconnected, embedded.agent.failed has the class only, the app zone '
        'gets nothing', () async {
      late final List<AcpTransportErrorCode> failures;
      final leaked = await inAppZone(() async {
        agent = await assemble(
          wrap: (scripted) => (model, context, {cancel}) {
            Timer.run(() => throw StateError(secretText));
            return scripted(model, context, cancel: cancel);
          },
        );
        failures = failuresOf(agent!.clientTransport);
        client = TestAcpClient(agent!.clientTransport);
        await client!.start();
        await client!.initialize();
        final sessionId = await client!.newSession('/t');
        unawaited(
          client!.prompt(sessionId, 'hi').then<void>((_) {}, onError: (_) {}),
        );
        await agent!.closed;
      });

      expect(leaked, isEmpty);
      expect(failures, [AcpTransportErrorCode.disconnected]);
      expect(agent!.clientTransport.state, AcpTransportState.failed);
      final failed = logger.eventsOf('embedded.agent.failed').single;
      expect(failed.level, LogLevel.error);
      expect(failed.fields, {'error_class': 'StateError'});
      expect(failed.error, isNull);
      expect(logger.records.join('\n'), isNot(contains(secretText)));
      expect(logger.eventsOf('embedded.agent.serve_failed'), isEmpty);
      agent = null;
    });

    test('a serve error takes the same path: failed event, agent end closed, '
        'dispose', () async {
      late final List<AcpTransportErrorCode> failures;
      final leaked = await inAppZone(() async {
        agent = await assemble(
          serve: (server, transport) async => throw StateError(secretText),
        );
        failures = failuresOf(agent!.clientTransport);
        await agent!.closed;
      });

      expect(leaked, isEmpty);
      expect(failures, [AcpTransportErrorCode.disconnected]);
      final failed = logger.eventsOf('embedded.agent.failed').single;
      expect(failed.level, LogLevel.error);
      expect(failed.fields, {'error_class': 'StateError'});
      expect(logger.records.join('\n'), isNot(contains(secretText)));
      agent = null;
    });

    test('a second error after the failure is not a second failure and does '
        'not reach the app zone', () async {
      final leaked = await inAppZone(() async {
        agent = await assemble(
          wrap: (scripted) => (model, context, {cancel}) {
            Timer.run(() => throw StateError('first'));
            Timer.run(() => throw ArgumentError('second'));
            return scripted(model, context, cancel: cancel);
          },
        );
        client = TestAcpClient(agent!.clientTransport);
        await client!.start();
        await client!.initialize();
        final sessionId = await client!.newSession('/t');
        unawaited(
          client!.prompt(sessionId, 'hi').then<void>((_) {}, onError: (_) {}),
        );
        await agent!.closed;
        await pumpEventQueue();
      });

      expect(leaked, isEmpty);
      expect(logger.eventsOf('embedded.agent.failed'), hasLength(1));
      // Вторая ошибка не теряется: она записана как поздняя (решение
      // пользователя 2026-11-02, п. B).
      final late = logger.eventsOf('embedded.agent.late_error').single;
      expect(late.level, LogLevel.warning);
      expect(late.fields, {'error_class': 'ArgumentError'});
    });
  });
}

/// Корень пакета `codelab_embedded` (файлы тестовых процессов лежат в нём).
Future<String> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:codelab_embedded/io.dart'),
  );
  return File.fromUri(lib!).parent.parent.path;
}

bool _alive(int pid) => Process.runSync('ps', ['-p', '$pid']).exitCode == 0;
