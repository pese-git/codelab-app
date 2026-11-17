import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../compaction/anchor_support.dart';
import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../session/journal_lines.dart' as j;
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
        callStep('c1', 'task_create', {'subject': 'Read', 'priority': 'high'}),
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
      // Реплей отдаёт список ветки одним снимком после истории (§17.16.6).
      final restored = replay.whereType<TaskListChanged>().single;
      expect(restored.items.single.subject, 'Read');
      expect(restored.change.op, 'restore');
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

  /// Якорь сжатия после загрузки (design.md change
  /// `anchor-context-estimate-after-compaction`, D5; agent-compaction
  /// «Загрузка сессии после сжатия», «Несколько сжатий и ветки», CMP-11):
  /// якорь фиксируется по проекции, которой восстановлен транскрипт, а не
  /// хранится в журнале.
  group('the compaction anchor after loadSession (D5)', () {
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

    UserMessage newMessage(String text) =>
        UserMessage([TextContent(text)], timestamp: DateTime.utc(2026));

    /// Загружает [lines] в новую сессию и возвращает оценку первого запроса
    /// хода `new request` вместе с контекстом запроса.
    Future<(int? estimated, LlmContext request)> loadAndAsk(
      List<String> lines,
    ) async {
      final store = MemorySessionStore()
        ..putText(
          id,
          j.journal([j.header(id: id.value, cwd: '/proj'), ...lines]),
        );
      final h = anchorHarness([turn('ok')], sessions: store);
      final loaded = await h.core.runtime.loadSession(
        id,
        const SessionHostPorts(),
      );
      final events = <AgentEvent>[];
      loaded.events.listen(events.add);

      await loaded.prompt(const [TextContent('new request')]);

      final estimated = firstRequestOfTurn(events, 0)?.estimatedTokens;
      final request = h.requestedContexts.first;
      await h.core.runtime.dispose();
      return (estimated, request);
    }

    List<String> branchWithCompaction(int tokensAfter) => [
      j.user('u1', null, text: 'old ${'o' * 6000}'),
      j.answer('a1', 'u1'),
      j.user('u2', 'a1', text: 'kept request'),
      j.answer('a2', 'u2'),
      j.compaction('k1', 'a2', firstKept: 'u2', tokensAfter: tokensAfter),
    ];

    test('a compaction as the last event of the branch: the first request '
        'is estimated by tokensAfter plus the new message', () async {
      // Сжатие реальной сессией: `/compact` пишет запись последним событием.
      final store = MemorySessionStore();
      final first = anchorHarness([
        turn('a' * 8000, input: 3000),
        turn('b' * 8000, input: 7500),
        turn('## Summary'),
      ], sessions: store);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.prompt(const [TextContent('first task')]);
      await created.prompt(const [TextContent('second task')]);
      await created.prompt(const [TextContent('/compact')]);
      await first.core.runtime.dispose();
      final record = (await store.open(
        created.id,
      )).records.whereType<CompactionRecord>().single;

      final second = anchorHarness([turn('ok')], sessions: store);
      final loaded = await second.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
      );
      final events = <AgentEvent>[];
      loaded.events.listen(events.add);
      await loaded.prompt(const [TextContent('new request')]);

      final estimated = firstRequestOfTurn(events, 0)?.estimatedTokens;
      expect(
        estimated,
        record.tokensAfter + estimateMessageTokens(newMessage('new request')),
      );
      // Предпосылка: чистая эвристика дала бы другое число.
      expect(heuristicOf(second.requestedContexts.first), isNot(estimated));
      await second.core.runtime.dispose();
    });

    test('two branches: the later compaction lies on the inactive branch — '
        'the anchor is from the record of the active one', () async {
      final (estimated, request) = await loadAndAsk([
        j.user('u1', null, text: 'old ${'o' * 6000}'),
        j.answer('a1', 'u1'),
        j.user('u2', 'a1', text: 'kept request'),
        j.answer('a2', 'u2'),
        // Активная ветка: сжатие k1 (tokensAfter 900) и слова после него.
        j.compaction('k1', 'a2', firstKept: 'u2', tokensAfter: 900),
        j.user('uA', 'k1', text: 'after the compaction'),
        // Неактивная ветка, записанная позже: своё сжатие (tokensAfter 4000).
        j.user('u2b', 'a1', text: 'other request'),
        j.answer('a2b', 'u2b'),
        j.compaction('k2', 'a2b', firstKept: 'u2b', tokensAfter: 4000),
        // Возврат на активную ветку.
        j.leaf('l1', 'k2', target: 'uA'),
      ]);

      expect(
        estimated,
        900 +
            estimateMessageTokens(newMessage('after the compaction')) +
            estimateMessageTokens(newMessage('new request')),
      );
      expect(heuristicOf(request), isNot(estimated));
    });

    test('tokensAfter 0 in the journal is not an anchor: the plain '
        'heuristic (D6)', () async {
      final (estimated, request) = await loadAndAsk(branchWithCompaction(0));

      expect(estimated, heuristicOf(request));
    });

    test('a journal without a compaction: the plain heuristic', () async {
      final (estimated, request) = await loadAndAsk([
        j.user('u1', null, text: 'hello'),
        j.answer('a1', 'u1'),
      ]);

      expect(estimated, heuristicOf(request));
    });
  });
}
