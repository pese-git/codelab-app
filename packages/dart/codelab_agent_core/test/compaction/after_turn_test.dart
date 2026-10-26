import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Фоновое сжатие после хода (задача 9.5; agent-compaction «Точки
/// срабатывания сжатия», триггер `afterTurn`; design.md, D8).
void main() {
  CoreHarness harness(List<Map<String, Object?>> steps) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: FakeGate(),
    defaultModel: modelWithWindow(16384),
    steps: steps,
  );

  Future<(AgentSession, List<AgentEvent>)> open(CoreHarness h) async {
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    return (session, events);
  }

  String firstText(LlmContext request) =>
      ((request.messages.first as UserMessage).content.single as TextContent)
          .text;

  test('runs after a completed turn; the next prompt waits for it', () async {
    final h = harness([
      textStep('a' * 8000),
      textStep('b' * 36000),
      textStep('## Open user requests\n- third task'),
      textStep('Done.'),
    ]);
    final (session, events) = await open(h);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);

    await session.prompt(const [TextContent('third task')]);

    h.model.verify();
    expect(h.model.requests[2].tools, isEmpty);
    expect(firstText(h.model.requests[3]), contains('- third task'));
    final kinds = [
      for (final e in events)
        if (e is TurnEnded || e is TurnStarted || e is ContextCompacted)
          e.runtimeType,
    ];
    expect(kinds, [
      TurnStarted,
      TurnEnded,
      TurnStarted,
      TurnEnded,
      ContextCompacted,
      TurnStarted,
      TurnEnded,
    ]);
    await h.core.runtime.dispose();
  });

  test('does not run after a cancelled turn', () async {
    final h = harness([
      textStep('a' * 8000),
      {
        'reply': [
          {'text': 'b' * 36000},
        ],
        'stopReason': 'aborted',
      },
      textStep('Done.'),
    ]);
    final (session, events) = await open(h);
    await session.prompt(const [TextContent('first task')]);
    final cancelled = await session.prompt(const [TextContent('second')]);
    expect(cancelled.reason, TurnEndReason.cancelled);

    await session.prompt(const [TextContent('third task')]);

    h.model.verify();
    expect(events.whereType<ContextCompacted>(), isEmpty);
    await h.core.runtime.dispose();
  });

  test('does not run after a failed turn', () async {
    final h = harness([
      textStep('a' * 8000),
      {
        'reply': [
          {'text': 'b' * 36000},
        ],
        'error': {'class': 'rateLimited', 'message': 'slow down'},
      },
      textStep('Done.'),
    ]);
    final (session, events) = await open(h);
    await session.prompt(const [TextContent('first task')]);
    final failed = await session.prompt(const [TextContent('second')]);
    expect(failed.reason, TurnEndReason.failed);

    await session.prompt(const [TextContent('third task')]);

    h.model.verify();
    expect(events.whereType<ContextCompacted>(), isEmpty);
    await h.core.runtime.dispose();
  });

  test('a failed background compaction is AgentError(compaction)', () async {
    final h = harness([
      textStep('a' * 8000),
      textStep('b' * 36000),
      {
        'error': {'class': 'rateLimited', 'message': 'slow down'},
      },
      textStep('Done.'),
    ]);
    final (session, events) = await open(h);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    final journal = (await h.sessions.open(session.id)).records.length;

    final result = await session.prompt(const [TextContent('third task')]);

    expect(result.reason, TurnEndReason.completed);
    h.model.verify();
    final error = events.whereType<AgentError>().single;
    expect(error.cls, AgentErrorClass.compaction);
    expect(events.whereType<ContextCompacted>(), isEmpty);
    final records = (await h.sessions.open(session.id)).records;
    expect(records.whereType<CompactionRecord>(), isEmpty);
    expect(records.length, greaterThan(journal));
    await h.core.runtime.dispose();
  });

  test('contextWindowCap lowers the threshold (CMP-6)', () async {
    List<Map<String, Object?>> steps() => [
      textStep('a' * 8000),
      textStep('b' * 36000),
      textStep('## Open user requests\n- none'),
      textStep('Done.'),
    ];
    final capped = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      defaultModel: modelWithWindow(128000),
      compaction: const CompactionOverrides(contextWindowCap: 16384),
      steps: steps(),
    );
    final (session, events) = await open(capped);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    // Следующий prompt дожидается фонового сжатия.
    await session.prompt(const [TextContent('third task')]);
    await capped.core.runtime.dispose();

    capped.model.verify();
    expect(events.whereType<ContextCompacted>(), hasLength(1));
  });
}
