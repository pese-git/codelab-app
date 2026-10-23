import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

final class _AllowGate implements PermissionGate {
  final requests = <PermissionRequest>[];

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    requests.add(req);
    return PermissionDecision.allowOnce;
  }
}

Map<String, Object?> _call(String id, String name, Map<String, Object?> args) =>
    {
      'reply': [
        {
          'toolCall': {'id': id, 'name': name, 'arguments': args},
        },
      ],
    };

/// Iteration 2 end to end (tasks.md, 7.5): read → edit → exec through
/// `buildAgentCore` on a real directory and a real shell.
void main() {
  test('read → edit → exec on LocalExecutionEnv', () async {
    final tmp = Directory.systemTemp.createTempSync('local_turn_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = tmp.resolveSymbolicLinksSync();
    File('$root/greeting.txt').writeAsStringSync('hello\n');
    final gate = _AllowGate();
    final model = ScriptedStreamFunction.fromJson({
      'steps': [
        _call('c1', 'read', {'path': 'greeting.txt'}),
        _call('c2', 'edit', {
          'path': 'greeting.txt',
          'oldText': 'hello',
          'newText': 'hello, world',
        }),
        _call('c3', 'exec', {'command': 'cat greeting.txt'}),
        {
          'reply': [
            {'text': 'Done.'},
          ],
          'expect': {
            'toolResult': {'toolCallId': 'c3', 'isError': false},
          },
        },
      ],
    });
    final core = buildAgentCore(
      profile: HostProfile.of('embedded-cli'),
      services: AgentCoreServices(
        baseEnv: LocalExecutionEnv(cwd: root),
        gate: gate,
        logger: RecordingLogger(),
        clock: const SystemClock(),
        ids: SequentialIdGenerator(),
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'model-1',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost:8080/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
      ),
      streamFunction: model.call,
    );
    final session = await core.runtime.createSession(SessionSpec(cwd: root));

    final result = await session.prompt([const TextContent('greet the world')]);

    model.verify();
    expect(result.reason, TurnEndReason.completed);
    expect(File('$root/greeting.txt').readAsStringSync(), 'hello, world\n');
    expect(gate.requests.map((r) => r.tool), ['edit', 'exec']);
    final execResult = model.requests.last.messages.last as ToolResultMessage;
    expect((execResult.content.single as TextContent).text, 'hello, world\n');
    await core.runtime.dispose();
  });
}
