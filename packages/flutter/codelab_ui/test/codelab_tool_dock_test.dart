// Красные тесты задачи 3.1 change `redesign-protocol-pane`: поле
// `CodeLabDockTab.actions` дока (design.md D1, D12; spec agent-workbench-ui
// «Панель Protocol: виды Frames и Log», сценарий «Действия только у активной
// вкладки Protocol»).
//
// Красный до задачи 3.2: у `CodeLabDockTab` ещё нет параметра `actions`
// (ошибка компиляции — допустимый красный).
//
// Границы (`codelab_ui/AGENTS.md` §2): док ничего не знает о действиях —
// хост передаёт готовые виджеты, кит только решает, где и когда их показать.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _protocolActions = ValueKey('protocol-actions');
const _planActions = ValueKey('plan-actions');

Widget _dock({required ToolPane active, bool withActions = true}) => FluentApp(
  home: SizedBox(
    width: 600,
    height: 300,
    child: CodeLabToolDock(
      active: active,
      tabs: [
        CodeLabDockTab(
          pane: ToolPane.plan,
          content: const Text('plan body'),
          actions: withActions
              ? const [SizedBox(key: _planActions, width: 20, height: 20)]
              : null,
        ),
        CodeLabDockTab(
          pane: ToolPane.protocol,
          content: const Text('protocol body'),
          actions: withActions
              ? const [
                  Text('Pause'),
                  Text('Clear'),
                  SizedBox(key: _protocolActions, width: 20, height: 20),
                ]
              : null,
        ),
      ],
    ),
  ),
);

void main() {
  group('CodeLabDockTab.actions', () {
    testWidgets('действия активной вкладки видны', (tester) async {
      await tester.pumpWidget(_dock(active: ToolPane.protocol));

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.byKey(_protocolActions), findsOneWidget);
    });

    testWidgets('действия стоят в строке вкладок справа от вкладок', (
      tester,
    ) async {
      await tester.pumpWidget(_dock(active: ToolPane.protocol));

      final lastTab = tester.getRect(
        find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)),
      );
      final action = tester.getRect(find.byKey(_protocolActions));
      final content = tester.getRect(find.text('protocol body'));

      expect(action.left, greaterThanOrEqualTo(lastTab.right));
      // Строка вкладок над содержимым панели, а не внутри него.
      expect(action.bottom, lessThanOrEqualTo(content.top));
      // Действия прижаты к правому краю дока (док шириной 600).
      expect(action.right, greaterThan(500));
    });

    testWidgets('у неактивной вкладки действий нет', (tester) async {
      await tester.pumpWidget(_dock(active: ToolPane.plan));

      expect(find.byKey(_planActions), findsOneWidget);
      expect(find.byKey(_protocolActions), findsNothing);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('переключение вкладки меняет набор действий', (tester) async {
      await tester.pumpWidget(_dock(active: ToolPane.protocol));
      expect(find.byKey(_protocolActions), findsOneWidget);

      await tester.pumpWidget(_dock(active: ToolPane.plan));
      expect(find.byKey(_protocolActions), findsNothing);
      expect(find.byKey(_planActions), findsOneWidget);
    });

    testWidgets('без actions вид дока прежний: вкладки и содержимое', (
      tester,
    ) async {
      await tester.pumpWidget(
        _dock(active: ToolPane.protocol, withActions: false),
      );

      expect(find.byKey(CodeLabToolDock.tabKey(ToolPane.plan)), findsOneWidget);
      expect(
        find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)),
        findsOneWidget,
      );
      expect(find.text('protocol body'), findsOneWidget);
      expect(find.byKey(_protocolActions), findsNothing);
    });

    testWidgets('кнопки действий нажимаются, не переключая вкладку', (
      tester,
    ) async {
      var pressed = 0;
      final selected = <ToolPane>[];
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 600,
            height: 300,
            child: CodeLabToolDock(
              active: ToolPane.protocol,
              onSelected: selected.add,
              tabs: [
                CodeLabDockTab(
                  pane: ToolPane.protocol,
                  content: const Text('protocol body'),
                  actions: [
                    Button(
                      key: const ValueKey('pause'),
                      onPressed: () => pressed++,
                      child: const Text('Pause'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pumpAndSettle();

      expect(pressed, 1);
      expect(selected, isEmpty);
    });
  });

  // Док по умолчанию в app — 360 px (`kDockDefaultWidth`): действия вкладки
  // Protocol (четыре кнопки, в русском интерфейсе длинные подписи) должны
  // помещаться без переполнения строки вкладок — сжиматься и прокручиваться
  // (change `redesign-protocol-pane`, D1, D12). Переполнение `RenderFlex`
  // тест Flutter считает ошибкой, поэтому отдельных проверок не нужно.
  group('действия в доке шириной 360 px', () {
    Widget narrowDock(List<String> labels) => FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 360,
          height: 300,
          child: CodeLabToolDock(
            active: ToolPane.protocol,
            tabs: [
              CodeLabDockTab(
                pane: ToolPane.protocol,
                content: const Text('protocol body'),
                actions: [
                  for (final label in labels)
                    Button(onPressed: () {}, child: Text(label)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('английские подписи: без переполнения', (tester) async {
      await tester.pumpWidget(
        narrowDock(const ['Trace', 'Pause', 'Clear', 'Export…']),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Export…'), findsOneWidget);
    });

    testWidgets('длинные русские подписи: без переполнения, все кнопки в '
        'дереве и доступны прокруткой', (tester) async {
      await tester.pumpWidget(
        narrowDock(const [
          'Трассировка',
          'Приостановить',
          'Очистить',
          'Экспорт…',
        ]),
      );

      expect(tester.takeException(), isNull);
      for (final label in ['Трассировка', 'Приостановить', 'Очистить']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Вкладка остаётся видимой в пределах дока.
      final tab = tester.getRect(
        find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)),
      );
      expect(tab.right, lessThanOrEqualTo(360));
      // Строка вкладок не шире дока, а действия не вылезают за его правый край.
      final actions = tester.getRect(find.text('Трассировка'));
      expect(actions.left, lessThan(360));
    });

    testWidgets('последняя кнопка достижима прокруткой строки действий', (
      tester,
    ) async {
      await tester.pumpWidget(
        narrowDock(const [
          'Трассировка',
          'Приостановить',
          'Очистить',
          'Экспорт…',
        ]),
      );

      await tester.ensureVisible(find.text('Экспорт…'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('Экспорт…')).right,
        lessThanOrEqualTo(360),
      );
    });
  });
}
