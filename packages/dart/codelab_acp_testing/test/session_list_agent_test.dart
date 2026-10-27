// Тесты режима scripted-агента `withSessionList` (tasks 5.4 change
// `add-session-list-and-reload`; design D8): настоящий процесс агента на
// Dart VM, кадры JSON-RPC построчно через stdin/stdout.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

void main() {
  late Directory directory;
  late File script;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('session_list_agent_');
    script = await writeCodelabCompatibleStdioAgent(
      directory,
      mode: CodelabCompatibleStdioAgentMode.withSessionList,
    );
  });
  tearDown(() => directory.delete(recursive: true));

  Future<AgentProcess> startAgent() async {
    final agent = await AgentProcess.start(script);
    addTearDown(agent.stop);
    await agent.request('initialize', {'protocolVersion': 1});
    return agent;
  }

  test(
    'initialize declares loadSession and sessionCapabilities.list',
    () async {
      final agent = await AgentProcess.start(script);
      addTearDown(agent.stop);

      final result =
          (await agent.request('initialize', {'protocolVersion': 1}))['result']!
              as Map;
      final capabilities = result['agentCapabilities']! as Map;

      expect(capabilities['loadSession'], isTrue);
      expect((capabilities['sessionCapabilities']! as Map)['list'], isA<Map>());
    },
  );

  test(
    'session/list pages by two with an opaque cursor, newest first',
    () async {
      final agent = await startAgent();
      final ids = [
        for (var i = 0; i < 3; i++) await agent.newSession(directory.path),
      ];

      final first =
          (await agent.request('session/list', {
                'cwd': directory.path,
              }))['result']!
              as Map;
      final cursor = first['nextCursor'] as String?;
      final second =
          (await agent.request('session/list', {
                'cwd': directory.path,
                'cursor': cursor,
              }))['result']!
              as Map;

      List<String> idsOf(Map page) => [
        for (final session in page['sessions']! as List)
          (session as Map)['sessionId']! as String,
      ];
      expect(idsOf(first), [ids[2], ids[1]]);
      expect(cursor, isNotNull);
      expect(idsOf(second), [ids[0]]);
      expect(second.containsKey('nextCursor'), isFalse);
      expect(
        await agent.request('session/list', {'cwd': '/elsewhere'}),
        containsPair('result', {'sessions': <Object?>[]}),
      );
    },
  );

  test('session/load replays the conversation before answering', () async {
    final agent = await startAgent();
    final id = await agent.newSession(directory.path);
    await agent.prompt(id, 'fix the tests');
    agent.received.clear();

    final response = await agent.request('session/load', {
      'sessionId': id,
      'cwd': directory.path,
      'mcpServers': <Object?>[],
    });

    expect(response.containsKey('result'), isTrue);
    expect(
      [
        for (final frame in agent.received)
          if (frame['method'] == 'session/update')
            (
              ((frame['params']! as Map)['update']! as Map)['sessionUpdate'],
              (((frame['params']! as Map)['update']! as Map)['content']!
                  as Map)['text'],
            ),
      ],
      [
        ('user_message_chunk', 'fix the tests'),
        ('agent_message_chunk', 'echo: fix the tests'),
      ],
    );
  });

  test('sessions outlive the agent process', () async {
    final before = await startAgent();
    final id = await before.newSession(directory.path);
    await before.prompt(id, 'remember me');
    await before.stop();

    final after = await startAgent();
    final listed =
        (await after.request('session/list', {
              'cwd': directory.path,
            }))['result']!
            as Map;
    final session = (listed['sessions']! as List).single as Map;
    expect(session['sessionId'], id);
    expect(session['title'], 'remember me');

    after.received.clear();
    await after.request('session/load', {
      'sessionId': id,
      'cwd': directory.path,
      'mcpServers': <Object?>[],
    });
    expect(
      after.received.where((frame) => frame['method'] == 'session/update'),
      hasLength(2),
    );
  });

  test('session/load of an unknown id is "Resource not found"', () async {
    final agent = await startAgent();

    final response = await agent.request('session/load', {
      'sessionId': 'nope',
      'cwd': directory.path,
      'mcpServers': <Object?>[],
    });

    expect((response['error']! as Map)['code'], -32002);
  });
}
