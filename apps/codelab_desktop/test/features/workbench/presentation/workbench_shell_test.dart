// Каркас рабочего места в собранном приложении (tasks 5.1, 5.3 change
// `redesign-workbench-shell`; spec agent-workbench-ui «Layout workbench»,
// «Layout class follows the window width», «Клавиатурный десктопный UX»).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/workbench_shell.dart';
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

  // Переход в настройки и обратно (задача 1.3 change
  // `add-app-settings-shell`; spec app-settings «Переход в настройки и
  // обратно»; DSK-24). Набор `available` в тестах задаёт `settingsPages`.
  group('settings navigation', () {
    const withConnection = SettingsPages(available: {SettingsPage.connection});
    final settingsNav = find.byKey(const ValueKey('settings-nav-connection'));

    Future<void> pressWithControl(
      WidgetTester tester,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> createSession(
      WidgetTester tester,
      CodeLabShellCubit cubit,
      FakeAcpTransport agent,
      String id,
    ) async {
      unawaited(cubit.createSession());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      final request = agent.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((r) => r.method == sessionNewMethod);
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('Ctrl+, opens the settings screen on Connection', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      expect(settingsNav, findsNothing);

      await pressWithControl(tester, LogicalKeyboardKey.comma);

      expect(settingsNav, findsOneWidget);
      // Первое открытие: выбран пункт Connection (spec app-settings).
      final view = tester.widget<NavigationView>(find.byType(NavigationView));
      expect(view.pane!.selected, 0);
      expect(
        view.pane!.effectiveItems.first.key,
        const ValueKey('settings-nav-connection'),
      );
      await tearDownApp(tester);
    });

    testWidgets('Cmd+, opens the settings screen too', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(settingsNav, findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('the Settings button in the sidebar opens the settings '
        'screen', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));

      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();

      expect(settingsNav, findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Esc returns to the same session with the same composer '
        'text', (tester) async {
      setWindow(tester, const Size(1440, 900));
      final agent = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: FakeAcpTransport(),
        stdioTransportFactory: (_) => agent,
        settingsPages: withConnection,
      );
      final cubit = await pumpApp(tester, binding);
      await tester.runAsync(() => cubit.connect());
      await tester.pump();
      agent.drainSentMessages();
      await createSession(tester, cubit, agent, 'session-B');
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'unsent draft',
      );
      await tester.pump();

      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      expect(settingsNav, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(settingsNav, findsNothing);
      expect(cubit.state.activeSessionId, 'session-B');
      expect(find.text('unsent draft'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('workbench shortcuts work again after returning from '
        'settings', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      await pressWithControl(tester, LogicalKeyboardKey.comma);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(settingsNav, findsNothing);

      await pressWithControl(tester, LogicalKeyboardKey.comma);

      expect(settingsNav, findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Ctrl+, on the settings screen changes nothing', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      await pressWithControl(tester, LogicalKeyboardKey.comma);

      await pressWithControl(tester, LogicalKeyboardKey.comma);

      expect(settingsNav, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(settingsNav, findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('the Back button returns to the workbench', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      await pressWithControl(tester, LogicalKeyboardKey.comma);

      await tester.tap(find.byKey(CodeLabSettingsNavigation.backKey));
      await tester.pumpAndSettle();

      expect(settingsNav, findsNothing);
      expect(find.byType(CodeLabPromptComposer), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('with no available pages Ctrl+, and Settings open nothing: '
        'there is no empty settings screen (SETUP-17)', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(
        tester,
        CodeLabTestBinding(settingsPages: const SettingsPages(available: {})),
      );

      await pressWithControl(tester, LogicalKeyboardKey.comma);
      expect(settingsNav, findsNothing);
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      expect(settingsNav, findsNothing);
      expect(find.byType(CodeLabPromptComposer), findsOneWidget);

      await tearDownApp(tester);
    });

    testWidgets('in the production build Settings opens the Connection '
        'page', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding());

      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();

      expect(settingsNav, findsOneWidget);
      expect(
        find.byKey(const ValueKey('connection-profile-row-embedded')),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('Esc on the workbench during a turn cancels the turn and '
        'does not open settings', (tester) async {
      setWindow(tester, const Size(1440, 900));
      final agent = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: FakeAcpTransport(),
        stdioTransportFactory: (_) => agent,
        settingsPages: withConnection,
      );
      final cubit = await pumpApp(tester, binding);
      await tester.runAsync(() => cubit.connect());
      await tester.pump();
      agent.drainSentMessages();
      await createSession(tester, cubit, agent, 'session-1');

      unawaited(cubit.submitPrompt('long task'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      final prompt = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
        (r) => r.method == sessionPromptMethod,
      );
      expect(cubit.state.canCancel, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(
        agent.sentMessages.whereType<JsonRpcNotification>().where(
          (n) => n.method == sessionCancelMethod,
        ),
        hasLength(1),
      );
      expect(settingsNav, findsNothing);

      // Ответ агента снимает таймер запроса, иначе тест оставит его висеть.
      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'cancelled'},
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tearDownApp(tester);
    });
  });

  // Фокус и одобрения под экраном настроек (ревью итерации 1, H1, M2, L4).
  group('settings screen and the hidden workbench', () {
    const withConnection = SettingsPages(available: {SettingsPage.connection});
    final settingsNav = find.byKey(const ValueKey('settings-nav-connection'));

    /// Кадры вместо `pumpAndSettle`: при ходе или одобрении индикаторы
    /// анимируются бесконечно, и `pumpAndSettle` не завершается.
    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await frames(tester);
    }

    Future<void> createSession(
      WidgetTester tester,
      CodeLabShellCubit cubit,
      FakeAcpTransport agent,
      String id,
    ) async {
      agent.drainSentMessages();
      unawaited(cubit.createSession());
      await settle(tester);
      final request = agent.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((r) => r.method == sessionNewMethod);
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      await settle(tester);
    }

    /// Ход в активной сессии: запрос разрешения привязывается к ходу.
    Future<void> startTurn(WidgetTester tester, CodeLabShellCubit cubit) async {
      unawaited(cubit.submitPrompt('run a command'));
      await settle(tester);
    }

    void askPermission(FakeAcpTransport agent, String sessionId, int id) {
      agent.emitInbound(
        JsonRpcMessage.request(
          id: JsonRpcId.integer(id),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: SessionId(sessionId),
            toolCall: ToolCallUpdate(
              toolCallId: ToolCallId('call-$id'),
              title: 'Run echo',
              kind: ToolKind.execute,
              status: ToolCallStatus.inProgress,
              rawInput: const {'command': 'echo hi'},
            ),
            options: const [
              PermissionOption(
                optionId: PermissionOptionId('allow-once'),
                name: 'Allow once',
                kind: PermissionOptionKind.allowOnce,
              ),
              PermissionOption(
                optionId: PermissionOptionId('reject-once'),
                name: 'Reject',
                kind: PermissionOptionKind.rejectOnce,
              ),
            ],
          ).toJson(),
        ),
      );
    }

    Future<(CodeLabShellCubit, FakeAcpTransport)> connected(
      WidgetTester tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      final agent = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: FakeAcpTransport(),
        stdioTransportFactory: (_) => agent,
        // Встроенный агент не открывается: Space и Enter на странице
        // «Connection» могут нажать его «Connect», а тестовая сборка по
        // умолчанию даёт падающий открыватель (`CodeLabTestBinding`).
        settingsPages: withConnection,
      );
      final cubit = await pumpApp(tester, binding);
      await tester.runAsync(() => cubit.connect());
      await tester.pump();
      return (cubit, agent);
    }

    Future<void> tabMany(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
    }

    int responsesTo(FakeAcpTransport agent) =>
        agent.sentMessages.whereType<JsonRpcResponse>().length;

    testWidgets('Esc after opening settings during a turn leaves settings '
        'without session/cancel', (tester) async {
      final (cubit, agent) = await connected(tester);
      await createSession(tester, cubit, agent, 'session-1');
      unawaited(cubit.submitPrompt('long task'));
      await settle(tester);
      await tester.pump();
      final prompt = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
        (r) => r.method == sessionPromptMethod,
      );
      expect(cubit.state.canCancel, isTrue);

      await pressCtrl(tester, LogicalKeyboardKey.comma);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);

      expect(settingsNav, findsNothing);
      expect(
        agent.sentMessages.whereType<JsonRpcNotification>().where(
          (n) => n.method == sessionCancelMethod,
        ),
        isEmpty,
      );
      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await settle(tester);
      await tearDownApp(tester);
    });

    // Тесты Tab/Space/Enter ниже проверяют сквозное поведение клавиш. Саму
    // защиту (исключение рабочего места из фокуса) доказывает детерминированный
    // тест «workbench nodes cannot take focus under settings».
    testWidgets('workbench nodes cannot take focus under settings (H1)', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      final composer = tester
          .widget<TextBox>(
            find.byKey(
              const ValueKey('composer-text-box'),
              skipOffstage: false,
            ),
          )
          .focusNode!;
      await pressCtrl(tester, LogicalKeyboardKey.comma);
      expect(settingsNav, findsOneWidget);

      composer.requestFocus();
      await tester.pump();

      expect(composer.hasFocus, isFalse);
      expect(composer.canRequestFocus, isFalse);
      expect(FocusManager.instance.primaryFocus, isNot(same(composer)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(composer.canRequestFocus, isTrue);
      composer.requestFocus();
      await tester.pump();
      expect(composer.hasFocus, isTrue);
      await tearDownApp(tester);
    });

    testWidgets('Tab, Space and Enter on the settings screen never answer a '
        'pending approval', (tester) async {
      final (cubit, agent) = await connected(tester);
      await createSession(tester, cubit, agent, 'session-1');
      await startTurn(tester, cubit);
      askPermission(agent, 'session-1', 701);
      await settle(tester);
      await tester.pump();
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      final before = responsesTo(agent);

      await pressCtrl(tester, LogicalKeyboardKey.comma);
      expect(settingsNav, findsOneWidget);
      // Число Tab не подгоняется под раскладку страницы: Tab нажимается с
      // верхней границей, пока фокус не окажется на переключателе
      // «Connect on start» (Space и Enter на нём безвредны). На каждом шаге
      // проверяется, что фокус не ушёл в скрытое рабочее место (H1
      // итерации 1).
      var onTarget = false;
      for (var i = 0; i < 80 && !onTarget; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final context = FocusManager.instance.primaryFocus?.context;
        expect(context, isNotNull);
        expect(
          context!.findAncestorWidgetOfExactType<CodeLabShell>(),
          isNull,
          reason: 'focus left the settings screen for the workbench',
        );
        context.visitAncestorElements((element) {
          if (element.widget.key ==
              const ValueKey('connection-connect-on-start')) {
            onTarget = true;
          }
          return !onTarget;
        });
      }
      expect(
        onTarget,
        isTrue,
        reason: 'Tab never reached the Connect on start toggle',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(responsesTo(agent), before);
      expect(settingsNav, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);
      await tearDownApp(tester);
    });

    testWidgets('Tab then Enter on the settings screen does not send the '
        'composer draft', (tester) async {
      final (cubit, agent) = await connected(tester);
      await createSession(tester, cubit, agent, 'session-1');
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'draft',
      );
      await tester.pump();
      agent.drainSentMessages();

      await pressCtrl(tester, LogicalKeyboardKey.comma);
      await tabMany(tester, 25);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);
      await settle(tester);
      expect(
        tester
            .widget<TextBox>(
              find.byKey(
                const ValueKey('composer-text-box'),
                skipOffstage: false,
              ),
            )
            .controller!
            .text,
        'draft',
      );

      expect(
        agent.sentMessages.whereType<JsonRpcRequest>().where(
          (r) => r.method == sessionPromptMethod,
        ),
        isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // В полёте остаются таймеры запросов; без паузы они переживают дерево.
      await tester.pump(const Duration(seconds: 10));
      await tearDownApp(tester);
    });

    testWidgets('returning from settings restores focus to the composer', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      await pumpApp(tester, CodeLabTestBinding(settingsPages: withConnection));
      await tester.tap(find.byKey(const ValueKey('composer-text-box')));
      await tester.pump();
      FocusNode composerFocus() => tester
          .widget<TextBox>(
            find.byKey(
              const ValueKey('composer-text-box'),
              skipOffstage: false,
            ),
          )
          .focusNode!;
      expect(composerFocus().hasFocus, isTrue);

      await pressCtrl(tester, LogicalKeyboardKey.comma);
      expect(composerFocus().hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);

      expect(composerFocus().hasFocus, isTrue);
      await tearDownApp(tester);
    });

    testWidgets('Esc returns to session B after the active session became C', (
      tester,
    ) async {
      final (cubit, agent) = await connected(tester);
      await createSession(tester, cubit, agent, 'session-B');
      await createSession(tester, cubit, agent, 'session-C');
      cubit.selectSession('session-B');
      await tester.pump();
      await tester.pump();

      await pressCtrl(tester, LogicalKeyboardKey.comma);
      cubit.selectSession('session-C');
      await tester.pump();
      await tester.pump();
      expect(cubit.state.activeSessionId, 'session-C');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);

      expect(cubit.state.activeSessionId, 'session-B');
      await tearDownApp(tester);
    });
  });
}
