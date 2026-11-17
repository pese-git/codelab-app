// Разбор `_codelab/session/usage` (задача 2.4 change `add-usage-extension`;
// spec acp-client-kit «Usage сессии»: «Неверный тип поля», «Причины
// неполноты», «Деньги без накопления ошибки», «Скорое сжатие»; design.md,
// D2, D6, D8, D9, D11).
//
// Красные тесты: `lib/src/usage/` ещё нет (задача 2.9) — файл не
// компилируется. Отсутствующие символы: `UsageDecoder`, `UsageSnapshot`,
// `UsageTrigger`, `UsageTotals`, `TokenCounts`, `Money`, `UsagePartial`,
// `ContextFillView`.
//
// Формы, которые задаёт этот тест (эскиз D8 даёт только модель отображения;
// имена уточняет исполнитель 2.9):
//   * `UsageDecoder().decode(params, onWarning: (field, reason) {...})` —
//     `UsageSnapshot?` без исключений; на каждое неразобранное поле
//     вызывается `onWarning` ровно один раз;
//   * `UsageSnapshot`: `sessionId` (`SessionId`), `seq`, `trigger`
//     (`UsageTrigger.step | turn | compaction | unknown`), `turnId`,
//     `turn` (`UsageTotals?`), `session` (`UsageTotals`), `context`
//     (`ContextFillView?`).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

/// Маркер утечки: разбор не должен переносить сырые значения в предупреждения.
const _leak = 'sk-test-leak-0123456789';

Map<String, Object?> _tokens([int input = 1200, int output = 310]) => {
  'input': input,
  'output': output,
  'cacheRead': 9800,
  'cacheWrite': 0,
};

/// Снимок D2 с точечными заменами: значение `null` убирает ключ.
Map<String, Object?> _params([Map<String, Object?> overrides = const {}]) {
  final params = <String, Object?>{
    'sessionId': 's-1',
    'seq': 4,
    'trigger': 'step',
    'turnId': 't-1',
    'step': {
      'index': 1,
      'model': 'anthropic/claude-sonnet-4',
      'tokens': _tokens(),
      'cost': '0.00954',
    },
    'turn': {
      'steps': 2,
      'tokens': {..._tokens(2400, 520), 'reasoning': 40},
      'cost': '0.0183',
    },
    'session': {
      'turns': 3,
      'steps': 7,
      'tokens': _tokens(9100, 2100),
      'cost': '0.0372',
      'partial': ['beforeLoad'],
    },
    'currency': 'USD',
    'context': {'used': 22900, 'size': 200000, 'compactAt': 183616},
    ...overrides,
  };
  params.removeWhere((_, value) => value == null);
  return params;
}

/// Параметры, где `session.cost` заменён строкой [cost].
Map<String, Object?> _withSessionCost(Object? cost) => _params({
  'session': {'turns': 1, 'steps': 1, 'tokens': _tokens(), 'cost': cost},
});

