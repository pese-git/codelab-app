import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/session_bridge.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';
import 'support/fake_bridge_session.dart';
import 'support/server_harness.dart' show scriptedModel;

/// Учёт usage на уровне `SessionBridge` с фальшивой сессией: события ядра
/// подаёт тест, поэтому проверяются случаи, которых настоящий ход не даёт
/// (шаг вне хода, цены с мусором) и порядок кадров при реплее (change
/// `add-usage-extension`, D4, D6, D14, D18 Т5; AGENTS.md §9).
void main() {
  const root = SessionId('sess_fake');

  late FakeBridgeSession session;
  late ClientChannel channel;

  /// Лента порядка: `replay:<вид>`, `live:<вид>` — кадры `session/update`,
  /// `usage:<trigger>` — кадры `_codelab/session/usage`.
  late List<String> log;

  /// Параметры принятых кадров usage по порядку.
  late List<Map<String, Object?>> usage;

  Future<SessionBridge> open({bool declare = true}) async {
    channel = await ClientChannel.open(
      capabilities: acp.ClientCapabilities(
        terminal: true,
        meta: declare
            ? const {
                'codelab': {
                  'usage': {'version': 1},
                  // Без этого согласия реплей не придерживает кадры хода.
                  'subagentToolCalls': {'version': 1},
                },
              }
            : null,
      ),
    );
    session = FakeBridgeSession();
    log = [];
    usage = [];
    return SessionBridge(
      owner: Object(),
      sink: (n) => log.add('live:${n.update.toJson()['sessionUpdate']}'),
      usageSink: (frame) {
        final params = (frame as acp.JsonRpcNotification).params! as Map;
        usage.add(params.cast<String, Object?>());
        log.add('usage:${params['trigger']}');
      },
      link: channel.link,
      clock: channel.clock,
      logger: channel.logger,
    )..attach(session);
  }

  tearDown(() => session.dispose());

  Future<void> pump() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ModelRef modelWith(ModelCost? cost) => ModelRef(
    provider: 'scripted',
    id: 'scripted-1',
    api: scriptedModel.api,
    baseUrl: scriptedModel.baseUrl,
    contextWindow: scriptedModel.contextWindow,
    maxOutputTokens: scriptedModel.maxOutputTokens,
    cost: cost,
  );

  StepEnded step({
    ModelCost? price = const ModelCost(input: 3, output: 15),
    Usage? used,
    int index = 0,
    StopReason reason = StopReason.stop,
  }) {
    final spent =
        used ??
        Usage(
          input: 100,
          output: 20,
          cost: price == null
              ? UsageCost.zero
              : UsageCost(
                  input: 100 * price.input / 1e6,
                  output: 20 * price.output / 1e6,
                ),
        );
    return StepEnded(
      root,
      result: StepResult(
        stepIndex: index,
        response: AssistantMessage(
          content: const [],
          model: modelWith(price),
          usage: spent,
          stopReason: reason,
          timestamp: DateTime.utc(2026),
        ),
        results: const [],
        usage: spent,
      ),
    );
  }

  const turnId = TurnId('turn_1');

  void startTurn() =>
      session.emit(TurnStarted(root, turnId: turnId, input: []));

  void endTurn([Usage? total]) => session.emit(
    TurnEnded(
      root,
      reason: TurnEndReason.completed,
      usage: total ?? Usage.zero,
    ),
  );

  // Поздний `StepEnded` после `TurnEnded` или до `TurnStarted` не учитывается
  // и кадра не даёт; `seq` при этом не тратится (D4, AGENTS.md §9).
  test('a StepEnded outside a turn sends nothing and spends no seq', () async {
    await open();

    session.emit(step());
    await pump();
    expect(usage, isEmpty);

    startTurn();
    session.emit(step());
    endTurn(step().result.usage);
    session.emit(step(index: 1));
    await pump();

    expect(usage.map((f) => f['trigger']), ['step', 'turn']);
    expect(usage.map((f) => f['seq']), [1, 2]);
    expect((usage.last['turn']! as Map)['steps'], 1);
  });

  group('a price that is not a finite non-negative number', () {
    // Бесконечная или отрицательная цена — «цены нет»: `noPrice` и ни
    // `cost`, ни исключения в обработчике события (D6, §12.1.5).
    for (final (name, price) in [
      ('infinite', const ModelCost(input: double.infinity, output: 15)),
      ('negative', const ModelCost(input: -3000, output: 15)),
      ('NaN', const ModelCost(input: double.nan, output: 15)),
    ]) {
      test('$name: noPrice without cost, the turn goes on', () async {
        await open();
        final first = step(price: price);
        final second = step(price: price, index: 1);

        startTurn();
        session
          ..emit(first)
          ..emit(second);
        endTurn(first.result.usage + second.result.usage);
        await pump();

        expect(usage.map((f) => f['trigger']), ['step', 'step', 'turn']);
        for (final frame in usage) {
          expect(frame, isNot(contains('currency')), reason: '$frame');
          for (final key in ['step', 'turn', 'session']) {
            if (frame[key] case final Map<Object?, Object?> part) {
              expect(part, isNot(contains('cost')), reason: '$key of $frame');
            }
          }
        }
        expect((usage.first['step']! as Map)['partial'], ['noPrice']);
        expect((usage.last['turn']! as Map)['partial'], ['noPrice']);
        expect((usage.last['session']! as Map)['partial'], ['noPrice']);
      });
    }

    test('a client without usage is not affected either', () async {
      await open(declare: false);
      const price = ModelCost(input: double.infinity, output: 15);
      final spent = step(price: price);

      startTurn();
      session.emit(spent);
      endTurn(spent.result.usage);
      await pump();

      expect(usage, isEmpty);
      expect(channel.logger.eventsOf('acp.usage.sent'), isEmpty);
    });
  });

  // D6: у шага на модели с ценами `cost` есть всегда, `"0"` при нуле токенов.
  test('a priced step without tokens has cost "0"', () async {
    await open();

    startTurn();
    session.emit(step(used: Usage.zero));
    endTurn();
    await pump();

    expect((usage.first['step']! as Map)['cost'], '0');
    expect((usage.last['turn']! as Map)['cost'], '0');
    expect((usage.last['session']! as Map)['cost'], '0');
    expect(usage.last['currency'], 'USD');
  });

  // D26: `aborted` с нулевым usage провайдера — провайдер usage не прислал
  // (отмена посреди потока), поэтому `noUsage` ставится шагу, ходу и сессии.
  test('an aborted step without provider usage is noUsage (D26)', () async {
    await open();

    startTurn();
    session.emit(step(used: Usage.zero, reason: StopReason.aborted));
    endTurn();
    await pump();

    final first = usage.first['step']! as Map;
    expect(first['partial'], ['noUsage']);
    expect(first['cost'], '0');
    expect((usage.last['turn']! as Map)['partial'], contains('noUsage'));
    expect((usage.last['session']! as Map)['partial'], contains('noUsage'));
  });

  // D26, контроль: частичный usage провайдера (`input > 0`) — не причина.
  test(
    'an aborted step with partial provider usage is not noUsage (D26)',
    () async {
      await open();

      startTurn();
      session.emit(
        step(
          used: const Usage(input: 40, output: 0),
          reason: StopReason.aborted,
        ),
      );
      endTurn();
      await pump();

      expect(usage.first['step']! as Map, isNot(contains('partial')));
      expect(usage.last['turn']! as Map, isNot(contains('partial')));
      expect(usage.last['session']! as Map, isNot(contains('partial')));
    },
  );

  // D26, контроль: `aborted` с `input == 0`, но `output > 0` — провайдер usage
  // прислал, условие именно `input + output == 0`, а не `input == 0`.
  test('an aborted step with output only is not noUsage (D26)', () async {
    await open();

    startTurn();
    session.emit(
      step(used: const Usage(input: 0, output: 7), reason: StopReason.aborted),
    );
    endTurn();
    await pump();

    expect(usage.first['step']! as Map, isNot(contains('partial')));
    expect(usage.last['turn']! as Map, isNot(contains('partial')));
    expect(usage.last['session']! as Map, isNot(contains('partial')));
  });

  // D26, инвариант дельты agent-acp-server: `noUsage` и `noPrice` у шага вместе
  // не бывают. Шаг только с кэш-токенами — usage провайдер прислал, значит,
  // `noUsage` нет; на модели без цен остаётся одно `noPrice`.
  for (final reason in [StopReason.stop, StopReason.aborted]) {
    test('a cache-only ${reason.name} step on a model without prices is '
        'noPrice only', () async {
      await open();

      startTurn();
      session.emit(
        step(
          price: null,
          used: const Usage(input: 0, output: 0, cacheRead: 10000),
          reason: reason,
        ),
      );
      endTurn();
      await pump();

      expect((usage.first['step']! as Map)['partial'], ['noPrice']);
      expect((usage.last['turn']! as Map)['partial'], ['noPrice']);
      expect((usage.last['session']! as Map)['partial'], ['noPrice']);
    });

    test('a cache-only ${reason.name} step on a priced model has no partial '
        'and cost by cacheRead', () async {
      await open();

      startTurn();
      session.emit(
        step(
          price: const ModelCost(input: 3, output: 15, cacheRead: 0.3),
          used: const Usage(
            input: 0,
            output: 0,
            cacheRead: 10000,
            cost: UsageCost(cacheRead: 0.003),
          ),
          reason: reason,
        ),
      );
      endTurn();
      await pump();

      final first = usage.first['step']! as Map;
      expect(first, isNot(contains('partial')));
      expect(first['cost'], '0.003');
      expect(usage.last['turn']! as Map, isNot(contains('partial')));
      expect(usage.last['session']! as Map, isNot(contains('partial')));
    });
  }

  // D26: только `cacheWrite` — тоже usage провайдера, `noUsage` нет.
  test(
    'a cacheWrite-only step on a model without prices is noPrice only',
    () async {
      await open();

      startTurn();
      session.emit(
        step(
          price: null,
          used: const Usage(input: 0, output: 0, cacheWrite: 500),
          reason: StopReason.aborted,
        ),
      );
      endTurn();
      await pump();

      expect((usage.first['step']! as Map)['partial'], ['noPrice']);
      expect((usage.last['turn']! as Map)['partial'], ['noPrice']);
    },
  );

  // D26, контроль: `error` с нулями — сбой, а не молчание провайдера.
  test('an error step with zero usage is not noUsage (D26)', () async {
    await open();

    startTurn();
    session.emit(step(used: Usage.zero, reason: StopReason.error));
    endTurn();
    await pump();

    expect(usage.first['step']! as Map, isNot(contains('partial')));
    expect(usage.last['turn']! as Map, isNot(contains('partial')));
    expect(usage.last['session']! as Map, isNot(contains('partial')));
  });

  // D26, контроль: синтетический `overflow` (`_exhausted`, провайдер не
  // вызывался) — это `error` с нулями, `noUsage` у него нет.
  test('a synthetic overflow step is not noUsage (D26)', () async {
    await open();

    startTurn();
    const spent = Usage.zero;
    session.emit(
      StepEnded(
        root,
        result: StepResult(
          stepIndex: 0,
          response: AssistantMessage(
            content: const [],
            model: modelWith(const ModelCost(input: 3, output: 15)),
            usage: spent,
            stopReason: StopReason.error,
            errorClass: LlmErrorClass.overflow,
            errorMessage: 'context exhausted',
            timestamp: DateTime.utc(2026),
          ),
          results: const [],
          usage: spent,
        ),
      ),
    );
    endTurn();
    await pump();

    expect(usage.first['step']! as Map, isNot(contains('partial')));
    expect(usage.last['turn']! as Map, isNot(contains('partial')));
  });

  // D18 Т5: кадр usage, построенный во время реплея, уходит после кадров
  // реплея и в общем порядке с `session/update` живого хода.
  test('a usage frame built during the replay goes after the replay frames '
      'in the common order', () async {
    final bridge = await open();
    final gate = Completer<void>();
    session.replayTreeGates.add(gate);
    startTurn();
    await pump();
    log.clear();
    usage.clear();

    final replay = bridge.replayInto((u) => log.add('replay'));
    await pump();
    session.emit(
      MessageDelta(
        root,
        delta: 'live',
        partial: AssistantMessage(
          content: const [],
          model: scriptedModel,
          usage: Usage.zero,
          stopReason: StopReason.stop,
          timestamp: DateTime.utc(2026),
        ),
      ),
    );
    session.emit(step());
    await pump();
    expect(log, isEmpty, reason: 'ничего не уходит до конца реплея');
    expect(usage, isEmpty);

    gate.complete();
    await replay;

    final firstLive = log.indexWhere((e) => e != 'replay');
    expect(firstLive, greaterThan(0));
    expect(log.sublist(0, firstLive).every((e) => e == 'replay'), isTrue);
    expect(log.sublist(firstLive), ['live:agent_message_chunk', 'usage:step']);
    expect(usage.single['seq'], 1);
  });

  // D3 «кадр только объявившему»: кадр, придержанный на реплее, при выпуске
  // заново проверяет согласие текущего соединения, а не соединения, при
  // котором он построен.
  test('a held usage frame is dropped when the new connection did not '
      'declare usage', () async {
    final bridge = await open();
    final gate = Completer<void>();
    session.replayTreeGates.add(gate);
    startTurn();
    await pump();
    usage.clear();

    final replay = bridge.replayInto((u) {});
    await pump();
    session.emit(step());
    await pump();
    expect(usage, isEmpty, reason: 'кадр придержан на реплее');

    bridge.detach(const Duration(seconds: 1));
    bridge.reattach(
      owner: Object(),
      requests: channel.requests,
      capabilities: const acp.ClientCapabilities(terminal: true),
      sink: (_) {},
      usageSink: (frame) => usage.add(const {'late': true}),
    );
    gate.complete();
    await replay;
    await pump();

    expect(usage, isEmpty);
  });

  // Граница точного целого `double`: 2^53 микроединиц уже не «безопасное»
  // число (безопасный предел 2^53 - 1), а явно большая цена — тем более.
  group('micro-units beyond 2^53 - 1', () {
    for (final (name, total) in [
      ('exactly 2^53', 9007199254.740992),
      ('far above', 1e12),
    ]) {
      test('$name: noPrice without cost, the turn goes on', () async {
        await open();

        startTurn();
        session.emit(
          step(
            used: Usage(
              input: 1000000,
              output: 0,
              cost: UsageCost(input: total, output: 0),
            ),
          ),
        );
        await pump();

        final frame = usage.single;
        expect(frame, isNot(contains('currency')));
        expect(frame['step'], isNot(contains('cost')));
        expect((frame['step']! as Map)['partial'], ['noPrice']);
      });
    }
  });

  // D14, §16: запись `acp.usage.sent` несёт `turn_id`, если ход известен
  // (снимок `compaction` вне хода — без него), без токенов и денег.
  test('acp.usage.sent carries turn_id when the turn is known', () async {
    await open();

    startTurn();
    session.emit(step());
    endTurn(step().result.usage);
    session.emit(
      const ContextCompacted(root, tokensBefore: 1000, tokensAfter: 100),
    );
    await pump();

    final records = channel.logger.eventsOf('acp.usage.sent');
    expect(records.map((r) => r.fields['trigger']), [
      'step',
      'turn',
      'compaction',
    ]);
    expect(records[0].fields['turn_id'], 'turn_1');
    expect(records[1].fields['turn_id'], 'turn_1');
    expect(records[2].fields, isNot(contains('turn_id')));
    for (final record in records) {
      expect(
        record.fields.keys.toSet().intersection({
          'tokens',
          'cost',
          'input',
          'output',
        }),
        isEmpty,
      );
    }
  });

  // «Отброшенный проход сжатия» (change `fix-discarded-compaction-usage`, D5,
  // CMP-13): суммаризатор оплачен, а `compaction` не записан — usage входит
  // в сумму сессии снимком `compactionDiscarded` без хода. Каталог фальшивой
  // сессии без цен, поэтому цена здесь — `noPrice`; ветка с ценами идёт через
  // настоящее ядро (`usage_ledger_seed_test.dart`, фикстура
  // `acp/compact-no-gain-usage`).
  group('a discarded compaction pass', () {
    CompactionDiscarded discarded({
      Usage usage = const Usage(input: 900, output: 120),
      int tokensBefore = 120,
      int tokensAfter = 150,
    }) => CompactionDiscarded(
      root,
      tokensBefore: tokensBefore,
      tokensAfter: tokensAfter,
      usage: usage,
      model: 'scripted/scripted-1',
    );

    StepEnded stepWithContext() => StepEnded(
      root,
      result: step().result,
      context: const ContextFill(used: 120, window: 32000, compactAt: 24000),
    );

    Map<String, Object?> asMap(Object? value) =>
        (value! as Map).cast<String, Object?>();

    test('sends a snapshot without turn fields; session has the summarizer, '
        'turns and steps do not change, used is tokensBefore', () async {
      await open();
      startTurn();
      session.emit(stepWithContext());
      endTurn(step().result.usage);
      usage.clear();

      session.emit(discarded(tokensBefore: 120, tokensAfter: 130));
      await pump();

      final frame = usage.single;
      expect(frame['trigger'], 'compactionDiscarded');
      expect(frame['seq'], 3);
      expect(
        frame.keys.toSet().intersection({'turnId', 'step', 'turn'}),
        isEmpty,
      );
      final total = asMap(frame['session']);
      expect(total['turns'], 1);
      expect(total['steps'], 1);
      expect(asMap(total['tokens'])['input'], 1000);
      expect(asMap(total['tokens'])['output'], 140);
      expect(total['partial'], ['noPrice']);
      expect(frame['context'], {
        'used': 120,
        'size': 32000,
        'compactAt': 24000,
      });
      expect(log.last, 'usage:compactionDiscarded');
    });

    test('used is tokensBefore of the event, not of the last step', () async {
      await open();
      startTurn();
      session.emit(stepWithContext());
      endTurn(step().result.usage);
      usage.clear();

      session.emit(discarded(tokensBefore: 777, tokensAfter: 800));
      await pump();

      expect(asMap(usage.single['context'])['used'], 777);
    });

    test('without a known fill there is no context', () async {
      await open();

      session.emit(discarded());
      await pump();

      expect(usage.single['trigger'], 'compactionDiscarded');
      expect(usage.single, isNot(contains('context')));
    });

    test(
      'a zero usage still sends the snapshot, the sum does not grow',
      () async {
        await open();
        startTurn();
        session.emit(stepWithContext());
        endTurn(step().result.usage);
        usage.clear();

        session.emit(discarded(usage: Usage.zero));
        await pump();

        final frame = usage.single;
        expect(frame['trigger'], 'compactionDiscarded');
        final total = asMap(frame['session']);
        expect(asMap(total['tokens'])['input'], 100);
        expect(asMap(total['tokens'])['output'], 20);
      },
    );

    test('a client that did not declare usage gets no frames, the sum is kept '
        'for later snapshots', () async {
      final bridge = await open(declare: false);

      session.emit(discarded());
      await pump();
      expect(usage, isEmpty);

      // Сумма копится независимо от согласия: новый владелец, объявивший
      // `usage`, видит её в следующем снимке (Q11 (а)).
      bridge.detach(const Duration(seconds: 1));
      bridge.reattach(
        owner: Object(),
        requests: channel.requests,
        capabilities: const acp.ClientCapabilities(
          terminal: true,
          meta: {
            'codelab': {
              'usage': {'version': 1},
            },
          },
        ),
        sink: (_) {},
        usageSink: (frame) => usage.add(
          ((frame as acp.JsonRpcNotification).params! as Map)
              .cast<String, Object?>(),
        ),
      );
      startTurn();
      session.emit(stepWithContext());
      await pump();

      expect(usage.single['trigger'], 'step');
      expect(asMap(asMap(usage.single['session'])['tokens'])['input'], 1000);
    });

    test('the sum stays in the session: the next step snapshot keeps it, '
        'the turn does not', () async {
      await open();
      session.emit(discarded());
      startTurn();
      session.emit(stepWithContext());
      await pump();

      final stepFrame = usage.last;
      expect(stepFrame['trigger'], 'step');
      expect(asMap(asMap(stepFrame['turn'])['tokens'])['input'], 100);
      expect(asMap(asMap(stepFrame['session'])['tokens'])['input'], 1000);
    });

    test('acp.usage.sent has trigger compactionDiscarded, no turn_id and no '
        'tokens', () async {
      await open();

      session.emit(discarded());
      await pump();

      final record = channel.logger.eventsOf('acp.usage.sent').single;
      expect(record.fields['trigger'], 'compactionDiscarded');
      expect(record.fields, isNot(contains('turn_id')));
      expect(
        record.fields.keys.toSet().intersection({'tokens', 'cost'}),
        isEmpty,
      );
    });

    test('a recorded compaction keeps its trigger', () async {
      await open();

      session.emit(
        const ContextCompacted(root, tokensBefore: 1000, tokensAfter: 100),
      );
      await pump();

      expect(usage.single['trigger'], 'compaction');
    });

    test('no session/update frame', () async {
      await open();

      session.emit(discarded());
      await pump();

      expect(log.where((l) => !l.startsWith('usage:')), isEmpty);
    });
  });
}
