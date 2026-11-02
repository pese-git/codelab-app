// Диалог подключения: тип «Embedded agent» (задача 4.1 change
// `add-embedded-agent-mode`; agent-workbench-ui «Тип подключения «Встроенный
// агент»», сценарий «Выбор встроенного агента»; design.md D9).
//
// Проверяется поведение выбора типа (какие поля видны, что в состоянии
// рабочего места), а не пиксели.

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app_scope.dart';

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

  Future<CodeLabShellCubit> openDialog(WidgetTester tester) async {
    final binding = CodeLabTestBinding();
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    return binding.scope.resolve<CodeLabShellCubit>();
  }

  testWidgets('the dialog offers the third type next to stdio and WebSocket, '
      'stdio stays selected', (tester) async {
    final shell = await openDialog(tester);

    expect(find.widgetWithText(CodeLabButton, 'stdio'), findsOneWidget);
    expect(find.widgetWithText(CodeLabButton, 'WebSocket'), findsOneWidget);
    expect(
      find.widgetWithText(CodeLabButton, 'Embedded agent'),
      findsOneWidget,
    );
    expect(shell.state.transportType, CodeLabTransportType.stdio);
    expect(
      find.byKey(const ValueKey('transport-field-Command')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets('selecting Embedded agent has no fields and shows the label '
      'and the detail of the connection', (tester) async {
    final shell = await openDialog(tester);

    await tester.tap(find.widgetWithText(CodeLabButton, 'Embedded agent'));
    await tester.pumpAndSettle();

    expect(shell.state.transportType, CodeLabTransportType.embedded);
    expect(shell.state.profileLabel, 'Embedded agent');
    expect(
      shell.state.connectionDetail,
      'codelab_embedded (embedded-app-desktop)',
    );
    expect(find.byKey(const ValueKey('transport-field-Command')), findsNothing);
    expect(
      find.byKey(const ValueKey('transport-field-Endpoint')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });
}
