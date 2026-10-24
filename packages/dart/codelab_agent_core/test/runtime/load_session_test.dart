import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../session/recording_store.dart';

/// `createSession`, `loadSession` и `replay` с журналом (agent-runtime
/// «AgentRuntime и AgentSession», design.md D4).
void main() {
  List<Map<String, Object?>> linesOf(MemorySessionStore store, SessionId id) =>
      [
        for (final line in const LineSplitter().convert(store.textOf(id)!))
          jsonDecode(line) as Map<String, Object?>,
      ];

  CoreHarness harness(
    SessionStore store,
    List<Map<String, Object?>> steps, {
    FakeClock? clock,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: FakeGate(),
    sessions: store,
    clock: clock,
    steps: steps,
  );

  test('a new journal starts with model_change of the session model', () async {
    final store = MemorySessionStore();
    final h = harness(store, const []);

    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );

    final lines = linesOf(store, session.id);
    expect(lines.first['type'], 'session');
    expect(lines.first['cwd'], '/proj');
    expect(lines[1], {
      'type': 'model_change',
      'id': isA<String>(),
      'parentId': null,
      'timestamp': isA<String>(),
      'provider': 'test',
      'modelId': 'model-1',
      'baseUrl': 'http://localhost:8080/v1',
    });
    expect(session.id.value, hasLength(26));
  });

  test(
    'loadSession restores the transcript, the mode and the replay',
    () async {
      final store = MemorySessionStore();
      final first = harness(store, [
        callStep('c1', 'update_plan', {
          'entries': [
            {'content': 'Read', 'priority': 'high', 'status': 'pending'},
          ],
        }),
        textStep('Planned.'),
        textStep('Second answer.'),
      ]);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.prompt(const [TextContent('Make a plan')]);
      await created.setMode(ModeId.plan);
      await created.prompt(const [TextContent('Go on')]);
      await first.core.runtime.dispose();

      final second = harness(store, [textStep('Third answer.')]);
      final loaded = await second.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
      );

      expect(loaded.id, created.id);
      expect(loaded.mode, ModeId.plan);
      final replay = loaded.replay().toList();
      expect(
        replay
            .whereType<MessageEnded>()
            .map((e) => e.message)
            .whereType<UserMessage>()
            .map((m) => (m.content.single as TextContent).text),
        ['Make a plan', 'Go on'],
      );
      expect(
        replay.whereType<PlanUpdated>().single.entries.single.content,
        'Read',
      );
      expect(replay.whereType<ModeChanged>().single.mode, ModeId.plan);

      await loaded.prompt(const [TextContent('And now?')]);

      final request = second.model.requests.single;
      expect(
        request.messages.whereType<UserMessage>().map(
          (m) => (m.content.single as TextContent).text,
        ),
        ['Make a plan', 'Go on', 'And now?'],
      );
      expect(request.messages.whereType<ToolResultMessage>(), hasLength(1));
    },
  );

  test('loadSession of an unknown id is SessionNotFound', () async {
    final h = harness(MemorySessionStore(), const []);

    await expectLater(
      h.core.runtime.loadSession(
        const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0Z'),
        const SessionHostPorts(),
      ),
      throwsA(isA<SessionNotFound>()),
    );
  });

  test('another model of the journal is not restored (D4)', () async {
    final store = MemorySessionStore();
    final first = harness(store, [textStep('ok')]);
    final created = await first.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await created.prompt(const [TextContent('hi')]);
    await first.core.runtime.dispose();
    final other = ModelRef(
      provider: 'other',
      id: 'model-2',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:9090/v1'),
      contextWindow: 16000,
      maxOutputTokens: 1024,
    );

    final second = harness(store, const []);
    await second.core.runtime.loadSession(
      created.id,
      const SessionHostPorts(),
      model: other,
    );

    expect(second.logger.eventsOf('session.model.not_restored'), hasLength(1));
    final last = linesOf(store, created.id).last;
    expect(last['type'], 'model_change');
    expect(last['provider'], 'other');
    expect(last['modelId'], 'model-2');
  });

  test('the same model writes no new model_change', () async {
    final store = MemorySessionStore();
    final first = harness(store, const []);
    final created = await first.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await first.core.runtime.dispose();
    final before = store.textOf(created.id);

    await harness(
      store,
      const [],
    ).core.runtime.loadSession(created.id, const SessionHostPorts());

    expect(store.textOf(created.id), before);
  });

  test('a failed journal write ends the turn as failed (SES-8)', () async {
    final store = RecordingStore();
    final h = harness(store, const []);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    store.failAppends = true;

    final result = await session.prompt(const [TextContent('hi')]);
    await pumpEventQueue();

    expect(result.reason, TurnEndReason.failed);
    expect(
      events.whereType<AgentError>().map((e) => e.cls),
      contains(AgentErrorClass.storage),
    );
    expect(h.model.requests, isEmpty);
    expect(h.logger.eventsOf('session.append.failed'), isNotEmpty);
  });
}
