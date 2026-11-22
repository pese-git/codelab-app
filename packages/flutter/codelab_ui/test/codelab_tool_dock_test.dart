// Действия вкладки дока (change `redesign-protocol-pane`, D1, D12, D17): на
// узком доке (360 px) непомещающиеся действия уходят в меню «⋯», закреплённый
// переключатель (Trace) остаётся на виду, а активная вкладка не обрезается.
//
// Красный до правки кита: `CodeLabDockTab.actions` принимает готовые виджеты,
// модели `CodeLabDockAction` нет (ошибка компиляции — допустимый красный).
//
// Тестовый шрифт Ahem вдвое шире настоящих; масштаб текста 0.5 приближает
// метрики к реальным (как в тестах панели Protocol в app).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _moreHint = 'More actions';

void _realisticText(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = 0.5;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Док шириной [width] с вкладками [panes] (активна `protocol`) и четырьмя
/// действиями: закреплённый переключатель и три обычных.
Widget _dock({
  required double width,
  List<ToolPane> panes = const [
    ToolPane.plan,
    ToolPane.protocol,
    ToolPane.usage,
    ToolPane.files,
  ],
  List<String> log = const [],
  bool exportEnabled = true,
  bool ru = true,
}) {
  final labels = ru
      ? const ['Трассировка', 'Приостановить', 'Очистить', 'Экспорт…']
      : const ['Trace', 'Pause', 'Clear', 'Export…'];
  void note(String name) => log.add(name);
  return FluentApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 300,
        child: CodeLabToolDock(
          active: ToolPane.protocol,
          tabs: [
            for (final pane in panes)
              CodeLabDockTab(
                pane: pane,
                content: Text('${pane.name} body'),
                actions: pane == ToolPane.protocol
                    ? [
                        CodeLabDockAction(
                          label: labels[0],
                          pinned: true,
                          checked: false,
                          onPressed: () => note('trace'),
                        ),
                        CodeLabDockAction(
                          label: labels[1],
                          onPressed: () => note('pause'),
                        ),
                        CodeLabDockAction(
                          label: labels[2],
                          onPressed: () => note('clear'),
                        ),
                        CodeLabDockAction(
                          label: labels[3],
                          onPressed: exportEnabled
                              ? () => note('export')
                              : null,
                        ),
                      ]
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

Finder get _moreIcons => find.byIcon(FluentIcons.more);

/// «⋯» в строке вкладок: Fluent держит построенную, но невидимую кнопку и вне
/// строки (под ней), пока всё помещается, поэтому «видимая» — внутри строки
/// вкладок (верхние 60 px дока).
Finder _moreVisible(WidgetTester tester) {
  final visible = _moreIcons.evaluate().where(
    (e) => tester.getRect(find.byWidget(e.widget)).top < 60,
  );
  return visible.isEmpty
      ? find.byWidget(const SizedBox.shrink(key: ValueKey('none')))
      : find.byWidget(visible.first.widget);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_moreVisible(tester));
  await tester.pumpAndSettle();
}

void main() {
  group('действия на узком доке (360 px, русские подписи)', () {
    testWidgets('нет переполнения при 4 вкладках', (tester) async {
      _realisticText(tester);
      await tester.pumpWidget(_dock(width: 360));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('закреплённый переключатель виден и нажимается', (
      tester,
    ) async {
      _realisticText(tester);
      final log = <String>[];
      await tester.pumpWidget(_dock(width: 360, log: log));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Трассировка'));
      await tester.pumpAndSettle();

      expect(log, ['trace']);
      expect(
        tester.widget<ToggleButton>(find.byType(ToggleButton)).checked,
        isFalse,
      );
    });

    testWidgets('остальные действия доступны через «⋯», у кнопки есть '
        'подсказка', (tester) async {
      _realisticText(tester);
      final log = <String>[];
      await tester.pumpWidget(_dock(width: 360, log: log));
      await tester.pumpAndSettle();

      expect(_moreVisible(tester), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == _moreHint),
        findsOneWidget,
      );
      await _openMenu(tester);
      for (final label in ['Приостановить', 'Очистить', 'Экспорт…']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Экспорт…').last);
      await tester.pumpAndSettle();

      expect(log, ['export']);
    });

    testWidgets('недоступное действие (onPressed: null) в меню не '
        'срабатывает', (tester) async {
      _realisticText(tester);
      final log = <String>[];
      await tester.pumpWidget(
        _dock(width: 360, log: log, exportEnabled: false),
      );
      await tester.pumpAndSettle();

      await _openMenu(tester);
      await tester.tap(find.text('Экспорт…').last);
      await tester.pumpAndSettle();

      expect(log, isEmpty);
    });

    testWidgets('активная вкладка не обрезана действиями', (tester) async {
      _realisticText(tester);
      await tester.pumpWidget(_dock(width: 360));
      await tester.pumpAndSettle();

      final tab = tester.getRect(
        find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)),
      );
      expect(tab.left, greaterThanOrEqualTo(0));
      expect(tab.right, lessThanOrEqualTo(360 - 100));
    });

    testWidgets('горизонтальной прокрутки у строки действий нет', (
      tester,
    ) async {
      _realisticText(tester);
      await tester.pumpWidget(_dock(width: 360));
      await tester.pumpAndSettle();

      // Единственная горизонтальная прокрутка в строке — у вкладок.
      final horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((w) => w.scrollDirection == Axis.horizontal);
      expect(horizontal, hasLength(1));
    });
  });

  group('широкий док: все действия на виду без «⋯»', () {
    testWidgets('900 px, английские подписи', (tester) async {
      _realisticText(tester);
      await tester.pumpWidget(
        _dock(width: 900, ru: false, panes: const [ToolPane.protocol]),
      );
      await tester.pumpAndSettle();

      for (final label in ['Trace', 'Pause', 'Clear', 'Export…']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(_moreVisible(tester), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('вкладки без действий', () {
    testWidgets('у неактивной вкладки действий нет, у активной без actions '
        'вид прежний', (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CodeLabToolDock(
              active: ToolPane.plan,
              tabs: const [
                CodeLabDockTab(pane: ToolPane.plan, content: Text('plan')),
                CodeLabDockTab(
                  pane: ToolPane.protocol,
                  content: Text('protocol'),
                  actions: [CodeLabDockAction(label: 'Clear')],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Clear'), findsNothing);
      expect(_moreVisible(tester), findsNothing);
    });
  });
}
