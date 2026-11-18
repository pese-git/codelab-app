import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart' show RecordingLogger;
import 'package:test/test.dart';

import 'support/server_harness.dart';
import 'support/usage_journal.dart';

/// Полная сумма сессии после `session/load`, снимок `load` и суммаризатор в
/// сумме сессии (agent-acp-server «Полная сумма сессии после session/load»,
/// «Уведомление `_codelab/session/usage`»: «Сессия после загрузки»,
/// «Загрузка сессии без шагов», «Загрузка соединением без объявления»,
/// «Суммаризатор в сумме сессии»; design.md change `add-usage-ledger`, D4,
/// D8, D12, Q3, Q6; задача 2.3).
///
/// Почему отдельный файл: журнал собирается записями (`UsageJournal`), а не
/// прогоном, чтобы проверить именно засев и порядок кадров. Файл красный до
/// задачи 2.7: мост всё ещё ставит `beforeLoad` и снимка `load` нет.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  const usageClient = <String, Object?>{
    'fs': {'readTextFile': true, 'writeTextFile': true},
    'terminal': true,
    '_meta': {
      'codelab': {
        'usage': {'version': 1},
      },
    },
  };

  final pricedModel = ModelRef(
    provider: 'scripted',
    id: 'scripted-1',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 32768,
    maxOutputTokens: 4096,
    cost: const ModelCost(
      input: 3,
      output: 15,
      cacheRead: 0.3,
      cacheWrite: 3.75,
    ),
  );

  final sessionId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  Map<String, Object?> tokens([
    int input = 0,
    int output = 0,
    int cacheRead = 0,
    int cacheWrite = 0,
  ]) => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
  };

  Map<String, Object?> asMap(Object? value) =>
      (value! as Map).cast<String, Object?>();

  Map<String, Object?> textStep(String text, Map<String, Object?>? usage) => {
    'reply': [
      {'text': text},
    ],
    'usage': ?usage,
  };

  List<Map<String, Object?>> usageOf(TestClient client) => [
    for (final frame in client.received)
      if (frame case JsonRpcNotification(
        method: '_codelab/session/usage',
        :final params,
      ))
        asMap(params),
  ];

  int positionOfUsage(TestClient client, int seq) => client.received.indexWhere(
    (f) =>
        f is JsonRpcNotification &&
        f.method == '_codelab/session/usage' &&
        (f.params! as Map)['seq'] == seq,
  );

  /// Журнал из трёх ходов, вызова субагента и сжатия с usage суммаризатора:
  /// шаги (1200, 300, 10000) · (100, 20) и (200, 40) с вызовом `agent` ·
  /// (300, 50), ребёнок (500, 100), суммаризатор (900, 120). Суммы: input
  /// 3200, output 630, cacheRead 10000; стоимость 0.02205 (в микродолларах
  /// 11100 + 600 + 1200 + 1650 + 3000 + 4500); 3 хода, 4 шага.
  UsageJournal threeTurns() {
    final journal = UsageJournal(sessionId)
      ..user('Первый вопрос')
      ..assistant('Первый ответ.', pricedUsage(1200, 300, 10000))
      ..user('Найди код авторизации')
      ..assistant('Ищу.', pricedUsage(100, 20), calls: const ['call_1'])
      ..subagent(
        'call_1',
        const Usage(
          input: 500,
          output: 100,
          cost: UsageCost(input: 0.0015, output: 0.0015),
        ),
      )
      ..assistant('Нашёл.', pricedUsage(200, 40))
      ..user('Третий вопрос');
    final thirdUser = journal.lastId;
    journal
      ..assistant('Третий ответ.', pricedUsage(300, 50))
      ..compaction(thirdUser, pricedUsage(900, 120));
    return journal;
  }

  const journalTokens = {
    'input': 3200,
    'output': 630,
    'cacheRead': 10000,
    'cacheWrite': 0,
  };

  /// Сервер, в журнале которого лежит [journal]; клиент объявил `usage`, если
  /// [declare]. `session/load` не выполнен.
  Future<void> serverWith(
    UsageJournal journal, {
    bool declare = true,
    List<Map<String, Object?>> steps = const [],
    UsageLedgerStore? port,
    CompactionOverrides compaction = const CompactionOverrides(),
  }) async {
    final store = JournalStore();
    await journal.seedInto(store);
    h = await ServerHarness.start(
      sessions: store,
      defaultModel: pricedModel,
      steps: steps,
      usageLedger: port,
      compaction: compaction,
    );
    await h.initialize(clientCapabilities: declare ? usageClient : null);
  }

  /// `session/load`; после ответа даёт очереди событий разойтись: снимок
  /// `load` уходит действием `Reply.after`, уже после ответа (D8), и без
  /// паузы тест прочитал бы кадры раньше, чем они пришли.
  Future<JsonRpcResponse> load(TestClient client, {String? id}) async {
    final response = await client.request('session/load', {
      'sessionId': id ?? sessionId.value,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    await pumpEventQueue();
    return response;
  }

  Future<TestClient> connectDeclaring() async {
    final link = InProcessAcpLink();
    unawaited(h.server.serve(link.agent));
    final other = TestClient(link.client);
    await other.start();
    await other.request(
      'initialize',
      ServerHarness.initializeParams(clientCapabilities: usageClient),
    );
    return other;
  }

  Future<Map<String, Object?>> ledgerOf(
    TestClient client, [
    String? id,
  ]) async => (await client.request('_codelab/session/usage/ledger', {
    'sessionId': id ?? sessionId.value,
  })).resultMap;

  group('the seed of a journal with three turns, a subagent and a summary', () {
    late JsonRpcResponse loaded;
    late MemoryUsageLedgerStore port;

    setUp(() async {
      port = MemoryUsageLedgerStore();
      await serverWith(threeTurns(), port: port);
      loaded = await load(h.client);
      expect(loaded.error, isNull);
    });

    test('one load snapshot after the answer and after every replay frame, '
        'without turnId, step and turn', () {
      final frames = usageOf(h.client);
      expect(frames, hasLength(1));
      final load = frames.single;
      expect(load['trigger'], 'load');
      expect(load['seq'], 1);
      expect(load['sessionId'], sessionId.value);
      expect(
        load.keys.toSet().intersection({'turnId', 'step', 'turn'}),
        isEmpty,
      );
      expect(load['currency'], 'USD');
      // После ответа на `session/load` (порядок «реплей → ответ → снимок»,
      // D8), а не в конце реплея: клиент v1 сбрасывает usage при загрузке.
      final answerAt = h.client.received.indexOf(loaded);
      expect(positionOfUsage(h.client, 1), greaterThan(answerAt));
      final lastReplay = h.client.received.lastIndexWhere(
        (f) => f is JsonRpcNotification && f.method == 'session/update',
      );
      expect(positionOfUsage(h.client, 1), greaterThan(lastReplay));
    });

    test(
      'session of the load snapshot is the full sum, without beforeLoad',
      () {
        final session = asMap(usageOf(h.client).single['session']);

        expect(session['turns'], 3);
        expect(session['steps'], 4);
        expect(session['tokens'], journalTokens);
        expect(session['cost'], '0.02205');
        expect(session, isNot(contains('partial')));
      },
    );

    test('session of the snapshot equals total of the ledger by tokens, cost, '
        'turns, steps and partial (D8 invariant)', () async {
      final session = asMap(usageOf(h.client).single['session']);

      final result = await ledgerOf(h.client);

      final total = asMap(result['total']);
      expect(total['tokens'], session['tokens']);
      expect(total['cost'], session['cost']);
      expect(total['turns'], session['turns']);
      expect(total['steps'], session['steps']);
      expect(total['partial'], session['partial']);
      // Субагент и суммаризатор учтены отдельными слагаемыми.
      expect(asMap(result['subagents'])['runs'], 1);
      expect(asMap(result['summaries'])['count'], 1);
      expect(asMap(result['summaries'])['tokens'], tokens(900, 120));
    });

    test('the seed reads and writes no file (D8: in memory)', () {
      expect(port.reads, 0);
      expect(port.writes, 0);
    });

    test('debug acp.usage.seeded has session_id, turns, steps, duration_ms '
        'and no tokens or money', () {
      final records = h.logger.eventsOf('acp.usage.seeded');

      expect(records, hasLength(1));
      expect(records.single.level, LogLevel.debug);
      expect(records.single.fields.keys.toSet(), {
        'session_id',
        'turns',
        'steps',
        'duration_ms',
      });
      expect(records.single.fields['session_id'], sessionId.value);
      expect(records.single.fields['turns'], 3);
      expect(records.single.fields['steps'], 4);
    });

    test('acp.usage.sent for the load snapshot has no turn_id', () {
      final records = h.logger.eventsOf('acp.usage.sent');

      expect(records, hasLength(1));
      expect(records.single.fields['trigger'], 'load');
      expect(records.single.fields['seq'], 1);
      expect(records.single.fields['turn_id'], isNull);
    });
  });

  test('the next turn adds to the seed: seq continues, turns and steps grow '
      '(Сессия после загрузки)', () async {
    await serverWith(
      threeTurns(),
      steps: [
        textStep('Вот ответ.', const {'input': 100, 'output': 50}),
      ],
    );
    await load(h.client);

    final response = await h.prompt(sessionId.value, 'Ещё раз');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final frames = usageOf(h.client);
    expect(frames.map((f) => f['seq']), [1, 2, 3]);
    expect(frames.map((f) => f['trigger']), ['load', 'step', 'turn']);
    for (final frame in frames.skip(1)) {
      final session = asMap(frame['session']);
      expect(session['turns'], 4);
      expect(session['steps'], 5);
      expect(session['tokens'], tokens(3300, 680, 10000, 0));
      expect(session['cost'], '0.0231');
      expect(session, isNot(contains('partial')));
    }
    // Итог хода — только его шаги, без суммы журнала и суммаризатора.
    expect(asMap(frames.last['turn'])['tokens'], tokens(100, 50));
    expect(asMap(frames.last['turn'])['steps'], 1);
  });

  test('a second load by the same connection holder does not seed again '
      '(reattach): the sum and turns do not double, seq grows', () async {
    await serverWith(threeTurns());
    await load(h.client);
    final other = await connectDeclaring();

    final response = await load(other);

    expect(response.error, isNull);
    final frames = usageOf(other);
    expect(frames, hasLength(1));
    expect(frames.single['trigger'], 'load');
    expect(frames.single['seq'], 2);
    final session = asMap(frames.single['session']);
    expect(session['turns'], 3);
    expect(session['steps'], 4);
    expect(session['tokens'], journalTokens);
    expect(h.logger.eventsOf('acp.usage.seeded'), hasLength(1));
    // Журнал по-прежнему равен сумме: пересева и удвоения нет.
    final total = asMap((await ledgerOf(other))['total']);
    expect(total['turns'], 3);
    expect(total['tokens'], journalTokens);
  });

  test('a journal without model answers gives no load snapshot '
      '(Загрузка сессии без шагов)', () async {
    final journal = UsageJournal(sessionId)..user('Вопрос без ответа');
    await serverWith(journal);

    final response = await load(h.client);

    expect(response.error, isNull);
    expect(usageOf(h.client), isEmpty);
    expect(h.logger.eventsOf('acp.usage.sent'), isEmpty);
  });

  test('a connection that did not declare usage gets no snapshots and the '
      'same replay and answer (Загрузка соединением без объявления)', () async {
    await serverWith(threeTurns(), declare: false);

    final response = await load(h.client);

    expect(response.error, isNull);
    expect(usageOf(h.client), isEmpty);
    final methods = {
      for (final frame in h.client.received)
        if (frame is JsonRpcNotification) frame.method,
    };
    expect(methods, {'session/update'});
    expect(h.logger.eventsOf('acp.usage.sent'), isEmpty);
  });

  test('a load of an unknown session is an error and no snapshot', () async {
    await serverWith(threeTurns());

    final response = await load(h.client, id: 'no-such-session');

    expect(response.error, isNotNull);
    expect(usageOf(h.client), isEmpty);
  });

  // «Суммаризатор в сумме сессии» (D4, Q6 (а); фикстура
  // `acp/compact-usage-summary`): usage суммаризатора входит в `session`
  // снимка `compaction` сверх итогов ходов; `turns` и `steps` не меняются, а
  // `turn` следующего хода его не содержит.
  group('/compact in a live session (D4)', () {
    late String id;

    setUp(() async {
      final longReply = 'Ответ подробно. ' * 150;
      h = await ServerHarness.start(
        defaultModel: pricedModel,
        compaction: const CompactionOverrides(keepRecentTokens: 512),
        steps: [
          textStep(longReply, const {'input': 100, 'output': 20}),
          textStep(longReply, const {'input': 20000, 'output': 20}),
          // Ответ суммаризатора с usage: 900 + 120.
          textStep('Пользователь задал два вопроса.', const {
            'input': 900,
            'output': 120,
          }),
          textStep('Готово.', const {'input': 50, 'output': 10}),
        ],
      );
      await h.initialize(clientCapabilities: usageClient);
      id = await h.newSession();
      await h.prompt(id, 'Первый вопрос');
      await h.prompt(id, 'Второй вопрос');
    });

    test('the compaction snapshot carries the summarizer in session, not in '
        'turns or steps', () async {
      final response = await h.prompt(id, '/compact обработка ошибок');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      final compaction = usageOf(h.client).last;
      expect(compaction['trigger'], 'compaction');
      final session = asMap(compaction['session']);
      expect(session['turns'], 2);
      expect(session['steps'], 2);
      expect(session['tokens'], tokens(21000, 160));
      expect(session['cost'], '0.0654');
      expect(session, isNot(contains('partial')));
    });

    test('the next turn: turn has its own steps only, session keeps the '
        'summarizer', () async {
      await h.prompt(id, '/compact обработка ошибок');

      await h.prompt(id, 'Третий вопрос');

      final turn = usageOf(h.client).last;
      expect(turn['trigger'], 'turn');
      expect(asMap(turn['turn'])['tokens'], tokens(50, 10));
      expect(asMap(turn['turn'])['cost'], '0.0003');
      final session = asMap(turn['session']);
      expect(session['turns'], 3);
      expect(session['steps'], 3);
      expect(session['tokens'], tokens(21050, 170));
    });

    test('the ledger shows the summary as its own group and its total equals '
        'the session of the last snapshot', () async {
      await h.prompt(id, '/compact обработка ошибок');

      final result = (await h.client.request('_codelab/session/usage/ledger', {
        'sessionId': id,
      })).resultMap;

      expect(asMap(result['summaries'])['count'], 1);
      expect(asMap(result['summaries'])['tokens'], tokens(900, 120));
      expect(asMap(result['summaries'])['cost'], '0.0045');
      expect(result['total'], usageOf(h.client).last['session']);
      // Ходы суммаризатора не содержат (D4 п. 3): сумма ходов меньше итога.
      final turns = (result['turns']! as List).cast<Map<String, Object?>>();
      final inTurns = turns.fold<int>(
        0,
        (sum, t) => sum + (asMap(asMap(t['total'])['tokens'])['input']! as int),
      );
      expect(inTurns, 20100);
    });
  });

  // «Отброшенный проход сжатия» в живой сессии (change
  // `fix-discarded-compaction-usage`, D5, D7; фикстура
  // `acp/compact-no-gain-usage`): резюме суммаризатора длиннее региона,
  // проход отбрасывается по CMP-10, а оплаченный вызов входит в сумму сессии.
  group('/compact without a gain in a live session (D5)', () {
    late String id;

    setUp(() async {
      h = await ServerHarness.start(
        defaultModel: pricedModel,
        compaction: const CompactionOverrides(keepRecentTokens: 512),
        steps: [
          textStep('Первый ответ подробно. ' * 100, const {
            'input': 100,
            'output': 20,
          }),
          // Резюме длиннее региона и с usage: 900 + 120.
          textStep('Пользователь задал вопрос. ' * 3, const {
            'input': 900,
            'output': 120,
          }),
        ],
      );
      await h.initialize(clientCapabilities: usageClient);
      id = await h.newSession();
      await h.prompt(id, 'Первый вопрос');
    });

    test('the answer is Nothing to compact, then the snapshot, then end_turn '
        'with the summarizer in session and turns/steps unchanged', () async {
      final before = usageOf(h.client).last;

      final response = await h.prompt(id, '/compact');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      final frame = usageOf(h.client).last;
      expect(frame['trigger'], 'compactionDiscarded');
      expect(frame['seq'], 3);
      expect(
        frame.keys.toSet().intersection({'turnId', 'step', 'turn'}),
        isEmpty,
      );
      final session = asMap(frame['session']);
      expect(session['turns'], 1);
      expect(session['steps'], 1);
      expect(session['tokens'], tokens(1000, 140));
      expect(session['cost'], '0.0051');
      expect(session, isNot(contains('partial')));
      expect(asMap(frame['context'])['used'], asMap(before['context'])['used']);
      final text = [
        for (final f in h.client.received)
          if (f is JsonRpcNotification && f.method == 'session/update')
            jsonEncode(f.params),
      ];
      expect(text.last, contains('Nothing to compact.'));
      expect(
        positionOfUsage(h.client, 3),
        lessThan(h.client.received.indexOf(response)),
      );
    });

    test('the ledger: summaries.count 1 and discarded 1, total equals the '
        'session of the last snapshot', () async {
      await h.prompt(id, '/compact');

      final result = (await h.client.request('_codelab/session/usage/ledger', {
        'sessionId': id,
      })).resultMap;

      final summaries = asMap(result['summaries']);
      expect(summaries['count'], 1);
      expect(summaries['discarded'], 1);
      expect(summaries['tokens'], tokens(900, 120));
      expect(summaries['cost'], '0.0045');
      expect(result['total'], usageOf(h.client).last['session']);
      expect((result['ledger']! as Map)['status'], isNotNull);
    });
  });

  // Гонки отмены после проверки выигрыша (Q9 (а), CMP-13): проход уже признан
  // отброшенным, вызов оплачен, и ни `session/cancel`, ни закрытие сессии
  // запись учёта не отменяют. `stale` через мост недостижим: сообщение или
  // иная запись во время резюме возможна только из хода или команды той же
  // сессии, а они идут по очереди, `/compact` их не пропускает; поэтому этот
  // исход покрывают тесты ядра (`compactor_test.dart`), а мост различает
  // исходы не по `reason`, а по событию, которое одно и то же.
  group('a race after the gain check (Q9)', () {
    late JournalStore store;
    late String id;

    setUp(() async {
      store = JournalStore()..holdWhen = (r) => r is CustomRecord;
      h = await ServerHarness.start(
        sessions: store,
        defaultModel: pricedModel,
        compaction: const CompactionOverrides(keepRecentTokens: 512),
        steps: [
          textStep('Первый ответ подробно. ' * 100, const {
            'input': 100,
            'output': 20,
          }),
          textStep('Пользователь задал вопрос. ' * 3, const {
            'input': 900,
            'output': 120,
          }),
        ],
      );
      await h.initialize(clientCapabilities: usageClient);
      id = await h.newSession();
      await h.prompt(id, 'Первый вопрос');
    });

    test(
      'session/cancel while the accounting record waits: the snapshot is '
      'sent, the sum has the call, Nothing to compact., ACP-5 cancelled',
      () async {
        final answer = h.client.request('session/prompt', {
          'sessionId': id,
          'prompt': [
            {'type': 'text', 'text': '/compact'},
          ],
        });
        await store.heldReached;
        await h.client.notify('session/cancel', {'sessionId': id});
        await pumpEventQueue();
        store.releaseHeld();
        final response = await answer;

        // Ядро завершает команду как `completed`, но ACP-5 требует от моста
        // ответ `cancelled` на ход, для которого пришёл `session/cancel`
        // (05-Prompt Turn.md, Cancellation); учёт вызова от этого не зависит.
        expect(response.resultMap, {'stopReason': 'cancelled'});
        final frame = usageOf(h.client).last;
        expect(frame['trigger'], 'compactionDiscarded');
        final session = asMap(frame['session']);
        expect(session['tokens'], tokens(1000, 140));
        expect(session['cost'], '0.0051');
        expect(
          [
            for (final f in h.client.received)
              if (f is JsonRpcNotification && f.method == 'session/update')
                jsonEncode(f.params),
          ].last,
          contains('Nothing to compact.'),
        );
        final ledger = (await h.client.request(
          '_codelab/session/usage/ledger',
          {'sessionId': id},
        )).resultMap;
        expect(asMap(ledger['summaries'])['discarded'], 1);
        expect(ledger['total'], session);
      },
    );

    test('close() of the server while the record waits: the record is on '
        'disk, after session/load the sum has the call', () async {
      // `shutdown` отменяет ход и ждёт запись до закрытия писателя.
      unawaited(
        h.client.request('session/prompt', {
          'sessionId': id,
          'prompt': [
            {'type': 'text', 'text': '/compact'},
          ],
        }),
      );
      await store.heldReached;
      final closing = h.server.shutdown(grace: Duration.zero);
      await pumpEventQueue();
      store.releaseHeld();
      await closing;

      store.holdWhen = null;
      h = await ServerHarness.start(sessions: store, defaultModel: pricedModel);
      await h.initialize(clientCapabilities: usageClient);
      final loaded = await load(h.client, id: id);
      expect(loaded.error, isNull);

      final session = asMap(usageOf(h.client).single['session']);
      expect(session['tokens'], tokens(1000, 140));
      final ledger = await ledgerOf(h.client, id);
      expect(ledger['total'], session);
      expect(asMap(ledger['summaries'])['discarded'], 1);
    });
  });

  // «Сумма после session/load» и ответ журнала с отброшенным проходом
  // (D3, D5): запись учёта `codelab.compaction_discarded` входит в `summaries`
  // и в засев; `discarded` — только при ненулевом значении.
  group('the seed of a journal with a discarded pass (D5)', () {
    UsageJournal journalWithDiscarded() => UsageJournal(sessionId)
      ..user('Первый вопрос')
      ..assistant('Первый ответ.', pricedUsage(100, 20))
      ..discarded(pricedUsage(900, 120));

    test('the load snapshot includes the discarded call and equals total of '
        'the ledger; summaries.discarded is 1', () async {
      await serverWith(journalWithDiscarded());
      await load(h.client);

      final frame = usageOf(h.client).single;
      expect(frame['trigger'], 'load');
      final session = asMap(frame['session']);
      expect(session['turns'], 1);
      expect(session['steps'], 1);
      expect(session['tokens'], tokens(1000, 140));
      expect(session['cost'], '0.0051');

      final result = await ledgerOf(h.client);
      expect(result['total'], session);
      final summaries = asMap(result['summaries']);
      expect(summaries['count'], 1);
      expect(summaries['discarded'], 1);
    });

    test('a journal with a written pass only: no discarded key', () async {
      final journal = UsageJournal(sessionId)
        ..user('Первый вопрос')
        ..assistant('Первый ответ.', pricedUsage(100, 20));
      final first = journal.lastId;
      journal.compaction(first, pricedUsage(900, 120));
      await serverWith(journal);
      await load(h.client);

      final summaries = asMap((await ledgerOf(h.client))['summaries']);

      expect(summaries['count'], 1);
      expect(summaries, isNot(contains('discarded')));
    });

    test('a written and a discarded pass: count 2, discarded 1', () async {
      final journal = UsageJournal(sessionId)
        ..user('Первый вопрос')
        ..assistant('Первый ответ.', pricedUsage(100, 20));
      final first = journal.lastId;
      journal
        ..compaction(first, pricedUsage(900, 120))
        ..discarded(pricedUsage(500, 60));
      await serverWith(journal);
      await load(h.client);

      final result = await ledgerOf(h.client);

      final summaries = asMap(result['summaries']);
      expect(summaries['count'], 2);
      expect(summaries['discarded'], 1);
      expect(summaries['tokens'], tokens(1400, 180));
      expect(result['total'], usageOf(h.client).single['session']);
    });
  });

  // Правила `seq` сквозные для сессии сервера: загрузка не сбрасывает счёт
  // снимков уже открытой сессии (D8, «Сессия перешла к новому соединению»).
  test('a load of an already open session keeps the seq counter of the '
      'server session', () async {
    await serverWith(
      threeTurns(),
      steps: [
        textStep('Ответ.', const {'input': 10, 'output': 5}),
      ],
    );
    await load(h.client);
    await h.prompt(sessionId.value, 'Ещё');
    expect(usageOf(h.client).map((f) => f['seq']), [1, 2, 3]);

    final other = await connectDeclaring();
    await load(other);

    expect(usageOf(other).map((f) => f['seq']), [4]);
    expect(usageOf(other).single['trigger'], 'load');
    expect(asMap(usageOf(other).single['session'])['turns'], 4);
  });

  // Сбой засева (design.md change `add-usage-ledger`, D8, D15): загрузка не
  // падает и сессия регистрируется, сумма честно помечена как неполная
  // (`beforeLoad`, откат по Migration Plan), в лог уходит только класс
  // исключения.
  test('a seed failure does not fail the load: warning seed_failed with '
      'error_class, the session works, the sum is beforeLoad', () async {
    final store = JournalStore();
    await threeTurns().seedInto(store);
    final catalog = _BreakableCatalog(pricedModel);
    h = await ServerHarness.start(
      sessions: store,
      defaultModel: pricedModel,
      models: catalog,
      steps: [
        textStep('Вот ответ.', const {'input': 100, 'output': 50}),
      ],
    );
    await h.initialize(clientCapabilities: usageClient);
    catalog.broken = true;

    final response = await load(h.client);
    catalog.broken = false;

    expect(response.error, isNull);
    final warnings = h.logger.eventsOf('acp.usage.seed_failed');
    expect(warnings, hasLength(1));
    expect(warnings.single.level, LogLevel.warning);
    expect(warnings.single.fields, {
      'session_id': sessionId.value,
      'error_class': 'StateError',
    });
    expect(h.logger.eventsOf('acp.usage.seeded'), isEmpty);
    // Нет засева — нет снимка `load`, а сессия зарегистрирована и ходит.
    expect(usageOf(h.client), isEmpty);
    final turn = await h.prompt(sessionId.value, 'Ещё раз');
    expect(turn.resultMap, {'stopReason': 'end_turn'});
    final session = asMap(usageOf(h.client).last['session']);
    expect(session['partial'], contains('beforeLoad'));
    expect(session['turns'], 1);
  });

  // `after:` ответа `session/load` (D8): сбой снимка `load` не отнимает
  // возобновление идущего хода у нового владельца.
  test('a failure of the load snapshot does not skip the resume of a moved '
      'turn', () async {
    h = await ServerHarness.start(
      defaultModel: pricedModel,
      wrapLogger: (inner) => _FailingLogger(
        inner,
        (event, fields) =>
            event == 'acp.usage.sent' && fields['trigger'] == 'load',
      ),
      steps: [
        textStep('Здравствуйте.', const {'input': 10, 'output': 5}),
        {
          'reply': [
            {
              'toolCall': {
                'id': 'call_5',
                'name': 'write',
                'arguments': {'path': 'a.txt', 'content': 'a'},
              },
            },
          ],
          'usage': const {'input': 1200, 'output': 300},
        },
        textStep('Written.', const {'input': 1500, 'output': 400}),
      ],
    );
    await h.initialize(clientCapabilities: usageClient);
    h.client.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));
    final id = await h.newSession();
    // Первый ход закончен: в сумме сессии есть шаг, и снимок `load` нужен.
    await h.prompt(id, 'Привет');
    final turn = h.prompt(id, 'Write a.txt');
    turn.ignore();
    while (true) {
      final frame = await h.client.next();
      if (frame is JsonRpcRequest &&
          frame.method == 'session/request_permission') {
        break;
      }
    }
    await h.client.transport.close();
    await pumpEventQueue();

    final other = await connectDeclaring();
    other.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));
    await load(other, id: id);
    JsonRpcRequest? again;
    while (again == null) {
      final frame = await other.next();
      if (frame is JsonRpcRequest &&
          frame.method == 'session/request_permission') {
        again = frame;
      }
    }

    // Запрос разрешения пришёл заново: `resume` выполнен, хотя снимок упал.
    expect(again, isNotNull);
    expect(h.logger.eventsOf('acp.usage.sent').last.fields['trigger'], 'load');
    final failed = h.logger.eventsOf('acp.usage.load_snapshot_failed');
    expect(failed, hasLength(1));
    expect(failed.single.fields['error_class'], 'StateError');
  });
}

