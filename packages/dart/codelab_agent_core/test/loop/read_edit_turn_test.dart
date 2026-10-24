import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import 'loop_harness.dart';

/// Iteration 1 end to end: a scripted model reads a file, edits it and
/// answers; the tools work on a bounded memory env (tasks.md, 4.7).
void main() {
  test('read → edit → answer on the bounded memory env', () async {
    final h = await LoopHarness.create(
      tools: [ReadTool(), EditTool()],
      llm: script([
        callStep([
          ('c1', 'read', {'path': 'lib/main.dart'}),
        ]),
        {
          ...callStep([
            (
              'c2',
              'edit',
              {
                'path': 'lib/main.dart',
                'oldText': 'debug: false',
                'newText': 'debug: true',
              },
            ),
          ]),
          'expect': {
            'toolResult': {'toolCallId': 'c1', 'isError': false},
          },
        },
        {
          ...textStep('Turned debug on.'),
          'expect': {
            'toolResult': {'toolCallId': 'c2', 'isError': false},
          },
        },
      ]),
    );
    await h.env.writeText(
      '/proj/lib/main.dart',
      'const config = (debug: false);\n',
    );
    final agent = Agent(
      config: h.config(),
      systemPrompt: 'You are CodeLab.',
      tools: h.tools,
    );
    final events = <AgentEvent>[];
    agent.subscribe(events.add);

    await agent.prompt([user('turn debug on')]);

    h.scripted!.verify();
    expect(
      await h.env.readText('/proj/lib/main.dart'),
      const Ok<String, FileError>('const config = (debug: true);\n'),
    );
    final read = agent.messages.whereType<ToolResultMessage>().first;
    expect(
      (read.content.single as TextContent).text,
      '1| const config = (debug: false);',
    );
    final edited = events.whereType<ToolCallFinished>().last;
    expect(edited.diffs.single.path, '/proj/lib/main.dart');
    expect(events.last, isA<TurnEnded>());
    expect((events.last as TurnEnded).reason, TurnEndReason.completed);
  });

  test(
    'a path outside the workspace is rejected and the turn goes on',
    () async {
      final h = await LoopHarness.create(
        tools: [ReadTool()],
        llm: script([
          callStep([
            ('c1', 'read', {'path': '/proj_evil/secret'}),
          ]),
          textStep('I cannot read it.'),
        ]),
      );
      await h.env.writeText('/proj_evil/secret', 'token\n');

      final added = await h.run([user('read the secret')]);

      final result = added.whereType<ToolResultMessage>().single;
      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        'Path is outside the workspace: /proj_evil/secret',
      );
      expect(h.trace.last, 'TurnEnded(completed)');
    },
  );
}
