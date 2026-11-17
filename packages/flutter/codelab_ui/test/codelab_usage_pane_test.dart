// Красные тесты задачи 1.6 change `add-desktop-usage-pane`: организм
// `CodeLabUsagePane` (слой `organisms/`; design.md D1, D2; agent-workbench-ui
// «Панель Usage»: карточки, таблицы `Per turn` и `Per model` с раскрытием,
// состояния журнала, заметка сбоя с `Retry`, заметка «без журнала»).
//
// Отсутствующее пока поведение (до задачи 1.7 виджет пуст): ключи `usage-*`,
// раскрытие хода до шагов, индикаторы, кнопки и заметки.
//
// Границы (`codelab_ui/AGENTS.md` §2): виджет ничего не форматирует и не
// считает. Тон и тексты (`~$2.26`, `—`, `Couldn't load usage history.`)
// приходят готовыми и проверяются как есть; кнопка `Rebuild from log` без
// колбэка недоступна, а не скрыта (D2 п. 1).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _pane(CodeLabUsagePane pane) => FluentApp(
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SingleChildScrollView(child: pane),
  ),
);

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

const _cards = [
  CodeLabUsageCard(
    id: 'input',
    title: 'Input',
    value: '950',
    detail: 'cache read 400 · write 50',
  ),
  CodeLabUsageCard(id: 'output', title: 'Output', value: '300'),
  CodeLabUsageCard(
    id: 'cost',
    title: 'Cost',
    value: r'~$2.26',
    detail: 'agent sent no usage for some steps',
    tone: CodeLabTone.warning,
  ),
  CodeLabUsageCard(
    id: 'turns',
    title: 'Turns · steps',
    value: '2 · 3',
    detail: 'avg 1.5 steps per turn',
  ),
];

const _turns = [
  CodeLabUsageRow(
    id: '2',
    label: '2 · “Fix the build”',
    input: '130',
    output: '40',
    cost: r'$0.0041',
    running: true,
    note: 'subagents · 2 runs',
    children: [
      CodeLabUsageRow(
        id: '2-0',
        label: 'step 1 · Read lib/a.dart',
        input: '50',
        output: '10',
        cost: r'$0.001',
        hint: 'openai/gpt-5',
      ),
      CodeLabUsageRow(
        id: '2-1',
        label: 'step 2 · reply',
        input: '—',
        output: '—',
        cost: '—',
      ),
    ],
  ),
  CodeLabUsageRow(id: '1', label: '1', input: '—', output: '—', cost: '—'),
];

const _models = [
  CodeLabUsageRow(
    id: 'openai/gpt-5',
    label: 'openai / gpt-5',
    input: '950',
    output: '300',
    cost: r'$1.20',
  ),
  CodeLabUsageRow(
    id: 'subagents',
    label: 'Subagents',
    input: '10',
    output: '5',
    cost: '—',
    note: '2 runs',
  ),
];

CodeLabUsagePane _full({
  VoidCallback? onRebuild,
  VoidCallback? onExport,
  VoidCallback? onRetry,
  bool loading = false,
  bool refreshing = false,
  List<CodeLabUsageNote> notes = const [],
  List<CodeLabUsageRow> turns = _turns,
  List<CodeLabUsageRow> models = _models,
  bool showRebuild = true,
  bool showExport = true,
}) => CodeLabUsagePane(
  title: 'This session',
  cards: _cards,
  statusLine: 'Ledger: up to date · 12 records',
  turns: turns,
  models: models,
  loading: loading,
  refreshing: refreshing,
  notes: notes,
  showRebuild: showRebuild,
  showExport: showExport,
  onRebuild: onRebuild,
  onExport: onExport,
  onRetry: onRetry,
);

