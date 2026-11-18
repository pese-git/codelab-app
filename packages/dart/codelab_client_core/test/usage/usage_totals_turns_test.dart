// Число ходов агрегата `UsageTotals.turns` (задача 1.1 `[client]` change
// `fix-usage-pane-live-cards`; spec acp-client-kit «Usage сессии», сценарий
// «Число ходов сессии»; design.md, D2).
//
// Красные тесты: у `UsageTotals` нет поля `turns` (задача 1.2), поэтому файл
// не компилируется. Отсутствующий символ: `UsageTotals.turns` (`int?`).
//
// Что проверяется:
//   * `UsageDecoder` читает `turns` у `session` и у `turn`: целое >= 0 —
//     значение; строка, дробь, отрицательное — `null` и предупреждение
//     `field: <агрегат>.turns`, `reason: wrong_type`, снимок применяется;
//     без поля — `null` без предупреждения;
//   * `UsageLedgerDecoder` разбирает `total` той же функцией, поэтому
//     `total.turns` появляется, а `turnCount` остаётся прежним (D2:
//     «kit не сливает журнал со снимками»);
//   * свёртка в `SessionView.usage` — то же на живых снимках: одно
//     предупреждение `usage.decode_failed` на сессию и поле, без сырых
//     значений (AGENTS.md §10, §16).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/usage_agent.dart';

/// Маркер утечки: сырое значение не должно попасть в предупреждение.
const _leak = 'sk-test-leak-0123456789';

Map<String, Object?> _tokens() => {
  'input': 100,
  'output': 10,
  'cacheRead': 5,
  'cacheWrite': 0,
};

/// Снимок D2: [session] и [turn] подставляются как есть.
Map<String, Object?> _snapshot({
  required Map<String, Object?> session,
  Map<String, Object?>? turn,
  int seq = 1,
}) => {
  'sessionId': 's-1',
  'seq': seq,
  'trigger': 'turn',
  'turnId': 't-1',
  'turn': ?turn,
  'session': session,
  'currency': 'USD',
};

Map<String, Object?> _aggregate({Object? turns = 3, bool withTurns = true}) => {
  if (withTurns) 'turns': turns,
  'steps': 7,
  'tokens': _tokens(),
  'cost': '0.0372',
};

