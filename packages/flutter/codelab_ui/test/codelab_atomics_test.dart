import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
