// Тесты задачи 3.3 change `add-desktop-usage-pane`: данные блока
// `Turn budget` панели Usage (agent-workbench-ui «Бюджет хода в панели
// Usage»: «Прогресс во время хода», «Время идёт между шагами», «Начало
// нового хода», «Цена неизвестна», «После хода», «Бюджет у агента без
// журнала», «Без лимитов»; design.md, D9, D10, Q5 (а), Q11 (а), R2, R8).
//
// Формы (см. `usage_budget.dart`): `UsagePaneData.budget` (`UsageBudgetData`: `title`,
// `rows` — Steps, Tokens, Cost, `time` — исходные числа Time, `ticking`),
// чистые `usageBudgetRowsAt(budget, now:)` и `formatUsageDuration(ms)`.
// Источник — `SessionView.usage.budget` (kit, D9): статус сессии и
// `pendingApprovals` берутся из того же `SessionView`.
//
// Числа форматирует kit (`formatUsageTokens`, `formatUsageMoney`); здесь они
// проверяются готовыми подписями. Тон считается в целых: `used·5 ≥ limit·4` —
// `warning`, `used ≥ limit` — `danger` (D9). Группа `ActiveSessionCubit`
// проверяет ключ кэша данных панели (D1, D9): без него заголовок и признак
// тика застревали бы до следующего снимка usage.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show AcpSession, ApprovalRequestId, ApprovalRiskLevel;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/usage/application/usage_budget.dart';
import 'package:codelab_desktop/features/usage/application/usage_pane_data.dart';
import 'package:codelab_desktop/features/workbench/application/active_session_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_usage_csv_saver.dart';

final _t0 = DateTime.utc(2026, 11, 18, 12);

Money _usd(int micros) => Money(micros: micros, currency: 'USD');

/// Бюджет снимка; по умолчанию — все четыре подполя из сценария «Прогресс во
/// время хода»: `3 / 50`, `92.0k / 200.0k`, `$0.41 / $0.50`, `3:00 / 10:00`.
TurnBudgetView _budget({
  bool ended = false,
  DateTime? receivedAt,
  String turnId = 'turn-1',
  BudgetCount? steps = const BudgetCount(used: 3, limit: 50),
  BudgetCount? tokens = const BudgetCount(used: 92000, limit: 200000),
  BudgetCost? cost,
  BudgetDuration? duration = const BudgetDuration(
    usedMs: 180000,
    limitMs: 600000,
  ),
  bool defaultCost = true,
}) => TurnBudgetView(
  turnId: turnId,
  receivedAt: receivedAt ?? _t0,
  ended: ended,
  steps: steps,
  tokens: tokens,
  cost: defaultCost && cost == null
      ? BudgetCost(used: _usd(410000), limit: _usd(500000))
      : cost,
  duration: duration,
);

const _approval = PendingApprovalView(
  approvalId: ApprovalRequestId('permission-1'),
  sessionId: SessionId('s'),
  risk: ApprovalRiskLevel.shell,
  options: [],
  focused: true,
);

SessionView _view(
  TurnBudgetView? budget, {
  SessionStatusView status = SessionStatusView.idle,
  bool approval = false,
  UsageLedgerState ledger = const UsageLedgerState.unavailable(),
  UsageSupport support = UsageSupport.reported,
  UsageView? usage,
}) => SessionView(
  revision: 1,
  status: status,
  usage: usage ?? UsageView(support: support, lastSeq: 1, budget: budget),
  usageLedger: ledger,
  pendingApprovals: [if (approval) _approval],
);

UsageBudgetData _data(
  TurnBudgetView? budget, {
  SessionStatusView status = SessionStatusView.idle,
  bool approval = false,
}) {
  final data = usagePaneDataOf(
    _view(budget, status: status, approval: approval),
    cwd: '/work',
  );
  expect(data.budget, isNotNull, reason: 'блок Turn budget должен быть');
  return data.budget!;
}

/// Строка Steps/Tokens/Cost по id из данных (Time — через [usageBudgetRowsAt]).
UsageBudgetRow _row(UsageBudgetData data, String id, {DateTime? now}) =>
    usageBudgetRowsAt(data, now: now ?? _t0).singleWhere((r) => r.id == id);

List<String> _ids(UsageBudgetData data) => [
  for (final r in usageBudgetRowsAt(data, now: _t0)) r.id,
];

