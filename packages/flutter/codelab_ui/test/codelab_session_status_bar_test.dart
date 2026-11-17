// Красные тесты задачи 3.1 change `add-usage-extension`: виджет
// `CodeLabSessionStatusBar` (слой `molecules/`; design.md D11, D23 Т1;
// agent-workbench-ui «Строка статуса сессии под композером»: «Агент без
// расширения», «Контекст близко к пределу», «Цена неизвестна»; DSK-11).
//
// Отсутствующий пока API (файл не компилируется до задачи 3.10):
// `CodeLabSessionStatusBar(data:)`, `CodeLabSessionStatusData`
// (`modelLabel`, `modeLabel`, `usage`, `cost`, `context`, `busy`),
// `CodeLabStatusSegment` (`label`, `tooltip`, `tone`). Имена рабочие: при
// расхождении переименовать здесь, поведение не меняется.
//
// Границы (`codelab_ui/AGENTS.md` §2): виджет ничего не форматирует и не
// считает — подписи, подсказки и тон приходят готовыми. Проверяется только
// поведение: ключи, видимые подписи, тон, подсказка, индикатор; сегмент с
// тоном не `neutral` рисуется как `CodeLabBadge` (тон не передаётся одним
// цветом, §5), нейтральный — обычным текстом.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _usageKey = ValueKey('status-bar-usage');
const _costKey = ValueKey('status-bar-cost');
const _contextKey = ValueKey('status-bar-context');

Widget _bar(CodeLabSessionStatusData data) => FluentApp(
  home: ScaffoldPage(
    content: Align(
      alignment: Alignment.bottomCenter,
      child: CodeLabSessionStatusBar(data: data),
    ),
  ),
);

Finder _in(ValueKey<String> key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

String? _tooltipOf(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<Tooltip>(_in(key, find.byType(Tooltip))).message;

void main() {
  testWidgets('shows model, mode and the ready segment labels', (tester) async {
    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          modelLabel: 'GPT-5',
          modeLabel: 'Standard',
          usage: CodeLabStatusSegment(label: '12.3k → 1.2k'),
          cost: CodeLabStatusSegment(label: r'$0.0041 · session $1.20'),
          context: CodeLabStatusSegment(label: '79% context'),
        ),
      ),
    );

    expect(find.text('GPT-5'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(_in(_usageKey, find.text('12.3k → 1.2k')), findsOneWidget);
    expect(
      _in(_costKey, find.text(r'$0.0041 · session $1.20')),
      findsOneWidget,
    );
    expect(_in(_contextKey, find.text('79% context')), findsOneWidget);
    // Нейтральный сегмент — не плашка тона.
    expect(_in(_contextKey, find.byType(CodeLabBadge)), findsNothing);
  });

  testWidgets('the tone of a segment comes from the data, not from the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          context: CodeLabStatusSegment(
            label: '85% context',
            tone: CodeLabTone.warning,
          ),
        ),
      ),
    );

    final badge = tester.widget<CodeLabBadge>(
      _in(_contextKey, find.byType(CodeLabBadge)),
    );
    expect(badge.label, '85% context');
    expect(badge.tone, CodeLabTone.warning);

    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          context: CodeLabStatusSegment(
            label: '96% context',
            tone: CodeLabTone.danger,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<CodeLabBadge>(_in(_contextKey, find.byType(CodeLabBadge)))
          .tone,
      CodeLabTone.danger,
    );
  });

  testWidgets('unknown usage: «usage: —» with a hint and no other segments', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          modelLabel: 'GPT-5',
          usage: CodeLabStatusSegment(
            label: 'usage: —',
            tooltip: 'agent does not report usage',
          ),
        ),
      ),
    );

    expect(_in(_usageKey, find.text('usage: —')), findsOneWidget);
    expect(_tooltipOf(tester, _usageKey), 'agent does not report usage');
    expect(find.byKey(_costKey), findsNothing);
    expect(find.byKey(_contextKey), findsNothing);
    // DSK-11: на строке нет нулей на месте неизвестного.
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('unknown price: «—» with the hint «price unknown», not \$0', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          usage: CodeLabStatusSegment(label: '165 → 30'),
          cost: CodeLabStatusSegment(label: '—', tooltip: 'price unknown'),
        ),
      ),
    );

    expect(_in(_costKey, find.text('—')), findsOneWidget);
    expect(_tooltipOf(tester, _costKey), 'price unknown');
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('the usage hint is shown as given (five counters from the app)', (
    tester,
  ) async {
    const hint = 'input 120 · output 30 · cache read 40 · cache write 5';
    await tester.pumpWidget(
      _bar(
        const CodeLabSessionStatusData(
          usage: CodeLabStatusSegment(label: '165 → 30', tooltip: hint),
        ),
      ),
    );

    expect(_tooltipOf(tester, _usageKey), hint);
  });

  testWidgets('busy shows the progress indicator in place of the turn tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(const CodeLabSessionStatusData(modelLabel: 'GPT-5', busy: true)),
    );

    expect(find.byType(CodeLabProgressIndicator), findsOneWidget);
    expect(find.byKey(_usageKey), findsNothing);
    expect(find.byKey(_costKey), findsNothing);

    await tester.pumpWidget(
      _bar(const CodeLabSessionStatusData(modelLabel: 'GPT-5')),
    );
    expect(find.byType(CodeLabProgressIndicator), findsNothing);
  });

  testWidgets('absent segments are not drawn (no empty keys)', (tester) async {
    await tester.pumpWidget(
      _bar(const CodeLabSessionStatusData(modelLabel: 'GPT-5')),
    );

    expect(find.byKey(_usageKey), findsNothing);
    expect(find.byKey(_costKey), findsNothing);
    expect(find.byKey(_contextKey), findsNothing);
  });

  test('data compares by value', () {
    const a = CodeLabSessionStatusData(
      modelLabel: 'm',
      usage: CodeLabStatusSegment(label: 'u', tooltip: 't'),
      busy: true,
    );
    const b = CodeLabSessionStatusData(
      modelLabel: 'm',
      usage: CodeLabStatusSegment(label: 'u', tooltip: 't'),
      busy: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const CodeLabSessionStatusData(modelLabel: 'm')));
  });
}
