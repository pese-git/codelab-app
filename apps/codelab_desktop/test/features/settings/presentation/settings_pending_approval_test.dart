// InfoBar ожидающего одобрения на экране настроек (задача 1.8 change
// `add-app-settings-shell`; spec app-settings «Ожидающее одобрение видно из
// настроек»; design.md D2, D17).
//
// Признак берётся из `SessionView.pendingApprovals` через Cubit рабочего
// места; сам ответ на запрос даётся только на рабочем месте.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';
import '../../../support/start_agent.dart';

void main() {
  final pendingBar = find.byKey(const ValueKey('settings-pending-approval'));
  final settingsNav = find.byKey(const ValueKey('settings-nav-connection'));

  late FakeAcpTransport agent;
  late CodeLabShellCubit cubit;
  late CodeLabTestBinding binding;

  /// Кадры вместо `pumpAndSettle`: при ходе индикаторы анимируются
  /// бесконечно.
  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames(tester);
  }

  Future<void> createSession(WidgetTester tester, String id) async {
    agent.drainSentMessages();
    unawaited(cubit.createSession());
    await settle(tester);
    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionNewMethod,
    );
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
    );
    await settle(tester);
  }

  /// Запрос разрешения привязывается к ходу, поэтому сначала идёт ход.
  Future<void> startTurn(WidgetTester tester) async {
    unawaited(cubit.submitPrompt('run a command'));
    await settle(tester);
  }

  void ask(String sessionId, int id) {
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

  Future<void> pumpConnected(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    agent = FakeAcpTransport();
    binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => cubit.startWith());
    await tester.pump();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    // В полёте остаются таймеры запросов; без паузы они переживают дерево.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  }

  List<Map<String, Object?>> settingsEvents(String event) => [
    for (final entry in binding.scope.resolve<LogBuffer>().entries.value)
      if (entry['event'] == event) Map<String, Object?>.from(entry),
  ];

  /// Сессия `A` ведёт ход, затем активна `B`; запрос приходит в `A`.
  Future<void> backgroundRequestInA(WidgetTester tester) async {
    await createSession(tester, 'session-A');
    await startTurn(tester);
    await createSession(tester, 'session-B');
    ask('session-A', 702);
    await settle(tester);
  }

  testWidgets('a request in background session A while B is active shows '
      'the InfoBar and keeps settings open', (tester) async {
    await pumpConnected(tester);
    await backgroundRequestInA(tester);
    expect(cubit.state.activeSessionId, 'session-B');

    await openSettings(tester);

    expect(pendingBar, findsOneWidget);
    expect(find.text('Agent is waiting for your approval'), findsOneWidget);
    expect(settingsNav, findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('"Back to session" shows session A with the approval card', (
    tester,
  ) async {
    await pumpConnected(tester);
    await backgroundRequestInA(tester);
    await openSettings(tester);

    await tester.tap(find.text('Back to session'));
    await frames(tester);

    expect(settingsNav, findsNothing);
    expect(cubit.state.activeSessionId, 'session-A');
    expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('with requests in two sessions the active one is chosen', (
    tester,
  ) async {
    await pumpConnected(tester);
    await createSession(tester, 'session-A');
    await startTurn(tester);
    await createSession(tester, 'session-B');
    await startTurn(tester);
    ask('session-A', 801);
    ask('session-B', 802);
    await settle(tester);
    cubit.selectSession('session-A');
    await settle(tester);
    await openSettings(tester);

    await tester.tap(find.text('Back to session'));
    await frames(tester);

    expect(cubit.state.activeSessionId, 'session-A');
    await tearDownApp(tester);
  });

  testWidgets('the InfoBar disappears once the request is answered', (
    tester,
  ) async {
    await pumpConnected(tester);
    await createSession(tester, 'session-1');
    await startTurn(tester);
    ask('session-1', 703);
    await settle(tester);
    final pending =
        cubit.state.transcriptRows
                .whereType<CodeLabToolCallRow>()
                .single
                .approval!
            as CodeLabTranscriptApprovalPending;
    await openSettings(tester);
    expect(pendingBar, findsOneWidget);

    pending.onOptionSelected(pending.options.first.id);
    await settle(tester);
    await frames(tester);

    expect(pendingBar, findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('the InfoBar disappears when the turn is cancelled', (
    tester,
  ) async {
    await pumpConnected(tester);
    await createSession(tester, 'session-1');
    await startTurn(tester);
    ask('session-1', 710);
    await settle(tester);
    await openSettings(tester);
    expect(pendingBar, findsOneWidget);

    unawaited(cubit.cancelTurn());
    await settle(tester);
    await frames(tester);

    expect(pendingBar, findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('the InfoBar disappears when the connection is lost', (
    tester,
  ) async {
    await pumpConnected(tester);
    await createSession(tester, 'session-1');
    await startTurn(tester);
    ask('session-1', 711);
    await settle(tester);
    await openSettings(tester);
    expect(pendingBar, findsOneWidget);

    agent.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Stdio ACP agent exited unexpectedly with code -9.',
      ),
    );
    await settle(tester);
    await frames(tester);

    expect(pendingBar, findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('the InfoBar is not shown for a session left detached by '
      'reconnect (the request belongs to the old connection)', (tester) async {
    // Первое подключение — старый агент, второе (reconnect) — новый, который
    // сессию не загружает: она остаётся detached со старым запросом.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final old = FakeAcpTransport();
    final fresh = FakeAcpTransport();
    var starts = 0;
    agent = old;
    binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => starts++ == 0 ? old : fresh,
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => cubit.startWith());
    await tester.pump();
    await createSession(tester, 'session-1');
    await startTurn(tester);
    ask('session-1', 720);
    await settle(tester);
    expect(cubit.sessionIdsWithPendingApproval, ['session-1']);

    // Ход идёт и ждёт одобрения: перезапуск спрашивает подтверждение (D22).
    await tester.runAsync(() => cubit.restartAgent());
    expect(cubit.state.pendingRestart, isNotNull);
    await tester.runAsync(() => cubit.confirmRestart());
    await settle(tester);
    await openSettings(tester);

    expect(cubit.sessionIdsWithPendingApproval, isEmpty);
    expect(pendingBar, findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('settings offer no answer buttons and do not return on their '
      'own', (tester) async {
    await pumpConnected(tester);
    await createSession(tester, 'session-1');
    await startTurn(tester);
    await openSettings(tester);

    ask('session-1', 704);
    await settle(tester);
    await frames(tester);

    expect(pendingBar, findsOneWidget);
    expect(settingsNav, findsOneWidget);
    expect(find.byKey(CodeLabApprovalPrompt.allowKey), findsNothing);
    expect(find.byKey(CodeLabApprovalPrompt.rejectKey), findsNothing);

    // L4: запрос, пришедший под настройками, виден на ленте после Esc.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('shown is logged once, back_to_approval on the press, with no '
      'request or tool call fields', (tester) async {
    await pumpConnected(tester);
    await backgroundRequestInA(tester);
    await openSettings(tester);
    // Повторные состояния рабочего места не дублируют запись.
    cubit.selectSession('session-B');
    await settle(tester);
    await frames(tester);

    expect(settingsEvents('settings.pending_approval_shown'), hasLength(1));
    expect(
      settingsEvents('settings.pending_approval_shown').single['sessions'],
      1,
    );

    await tester.tap(find.text('Back to session'));
    await frames(tester);

    expect(settingsEvents('settings.back_to_approval'), hasLength(1));
    for (final event in [
      ...settingsEvents('settings.pending_approval_shown'),
      ...settingsEvents('settings.back_to_approval'),
    ]) {
      final text = event.toString();
      expect(text, isNot(contains('702')));
      expect(text, isNot(contains('call-')));
      expect(text, isNot(contains('session-A')));
    }
    await tearDownApp(tester);
  });
}
