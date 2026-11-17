// Красные тесты задачи 1.4 change `add-desktop-usage-pane`: модель
// отображения панели Usage `UsagePaneData` и маппер `usagePaneDataOf`
// (agent-workbench-ui «Панель Usage»: «Панель с журналом», «Неизвестная цена
// и ход без usage», «Неполная стоимость сессии», «Агент без журнала», «Агент
// без usage», «Сбой загрузки журнала»; design.md, D2, D10, Q7–Q9).
//
// Формы (рабочие, при расхождении переименовать здесь и в заглушке
// `usage_pane_data.dart`): `UsagePaneData` (`available`, `ledgerAvailable`,
// `busy`, `ledger`, `notice`, `failureHint`, `statusLine`, `cards`, `turns`,
// `models`, `canRebuild`, `canExport`), карточки `UsagePaneCard`
// (`id`, `value`, `detail`), строки `UsagePaneTurn`/`UsagePaneStep`/
// `UsagePaneModel` с готовыми строками столбцов.
//
// Все числа форматирует kit (`usage_format.dart`, D2): тесты берут значения,
// где формат kit совпадает с «как есть» (< 1000), а большие числа (`184.2k`) —
// в одном отдельном тесте. Неизвестное — `—`, не `0` (DSK-11).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show SessionId, ToolCallId, ToolKind;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/usage/application/usage_pane_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _sid = SessionId('s-1');
const _none = TokenCounts(input: 0, output: 0, cacheRead: 0, cacheWrite: 0);

TokenCounts _tokens(
  int input,
  int output, {
  int cacheRead = 0,
  int cacheWrite = 0,
  int? reasoning,
}) => TokenCounts(
  input: input,
  output: output,
  cacheRead: cacheRead,
  cacheWrite: cacheWrite,
  reasoning: reasoning,
);

Money _usd(int micros) => Money(micros: micros, currency: 'USD');

UsageTotals _totals(
  TokenCounts tokens, {
  Money? cost,
  int steps = 1,
  Set<UsagePartial> partial = const {},
}) => UsageTotals(tokens: tokens, cost: cost, steps: steps, partial: partial);

UsageLedgerStep _step(
  int index, {
  List<String> ids = const [],
  String? model,
  TokenCounts? tokens,
  Money? cost,
}) => UsageLedgerStep(
  index: index,
  tokens: tokens ?? _tokens(50, 10),
  model: model,
  cost: cost,
  toolCallIds: ids,
);

UsageLedgerView _ledger({
  int seq = 5,
  UsageTotals? total,
  int turnCount = 2,
  UsageLedgerStatus? status,
  String? reason,
  int? records,
  List<UsageLedgerTurn> turns = const [],
  List<UsageLedgerModel> models = const [],
  UsageLedgerGroup? subagents,
  UsageLedgerGroup? summaries,
}) => UsageLedgerView(
  sessionId: _sid,
  seq: seq,
  total:
      total ??
      _totals(
        _tokens(500, 300, cacheRead: 400, cacheWrite: 50, reasoning: 120),
        cost: _usd(1200000),
        steps: 3,
      ),
  turnCount: turnCount,
  status: status,
  reason: reason,
  records: records,
  turns: turns,
  models: models,
  subagents: subagents,
  summaries: summaries,
);

SessionView _view({
  UsageLedgerState ledger = const UsageLedgerState.unavailable(),
  UsageView usage = const UsageView(support: UsageSupport.reported),
  SessionStatusView status = SessionStatusView.idle,
  List<TranscriptItem> transcript = const [],
}) => SessionView(
  revision: 1,
  status: status,
  usage: usage,
  usageLedger: ledger,
  transcript: transcript,
);

UsagePaneData _of(SessionView view) => usagePaneDataOf(view, cwd: '/work');

UsagePaneCard _card(UsagePaneData data, String id) =>
    data.cards.singleWhere((c) => c.id == id);

ToolCallItem _readCall(String id, String path) => ToolCallItem(
  id: 'tool-$id',
  toolCallId: ToolCallId(id),
  title: 'Read',
  details: ToolCallView(
    kind: ToolKind.read,
    status: ToolCallStatusView.succeeded,
    rawInput: {'path': path},
  ),
);

