// Бюджет хода в usage сессии (задача 3.1 change `add-desktop-usage-pane`;
// spec acp-client-kit «Бюджет хода в usage сессии»: «Бюджет из снимка шага»,
// «Итог хода», «Цена неизвестна», «Тот же ход без бюджета», «Новый ход без
// лимитов», «Снимки без хода», «Неверное подполе», «Бюджет не объект»,
// «Сброс при переподключении и загрузке»; design.md, D7, D9, решение
// Q11 (а); `12-1-view-model.md` §12.1.5 п. 3b).
//
// Покрывает разбор `budget` в `UsageDecoder` и свёртку в `UsageFold`
// (D9) и параметр `UsageFold.apply(receivedAt:)`.
//
// Формы, которые фиксирует этот тест (D9):
//   * `UsageSnapshot.budget` — `UsageBudget?` (подполя провода без `turnId`,
//     момента и `ended`);
//   * `UsageView.budget` — `TurnBudgetView?`: `turnId`, `receivedAt`, `ended`
//     и подполя `steps`/`tokens` (`BudgetCount`), `cost` (`BudgetCost`),
//     `duration` (`BudgetDuration`).
//
// Гонки и порядок — принудительным порядком кадров на `FakeAcpTransport`
// через `UsageAgent`, без таймеров; время — внедрённые часы.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/usage_agent.dart';

// --- Провод -----------------------------------------------------------------

Map<String, Object?> _tokens([int input = 1200, int output = 310]) => {
  'input': input,
  'output': output,
  'cacheRead': 0,
  'cacheWrite': 0,
};

/// Снимок D2 с `budget`; значение `null` у ключа убирает его.
Map<String, Object?> _params({
  int seq = 1,
  String trigger = 'step',
  String? turnId = 't-1',
  Object? budget,
  Object? currency = 'USD',
}) {
  final params = <String, Object?>{
    'sessionId': 's-1',
    'seq': seq,
    'trigger': trigger,
    'turnId': turnId,
    if (turnId != null)
      'turn': {'steps': 1, 'tokens': _tokens(), 'cost': '0.001'},
    'session': {'turns': 1, 'steps': 1, 'tokens': _tokens(), 'cost': '0.001'},
    'currency': currency,
    'budget': budget,
  };
  params.removeWhere((_, value) => value == null);
  return params;
}

/// Бюджет D7 со всеми подполями.
Map<String, Object?> _fullBudget() => {
  'steps': {'used': 3, 'limit': 50},
  'tokens': {'used': 92000, 'limit': 200000},
  'cost': {'used': '0.41', 'limit': '0.5'},
  'duration': {'usedMs': 180000, 'limitMs': 600000},
};

/// Предупреждения разбора как пары `(field, reason)`.
typedef _Warned = List<(String, String)>;

UsageSnapshot? _decode(Map<String, Object?> params, [_Warned? warned]) =>
    const UsageDecoder().decode(
      params,
      onWarning: (field, reason) => warned?.add((field, reason)),
    );

// --- Свёртка ----------------------------------------------------------------

