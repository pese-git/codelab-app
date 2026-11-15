import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Проекция usage в уведомление `_codelab/session/usage` (agent-acp-server
/// «Уведомление `_codelab/session/usage`», «initialize»; design.md change
/// `add-usage-extension`, D1, D2, D4–D7, D9, D14, D18 Т5, Т7; задача 1.3).
///
/// Почему отдельный файл: сценарии идут через настоящее ядро со scripted
/// моделью и `InProcessAcpLink` и проверяют порядок кадров, `seq`, агрегаты и
/// переход сессии между соединениями. Файл красный до задачи 1.8:
/// уведомления `_codelab/session/usage` адаптер ещё не отправляет.
///
/// Как читать: числа выбраны так, чтобы стоимость была целой в микродолларах
/// (цены 3 / 15 / 0.3 / 3.75 доллара за 10^6 токенов) и совпадала с
/// фикстурой `acp/prompt-usage-steps`.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  /// Маркер утечки: ни в уведомлении, ни в debug-записи его быть не должно
  /// (уведомление не несёт текстов сообщений и аргументов инструментов).
  const leak = 'sk-test-leak-0123456789';

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

  const step0 = {'input': 1200, 'output': 300, 'cacheRead': 10000};
  const step1 = {
    'input': 1500,
    'output': 400,
    'cacheRead': 12000,
    'cacheWrite': 800,
  };

  /// Агент и клиент, объявивший `usage` (если [declare]); сессия создана.
  Future<String> ready({
    List<Map<String, Object?>> steps = const [],
    ModelRef? model,
    Map<HostCapability, CapabilityState> narrow = const {},
    CompactionOverrides compaction = const CompactionOverrides(),
    bool declare = true,
  }) async {
    h = await ServerHarness.start(
      steps: steps,
      defaultModel: model,
      narrow: narrow,
      compaction: compaction,
    );
    await h.initialize(clientCapabilities: declare ? usageClient : null);
    return h.newSession();
  }

  /// Параметры всех `_codelab/session/usage`, пришедших клиенту, по порядку.
  List<Map<String, Object?>> usageOf(TestClient client) => [
    for (final frame in client.received)
      if (frame case JsonRpcNotification(
        method: '_codelab/session/usage',
        :final params,
      ))
        (params! as Map).cast<String, Object?>(),
  ];

  /// Позиция кадра `_codelab/session/usage` с [seq] среди всех кадров.
  int positionOfUsage(TestClient client, int seq) => client.received.indexWhere(
    (f) =>
        f is JsonRpcNotification &&
        f.method == '_codelab/session/usage' &&
        (f.params! as Map)['seq'] == seq,
  );

  Map<String, Object?> asMap(Object? value) =>
      (value! as Map).cast<String, Object?>();

  // «Два шага с ценами» (фикстура `acp/prompt-usage-steps`): `seq` 1…3,
  // суммы, `cost` — десятичная строка из микроединиц (D2, D4, D9). Здесь
  // же — порядок «снимок turn после содержательных `session/update` и до
  // ответа» (ACP-3, D7) и форма без новых корневых полей.
  group('two priced steps', () {
    late String sessionId;
    late JsonRpcResponse response;
    late List<Map<String, Object?>> frames;

    setUp(() async {
      sessionId = await ready(
        model: pricedModel,
        steps: [taskStep(step0), textStep('Список готов.', step1)],
      );
      response = await h.prompt(sessionId, 'Составь список задач');
      frames = usageOf(h.client);
    });

    test('step, step, turn with seq 1, 2, 3 and one turnId', () {
      expect(response.resultMap, {'stopReason': 'end_turn'});
      expect(frames.map((f) => f['seq']), [1, 2, 3]);
      expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
      expect(frames.map((f) => f['sessionId']).toSet(), {sessionId});
      final turnId = frames.first['turnId'];
      expect(turnId, isA<String>().having((s) => s, 'turnId', isNotEmpty));
      expect(frames.map((f) => f['turnId']).toSet(), {turnId});
    });

    test('step snapshots carry the step, the turn so far and the session', () {
      final first = frames[0];
      expect(first['step'], {
        'index': 0,
        'model': 'scripted/scripted-1',
        'tokens': tokens(1200, 300, 10000, 0),
        'cost': '0.0111',
      });
      expect(first['turn'], {
        'steps': 1,
        'tokens': tokens(1200, 300, 10000, 0),
        'cost': '0.0111',
      });
      // Сессия считает и текущий ход: `turns` — число ходов, в которых были
      // шаги (D4 п. 4).
      expect(first['session'], {
        'turns': 1,
        'steps': 1,
        'tokens': tokens(1200, 300, 10000, 0),
        'cost': '0.0111',
      });
      final second = frames[1];
      expect(second['step'], {
        'index': 1,
        'model': 'scripted/scripted-1',
        'tokens': tokens(1500, 400, 12000, 800),
        'cost': '0.0171',
      });
      expect(second['turn'], {
        'steps': 2,
        'tokens': tokens(2700, 700, 22000, 800),
        'cost': '0.0282',
      });
      expect(second['session'], {
        'turns': 1,
        'steps': 2,
        'tokens': tokens(2700, 700, 22000, 800),
        'cost': '0.0282',
      });
    });

    test('the turn snapshot is the turn total without a step', () {
      final turn = frames[2];
      expect(turn, isNot(contains('step')));
      expect(turn['turn'], {
        'steps': 2,
        'tokens': tokens(2700, 700, 22000, 800),
        'cost': '0.0282',
      });
      expect(turn['session'], {
        'turns': 1,
        'steps': 2,
        'tokens': tokens(2700, 700, 22000, 800),
        'cost': '0.0282',
      });
    });

    test('currency is USD and context follows the last step (D5)', () {
      for (final frame in frames) {
        expect(frame['currency'], 'USD');
      }
      // После шага с инструментом `used` зависит от оценки хвоста; после
      // текстового шага — якорь usage: 1500 + 12000 + 800 + 400. Окно
      // 32768, запас `reserve_tokens` 8192, порог — 24576.
      expect(frames[0]['context'], {
        'used': isA<int>(),
        'size': 32768,
        'compactAt': 24576,
      });
      expect(frames[1]['context'], {
        'used': 14700,
        'size': 32768,
        'compactAt': 24576,
      });
      expect(frames[2]['context'], {
        'used': 14700,
        'size': 32768,
        'compactAt': 24576,
      });
    });

    test('the turn snapshot goes after the content updates and before the '
        'response (ACP-3, D7)', () {
      final turnAt = positionOfUsage(h.client, 3);
      final responseAt = h.client.received.indexOf(response);
      final lastContent = h.client.received.lastIndexWhere(
        (f) =>
            f is JsonRpcNotification &&
            f.method == 'session/update' &&
            ((f.params! as Map)['update']! as Map)['sessionUpdate'] !=
                'session_info_update',
      );
      expect(turnAt, greaterThan(lastContent));
      expect(turnAt, lessThan(responseAt));
      // Шаги идут по мере хода, а не пачкой в конце: снимок первого шага —
      // до текстового ответа второго.
      final textAt = h.client.received.indexWhere(
        (f) =>
            f is JsonRpcNotification &&
            f.method == 'session/update' &&
            ((f.params! as Map)['update']! as Map)['sessionUpdate'] ==
                'agent_message_chunk',
      );
      expect(positionOfUsage(h.client, 1), lessThan(textAt));
      expect(positionOfUsage(h.client, 2), greaterThan(textAt));
    });

    // «Стандартные типы без новых полей» (D17): usage приходит только в
    // `_codelab/session/usage`; ответ на `session/prompt` и кадры
    // `session/update` новых корневых полей не получают.
    test('standard frames have no usage fields (D17)', () {
      expect(response.result, {'stopReason': 'end_turn'});
      for (final frame in h.client.received) {
        if (frame case JsonRpcNotification(
          method: 'session/update',
          :final params,
        )) {
          expect((params! as Map).keys.toSet(), {'sessionId', 'update'});
          final update = asMap((params as Map)['update']);
          expect(update.keys, isNot(contains('usage')));
          final meta = update['_meta'];
          if (meta != null) {
            expect(
              asMap(asMap(meta)['codelab']).keys,
              isNot(contains('usage')),
            );
          }
        }
      }
    });
  });

  // «Модель без цен и шаг без usage» (D6; фикстура
  // `acp/prompt-usage-unpriced`): `noPrice` — токены без цен, `noUsage` —
  // ответ модели без usage; порядок причин — как в таблице D6; `cost` и
  // `currency` отсутствуют.
  test('a model without prices and an answer without usage', () async {
    final sessionId = await ready(
      steps: [
        taskStep(const {'input': 500, 'output': 100}),
        textStep('Готово.', null),
      ],
    );

    await h.prompt(sessionId, 'Составь список задач');

    final frames = usageOf(h.client);
    expect(frames.map((f) => f['seq']), [1, 2, 3]);
    for (final frame in frames) {
      expect(frame, isNot(contains('currency')));
      for (final key in ['step', 'turn', 'session']) {
        if (frame[key] case final Map<Object?, Object?> part) {
          expect(part, isNot(contains('cost')), reason: '$key of $frame');
        }
      }
    }
    expect(asMap(frames[0]['step'])['partial'], ['noPrice']);
    expect(asMap(frames[0]['turn'])['partial'], ['noPrice']);
    final second = asMap(frames[1]['step']);
    expect(second['tokens'], tokens());
    expect(second['partial'], ['noUsage']);
    for (final frame in frames.skip(1)) {
      expect(asMap(frame['turn'])['partial'], ['noUsage', 'noPrice']);
      expect(asMap(frame['session'])['partial'], ['noUsage', 'noPrice']);
    }
    expect(asMap(frames[2]['turn'])['tokens'], tokens(500, 100));
  });

  // `noUsage` — только при успешном ответе: ответ без usage у единственного
  // шага даёт `noUsage` без `noPrice` (токенов нет, значит, цены не нужны).
  test('an answer without usage alone is noUsage, not noPrice', () async {
    final sessionId = await ready(
      model: pricedModel,
      steps: [textStep('Привет', null)],
    );

    await h.prompt(sessionId, 'Привет');

    final frames = usageOf(h.client);
    expect(frames.map((f) => f['trigger']), ['step', 'turn']);
    expect(asMap(frames[0]['step'])['partial'], ['noUsage']);
    expect(asMap(frames.last['session'])['partial'], ['noUsage']);
    // Цены у модели есть, но считать нечего: стоимости нет, а не `"0"`.
    expect(asMap(frames.last['session']), isNot(contains('cost')));
  });

  // «Отмена посреди инструмента» (D7; фикстура `acp/prompt-usage-cancelled`):
  // потраченное до отмены — настоящий расход; снимок turn — после
  // `tool_call_update` failed и до ответа `cancelled`.
  test('cancel during exec: the turn snapshot is before cancelled', () async {
    final sessionId = await ready(
      model: pricedModel,
      steps: [
        {
          'reply': [
            {
              'toolCall': {
                'id': 'call_3',
                'name': 'exec',
                'arguments': {'command': 'sleep 60'},
              },
            },
          ],
          'usage': const {'input': 800, 'output': 120},
        },
      ],
    );
    final handlers = h.client.handlers;
    handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    };
    handlers['terminal/create'] = (_) => {'terminalId': 'term_1'};
    handlers['terminal/kill'] = (_) => <String, Object?>{};
    handlers['terminal/output'] = (_) => {
      'output': 'zzz\n',
      'truncated': false,
    };
    handlers['terminal/release'] = (_) => <String, Object?>{};

    final turn = h.prompt(sessionId, 'Sleep');
    while (true) {
      final frame = await h.client.next();
      if (frame is JsonRpcRequest && frame.method == 'terminal/wait_for_exit') {
        break;
      }
    }
    await h.client.notify('session/cancel', {'sessionId': sessionId});
    final response = await turn;

    expect(response.resultMap, {'stopReason': 'cancelled'});
    final frames = usageOf(h.client);
    expect(frames.last['trigger'], 'turn');
    expect(asMap(frames.last['turn'])['tokens'], tokens(800, 120));
    expect(asMap(frames.last['turn'])['cost'], '0.0042');
    final turnAt = positionOfUsage(h.client, frames.last['seq']! as int);
    final failedAt = h.client.received.lastIndexWhere(
      (f) =>
          f is JsonRpcNotification &&
          f.method == 'session/update' &&
          ((f.params! as Map)['update']! as Map)['status'] == 'failed',
    );
    expect(failedAt, isNonNegative);
    expect(turnAt, greaterThan(failedAt));
    expect(turnAt, lessThan(h.client.received.indexOf(response)));
  });

  // «Сбой провайдера» (D7, ACP-7): расход до сбоя показан — снимок turn идёт
  // перед ошибкой `-32603`, шаг с ошибкой не даёт `noUsage` (D6).
  test('a provider failure: the turn snapshot is before -32603', () async {
    final sessionId = await ready(
      model: pricedModel,
      steps: [
        taskStep(const {'input': 100, 'output': 20}),
        {
          'error': {'class': 'auth', 'message': '401 Unauthorized'},
        },
      ],
    );

    final response = await h.prompt(sessionId, 'Составь список задач');

    expect(response.errorCode, -32603);
    final frames = usageOf(h.client);
    expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
    final failedStep = asMap(frames[1]['step']);
    expect(failedStep['tokens'], tokens());
    expect(failedStep, isNot(contains('partial')));
    expect(asMap(frames.last['turn'])['tokens'], tokens(100, 20));
    expect(
      positionOfUsage(h.client, 3),
      lessThan(h.client.received.indexOf(response)),
    );
  });

  // «ход перенесён reattach»: ход идёт, первое соединение закрыто, сессию
  // загружает второе; снимок turn уходит новому владельцу перед
  // `session_info_update` с `_meta.codelab.turnEnded` (D18 Т5, ACP-3).
  group('connections of one session', () {
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

    Future<JsonRpcResponse> load(TestClient client, String sessionId) =>
        client.request('session/load', {
          'sessionId': sessionId,
          'cwd': '/work/demo',
          'mcpServers': <Object?>[],
        });

    test('a moved turn: the turn snapshot goes before the turnEnded update '
        'to the new owner', () async {
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
      await load(other, sessionId);
      JsonRpcRequest again;
      while (true) {
        final frame = await other.next();
        if (frame is JsonRpcRequest &&
            frame.method == 'session/request_permission') {
          again = frame;
          break;
        }
      }
      await other.respond(again, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      });
      int endedAt() => other.received.indexWhere(
        (f) =>
            f is JsonRpcNotification &&
            f.method == 'session/update' &&
            ((f.params! as Map)['update']! as Map)['sessionUpdate'] ==
                'session_info_update' &&
            ((f.params! as Map)['update']! as Map)['_meta'] != null,
      );
      while (endedAt() < 0) {
        await other.next();
      }

      final frames = usageOf(other);
      expect(frames.last['trigger'], 'turn');
      expect(frames.map((f) => f['seq']), [1, 2, 3]);
      expect(positionOfUsage(other, 3), lessThan(endedAt()));
    });

    // «Сессия перешла к новому соединению» (Q11 (а), D4): снимки нового хода
    // получает только новое соединение, `seq` продолжает счёт без сброса,
    // агрегат `session` включает прежние ходы, `beforeLoad` нет.
    test('a session that moved to a new connection continues seq without a '
        'reset', () async {
      final sessionId = await ready(
        model: pricedModel,
        steps: [
          taskStep(step0),
          textStep('Список готов.', step1),
          textStep('Ещё ответ.', const {'input': 100, 'output': 50}),
        ],
      );
      await h.prompt(sessionId, 'Составь список задач');
      expect(usageOf(h.client).map((f) => f['seq']), [1, 2, 3]);

      final other = await connectDeclaring();
      expect((await load(other, sessionId)).error, isNull);
      expect(usageOf(other), isEmpty, reason: 'replay is not accounting');
      final second = await other.request('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'Ещё'},
        ],
      });

      expect(second.resultMap, {'stopReason': 'end_turn'});
      final frames = usageOf(other);
      expect(frames.map((f) => f['seq']), [4, 5]);
      expect(frames.map((f) => f['trigger']), ['step', 'turn']);
      expect(frames.first['turnId'], isNot(usageOf(h.client).first['turnId']));
      final session = asMap(frames.last['session']);
      expect(session['turns'], 2);
      expect(session['steps'], 3);
      expect(session['tokens'], tokens(2800, 750, 22000, 800));
      expect(session, isNot(contains('partial')));
      // Прежнее соединение новых снимков не получает.
      expect(usageOf(h.client).map((f) => f['seq']), [1, 2, 3]);
    });
  });

  // «Субагент на модели без цен» (Q13 (б), D6): токены ребёнка в
  // `TurnEnded.usage` при нулевой стоимости — `noPrice` у turn и session;
  // собственные шаги корня usage не несут, поэтому причина берётся именно из
  // эвристики по `subagentUsage`, а не из шагов.
  test(
    'a child on a model without prices marks turn and session noPrice',
    () async {
      h = await ServerHarness.start(
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'call_1',
                  'name': 'agent',
                  'arguments': {
                    'type': 'explore',
                    'description': 'Find auth code',
                    'prompt': 'Find where authentication is implemented.',
                  },
                },
              },
            ],
          },
          {
            'reply': [
              {'text': 'Auth lives in lib/auth.dart.'},
            ],
            'usage': {'input': 100, 'output': 20},
          },
          textStep('Done.', null),
        ],
        configSource: LayeredConfigSource(
          extra: {
            'providers': {
              'a': {
                'kind': 'openai-compatible',
                'base_url': 'https://a.test/v1',
                'models': {
                  'm1': {'context_window': 65536},
                },
              },
            },
          },
        ),
      );
      await h.initialize(clientCapabilities: usageClient);
      final sessionId = await h.newSession();

      await h.prompt(sessionId, 'Where is auth?');

      final turn = usageOf(h.client).singleWhere((f) => f['trigger'] == 'turn');
      expect(asMap(turn['turn'])['tokens'], tokens(100, 20));
      expect(asMap(turn['turn'])['partial'], contains('noPrice'));
      expect(asMap(turn['session'])['partial'], contains('noPrice'));
      // Шаги корня без токенов: `noPrice` у шага не ставится.
      for (final step in usageOf(
        h.client,
      ).where((f) => f['trigger'] == 'step')) {
        expect(asMap(step['step'])['partial'], isNot(contains('noPrice')));
      }
    },
  );

  // Q14 (б), D14: каждая отправка — debug `acp.usage.sent` с
  // `{session_id, seq, trigger}` и без токенов, денег и текстов; уведомление
  // не несёт текстов сообщений (маркер утечки в запросе и ответе).
  test('every send is a debug acp.usage.sent without tokens and money, and '
      'the notification has no secrets', () async {
    final sessionId = await ready(
      model: pricedModel,
      steps: [taskStep(step0), textStep('Ответ с $leak', step1)],
    );

    await h.prompt(sessionId, 'Ключ $leak');

    final frames = usageOf(h.client);
    final records = h.logger.eventsOf('acp.usage.sent');
    expect(records, hasLength(frames.length));
    for (final (i, record) in records.indexed) {
      expect(record.level, LogLevel.debug);
      expect(record.fields, {
        'session_id': sessionId,
        'seq': frames[i]['seq'],
        'trigger': frames[i]['trigger'],
      });
    }
    expect(jsonEncode(frames), isNot(contains(leak)));
    expect(
      jsonEncode([for (final r in h.logger.records) r.fields]),
      isNot(contains('0.0111')),
    );
  });

  // «Автосжатие выключено» (Q10 (а), D5; фикстура
  // `acp/prompt-usage-compaction-off`): оценщик заполнения у цикла есть
  // всегда, поэтому `context` с `used` и `size`, но без `compactAt`.
  test('compaction off: context has used and size without compactAt', () async {
    final sessionId = await ready(
      model: pricedModel,
      narrow: const {HostCapability.compaction: CapabilityOff('тест')},
      steps: [
        textStep('Привет! Чем помочь?', const {'input': 1000, 'output': 200}),
      ],
    );

    await h.prompt(sessionId, 'Привет');

    final frames = usageOf(h.client);
    expect(frames, hasLength(2));
    for (final frame in frames) {
      expect(frame['context'], {'used': 1200, 'size': 32768});
    }
  });

  // «Встроенная команда без модели» (D4 п. 5, D18 Т7): `/status` — ход без
  // шагов, уведомлений нет; ответ — как прежде.
  test('a built-in /status turn sends no usage notifications', () async {
    final sessionId = await ready(model: pricedModel);

    final response = await h.prompt(sessionId, '/status');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    expect(usageOf(h.client), isEmpty);
  });

  // «Клиент без объявления» (D3): ни одного кадра `_codelab/session/usage`,
  // остальные кадры хода — прежние (ход с двумя шагами).
  test('a connection that did not declare usage receives no frames', () async {
    final sessionId = await ready(
      declare: false,
      model: pricedModel,
      steps: [taskStep(step0), textStep('Список готов.', step1)],
    );

    final response = await h.prompt(sessionId, 'Составь список задач');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    expect(usageOf(h.client), isEmpty);
    expect(h.logger.eventsOf('acp.usage.sent'), isEmpty);
    final methods = {
      for (final frame in h.client.received)
        if (frame is JsonRpcNotification) frame.method,
    };
    expect(methods, {'session/update'});
  });

  // «Сжатие контекста» (D5; фикстура `acp/compact-usage-context`): ход
  // `/compact` без шага модели — снимка turn нет, а после `ContextCompacted`
  // приходит `trigger: compaction` без `turnId`, `step` и `turn`, с
  // `context.used`, меньшим, чем в последнем снимке хода.
  test('/compact sends a compaction snapshot without turnId', () async {
    final longReply = 'Ответ подробно. ' * 150;
    final sessionId = await ready(
      model: pricedModel,
      compaction: const CompactionOverrides(keepRecentTokens: 512),
      steps: [
        textStep(longReply, const {'input': 100, 'output': 20}),
        textStep(longReply, const {'input': 20000, 'output': 20}),
        textStep('Пользователь задал два вопроса.', null),
      ],
    );
    await h.prompt(sessionId, 'Первый вопрос');
    await h.prompt(sessionId, 'Второй вопрос');
    final before = usageOf(h.client);
    expect(before.map((f) => f['seq']), [1, 2, 3, 4]);
    expect(asMap(before.last['context'])['used'], 20020);

    final response = await h.prompt(sessionId, '/compact обработка ошибок');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final frames = usageOf(h.client);
    expect(frames, hasLength(5));
    final compaction = frames.last;
    expect(compaction['seq'], 5);
    expect(compaction['trigger'], 'compaction');
    expect(
      compaction.keys.toSet().intersection({'turnId', 'step', 'turn'}),
      isEmpty,
    );
    final context = asMap(compaction['context']);
    expect(context['used'], lessThan(20020));
    // `size` и `compactAt` — из последнего `StepEnded` (D5).
    expect(context['size'], 32768);
    expect(context['compactAt'], 24576);
    expect(asMap(compaction['session'])['turns'], 2);
    expect(asMap(compaction['session'])['steps'], 2);
    expect(
      positionOfUsage(h.client, 5),
      lessThan(h.client.received.indexOf(response)),
    );
  });

  // «Сессия после загрузки» (Q7 (а), D6; фикстура
  // `acp/session-load-usage-partial`): журнал с ответами модели загружен в
  // новом сервере — до хода снимков нет, потом `session.partial` содержит
  // `beforeLoad`, а `session.turns` считает только ходы после загрузки.
  test('session/load of a journal with model answers: beforeLoad after the '
      'first turn, no snapshots before it', () async {
    final sessionId = await ready(
      model: pricedModel,
      steps: [
        textStep('Здравствуйте.', const {'input': 10, 'output': 5}),
      ],
    );
    await h.prompt(sessionId, 'Привет');
    final store = h.store;
    await h.dispose();

    h = await ServerHarness.start(
      sessions: store,
      defaultModel: pricedModel,
      steps: [
        textStep('Вот ответ.', const {'input': 100, 'output': 50}),
      ],
    );
    await h.initialize(clientCapabilities: usageClient);
    final load = await h.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    expect(load.error, isNull);
    expect(usageOf(h.client), isEmpty, reason: 'replay is not accounting');

    await h.prompt(sessionId, 'Ещё раз');

    final frames = usageOf(h.client);
    expect(frames.map((f) => f['seq']), [1, 2]);
    for (final frame in frames) {
      final session = asMap(frame['session']);
      expect(session['partial'], ['beforeLoad']);
      expect(session['turns'], 1);
      expect(session['tokens'], tokens(100, 50));
      expect(session['cost'], '0.00105');
    }
  });
}
