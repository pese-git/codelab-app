// Разбор ответа `_codelab/session/usage/ledger` (задача 3.2 change
// `add-usage-ledger`; spec acp-client-kit «Журнал usage сессии в клиенте»:
// разбор ответа, «Журнал загружен»; design.md, D6, D10).
//
// Красные тесты: `UsageLedgerDecoder.decode` — заглушка (задача 3.9).
//
// Формы, которые задаёт этот тест (имена — исполнителю 3.9, design D10):
//   * `UsageLedgerDecoder().decode(result, onWarning: (field, reason) {...})`
//     — `UsageLedgerView?`, как `UsageDecoder.decode`: без исключений, `null`
//     — ответ отброшен;
//   * `UsageLedgerView`: `sessionId`, `seq`, `total` (`UsageTotals`),
//     `turnCount`, `status`, `reason`, `records`, `turns`, `models`,
//     `subagents`, `summaries`;
//   * `UsageLedgerTurn`: `index`, `title`, `running`, `total`, `steps`,
//     `subagents`; `UsageLedgerStep`: `index`, `model`, `tokens`, `cost`,
//     `partial`, `toolCallIds`.
// Для обязательных полей причина — `required`, для неверного формата денег
// и валюты — `wrong_format` (как у `UsageDecoder`). Ограничение «не чаще
// раза на сессию и поле» накладывает `ClientWorkspace`, оно проверяется в
// `session_usage_ledger_test.dart`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

/// Маркер утечки: сырые значения не должны попадать в предупреждения.
const _leak = 'sk-test-leak-0123456789';

Map<String, Object?> _tokens([int input = 100, int output = 10]) => {
  'input': input,
  'output': output,
  'cacheRead': 5,
  'cacheWrite': 0,
};

Map<String, Object?> _step(
  int index, {
  String model = 'anthropic/claude-sonnet-4',
  String cost = '0.02',
  List<String> toolCallIds = const ['call_1'],
}) => {
  'index': index,
  'model': model,
  'tokens': _tokens(),
  'cost': cost,
  'toolCallIds': toolCallIds,
};

/// Ответ D6 с двумя ходами; [overrides] заменяет ключи, `null` убирает.
Map<String, Object?> _result([Map<String, Object?> overrides = const {}]) {
  final result = <String, Object?>{
    'sessionId': 's-1',
    'seq': 12,
    'currency': 'USD',
    'ledger': {'status': 'rebuilt', 'reason': 'stale', 'records': 214},
    'total': {
      'turns': 2,
      'steps': 3,
      'tokens': {..._tokens(300, 30), 'reasoning': 7},
      'cost': '2.26',
      'partial': ['noUsage', 'future'],
    },
    'turns': [
      {
        'index': 1,
        'title': 'Render agent replies as markdown',
        'total': {'steps': 2, 'tokens': _tokens(200, 20), 'cost': '0.24'},
        'steps': [_step(0), _step(1, toolCallIds: const [])],
        'subagents': {'runs': 1, 'tokens': _tokens(), 'cost': '0.01'},
      },
      {
        'index': 2,
        'running': true,
        'total': {'steps': 1, 'tokens': _tokens()},
        'steps': [
          _step(0, cost: '0.000001', toolCallIds: const ['a', 'b']),
        ],
      },
    ],
    'models': [
      {
        'model': 'anthropic/claude-sonnet-4',
        'steps': 3,
        'tokens': _tokens(300, 30),
        'cost': '2.18',
        'partial': ['noUsage'],
      },
    ],
    'subagents': {'runs': 2, 'tokens': _tokens(), 'cost': '0.03'},
    'summaries': {'count': 1, 'tokens': _tokens(), 'cost': '0.01'},
    ...overrides,
  };
  result.removeWhere((_, value) => value == null);
  return result;
}

