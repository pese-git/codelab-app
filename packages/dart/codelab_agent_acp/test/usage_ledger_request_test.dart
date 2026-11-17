import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';
import 'support/usage_journal.dart';

/// Запрос `_codelab/session/usage/ledger` (agent-acp-server «Запрос
/// `_codelab/session/usage/ledger`»; design.md change `add-usage-ledger`,
/// D6, D7, D12, Q1, Q2, Q8; задача 2.2).
///
/// Почему отдельный файл: запрос — первый вызов клиент → агент в
/// пространстве `_codelab/*`, а проверяет он форму результата, ошибки,
/// поведение во время хода и журнал. Файл красный до задачи 2.6: обработчик
/// `_onRequest` знает только `session/*` и `initialize` и отвечает `-32601`.
///
/// Как читать: числа и цены те же, что в `usage_projection_test.dart` и
/// фикстуре `acp/prompt-usage-steps` (3 / 15 / 0.3 / 3.75 доллара за 10^6
/// токенов), поэтому стоимость шагов — `0.0111` и `0.0171`.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  /// Маркер: слова пользователя попадают в `title` ответа, но не в лог.
  const secretWords = 'sk-test-leak-0123456789';

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

  const step0 = {'input': 1200, 'output': 300, 'cacheRead': 10000};
  const step1 = {
    'input': 1500,
    'output': 400,
    'cacheRead': 12000,
    'cacheWrite': 800,
  };

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

  Map<String, Object?> taskStep(Map<String, Object?>? usage) => {
    'reply': [
      {
        'toolCall': {
          'id': 'call_1',
          'name': 'task_create',
          'arguments': {'subject': 'Прочитать тесты', 'priority': 'high'},
        },
      },
    ],
    'usage': ?usage,
  };

  Map<String, Object?> textStep(String text, Map<String, Object?>? usage) => {
    'reply': [
      {'text': text},
    ],
    'usage': ?usage,
  };

  Map<String, Object?> asMap(Object? value) =>
      (value! as Map).cast<String, Object?>();

  List<Map<String, Object?>> usageOf(TestClient client) => [
    for (final frame in client.received)
      if (frame case JsonRpcNotification(
        method: '_codelab/session/usage',
        :final params,
      ))
        asMap(params),
  ];

  /// Сервер с клиентом, объявившим `usage`, и сессией; ход «два шага с
  /// ценами» (вызов `task_create` с `call_1`, затем текст) уже выполнен, если
  /// [prompted].
  Future<String> ready({
    List<Map<String, Object?>>? steps,
    ModelRef? model,
    UsageLedgerStore? port,
    bool prompted = true,
    String prompt = 'Составь список задач для исправления теста',
  }) async {
    h = await ServerHarness.start(
      defaultModel: model ?? pricedModel,
      usageLedger: port,
      steps: steps ?? [taskStep(step0), textStep('Список готов.', step1)],
    );
    await h.initialize(clientCapabilities: usageClient);
    final sessionId = await h.newSession();
    if (prompted) {
      await h.prompt(sessionId, prompt);
    }
    return sessionId;
  }

  Future<JsonRpcResponse> ledger(
    String sessionId, {
    Object? rebuild,
    Map<String, Object?> extra = const {},
  }) => h.client.request('_codelab/session/usage/ledger', {
    'sessionId': sessionId,
    'rebuild': ?rebuild,
    ...extra,
  });

  group('the result after a turn with two priced steps (D6)', () {
    late String sessionId;
    late Map<String, Object?> result;

    setUp(() async {
      sessionId = await ready();
      final response = await ledger(sessionId);
      expect(response.error, isNull);
      result = response.resultMap;
    });

    test('top-level fields: sessionId, seq of the last snapshot, currency', () {
      final lastSeq = usageOf(h.client).last['seq'];
      expect(lastSeq, 3);
      expect(result['sessionId'], sessionId);
      expect(result['seq'], lastSeq);
      expect(result['currency'], 'USD');
      // Без порта файла нет: отчёт строится в памяти (D3).
      expect(asMap(result['ledger'])['status'], 'inMemory');
      expect(asMap(result['ledger'])['records'], isA<int>());
      expect(asMap(result['ledger']), isNot(contains('reason')));
    });

    test('total equals the session of the last snapshot (D8 invariant)', () {
      final session = asMap(usageOf(h.client).last['session']);
      expect(result['total'], session);
      expect(result['total'], {
        'turns': 1,
        'steps': 2,
        'tokens': tokens(2700, 700, 22000, 800),
        'cost': '0.0282',
      });
    });

    test(
      'one turn with the title, the total and two steps with toolCallIds',
      () {
        final turns = (result['turns']! as List).cast<Map<String, Object?>>();
        expect(turns, hasLength(1));
        final turn = turns.single;
        expect(turn['index'], 1);
        expect(turn['title'], 'Составь список задач для исправления теста');
        expect(turn['total'], {
          'steps': 2,
          'tokens': tokens(2700, 700, 22000, 800),
          'cost': '0.0282',
        });
        expect(turn, isNot(contains('running')));
        expect(turn, isNot(contains('subagents')));
        final steps = (turn['steps']! as List).cast<Map<String, Object?>>();
        expect(steps, hasLength(2));
        expect(steps[0], containsPair('index', 0));
        expect(steps[0], containsPair('model', 'scripted/scripted-1'));
        expect(steps[0], containsPair('tokens', tokens(1200, 300, 10000, 0)));
        expect(steps[0], containsPair('cost', '0.0111'));
        expect(steps[0], containsPair('toolCallIds', ['call_1']));
        expect(steps[1], containsPair('index', 1));
        expect(steps[1], containsPair('tokens', tokens(1500, 400, 12000, 800)));
        expect(steps[1], containsPair('cost', '0.0171'));
        // `toolCallIds` есть у каждого шага; у шага без вызовов это `[]`, а не
        // отсутствующее поле (D6).
        expect(steps[1], containsPair('toolCallIds', <Object?>[]));
      },
    );

    test('one model line with the steps of that model, no subagents or '
        'summaries', () {
      expect(result['models'], [
        {
          'model': 'scripted/scripted-1',
          'steps': 2,
          'tokens': tokens(2700, 700, 22000, 800),
          'cost': '0.0282',
        },
      ]);
      expect(result, isNot(contains('subagents')));
      expect(result, isNot(contains('summaries')));
    });

    test(
      'the second request returns the same totals (determinism, OBS-10)',
      () async {
        final again = (await ledger(sessionId)).resultMap;

        expect(again['total'], result['total']);
        expect(again['turns'], result['turns']);
        expect(again['models'], result['models']);
        expect(again['seq'], result['seq']);
      },
    );
  });

  group('the state of the file (D3, D6)', () {
    test('first request writes the file: rebuilt / missing; second: upToDate; '
        'rebuild: rebuilt / explicit', () async {
      final port = MemoryUsageLedgerStore();
      final sessionId = await ready(port: port);

      final first = asMap((await ledger(sessionId)).resultMap['ledger']);
      expect(first['status'], 'rebuilt');
      expect(first['reason'], 'missing');
      expect(port.files, contains(sessionId));

      final second = asMap((await ledger(sessionId)).resultMap['ledger']);
      expect(second['status'], 'upToDate');
      expect(second, isNot(contains('reason')));
      expect(second['records'], first['records']);

      final forced = (await ledger(sessionId, rebuild: true)).resultMap;
      expect(asMap(forced['ledger'])['status'], 'rebuilt');
      expect(asMap(forced['ledger'])['reason'], 'explicit');
      // Итоги те же, что без `rebuild`.
      expect(forced['total'], isNotNull);
    });

    test(
      'rebuild: false is the default; a new turn makes the file stale',
      () async {
        final port = MemoryUsageLedgerStore();
        final sessionId = await ready(
          port: port,
          steps: [
            taskStep(step0),
            textStep('Список готов.', step1),
            textStep('Ещё ответ.', const {'input': 100, 'output': 50}),
          ],
        );
        await ledger(sessionId, rebuild: false);
        await h.prompt(sessionId, 'Ещё');

        final next = (await ledger(sessionId)).resultMap;

        expect(asMap(next['ledger'])['status'], 'rebuilt');
        expect(asMap(next['ledger'])['reason'], 'stale');
        expect(asMap(next['total'])['turns'], 2);
        expect(asMap(next['total'])['steps'], 3);
      },
    );

    test('a broken file is rebuilt with the reason invalid', () async {
      final port = MemoryUsageLedgerStore();
      final sessionId = await ready(port: port);
      port.files[sessionId] = '{not json';

      final result = (await ledger(sessionId)).resultMap;

      expect(asMap(result['ledger'])['status'], 'rebuilt');
      expect(asMap(result['ledger'])['reason'], 'invalid');
    });

    test('a write failure is not a request error: notSaved and a warning '
        '(Сбой записи файла)', () async {
      final port = MemoryUsageLedgerStore()..failWrite = 'Permission denied';
      final sessionId = await ready(port: port);

      final response = await ledger(sessionId);

      expect(response.error, isNull);
      expect(asMap(response.resultMap['ledger'])['status'], 'notSaved');
      // Итоги отдаются несмотря на сбой записи.
      expect(asMap(response.resultMap['total'])['steps'], 2);
      final warnings = h.logger.eventsOf('usage.ledger.write_failed');
      expect(warnings, hasLength(1));
      expect(warnings.single.level, LogLevel.warning);
      expect(warnings.single.fields['session_id'], sessionId);
    });
  });

  group('params and errors (D6)', () {
    test(
      'an unknown sessionId is -32002 and the port is not touched',
      () async {
        final port = MemoryUsageLedgerStore();
        await ready(port: port, prompted: false);

        final response = await ledger('no-such-session');

        expect(response.errorCode, -32002);
        expect(port.reads, 0);
        expect(port.writes, 0);
      },
    );

    test('a non-boolean rebuild is -32602', () async {
      final sessionId = await ready(prompted: false);

      final response = await ledger(sessionId, rebuild: 'yes');

      expect(response.errorCode, -32602);
    });

    test('a non-string sessionId is -32602', () async {
      await ready(prompted: false);

      final response = await h.client.request('_codelab/session/usage/ledger', {
        'sessionId': 42,
      });

      expect(response.errorCode, -32602);
    });

    test('an unknown param is ignored (forward compatibility)', () async {
      final sessionId = await ready();

      final response = await ledger(sessionId, extra: {'future': true});

      expect(response.error, isNull);
      expect(response.resultMap['sessionId'], sessionId);
    });

    test('an exception outside the port contract is -32603 with '
        'data.codelab.reason usageLedgerFailed and a warning', () async {
      final port = MemoryUsageLedgerStore()
        ..failRead = StateError('broken journal');
      final sessionId = await ready(port: port);

      final response = await ledger(sessionId);

      expect(response.errorCode, -32603);
      final data = asMap(response.error!.data);
      expect(asMap(data['codelab'])['reason'], 'usageLedgerFailed');
      expect(
        h.logger.records.where((r) => r.level == LogLevel.warning),
        isNotEmpty,
      );
      // Соединение живо: следующий запрос обслуживается.
      port.failRead = null;
      expect((await ledger(sessionId)).error, isNull);
    });
  });

  group('during a turn (Запрос во время хода)', () {
    /// Ход приостановлен на запросе разрешения записи файла: шаг с `write`
    /// уже записан в журнал, ход идёт.
    Future<
      ({
        String sessionId,
        JsonRpcRequest permission,
        Future<JsonRpcResponse> turn,
      })
    >
    pausedTurn() async {
      h = await ServerHarness.start(
        defaultModel: pricedModel,
        steps: [
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
            'usage': step0,
          },
          textStep('Written.', step1),
        ],
      );
      await h.initialize(clientCapabilities: usageClient);
      h.client.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));
      final sessionId = await h.newSession();
      final turn = h.prompt(sessionId, 'Write a.txt');
      while (true) {
        final frame = await h.client.next();
        if (frame is JsonRpcRequest &&
            frame.method == 'session/request_permission') {
          return (sessionId: sessionId, permission: frame, turn: turn);
        }
      }
    }

    test('the answer comes at once, the last turn is running and the turn '
        'goes on unchanged', () async {
      final paused = await pausedTurn();

      final response = await ledger(paused.sessionId);

      expect(response.error, isNull);
      final turns = (response.resultMap['turns']! as List)
          .cast<Map<String, Object?>>();
      expect(turns.single['running'], isTrue);
      expect(turns.single['title'], 'Write a.txt');
      expect(asMap(turns.single['total'])['steps'], 1);
      expect(asMap(response.resultMap['total'])['steps'], 1);
      // `seq` — последний снимок, потраченный к моменту построения.
      await pumpEventQueue();
      expect(
        response.resultMap['seq'],
        usageOf(
          h.client,
        ).map((f) => f['seq']! as int).fold<int>(0, (a, b) => a > b ? a : b),
      );

      await h.client.respond(paused.permission, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      });
      final end = await paused.turn;
      expect(end.resultMap, {'stopReason': 'end_turn'});

      final after = (await ledger(paused.sessionId)).resultMap;
      final afterTurns = (after['turns']! as List).cast<Map<String, Object?>>();
      expect(afterTurns.single, isNot(contains('running')));
      expect(asMap(after['total'])['steps'], 2);
    });

    test('session/cancel does not cancel the request', () async {
      final paused = await pausedTurn();

      final pending = ledger(paused.sessionId);
      unawaited(
        h.client.notify('session/cancel', {'sessionId': paused.sessionId}),
      );
      final response = await pending;

      expect(response.error, isNull);
      expect(response.resultMap['sessionId'], paused.sessionId);
      final end = await paused.turn;
      expect(end.resultMap['stopReason'], 'cancelled');
    });
  });

  group('prices and reasons (Модель без цен в истории)', () {
    test('a model without prices: no cost, noPrice at step, turn, model and '
        'total, no currency', () async {
      h = await ServerHarness.start(
        steps: [
          textStep('Ответ.', const {'input': 100, 'output': 50}),
        ],
      );
      await h.initialize(clientCapabilities: usageClient);
      final sessionId = await h.newSession();
      await h.prompt(sessionId, 'Привет');

      final result = (await ledger(sessionId)).resultMap;

      final turn = asMap((result['turns']! as List).single);
      final step = asMap((turn['steps']! as List).single);
      expect(step, isNot(contains('cost')));
      expect(step['partial'], ['noPrice']);
      expect(asMap(turn['total']), isNot(contains('cost')));
      expect(asMap(turn['total'])['partial'], ['noPrice']);
      final model = asMap((result['models']! as List).single);
      expect(model, isNot(contains('cost')));
      expect(model['partial'], ['noPrice']);
      expect(asMap(result['total']), isNot(contains('cost')));
      expect(asMap(result['total'])['partial'], ['noPrice']);
      expect(result, isNot(contains('currency')));
      // Ноль за цену не выдаётся.
      expect(jsonEncode(result), isNot(contains('"cost":"0"')));
    });

    test(
      'a step without usage from the provider is noUsage, not zero money',
      () async {
        final sessionId = await ready(
          steps: [textStep('Ответ.', null)],
          prompt: 'Привет',
        );

        final result = (await ledger(sessionId)).resultMap;

        final step = asMap(
          (asMap((result['turns']! as List).single)['steps']! as List).single,
        );
        expect(step['partial'], ['noUsage']);
        expect(asMap(result['total'])['partial'], ['noUsage']);
      },
    );
  });

  group('log and privacy (D12, §16)', () {
    test('debug acp.usage.ledger has the fixed fields and no tokens, money '
        'or titles', () async {
      final port = MemoryUsageLedgerStore();
      final sessionId = await ready(
        port: port,
        prompt: 'Ключ $secretWords',
        steps: [taskStep(step0), textStep('Ответ с $secretWords', step1)],
      );

      final response = await ledger(sessionId, rebuild: true);

      final records = h.logger.eventsOf('acp.usage.ledger');
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.level, LogLevel.debug);
      expect(record.fields.keys.toSet(), {
        'session_id',
        'rebuild',
        'status',
        'turns',
        'steps',
        'duration_ms',
      });
      expect(record.fields['session_id'], sessionId);
      expect(record.fields['rebuild'], isTrue);
      expect(record.fields['status'], 'rebuilt');
      expect(record.fields['turns'], 1);
      expect(record.fields['steps'], 2);
      final logged = jsonEncode([for (final r in h.logger.records) r.fields]);
      expect(logged, isNot(contains(secretWords)));
      expect(logged, isNot(contains('0.0282')));
      expect(logged, isNot(contains('2700')));
      // Подпись хода — слова пользователя — есть в ответе, но не в логе.
      expect(
        asMap((response.resultMap['turns']! as List).single)['title'],
        contains(secretWords),
      );
      // Ответ не несёт текстов ответа модели.
      expect(jsonEncode(response.resultMap), isNot(contains('Ответ с')));
    });

    test('the title is at most 64 runes', () async {
      final sessionId = await ready(prompt: 'я' * 100);

      final result = (await ledger(sessionId)).resultMap;

      final title =
          asMap((result['turns']! as List).single)['title']! as String;
      expect(title.runes.length, 64);
    });
  });

  // «Стандартные типы без новых полей (usageLedger)» (ACP-2, 15-Extensibility):
  // журнал приходит только в результате запроса.
  test('no standard ACP frame gets new fields: the ledger lives only in the '
      'result of the request', () async {
    final sessionId = await ready();
    final before = h.client.received.length;

    final response = await ledger(sessionId);

    expect(response.resultMap, contains('ledger'));
    final frames = h.client.received.take(before);
    for (final frame in frames) {
      final text = jsonEncode(frame);
      expect(text, isNot(contains('"ledger"')), reason: text);
    }
    // Запрос не порождает уведомлений: ни `session/update`, ни снимков usage.
    expect(
      h.client.received.skip(before).whereType<JsonRpcNotification>(),
      isEmpty,
    );
  });
}
