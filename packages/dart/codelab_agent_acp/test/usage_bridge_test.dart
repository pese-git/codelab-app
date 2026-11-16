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
          stopReason: StopReason.stop,
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
}
