// Тесты режима scripted-агента `withUsageBudget` (change
// `add-desktop-usage-pane`, D7, задача 2.4): настоящий процесс агента на
// Dart VM, кадры JSON-RPC построчно через stdin/stdout. Нужен приёмке app
// (блок «Turn budget»); числа детерминированы.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

const _method = '_codelab/session/usage';

void main() {
  late Directory directory;
  late AgentProcess agent;

  Future<void> start(CodelabCompatibleStdioAgentMode mode) async {
    directory = await Directory.systemTemp.createTemp('usage_budget_agent_');
    final script = await writeCodelabCompatibleStdioAgent(
      directory,
      mode: mode,
    );
    agent = await AgentProcess.start(script);
  }

  tearDown(() async {
    await agent.stop();
    await directory.delete(recursive: true);
  });

  Future<void> initialize({bool usage = true}) => agent.request('initialize', {
    'protocolVersion': 1,
    'clientCapabilities': {
      '_meta': {
        'codelab': {
          if (usage) 'usage': {'version': 1},
        },
      },
    },
  });

  List<Map<String, Object?>> snapshots() => [
    for (final frame in agent.received)
      if (frame['method'] == _method)
        (frame['params']! as Map).cast<String, Object?>(),
  ];

  test('step and turn snapshots of both turns carry the budget', () async {
    await start(CodelabCompatibleStdioAgentMode.withUsageBudget);
    await initialize();
    final sessionId = await agent.newSession(directory.path);

    await agent.prompt(sessionId, 'first');
    await agent.prompt(sessionId, 'second');

    final frames = snapshots();
    expect(frames.map((f) => f['trigger']), ['step', 'turn', 'step', 'turn']);
    const tokens = [12800, 12800, 21500, 21500];
    const cost = ['0.04', '0.04', '0.05', '0.05'];
    for (final (i, frame) in frames.indexed) {
      expect(frame['budget'], {
        'steps': {'used': 1, 'limit': 50},
        'tokens': {'used': tokens[i], 'limit': 200000},
        'cost': {'used': cost[i], 'limit': '0.5'},
        'duration': {'usedMs': 1500, 'limitMs': 600000},
      }, reason: 'снимок ${i + 1}');
      expect(frame['currency'], 'USD');
    }
  });

  test('a client without the usage declaration gets no snapshots', () async {
    await start(CodelabCompatibleStdioAgentMode.withUsageBudget);
    await initialize(usage: false);
    final sessionId = await agent.newSession(directory.path);

    await agent.prompt(sessionId, 'hello');

    expect(snapshots(), isEmpty);
  });

  test('the load snapshot has no budget', () async {
    await start(CodelabCompatibleStdioAgentMode.withUsageBudget);
    await initialize();

    await agent.request('session/load', {
      'sessionId': 'journal-1',
      'cwd': directory.path,
      'mcpServers': <Object?>[],
    });
    await agent.newSession(directory.path);

    final load = snapshots().single;
    expect(load['trigger'], 'load');
    expect(load, isNot(contains('budget')));
  });

  test(
    'withUsage does not carry the budget (existing numbers unchanged)',
    () async {
      await start(CodelabCompatibleStdioAgentMode.withUsage);
      await initialize();
      final sessionId = await agent.newSession(directory.path);

      await agent.prompt(sessionId, 'hello');

      for (final frame in snapshots()) {
        expect(frame, isNot(contains('budget')));
      }
    },
  );
}
