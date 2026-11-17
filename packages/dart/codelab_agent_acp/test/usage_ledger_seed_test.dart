import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcResponse;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
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

  Future<JsonRpcResponse> load(TestClient client, {String? id}) =>
      client.request('session/load', {
        'sessionId': id ?? sessionId.value,
        'cwd': '/work/demo',
        'mcpServers': <Object?>[],
      });

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
}
