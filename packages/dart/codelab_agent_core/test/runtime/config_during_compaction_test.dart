import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/tree.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../session/recording_store.dart';

/// Смена конфигурации во время сжатия сохраняется в журнале (agent-runtime
/// «Смена конфигурации во время сжатия сохраняется в журнале», agent-sessions
/// «Последовательная запись журнала»; change
/// `fix-config-change-during-background-compaction`, D1, D2, D4; SES-16,
/// CMP-12).
///
/// Суммаризатор «висит» на `Completer` теста: пока он держит запрос резюме,
/// смена конфигурации идёт мимо сжатия, как у клиента ACP. После отпускания
/// сессия закрывается, журнал открывается второй раз (`loadSession`), и
/// смена должна быть на месте.
void main() {
  ModelRef model(String id, int window) => ModelRef(
    provider: 'test',
    id: id,
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: window,
    maxOutputTokens: 4096,
    supportsReasoning: true,
  );

  final reviewer = MarkdownFile(
    path: '/home/.codelab/agents/reviewer.md',
    scope: ExtensionScope.user,
    body: 'Review carefully.',
    bodyLine: 6,
    frontmatter: const ConfigTree(
      kind: ConfigLayerKind.user,
      source: '/home/.codelab/agents/reviewer.md',
      values: {
        'name': 'reviewer',
        'description': 'Reviews',
        'model': 'test/other',
        'mode': 'plan',
        'tools': ['read', 'search'],
      },
    ),
  );

  final overflow = <String, Object?>{
    'error': {'class': 'overflow', 'message': 'prompt is too long'},
  };

  late MemorySessionStore memory;
  late RecordingStore store;
  late Completer<void> started;
  late Completer<void> release;

  setUp(() {
    memory = MemorySessionStore();
    store = RecordingStore(memory);
    started = Completer<void>();
    release = Completer<void>();
  });

  /// [holdSummary]: запрос резюме (`cacheKey` на `:summary`) ждёт [release].
  CoreHarness build(
    List<Map<String, Object?>> steps, {
    int window = 16384,
    SessionStore? sessions,
    bool holdSummary = true,
    CompactionOverrides compaction = const CompactionOverrides(),
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: {...noExec, ...inMemoryJournal},
    gate: FakeGate(),
    sessions: sessions ?? store,
    defaultModel: model('model-1', window),
    models: FixedModelCatalog([
      model('model-1', window),
      model('other', window),
    ]),
    projectFiles: _Port([reviewer]),
    compaction: compaction,
    steps: steps,
    hold: (context) {
      if (!holdSummary || !(context.cacheKey ?? '').endsWith(':summary')) {
        return null;
      }
      if (!started.isCompleted) {
        started.complete();
      }
      return release.future;
    },
  );

  /// Два хода, после второго стартует фоновое `afterTurn`; запрос резюме
  /// ушёл и висит.
  Future<(CoreHarness, AgentSession)> backgroundCompaction() async {
    final h = build([
      textStep('a' * 8000),
      textStep('b' * 36000),
      textStep('## Open user requests\n- third task'),
      textStep('Done.'),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    await started.future;
    return (h, session);
  }

  Future<(AgentSession, CoreHarness)> reload(SessionId id) async {
    final second = build(const [], sessions: memory, holdSummary: false);
    final loaded = await second.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );
    return (loaded, second);
  }

  /// Отпускает резюме, ждёт фон (третий ход), закрывает рантайм и открывает
  /// журнал вторым рантаймом.
  Future<(AgentSession, CoreHarness)> finishAndReload(
    CoreHarness h,
    AgentSession session,
  ) async {
    expect(release.isCompleted, isFalse, reason: 'the summary still hangs');
    release.complete();
    await session.prompt(const [TextContent('third task')]);
    await h.core.runtime.dispose();
    return reload(session.id);
  }

  /// Одна запись `compaction`, и она на активной ветке.
  Future<void> expectCompactionOnBranch(SessionId id) async {
    final snapshot = await memory.open(id);
    expect(snapshot.records.whereType<CompactionRecord>(), hasLength(1));
    expect(pathToLeaf(snapshot).whereType<CompactionRecord>(), hasLength(1));
  }

  group('background afterTurn compaction', () {
    test('the mode set during the summary survives loadSession', () async {
      final (h, session) = await backgroundCompaction();

      await session.setMode(ModeId.plan);
      final (loaded, _) = await finishAndReload(h, session);

      expect(loaded.mode, ModeId.plan);
      await expectCompactionOnBranch(session.id);
    });

    test('the model set during the summary survives loadSession', () async {
      final (h, session) = await backgroundCompaction();

      await session.setModel(const ModelId('test/other'));
      final (loaded, second) = await finishAndReload(h, session);

      expect(loaded.model.id, 'other');
      expect(second.logger.eventsOf('session.model.not_restored'), isEmpty);
      await expectCompactionOnBranch(session.id);
    });

    test('the effort set during the summary survives loadSession', () async {
      final (h, session) = await backgroundCompaction();

      await session.setEffort(ReasoningEffort.high);
      final (loaded, _) = await finishAndReload(h, session);

      expect(loaded.effort, ReasoningEffort.high);
      await expectCompactionOnBranch(session.id);
    });

    test('the agent set during the summary survives loadSession', () async {
      final (h, session) = await backgroundCompaction();

      await session.setAgent('reviewer');
      final (loaded, _) = await finishAndReload(h, session);

      expect(loaded.agent, 'reviewer');
      expect(loaded.mode, ModeId.plan);
      expect(loaded.model.id, 'other');
      await expectCompactionOnBranch(session.id);
    });
  });

  test('the mode set during /compact survives loadSession', () async {
    final h = build(
      [
        textStep('a' * 8000),
        textStep('b' * 16000),
        textStep('## Summary\n- done'),
      ],
      window: 32000,
      compaction: const CompactionOverrides(keepRecentTokens: 2048),
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);

    final command = session.prompt(const [TextContent('/compact')]);
    await started.future;
    await session.setMode(ModeId.plan);
    release.complete();
    final result = await command;
    await h.core.runtime.dispose();

    expect(result.reason, TurnEndReason.completed);
    final compacted = events.whereType<ContextCompacted>().single;
    final reply = [
      for (final e in events.whereType<MessageEnded>())
        if (e.message case AssistantMessage(:final content))
          content.whereType<TextContent>().map((b) => b.text).join(),
    ];
    // Ответ команды — последнее сообщение; раньше шли ответы двух ходов.
    expect(
      reply.last,
      'Compacted: ${compacted.tokensBefore} → ${compacted.tokensAfter} tokens.',
    );
    final (loaded, _) = await reload(session.id);
    expect(loaded.mode, ModeId.plan);
    await expectCompactionOnBranch(session.id);
  });

  test('the model set during the emergency compaction survives '
      'loadSession', () async {
    final h = build([
      textStep('b' * 8000),
      textStep('a' * 8000),
      overflow,
      textStep('## Open user requests\n- third task'),
      textStep('Turn prefix: first task.'),
      textStep('Done.'),
    ], compaction: const CompactionOverrides(keepRecentTokens: 1000));
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt(const [TextContent('zeroth task')]);
    await session.prompt(const [TextContent('first task')]);

    final third = session.prompt(const [TextContent('second task')]);
    await started.future;
    await session.setModel(const ModelId('test/other'));
    release.complete();
    final result = await third;
    await h.core.runtime.dispose();

    expect(result.reason, TurnEndReason.completed);
    final (loaded, second) = await reload(session.id);
    expect(loaded.model.id, 'other');
    expect(second.logger.eventsOf('session.model.not_restored'), isEmpty);
    await expectCompactionOnBranch(session.id);
  });

  test('close during the summary while the compaction record waits behind '
      'a mode change: no compaction, the mode survives (R3)', () async {
    final (h, session) = await backgroundCompaction();
    final gate = Completer<void>();
    store
      ..appendGate = gate.future
      ..gateWhen = (r) => r is ModeChangeRecord;
    final change = session.setMode(ModeId.plan);
    await _until(() => store.waiting > 0, 'mode_change reached the store');
    release.complete();
    await _pump();

    final closing = session.close();
    gate.complete();
    await change;
    await closing;
    await h.core.runtime.dispose();

    final snapshot = await memory.open(session.id);
    expect(snapshot.records.whereType<CompactionRecord>(), isEmpty);
    expect(snapshot.records.whereType<ModeChangeRecord>(), hasLength(1));
    final (loaded, _) = await reload(session.id);
    expect(loaded.mode, ModeId.plan);
  });

  test('the mode set while a message of the turn is being written survives '
      'loadSession (SES-16)', () async {
    final h = build([textStep('The answer.')], holdSummary: false);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final gate = Completer<void>();
    store
      ..appendGate = gate.future
      ..gateWhen = (r) => r is MessageRecord && r.message is AssistantMessage;

    final turn = session.prompt(const [TextContent('go')]);
    await _until(() => store.waiting > 0, 'the answer reached the store');
    var changed = false;
    final change = session.setMode(ModeId.plan).then((r) {
      changed = true;
      return r;
    });
    await _pump();
    // Предусловие SES-16: смена стоит в очереди писателя за записью ответа,
    // она ещё не в хранилище и не завершена.
    expect(
      store.appended.map((a) => a.record).whereType<ModeChangeRecord>(),
      isEmpty,
    );
    expect(changed, isFalse);
    gate.complete();
    await change;
    final result = await turn;
    await h.core.runtime.dispose();

    expect(result.reason, TurnEndReason.completed);
    final (loaded, _) = await reload(session.id);
    expect(loaded.mode, ModeId.plan);
    final answers = [
      for (final e in loaded.replay().whereType<MessageEnded>())
        if (e.message is AssistantMessage) e.message,
    ];
    expect(answers, hasLength(1), reason: 'the answer is on the active branch');
  });
}

/// Ждёт условие микрозадачами, но не бесконечно: иначе сбой в коде превратил
/// бы тест в зависание (запрет таймеров для синхронизации, `AGENTS.md` ядра).
Future<void> _until(bool Function() condition, String what) async {
  for (var i = 0; i < 10000; i++) {
    if (condition()) {
      return;
    }
    await Future<void>.value();
  }
  fail('never happened: $what');
}

Future<void> _pump() async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.value();
  }
}

final class _Port implements ProjectFilesSource {
  _Port(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}