/// Одна строка Steps с заданными числами — для таблиц тона и заполнения.
UsageBudgetRow _steps(int used, int limit) => _row(
  _data(
    _budget(
      steps: BudgetCount(used: used, limit: limit),
    ),
  ),
  'steps',
);

// --- двойники для группы ActiveSessionCubit (как в ledger_refresh_test) ---

final class _Handle extends Fake implements SessionHandle {
  _Handle(String id, this._current) : id = SessionId(id);

  @override
  final SessionId id;

  SessionView _current;
  final StreamController<SessionView> _stream =
      StreamController<SessionView>.broadcast(sync: true);

  @override
  SessionView get current => _current;

  @override
  Stream<SessionView> get view => _stream.stream;

  void emit(SessionView next) {
    _current = next;
    _stream.add(next);
  }
}

final class _Workspace extends Fake implements ClientWorkspace {
  final Map<String, _Handle> handles = {};

  @override
  SessionHandle? session(SessionId id) => handles[id.value];

  @override
  Stream<PromptOutcome> get promptOutcomes => const Stream.empty();

  @override
  Future<void> refreshUsageLedger(SessionId id, {bool rebuild = false}) async {}
}

void main() {
  group('строки по присутствующим подполям (D9)', () {
    test('все четыре: порядок Steps, Tokens, Cost, Time', () {
      expect(_ids(_data(_budget())), ['steps', 'tokens', 'cost', 'time']);
    });

    test('только Tokens и duration: строки tokens и time', () {
      final data = _data(_budget(steps: null, defaultCost: false, cost: null));
      expect(_ids(data), ['tokens', 'time']);
    });

    test('только Steps: одна строка, Time нет', () {
      final data = _data(
        _budget(tokens: null, duration: null, defaultCost: false),
      );
      expect(_ids(data), ['steps']);
      expect(data.time, isNull);
    });

    test('Time есть, только если есть duration', () {
      expect(_data(_budget()).time, isNotNull);
      expect(_data(_budget(duration: null)).time, isNull);
      expect(_ids(_data(_budget(duration: null))), ['steps', 'tokens', 'cost']);
    });

    test('в данных строки Steps, Tokens, Cost; Time — исходные числа', () {
      final data = _data(_budget(receivedAt: _t0));
      expect([for (final r in data.rows) r.id], ['steps', 'tokens', 'cost']);
      expect(data.time?.usedMs, 180000);
      expect(data.time?.limitMs, 600000);
      expect(data.time?.receivedAt, _t0);
    });

    test('пояснение под блоком — константа из application', () {
      expect(
        usageBudgetFootnote,
        'When a limit is hit, the turn stops at the next step boundary.',
      );
    });
  });

  group('подписи строк (D9, «Прогресс во время хода»)', () {
    test('Steps `3 / 50`, Tokens `92.0k / 200.0k`, Cost `\$0.41 / \$0.50`, '
        'Time `3:00 / 10:00`', () {
      final data = _data(_budget());
      expect(_row(data, 'steps').value, '3 / 50');
      expect(_row(data, 'tokens').value, '92.0k / 200.0k');
      expect(_row(data, 'cost').value, r'$0.41 / $0.50');
      expect(_row(data, 'time').value, '3:00 / 10:00');
    });

    test('подписи строк: Steps, Tokens, Cost, Time', () {
      final data = _data(_budget());
      expect(
        [for (final r in usageBudgetRowsAt(data, now: _t0)) r.label],
        ['Steps', 'Tokens', 'Cost', 'Time'],
      );
    });

    test('Cost в другой валюте печатает kit: `0.41 EUR / 0.50 EUR`', () {
      final data = _data(
        _budget(
          cost: BudgetCost(
            used: const Money(micros: 410000, currency: 'EUR'),
            limit: const Money(micros: 500000, currency: 'EUR'),
          ),
        ),
      );
      expect(_row(data, 'cost').value, '0.41 EUR / 0.50 EUR');
    });

    test('подсказка Tokens называет правило `input + output, including '
        'subagents` (R2); у остальных строк подсказки нет', () {
      final data = _data(_budget());
      expect(_row(data, 'tokens').hint, 'input + output, including subagents');
      expect(_row(data, 'steps').hint, isNull);
      expect(_row(data, 'cost').hint, isNull);
      expect(_row(data, 'time').hint, isNull);
    });
  });

  group('Cost без израсходованной суммы (R8, «Цена неизвестна»)', () {
    late UsageBudgetData data;

    setUp(() {
      data = _data(_budget(cost: BudgetCost(limit: _usd(500000))));
    });

    test('подпись `— / \$0.50`, не `\$0.00 / \$0.50`', () {
      expect(_row(data, 'cost').value, r'— / $0.50');
    });

    test('пояснение `not checked: price unknown`', () {
      expect(_row(data, 'cost').note, 'not checked: price unknown');
    });

    test('без тона и с пустой полосой', () {
      final row = _row(data, 'cost');
      expect(row.tone, UsageBudgetTone.neutral);
      expect(row.fill, 0);
    });

    test('известная цена пояснения не имеет', () {
      expect(_row(_data(_budget()), 'cost').note, isNull);
    });
  });

  group('тон по доле в целых (D9)', () {
    test('ниже 80 % — нейтральный; граница used·5 = limit·4 — warning', () {
      expect(_steps(79, 100).tone, UsageBudgetTone.neutral);
      expect(_steps(3, 5).tone, UsageBudgetTone.neutral);
      expect(_steps(80, 100).tone, UsageBudgetTone.warning);
      expect(_steps(4, 5).tone, UsageBudgetTone.warning);
      expect(_steps(99, 100).tone, UsageBudgetTone.warning);
    });

    test('от 100 % — danger', () {
      expect(_steps(100, 100).tone, UsageBudgetTone.danger);
      expect(_steps(101, 100).tone, UsageBudgetTone.danger);
      expect(_steps(5, 5).tone, UsageBudgetTone.danger);
    });

    test('граница без `double`: 79999 из 100000 — нейтральный, 80000 — '
        'warning', () {
      final low = _row(
        _data(_budget(tokens: const BudgetCount(used: 79999, limit: 100000))),
        'tokens',
      );
      final edge = _row(
        _data(_budget(tokens: const BudgetCount(used: 80000, limit: 100000))),
        'tokens',
      );
      expect(low.tone, UsageBudgetTone.neutral);
      expect(edge.tone, UsageBudgetTone.warning);
    });

    test('числа около 2^62 с провода: тон без переполнения умножения', () {
      const limit = (1 << 62) + (1 << 61);
      const edge = limit - limit ~/ 5;
      // used·5 переполнило бы int64 и дало бы ложный нейтральный/warning.
      expect(_steps(edge, limit).tone, UsageBudgetTone.warning);
      expect(_steps(edge - 1, limit).tone, UsageBudgetTone.neutral);
      expect(_steps(limit, limit).tone, UsageBudgetTone.danger);
      expect(_steps(1 << 61, limit).tone, UsageBudgetTone.neutral);
    });

    test('граница warning равна ceil(4·L/5) на малых лимитах', () {
      for (var limit = 0; limit <= 12; limit++) {
        for (var used = 0; used < limit; used++) {
          expect(
            _steps(used, limit).tone,
            used * 5 >= limit * 4
                ? UsageBudgetTone.warning
                : UsageBudgetTone.neutral,
            reason: '$used / $limit',
          );
        }
      }
    });

    test('Cost: `\$0.41 / \$0.50` — warning (сценарий «Прогресс»)', () {
      expect(_row(_data(_budget()), 'cost').tone, UsageBudgetTone.warning);
    });

    test('Cost: `\$0.52 / \$0.50` — danger (сценарий «После хода»)', () {
      final data = _data(
        _budget(
          ended: true,
          cost: BudgetCost(used: _usd(520000), limit: _usd(500000)),
        ),
      );
      final row = _row(data, 'cost');
      expect(row.value, r'$0.52 / $0.50');
      expect(row.tone, UsageBudgetTone.danger);
      expect(row.fill, 1.0);
    });

    test('Steps `3 / 50` и Tokens `92.0k / 200.0k` — нейтральные', () {
      final data = _data(_budget());
      expect(_row(data, 'steps').tone, UsageBudgetTone.neutral);
      expect(_row(data, 'tokens').tone, UsageBudgetTone.neutral);
    });
  });

  group('заполнение полосы и больше 100 %', () {
    test('доля used / limit', () {
      expect(_steps(25, 100).fill, closeTo(0.25, 1e-9));
      final tokens = _row(_data(_budget()), 'tokens');
      expect(tokens.fill, closeTo(0.46, 1e-9));
    });

    test('больше 100 %: полоса не больше 1, подпись с настоящими числами', () {
      final row = _steps(150, 100);
      expect(row.fill, 1.0);
      expect(row.value, '150 / 100');
      expect(row.tone, UsageBudgetTone.danger);
    });

    test('ровно 100 % — полная полоса', () {
      expect(_steps(100, 100).fill, 1.0);
    });

    test('лимит 0: полоса полная, danger, деления на ноль нет', () {
      final row = _steps(0, 0);
      expect(row.fill, 1.0);
      expect(row.tone, UsageBudgetTone.danger);
      expect(row.value, '0 / 0');
    });

    test('лимит Cost 0 (`max_cost` меньше половины микродоллара)', () {
      final data = _data(
        _budget(
          cost: BudgetCost(used: _usd(0), limit: _usd(0)),
        ),
      );
      final row = _row(data, 'cost');
      expect(row.fill, 1.0);
      expect(row.tone, UsageBudgetTone.danger);
      expect(row.value, r'$0.00 / $0.00');
    });

    test('лимит 0 у Time: полоса полная, без исключения', () {
      final data = _data(
        _budget(duration: const BudgetDuration(usedMs: 0, limitMs: 0)),
      );
      final row = _row(data, 'time');
      expect(row.fill, 1.0);
      expect(row.tone, UsageBudgetTone.danger);
    });
  });

  group('formatUsageDuration: `m:ss` и `h:mm:ss`, секунды вниз', () {
    test('минуты и секунды', () {
      expect(formatUsageDuration(0), '0:00');
      expect(formatUsageDuration(999), '0:00');
      expect(formatUsageDuration(1000), '0:01');
      expect(formatUsageDuration(59999), '0:59');
      expect(formatUsageDuration(60000), '1:00');
      expect(formatUsageDuration(90000), '1:30');
      expect(formatUsageDuration(180000), '3:00');
      expect(formatUsageDuration(599999), '9:59');
      expect(formatUsageDuration(600000), '10:00');
      expect(formatUsageDuration(3599999), '59:59');
    });

    test('от часа — `h:mm:ss`', () {
      expect(formatUsageDuration(3600000), '1:00:00');
      expect(formatUsageDuration(3661999), '1:01:01');
      expect(formatUsageDuration(36000000), '10:00:00');
    });

    test('отрицательное значение считается нулём', () {
      expect(formatUsageDuration(-5), '0:00');
    });

    test('подпись Time с часом: `1:00:00 / 2:00:00`', () {
      final data = _data(
        _budget(
          duration: const BudgetDuration(usedMs: 3600000, limitMs: 7200000),
        ),
      );
      expect(_row(data, 'time').value, '1:00:00 / 2:00:00');
    });
  });

  group('заголовок `This turn` / `Last turn` (Q11 (а))', () {
    test('running и неитоговый бюджет — `This turn`', () {
      final data = _data(_budget(), status: SessionStatusView.running);
      expect(data.title, 'This turn');
    });

    test('cancelling и неитоговый бюджет — `This turn`', () {
      final data = _data(_budget(), status: SessionStatusView.cancelling);
      expect(data.title, 'This turn');
    });

    test('сессия свободна — `Last turn`, даже если бюджет неитоговый', () {
      expect(_data(_budget()).title, 'Last turn');
      expect(_data(_budget(ended: true)).title, 'Last turn');
    });

    test('running с итоговым бюджетом прошлого хода — `Last turn` с его '
        'числами, без тика («Начало нового хода»)', () {
      final data = _data(
        _budget(
          ended: true,
          duration: const BudgetDuration(usedMs: 90000, limitMs: 600000),
        ),
        status: SessionStatusView.running,
      );
      expect(data.title, 'Last turn');
      expect(data.ticking, isFalse);
      // Часы далеко впереди: итог прошлого хода не дорастает.
      final later = _t0.add(const Duration(minutes: 30));
      expect(_row(data, 'time', now: later).value, '1:30 / 10:00');
      expect(_row(data, 'steps').value, '3 / 50');
    });

    test('первый `step` нового хода (ended ложен) переключает на `This turn` '
        'и включает тик', () {
      final data = _data(
        _budget(turnId: 'turn-2', steps: const BudgetCount(used: 1, limit: 50)),
        status: SessionStatusView.running,
      );
      expect(data.title, 'This turn');
      expect(data.ticking, isTrue);
      expect(_row(data, 'steps').value, '1 / 50');
    });
  });

  group('признак тика (D9)', () {
    test('running, нет одобрений, неитоговый, есть duration — тик', () {
      final data = _data(_budget(), status: SessionStatusView.running);
      expect(data.ticking, isTrue);
    });

    test('ожидающее одобрение отключает тик', () {
      final data = _data(
        _budget(),
        status: SessionStatusView.running,
        approval: true,
      );
      expect(data.ticking, isFalse);
      expect(data.title, 'This turn');
    });

    test('cancelling, idle, failed — без тика', () {
      for (final status in [
        SessionStatusView.cancelling,
        SessionStatusView.idle,
        SessionStatusView.failed,
      ]) {
        expect(
          _data(_budget(), status: status).ticking,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('итоговый бюджет — без тика', () {
      final data = _data(
        _budget(ended: true),
        status: SessionStatusView.running,
      );
      expect(data.ticking, isFalse);
    });

    test('без duration — без тика', () {
      final data = _data(
        _budget(duration: null),
        status: SessionStatusView.running,
      );
      expect(data.ticking, isFalse);
    });
  });

  group('Time на момент now (D9, «Время между снимками», R3)', () {
    UsageBudgetData running({bool approval = false, bool ended = false}) =>
        _data(
          _budget(ended: ended),
          status: SessionStatusView.running,
          approval: approval,
        );

    String time(UsageBudgetData data, Duration after) =>
        _row(data, 'time', now: _t0.add(after)).value;

    test('running без одобрений: usedMs + (now − receivedAt)', () {
      final data = running();
      expect(time(data, Duration.zero), '3:00 / 10:00');
      expect(time(data, const Duration(seconds: 5)), '3:05 / 10:00');
      expect(time(data, const Duration(minutes: 1)), '4:00 / 10:00');
    });

    test('секунды вниз: 5,9 с дают `3:05`', () {
      expect(
        time(running(), const Duration(milliseconds: 5900)),
        '3:05 / 10:00',
      );
    });

    test('при ожидающем одобрении Time остаётся `3:00 / 10:00`', () {
      expect(
        time(running(approval: true), const Duration(seconds: 5)),
        '3:00 / 10:00',
      );
    });

    test('при cancelling — usedMs снимка', () {
      final data = _data(_budget(), status: SessionStatusView.cancelling);
      expect(time(data, const Duration(seconds: 5)), '3:00 / 10:00');
    });

    test('при свободной сессии — usedMs снимка', () {
      expect(
        time(_data(_budget()), const Duration(seconds: 5)),
        '3:00 / 10:00',
      );
    });

    test('итоговый бюджет — usedMs снимка', () {
      expect(
        time(running(ended: true), const Duration(seconds: 5)),
        '3:00 / 10:00',
      );
    });

    test('usedMs около 2^63−1: сложение насыщается, не уходит в минус', () {
      const max = 0x7fffffffffffffff;
      final data = _data(
        _budget(
          duration: const BudgetDuration(usedMs: max - 100, limitMs: max),
        ),
        status: SessionStatusView.running,
      );
      expect(
        time(data, const Duration(seconds: 5)),
        '${formatUsageDuration(max)} / ${formatUsageDuration(max)}',
      );
    });

    test('отрицательная разность (часы позади часов kit) считается нулём', () {
      expect(time(running(), const Duration(seconds: -7)), '3:00 / 10:00');
    });

    test('тон и заполнение Time считаются на момент now', () {
      final data = _data(
        _budget(
          duration: const BudgetDuration(usedMs: 470000, limitMs: 600000),
        ),
        status: SessionStatusView.running,
      );
      final calm = _row(data, 'time', now: _t0);
      final warn = _row(
        data,
        'time',
        now: _t0.add(const Duration(seconds: 10)),
      );
      final over = _row(
        data,
        'time',
        now: _t0.add(const Duration(seconds: 150)),
      );
      expect(calm.tone, UsageBudgetTone.neutral);
      expect(warn.tone, UsageBudgetTone.warning);
      expect(warn.value, '8:00 / 10:00');
      expect(over.tone, UsageBudgetTone.danger);
      expect(over.value, '10:20 / 10:00');
      expect(over.fill, 1.0);
    });

    test('остальные строки от now не зависят', () {
      final data = running();
      final a = _row(data, 'steps', now: _t0);
      final b = _row(data, 'steps', now: _t0.add(const Duration(hours: 1)));
      expect(a.value, b.value);
      expect(
        _row(data, 'tokens', now: _t0).value,
        _row(data, 'tokens', now: _t0.add(const Duration(hours: 1))).value,
      );
    });
  });

  group('блок без журнала и без бюджета (D10, «Без лимитов»)', () {
    test('агент без журнала: панель доступна, блок есть из usage', () {
      final data = usagePaneDataOf(
        _view(
          _budget(ended: true),
          ledger: const UsageLedgerState.unavailable(),
        ),
        cwd: '/work',
      );
      expect(data.available, isTrue);
      expect(data.ledgerAvailable, isFalse);
      expect(data.notice, UsagePaneNotice.noLedger);
      expect(data.budget, isNotNull);
      expect(data.budget!.title, 'Last turn');
    });

    test('с журналом блок строится из usage, а не из журнала', () {
      final data = usagePaneDataOf(
        _view(_budget(), ledger: const UsageLedgerState.idle()),
        cwd: '/work',
      );
      expect(data.ledgerAvailable, isTrue);
      expect(data.budget, isNotNull);
    });

    test('без budget блока нет', () {
      expect(usagePaneDataOf(_view(null), cwd: '/work').budget, isNull);
    });

    test('панель недоступна — блока нет', () {
      final data = usagePaneDataOf(
        _view(null, support: UsageSupport.unknown),
        cwd: '/work',
      );
      expect(data.available, isFalse);
      expect(data.budget, isNull);
    });

    test('сессии нет — блока нет', () {
      expect(usagePaneDataOf(null, cwd: '/work').budget, isNull);
    });
  });

  group('ActiveSessionCubit: ключ кэша данных панели (D1, D9)', () {
    late _Workspace workspace;
    late ActiveSessionCubit cubit;
    late _Handle handle;

    // Один и тот же `UsageView` во всех ревизиях: кэш по identity `usage`
    // сам их не различит, нужен ключ статуса и одобрений.
    final usage = UsageView(
      support: UsageSupport.reported,
      lastSeq: 3,
      budget: _budget(),
    );

    SessionView revision(
      int n, {
      SessionStatusView status = SessionStatusView.idle,
      bool approval = false,
    }) => SessionView(
      revision: n,
      status: status,
      usage: usage,
      usageLedger: const UsageLedgerState.unavailable(),
      pendingApprovals: [if (approval) _approval],
    );

    setUp(() {
      workspace = _Workspace();
      handle = workspace.handles['a'] = _Handle('a', revision(1));
      cubit = ActiveSessionCubit(
        changes: ShellChanges(),
        workspace: workspace,
        diagnostics: ShellDiagnostics(),
        usageCsvSaver: FakeUsageCsvSaver(),
      );
      cubit.show(AcpSession(id: const SessionId('a'), cwd: '/work'));
    });

    tearDown(() => cubit.close());

    test('сессия свободна: `Last turn`, тика нет', () async {
      await pumpEventQueue();
      expect(cubit.state.usage.budget?.title, 'Last turn');
      expect(cubit.state.usage.budget?.ticking, isFalse);
    });

    test(
      'смена статуса без новой ревизии usage меняет заголовок и тик',
      () async {
        handle.emit(revision(2, status: SessionStatusView.running));
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.title, 'This turn');
        expect(cubit.state.usage.budget?.ticking, isTrue);

        handle.emit(revision(3, status: SessionStatusView.cancelling));
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.title, 'This turn');
        expect(cubit.state.usage.budget?.ticking, isFalse);

        handle.emit(revision(4));
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.title, 'Last turn');
        expect(cubit.state.usage.budget?.ticking, isFalse);
      },
    );

    test(
      'появление и снятие ожидающего одобрения меняют признак тика',
      () async {
        handle.emit(revision(2, status: SessionStatusView.running));
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.ticking, isTrue);

        handle.emit(
          revision(3, status: SessionStatusView.running, approval: true),
        );
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.ticking, isFalse);
        expect(cubit.state.usage.budget?.title, 'This turn');

        handle.emit(revision(4, status: SessionStatusView.running));
        await pumpEventQueue();
        expect(cubit.state.usage.budget?.ticking, isTrue);
      },
    );
  });
}