void main() {
  late List<(String field, String reason)> warnings;
  late UsageDecoder decoder;

  UsageSnapshot? decode(Map<String, Object?> params) => decoder.decode(
    params,
    onWarning: (field, reason) => warnings.add((field, reason)),
  );

  setUp(() {
    warnings = [];
    decoder = UsageDecoder();
  });

  group('the D2 shape', () {
    test('a full step snapshot is decoded', () {
      final snapshot = decode(_params())!;

      expect(snapshot.sessionId, const SessionId('s-1'));
      expect(snapshot.seq, 4);
      expect(snapshot.trigger, UsageTrigger.step);
      expect(snapshot.turnId, 't-1');
      expect(snapshot.turn!.steps, 2);
      expect(snapshot.turn!.tokens.input, 2400);
      expect(snapshot.turn!.tokens.output, 520);
      expect(snapshot.turn!.tokens.cacheRead, 9800);
      expect(snapshot.turn!.tokens.reasoning, 40);
      expect(snapshot.turn!.cost!.micros, 18300);
      expect(snapshot.turn!.cost!.currency, 'USD');
      expect(snapshot.session.steps, 7);
      expect(snapshot.session.tokens.input, 9100);
      expect(snapshot.session.tokens.reasoning, isNull);
      expect(snapshot.session.cost!.micros, 37200);
      expect(snapshot.session.partial, {UsagePartial.beforeLoad});
      expect(snapshot.context!.used, 22900);
      expect(snapshot.context!.size, 200000);
      expect(snapshot.context!.compactAt, 183616);
      expect(warnings, isEmpty);
    });

    test('a compaction snapshot has no turn and no turnId', () {
      final snapshot = decode(
        _params({
          'trigger': 'compaction',
          'turnId': null,
          'turn': null,
          'step': null,
        }),
      )!;

      expect(snapshot.trigger, UsageTrigger.compaction);
      expect(snapshot.turnId, isNull);
      expect(snapshot.turn, isNull);
      expect(warnings, isEmpty);
    });

    test('unknown fields and an unknown trigger are accepted', () {
      final snapshot = decode(
        _params({
          'trigger': 'future',
          'limits': {'maxTokens': 1000},
          'session': {
            'turns': 1,
            'steps': 1,
            'tokens': {..._tokens(), 'thoughts': 3},
            'extra': 1,
          },
        }),
      )!;

      expect(snapshot.trigger, UsageTrigger.unknown);
      expect(snapshot.session.tokens.input, 1200);
      expect(warnings, isEmpty);
    });

    test('a missing context and a missing currency without costs are fine', () {
      final snapshot = decode(
        _params({
          'context': null,
          'currency': null,
          'turn': {'steps': 1, 'tokens': _tokens()},
          'session': {'turns': 1, 'steps': 1, 'tokens': _tokens()},
        }),
      )!;

      expect(snapshot.context, isNull);
      expect(snapshot.session.cost, isNull);
      expect(snapshot.turn!.cost, isNull);
      expect(warnings, isEmpty);
    });
  });

  group('partial reasons', () {
    test('unknown reasons are dropped, known are kept', () {
      final snapshot = decode(
        _params({
          'session': {
            'turns': 1,
            'steps': 1,
            'tokens': _tokens(),
            'partial': ['beforeLoad', 'future'],
          },
        }),
      )!;

      expect(snapshot.session.partial, {UsagePartial.beforeLoad});
      expect(warnings, isEmpty);
    });

    test('all three known reasons are recognised', () {
      final snapshot = decode(
        _params({
          'session': {
            'turns': 1,
            'steps': 1,
            'tokens': _tokens(),
            'partial': ['noUsage', 'noPrice', 'beforeLoad'],
          },
        }),
      )!;

      expect(snapshot.session.partial, {
        UsagePartial.noUsage,
        UsagePartial.noPrice,
        UsagePartial.beforeLoad,
      });
    });

    test('no partial means an empty set', () {
      expect(decode(_params())!.turn!.partial, isEmpty);
    });
  });

  group('wrong type of an optional field', () {
    test('context with a string used: the field is absent, one warning', () {
      final snapshot = decode(
        _params({
          'context': {'used': 'many', 'size': 200000},
        }),
      )!;

      expect(snapshot.context, isNull);
      expect(snapshot.session.tokens.input, 9100);
      expect(warnings, hasLength(1));
      expect(warnings.single.$1, 'context');
    });

    test('turn that is not an object: the field is absent, one warning', () {
      final snapshot = decode(_params({'turn': 'oops'}))!;

      expect(snapshot.turn, isNull);
      expect(warnings, hasLength(1));
      expect(warnings.single.$1, 'turn');
    });

    test('turnId that is not a string: the field is absent, one warning', () {
      final snapshot = decode(_params({'turnId': 7}))!;

      expect(snapshot.turnId, isNull);
      expect(warnings, hasLength(1));
    });

    test('a warning never carries the raw value', () {
      decode(
        _params({
          'context': {'used': _leak, 'size': 200000},
        }),
      );

      expect(warnings, hasLength(1));
      expect('${warnings.single}', isNot(contains(_leak)));
    });
  });

  group('wrong required fields drop the whole snapshot', () {
    final cases = <String, Map<String, Object?>>{
      'sessionId missing': _params({'sessionId': null}),
      'sessionId not a string': _params({'sessionId': 5}),
      'seq missing': _params({'seq': null}),
      'seq a string': _params({'seq': '4'}),
      'seq zero': _params({'seq': 0}),
      'seq a double': _params({'seq': 4.5}),
      'trigger missing': _params({'trigger': null}),
      'trigger not a string': _params({'trigger': 1}),
      'session missing': _params({'session': null}),
      'session.tokens missing': _params({
        'session': {'turns': 1, 'steps': 1},
      }),
      'session.tokens.input a string': _params({
        'session': {
          'turns': 1,
          'steps': 1,
          'tokens': {
            'input': 'x',
            'output': 1,
            'cacheRead': 0,
            'cacheWrite': 0,
          },
        },
      }),
      'session.tokens.output missing': _params({
        'session': {
          'turns': 1,
          'steps': 1,
          'tokens': {'input': 1, 'cacheRead': 0, 'cacheWrite': 0},
        },
      }),
    };
    for (final MapEntry(key: name, value: params) in cases.entries) {
      test('$name: null and one warning, no exception', () {
        expect(decode(params), isNull);
        expect(warnings, hasLength(1));
      });
    }
  });

  group('money', () {
    final valid = <String, int>{'0': 0, '0.000001': 1, '12.5': 12500000};
    for (final MapEntry(key: text, value: micros) in valid.entries) {
      test('"$text" is $micros micros', () {
        final cost = decode(_withSessionCost(text))!.session.cost!;

        expect(cost.micros, micros);
        expect(cost.currency, 'USD');
        expect(warnings, isEmpty);
      });
    }

    for (final text in ['1e-3', '-1', '0.0000001', '', ' 1', '1.', '.5']) {
      test('"$text" gives no cost without an error', () {
        final snapshot = decode(_withSessionCost(text));

        expect(snapshot, isNotNull);
        expect(snapshot!.session.cost, isNull);
        expect(snapshot.session.tokens.input, 1200);
      });
    }

    test('a numeric cost (not a string) gives no cost', () {
      expect(decode(_withSessionCost(0.5))!.session.cost, isNull);
    });

    // Валюта — ISO 4217: `^[A-Z]{3}$`. Поле необязательное (снимок не
    // отбрасывается), как и при отсутствии валюты: стоимость пропадает,
    // токены остаются, причина — `wrong_format` без сырого значения.
    for (final bad in ['', 'usd', 'US', 'USDX', 'U\x1b[31m', ' USD', 'ЮСД']) {
      test('currency "${bad.runes.length} chars" not matching [A-Z]{3} '
          'gives no cost and a wrong_format warning', () {
        final snapshot = decode(_params({'currency': bad}))!;

        expect(snapshot.session.cost, isNull);
        expect(snapshot.turn!.cost, isNull);
        expect(snapshot.session.tokens.input, 9100);
        expect(warnings, [('currency', 'wrong_format')]);
      });
    }

    test('currency EUR is accepted with the cost in EUR', () {
      final snapshot = decode(
        _params({
          'currency': 'EUR',
          'session': {
            'turns': 1,
            'steps': 1,
            'tokens': _tokens(),
            'cost': '1.2',
          },
        }),
      )!;

      expect(
        snapshot.session.cost,
        const Money(micros: 1200000, currency: 'EUR'),
      );
      expect(warnings, isEmpty);
    });

    test('cost without currency gives no cost', () {
      final snapshot = decode(_params({'currency': null}))!;

      expect(snapshot.session.cost, isNull);
      expect(snapshot.turn!.cost, isNull);
      expect(snapshot.session.tokens.input, 9100);
    });
  });

  group('context fill', () {
    ContextFillView? context(Map<String, Object?> value) =>
        decode(_params({'context': value}))!.context;

    test('fraction is used / size', () {
      expect(context({'used': 50000, 'size': 200000})!.fraction, 0.25);
    });

    test('fraction is null without size and at size 0', () {
      expect(context({'used': 5})!.fraction, isNull);
      expect(context({'used': 5, 'size': 0})!.fraction, isNull);
    });

    test(
      'compactionSoon: used >= 0.9 * compactAt (scenario «Скорое сжатие»)',
      () {
        expect(
          context({
            'used': 168000,
            'size': 200000,
            'compactAt': 183616,
          })!.compactionSoon,
          isTrue,
        );
        // Без `compactAt` (автосжатие выключено) подписи нет (Q3 (б)).
        expect(
          context({'used': 168000, 'size': 200000})!.compactionSoon,
          isFalse,
        );
        // Ниже порога 0.9 * compactAt = 165254.4.
        expect(
          context({
            'used': 165000,
            'size': 200000,
            'compactAt': 183616,
          })!.compactionSoon,
          isFalse,
        );
      },
    );
  });
}
