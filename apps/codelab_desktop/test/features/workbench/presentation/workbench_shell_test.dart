// Каркас рабочего места в собранном приложении (tasks 5.1, 5.3 change
// `redesign-workbench-shell`; spec agent-workbench-ui «Layout workbench»,
// «Layout class follows the window width», «Клавиатурный десктопный UX»).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app_scope.dart';

void main() {
  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<CodeLabShellCubit> pumpApp(
    WidgetTester tester,
    CodeLabTestBinding binding,
  ) async {
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.pump();
    return binding.scope.resolve<CodeLabShellCubit>();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  }

  testWidgets('a 1440 px window shows the app bar, sidebar, session pane and '
      'the open Plan pane left to right', (tester) async {
    setWindow(tester, const Size(1440, 900));
    final cubit = await pumpApp(tester, CodeLabTestBinding());

    cubit.togglePane(ToolPane.plan);
    // Состояние фасада доходит до `BlocBuilder` через поток — нужен кадр.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final sidebar = tester.getRect(
      find.byKey(CodeLabWorkbenchLayout.sidebarKey),
    );
    final session = tester.getRect(
      find.byKey(CodeLabWorkbenchLayout.sessionPaneKey),
    );
    final dock = tester.getRect(find.byKey(CodeLabWorkbenchLayout.dockKey));
    expect(sidebar.right, lessThan(session.left));
    expect(session.right, lessThan(dock.left));
    expect(find.byKey(CodeLabToolDock.paneKey(ToolPane.plan)), findsOneWidget);
    expect(find.byType(CodeLabAppBar), findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('resizing across layout classes keeps the composer draft '
      '(MOB-3)', (tester) async {
    setWindow(tester, const Size(1440, 900));
    await pumpApp(tester, CodeLabTestBinding());

    await tester.enterText(
      find.byKey(const ValueKey('composer-text-box')),
      'unsent draft',
    );
    await tester.pump();

    for (final size in const [Size(820, 900), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      await tester.pump();
    }

    expect(find.text('unsent draft'), findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('Cmd/Ctrl+B collapses the sidebar in a wide window and opens '
      'it over the content in a narrow one', (tester) async {
    setWindow(tester, const Size(1440, 900));
    final cubit = await pumpApp(tester, CodeLabTestBinding());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(cubit.state.sidebarCollapsed, isTrue);
    expect(
      tester.getSize(find.byKey(CodeLabWorkbenchLayout.sidebarKey)).width,
      56,
    );

    tester.view.physicalSize = const Size(820, 900);
    await tester.pump();
    expect(find.byKey(CodeLabWorkbenchLayout.sidebarKey), findsNothing);

    await tester.tap(find.byKey(CodeLabAppBar.menuKey));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cubit.state.sidebarOverlayOpen, isTrue);
    expect(find.byKey(CodeLabWorkbenchLayout.sidebarKey), findsOneWidget);

    await tearDownApp(tester);
  });

  /// Нажатие переключателя через его обработчик: в тестовом шрифте Ahem
  /// подписи app bar шире реальных, и попадание по координате ненадёжно.
  void toggle(WidgetTester tester, ToolPane pane) => tester
      .widget<ToggleButton>(find.byKey(CodeLabAppBar.toggleKey(pane)))
      .onChanged!(true);

  testWidgets('in a narrow window a pane toggle re-opens a dismissed dock '
      'instead of closing the pane', (tester) async {
    setWindow(tester, const Size(1100, 900));
    final cubit = await pumpApp(tester, CodeLabTestBinding());
    toggle(tester, ToolPane.plan);
    await tester.pump();
    await tester.pump();
    expect(cubit.state.dockOverlayOpen, isTrue);

    cubit.dismissDockOverlay();
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<ToggleButton>(
            find.byKey(CodeLabAppBar.toggleKey(ToolPane.plan)),
          )
          .checked,
      isFalse,
    );

    toggle(tester, ToolPane.plan);
    await tester.pump();
    await tester.pump();

    expect(cubit.state.openPanes, [ToolPane.plan]);
    expect(cubit.state.dockOverlayOpen, isTrue);

    await tearDownApp(tester);
  });

  testWidgets('Cmd/Ctrl+N creates a session while connected', (tester) async {
    setWindow(tester, const Size(1440, 900));
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
    );
    final cubit = await pumpApp(tester, binding);
    await tester.runAsync(() => cubit.connect());
    await tester.pump();
    agent.drainSentMessages();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionNewMethod,
    );
    // Ответ агента снимает таймер запроса, иначе тест оставит его висеть.
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(cubit.state.activeSessionId, 'session-1');

    await tearDownApp(tester);
  });

  for (final size in const [
    Size(390, 844),
    Size(820, 1180),
    Size(1180, 820),
    Size(1440, 900),
  ]) {
    testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} '
        'with the composer visible', (tester) async {
      setWindow(tester, size);
      final cubit = await pumpApp(tester, CodeLabTestBinding());
      cubit.togglePane(ToolPane.protocol);
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CodeLabPromptComposer), findsOneWidget);

      await tearDownApp(tester);
    });
  }
}
