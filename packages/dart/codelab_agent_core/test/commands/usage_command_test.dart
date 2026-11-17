import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// Встроенная команда `/usage [rebuild]` (agent-slash-commands «Команда
/// /usage»; design.md change `add-usage-ledger`, D5, Q7; `agent-core/
/// 12-observability-and-errors.md` §12.6.1). Задача 1.4.
///
/// Тесты идут через публичные `AgentSession.prompt` и `events`, как у хостов.
/// Модели — две: с ценами в каталоге сессии (`test/priced`) и без
/// (`test/free`, `cost == null`): «цена неизвестна» решает каталог (Q4).
void main() {
  final priced = _model('priced', const ModelCost(input: 1, output: 2));
  final free = _model('free', null);

  /// Ответ модели с usage; стоимость — как её посчитал бы адаптер провайдера
  /// (у модели без цен — ноль, `calculateCost`).
  Map<String, Object?> answer(Usage usage) => {
    'reply': [
      {'text': 'ok'},
    ],
    'usage': usage.toJson(),
  };

  const first = Usage(
    input: 1000,
    output: 100,
    cacheRead: 2000,
    cost: UsageCost(input: 0.001, output: 0.0002, cacheRead: 0.0005),
  );
  const second = Usage(
    input: 500,
    output: 50,
    cacheRead: 1000,
    cost: UsageCost(input: 0.0005, output: 0.0001, cacheRead: 0.0002),
  );
  const unpriced = Usage(input: 300, output: 30);

  late _FakeStore store;
  late CoreHarness h;
  late AgentSession session;

  /// Сессия на [model]; [steps] — ответы модели по порядку.
  Future<void> open(
    List<Map<String, Object?>> steps, {
    ModelRef? model,
    bool withStore = true,
  }) async {
    store = _FakeStore();
    h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      models: FixedModelCatalog([priced, free]),
      defaultModel: model ?? priced,
      usageLedger: withStore ? store : null,
      steps: steps,
    );
    session = await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));
  }

  tearDown(() async => h.core.runtime.dispose());

  /// Отправляет [text] и собирает события хода и текст ответа.
  ///
  /// Поздний подписчик `events` получает хвост предыдущего хода (контракт
  /// доставки `AgentSession.events`), поэтому берутся события после
  /// последнего `TurnStarted`.
  Future<({List<AgentEvent> events, String text, TurnResult result})> ask(
    String text, {
    CancelToken? cancel,
  }) async {
    final all = <AgentEvent>[];
    final subscription = session.events.listen(all.add);
    final result = await session.prompt([TextContent(text)], cancel: cancel);
    await pumpEventQueue();
    await subscription.cancel();
    final events = all.sublist(all.lastIndexWhere((e) => e is TurnStarted));
    final ended = [
      for (final e in events.whereType<MessageEnded>())
        if (e.message is AssistantMessage) e,
    ];
    final reply = ended.isEmpty
        ? ''
        : ended.last.message.content
              .whereType<TextContent>()
              .map((b) => b.text)
              .join();
    return (events: events, text: reply, result: result);
  }

  Future<int> journalLength() async =>
      (await h.sessions.open(session.id)).records.length;

  group('the text (scenario "/usage после двух ходов", D5, Q7)', () {
    test('two turns on a priced model: the text line by line, the file is '
        'written, the model is not called, the journal gets no records '
        'of the command', () async {
      await open([answer(first), answer(second)]);
      await ask('first task');
      await ask('second task');
      final records = await journalLength();

      final reply = await ask('/usage');

      expect(
        reply.text,
        'Session usage: 2 turns, 2 steps\n'
        'Total: input 1500, output 150, cache read 3000, cache write 0, '
        'cost \$0.0025\n'
        'By model:\n'
        '  test/priced: 2 steps, input 1500, output 150, cache read 3000, '
        'cache write 0, cost \$0.0025\n'
        'Ledger: rebuilt from journal ($records records)',
      );
      expect(reply.text.endsWith('\n'), isFalse);
      expect(reply.result.reason, TurnEndReason.completed);
      expect(
        [for (final e in reply.events) e.runtimeType],
        [TurnStarted, MessageStarted, MessageDelta, MessageEnded, TurnEnded],
      );
      expect(h.requestedModels, hasLength(2), reason: 'the model is idle');
      expect(await journalLength(), records);
      expect(store.files[session.id], isNotNull);
    });

    test(
      'a repeat: up to date, the text above the last line is the same',
      () async {
        await open([answer(first), answer(second)]);
        await ask('first task');
        await ask('second task');
        final records = await journalLength();
        final one = await ask('/usage');

        final two = await ask('/usage');

        final lines = two.text.split('\n');
        expect(lines.last, 'Ledger: up to date ($records records)');
        expect(
          lines.take(lines.length - 1).join('\n'),
          one.text.split('\n').take(lines.length - 1).join('\n'),
        );
      },
    );

    test('/usage rebuild: rebuilt from journal, the log has reason explicit '
        '(scenario "/usage rebuild")', () async {
      await open([answer(first)]);
      await ask('first task');
      final records = await journalLength();
      await ask('/usage');

      final reply = await ask('/usage rebuild');

      expect(
        reply.text.split('\n').last,
        'Ledger: rebuilt from journal ($records records)',
      );
      expect(
        h.logger.eventsOf('usage.ledger.rebuild').last.fields['reason'],
        'explicit',
      );
    });

    test('without a port: rebuilt in memory', () async {
      await open([answer(first)], withStore: false);
      await ask('first task');
      final records = await journalLength();

      final reply = await ask('/usage');

      expect(
        reply.text.split('\n').last,
        'Ledger: rebuilt in memory ($records records)',
      );
    });

    test(
      'a write failure: rebuilt, not saved (the reason of the OS)',
      () async {
        await open([answer(first)]);
        await ask('first task');
        store.failWith = const UsageLedgerStoreException('Permission denied');

        final reply = await ask('/usage');

        expect(
          reply.text.split('\n').last,
          'Ledger: rebuilt, not saved (Permission denied)',
        );
      },
    );

    test('an empty session: one line', () async {
      await open([]);

      final reply = await ask('/usage');

      expect(reply.text, 'Session usage: no model requests yet');
    });

    test('the arguments: /usage now is the usage line, the ledger is not '
        'built', () async {
      await open([answer(first)]);
      await ask('first task');

      final reply = await ask('/usage now');

      expect(reply.text, 'Usage: /usage [rebuild]');
      expect(reply.result.reason, TurnEndReason.completed);
      expect(store.reads, 0);
      expect(store.writes, isEmpty);
      expect(h.logger.eventsOf('usage.ledger.rebuild'), isEmpty);
    });
  });

  group('the cost and the noUsage mark (Q7 (а))', () {
    test(
      'a model without prices: cost unknown everywhere, no \$0.0000',
      () async {
        await open([answer(unpriced), answer(unpriced)], model: free);
        await ask('first task');
        await ask('second task');

        final text = (await ask('/usage')).text;

        expect(text, contains('Total: input 600'));
        expect(text, contains('  test/free: 2 steps, input 600'));
        expect(text, isNot(contains('\$0.0000')));
        final costLines = text.split('\n').where((l) => l.contains('cost'));
        expect(costLines, isNotEmpty);
        expect(costLines, everyElement(endsWith('cost unknown')));
      },
    );

    test('a priced part and an unpriced part: ~\$ in the total, each model '
        'on its own', () async {
      await open([answer(first), answer(unpriced)]);
      await ask('first task');
      await ask('/model test/free');
      await ask('second task');

      final lines = (await ask('/usage')).text.split('\n');

      expect(
        lines.singleWhere((l) => l.startsWith('Total:')),
        endsWith('cost ~\$0.0017'),
      );
      expect(
        lines.singleWhere((l) => l.startsWith('  test/priced:')),
        endsWith('cost \$0.0017'),
      );
      expect(
        lines.singleWhere((l) => l.startsWith('  test/free:')),
        endsWith('cost unknown'),
      );
    });

    test('an answer without usage: ~ before the number of input tokens in the '
        'lines it belongs to', () async {
      await open([answer(first), answer(const Usage())]);
      await ask('first task');
      await ask('second task');

      final lines = (await ask('/usage')).text.split('\n');

      expect(
        lines.singleWhere((l) => l.startsWith('Total:')),
        contains('input ~1000'),
      );
      expect(
        lines.singleWhere((l) => l.startsWith('  test/priced:')),
        contains('input ~1000'),
      );
    });

    test('a turn answered with usage only: no ~ before input', () async {
      await open([answer(first)]);
      await ask('first task');

      final text = (await ask('/usage')).text;

      expect(text, startsWith('Session usage: 1 turns, 1 steps'));
      expect(text, isNot(contains('input ~')));
    });
  });

  group('Subagents and Summaries (D1 пп. 5, 6; D2; D5)', () {
    const sub = Usage(input: 40, cost: UsageCost(input: 0.0004));
    // Токены при нулевой стоимости: цена прогона неизвестна (эвристика Q13).
    const subNoPrice = Usage(input: 70);
    const summary = Usage(
      input: 900,
      output: 120,
      cost: UsageCost(input: 0.0009, output: 0.0003),
    );

    /// Сессия, загруженная из журнала, собранного вручную.
    Future<List<String>> usageOf(
      List<Usage> subagents,
      String summaryModel,
      Usage summaryUsage,
    ) async {
      await open([]);
      final at = DateTime.utc(2026);
      const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0B');
      final memory = h.sessions as MemorySessionStore;
      await memory.create(
        SessionHeader(
          id: id,
          cwd: '/proj',
          created: at,
          agent: const AgentInfo(name: 'test', version: '0'),
        ),
      );
      var n = 0;
      String? parent;
      Future<void> add(
        SessionRecord Function(String id, String? p) make,
      ) async {
        final recordId = 'r${(n++).toString().padLeft(7, '0')}';
        await memory.append(id, make(recordId, parent));
        parent = recordId;
      }

      await add(
        (i, p) => MessageRecord(
          id: i,
          parentId: p,
          timestamp: at,
          message: UserMessage(const [TextContent('task')], timestamp: at),
        ),
      );
      await add(
        (i, p) => MessageRecord(
          id: i,
          parentId: p,
          timestamp: at,
          message: AssistantMessage(
            content: const [TextContent('ok')],
            model: priced,
            usage: first,
            stopReason: StopReason.stop,
            timestamp: at,
          ),
        ),
      );
      for (final (k, usage) in subagents.indexed) {
        await add(
          (i, p) => SubagentRecord(
            id: i,
            parentId: p,
            timestamp: at,
            subagentId: 's$k',
            toolCallId: 'call_$k',
            agent: 'explore',
            description: 'look',
            status: 'completed',
            usage: usage,
          ),
        );
      }
      await add(
        (i, p) => CompactionRecord(
          id: i,
          parentId: p,
          timestamp: at,
          summary: 'summary',
          firstKeptId: 'r0000000',
          tokensBefore: 900,
          tokensAfter: 100,
          details: {
            'summaryModel': summaryModel,
            'usage': summaryUsage.toJson(),
          },
        ),
      );
      session = await h.core.runtime.loadSession(id, const SessionHostPorts());
      return (await ask('/usage')).text.split('\n');
    }

    String line(List<String> lines, String prefix) =>
        lines.singleWhere((l) => l.startsWith(prefix));

    test('both lines appear with the counters; Total sums everything and '
        'the models list has the steps only', () async {
      final lines = await usageOf([sub], 'test/priced', summary);

      expect(lines.first, 'Session usage: 1 turns, 1 steps');
      expect(
        line(lines, 'Subagents:'),
        startsWith(
          'Subagents: 1 runs, input 40, output 0, cache read 0, '
          'cache write 0, cost ',
        ),
      );
      expect(
        line(lines, 'Summaries:'),
        startsWith(
          'Summaries: 1, input 900, output 120, cache read 0, '
          'cache write 0, cost ',
        ),
      );
      expect(
        line(lines, 'Total:'),
        startsWith(
          'Total: input 1940, output 220, cache read 2000, cache write 0',
        ),
      );
      expect(
        line(lines, '  test/priced:'),
        startsWith('  test/priced: 1 steps, input 1000, output 100'),
      );
    });

    test('everything priced: \$ in Subagents, Summaries and Total', () async {
      final lines = await usageOf([sub], 'test/priced', summary);

      expect(line(lines, 'Subagents:'), endsWith('cost \$0.0004'));
      expect(line(lines, 'Summaries:'), endsWith('cost \$0.0012'));
      expect(line(lines, 'Total:'), endsWith('cost \$0.0033'));
    });

    test(
      'one priced run and one with tokens at zero cost: Subagents ~\$; '
      'the summary model is without prices in the catalog: Summaries '
      'unknown; Total ~\$ (scenario "Цена субагентов и суммаризатора")',
      () async {
        final lines = await usageOf(
          [sub, subNoPrice],
          'test/free',
          const Usage(input: 900, output: 120),
        );

        expect(line(lines, 'Subagents:'), endsWith('cost ~\$0.0004'));
        expect(line(lines, 'Summaries:'), endsWith('cost unknown'));
        expect(line(lines, 'Total:'), endsWith('cost ~\$0.0021'));
      },
    );

    test(
      'a run with tokens at zero cost alone: Subagents cost unknown',
      () async {
        final lines = await usageOf([subNoPrice], 'test/priced', summary);

        expect(line(lines, 'Subagents:'), endsWith('cost unknown'));
        expect(line(lines, 'Total:'), contains('cost ~\$'));
      },
    );

    test(
      'a summary model absent from the catalog: Summaries cost unknown',
      () async {
        final lines = await usageOf(
          const [],
          'gone/removed',
          const Usage(input: 900, output: 120),
        );

        expect(line(lines, 'Summaries:'), endsWith('cost unknown'));
        expect(lines.any((l) => l.startsWith('Subagents:')), isFalse);
      },
    );

    test('with zero counters the lines are absent', () async {
      await open([answer(first)]);
      await ask('first task');

      final text = (await ask('/usage')).text;

      expect(text, startsWith('Session usage: 1 turns, 1 steps'));
      expect(text, isNot(contains('Subagents:')));
      expect(text, isNot(contains('Summaries:')));
    });
  });

  group('the slot, the journal and the cancel', () {
    test('the cancel before the answer: cancelled without a message; the '
        'write that has started is finished', () async {
      await open([answer(first)]);
      await ask('first task');
      store.gate = Completer<void>();

      final reply = ask('/usage');
      // Без команды запись не начнётся: ждём ответ, а не зависаем.
      await Future.any([store.writeStarted, reply.then<void>((_) {})]);
      await session.cancel();
      final cancelled = await reply;

      expect(cancelled.result.reason, TurnEndReason.cancelled);
      expect(cancelled.text, '');
      expect(
        [for (final e in cancelled.events) e.runtimeType],
        [TurnStarted, TurnEnded],
      );
      expect(store.files[session.id], isNull);
      store.gate!.complete();
      await pumpEventQueue();
      expect(store.files[session.id], isNotNull);
    });

    test('neither the command nor the answer are written to the journal, '
        'and the slot is free for the next prompt', () async {
      await open([answer(first), answer(second)]);
      await ask('first task');
      final before = (await h.sessions.open(session.id)).records.length;

      final plain = await ask('/usage');
      await ask('/usage rebuild');
      final after = await h.sessions.open(session.id);

      expect(plain.text, startsWith('Session usage: 1 turns, 1 steps'));
      expect(after.records.length, before);
      final next = await ask('second task');
      expect(next.result.reason, TurnEndReason.completed);
    });

    test('the session lists the command after status, with the hint', () async {
      await open([]);

      final names = [for (final c in session.commands) c.name];

      expect(names.indexOf('usage'), names.indexOf('status') + 1);
      expect(
        session.commands.singleWhere((c) => c.name == 'usage').inputHint,
        '[rebuild]',
      );
    });
  });
}

ModelRef _model(String id, ModelCost? cost) => ModelRef(
  provider: 'test',
  id: id,
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32768,
  maxOutputTokens: 4096,
  cost: cost,
);

/// Порт файла в памяти (как в `usage_ledger_report_test.dart`): обращения,
/// сбой и ворота записи.
final class _FakeStore implements UsageLedgerStore {
  final files = <SessionId, String>{};
  final writes = <String>[];
  var reads = 0;
  UsageLedgerStoreException? failWith;
  Completer<void>? gate;
  final _started = Completer<void>();

  Future<void> get writeStarted => _started.future;

  @override
  Future<String?> read(SessionId id) async {
    reads++;
    return files[id];
  }

  @override
  Future<void> write(SessionId id, String content) async {
    if (!_started.isCompleted) {
      _started.complete();
    }
    await gate?.future;
    if (failWith case final error?) {
      throw error;
    }
    files[id] = content;
    writes.add(content);
  }
}