void main() {
  group('UsageDecoder', () {
    late List<(String field, String reason)> warnings;
    const decoder = UsageDecoder();

    UsageSnapshot? decode(Map<String, Object?> params) => decoder.decode(
      params,
      onWarning: (field, reason) => warnings.add((field, reason)),
    );

    setUp(() => warnings = []);

    test('session.turns 3 is kept; steps stay as they were', () {
      final snapshot = decode(_snapshot(session: _aggregate()))!;

      expect(snapshot.session.turns, 3);
      expect(snapshot.session.steps, 7);
      expect(warnings, isEmpty);
    });

    test('zero turns is a value, not an absence', () {
      final snapshot = decode(_snapshot(session: _aggregate(turns: 0)))!;

      expect(snapshot.session.turns, 0);
      expect(warnings, isEmpty);
    });

    for (final (name, value) in <(String, Object?)>[
      ('a string', '3'),
      ('a negative number', -1),
      ('a fraction', 2.5),
      ('a bool', true),
      ('a leaking string', _leak),
    ]) {
      test('session.turns as $name: null, one wrong_type warning, the '
          'snapshot is applied', () {
        final snapshot = decode(_snapshot(session: _aggregate(turns: value)))!;

        expect(snapshot.session.turns, isNull);
        expect(snapshot.session.steps, 7);
        expect(snapshot.session.tokens.input, 100);
        expect(snapshot.session.cost!.micros, 37200);
        expect(warnings, [('session.turns', 'wrong_type')]);
      });
    }

    test('without the field turns is null and there is no warning', () {
      final snapshot = decode(
        _snapshot(session: _aggregate(withTurns: false)),
      )!;

      expect(snapshot.session.turns, isNull);
      expect(warnings, isEmpty);
    });

    test('the turn aggregate carries no turns: null without a warning', () {
      final snapshot = decode(
        _snapshot(
          session: _aggregate(),
          turn: {'steps': 2, 'tokens': _tokens(), 'cost': '0.0183'},
        ),
      )!;

      expect(snapshot.turn!.turns, isNull);
      expect(snapshot.session.turns, 3);
      expect(warnings, isEmpty);
    });

    test('turn.turns of a wrong type is named by its own aggregate', () {
      final snapshot = decode(
        _snapshot(
          session: _aggregate(),
          turn: {'turns': '1', 'steps': 2, 'tokens': _tokens()},
        ),
      )!;

      expect(snapshot.turn!.turns, isNull);
      expect(warnings, [('turn.turns', 'wrong_type')]);
    });

    test('the warning does not carry the raw value (AGENTS.md §10)', () {
      decode(_snapshot(session: _aggregate(turns: _leak)));

      expect(warnings.toString(), isNot(contains(_leak)));
    });
  });

  group('UsageLedgerDecoder (the shared aggregate parser, D2)', () {
    late List<(String field, String reason)> warnings;
    const decoder = UsageLedgerDecoder();

    UsageLedgerView? decode(Object? turns) => decoder.decode({
      'sessionId': 's-1',
      'seq': 12,
      'currency': 'USD',
      'ledger': {'status': 'rebuilt', 'reason': 'stale', 'records': 3},
      'total': _aggregate(turns: turns),
      'turns': [
        {
          'index': 1,
          'total': {'steps': 2, 'tokens': _tokens()},
          'steps': const <Object?>[],
        },
        {
          'index': 2,
          'total': {'steps': 1, 'tokens': _tokens()},
          'steps': const <Object?>[],
        },
      ],
    }, onWarning: (field, reason) => warnings.add((field, reason)));

    setUp(() => warnings = []);

    test('total.turns is kept, turnCount is still the number of turns', () {
      final view = decode(2)!;

      expect(view.total.turns, 2);
      expect(view.turnCount, 2);
      expect(warnings, isEmpty);
    });

    test('total.turns wins over the number of ledger records: 3 with two '
        'records kept (D2: kit does not merge the ledger with snapshots)', () {
      final view = decode(3)!;

      expect(view.turns, hasLength(2));
      expect(view.total.turns, 3);
      expect(view.turnCount, 3);
    });

    test('total.turns of a wrong type: null, turnCount is the former 0 '
        '(D2: kit does not derive the turn count from records)', () {
      final view = decode('2')!;

      expect(view.total.turns, isNull);
      expect(view.turnCount, 0);
      expect(warnings, [('total.turns', 'wrong_type')]);
    });
  });

  group('SessionView.usage', () {
    late UsageAgent agent;

    tearDown(() => agent.dispose());

    Future<SessionHandle> connected() async {
      agent = UsageAgent(capabilities: usageCapabilities);
      await agent.start();
      return agent.newSession('s-1');
    }

    test(
      'a live snapshot with turns 3 and steps 7 gives usage.session.turns '
      '3; the turn aggregate has none (scenario «Число ходов сессии»)',
      () async {
        final session = await connected();

        agent.usage(
          _snapshot(
            session: _aggregate(),
            turn: {'steps': 2, 'tokens': _tokens()},
          ),
        );

        expect(session.current.usage.session!.turns, 3);
        expect(session.current.usage.session!.steps, 7);
        expect(session.current.usage.lastTurn!.turns, isNull);
      },
    );

    test('turns as a string: null, the snapshot is applied, one '
        'usage.decode_failed with field session.turns and no raw value; the '
        'second wrong snapshot does not repeat it', () async {
      final session = await connected();

      agent.usage(_snapshot(session: _aggregate(turns: '3')));
      agent.usage(_snapshot(session: _aggregate(turns: _leak), seq: 2));

      expect(session.current.usage.support, UsageSupport.reported);
      expect(session.current.usage.lastSeq, 2);
      expect(session.current.usage.session!.turns, isNull);
      expect(session.current.usage.session!.steps, 7);
      final warnings = agent.logger.where('usage.decode_failed').toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.level, 'warning');
      expect(warnings.single.context['field'], 'session.turns');
      expect(warnings.single.context['reason'], 'wrong_type');
      expect(warnings.single.context['session_id'], 's-1');
      expect(agent.logger.entries.toString(), isNot(contains(_leak)));
    });
  });
}
