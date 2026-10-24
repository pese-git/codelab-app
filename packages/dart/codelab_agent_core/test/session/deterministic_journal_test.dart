import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// DoD этапа 3: два прогона одного сценария дают побайтово одинаковый
/// JSONL (agent-sessions «Запись журнала из событий», PKG-6).
void main() {
  Future<String> run() async {
    final clock = FakeClock(start: DateTime.utc(2026, 10, 21, 8));
    final env = MemoryExecutionEnv(cwd: '/proj', clock: clock);
    await env.writeText('/proj/a.txt', 'Hello\n');
    final store = MemorySessionStore();
    final h = CoreHarness.build(
      baseEnv: env,
      narrow: noExec,
      gate: FakeGate(),
      clock: clock,
      sessions: store,
      steps: [
        callStep('c1', 'read', {'path': 'a.txt'}),
        callStep('c2', 'edit', {
          'path': 'a.txt',
          'oldText': 'Hello',
          'newText': 'Hi',
        }),
        textStep('Done.'),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt(const [TextContent('Rename the greeting')]);
    await h.core.runtime.dispose();
    return store.textOf(session.id)!;
  }

  test('same script yields an identical journal', () async {
    final first = await run();
    final second = await run();

    expect(second, first);
    final types = [
      for (final line in const LineSplitter().convert(first))
        (jsonDecode(line) as Map<String, Object?>)['type'],
    ];
    expect(types, [
      'session',
      'model_change',
      'message', // user
      'message', // read call
      'message', // read result
      'message', // edit call
      'message', // edit result
      'message', // answer
      'session_info',
    ]);
  });
}