/// Каталог, который можно сломать после создания сессии: `resolve` бросает
/// [StateError] — сбой свёртки засева вне контракта порта.
final class _BreakableCatalog implements ModelCatalog {
  _BreakableCatalog(ModelRef model) : _inner = FixedModelCatalog([model]);

  final FixedModelCatalog _inner;
  var broken = false;

  @override
  List<ModelEntry> get models => _inner.models;

  @override
  ModelRef? resolve(ModelId id, {ReasoningEffort? effort}) {
    // Ломается только вызов свёртки засева (`modelsWithoutPrice`): создание
    // и загрузка сессии каталогом пользуются сами и должны пройти.
    if (broken &&
        StackTrace.current.toString().contains('modelsWithoutPrice')) {
      throw StateError('catalog is broken');
    }
    return _inner.resolve(id, effort: effort);
  }

  @override
  Stream<void> get changes => _inner.changes;

  @override
  Future<void> refresh({bool force = false}) => _inner.refresh(force: force);
}

/// Логгер, который после записи события бросает исключение: имитирует сбой
/// внутри `after:` ответа.
final class _FailingLogger implements Logger {
  _FailingLogger(this.inner, this.failOn);

  final RecordingLogger inner;
  final bool Function(String event, Map<String, Object?> fields) failOn;

  @override
  bool isEnabled(LogLevel level) => inner.isEnabled(level);

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    inner.log(level, event, fields: fields, error: error, stack: stack);
    if (failOn(event, fields)) {
      throw StateError('logger failure');
    }
  }
}
