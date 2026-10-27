// Тесты режима scripted-агента `withAvailableCommands` (tasks 1.1 change
// `add-command-palette-agent-commands`; design D6): настоящий процесс агента
// на Dart VM, кадры JSON-RPC построчно через stdin/stdout.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

void main() {
  late Directory directory;
  late AgentProcess agent;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'available_commands_agent_',
    );
    final script = await writeCodelabCompatibleStdioAgent(
      directory,
      mode: CodelabCompatibleStdioAgentMode.withAvailableCommands,
    );
    agent = await AgentProcess.start(script);
    await agent.request('initialize', {'protocolVersion': 1});
  });
  tearDown(() async {
    await agent.stop();
    await directory.delete(recursive: true);
  });

  /// Текст `agent_message_chunk` ответа на промпт [text].
  Future<List<Object?>> replyTo(String sessionId, String text) async {
    agent.received.clear();
    final response = await agent.prompt(sessionId, text);
    expect(response['result'], {'stopReason': 'end_turn'});
    return [
      for (final update in agent.updates)
        if (update['sessionUpdate'] == 'agent_message_chunk')
          (update['content']! as Map)['text'],
    ];
  }

  test('session/new is followed by available_commands_update with compact '
      'and plan', () async {
    await agent.newSession(directory.path);
    // Уведомление идёт после ответа: дожидаемся его следующим запросом.
    await agent.request('session/list', {'cwd': directory.path});

    final commands = [
      for (final update in agent.updates)
        if (update['sessionUpdate'] == 'available_commands_update')
          ...update['availableCommands']! as List,
    ];
    expect(commands, [
      {'name': 'compact', 'description': 'Compact the conversation'},
      {
        'name': 'plan',
        'description': 'Create a plan',
        'input': {'hint': 'what to plan'},
      },
    ]);
  });

  test('a /compact prompt gets the compaction report', () async {
    final sessionId = await agent.newSession(directory.path);

    expect(await replyTo(sessionId, '/compact'), [
      'Compacted the conversation.',
    ]);
  });

  test('any other prompt is echoed', () async {
    final sessionId = await agent.newSession(directory.path);

    expect(await replyTo(sessionId, 'fix the tests'), ['echo: fix the tests']);
  });
}
