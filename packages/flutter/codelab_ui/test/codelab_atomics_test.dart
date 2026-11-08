import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _dialogTitleTests();
  _monospaceBlockTests();
  testWidgets(
    'CodeLabResizeHandle reports the total drag distance via onDelta',
    (tester) async {
      final deltas = <double>[];
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            height: 400,
            child: CodeLabResizeHandle(onDelta: deltas.add),
          ),
        ),
      );

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(24, 0));

      expect(deltas, isNotEmpty);
      expect(deltas.fold(0.0, (sum, dx) => sum + dx), closeTo(24, 0.01));
    },
  );

  testWidgets(
    'CodeLabResizeHandle calls onDragEnd once the gesture completes',
    (tester) async {
      var dragEndCalls = 0;
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            height: 400,
            child: CodeLabResizeHandle(
              onDelta: (_) {},
              onDragEnd: () => dragEndCalls++,
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CodeLabResizeHandle)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      expect(dragEndCalls, 0);

      await gesture.up();
      await tester.pump();
      expect(dragEndCalls, 1);
    },
  );

  testWidgets('CodeLabResizeHandle shows a resize cursor', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          height: 400,
          child: CodeLabResizeHandle(onDelta: (_) {}),
        ),
      ),
    );

    final mouseRegion = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byType(CodeLabResizeHandle),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(mouseRegion.cursor, SystemMouseCursors.resizeColumn);
  });
}

void _dialogTitleTests() {
  testWidgets('CodeLabDialogTitle is subtitle: 20 px, weight 600', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(home: const Center(child: CodeLabDialogTitle('Title'))),
    );

    final text = tester.widget<Text>(find.text('Title'));
    expect(text.style?.fontSize, 20);
    expect(text.style?.fontWeight, FontWeight.w600);
  });
}

/// `CodeLabMonospaceBlock` (задача 5.6 change `add-provider-setup-ui`; D19):
/// моноширинный блок ответа `/mcp list` — без разбора, с переносом и
/// выделением. Красный тест: атома ещё нет (реализация — задача 5.9).
///
/// Ожидаемый API: `CodeLabMonospaceBlock(String data, {Key? key})`. Блок
/// рисует текст `SelectableText` в стиле роли `CodeLabTextRole.mono`
/// (`CodeLabText.styleOf`), текст не меняет и не разбирает.
void _monospaceBlockTests() {
  const reply =
      'github   connected   42 tools\n'
      'postgres failed      ECONNREFUSED 127.0.0.1:5432';

  Future<void> pumpBlock(WidgetTester tester, String data, double width) =>
      tester.pumpWidget(
        FluentApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: CodeLabMonospaceBlock(data)),
          ),
        ),
      );

  testWidgets('CodeLabMonospaceBlock shows the text as is in the mono role', (
    tester,
  ) async {
    await pumpBlock(tester, reply, 600);

    final selectable = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(CodeLabMonospaceBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(selectable.data, reply);
    final mono = CodeLabText.styleOf(
      tester.element(find.byType(CodeLabMonospaceBlock)),
      CodeLabTextRole.mono,
    )!;
    expect(selectable.style?.fontFamily, mono.fontFamily);
    expect(selectable.style?.fontSize, mono.fontSize);
  });

  testWidgets('CodeLabMonospaceBlock keeps line breaks', (tester) async {
    await pumpBlock(tester, 'one', 600);
    final single = tester.getSize(find.byType(CodeLabMonospaceBlock)).height;

    await pumpBlock(tester, 'one\ntwo\nthree', 600);
    final triple = tester.getSize(find.byType(CodeLabMonospaceBlock)).height;

    expect(triple, greaterThan(single));
  });

  testWidgets('CodeLabMonospaceBlock wraps a long line instead of '
      'overflowing', (tester) async {
    const long =
        'postgres failed ECONNREFUSED 127.0.0.1:5432 and the next attempt '
        'is in 24 seconds';
    await pumpBlock(tester, long, 800);
    final wide = tester.getSize(find.byType(CodeLabMonospaceBlock));

    await pumpBlock(tester, long, 160);
    final narrow = tester.getSize(find.byType(CodeLabMonospaceBlock));

    expect(tester.takeException(), isNull);
    expect(narrow.width, lessThanOrEqualTo(160));
    expect(narrow.height, greaterThan(wide.height));
  });

  testWidgets('CodeLabMonospaceBlock text can be selected', (tester) async {
    await pumpBlock(tester, 'github connected', 600);

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.enableInteractiveSelection, isTrue);
    await tester.tap(find.byType(SelectableText));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
