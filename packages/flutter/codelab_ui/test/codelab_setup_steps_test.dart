// Тесты `CodeLabSetupSteps` (задача 3.1 change `add-app-onboarding`; design.md
// D12; артборды `Onboarding*`): горизонтальная строка шагов — кружок с номером
// или `✓` и подпись; текущий шаг полужирный и с рамкой акцента; строка
// переносится по ширине и объявляет текущий шаг экранному диктору.
//
// Красные по причине компиляции: `CodeLabSetupSteps` появляется в задаче 3.2.
//
// Контракт молекулы (принят при реализации 3.2): `CodeLabSetupSteps({steps,
// current, done = const {}})` — [steps] подписи, [current] индекс текущего,
// [done] индексы с отметкой (в том числе пропущенный шаг, D4). Молекула только
// рисует: логики onboarding в ней нет (AGENTS.md §5).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _steps = [
  'What CodeLab does',
  'Permissions',
  'Choose a model',
  'Privacy',
];

void main() {
  Future<void> pumpSteps(
    WidgetTester tester, {
    required int current,
    Set<int> done = const {},
    List<String> steps = _steps,
    double width = 900,
  }) => tester.pumpWidget(
    FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CodeLabSetupSteps(steps: steps, current: current, done: done),
        ),
      ),
    ),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  testWidgets('показывает все подписи слева направо', (tester) async {
    await pumpSteps(tester, current: 0);

    final xs = [
      for (final label in _steps) tester.getTopLeft(find.text(label)).dx,
    ];
    expect(xs, [...xs]..sort());
    expect(xs.toSet(), hasLength(_steps.length));
  });

  testWidgets('непройденные шаги — с номером, пройденные — с ✓', (
    tester,
  ) async {
    await pumpSteps(tester, current: 2, done: {0, 1});

    expect(find.text('✓'), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget, reason: 'текущий шаг с номером');
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('пропущенный шаг показывается отмеченным, как пройденный', (
    tester,
  ) async {
    // Шаг 3 пропущен (D4), текущий — 4: отмечены 1, 2 и 3.
    await pumpSteps(tester, current: 3, done: {0, 1, 2});

    expect(find.text('✓'), findsNWidgets(3));
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('только текущая подпись полужирная и основного цвета', (
    tester,
  ) async {
    await pumpSteps(tester, current: 1, done: {0});

    final theme = FluentTheme.of(
      tester.element(find.byType(CodeLabSetupSteps)),
    );
    final current = styleOf(tester, 'Permissions');
    expect(current.fontWeight, FontWeight.w600);
    expect(current.color, theme.resources.textFillColorPrimary);
    for (final other in ['What CodeLab does', 'Choose a model', 'Privacy']) {
      final style = styleOf(tester, other);
      expect(style.fontWeight, isNot(FontWeight.w600), reason: other);
      expect(
        style.color,
        theme.resources.textFillColorSecondary,
        reason: other,
      );
    }
  });

  testWidgets('текущий шаг выделен рамкой акцента, остальные — нет', (
    tester,
  ) async {
    await pumpSteps(tester, current: 1);

    final theme = FluentTheme.of(
      tester.element(find.byType(CodeLabSetupSteps)),
    );
    Border? borderOf(String number) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text(number),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).border as Border?;
    }

    expect(borderOf('2')?.top.color, theme.accentColor.normal);
    expect(borderOf('1')?.top.color, isNot(theme.accentColor.normal));
  });

  testWidgets('объявляет текущий шаг экранному диктору', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSteps(tester, current: 2, done: {0, 1});

    expect(
      tester.getSemantics(find.text('Choose a model')),
      matchesSemantics(
        label: 'Choose a model',
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Permissions')),
      isNot(matchesSemantics(isSelected: true, hasSelectedState: true)),
    );
    handle.dispose();
  });

  testWidgets('переносится на следующую строку при малой ширине', (
    tester,
  ) async {
    await pumpSteps(tester, current: 1, width: 260);

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.text('What CodeLab does'));
    final last = tester.getTopLeft(find.text('Privacy'));
    expect(last.dy, greaterThan(first.dy));
  });

  testWidgets('пустой список и индекс вне диапазона не падают', (tester) async {
    await pumpSteps(tester, current: 0, steps: const []);
    expect(tester.takeException(), isNull);

    await pumpSteps(tester, current: 9);
    expect(tester.takeException(), isNull);
    expect(styleOf(tester, 'Privacy').fontWeight, isNot(FontWeight.w600));
  });
}
