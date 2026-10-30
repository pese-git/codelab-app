import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';

import 'support/agent_process.dart';

/// Файлы проекта в бинаре (agent-binary «Файлы проекта в бинаре», сценарий
/// «Сценарий не читает CODELAB_HOME»; design.md change
/// `add-agent-project-files`, D16). Процессный тест на Dart VM
/// (`AGENTS.md` §21).
void main() {
  late Directory temp;
  late String project;
  late String home;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_project_');
    addTearDown(() => temp.delete(recursive: true));
    project = '${temp.path}/project';
    home = '${temp.path}/home';
    Directory(project).createSync();
    Directory('$home/prompts').createSync(recursive: true);
    File('$project/AGENTS.md').writeAsStringSync('project-rule-text\n');
    File('$home/AGENTS.md').writeAsStringSync('user-rule-text\n');
    File('$home/prompts/review.md').writeAsStringSync(
      r'Review $ARGUMENTS'
      '\n',
    );
  });

  test('--llm-script reads AGENTS.md of cwd and never CODELAB_HOME', () async {
    final agent = await AgentProcess.start(
      ['serve', '--stdio', '--llm-script', 'test/llm_scripts/hello.json'],
      environment: {'CODELAB_HOME': home},
    );
    addTearDown(agent.kill9);
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': 1},
    });
    await agent.responseTo(1);
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'session/new',
      'params': {'cwd': project, 'mcpServers': <Object?>[]},
    });
    final seen = <Map<String, Object?>>[];
    final created = await agent.responseTo(2, seen: seen);
    expect(created['result'], isNotNull, reason: agent.stderrText);
    // Контекст проекта идёт в промпт без обращений к клиенту (D2):
    // `fs/read_text_file` агент не отправлял.
    expect([
      for (final m in seen) m['method'],
    ], isNot(contains('fs/read_text_file')));
    await agent.closeStdin();
    expect(await agent.exitCode, 0);

    await agent.stderrContains('project_context.loaded');
    final line = agent.stderrText
        .split('\n')
        .singleWhere((l) => l.contains('project_context.loaded'));
    expect(line, contains('AGENTS.md'));
    expect(line, isNot(contains('CODELAB_HOME')));
    // Содержимое файлов не попадает в лог (D14).
    expect(agent.stderrText, isNot(contains('project-rule-text')));
    expect(agent.stderrText, isNot(contains('user-rule-text')));
    // Шаблоны пользователя сценарий тоже не читает.
    final commands = [
      for (final m in seen)
        if (m case {
          'params': {
            'update': {
              'sessionUpdate': 'available_commands_update',
              'availableCommands': final List<Object?> list,
            },
          },
        })
          ...list,
    ];
    expect(commands, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // D17: под `--llm-script` `CODELAB_HOME` не раскрывается и не проверяется:
  // `~bob/cl` и `~/cl` без HOME не дают код 64, каталог `./~bob` не создаётся.
  for (final (name, value, userHome) in [
    ('~user/cl', '~bob/cl', null),
    ('~/cl without HOME', '~/cl', ''),
  ]) {
    test(
      '--llm-script with CODELAB_HOME=$name starts and runs a turn',
      () async {
        final agent = await AgentProcess.start(
          [
            'serve',
            '--stdio',
            '--llm-script',
            '$appDirectory/test/llm_scripts/hello.json',
          ],
          environment: {'CODELAB_HOME': value, 'HOME': ?userHome},
          workingDirectory: project,
        );
        addTearDown(agent.kill9);
        agent.sendJson({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        });
        await agent.responseTo(1);
        agent.sendJson({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'session/new',
          'params': {'cwd': project, 'mcpServers': <Object?>[]},
        });
        final created = await agent.responseTo(2);
        final sessionId = (created['result'] as Map)['sessionId'];
        agent.sendJson({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'session/prompt',
          'params': {
            'sessionId': sessionId,
            'prompt': [
              {'type': 'text', 'text': 'hi'},
            ],
          },
        });
        final done = await agent.responseTo(3);
        expect(done['result'], isNotNull, reason: agent.stderrText);
        await agent.closeStdin();
        expect(await agent.exitCode, 0, reason: agent.stderrText);
        expect(Directory('$project/~bob').existsSync(), isFalse);
        expect(Directory('$project/~').existsSync(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }

  test('serve --ws reads no project files and logs the skip once', () async {
    const token = 'secret-token';
    final agent = await AgentProcess.start(
      [
        'serve',
        '--ws',
        '--port',
        '0',
        '--llm-script',
        'test/llm_scripts/hello.json',
      ],
      environment: {'CODELAB_HOME': home, 'CODELAB_AGENT_TOKEN': token},
    );
    addTearDown(agent.kill9);
    await agent.stderrContains('serve.ws.listening');
    final port = int.parse(
      RegExp(
        r'serve\.ws\.listening .*port: (\d+)',
      ).firstMatch(agent.stderrText)!.group(1)!,
    );
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:$port/acp'),
        token: token,
      ),
    );
    await transport.start();
    addTearDown(transport.close);
    final peer = AcpPeer(transport);
    addTearDown(peer.dispose);

    await peer.call('initialize', {'protocolVersion': 1});
    final created = await peer.call('session/new', {
      'cwd': project,
      'mcpServers': <Object?>[],
    });
    expect(created['sessionId'], isNotNull);

    // Клиент WebSocket выбирает `cwd` сам, а читать пришлось бы с ФС
    // машины агента (design.md, D2): ни проект, ни `$CODELAB_HOME`.
    expect(agent.stderrText, isNot(contains('project_context.loaded')));
    final skipped = [
      for (final line in agent.stderrText.split('\n'))
        if (line.contains('project_files.skipped')) line,
    ];
    expect(skipped, hasLength(1), reason: agent.stderrText);
    expect(agent.stderrText, isNot(contains('project-rule-text')));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
