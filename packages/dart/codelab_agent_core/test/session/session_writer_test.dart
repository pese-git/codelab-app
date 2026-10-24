import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'recording_store.dart';

/// Запись журнала из событий (agent-sessions «Запись журнала из событий»,
/// §8.3, SES-8, SES-9).
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
  final at = DateTime.utc(2026, 10, 21, 8);

  late RecordingStore store;
  late RecordingLogger logger;
  late List<Object> failures;
  late SessionWriter writer;

  setUp(() async {
    store = RecordingStore();
    logger = RecordingLogger();
    failures = [];
    final header = SessionHeader(
      id: id,
      cwd: '/work/demo',
      created: at,
      agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
    );
    await store.create(header);
    writer = SessionWriter(
      store: store,
      snapshot: SessionSnapshot.empty(header),
      ids: SequentialIdGenerator(),
      clock: FakeClock(start: at),
      logger: logger,
      onFailure: failures.add,
    );
  });

  final prompt = UserMessage(const [TextContent('go')], timestamp: at);
  final answer = AssistantMessage(
    content: [
      ToolCall(id: 'c1', name: 'edit', arguments: const {'path': 'a.txt'}),
    ],
    model: testModel,
    usage: Usage.zero,
    stopReason: StopReason.toolUse,
    timestamp: at,
  );
  final result = ToolResultMessage(
    toolCallId: 'c1',
    toolName: 'edit',
    content: const [TextContent('Edited a.txt.')],
    isError: false,
    timestamp: at,
  );
  const diff = FileDiff(path: '/work/demo/a.txt', oldText: 'a', newText: 'b');

  Future<void> feed(List<AgentEvent> events) async {
    for (final event in events) {
      await writer.handle(event);
    }
  }

  List<AgentEvent> turn() => [
    TurnStarted(id, turnId: const TurnId('t1'), input: [prompt]),
    MessageStarted(id, message: prompt),
    MessageEnded(id, message: prompt),
    StepStarted(id, stepIndex: 0),
    MessageStarted(id, message: answer),
    MessageEnded(id, message: answer),
    ToolCallStarted(
      id,
      toolCallId: 'c1',
      tool: 'edit',
      kind: ToolKind.edit,
      title: 'Edit a.txt',
      input: const {'path': 'a.txt'},
      locations: const [Location('/work/demo/a.txt', line: 1)],
    ),
    ToolCallFinished(
      id,
      toolCallId: 'c1',
      outcome: ToolOutcome.completed,
      content: result.content,
      diffs: const [diff],
    ),
    MessageStarted(id, message: result),
    MessageEnded(id, message: result),
    TurnEnded(id, reason: TurnEndReason.completed, usage: Usage.zero),
  ];

  test('messages of a turn, durable tool result, flush at the end', () async {
    await feed(turn());

    expect(store.appended.map((a) => a.record.type), [
      'message',
      'message',
      'message',
    ]);
    expect(store.appended.map((a) => a.durable), [false, false, true]);
    expect(store.flushes, 1);
    final [user, assistant, tool] = [
      for (final a in store.appended) a.record as MessageRecord,
    ];
    expect(user.parentId, isNull);
    expect(assistant.parentId, user.id);
    expect(tool.parentId, assistant.id);
    expect(tool.outcome, 'completed');
    expect(tool.diff, diff);
    expect(tool.toolMeta?.title, 'Edit a.txt');
    expect(tool.toolMeta?.kind, ToolKind.edit);
    expect(tool.toolMeta?.locations, const [
      Location('/work/demo/a.txt', line: 1),
    ]);
    expect(tool.message, result);
    expect(writer.snapshot.leafId, tool.id);
    expect(writer.snapshot.records, hasLength(3));
  });

  test('origin of service messages comes from MessageStarted', () async {
    final nudge = UserMessage(const [TextContent('Continue.')], timestamp: at);

    await feed([
      MessageStarted(
        id,
        message: nudge,
        origin: const LoopNudgeOrigin(LoopNudgeReason.emptyResponse, 2),
      ),
      MessageEnded(id, message: nudge),
    ]);

    final record = store.appended.single.record as MessageRecord;
    expect(record.origin, 'loop_nudge');
    expect(record.nudge, 'empty_response');
    expect(record.attempt, 2);
  });

  test('plan, mode and title records', () async {
    await feed([
      PlanUpdated(
        id,
        entries: const [
          PlanEntry(
            content: 'step',
            priority: PlanPriority.high,
            status: PlanStatus.inProgress,
          ),
        ],
      ),
      const ModeChanged(id, mode: ModeId.plan),
      SessionTitleChanged(id, title: 'Go', updatedAt: at),
    ]);

    final [plan, mode, info] = [for (final a in store.appended) a.record];
    expect((plan as PlanRecord).entries.single.status, PlanStatus.inProgress);
    expect((mode as ModeChangeRecord).modeId, 'plan');
    expect((info as SessionInfoRecord).title, 'Go');
    expect(info.source, 'auto');
  });

  test('deltas, progress and other events are not written', () async {
    await feed([
      MessageDelta(id, delta: 'x', partial: answer),
      ThoughtDelta(id, delta: 'y', partial: answer),
      ToolCallProgress(id, toolCallId: 'c1', content: const []),
      StepStarted(id, stepIndex: 0),
      ModelRequested(id, model: testModel, estimatedTokens: 0, messageCount: 1),
    ]);

    expect(store.appended, isEmpty);
  });

  test('append assigns id, parent and time', () async {
    final record = await writer.append(
      (id, parent, timestamp) => ModelChangeRecord(
        id: id,
        parentId: parent,
        timestamp: timestamp,
        provider: 'test',
        modelId: 'model-1',
      ),
    );

    expect(record.id, hasLength(8));
    expect(record.parentId, isNull);
    expect(record.timestamp, at);
    expect(writer.snapshot.leafId, record.id);
  });

  test('a failed append reports, logs and keeps the snapshot', () async {
    store.failAppends = true;

    await feed(turn().take(3).toList());

    expect(failures, hasLength(1));
    expect(logger.eventsOf('session.append.failed'), hasLength(1));
    expect(writer.snapshot.records, isEmpty);
    expect(writer.snapshot.leafId, isNull);
  });

  test(
    'after a failure the turn writes nothing more; the next turn does',
    () async {
      store.failAppends = true;
      await feed(turn().take(3).toList());
      store.failAppends = false;

      await feed(turn().skip(3).toList());
      expect(store.appended, isEmpty);

      await feed(turn());
      expect(store.appended, hasLength(3));
      expect(failures, hasLength(1));
    },
  );
}
