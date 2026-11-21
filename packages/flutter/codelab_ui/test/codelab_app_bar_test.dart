// Подпись бейджа соединения `connectionLabel` (задача 2.5 change
// `add-empty-project-screen`; design.md D8; spec agent-workbench-ui «App
// bar…», сценарий «Badge before the agent starts»).
//
// Красный до задачи 2.6: параметра `connectionLabel` ещё нет.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({
  required CodeLabConnectionStatus status,
  String? connectionLabel,
  VoidCallback? onConnect,
}) => FluentApp(
  home: ScaffoldPage(
    content: CodeLabAppBar(
      title: 'CodeLab',
      connectionStatus: status,
      connectionLabel: connectionLabel,
      onConnect: onConnect,
    ),
  ),
);

void main() {
  testWidgets(
    'connectionLabel заменяет подпись бейджа и не добавляет Connect',
    (tester) async {
      await tester.pumpWidget(
        _bar(
          status: CodeLabConnectionStatus.disconnected,
          connectionLabel: 'No project · agent not started',
        ),
      );

      expect(find.text('No project · agent not started'), findsOneWidget);
      expect(find.text('Disconnected'), findsNothing);
      expect(find.byKey(CodeLabAppBar.connectionConnectKey), findsNothing);
    },
  );

  testWidgets(
    'connectionLabel не показывает Connect, даже если есть onConnect',
    (tester) async {
      await tester.pumpWidget(
        _bar(
          status: CodeLabConnectionStatus.idle,
          connectionLabel: 'No project · agent not started',
          onConnect: () {},
        ),
      );

      expect(find.byKey(CodeLabAppBar.connectionConnectKey), findsNothing);
    },
  );

  testWidgets('null — прежние подписи по статусу', (tester) async {
    await tester.pumpWidget(_bar(status: CodeLabConnectionStatus.disconnected));
    expect(find.text('Disconnected'), findsOneWidget);

    await tester.pumpWidget(_bar(status: CodeLabConnectionStatus.connected));
    expect(find.text('Connected'), findsOneWidget);
  });
}
