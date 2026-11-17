import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Usage суммаризатора (agent-compaction «Usage суммаризатора»; design.md
/// change `add-usage-ledger`, D4, Q6). Задача 1.3.
///
/// Тесты идут через `AgentSession.prompt` на `ScriptedStreamFunction`:
/// проверяется то, что видит хост — событие `ContextCompacted`, запись
/// `compaction` в журнале и `TurnEnded.usage`.
void main() {
  // Цену usage ставит провайдерный слой по ценам модели (`calculateCost`),
  // а не сценарий: поэтому у модели тестов есть цены, а ожидаемый usage
  // считается теми же ценами.
  const rates = ModelCost(input: 1, output: 2);
  Usage priced(int input, int output) =>
      calculateCost(Usage(input: input, output: output), rates);
  final summaryUsage = priced(900, 120);

  ModelRef pricedModel(int window) {
    final m = modelWithWindow(window);
    return ModelRef(
      provider: m.provider,
      id: m.id,
      api: m.api,
      baseUrl: m.baseUrl,
      contextWindow: m.contextWindow,
      maxOutputTokens: m.maxOutputTokens,
      cost: rates,
    );
  }

  Map<String, Object?> summaryStep(String text, {Usage? usage}) => {
    'reply': [
      {'text': text},
    ],
    'usage': (usage ?? summaryUsage).toJson(),
  };

  Map<String, Object?> turnStep(String text, Usage usage) => {
    'reply': [
      {'text': text},
    ],
    'usage': usage.toJson(),
  };

  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    int window = 32000,
    CompactionOverrides compaction = const CompactionOverrides(
      keepRecentTokens: 2048,
    ),
  }) {
    return CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      defaultModel: pricedModel(window),
      compaction: compaction,
      steps: steps,
    );
  }

  Future<List<CompactionRecord>> compactions(
    CoreHarness h,
    AgentSession session,
  ) async => (await h.sessions.open(
    session.id,
  )).records.whereType<CompactionRecord>().toList();

  test('/compact: details.usage and the model in the record, usage and the '
      'model in ContextCompacted (scenario "/compact с usage")', () async {
    final h = harness([
      textStep('a' * 8000),
      textStep('b' * 16000),
      summaryStep('## Summary\n- done'),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);

    await session.prompt(const [TextContent('/compact')]);

    final record = (await compactions(h, session)).single;
    final details = record.details!;
    expect(
      Usage.fromJson(details['usage']! as Map<String, Object?>),
      summaryUsage,
    );
    expect(details['summaryModel'], 'test/model-1');
    final event = events.whereType<ContextCompacted>().single;
    expect(event.usage, summaryUsage);
    expect(event.model, 'test/model-1');
    await h.core.runtime.dispose();
  });

  test('every compaction pass has its own record and its own event, each '
      'with the usage of its own summarizer call (CMP-5)', () async {
    // Запросы суммаризатора узнаются по ключу кэша `<сессия>:summary`; каждый
    // ответ — с usage, отличным от других (`input` растёт с номером вызова).
    // Разрезанный ход даёт два запроса на проход, поэтому событий меньше
    // вызовов; число проходов (не меньше двух) подбирается размерами ниже.
    final turns = ScriptedStreamFunction.fromJson({
      'steps': [for (var i = 0; i < 12; i++) textStep('a' * 8000)],
    });
    final summarizer = ScriptedStreamFunction.fromJson({
      'steps': [
        for (var i = 0; i < 12; i++)
          summaryStep('x' * 20000, usage: Usage(input: 100 + i, output: 10)),
      ],
    });
    final clock = FakeClock();
    final store = MemorySessionStore();
    final core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: FakeGate(),
        logger: RecordingLogger(),
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
      ),
      config: CoreConfig(
        defaultModel: modelWithWindow(16384),
        compaction: const CompactionOverrides(
          reserveTokens: 2048,
          keepRecentTokens: 2048,
          keepRecentUserTurns: 1,
        ),
      ),
      streamFunction: (ref, context, {cancel}) {
        if (context.cacheKey?.endsWith(':summary') ?? false) {
          return summarizer.call(ref, context, cancel: cancel);
        }
        return turns.call(ref, context, cancel: cancel);
      },
    );
    final session = await core.runtime.createSession(SessionSpec(cwd: '/proj'));
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    for (var i = 0; i < 8; i++) {
      await session.prompt([TextContent('task $i')]);
    }
    await session.prompt(const [TextContent('/compact')]);

    final compacted = events.whereType<ContextCompacted>().toList();
    final records = (await store.open(
      session.id,
    )).records.whereType<CompactionRecord>().toList();
    expect(compacted.length, greaterThanOrEqualTo(2));
    expect(records, hasLength(compacted.length));
    for (final (i, event) in compacted.indexed) {
      final recorded = records[i].details!['usage'];
      expect(recorded, isA<Map<String, Object?>>(), reason: 'record $i');
      expect(event.usage, isNotNull, reason: 'event $i');
      expect(event.usage, Usage.fromJson(recorded! as Map<String, Object?>));
      expect(event.model, 'test/model-1');
    }
    expect(
      {for (final e in compacted) e.usage?.input},
      hasLength(compacted.length),
      reason: 'each pass has its own usage',
    );
    await core.runtime.dispose();
  });

  test('an emergency compaction in the middle of a turn: TurnEnded.usage is '
      'the sum of the steps, without the summarizer; the usage is in the '
      'record (scenario "Аварийное сжатие посреди хода")', () async {
    const stepUsage = Usage(input: 30, output: 7);
    final h = harness([
      textStep('a' * 8000),
      textStep('b' * 16000),
      // Третий ход: провайдер сообщает о переполнении окна, ядро сжимает
      // журнал (суммаризатор тратит токены) и повторяет шаг.
      {
        'error': {'class': 'overflow', 'message': 'prompt is too long'},
      },
      summaryStep('## Summary\n- first and second'),
      // Срез режет ход, и проход делает два запроса; usage второго нулевой,
      // сумма проходов проверяется отдельным тестом «разрезанный ход».
      summaryStep('Context of the split turn.', usage: const Usage()),
      turnStep('Done.', stepUsage),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    events.clear();

    final result = await session.prompt(const [TextContent('third task')]);

    expect(
      h.logger.eventsOf('compaction.done').single.fields['trigger'],
      'overflow',
    );
    expect(result.reason, TurnEndReason.completed);
    expect(result.usage.input, stepUsage.input);
    expect(result.usage.output, stepUsage.output);
    final ended = events.whereType<TurnEnded>().single;
    expect(ended.usage.input, stepUsage.input);
    expect(ended.usage.output, stepUsage.output);
    final record = (await compactions(h, session)).single;
    expect(
      Usage.fromJson(record.details!['usage']! as Map<String, Object?>),
      summaryUsage,
    );
    expect(events.whereType<ContextCompacted>().single.usage, summaryUsage);
    await h.core.runtime.dispose();
  });

  test('a split turn: two summarizer requests of one pass give the sum of '
      'their usage in one record and one event (D4, scenario "Разрезанный '
      'ход")', () async {
    final regionUsage = priced(900, 120);
    final contextUsage = priced(40, 10);
    final h = harness([
      textStep('a' * 8000),
      textStep('b' * 16000),
      {
        'error': {'class': 'overflow', 'message': 'prompt is too long'},
      },
      // Срез режет третий ход: резюме региона и контекст начала хода.
      summaryStep('## Summary\n- first and second', usage: regionUsage),
      summaryStep('Context of the split turn.', usage: contextUsage),
      turnStep('Done.', const Usage(input: 30, output: 7)),
    ]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    events.clear();

    await session.prompt(const [TextContent('third task')]);

    final record = (await compactions(h, session)).single;
    expect(record.details!['splitTurn'], isTrue);
    final sum = regionUsage + contextUsage;
    expect(
      Usage.fromJson(record.details!['usage']! as Map<String, Object?>),
      sum,
    );
    final event = events.whereType<ContextCompacted>().single;
    expect(event.usage, sum);
    expect(event.model, 'test/model-1');
    await h.core.runtime.dispose();
  });

  /// Журнал с одной записью `compaction` с [details], как его оставило бы
  /// ядро; возвращает событие реплея.
  Future<ContextCompacted> replayOf(Map<String, Object?> details) async {
    final h = harness([]);
    final at = DateTime.utc(2026);
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
    final store = h.sessions as MemorySessionStore;
    await store.create(
      SessionHeader(
        id: id,
        cwd: '/proj',
        created: at,
        agent: const AgentInfo(name: 'test', version: '0'),
      ),
    );
    await store.append(
      id,
      MessageRecord(
        id: 'r0000000',
        parentId: null,
        timestamp: at,
        message: UserMessage(const [TextContent('task')], timestamp: at),
      ),
    );
    await store.append(
      id,
      CompactionRecord(
        id: 'r0000001',
        parentId: 'r0000000',
        timestamp: at,
        summary: 'summary',
        firstKeptId: 'r0000000',
        tokensBefore: 900,
        tokensAfter: 100,
        details: details,
      ),
    );
    final loaded = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );
    final event = loaded.replay().whereType<ContextCompacted>().single;
    await h.core.runtime.dispose();
    return event;
  }

  const oldDetails = {
    'readFiles': <String>[],
    'modifiedFiles': <String>[],
    'splitTurn': false,
  };

  test('replay of a new record: usage from details.usage, model from '
      'details.summaryModel', () async {
    final event = await replayOf({
      ...oldDetails,
      'summaryModel': 'openai/gpt-4o-mini',
      'usage': summaryUsage.toJson(),
    });

    expect(event.usage, summaryUsage);
    expect(event.model, 'openai/gpt-4o-mini');
  });

  test('replay of an old record without details.usage: usage == null, the '
      'model from summaryModel; no summaryModel: null (scenario "Старая '
      'запись без usage")', () async {
    final withModel = await replayOf({
      ...oldDetails,
      'summaryModel': 'test/model-1',
    });
    final without = await replayOf(oldDetails);

    expect(withModel.tokensBefore, 900);
    expect(withModel.usage, isNull);
    expect(withModel.model, 'test/model-1');
    expect(without.usage, isNull);
    expect(without.model, isNull);
  });
}
