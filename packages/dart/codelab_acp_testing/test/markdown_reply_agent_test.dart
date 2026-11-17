// Тест режима scripted-агента `withMarkdownReply` (change
// `add-desktop-markdown`, задача 5.1): настоящий процесс агента на Dart VM.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

void main() {
  late Directory directory;
  late AgentProcess agent;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('markdown_reply_agent_');
    final script = await writeCodelabCompatibleStdioAgent(
      directory,
      mode: CodelabCompatibleStdioAgentMode.withMarkdownReply,
    );
    agent = await AgentProcess.start(script);
    await agent.request('initialize', {'protocolVersion': 1});
  });
  tearDown(() async {
    await agent.stop();
    await directory.delete(recursive: true);
  });

  test('a prompt gets "echo: <text>" as a single message chunk', () async {
    final sessionId = await agent.newSession(directory.path);
    agent.received.clear();

    final response = await agent.prompt(sessionId, '**bold** text');

    expect(response['result'], {'stopReason': 'end_turn'});
    expect(
      [
        for (final update in agent.updates)
          if (update['sessionUpdate'] == 'agent_message_chunk')
            (update['content']! as Map)['text'],
      ],
      ['echo: **bold** text'],
    );
  });
}
