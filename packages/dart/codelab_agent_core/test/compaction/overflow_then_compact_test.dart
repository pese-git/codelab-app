import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// DoD этапа 3 (задача 9.5; agent-compaction «Точки срабатывания сжатия»,
/// сценарий «Переполнение, затем успех»; agent-runtime «Минимальная сборка
/// buildAgentCore»).
void main() {
  final overflow = <String, Object?>{
    'error': {'class': 'overflow', 'message': 'prompt is too long'},
  };

  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    bool enabled = true,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: FakeGate(),
    defaultModel: modelWithWindow(16384),
    compaction: CompactionOverrides(keepRecentTokens: 1000, enabled: enabled),
    steps: steps,
  );

  test(
    'core/overflow-triggers-compaction: overflow → compaction → retry',
    () async {
      // Три хода: срез хвоста проходит внутри предыдущего хода, поэтому
      // регион сжатия — первый ход целиком (≈2000 токенов), и резюме заметно
      // короче него. С двумя ходами в резюме уходило одно короткое сообщение
      // пользователя, выигрыша не было, и проход не записывался (CMP-10).
      final h = harness([
        textStep('b' * 8000),
        textStep('a' * 8000),
        overflow,
        textStep('## Open user requests\n- second task'),
        // Срез внутри хода: начало хода резюмируется вторым запросом (§9.6).
        textStep('Turn prefix: first task.'),
        textStep('Done.'),
      ]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final events = <AgentEvent>[];
      session.events.listen(events.add);
      await session.prompt(const [TextContent('zeroth task')]);
      await session.prompt(const [TextContent('first task')]);

      final result = await session.prompt(const [TextContent('second task')]);

      expect(result.reason, TurnEndReason.completed);
      h.model.verify();
      final summaryRequest = h.model.requests[3];
      expect(summaryRequest.tools, isEmpty);
      expect(summaryRequest.cacheKey, '${session.id.value}:summary');
      final retry = h.model.requests[5];
      final first = retry.messages.first as UserMessage;
      expect(
        (first.content.single as TextContent).text,
        contains('- second task'),
      );
      expect(events.whereType<ContextCompacted>(), hasLength(1));
      expect(events.whereType<AgentError>(), isEmpty);
      final snapshot = await h.sessions.open(session.id);
      expect(snapshot.records.whereType<CompactionRecord>(), hasLength(1));
      await h.core.runtime.dispose();
    },
  );

  // CMP-8: аварийный вызов один на шаг. Повторный overflow после успешного
  // сжатия завершает ход `failed`, а следующий ход работает обычным путём без
  // зацикливания (change `anchor-context-estimate-after-compaction`, D3).
  test('overflow, compaction, a second overflow: the turn fails once, the '
      'next turn completes without a compaction loop (CMP-8)', () async {
    final h = harness([
      textStep('b' * 8000),
      textStep('a' * 8000),
      overflow,
      textStep('## Open user requests\n- second task'),
      textStep('Turn prefix: first task.'),
      overflow,
      textStep('Done.'),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('zeroth task')]);
    await session.prompt(const [TextContent('first task')]);

    final failed = await session.prompt(const [TextContent('second task')]);
    final next = await session.prompt(const [TextContent('third task')]);

    expect(failed.reason, TurnEndReason.failed);
    expect(next.reason, TurnEndReason.completed);
    h.model.verify();
    expect(events.whereType<ContextCompacted>(), hasLength(1));
    final snapshot = await h.sessions.open(session.id);
    expect(snapshot.records.whereType<CompactionRecord>(), hasLength(1));
    await h.core.runtime.dispose();
  });

  test('overflow, then a summary longer than the region: no compaction '
      'record, one accounting record, no retry, the turn fails (D5, CMP-8, '
      'CMP-10, change fix-discarded-compaction-usage D1)', () async {
    // Платные ответы суммаризатора: usage уходит в запись учёта, но не в ход.
    Map<String, Object?> paid(String text) => {
      'reply': [
        {'text': text},
      ],
      'usage': const Usage(input: 300, output: 60).toJson(),
    };
    final h = harness([
      textStep('b' * 8000),
      textStep('a' * 8000),
      overflow,
      // Резюме в несколько раз длиннее региона: выигрыша нет.
      paid('x' * 80000),
      paid('y' * 80000),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('zeroth task')]);
    await session.prompt(const [TextContent('first task')]);

    final result = await session.prompt(const [TextContent('second task')]);

    expect(result.reason, TurnEndReason.failed);
    h.model.verify();
    expect(
      h.model.requests.where((r) => r.cacheKey?.endsWith(':summary') ?? false),
      // Один аварийный вызов хода: срез внутри хода даёт два запроса
      // суммаризатора (регион и начало хода), второго вызова сжатия нет.
      hasLength(2),
      reason: 'one emergency call per turn',
    );
    expect(h.model.requests, hasLength(5), reason: 'no retry of the request');
    expect(events.whereType<ContextCompacted>(), isEmpty);
    final snapshot = await h.sessions.open(session.id);
    expect(snapshot.records.whereType<CompactionRecord>(), isEmpty);
    // Характеризационная правка (change `fix-discarded-compaction-usage`, D1,
    // R2): раньше журнал не менялся. Теперь — одна запись учёта с триггером
    // `overflow` и суммой двух запросов суммаризатора.
    final discarded = snapshot.records.whereType<CustomRecord>().single;
    expect(discarded.customType, 'codelab.compaction_discarded');
    final data = discarded.data! as Map;
    expect(data['trigger'], 'overflow');
    expect(data['reason'], 'no reduction');
    expect((data['usage']! as Map)['input'], 600);
    expect((data['usage']! as Map)['output'], 120);
    // Usage суммаризатора не входит в usage хода, в том числе на аварийном
    // пути (D2 change `add-usage-ledger`).
    final ended = events.whereType<TurnEnded>().last;
    expect(ended.reason, TurnEndReason.failed);
    expect(result.usage, Usage.zero);
    expect(ended.usage, Usage.zero);
    await h.core.runtime.dispose();
  });

  test('compaction off in the config: overflow fails the turn', () async {
    final h = harness([textStep('a' * 8000), overflow], enabled: false);
    expect(h.core.plan.offReasons, contains(HostCapability.compaction));
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt(const [TextContent('first task')]);

    final result = await session.prompt(const [TextContent('second task')]);

    expect(result.reason, TurnEndReason.failed);
    h.model.verify();
    final snapshot = await h.sessions.open(session.id);
    expect(snapshot.records.whereType<CompactionRecord>(), isEmpty);
    await h.core.runtime.dispose();
  });
}
