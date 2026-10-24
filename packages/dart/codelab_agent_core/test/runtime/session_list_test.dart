import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// S-03 на уровне ядра (agent-sessions «Список сессий и автоматический
/// заголовок», design.md D5).
void main() {
  test('two sessions in /a and one in /b: the /a page, newest first', () async {
    final clock = FakeClock(start: DateTime.utc(2026, 10, 21, 8));
    final env = MemoryExecutionEnv(cwd: '/');
    await env.writeText('/a/.keep', '');
    await env.writeText('/b/.keep', '');
    final h = CoreHarness.build(
      baseEnv: env,
      narrow: noExec,
      gate: FakeGate(),
      clock: clock,
      steps: [textStep('one'), textStep('two'), textStep('three')],
    );
    final runtime = h.core.runtime;
    final older = await runtime.createSession(SessionSpec(cwd: '/a'));
    await older.prompt(const [TextContent('older')]);
    await clock.elapse(const Duration(minutes: 1));
    final other = await runtime.createSession(SessionSpec(cwd: '/b'));
    await other.prompt(const [TextContent('other')]);
    await clock.elapse(const Duration(minutes: 1));
    final newer = await runtime.createSession(SessionSpec(cwd: '/a'));
    await newer.prompt(const [TextContent('newer')]);

    final page = await runtime.listSessions(cwd: '/a');

    expect(page.items.map((s) => s.id), [newer.id, older.id]);
    expect(page.items.map((s) => s.title), ['newer', 'older']);
    expect(page.nextCursor, isNull);
    expect((await runtime.listSessions()).items, hasLength(3));
  });

  test('a broken cursor is InvalidCursor', () async {
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/'),
      narrow: noExec,
      gate: FakeGate(),
      steps: const [],
    );

    await expectLater(
      h.core.runtime.listSessions(cursor: 'garbage'),
      throwsA(isA<InvalidCursor>()),
    );
  });
}