void main() {
  late List<(String field, String reason)> warnings;
  const decoder = UsageLedgerDecoder();

  UsageLedgerView? decode(Map<String, Object?> result) => decoder.decode(
    result,
    onWarning: (field, reason) => warnings.add((field, reason)),
  );

  setUp(() => warnings = []);

  group('the D6 shape', () {
    test('a full ledger is decoded: totals, turns, steps, models, groups', () {
      final view = decode(_result())!;

      expect(view.sessionId, const SessionId('s-1'));
      expect(view.seq, 12);
      expect(view.status, UsageLedgerStatus.rebuilt);
      expect(view.reason, 'stale');
      expect(view.records, 214);
      expect(view.turnCount, 2);
      expect(view.total.steps, 3);
      expect(view.total.tokens.input, 300);
      expect(view.total.tokens.reasoning, 7);
      expect(view.total.cost!.micros, 2260000);
      expect(view.total.cost!.currency, 'USD');
      // Незнакомая причина отброшена.
      expect(view.total.partial, {UsagePartial.noUsage});

      expect(view.turns, hasLength(2));
      final first = view.turns.first;
      expect(first.index, 1);
      expect(first.title, 'Render agent replies as markdown');
      expect(first.running, isFalse);
      expect(first.total.cost!.micros, 240000);
      expect(first.steps, hasLength(2));
      expect(first.steps.first.model, 'anthropic/claude-sonnet-4');
      expect(first.steps.first.cost!.micros, 20000);
      expect(first.subagents!.count, 1);
      expect(first.subagents!.cost!.micros, 10000);
      final second = view.turns.last;
      expect(second.index, 2);
      expect(second.title, isNull);
      expect(second.running, isTrue);
      expect(second.subagents, isNull);

      expect(view.models.single.model, 'anthropic/claude-sonnet-4');
      expect(view.models.single.steps, 3);
      expect(view.models.single.partial, {UsagePartial.noUsage});
      expect(view.subagents!.count, 2);
      expect(view.summaries!.count, 1);
      expect(view.summaries!.cost!.micros, 10000);
      expect(warnings, isEmpty);
    });

    test('toolCallIds are kept in order; an empty list stays empty', () {
      final view = decode(_result())!;

      expect(view.turns.first.steps.first.toolCallIds, ['call_1']);
      expect(view.turns.first.steps.last.toolCallIds, isEmpty);
      expect(view.turns.last.steps.single.toolCallIds, ['a', 'b']);
    });

    test('seq 0 (no snapshots yet) is a valid ledger', () {
      final view = decode(_result({'seq': 0}))!;

      expect(view.seq, 0);
      expect(warnings, isEmpty);
    });

    test('a minimal ledger: only the required fields', () {
      final view = decode({
        'sessionId': 's-1',
        'seq': 3,
        'total': {'tokens': _tokens()},
      })!;

      expect(view.turns, isEmpty);
      expect(view.models, isEmpty);
      expect(view.subagents, isNull);
      expect(view.summaries, isNull);
      expect(view.status, isNull);
      expect(view.total.cost, isNull);
      expect(warnings, isEmpty);
    });

    test('unknown fields and unknown ledger.status are accepted', () {
      final view = decode(
        _result({
          'future': {'x': 1},
          'ledger': {'status': 'somethingNew', 'records': 1},
        }),
      )!;

      expect(view.status, isNull);
      expect(view.records, 1);
      expect(warnings, isEmpty);
    });
  });

  group('money and currency share the UsageDecoder rules (D10)', () {
    test('cost strings become exact micros without double', () {
      final view = decode(
        _result({
          'total': {'tokens': _tokens(), 'cost': '999999999.999999'},
        }),
      )!;

      expect(view.total.cost!.micros, 999999999999999);
      expect(view.turns.last.steps.single.cost!.micros, 1);
    });

    test('a wrong cost string: no cost, one warning, tokens kept', () {
      final view = decode(
        _result({
          'total': {'tokens': _tokens(), 'cost': '1000000000'},
        }),
      )!;

      expect(view.total.cost, isNull);
      expect(view.total.tokens.input, 100);
      expect(warnings, [('total.cost', 'wrong_format')]);
    });

    for (final currency in ['usd', 'US\$', '\u001b[31m', _leak]) {
      test('currency ${currency.length > 10 ? 'long' : currency.codeUnits} is '
          'not ISO 4217: no costs anywhere, tokens kept, one warning '
          'without the value', () {
        final view = decode(_result({'currency': currency}))!;

        expect(view.total.cost, isNull);
        expect(view.turns.first.total.cost, isNull);
        expect(view.turns.first.steps.first.cost, isNull);
        expect(view.models.single.cost, isNull);
        expect(view.summaries!.cost, isNull);
        expect(view.total.tokens.input, 300);
        expect(warnings, [('currency', 'wrong_format')]);
        expect(warnings.map((w) => '$w'), everyElement(isNot(contains(_leak))));
      });
    }

    test('a cost without currency is absent, same as in UsageDecoder', () {
      final view = decode(_result({'currency': null}))!;

      expect(view.total.cost, isNull);
      expect(view.total.tokens.input, 300);
      expect(
        warnings.where((w) => w.$1 == 'currency'),
        hasLength(1),
        reason: 'одно предупреждение на поле, а не на каждую стоимость',
      );
    });

    test('currency EUR: micros and currency', () {
      final view = decode(_result({'currency': 'EUR'}))!;

      expect(view.total.cost!.currency, 'EUR');
      expect(view.models.single.cost!.currency, 'EUR');
    });

    test('the aggregate is decoded by the same code as UsageDecoder', () {
      // Тот же агрегат через оба декодера даёт равные значения: правило
      // денег, валюты и причин живёт в одном месте (D10).
      final aggregate = {
        'turns': 1,
        'steps': 2,
        'tokens': {..._tokens(), 'reasoning': 3},
        'cost': '0.0183',
        'partial': ['noPrice', 'future'],
      };
      final snapshot = const UsageDecoder().decode({
        'sessionId': 's-1',
        'seq': 1,
        'trigger': 'turn',
        'session': aggregate,
        'currency': 'USD',
      }, onWarning: (_, _) {})!;
      final view = decode({
        'sessionId': 's-1',
        'seq': 1,
        'currency': 'USD',
        'total': aggregate,
      })!;

      expect(view.total, snapshot.session);
    });
  });

  group('required fields', () {
    for (final (name, overrides, field)
        in <(String, Map<String, Object?>, String)>[
          ('sessionId', {'sessionId': null}, 'sessionId'),
          ('sessionId of a wrong type', {'sessionId': 5}, 'sessionId'),
          ('seq', {'seq': null}, 'seq'),
          ('seq of a wrong type', {'seq': '12'}, 'seq'),
          ('negative seq', {'seq': -1}, 'seq'),
          ('total', {'total': null}, 'total.tokens'),
          (
            'total.tokens',
            {
              'total': {'turns': 1},
            },
            'total.tokens',
          ),
          (
            'a token counter of a wrong type',
            {
              'total': {
                'tokens': {
                  'input': 'many',
                  'output': 1,
                  'cacheRead': 0,
                  'cacheWrite': 0,
                },
              },
            },
            'total.tokens',
          ),
        ]) {
      test('without $name the ledger is rejected as a whole', () {
        final view = decode(_result(overrides));

        expect(view, isNull);
        expect(warnings.map((w) => w.$1), contains(field));
        expect(warnings.map((w) => w.$2), contains('required'));
      });
    }

    test('a turn without index or total.tokens is skipped, others stay', () {
      final view = decode(
        _result({
          'turns': [
            {
              'title': 'no index',
              'total': {'steps': 1, 'tokens': _tokens()},
            },
            {
              'index': 2,
              'total': {'steps': 1},
            },
            {
              'index': 3,
              'total': {'steps': 1, 'tokens': _tokens()},
              'steps': [_step(0)],
            },
            'not a map',
          ],
        }),
      )!;

      expect(view.turns.map((t) => t.index), [3]);
      expect(warnings, isNotEmpty);
    });

    test('a step without index or tokens is skipped, others stay', () {
      final view = decode(
        _result({
          'turns': [
            {
              'index': 1,
              'total': {'steps': 3, 'tokens': _tokens()},
              'steps': [
                {'model': 'm', 'tokens': _tokens()},
                {'index': 1, 'model': 'm'},
                _step(2),
                42,
              ],
            },
          ],
        }),
      )!;

      expect(view.turns.single.steps.map((s) => s.index), [2]);
      expect(warnings, isNotEmpty);
    });
  });

  group('optional fields of a wrong type are simply absent', () {
    test('title, running, models, subagents and ledger of a wrong type', () {
      final view = decode(
        _result({
          'ledger': 'rebuilt',
          'models': 'many',
          'subagents': 7,
          'summaries': [1],
          'turns': [
            {
              'index': 1,
              'title': 5,
              'running': 'yes',
              'total': {'steps': 1, 'tokens': _tokens()},
              'steps': 'none',
            },
          ],
        }),
      )!;

      expect(view.status, isNull);
      expect(view.records, isNull);
      expect(view.models, isEmpty);
      expect(view.subagents, isNull);
      expect(view.summaries, isNull);
      expect(view.turns.single.title, isNull);
      expect(view.turns.single.running, isFalse);
      expect(view.turns.single.steps, isEmpty);
      expect(warnings, isNotEmpty);
    });

    test('a step model of a wrong type: the step is kept without model', () {
      final view = decode(
        _result({
          'turns': [
            {
              'index': 1,
              'total': {'steps': 1, 'tokens': _tokens()},
              'steps': [
                {'index': 0, 'model': 5, 'tokens': _tokens()},
              ],
            },
          ],
        }),
      )!;

      expect(view.turns.single.steps.single.model, isNull);
      expect(warnings, isNotEmpty);
    });

    test('a wrong cost of one step does not drop the step', () {
      final view = decode(
        _result({
          'turns': [
            {
              'index': 1,
              'total': {'steps': 1, 'tokens': _tokens()},
              'steps': [_step(0, cost: '1,5')],
            },
          ],
        }),
      )!;

      expect(view.turns.single.steps.single.cost, isNull);
      expect(view.turns.single.steps.single.tokens.input, 100);
      expect(warnings, hasLength(1));
      expect(warnings.single.$2, 'wrong_format');
    });

    test('warnings never carry the raw value', () {
      decode(
        _result({
          'ledger': _leak,
          'models': _leak,
          'subagents': _leak,
          'currency': _leak,
          'turns': [
            {
              'index': 1,
              'title': 5,
              'total': {'tokens': _tokens(), 'cost': _leak},
              'steps': [
                {'index': 0, 'tokens': _tokens(), 'cost': _leak},
              ],
            },
          ],
        }),
      );

      expect(warnings, isNotEmpty);
      expect(warnings.map((w) => '$w'), everyElement(isNot(contains(_leak))));
    });
  });

  group('tolerance', () {
    test('garbage of any shape never throws', () {
      for (final garbage in <Object?>[
        null,
        42,
        'text',
        true,
        <Object?>[],
        <String, Object?>{},
        {'turns': null},
        {'sessionId': 's-1', 'seq': 1, 'total': 'x'},
        {
          'sessionId': 's-1',
          'seq': 1,
          'total': {'tokens': []},
        },
        _result({
          'turns': [null, [], 3, {}],
        }),
        _result({
          'models': [
            null,
            {},
            {'model': 1},
          ],
        }),
      ]) {
        expect(
          () => decode(garbage is Map<String, Object?> ? garbage : {}),
          returnsNormally,
        );
      }
    });
  });
}
