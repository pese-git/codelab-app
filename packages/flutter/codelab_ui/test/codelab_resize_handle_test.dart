// Красные тесты задачи 3.1 change `redesign-protocol-pane`: ось
// `CodeLabResizeHandle.axis` (design.md D12; spec agent-workbench-ui «Панель
// Protocol: виды Frames и Log», сценарий «Разделитель ограничен»).
//
// Красный до задачи 3.2: у `CodeLabResizeHandle` нет параметра `axis`
// (ошибка компиляции — допустимый красный).
//
// Договорённость об имени оси: `axis` — направление самой линии разделителя.
// Прежний разделитель — вертикальная линия между колонками (`Axis.vertical`,
// курсор `resizeColumn`, `onDelta` по `dx`, по умолчанию); новый —
// горизонтальная линия между таблицей и панелью выбранного
// (`Axis.horizontal`, курсор `resizeRow`, `onDelta` по `dy`).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _handle({
  Axis? axis,
  required ValueChanged<double> onDelta,
  VoidCallback? onDragEnd,
}) => FluentApp(
  home: Center(
    child: SizedBox(
      width: 200,
      height: 200,
      // `Align` ослабляет жёсткие ограничения `SizedBox`: иначе размер
      // разделителя нельзя измерить.
      child: Align(
        child: axis == null
            ? CodeLabResizeHandle(onDelta: onDelta, onDragEnd: onDragEnd)
            : CodeLabResizeHandle(
                axis: axis,
                onDelta: onDelta,
                onDragEnd: onDragEnd,
              ),
      ),
    ),
  ),
);

/// Курсор ближайшего к разделителю `MouseRegion`.
MouseCursor _cursor(WidgetTester tester) {
  final region = tester.widget<MouseRegion>(
    find
        .descendant(
          of: find.byType(CodeLabResizeHandle),
          matching: find.byType(MouseRegion),
        )
        .first,
  );
  return region.cursor;
}

void main() {
  group('CodeLabResizeHandle.axis', () {
    testWidgets('по умолчанию вертикальная ось: курсор колонки и dx', (
      tester,
    ) async {
      final deltas = <double>[];
      await tester.pumpWidget(_handle(onDelta: deltas.add));

      expect(_cursor(tester), SystemMouseCursors.resizeColumn);

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(12, 0));
      expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(12, 0.5));
    });

    testWidgets('Axis.vertical совпадает с поведением по умолчанию', (
      tester,
    ) async {
      final deltas = <double>[];
      await tester.pumpWidget(
        _handle(axis: Axis.vertical, onDelta: deltas.add),
      );

      expect(_cursor(tester), SystemMouseCursors.resizeColumn);
    });

    testWidgets('горизонтальная ось: курсор строки', (tester) async {
      await tester.pumpWidget(_handle(axis: Axis.horizontal, onDelta: (_) {}));

      expect(_cursor(tester), SystemMouseCursors.resizeRow);
    });

    testWidgets('горизонтальная ось: onDelta получает смещение по вертикали', (
      tester,
    ) async {
      final deltas = <double>[];
      await tester.pumpWidget(
        _handle(axis: Axis.horizontal, onDelta: deltas.add),
      );

      // Горизонтальное движение не должно попадать в дельту.
      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, 30));
      expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(30, 0.5));

      deltas.clear();
      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, -10));
      expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(-10, 0.5));
    });

    testWidgets('горизонтальная ось: dx не попадает в onDelta', (tester) async {
      final deltas = <double>[];
      await tester.pumpWidget(
        _handle(axis: Axis.horizontal, onDelta: deltas.add),
      );

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(25, 0));
      expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(0, 0.001));
    });

    testWidgets('горизонтальная ось: onDragEnd вызывается по окончании жеста', (
      tester,
    ) async {
      var ended = 0;
      await tester.pumpWidget(
        _handle(
          axis: Axis.horizontal,
          onDelta: (_) {},
          onDragEnd: () => ended++,
        ),
      );

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, 20));
      expect(ended, 1);
    });

    testWidgets('горизонтальная ось: полоса тонкая по высоте и во всю ширину', (
      tester,
    ) async {
      await tester.pumpWidget(_handle(axis: Axis.horizontal, onDelta: (_) {}));

      final size = tester.getSize(find.byType(CodeLabResizeHandle));
      // Цель нажатия — `width` (8 по умолчанию) по высоте; по ширине — вся.
      expect(size.height, 8);
      expect(size.width, 200);
    });
  });
}