void main() {
  testWidgets('shows the header, the ledger status and the four cards as '
      'ready strings', (tester) async {
    await tester.pumpWidget(_pane(_full(onRebuild: () {}, onExport: () {})));

    expect(find.text('This session'), findsOneWidget);
    expect(
      _in('usage-ledger-status', find.text('Ledger: up to date · 12 records')),
      findsOneWidget,
    );
    expect(_in('usage-card-input', find.text('950')), findsOneWidget);
    expect(
      _in('usage-card-input', find.text('cache read 400 · write 50')),
      findsOneWidget,
    );
    expect(_in('usage-card-output', find.text('300')), findsOneWidget);
    expect(_in('usage-card-cost', find.text(r'~$2.26')), findsOneWidget);
    expect(
      _in('usage-card-cost', find.text('agent sent no usage for some steps')),
      findsOneWidget,
    );
    expect(_in('usage-card-turns', find.text('2 · 3')), findsOneWidget);
    expect(
      _in('usage-card-turns', find.text('avg 1.5 steps per turn')),
      findsOneWidget,
    );
  });

  testWidgets('the tone of a card comes from the data: a toned value is a '
      'badge, a neutral one is plain text', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-card-cost', find.byType(CodeLabBadge)), findsOneWidget);
    expect(_in('usage-card-input', find.byType(CodeLabBadge)), findsNothing);
  });

  testWidgets('a card without a second line shows no empty line', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-card-output', find.byType(CodeLabText)), findsWidgets);
    expect(
      _in('usage-card-output', find.textContaining('reasoning')),
      findsNothing,
    );
  });

  testWidgets('turns keep the order of the data; the running mark and the '
      'dashes are shown as given', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    final newer = tester.getTopLeft(find.byKey(const ValueKey('usage-turn-2')));
    final older = tester.getTopLeft(find.byKey(const ValueKey('usage-turn-1')));
    expect(newer.dy, lessThan(older.dy));
    expect(
      _in('usage-turn-2', find.text('2 · “Fix the build”')),
      findsOneWidget,
    );
    expect(_in('usage-turn-2', find.text('running')), findsOneWidget);
    expect(_in('usage-turn-1', find.text('running')), findsNothing);
    expect(_in('usage-turn-1', find.text('—')), findsNWidgets(3));
    expect(
      _in('usage-turn-2', find.text('subagents · 2 runs')),
      findsOneWidget,
    );
  });

  testWidgets('a turn expands to its steps on tap and collapses on the '
      'second tap', (tester) async {
    await tester.pumpWidget(_pane(_full()));
    expect(find.byKey(const ValueKey('usage-step-2-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-2-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-step-2-1')), findsOneWidget);
    expect(
      _in('usage-step-2-0', find.text('step 1 · Read lib/a.dart')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-2-0')), findsNothing);
  });

  testWidgets('the subagents line of an expanded turn goes after its steps '
      '(D2 item 4)', (tester) async {
    await tester.pumpWidget(_pane(_full()));
    final collapsed = tester.getTopLeft(find.text('subagents · 2 runs'));
    final turnTop = tester.getTopLeft(
      find.byKey(const ValueKey('usage-turn-2')),
    );
    expect(collapsed.dy, greaterThan(turnTop.dy));

    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    final note = tester.getTopLeft(find.text('subagents · 2 runs'));
    final lastStep = tester.getTopLeft(
      find.byKey(const ValueKey('usage-step-2-1')),
    );
    expect(find.text('subagents · 2 runs'), findsOneWidget);
    expect(note.dy, greaterThan(lastStep.dy));
  });

  testWidgets('the model of a step is the tooltip of its row', (tester) async {
    await tester.pumpWidget(_pane(_full()));
    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(
      _in('usage-step-2-0', find.byType(Tooltip)),
    );

    expect(tooltip.message, 'openai/gpt-5');
  });

  testWidgets('a turn without steps does not expand', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    await tester.tap(find.byKey(const ValueKey('usage-turn-1')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-1-0')), findsNothing);
  });

  testWidgets('models are numbered by position and carry the group note', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-model-0', find.text('openai / gpt-5')), findsOneWidget);
    expect(_in('usage-model-1', find.text('Subagents')), findsOneWidget);
    expect(_in('usage-model-1', find.text('2 runs')), findsOneWidget);
  });

  testWidgets('without a ledger yet an indicator replaces the tables', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pane(_full(loading: true, turns: const [], models: const [])),
    );

    expect(find.byKey(const ValueKey('usage-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsNothing);
    expect(find.byKey(const ValueKey('usage-model-0')), findsNothing);
  });

  testWidgets('refreshing keeps the old tables and shows the indicator in the '
      'header', (tester) async {
    await tester.pumpWidget(_pane(_full(refreshing: true)));

    expect(find.byKey(const ValueKey('usage-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsOneWidget);
  });

  testWidgets('no indicator when the journal is idle of work', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    expect(find.byKey(const ValueKey('usage-progress')), findsNothing);
  });

  testWidgets('a failure note shows the text and Retry, and the hint is '
      'its tooltip', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _pane(
        _full(
          onRetry: () => retries++,
          notes: const [
            CodeLabUsageNote(
              text: "Couldn't load usage history.",
              hint: '-32603',
              retryLabel: 'Retry',
            ),
          ],
        ),
      ),
    );

    expect(
      _in('usage-note', find.text("Couldn't load usage history.")),
      findsOneWidget,
    );
    expect(
      tester.widget<Tooltip>(_in('usage-note', find.byType(Tooltip))).message,
      '-32603',
    );
    await tester.tap(find.byKey(const ValueKey('usage-retry')));
    // Кнопка Fluent сбрасывает нажатие по таймеру 100 мс (как в
    // `codelab_molecules_test.dart`): без этого тест кончается с живым Timer.
    await tester.pump(const Duration(milliseconds: 100));

    expect(retries, 1);
  });

  testWidgets('the no-history note has no Retry action', (tester) async {
    await tester.pumpWidget(
      _pane(
        const CodeLabUsagePane(
          title: 'This session',
          cards: _cards,
          notes: [
            CodeLabUsageNote(
              text: 'This agent does not provide usage history.',
            ),
          ],
        ),
      ),
    );

    expect(
      _in(
        'usage-note',
        find.text('This agent does not provide usage history.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('usage-retry')), findsNothing);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsNothing);
  });

  testWidgets('Rebuild from log and Export CSV report taps', (tester) async {
    var rebuilds = 0;
    var exports = 0;
    await tester.pumpWidget(
      _pane(_full(onRebuild: () => rebuilds++, onExport: () => exports++)),
    );

    await tester.tap(find.byKey(const ValueKey('usage-rebuild')));
    await tester.tap(find.byKey(const ValueKey('usage-export')));
    // Таймер сброса нажатия кнопки Fluent, 100 мс.
    await tester.pump(const Duration(milliseconds: 100));

    expect(rebuilds, 1);
    expect(exports, 1);
    expect(find.text('Rebuild from log'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
  });

  testWidgets('a button without a callback is disabled, not hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    final rebuild = tester.widget<CodeLabButton>(
      find.byKey(const ValueKey('usage-rebuild')),
    );

    expect(rebuild.onPressed, isNull);
    expect(find.byKey(const ValueKey('usage-export')), findsOneWidget);
  });

  testWidgets('buttons the data does not offer are absent', (tester) async {
    await tester.pumpWidget(
      _pane(_full(showRebuild: false, showExport: false)),
    );

    expect(find.byKey(const ValueKey('usage-rebuild')), findsNothing);
    expect(find.byKey(const ValueKey('usage-export')), findsNothing);
  });

  // Ошибка ручной проверки PR #354: столбцы чисел были шириной 64 px, а
  // `maxLines: 1` без overflow молча резал `$0.00058` до `$0.0005` — пользователь
  // видел неверную сумму. Ширина столбца обязана определяться содержимым.
  group('числа в столбцах не обрезаются на ширине дока', () {
    const longValues = [r'$0.00058', r'~$123.45', r'$1234.56', '999.9k'];
    const wideTurns = [
      CodeLabUsageRow(
        id: 'w1',
        label:
            '12 · “A very long prompt that must wrap or shrink, not push'
            ' the numeric columns out of the dock”',
        input: '999.9k',
        output: '999.9k',
        cost: r'$0.00058',
        children: [
          CodeLabUsageRow(
            id: 'w1-0',
            label: 'step 1 · Read lib/a_very_long_file_name_indeed.dart',
            input: '999.9k',
            output: '999.9k',
            cost: r'~$123.45',
          ),
        ],
      ),
    ];
    const wideModels = [
      CodeLabUsageRow(
        id: 'm',
        label: 'openai / gpt-5-with-a-long-name',
        input: '999.9k',
        output: '999.9k',
        cost: r'$1234.56',
      ),
    ];

    testWidgets('значения целиком, без overflow, подпись переносится', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _pane(_full(turns: wideTurns, models: wideModels)),
      );
      await tester.tap(find.byKey(const ValueKey('usage-turn-w1')));
      await tester.pump();

      for (final value in [...longValues, r'$1234.56']) {
        for (final element in find.text(value).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '«$value» обрезано',
          );
          // Одна строка: текст не разломан посреди значения.
          expect(
            paragraph.size.height,
            lessThan(paragraph.text.style!.fontSize! * 2),
            reason: '«$value» перенесено',
          );
        }
      }
      expect(find.text(r'$0.00058'), findsOneWidget);
      expect(find.text(r'~$123.45'), findsOneWidget);
      expect(find.text(r'$1234.56'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('столбцы Input/Output/Cost выровнены между строками и шапкой', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_pane(_full(turns: wideTurns, models: const [])));
      await tester.tap(find.byKey(const ValueKey('usage-turn-w1')));
      await tester.pump();

      double right(Finder f) => tester.getTopRight(f.first).dx;
      // Левые края подписи `Cost` в шапке таблицы (последняя на экране, после
      // карточки) и значения в строке хода равны: столбец общий.
      expect(
        tester.getTopLeft(_in('usage-turn-w1', find.text(r'$0.00058'))).dx,
        tester.getTopLeft(find.text('Cost').last).dx,
      );
      expect(right(find.text('Cost')), lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });
  });

  group('Turn budget', () {
    // Красные тесты задачи 3.3 change `add-desktop-usage-pane`
    // (agent-workbench-ui «Бюджет хода в панели Usage»; design.md D9):
    // блок `Turn budget` между карточками и `Per turn`. Виджет ничего не
    // считает: заголовок, подписи, подсказки, тон и доля заполнения полосы
    // приходят готовыми (`codelab_ui/AGENTS.md` §2). Единственная «логика» —
    // раскладка: заполнение полосы ограничивается 100 % и тогда, когда
    // приложение прислало больше.
    //
    // Ключи (рабочие, при расхождении переименовать здесь и в заглушке):
    // блок `usage-budget`, заголовок `usage-budget-title`, строка
    // `usage-budget-<id>` (`steps`, `tokens`, `cost`, `time`), дорожка
    // `usage-budget-<id>-track`, заполнение `usage-budget-<id>-fill`,
    // пояснение под блоком `usage-budget-note`. Тон выше нейтрального
    // рисуется плашкой `CodeLabBadge` вокруг подписи — как у карточек.
    CodeLabUsageBudget budget({
      String title = 'This turn',
      List<CodeLabUsageBudgetRow>? rows,
    }) => CodeLabUsageBudget(
      title: title,
      rows:
          rows ??
          const [
            CodeLabUsageBudgetRow(
              id: 'steps',
              label: 'Steps',
              value: '3 / 50',
              fill: 0.06,
            ),
            CodeLabUsageBudgetRow(
              id: 'tokens',
              label: 'Tokens',
              value: '92.0k / 200.0k',
              fill: 0.46,
              hint: 'input + output, including subagents',
            ),
            CodeLabUsageBudgetRow(
              id: 'cost',
              label: 'Cost',
              value: r'$0.41 / $0.50',
              fill: 0.82,
              tone: CodeLabTone.warning,
            ),
            CodeLabUsageBudgetRow(
              id: 'time',
              label: 'Time',
              value: '3:00 / 10:00',
              fill: 0.3,
            ),
          ],
      footnote:
          'When a limit is hit, the turn stops at the next step boundary.',
    );

    Widget paneWith(CodeLabUsageBudget? value) => _pane(
      CodeLabUsagePane(
        title: 'This session',
        cards: _cards,
        turns: _turns,
        budget: value,
      ),
    );

    Finder row(String id) => find.byKey(ValueKey('usage-budget-$id'));

    testWidgets('показывает заголовок, подписи строк и пояснение из данных', (
      tester,
    ) async {
      await tester.pumpWidget(paneWith(budget()));

      expect(_in('usage-budget', find.text('This turn')), findsOneWidget);
      expect(find.byKey(const ValueKey('usage-budget-title')), findsOneWidget);
      for (final (id, label, value) in const [
        ('steps', 'Steps', '3 / 50'),
        ('tokens', 'Tokens', '92.0k / 200.0k'),
        ('cost', 'Cost', r'$0.41 / $0.50'),
        ('time', 'Time', '3:00 / 10:00'),
      ]) {
        expect(
          _in('usage-budget-$id', find.text(label)),
          findsOneWidget,
          reason: id,
        );
        expect(
          _in('usage-budget-$id', find.text(value)),
          findsOneWidget,
          reason: id,
        );
      }
      expect(
        _in(
          'usage-budget',
          find.text(
            'When a limit is hit, the turn stops at the next step boundary.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('usage-budget-note')), findsOneWidget);
    });

    testWidgets('заголовок `Last turn` берётся из данных как есть', (
      tester,
    ) async {
      await tester.pumpWidget(paneWith(budget(title: 'Last turn')));

      expect(_in('usage-budget', find.text('Last turn')), findsOneWidget);
      expect(find.text('This turn'), findsNothing);
    });

    testWidgets('строки только по присутствующим подполям, в порядке данных', (
      tester,
    ) async {
      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'steps',
                label: 'Steps',
                value: '3 / 50',
                fill: 0.06,
              ),
              CodeLabUsageBudgetRow(
                id: 'time',
                label: 'Time',
                value: '3:00 / 10:00',
                fill: 0.3,
              ),
            ],
          ),
        ),
      );

      expect(row('steps'), findsOneWidget);
      expect(row('time'), findsOneWidget);
      expect(row('tokens'), findsNothing);
      expect(row('cost'), findsNothing);
      expect(
        tester.getTopLeft(row('steps')).dy,
        lessThan(tester.getTopLeft(row('time')).dy),
      );
    });

    testWidgets('блок стоит между карточками и `Per turn`', (tester) async {
      await tester.pumpWidget(paneWith(budget()));

      final cards = tester.getTopLeft(
        find.byKey(const ValueKey('usage-card-turns')),
      );
      final block = tester.getTopLeft(
        find.byKey(const ValueKey('usage-budget')),
      );
      final perTurn = tester.getTopLeft(find.text('Per turn'));
      expect(block.dy, greaterThan(cards.dy));
      expect(block.dy, lessThan(perTurn.dy));
    });

    testWidgets('без бюджета блока нет', (tester) async {
      await tester.pumpWidget(paneWith(null));

      expect(find.byKey(const ValueKey('usage-budget')), findsNothing);
      expect(find.text('This turn'), findsNothing);
      expect(find.text('Last turn'), findsNothing);
    });

    testWidgets('заполнение полосы — доля из данных от ширины дорожки', (
      tester,
    ) async {
      await tester.pumpWidget(paneWith(budget()));

      double ratio(String id) {
        final track = tester.getSize(
          find.byKey(ValueKey('usage-budget-$id-track')),
        );
        final fill = tester.getSize(
          find.byKey(ValueKey('usage-budget-$id-fill')),
        );
        return fill.width / track.width;
      }

      expect(ratio('steps'), closeTo(0.06, 0.01));
      expect(ratio('tokens'), closeTo(0.46, 0.01));
      expect(ratio('cost'), closeTo(0.82, 0.01));
    });

    testWidgets('больше 100 %: полоса не шире дорожки, подпись — как пришла', (
      tester,
    ) async {
      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'cost',
                label: 'Cost',
                value: r'$0.52 / $0.50',
                fill: 1.4,
                tone: CodeLabTone.danger,
              ),
            ],
          ),
        ),
      );

      final track = tester.getSize(
        find.byKey(const ValueKey('usage-budget-cost-track')),
      );
      final fill = tester.getSize(
        find.byKey(const ValueKey('usage-budget-cost-fill')),
      );
      expect(fill.width, closeTo(track.width, 0.5));
      expect(
        _in('usage-budget-cost', find.text(r'$0.52 / $0.50')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('полная полоса при доле 1 и пустая при доле 0', (tester) async {
      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'cost',
                label: 'Cost',
                value: r'$0.00 / $0.00',
                fill: 1,
                tone: CodeLabTone.danger,
              ),
              CodeLabUsageBudgetRow(
                id: 'steps',
                label: 'Steps',
                value: '0 / 50',
                fill: 0,
              ),
            ],
          ),
        ),
      );

      final full = tester.getSize(
        find.byKey(const ValueKey('usage-budget-cost-fill')),
      );
      final fullTrack = tester.getSize(
        find.byKey(const ValueKey('usage-budget-cost-track')),
      );
      final empty = tester.getSize(
        find.byKey(const ValueKey('usage-budget-steps-fill')),
      );
      expect(full.width, closeTo(fullTrack.width, 0.5));
      expect(empty.width, 0);
    });

    testWidgets('тон из данных: warning и danger — плашка того же тона, '
        'нейтральная строка — без плашки', (tester) async {
      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'steps',
                label: 'Steps',
                value: '3 / 50',
                fill: 0.06,
              ),
              CodeLabUsageBudgetRow(
                id: 'tokens',
                label: 'Tokens',
                value: '170.0k / 200.0k',
                fill: 0.85,
                tone: CodeLabTone.warning,
              ),
              CodeLabUsageBudgetRow(
                id: 'cost',
                label: 'Cost',
                value: r'$0.52 / $0.50',
                fill: 1,
                tone: CodeLabTone.danger,
              ),
            ],
          ),
        ),
      );

      CodeLabBadge? badge(String id) => tester
          .widgetList<CodeLabBadge>(
            find.descendant(
              of: find.byKey(ValueKey('usage-budget-$id')),
              matching: find.byType(CodeLabBadge),
            ),
          )
          .firstOrNull;

      expect(badge('steps'), isNull);
      expect(badge('tokens')?.tone, CodeLabTone.warning);
      expect(badge('tokens')?.label, '170.0k / 200.0k');
      expect(badge('cost')?.tone, CodeLabTone.danger);
      expect(badge('cost')?.label, r'$0.52 / $0.50');
    });

    testWidgets('подсказка строки Tokens — в Tooltip, а строка без подсказки '
        'её не имеет', (tester) async {
      await tester.pumpWidget(paneWith(budget()));

      expect(
        _in(
          'usage-budget-tokens',
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                w.message == 'input + output, including subagents',
          ),
        ),
        findsOneWidget,
      );
      expect(_in('usage-budget-steps', find.byType(Tooltip)), findsNothing);
    });

    testWidgets('Cost без израсходованной суммы: подпись и пояснение строки '
        'приходят готовыми и без тона', (tester) async {
      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'cost',
                label: 'Cost',
                value: r'— / $0.50',
                fill: 0,
                note: 'not checked: price unknown',
              ),
            ],
          ),
        ),
      );

      expect(_in('usage-budget-cost', find.text(r'— / $0.50')), findsOneWidget);
      expect(
        _in('usage-budget-cost', find.text('not checked: price unknown')),
        findsOneWidget,
      );
      expect(_in('usage-budget-cost', find.byType(CodeLabBadge)), findsNothing);
    });

    testWidgets('смена данных (тик времени) обновляет подпись без смены '
        'остальных строк', (tester) async {
      await tester.pumpWidget(paneWith(budget()));
      expect(find.text('3:00 / 10:00'), findsOneWidget);

      await tester.pumpWidget(
        paneWith(
          budget(
            rows: const [
              CodeLabUsageBudgetRow(
                id: 'steps',
                label: 'Steps',
                value: '3 / 50',
                fill: 0.06,
              ),
              CodeLabUsageBudgetRow(
                id: 'time',
                label: 'Time',
                value: '3:05 / 10:00',
                fill: 0.31,
              ),
            ],
          ),
        ),
      );

      expect(find.text('3:00 / 10:00'), findsNothing);
      expect(
        _in('usage-budget-time', find.text('3:05 / 10:00')),
        findsOneWidget,
      );
      expect(_in('usage-budget-steps', find.text('3 / 50')), findsOneWidget);
    });
  });
}