const _noTotals = UsageTotals(
  tokens: TokenCounts(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
);

UsageSnapshot _snap(
  int seq, {
  UsageTrigger trigger = UsageTrigger.step,
  String? turnId,
  UsageBudget? budget,
}) => UsageSnapshot(
  sessionId: const SessionId('s-1'),
  seq: seq,
  trigger: trigger,
  turnId: turnId,
  session: _noTotals,
  budget: budget,
);

const _budgetA = UsageBudget(
  tokens: BudgetCount(used: 100, limit: 1000),
  steps: BudgetCount(used: 1, limit: 50),
);
const _budgetA2 = UsageBudget(
  tokens: BudgetCount(used: 300, limit: 1000),
  steps: BudgetCount(used: 2, limit: 50),
);

final _t1 = DateTime.utc(2026, 11, 18, 10);
final _t2 = DateTime.utc(2026, 11, 18, 10, 0, 5);
final _t3 = DateTime.utc(2026, 11, 18, 10, 0, 9);

UsageFold _apply(
  UsageFold fold,
  UsageSnapshot snapshot, {
  int generation = 1,
  DateTime? at,
}) => fold.apply(snapshot, generation: generation, receivedAt: at ?? _t1)!;

void main() {
  group('UsageDecoder: budget (D9, «Разбор»)', () {
    test('all subfields: counts, money by micros, duration; no warnings '
        '(сценарий «Бюджет из снимка шага»)', () {
      final warned = <(String, String)>[];

      final budget = _decode(_params(budget: _fullBudget()), warned)!.budget;

      expect(budget, isNotNull);
      expect(budget!.steps, const BudgetCount(used: 3, limit: 50));
      expect(budget.tokens, const BudgetCount(used: 92000, limit: 200000));
      expect(
        budget.cost,
        const BudgetCost(
          used: Money(micros: 410000, currency: 'USD'),
          limit: Money(micros: 500000, currency: 'USD'),
        ),
      );
      expect(
        budget.duration,
        const BudgetDuration(usedMs: 180000, limitMs: 600000),
      );
      expect(warned, isEmpty);
    });

    test('only the given limits: the others are null', () {
      final budget = _decode(
        _params(
          budget: {
            'steps': {'used': 1, 'limit': 50},
            'tokens': {'used': 10, 'limit': 100},
          },
        ),
      )!.budget!;

      expect(budget.steps, const BudgetCount(used: 1, limit: 50));
      expect(budget.tokens, const BudgetCount(used: 10, limit: 100));
      expect(budget.cost, isNull);
      expect(budget.duration, isNull);
    });

    test('a snapshot without budget: budget is null, no warnings', () {
      final warned = <(String, String)>[];

      expect(_decode(_params(), warned)!.budget, isNull);
      expect(warned, isEmpty);
    });

    test('cost without used: price unknown, no warnings '
        '(сценарий «Цена неизвестна»)', () {
      final warned = <(String, String)>[];

      final cost = _decode(
        _params(
          budget: {
            'cost': {'limit': '0.5'},
          },
        ),
        warned,
      )!.budget!.cost;

      expect(cost!.used, isNull);
      expect(cost.limit, const Money(micros: 500000, currency: 'USD'));
      expect(warned, isEmpty);
    });

    test('cost money uses the cost rule: micros without double, zero used '
        'is a price', () {
      final cost = _decode(
        _params(
          budget: {
            'cost': {'used': '0', 'limit': '0.000001'},
          },
        ),
      )!.budget!.cost!;

      expect(cost.used, const Money(micros: 0, currency: 'USD'));
      expect(cost.limit, const Money(micros: 1, currency: 'USD'));
    });

    test('budget.cost without currency is dropped with the shared currency '
        'warning (once); the other subfields stay', () {
      final warned = <(String, String)>[];

      final budget = _decode(
        _params(
          currency: null,
          budget: {
            'tokens': {'used': 10, 'limit': 100},
            'cost': {'used': '0.1', 'limit': '0.5'},
          },
        ),
        warned,
      )!.budget!;

      expect(budget.cost, isNull);
      expect(budget.tokens, const BudgetCount(used: 10, limit: 100));
      // Одно предупреждение на снимок: тот же `currency`, что у агрегатов
      // (у снимка здесь `turn.cost` и `session.cost` тоже без валюты).
      expect(
        warned.where((w) => w == ('currency', 'required_with_cost')),
        hasLength(1),
      );
      expect(warned.where((w) => w.$1.startsWith('budget')), isEmpty);
    });

    test('budget.cost without currency: the cost limit alone is dropped '
        'too (limit is money)', () {
      final budget = _decode(
        _params(
          currency: null,
          budget: {
            'steps': {'used': 1, 'limit': 50},
            'cost': {'limit': '0.5'},
          },
        ),
      )!.budget!;

      expect(budget.cost, isNull);
      expect(budget.steps, isNotNull);
    });

    for (final (name, subfield, value) in <(String, String, Object?)>[
      ('steps: used is a string', 'steps', {'used': 'many', 'limit': 50}),
      ('tokens: limit is negative', 'tokens', {'used': 1, 'limit': -1}),
      ('tokens: used is a double', 'tokens', {'used': 1.5, 'limit': 10}),
      ('tokens: limit is missing', 'tokens', {'used': 1}),
      ('steps is not an object', 'steps', 5),
      (
        'duration: usedMs is a string',
        'duration',
        {'usedMs': '1', 'limitMs': 10},
      ),
      ('duration: limitMs is missing', 'duration', {'usedMs': 1}),
      ('cost: used is a number', 'cost', {'used': 0.41, 'limit': '0.5'}),
      (
        'cost: used with 7 fraction digits',
        'cost',
        {'used': '0.1234567', 'limit': '0.5'},
      ),
      ('cost: limit is missing', 'cost', {'used': '0.1'}),
      ('cost: limit is not money', 'cost', {'used': '0.1', 'limit': 'abc'}),
    ]) {
      test('wrong subfield ($name): the subfield is dropped, the others '
          'stay, one warning budget.$subfield (сценарий «Неверное '
          'подполе»)', () {
        final warned = <(String, String)>[];
        final good = <String, Object?>{
          'steps': {'used': 1, 'limit': 50},
          'tokens': {'used': 10, 'limit': 100},
          'cost': {'used': '0.1', 'limit': '0.5'},
          'duration': {'usedMs': 1, 'limitMs': 10},
        };
        final budget = _decode(
          _params(budget: {...good, subfield: value}),
          warned,
        )!.budget!;

        expect(switch (subfield) {
          'steps' => budget.steps,
          'tokens' => budget.tokens,
          'cost' => budget.cost,
          _ => budget.duration,
        }, isNull);
        // Остальные три подполя разобраны.
        expect(
          [
            budget.steps,
            budget.tokens,
            budget.cost,
            budget.duration,
          ].where((part) => part != null),
          hasLength(3),
        );
        expect(warned, hasLength(1));
        expect(warned.single.$1, 'budget.$subfield');
        expect(warned.single.$2, isIn(['wrong_type', 'wrong_format']));
      });
    }

    test('cost limit of 10^9 and above is dropped as wrong_format '
        '(9 digits of the whole part, D22 of add-usage-extension)', () {
      final warned = <(String, String)>[];

      final budget = _decode(
        _params(
          budget: {
            'tokens': {'used': 1, 'limit': 10},
            'cost': {'used': '1', 'limit': '1000000000'},
          },
        ),
        warned,
      )!.budget!;

      expect(budget.cost, isNull);
      expect(budget.tokens, isNotNull);
      expect(warned, [('budget.cost', 'wrong_format')]);
    });

    test('the largest allowed limit (999999999.999999) is kept', () {
      final budget = _decode(
        _params(
          budget: {
            'cost': {'limit': '999999999.999999'},
          },
        ),
      )!.budget!;

      expect(
        budget.cost!.limit,
        const Money(micros: 999999999999999, currency: 'USD'),
      );
    });

    test('a snapshot without turnId (compaction, compactionDiscarded, load) '
        'ignores budget: not parsed, no warnings even for a broken one', () {
      // D7: `budget` бывает только у снимков с ходом. Свёртка такой бюджет
      // всё равно отбросила бы, но разбор лишнего поля дал бы ложные записи
      // `usage.decode_failed` у снимков уровня сессии.
      for (final trigger in ['compaction', 'compactionDiscarded', 'load']) {
        for (final budget in <Object>[_fullBudget(), 'broken']) {
          final warned = <(String, String)>[];

          final snapshot = _decode(
            _params(trigger: trigger, turnId: null, budget: budget),
            warned,
          );

          expect(snapshot, isNotNull, reason: '$trigger $budget');
          expect(snapshot!.budget, isNull, reason: '$trigger $budget');
          expect(warned, isEmpty, reason: '$trigger $budget');
        }
      }
    });

    test('budget is not an object: no budget, one warning field budget, the '
        'snapshot is applied (сценарий «Бюджет не объект»)', () {
      for (final bad in <Object>['full', 5, true, <Object?>[]]) {
        final warned = <(String, String)>[];

        final snapshot = _decode(_params(budget: bad), warned);

        expect(snapshot, isNotNull, reason: '$bad');
        expect(snapshot!.budget, isNull, reason: '$bad');
        expect(warned, hasLength(1), reason: '$bad');
        expect(warned.single.$1, 'budget');
        expect(warned.single.$2, 'wrong_type');
      }
    });

    test('unknown keys inside budget and subfields are ignored silently '
        '(future deadline of add-session-deadline)', () {
      final warned = <(String, String)>[];

      final budget = _decode(
        _params(
          budget: {
            'tokens': {'used': 10, 'limit': 100, 'extra': 'x'},
            'deadline': {'atMs': 1},
            'cost': {'used': '0.1', 'limit': '0.5', 'note': 1},
          },
        ),
        warned,
      )!.budget!;

      expect(budget.tokens, const BudgetCount(used: 10, limit: 100));
      expect(budget.cost!.limit.micros, 500000);
      expect(warned, isEmpty);
    });

    test('budget without known subfields is absent: empty object, only '
        'unknown keys (no warnings)', () {
      for (final empty in <Map<String, Object?>>[
        const {},
        {
          'deadline': {'atMs': 1},
        },
      ]) {
        final warned = <(String, String)>[];

        expect(_decode(_params(budget: empty), warned)!.budget, isNull);
        expect(warned, isEmpty);
      }
    });

    test('budget with all subfields wrong is absent; only the subfield '
        'warnings are written, no extra one for budget', () {
      final warned = <(String, String)>[];

      final snapshot = _decode(
        _params(
          budget: {
            'steps': {'used': 'x', 'limit': 1},
            'tokens': 7,
          },
        ),
        warned,
      );

      expect(snapshot!.budget, isNull);
      expect(warned.map((w) => w.$1), ['budget.steps', 'budget.tokens']);
    });

    test('warnings carry no raw values (no leak of agent data)', () {
      const leak = 'sk-test-leak-0123456789';
      final warned = <(String, String)>[];

      _decode(
        _params(
          budget: {
            'tokens': {'used': leak, 'limit': 1},
            'cost': {'used': leak, 'limit': '0.5'},
          },
        ),
        warned,
      );

      expect(
        warned.any((w) => w.$1.contains(leak) || w.$2.contains(leak)),
        isFalse,
      );
    });
  });

  group('UsageFold: budget (D9, «Свёртка»)', () {
    test('a step snapshot with budget replaces it: turnId, receivedAt from '
        'the argument, ended is false', () {
      final fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
        at: _t1,
      );

      final budget = fold.view.budget!;
      expect(budget.turnId, 'A');
      expect(budget.receivedAt, _t1);
      expect(budget.ended, isFalse);
      expect(budget.tokens, const BudgetCount(used: 100, limit: 1000));
      expect(budget.steps, const BudgetCount(used: 1, limit: 50));
      expect(budget.cost, isNull);
      expect(budget.duration, isNull);
    });

    test('the next snapshot of the same turn replaces numbers and '
        'receivedAt', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
        at: _t1,
      );
      fold = _apply(
        fold,
        _snap(2, turnId: 'A', budget: _budgetA2),
        at: _t2,
      );

      expect(fold.view.budget!.tokens!.used, 300);
      expect(fold.view.budget!.receivedAt, _t2);
    });

    test('a subfield absent in the newer snapshot of the same turn is '
        'absent in the result: the budget is replaced, not merged', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
      );
      fold = _apply(
        fold,
        _snap(
          2,
          turnId: 'A',
          budget: const UsageBudget(steps: BudgetCount(used: 2, limit: 50)),
        ),
      );

      expect(fold.view.budget!.tokens, isNull);
      expect(fold.view.budget!.steps!.used, 2);
    });

    test('ended: false for step, true for turn (Q11 (а), сценарий «Итог '
        'хода»); the next step of turn B makes it false again', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
      );
      expect(fold.view.budget!.ended, isFalse);

      fold = _apply(
        fold,
        _snap(2, trigger: UsageTrigger.turn, turnId: 'A', budget: _budgetA2),
        at: _t2,
      );
      expect(fold.view.budget!.ended, isTrue);
      expect(fold.view.budget!.tokens!.used, 300);
      expect(fold.view.budget!.receivedAt, _t2);

      fold = _apply(fold, _snap(3, turnId: 'B', budget: _budgetA));
      expect(fold.view.budget!.turnId, 'B');
      expect(fold.view.budget!.ended, isFalse);
    });

    test('ended is sticky for the same turnId: a late step with budget after '
        'the turn snapshot keeps ended true (нарушение агентом, D9)', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
      );
      fold = _apply(
        fold,
        _snap(2, trigger: UsageTrigger.turn, turnId: 'A', budget: _budgetA2),
      );
      fold = _apply(fold, _snap(3, turnId: 'A', budget: _budgetA));

      expect(fold.view.budget!.turnId, 'A');
      expect(fold.view.budget!.ended, isTrue);
    });

    test('a turn snapshot of the same turn without budget sets ended and '
        'keeps numbers (the exception of D9); receivedAt stays', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
        at: _t1,
      );
      final before = fold.view.budget!;

      fold = _apply(
        fold,
        _snap(2, trigger: UsageTrigger.turn, turnId: 'A'),
        at: _t3,
      );

      final budget = fold.view.budget!;
      expect(budget.ended, isTrue);
      expect(budget.tokens, before.tokens);
      expect(budget.steps, before.steps);
      expect(budget.turnId, 'A');
      expect(budget.receivedAt, _t1);
    });

    test('a turn snapshot of a new turn without budget gives null (not '
        'ended of the old one)', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
      );

      fold = _apply(fold, _snap(2, trigger: UsageTrigger.turn, turnId: 'B'));

      expect(fold.view.budget, isNull);
    });

    test('a step snapshot of the same turn without budget keeps budget and '
        'receivedAt (сценарий «Тот же ход без бюджета»)', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
        at: _t1,
      );
      final before = fold.view.budget;

      fold = _apply(fold, _snap(2, turnId: 'A'), at: _t3);

      expect(fold.view.budget, before);
      expect(fold.view.budget!.receivedAt, _t1);
      expect(fold.view.lastSeq, 2);
    });

    test('a step snapshot of a new turn without budget: null '
        '(сценарий «Новый ход без лимитов»)', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, turnId: 'A', budget: _budgetA),
      );

      fold = _apply(fold, _snap(2, turnId: 'B'));

      expect(fold.view.budget, isNull);
    });

    test('a snapshot without turnId keeps budget: compaction, '
        'compactionDiscarded (decoded as unknown), load, unknown trigger '
        '(сценарий «Снимки без хода»)', () {
      for (final trigger in [
        UsageTrigger.compaction,
        UsageTrigger.unknown,
        UsageTrigger.load,
      ]) {
        var fold = _apply(
          UsageFold.initial(declared: true),
          _snap(1, trigger: UsageTrigger.turn, turnId: 'A', budget: _budgetA),
          at: _t1,
        );
        final before = fold.view.budget;
        expect(before, isNotNull);

        fold = _apply(fold, _snap(2, trigger: trigger), at: _t3);

        expect(fold.view.budget, before, reason: '$trigger');
        expect(fold.view.lastSeq, 2, reason: '$trigger');
      }
    });

    test('a snapshot without turnId does not take budget from itself '
        '(defensive: budget outside step/turn is not applied)', () {
      final fold = _apply(
        UsageFold.initial(declared: true),
        _snap(1, trigger: UsageTrigger.compaction, budget: _budgetA),
      );

      expect(fold.view.budget, isNull);
    });

    test('a duplicate and a late seq change nothing, receivedAt too', () {
      final fold = _apply(
        UsageFold.initial(declared: true),
        _snap(2, turnId: 'A', budget: _budgetA),
        at: _t1,
      );

      expect(
        fold.apply(
          _snap(2, turnId: 'A', budget: _budgetA2),
          generation: 1,
          receivedAt: _t3,
        ),
        isNull,
      );
      expect(
        fold.apply(
          _snap(1, turnId: 'B', budget: _budgetA2),
          generation: 1,
          receivedAt: _t3,
        ),
        isNull,
      );
      expect(fold.view.budget!.tokens!.used, 100);
      expect(fold.view.budget!.receivedAt, _t1);
    });

    test('a snapshot of an older generation is dropped; a newer generation '
        'with seq 1 applies', () {
      var fold = _apply(
        UsageFold.initial(declared: true),
        _snap(5, turnId: 'A', budget: _budgetA),
        generation: 2,
      );

      expect(
        fold.apply(
          _snap(9, turnId: 'A', budget: _budgetA2),
          generation: 1,
          receivedAt: _t3,
        ),
        isNull,
      );

      fold = _apply(
        fold,
        _snap(1, turnId: 'C', budget: _budgetA2),
        generation: 3,
        at: _t2,
      );
      expect(fold.view.budget!.turnId, 'C');
      expect(fold.view.budget!.receivedAt, _t2);
    });

    test('the initial fold has no budget', () {
      expect(UsageFold.initial(declared: true).view.budget, isNull);
      expect(UsageFold.initial(declared: false).view.budget, isNull);
    });
  });

  group('ClientWorkspace: budget (D9, «Часы»)', () {
    late UsageAgent agent;
    var now = DateTime.utc(2026, 11, 18, 10);

    setUp(() => now = DateTime.utc(2026, 11, 18, 10));
    tearDown(() => agent.dispose());

    Future<SessionHandle> connected([
      AgentCapabilities capabilities = usageLoadCapabilities,
    ]) async {
      agent = UsageAgent(capabilities: capabilities, clock: () => now);
      await agent.start();
      return agent.newSession('s-1');
    }

    Map<String, Object?> wire({
      int seq = 1,
      String trigger = 'step',
      String? turnId = 't-1',
      Object? budget,
    }) => {
      ...usageParams(
        sessionId: 's-1',
        seq: seq,
        trigger: trigger,
        turnId: turnId,
      ),
      'budget': ?budget,
    };

    test('receivedAt is the moment of applying by the workspace clock '
        '(сценарий «Бюджет из снимка шага»)', () async {
      final session = await connected();

      now = DateTime.utc(2026, 11, 18, 10, 0, 3);
      agent.usage(wire(budget: _fullBudget()));

      final budget = session.current.usage.budget!;
      expect(budget.receivedAt, DateTime.utc(2026, 11, 18, 10, 0, 3));
      expect(budget.turnId, 't-1');
      expect(budget.ended, isFalse);
      expect(budget.tokens, const BudgetCount(used: 92000, limit: 200000));
      expect(budget.cost!.used!.micros, 410000);
      expect(budget.cost!.limit.micros, 500000);
      expect(session.current.usage.budget!.steps!.limit, 50);
    });

    test('step then turn of the same turn: ended becomes true, receivedAt '
        'is the time of the turn snapshot', () async {
      final session = await connected();

      agent.usage(wire(budget: _fullBudget()));
      now = DateTime.utc(2026, 11, 18, 10, 0, 7);
      agent.usage(wire(seq: 2, trigger: 'turn', budget: _fullBudget()));

      final budget = session.current.usage.budget!;
      expect(budget.ended, isTrue);
      expect(budget.receivedAt, DateTime.utc(2026, 11, 18, 10, 0, 7));
    });

    test('a duplicate and a late snapshot do not change budget, receivedAt '
        'or the revision (сценарий «Дубль и опоздание»)', () async {
      final session = await connected();
      agent.usage(wire(seq: 2, budget: _fullBudget()));
      final revision = session.current.revision;
      final budget = session.current.usage.budget;
      expect(budget, isNotNull);

      now = DateTime.utc(2026, 11, 18, 11);
      agent.usage(
        wire(
          seq: 2,
          budget: {
            'steps': {'used': 9, 'limit': 50},
          },
        ),
      );
      agent.usage(
        wire(
          budget: {
            'steps': {'used': 9, 'limit': 50},
          },
        ),
      );

      expect(session.current.revision, revision);
      expect(session.current.usage.budget, budget);
    });

    test('a compaction and a compactionDiscarded snapshot keep budget '
        '(сценарий «Снимки без хода»)', () async {
      final session = await connected();
      agent.usage(wire(trigger: 'turn', budget: _fullBudget()));
      final budget = session.current.usage.budget;
      expect(budget, isNotNull);

      agent.usage(wire(seq: 2, trigger: 'compaction', turnId: null));
      agent.usage(wire(seq: 3, trigger: 'compactionDiscarded', turnId: null));

      expect(session.current.usage.lastSeq, 3);
      expect(session.current.usage.budget, budget);
    });

    test('a new turn without budget clears it', () async {
      final session = await connected();
      agent.usage(wire(budget: _fullBudget()));

      agent.usage(wire(seq: 2, turnId: 't-2'));

      expect(session.current.usage.budget, isNull);
    });

    test('a wrong subfield: one usage.decode_failed per session and field, '
        'the snapshot is applied (сценарий «Неверное подполе»)', () async {
      final session = await connected();

      agent.usage(
        wire(
          budget: {
            'steps': {'used': 1, 'limit': 50},
            'tokens': {'used': 'many', 'limit': 200000},
          },
        ),
      );
      agent.usage(
        wire(
          seq: 2,
          budget: {
            'steps': {'used': 2, 'limit': 50},
            'tokens': {'used': 'many', 'limit': 200000},
          },
        ),
      );

      final usage = session.current.usage;
      expect(usage.lastSeq, 2);
      expect(usage.budget!.tokens, isNull);
      expect(usage.budget!.steps!.used, 2);
      final warnings = agent.logger.where('usage.decode_failed').toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.level, 'warning');
      expect(warnings.single.context['field'], 'budget.tokens');
      expect(warnings.single.context['session_id'], 's-1');
      // В записи нет сырого значения агента.
      expect('${warnings.single.context}'.contains('many'), isFalse);
    });

    test('budget is not an object: one decode_failed with field budget, '
        'the snapshot is applied without budget', () async {
      final session = await connected();

      agent.usage(wire(budget: 'full'));
      agent.usage(wire(seq: 2, budget: 'full'));

      expect(session.current.usage.lastSeq, 2);
      expect(session.current.usage.budget, isNull);
      final warnings = agent.logger.where('usage.decode_failed').toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.context['field'], 'budget');
    });

    test('reconnect resets budget with the rest of usage; the new agent '
        'starts from seq 1', () async {
      final session = await connected();
      agent.usage(wire(seq: 5, budget: _fullBudget()));
      expect(session.current.usage.budget, isNotNull);

      agent.restartAgent(capabilities: usageLoadCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;

      expect(session.current.usage.budget, isNull);
      expect(session.current.usage.support, UsageSupport.awaiting);

      now = DateTime.utc(2026, 11, 18, 12);
      agent.usage(wire(budget: _fullBudget()));
      expect(
        session.current.usage.budget!.receivedAt,
        DateTime.utc(2026, 11, 18, 12),
      );
    });

    test('session/load of an open session resets budget', () async {
      final session = await connected();
      agent.usage(wire(seq: 5, budget: _fullBudget()));
      expect(session.current.usage.budget, isNotNull);

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-1'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      await loading;

      expect(session.current.usage.budget, isNull);
    });

    test('a snapshot that waits for the registration during session/load '
        'gets receivedAt of the application, not of the arrival', () async {
      await connected();

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('listed-1'),
        cwd: '/work',
      );
      // Снимок приходит до регистрации сессии и откладывается (D10).
      agent.usage({
        ...usageParams(sessionId: 'listed-1', seq: 1),
        'budget': _fullBudget(),
      });
      now = DateTime.utc(2026, 11, 18, 10, 5);
      agent.respond(await load, const <String, Object?>{});
      final session = await loading;
      await pumpEventQueue();

      final budget = session.current.usage.budget;
      expect(budget, isNotNull);
      expect(budget!.receivedAt, DateTime.utc(2026, 11, 18, 10, 5));
    });
  });
}
