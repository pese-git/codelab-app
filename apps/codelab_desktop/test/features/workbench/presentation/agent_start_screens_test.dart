// Панель сессии без Connect (задача B2.5 change `require-project-folder`;
// spec agent-workbench-ui «Агент стартует сам», «App bar…», «Connection
// banner above a non-empty transcript»; design.md D13, D18).
//
// Проверяется поведение отображения: какой экран виден в каком состоянии,
// какие кнопки есть и что они вызывают; пиксели не проверяются.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/shell_cubit_characterization/harness.dart'
    show ThrowingStartTransport;
import '../../../support/test_app_scope.dart';

final class _Picker implements ProjectFolderPicker {
  var picks = 0;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async {
    picks++;
    return null;
  }
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<CodeLabShellCubit> pump(
    WidgetTester tester,
    CodeLabTestBinding binding,
  ) async {
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    return binding.scope.resolve<CodeLabShellCubit>();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  final connectKey = CodeLabAppBar.connectionConnectKey;

  testWidgets('without a project the start screen offers Open folder and the '
      'app bar has no Connect', (tester) async {
    final picker = _Picker();
    final binding = CodeLabTestBinding(projectFolderPicker: picker);
    await pump(tester, binding);

    expect(find.text('Open a project to start a session.'), findsOneWidget);
    expect(find.byKey(connectKey), findsNothing);
    await tester.tap(find.byKey(const ValueKey('start-open-project')));
    await tester.pump(const Duration(seconds: 1));
    expect(picker.picks, 1);
    await tearDownApp(tester);
  });

  testWidgets('with a project the start screen offers New session, and '
      'Ctrl+N creates a session without a connection', (tester) async {
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/work/app',
      stdioTransportFactory: (_) => agent,
    );
    await pump(tester, binding);

    expect(find.text('Start a new session in app.'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-new-session')), findsOneWidget);
    expect(find.byKey(connectKey), findsNothing);

    // Cmd/Ctrl+N доступен при выбранном проекте и без соединения и стартует
    // агента (D13): первым кадром агенту уходит `initialize`.
    await tester.runAsync(() async {
      final sent = agent.sent.first;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await sent.timeout(const Duration(seconds: 3));
    });
    await tearDownApp(tester);
  });

  testWidgets('while the agent starts the start screen shows Starting '
      '<profile>…', (tester) async {
    final agent = FakeAcpTransport()..autoRespondToInitialize = false;
    final binding = CodeLabTestBinding(
      project: '/work/app',
      stdioTransportFactory: (_) => agent,
    );
    final cubit = await pump(tester, binding);

    await tester.runAsync(() async {
      unawaited(cubit.startOnLaunch());
      await pumpEventQueue();
    });
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Starting '), findsOneWidget);
    expect(find.byKey(const ValueKey('start-new-session')), findsOneWidget);
    expect(find.byKey(connectKey), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('a failed start shows the failure screen with Retry and, after '
      'the same failure again, Failed again (n)', (tester) async {
    final binding = CodeLabTestBinding(
      project: '/work/app',
      stdioTransportFactory: (_) =>
          ThrowingStartTransport(StateError('no agent')),
    );
    final cubit = await pump(tester, binding);

    await tester.runAsync(() async {
      await cubit.startOnLaunch();
      await cubit.retryStart();
      await cubit.retryStart();
    });
    await tester.pump();
    await tester.pump();

    final screen = find.byType(CodeLabConnectionScreen);
    expect(screen, findsOneWidget);
    expect(
      find.descendant(of: screen, matching: find.text('Retry')),
      findsOneWidget,
    );
    expect(find.textContaining('Failed again (2)'), findsOneWidget);
    expect(find.byKey(connectKey), findsNothing);
    await tearDownApp(tester);
  });
}
