import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

void main() {
  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    PermissionGate? gate,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: gate ?? FakeGate(),
    steps: steps,
  );

  test('a turn through the direct API', () async {
    final h = harness([textStep('Hello')]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final seen = <AgentEvent>[];
    session.events.listen(seen.add);

    final result = await session.prompt([const TextContent('hi')]);
    await pumpEventQueue();

    expect(result.reason, TurnEndReason.completed);
    expect(result.usage, Usage.zero);
    expect(seen.first, isA<TurnStarted>());
    expect(seen.last, isA<TurnEnded>());
    expect(seen.every((e) => e.sessionId == session.id), isTrue);
    expect(h.model.requests.single.cacheKey, session.id.value);
  });

  test(
    'a late subscriber gets the events of the current turn from the start',
    () async {
      final h = harness([
        {'waitForCancel': true},
      ]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      final turn = session.prompt([const TextContent('hi')]);
      await pumpEventQueue();
      final late = <AgentEvent>[];
      session.events.listen(late.add);
      await session.cancel();
      final result = await turn;
      await pumpEventQueue();

      expect(late.first, isA<TurnStarted>());
      expect(late.last, isA<TurnEnded>());
      expect(result.reason, TurnEndReason.cancelled);
    },
  );

  test('setMode emits ModeChanged and applies to the next call', () async {
    final gate = FakeGate();
    final h = harness([textStep('ok')], gate: gate);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.ask),
    );
    final seen = <AgentEvent>[];
    session.events.listen(seen.add);

    await session.setMode(ModeId.bypass);
    await pumpEventQueue();

    expect(seen.whereType<ModeChanged>().single.mode, ModeId.bypass);
    expect(session.mode, ModeId.bypass);
  });

  test('a second prompt during a turn is a StateError (LOOP-10)', () async {
    final h = harness([
      {'waitForCancel': true},
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );

    final turn = session.prompt([const TextContent('one')]);
    await pumpEventQueue();
    await expectLater(
      session.prompt([const TextContent('two')]),
      throwsStateError,
    );
    await session.cancel();
    await turn;
  });

  test('the cancel token of prompt cancels the turn', () async {
    final h = harness([
      {'waitForCancel': true},
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final source = CancelTokenSource();

    final turn = session.prompt([
      const TextContent('hi'),
    ], cancel: source.token);
    await pumpEventQueue();
    source.cancel();

    expect((await turn).reason, TurnEndReason.cancelled);
  });

  test('listSessions pages the store; dispose ends running turns', () async {
    final h = harness([
      {'waitForCancel': true},
    ]);
    final runtime = h.core.runtime;
    final a = await runtime.createSession(SessionSpec(cwd: '/proj'));
    final b = await runtime.createSession(SessionSpec(cwd: '/proj'));

    final turn = a.prompt([const TextContent('hi')]);
    await pumpEventQueue();

    // Одно время на FakeClock: при равном updatedAt больший id первым
    // (§8.10, шаг 4).
    expect((await runtime.listSessions()).items.map((s) => s.id), [b.id, a.id]);
    await runtime.dispose();
    expect((await turn).reason, TurnEndReason.cancelled);
  });
}
