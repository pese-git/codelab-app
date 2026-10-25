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

  test('overflow → compaction → the step succeeds', () async {
    final h = harness([
      textStep('a' * 8000),
      overflow,
      textStep('## Open user requests\n- second task'),
      textStep('Done.'),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt(const [TextContent('first task')]);
    final events = <AgentEvent>[];
    session.events.listen(events.add);

    final result = await session.prompt(const [TextContent('second task')]);

    expect(result.reason, TurnEndReason.completed);
    h.model.verify();
    final summaryRequest = h.model.requests[2];
    expect(summaryRequest.tools, isEmpty);
    expect(summaryRequest.cacheKey, '${session.id.value}:summary');
    final retry = h.model.requests[3];
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
