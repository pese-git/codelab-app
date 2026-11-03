import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/build_host.dart';

/// Команды сессии у `serve --ws` (agent-binary «Перезагрузка конфига в serve»,
/// сценарий «WebSocket без /config»; задача 5.11, design.md change
/// `add-config-writer-and-reload`, D12, D13, R0-3).
///
/// Почему: ответ `/config check` содержит пути файлов и тексты проблем машины
/// агента, а держатель токена WebSocket может быть на другой машине. Хост
/// поднимается в процессе теста, HTTP — `MockClient`, реальной сети нет.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_ws_cmds_');
    File('${temp.path}/c.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_env: P_KEY
    models:
      m: {}
agent:
  default_model: p/m
''');
  });

  tearDown(() => temp.delete(recursive: true));

  /// Хост и клиент; второй элемент — тела запросов к провайдеру.
  Future<(AcpPeer, List<String>)> start(String transport) async {
    final bodies = <String>[];
    final client = MockClient.streaming((request, body) async {
      bodies.add(utf8.decode(await body.expand((c) => c).toList()));
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final options = parseServeArgs(
      ['serve', transport, '--config', '${temp.path}/c.yaml'],
      environment: {'CODELAB_HOME': '${temp.path}/home', 'P_KEY': 'sk-test'},
    );
    final host = await buildHost(
      options,
      cwd: temp.path,
      logger: RecordingLogger(),
      httpClient: client,
    );
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    addTearDown(() => host.shutdown(grace: Duration.zero));
    return (AcpPeer(link.client), bodies);
  }

  List<Object?> commandNames(AcpPeer peer) => [
    for (final n in peer.notifications)
      if (n.params case {
        'update': {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': final List<Object?> commands,
        },
      })
        for (final c in commands) (c! as Map)['name'],
  ];

  // Контроль теста: без него `--ws` без `config`/`mcp` прошёл бы и в мире, где
  // команд нет вообще. Встроенные `/config` и `/mcp` объявляет ядро
  // (`commands/builtin_commands.dart`, задача 7.2).
  test('--stdio announces config and mcp (the control of the test)', () async {
    final (peer, _) = await start('--stdio');

    await peer.openSession(temp.path);
    await pumpEventQueue();

    expect(commandNames(peer), containsAll(['config', 'mcp']));
  });

  test('--ws announces neither config nor mcp', () async {
    final (peer, _) = await start('--ws');

    await peer.openSession(temp.path);
    await pumpEventQueue();

    expect(commandNames(peer), isNot(contains('config')));
    expect(commandNames(peer), isNot(contains('mcp')));
  });

  test('--ws: "/config check" is not executed but goes to the model as '
      'text (R0-3)', () async {
    final (peer, bodies) = await start('--ws');
    final session = await peer.openSession(temp.path);

    await expectLater(
      peer.prompt(session, '/config check'),
      throwsA(isA<AcpCallFailed>()),
    );

    expect(bodies, isNotEmpty);
    expect(bodies.join(), contains('/config check'));
  });
}
