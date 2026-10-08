import 'package:codelab_app/features/workbench/presentation/widgets/debug_log_pane.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_flutter/structured_log_flutter.dart';

LogBuffer _buffer({int entries = 0}) {
  final buffer = LogBuffer();
  for (var i = 0; i < entries; i++) {
    buffer.capture({
      'event': 'event $i',
      'level': 'info',
      'category': i.isEven ? 'application' : 'protocol',
      'timestamp': '2026-01-01T00:00:00.000',
    }, LogLevel.info);
  }
  return buffer;
}

Widget _host(double width, double height, LogBuffer buffer) => FluentApp(
  key: UniqueKey(),
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: WorkbenchDebugLogPane(logBuffer: buffer, onExpand: () {}),
    ),
  ),
);

/// Pumps [widget] and returns the vertical ("on the bottom") overflow errors
/// reported while laying it out. Horizontal overflows are deliberately not
/// counted: they come from `structured_log_fluent`'s toolbar at a few
/// specific widths and are a separate matter from this panel's height.
Future<List<String>> _verticalOverflows(
  WidgetTester tester,
  Widget widget,
) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') && text.contains('on the bottom')) {
      overflows.add(text.split('\n').first);
    }
  };
  addTearDown(() => FlutterError.onError = previous);

  await tester.pumpWidget(widget);
  await tester.pump();
  FlutterError.onError = previous;
  return overflows;
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('never overflows vertically, however short the panel gets', (
    tester,
  ) async {
    for (final width in [262.0, 320.0, 450.0, 518.0]) {
      for (final height in [20.0, 60.0, 100.0, 140.0]) {
        expect(
          await _verticalOverflows(tester, _host(width, height, _buffer())),
          isEmpty,
          reason: '${width}x$height',
        );
      }
    }
  });

  testWidgets(
    'kDebugLogPaneMinHeight is enough for the real FluentLogViewer at every '
    'width the pane can have (guards against a newer package needing more)',
    (tester) async {
      for (final width in [262.0, 320.0, 450.0, 518.0]) {
        for (final entries in [0, 3]) {
          expect(
            await _verticalOverflows(
              tester,
              _host(width, kDebugLogPaneMinHeight, _buffer(entries: entries)),
            ),
            isEmpty,
            reason: '${width}px wide, $entries entries',
          );
        }
      }
    },
  );

  ScrollableState outerScrollable(WidgetTester tester) => tester.state(
    find
        .descendant(
          of: find.byType(WorkbenchDebugLogPane),
          matching: find.byType(Scrollable),
        )
        .first,
  );

  testWidgets('scrolls only when the panel is shorter than the minimum', (
    tester,
  ) async {
    await tester.pumpWidget(_host(320, 400, _buffer()));
    expect(outerScrollable(tester).position.maxScrollExtent, 0);

    await tester.pumpWidget(_host(320, 100, _buffer()));
    expect(outerScrollable(tester).position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('keeps the viewer state when the panel shrinks below the '
      'minimum and grows back', (tester) async {
    final buffer = _buffer(entries: 2);
    final key = GlobalKey();
    Widget host(double height) => FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          height: height,
          child: WorkbenchDebugLogPane(
            key: key,
            logBuffer: buffer,
            onExpand: () {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(400));
    await tester.enterText(
      find
          .descendant(
            of: find.byType(WorkbenchDebugLogPane),
            matching: find.byType(EditableText),
          )
          .first,
      'needle',
    );
    await tester.pump();

    await tester.pumpWidget(host(100));
    await tester.pumpWidget(host(400));

    expect(find.text('needle'), findsOneWidget);
  });
}
