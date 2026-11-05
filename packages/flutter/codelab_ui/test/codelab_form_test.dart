// Виджеты форм `CodeLabFormRow`, `CodeLabFormNote` и
// `CodeLabSegmentedControl` (задача 3.8 change `add-app-settings-shell`;
// D16, D20; макет `docs/design/claude-design/AddProfile.dc.html`, классы
// `.ap-form`, `.ap-hint`, `.ap-err`, `.ap-seg`).
//
// Проверяется поведение и раскладка, общая для всех строк формы, а не
// пиксели отдельных виджетов.

import 'dart:ui' show Tristate;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => FluentApp(
  home: Center(child: SizedBox(width: 560, child: child)),
);

void main() {
  group('CodeLabForm', () {
    testWidgets('stacks the rows with the 10 px gap of the mockup', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const CodeLabForm(
            children: [
              SizedBox(key: ValueKey('r1'), height: 20),
              SizedBox(key: ValueKey('r2'), height: 30),
              SizedBox(key: ValueKey('r3'), height: 20),
            ],
          ),
        ),
      );

      final first = tester.getRect(find.byKey(const ValueKey('r1')));
      final second = tester.getRect(find.byKey(const ValueKey('r2')));
      final third = tester.getRect(find.byKey(const ValueKey('r3')));
      expect(second.top - first.bottom, 10);
      expect(third.top - second.bottom, 10);
      expect(first.width, 560);
    });

    testWidgets('an empty form renders nothing', (tester) async {
      await tester.pumpWidget(_app(const CodeLabForm(children: [])));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(CodeLabForm)).height, 0);
    });
  });

  group('CodeLabFormRow', () {
    testWidgets('puts the label in a fixed column and every control in the '
        'same column to its right', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CodeLabFormRow(
                label: 'Name',
                notes: [CodeLabFormNote('A hint')],
                child: SizedBox(key: ValueKey('first'), height: 32),
              ),
              CodeLabFormRow(
                label: 'Command',
                child: SizedBox(key: ValueKey('second'), height: 32),
              ),
            ],
          ),
        ),
      );

      final first = tester.getTopLeft(find.byKey(const ValueKey('first')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('second')));
      final label = tester.getTopLeft(find.text('Name'));
      expect(first.dx, second.dx);
      expect(first.dx - label.dx, 132 + 14);
      expect(
        tester.getSize(find.byKey(const ValueKey('first'))).width,
        560 - 132 - 14,
      );
    });

    testWidgets('shows the notes below the control, in order', (tester) async {
      await tester.pumpWidget(
        _app(
          const CodeLabFormRow(
            label: 'URL',
            notes: [
              CodeLabFormNote('First'),
              CodeLabFormNote('Second', tone: CodeLabFormNoteTone.error),
            ],
            child: SizedBox(key: ValueKey('control'), height: 32),
          ),
        ),
      );

      final control = tester.getBottomLeft(
        find.byKey(const ValueKey('control')),
      );
      final first = tester.getTopLeft(find.text('First'));
      final second = tester.getTopLeft(find.text('Second'));
      expect(first.dy, greaterThanOrEqualTo(control.dy));
      expect(second.dy, greaterThan(first.dy));
    });
  });

  group('CodeLabFormNote', () {
    testWidgets('errors and warnings differ in colour from a hint and the '
        'error is announced as an alert', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              CodeLabFormNote('hint text'),
              CodeLabFormNote('error text', tone: CodeLabFormNoteTone.error),
              CodeLabFormNote(
                'warning text',
                tone: CodeLabFormNoteTone.warning,
              ),
            ],
          ),
        ),
      );

      Color? colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('error text'), isNot(colorOf('hint text')));
      expect(colorOf('warning text'), isNot(colorOf('hint text')));
      expect(colorOf('warning text'), isNot(colorOf('error text')));
      expect(
        tester
            .getSemantics(find.text('error text'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
    });
  });

  group('CodeLabSegmentedControl', () {
    testWidgets('shows all options, marks the selected one and reports a '
        'tap on another', (tester) async {
      String? picked;
      await tester.pumpWidget(
        _app(
          CodeLabSegmentedControl<String>(
            value: 'a',
            semanticLabel: 'Profile type',
            options: const [
              CodeLabSegment(
                value: 'a',
                label: 'Local stdio',
                key: ValueKey('seg-a'),
              ),
              CodeLabSegment(
                value: 'b',
                label: 'WebSocket',
                key: ValueKey('seg-b'),
              ),
            ],
            onChanged: (value) => picked = value,
          ),
        ),
      );

      expect(find.text('Local stdio'), findsOneWidget);
      expect(find.text('WebSocket'), findsOneWidget);
      Tristate selected(String key) => tester
          .getSemantics(find.byKey(ValueKey(key)))
          .flagsCollection
          .isSelected;
      expect(selected('seg-a'), Tristate.isTrue);
      expect(selected('seg-b'), Tristate.isFalse);

      await tester.tap(find.byKey(const ValueKey('seg-a')));
      expect(picked, isNull, reason: 'the selected option does not report');

      await tester.tap(find.byKey(const ValueKey('seg-b')));
      // Нажатие оставляет таймер распознавателя жестов.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(picked, 'b');
    });
  });
}