void main() {
  group('доступность панели (D10, Q7)', () {
    test('журнал объявлен — панель доступна независимо от usage', () {
      expect(
        usageAvailableOf(
          _view(
            ledger: const UsageLedgerState.idle(),
            usage: const UsageView(),
          ),
        ),
        isTrue,
      );
    });

    test('только usage (awaiting или reported) — доступна', () {
      expect(
        usageAvailableOf(
          _view(usage: const UsageView(support: UsageSupport.awaiting)),
        ),
        isTrue,
      );
      expect(
        usageAvailableOf(
          _view(usage: const UsageView(support: UsageSupport.reported)),
        ),
        isTrue,
      );
    });

    test('ни usage, ни журнала — недоступна; без сессии — недоступна', () {
      expect(usageAvailableOf(_view(usage: const UsageView())), isFalse);
      expect(usageAvailableOf(null), isFalse);
    });

    test('недоступная панель — пустые данные', () {
      final data = _of(_view(usage: const UsageView()));

      expect(data.available, isFalse);
      expect(data.cards, isEmpty);
      expect(data.canExport, isFalse);
      expect(data.canRebuild, isFalse);
      expect(usagePaneDataOf(null, cwd: '/work').available, isFalse);
    });
  });

  group('карточки из журнала (D2 п. 2, Q8)', () {
    late UsagePaneData data;

    setUp(() {
      data = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              turns: [
                UsageLedgerTurn(index: 1, total: _totals(_tokens(1, 1))),
                UsageLedgerTurn(index: 2, total: _totals(_tokens(1, 1))),
              ],
            ),
          ),
        ),
      );
    });

    test('Input — input + cacheRead + cacheWrite, вторая строка — кэш', () {
      expect(_card(data, 'input').value, '950');
      expect(_card(data, 'input').detail, 'cache read 400 · write 50');
    });

    test('Output — output и reasoning, если он известен', () {
      expect(_card(data, 'output').value, '300');
      expect(_card(data, 'output').detail, 'reasoning 120');
    });

    test('Cost — деньги kit без «~» при полной сумме', () {
      expect(_card(data, 'cost').value, r'$1.20');
      expect(_card(data, 'cost').detail, isNull);
    });

    test('Turns · steps — ходы · шаги и среднее в целых десятых', () {
      expect(_card(data, 'turns').value, '2 · 3');
      expect(_card(data, 'turns').detail, 'avg 1.5 steps per turn');
    });

    test('среднее: половина вверх, десятые считаются в целых', () {
      UsagePaneData avg(int turns, int steps) => _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              turnCount: turns,
              total: _totals(_tokens(1, 1), steps: steps),
            ),
          ),
        ),
      );

      expect(_card(avg(4, 7), 'turns').detail, 'avg 1.8 steps per turn');
      expect(_card(avg(3, 5), 'turns').detail, 'avg 1.7 steps per turn');
      expect(_card(avg(8, 3), 'turns').detail, 'avg 0.4 steps per turn');
    });

    test('при нуле ходов среднего нет', () {
      final empty = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(turnCount: 0, total: _totals(_tokens(0, 0), steps: 0)),
          ),
        ),
      );

      expect(_card(empty, 'turns').detail, isNull);
    });

    test('без reasoning второй строки Output нет', () {
      final d = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(total: _totals(_tokens(10, 5))),
          ),
        ),
      );

      expect(_card(d, 'output').detail, isNull);
    });

    test('большие числа форматирует kit: 184200 → 184.2k', () {
      final d = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(total: _totals(_tokens(184200, 3000))),
          ),
        ),
      );

      expect(_card(d, 'input').value, '184.2k');
      expect(_card(d, 'output').value, '3.0k');
    });
  });

  group('Cost и неполнота (D2 п. 2; «Неполная стоимость сессии»)', () {
    UsagePaneData costOf({Money? cost, Set<UsagePartial> partial = const {}}) =>
        _of(
          _view(
            ledger: UsageLedgerState.loaded(
              _ledger(
                total: _totals(_tokens(10, 5), cost: cost, partial: partial),
              ),
            ),
          ),
        );

    test('noUsage: «~» перед стоимостью и текст причины', () {
      final d = costOf(cost: _usd(2260000), partial: {UsagePartial.noUsage});

      expect(_card(d, 'cost').value, r'~$2.26');
      expect(_card(d, 'cost').detail, 'agent sent no usage for some steps');
    });

    test('причины через запятую в порядке noUsage, noPrice, beforeLoad', () {
      final d = costOf(
        cost: _usd(1000000),
        partial: {
          UsagePartial.beforeLoad,
          UsagePartial.noPrice,
          UsagePartial.noUsage,
        },
      );

      expect(
        _card(d, 'cost').detail,
        'agent sent no usage for some steps, price unknown for some steps, '
        'before the session was loaded',
      );
    });

    test('цена неизвестна: «—» и price unknown, не \$0', () {
      final d = costOf();

      expect(_card(d, 'cost').value, '—');
      expect(_card(d, 'cost').detail, 'price unknown');
    });

    test('«~» перед токенами при noUsage и beforeLoad, но не при noPrice', () {
      UsagePaneData tokensOf(Set<UsagePartial> partial) => _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              total: _totals(_tokens(100, 20), partial: partial),
              turns: const [],
            ),
          ),
        ),
      );

      expect(_card(tokensOf({UsagePartial.noUsage}), 'input').value, '~100');
      expect(_card(tokensOf({UsagePartial.beforeLoad}), 'input').value, '~100');
      expect(_card(tokensOf({UsagePartial.noPrice}), 'input').value, '100');
    });
  });

  group('«Per turn» (D2 п. 4)', () {
    final transcript = [_readCall('c1', '/work/lib/a.dart')];
    late UsagePaneData data;

    setUp(() {
      data = _of(
        _view(
          transcript: transcript,
          ledger: UsageLedgerState.loaded(
            _ledger(
              turns: [
                UsageLedgerTurn(
                  index: 1,
                  total: _totals(_tokens(100, 20), cost: _usd(1000)),
                  steps: [_step(0)],
                ),
                UsageLedgerTurn(
                  index: 2,
                  title: 'Fix the build',
                  running: true,
                  total: _totals(
                    _tokens(100, 40, cacheRead: 20, cacheWrite: 10),
                    cost: _usd(4100),
                    steps: 3,
                  ),
                  steps: [
                    _step(
                      0,
                      ids: ['c1'],
                      model: 'openai/gpt-5',
                      cost: _usd(1000),
                    ),
                    _step(1),
                    _step(2, ids: ['x', 'y']),
                  ],
                  subagents: UsageLedgerGroup(
                    count: 2,
                    tokens: _tokens(5, 5),
                    cost: _usd(10),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });

    test('ходы идут от нового к старому', () {
      expect([for (final t in data.turns) t.index], [2, 1]);
    });

    test('подпись N · “title”, без title — N', () {
      expect(data.turns.first.label, '2 · “Fix the build”');
      expect(data.turns.last.label, '1');
    });

    test('столбцы: Input с кэшем, Output, Cost kit; running у идущего', () {
      final turn = data.turns.first;

      expect(turn.input, '130');
      expect(turn.output, '40');
      expect(turn.cost, r'$0.0041');
      expect(turn.running, isTrue);
      expect(data.turns.last.running, isFalse);
    });

    test('шаги: step N · подпись по транскрипту, модель — в подсказке', () {
      final steps = data.turns.first.steps;

      expect(
        [for (final s in steps) s.label],
        ['step 1 · Read lib/a.dart', 'step 2 · reply', 'step 3 · 2 tool calls'],
      );
      expect(steps.first.title, 'Read lib/a.dart');
      expect(steps.first.model, 'openai/gpt-5');
      expect(steps.first.turn, 2);
      expect(steps.first.index, 0);
    });

    test('у хода с субагентами — строка subagents · N runs', () {
      expect(data.turns.first.subagents, 'subagents · 2 runs');
      expect(data.turns.last.subagents, isNull);
    });
  });

  group('Неизвестное — «—», не 0 («Неизвестная цена и ход без usage»)', () {
    late UsagePaneData data;

    setUp(() {
      data = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              turns: [
                UsageLedgerTurn(
                  index: 1,
                  total: _totals(_none, partial: {UsagePartial.noUsage}),
                  steps: [
                    UsageLedgerStep(
                      index: 0,
                      tokens: _none,
                      partial: const {UsagePartial.noUsage},
                    ),
                  ],
                ),
                UsageLedgerTurn(
                  index: 2,
                  total: _totals(_tokens(100, 20)),
                  steps: [_step(0)],
                ),
              ],
              models: [
                UsageLedgerModel(
                  model: 'local/llama',
                  steps: 2,
                  tokens: _tokens(100, 20),
                ),
                UsageLedgerModel(
                  model: 'local/silent',
                  steps: 1,
                  tokens: _none,
                  partial: const {UsagePartial.noUsage},
                ),
              ],
            ),
          ),
        ),
      );
    });

    test('ход без usage — «—» в Input, Output и Cost', () {
      final turn = data.turns.last; // индекс 1 — старейший

      expect(turn.index, 1);
      expect([turn.input, turn.output, turn.cost], ['—', '—', '—']);
      final step = turn.steps.single;
      expect([step.input, step.output, step.cost], ['—', '—', '—']);
    });

    test('ход без цены — «—» только в Cost, токены остаются', () {
      final turn = data.turns.first;

      expect(turn.input, '100');
      expect(turn.output, '20');
      expect(turn.cost, '—');
    });

    test('модель без цены и модель без usage', () {
      final priceless = data.models.firstWhere(
        (m) => m.label == 'local / llama',
      );
      final silent = data.models.firstWhere((m) => m.label == 'local / silent');

      expect(priceless.input, '100');
      expect(priceless.cost, '—');
      expect([silent.input, silent.output, silent.cost], ['—', '—', '—']);
    });

    test('«0» и «\$0.00» не встречаются там, где значение неизвестно', () {
      final cells = [
        for (final t in data.turns) ...[t.input, t.output, t.cost],
        for (final m in data.models) ...[m.input, m.output, m.cost],
      ];

      expect(cells, isNot(contains('0')));
      expect(cells, isNot(contains(r'$0.00')));
    });
  });

  group('«Per model» (D2 п. 5, Q9)', () {
    test('подпись — provider / id по первому «/»; без «/» — как есть', () {
      final data = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              models: [
                UsageLedgerModel(
                  model: 'openai/gpt-5',
                  steps: 2,
                  tokens: _tokens(100, 20),
                  cost: _usd(1200000),
                ),
                UsageLedgerModel(
                  model: 'openrouter/meta/llama',
                  steps: 1,
                  tokens: _tokens(10, 5),
                ),
                UsageLedgerModel(
                  model: 'solo',
                  steps: 1,
                  tokens: _tokens(10, 5),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        [for (final m in data.models) m.label],
        ['openai / gpt-5', 'openrouter / meta/llama', 'solo'],
      );
      expect(data.models.first.cost, r'$1.20');
    });

    test('группы Subagents и Summaries — строками после моделей', () {
      final data = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              models: [
                UsageLedgerModel(
                  model: 'openai/gpt-5',
                  steps: 2,
                  tokens: _tokens(100, 20),
                ),
              ],
              subagents: UsageLedgerGroup(
                count: 2,
                tokens: _tokens(10, 5),
                cost: _usd(2000),
              ),
              summaries: UsageLedgerGroup(count: 3, tokens: _tokens(7, 2)),
            ),
          ),
        ),
      );

      expect(
        [for (final m in data.models) m.label],
        ['openai / gpt-5', 'Subagents', 'Summaries'],
      );
      expect(data.models[1].detail, '2 runs');
      expect(data.models[2].detail, '3');
      expect(data.models[1].input, '10');
      expect(data.models[2].cost, '—');
    });

    test('без групп в журнале строк Subagents и Summaries нет', () {
      final data = _of(
        _view(ledger: UsageLedgerState.loaded(_ledger(models: const []))),
      );

      expect(data.models, isEmpty);
    });
  });

  group('строка состояния журнала (Q3)', () {
    String? statusOf(UsageLedgerView ledger) =>
        _of(_view(ledger: UsageLedgerState.loaded(ledger))).statusLine;

    test('upToDate с числом записей', () {
      expect(
        statusOf(_ledger(status: UsageLedgerStatus.upToDate, records: 12)),
        'Ledger: up to date · 12 records',
      );
    });

    test('rebuilt с причиной и числом записей', () {
      expect(
        statusOf(
          _ledger(
            status: UsageLedgerStatus.rebuilt,
            reason: 'explicit',
            records: 12,
          ),
        ),
        'rebuilt from journal (explicit) · 12 records',
      );
    });

    test('inMemory и notSaved', () {
      expect(
        statusOf(_ledger(status: UsageLedgerStatus.inMemory)),
        'in memory',
      );
      expect(
        statusOf(_ledger(status: UsageLedgerStatus.notSaved)),
        'not saved',
      );
    });

    test('агент не прислал статус — строки нет', () {
      expect(statusOf(_ledger()), isNull);
    });
  });

  group('состояния журнала (D2 п. 6)', () {
    final previous = _ledger(
      turns: [UsageLedgerTurn(index: 1, total: _totals(_tokens(1, 1)))],
    );

    test('idle без журнала: индикатор вместо таблиц, Rebuild можно', () {
      final d = _of(_view(ledger: const UsageLedgerState.idle()));

      expect(d.busy, isTrue);
      expect(d.ledger, isNull);
      expect(d.turns, isEmpty);
      expect(d.canExport, isFalse);
      expect(d.canRebuild, isTrue);
    });

    test('loading без прежнего журнала: индикатор, Rebuild недоступен', () {
      final d = _of(_view(ledger: const UsageLedgerState.loading()));

      expect(d.busy, isTrue);
      expect(d.canRebuild, isFalse);
      expect(d.canExport, isFalse);
    });

    test('loading с прежним журналом: прежние данные, Export есть, '
        'Rebuild недоступен', () {
      final d = _of(
        _view(ledger: UsageLedgerState.loading(previous: previous)),
      );

      expect(d.busy, isTrue);
      expect(d.ledger, previous);
      expect(d.turns, hasLength(1));
      expect(d.canExport, isTrue);
      expect(d.canRebuild, isFalse);
    });

    test('loaded: без индикатора, Export и Rebuild доступны', () {
      final d = _of(_view(ledger: UsageLedgerState.loaded(previous)));

      expect(d.busy, isFalse);
      expect(d.canExport, isTrue);
      expect(d.canRebuild, isTrue);
      expect(d.notice, UsagePaneNotice.none);
    });

    test(
      'failed: заметка, код ошибки в подсказке, прежний журнал сохранён',
      () {
        final d = _of(
          _view(
            ledger: UsageLedgerState.failed(
              const UsageLedgerFailure(
                kind: UsageLedgerFailureKind.agentError,
                code: -32603,
              ),
              previous: previous,
            ),
          ),
        );

        expect(d.notice, UsagePaneNotice.ledgerFailed);
        expect(d.failureHint, contains('-32603'));
        expect(d.ledger, previous);
        expect(d.canExport, isTrue);
        expect(d.canRebuild, isTrue);
        expect(d.busy, isFalse);
      },
    );

    test('failed без прежнего журнала: Export нет', () {
      final d = _of(
        _view(
          ledger: const UsageLedgerState.failed(
            UsageLedgerFailure(kind: UsageLedgerFailureKind.request),
          ),
        ),
      );

      expect(d.notice, UsagePaneNotice.ledgerFailed);
      expect(d.canExport, isFalse);
    });
  });

  group('агент без журнала, но с usage («Агент без журнала»)', () {
    final session = _totals(
      _tokens(200, 50, cacheRead: 30, cacheWrite: 20),
      cost: _usd(1200000),
      steps: 3,
    );
    late UsagePaneData data;

    setUp(() {
      data = _of(
        _view(
          usage: UsageView(
            support: UsageSupport.reported,
            session: session,
            lastSeq: 4,
          ),
        ),
      );
    });

    test('панель доступна, карточки — из суммы снимка', () {
      expect(data.available, isTrue);
      expect(data.ledgerAvailable, isFalse);
      expect(_card(data, 'input').value, '250');
      expect(_card(data, 'output').value, '50');
      expect(_card(data, 'cost').value, r'$1.20');
    });

    test('Turns · steps показывает только шаги, без среднего', () {
      expect(_card(data, 'turns').value, '3');
      expect(_card(data, 'turns').detail, isNull);
    });

    test('таблиц, Export CSV и Rebuild нет, есть заметка noLedger', () {
      expect(data.turns, isEmpty);
      expect(data.models, isEmpty);
      expect(data.canExport, isFalse);
      expect(data.canRebuild, isFalse);
      expect(data.notice, UsagePaneNotice.noLedger);
      expect(data.busy, isFalse);
    });
  });

  group('Тон карточек: «немая» карточка не жёлтая (D2 п. 2)', () {
    UsagePaneData silent({Money? cost}) => _of(
      _view(
        ledger: UsageLedgerState.loaded(
          _ledger(
            total: _totals(_none, cost: cost, partial: {UsagePartial.noUsage}),
          ),
        ),
      ),
    );

    test('Input и Output со значением «—» не approximate', () {
      final d = silent();

      expect(_card(d, 'input').value, '—');
      expect(_card(d, 'input').approximate, isFalse);
      expect(_card(d, 'output').value, '—');
      expect(_card(d, 'output').approximate, isFalse);
    });

    test(
      'Cost со значением «—» не approximate, со значением — approximate',
      () {
        expect(_card(silent(), 'cost').value, '—');
        expect(_card(silent(), 'cost').approximate, isFalse);
        expect(_card(silent(cost: _usd(1000000)), 'cost').value, r'~$1.00');
        expect(_card(silent(cost: _usd(1000000)), 'cost').approximate, isTrue);
      },
    );

    test('Input со значением и неполной суммой остаётся approximate', () {
      final d = _of(
        _view(
          ledger: UsageLedgerState.loaded(
            _ledger(
              total: _totals(_tokens(100, 20), partial: {UsagePartial.noUsage}),
            ),
          ),
        ),
      );

      expect(_card(d, 'input').approximate, isTrue);
    });
  });
}
