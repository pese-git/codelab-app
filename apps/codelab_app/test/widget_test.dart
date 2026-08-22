import 'dart:async';

import 'package:codelab_app/main.dart';
import 'package:codelab_app/src/app_scope.dart';
import 'package:codelab_app/src/presentation/shell_cubit.dart';
import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_scope.dart';

void main() {
  testWidgets('renders the desktop workbench shell', (tester) async {
    final binding = CodeLabTestBinding();
    final scope = binding.scope;

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    expect(find.text('CodeLab'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Codelab Agent'), findsWidgets);
    expect(
      find.text('Connect an ACP agent to start a session.'),
      findsOneWidget,
    );
    expect(find.text('No active session'), findsOneWidget);
    expect(find.text('Create a session after connecting.'), findsOneWidget);
    expect(
      find.text('Shell bootstrapped. Connection wiring starts in 7.2.'),
      findsOneWidget,
    );
    expect(
      scope.resolve<CodeLabShellCubit>().state.transportType,
      CodeLabTransportType.stdio,
    );
    expect(find.byType(AcpWorkbenchLayout), findsOneWidget);
    expect(find.byType(AcpConnectionScreen), findsOneWidget);
    expect(find.byType(AcpPromptComposer), findsOneWidget);
    expect(find.byType(AcpWorkbenchShortcuts), findsOneWidget);
    expect(
      scope.resolve<CodeLabTransportFactory>(),
      isA<CodeLabTransportFactory>(),
    );
    expect(scope.resolve<StdioAcpAgentProfile>(), codelabAgentStdioProfile);
    expect(
      scope.resolve<CodeLabShellCubit>().state.stdioCommand,
      codelabAgentStdioProfile.command,
    );
    expect(scope.resolve<CodeLabShellCubit>().state.stdioArgs, 'serve --stdio');
    expect(scope.resolve<AcpClientApplication>(), isA<AcpClientApplication>());
    expect(scope.resolve<AcpTransport>(), same(binding.transport));
    expect(scope.resolve<CodeLabRootLifecycle>(), isA<CodeLabRootLifecycle>());
    expect(scope.resolve<CodeLabShellCubit>(), isA<CodeLabShellCubit>());
    expect(
      codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).application,
      same(scope.resolve<AcpClientApplication>()),
    );
    expect(
      codeLabDependenciesOf(tester.element(find.byType(CodeLabApp))).shellCubit,
      same(scope.resolve<CodeLabShellCubit>()),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets('requires a session before sending a prompt', (tester) async {
    final binding = CodeLabTestBinding();

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    await tester.enterText(find.byType(EditableText).last, 'hello');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();
    expect(
      shellCubit.state.diagnostics.last.message,
      'Create or select a session before sending a prompt.',
    );
    expect(binding.transport.sentMessages, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets('selects WebSocket and keeps endpoint in shell state', (
    tester,
  ) async {
    final binding = CodeLabTestBinding();

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();
    expect(shellCubit.state.transportType, CodeLabTransportType.stdio);
    expect(find.text('Codelab Agent'), findsWidgets);

    await tester.tap(find.widgetWithText(AcpButton, 'WebSocket'));
    await tester.pump(const Duration(milliseconds: 100));

    const endpoint = 'wss://agent.example.test/acp';
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Endpoint')),
      endpoint,
    );
    await tester.pump();

    expect(shellCubit.state.transportType, CodeLabTransportType.webSocket);
    expect(shellCubit.state.webSocketEndpoint, endpoint);
    expect(shellCubit.state.connectionDetail, endpoint);
    expect(binding.transport.state, AcpTransportState.idle);
    expect(binding.transport.sentMessages, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  test('creates a session and tracks it as active', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (_) => agentTransport,
    );

    shellCubit.updateStdioCwd('/workspace');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    final sentRequest = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final request = await sentRequest as dynamic;
    expect(request.method, 'session/new');
    expect(request.params, containsPair('cwd', '/workspace'));

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: request.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    expect(shellCubit.state.activeSessionId, 'session-1');
    expect(shellCubit.state.sessions.single.id, 'session-1');
    expect(shellCubit.state.currentSessionLabel, 'Session session-1');
    expect(shellCubit.state.currentSessionDetail, '/workspace');
    expect(
      shellCubit.state.diagnostics.map((entry) => entry.message),
      contains('Created ACP session session-1.'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('submitPrompt sends text content and records agent response', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (_) => agentTransport,
    );

    shellCubit.updateStdioCwd('/workspace');
    await shellCubit.connect();

    final createRequestFuture = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final createRequest = await createRequestFuture as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    final promptRequestFuture = agentTransport.sent.first;
    final submitFuture = shellCubit.submitPrompt('  hello agent  ');
    expect(shellCubit.state.isPromptSubmitting, isTrue);
    expect(shellCubit.state.canCancel, isTrue);
    expect(shellCubit.state.transcriptEntries.last.title, 'You');
    expect(shellCubit.state.transcriptEntries.last.body, 'hello agent');

    final promptRequest = await promptRequestFuture as dynamic;
    expect(promptRequest.method, 'session/prompt');
    expect(promptRequest.params, containsPair('sessionId', 'session-1'));
    expect(
      promptRequest.params,
      containsPair('prompt', [
        {'type': 'text', 'text': 'hello agent'},
      ]),
    );

    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: 'session/update',
        params: const {
          'sessionId': 'session-1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'hi from agent'},
          },
        },
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture;

    expect(shellCubit.state.isPromptSubmitting, isFalse);
    expect(shellCubit.state.canCancel, isFalse);
    expect(shellCubit.state.transcriptEntries.last.title, 'Agent');
    expect(shellCubit.state.transcriptEntries.last.body, 'hi from agent');
    expect(
      shellCubit.state.diagnostics.last.message,
      'Prompt completed with stopReason endTurn.',
    );

    await shellCubit.close();
    await application.dispose();
  });

  test(
    'inspector tracks tool calls approvals raw details and protocol',
    () async {
      final initialTransport = FakeAcpTransport();
      final agentTransport = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: initialTransport,
        stdioTransportFactory: (_) => agentTransport,
      );
      final application = binding.scope.resolve<AcpClientApplication>();
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await shellCubit.connect();

      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest = await createRequestFuture as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await createFuture;

      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt('inspect tool');
      final promptRequest = await promptRequestFuture as dynamic;

      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.toolCallUpdate(
              toolCallUpdate: ToolCallUpdate(
                toolCallId: const ToolCallId('tool-1'),
                title: 'Patch file',
                kind: ToolKind.edit,
                status: ToolCallStatus.inProgress,
                content: const [
                  ToolCallContent.diff(
                    diff: Diff(
                      path: '/workspace/lib/app.dart',
                      newText: 'next',
                    ),
                  ),
                ],
                rawInput: const {'path': '/workspace/lib/app.dart'},
              ),
            ),
          ).toJson(),
        ),
      );
      agentTransport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(42),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: const SessionId('session-1'),
            toolCall: ToolCallUpdate(
              toolCallId: const ToolCallId('tool-1'),
              title: 'Patch file',
              kind: ToolKind.edit,
              status: ToolCallStatus.inProgress,
              rawInput: const {'path': '/workspace/lib/app.dart'},
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

      final inspectorEntries = shellCubit.state.inspectorEntries;
      expect(
        inspectorEntries.any(
          (entry) => entry.category == CodeLabInspectorCategory.approval,
        ),
        isTrue,
      );
      expect(
        inspectorEntries.any(
          (entry) =>
              entry.category == CodeLabInspectorCategory.toolCall &&
              entry.title == 'Patch file',
        ),
        isTrue,
      );
      expect(
        inspectorEntries.any(
          (entry) =>
              entry.category == CodeLabInspectorCategory.protocol &&
              entry.title == 'session/update tool_call_update',
        ),
        isTrue,
      );
      expect(
        inspectorEntries
            .expand((entry) => entry.details)
            .map((detail) => detail.value),
        contains('/workspace/lib/app.dart (new)'),
      );
      expect(
        inspectorEntries.map((entry) => entry.rawInput).whereType<String>(),
        anyElement(contains('/workspace/lib/app.dart')),
      );

      await application.respondToPermission(
        const RespondToPermissionCommand.cancelled(
          sessionId: SessionId('session-1'),
          approvalId: ApprovalRequestId('permission-42'),
        ),
      );
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await submitFuture.timeout(const Duration(seconds: 2));

      await closeCodeLabRootScope();
    },
  );

  test('cancelTurn sends session cancel and clears submitting state', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (_) => agentTransport,
    );

    await shellCubit.connect();
    final createRequestFuture = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final createRequest = await createRequestFuture as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    final promptRequestFuture = agentTransport.sent.first;
    final submitFuture = shellCubit.submitPrompt('cancel this');
    final promptRequest = await promptRequestFuture as dynamic;
    expect(shellCubit.state.canCancel, isTrue);

    final cancelRequestFuture = agentTransport.sent.first;
    await shellCubit.cancelTurn();
    final cancelRequest = await cancelRequestFuture as dynamic;

    expect(cancelRequest.method, sessionCancelMethod);
    expect(cancelRequest.params, containsPair('sessionId', 'session-1'));
    expect(shellCubit.state.canCancel, isFalse);
    expect(shellCubit.state.isPromptSubmitting, isFalse);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Cancelled prompt turn'),
    );
    expect(
      shellCubit.state.inspectorEntries
          .firstWhere((entry) => entry.title.startsWith('Prompt turn'))
          .status,
      PromptTurnStatus.cancelled.name,
    );

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'cancelled'},
      ),
    );
    await submitFuture.timeout(const Duration(seconds: 2));

    await shellCubit.close();
    await application.dispose();
  });

  test('submitPrompt reports send failures without crashing', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (_) => agentTransport,
    );

    await shellCubit.connect();
    final createRequestFuture = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final createRequest = await createRequestFuture as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    agentTransport.failNextSend(
      const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'session/prompt send failed',
      ),
    );

    await shellCubit.submitPrompt('hello');

    expect(shellCubit.state.isPromptSubmitting, isFalse);
    expect(shellCubit.state.canCancel, isFalse);
    expect(
      shellCubit.state.transcriptEntries.last.kind,
      AcpTranscriptEntryKind.diagnostic,
    );
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to send prompt'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('connect starts selected stdio transport through application', () async {
    final configs = <StdioAcpTransportConfig>[];
    final initialTransport = FakeAcpTransport();
    final stdioTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return stdioTransport;
      },
    );

    shellCubit.updateStdioCwd('/tmp/codelab');
    shellCubit.updateStdioEnv('CODELAB_LOG_LEVEL=DEBUG\nEXTRA=value');
    await shellCubit.connect();

    expect(configs, [
      const StdioAcpTransportConfig(
        command: 'codelab',
        args: ['serve', '--stdio'],
        cwd: '/tmp/codelab',
        env: {'CODELAB_LOG_LEVEL': 'DEBUG', 'EXTRA': 'value'},
      ),
    ]);
    expect(initialTransport.state, AcpTransportState.closed);
    expect(stdioTransport.state, AcpTransportState.connected);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);
    expect(
      shellCubit.state.diagnostics.map((entry) => entry.message),
      contains('Starting stdio ACP agent: codelab serve --stdio.'),
    );
    expect(
      shellCubit.state.diagnostics.map((entry) => entry.message),
      contains('Stdio ACP agent started: codelab serve --stdio.'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test(
    'reconnect starts replacement stdio transport from editable state',
    () async {
      final configs = <StdioAcpTransportConfig>[];
      final initialTransport = FakeAcpTransport();
      final connectedTransport = FakeAcpTransport();
      final reconnectedTransport = FakeAcpTransport();
      final replacements = [connectedTransport, reconnectedTransport];
      final application = AcpClientApplication(transport: initialTransport);
      final shellCubit = CodeLabShellCubit(
        profile: codelabAgentStdioProfile,
        application: application,
        createSessionUseCase: CreateSession(application),
        sendPromptUseCase: SendPrompt(application),
        cancelTurnUseCase: CancelTurn(application),
        reconnectUseCase: Reconnect(application),
        stdioTransportFactory: (config) {
          configs.add(config);
          return replacements.removeAt(0);
        },
      );

      await shellCubit.connect();
      shellCubit
        ..updateStdioCommand('custom-agent')
        ..updateStdioArgs('serve --stdio --profile local')
        ..updateStdioCwd('/tmp/custom-codelab')
        ..updateStdioEnv('CODELAB_LOG_LEVEL=TRACE\nFEATURE_FLAG=enabled');
      await shellCubit.reconnect();

      expect(configs, [
        const StdioAcpTransportConfig(
          command: 'codelab',
          args: ['serve', '--stdio'],
          env: {'CODELAB_LOG_LEVEL': 'DEBUG'},
        ),
        const StdioAcpTransportConfig(
          command: 'custom-agent',
          args: ['serve', '--stdio', '--profile', 'local'],
          cwd: '/tmp/custom-codelab',
          env: {'CODELAB_LOG_LEVEL': 'TRACE', 'FEATURE_FLAG': 'enabled'},
        ),
      ]);
      expect(connectedTransport.state, AcpTransportState.closed);
      expect(reconnectedTransport.state, AcpTransportState.connected);
      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);
      expect(
        shellCubit.state.diagnostics.map((entry) => entry.message),
        contains(
          'Reconnecting stdio ACP agent: custom-agent serve --stdio --profile local.',
        ),
      );
      expect(
        shellCubit.state.diagnostics.map((entry) => entry.message),
        contains(
          'Stdio ACP agent reconnected: custom-agent serve --stdio --profile local.',
        ),
      );

      await shellCubit.close();
      await application.dispose();
    },
  );

  test('connect reports missing stdio command without crashing', () async {
    final configs = <StdioAcpTransportConfig>[];
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
    );

    shellCubit.updateStdioCommand('');
    await shellCubit.connect();

    expect(configs, isEmpty);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      shellCubit.state.diagnostics.last.message,
      'Stdio command is required before connecting.',
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('connect reports stdio start failure without crashing', () async {
    final configs = <StdioAcpTransportConfig>[];
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return _FailingStartTransport();
      },
    );

    shellCubit.updateStdioCommand('missing-codelab');
    await shellCubit.connect();

    expect(configs.single.command, 'missing-codelab');
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to start stdio ACP agent'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('connect leaves WebSocket startup deferred', () async {
    final configs = <StdioAcpTransportConfig>[];
    final initialTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp');
    await shellCubit.connect();

    expect(configs, isEmpty);
    expect(initialTransport.state, AcpTransportState.idle);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.disconnected);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('WebSocket connect is deferred'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('reconnect leaves WebSocket startup deferred', () async {
    final configs = <StdioAcpTransportConfig>[];
    final initialTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp');
    await shellCubit.reconnect();

    expect(configs, isEmpty);
    expect(initialTransport.state, AcpTransportState.idle);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.disconnected);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('WebSocket reconnect is deferred'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('createSession reports failures without adding a session', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      stdioTransportFactory: (_) => agentTransport,
    );

    await shellCubit.connect();
    agentTransport.failNextSend(
      const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'session/new send failed',
      ),
    );

    await shellCubit.createSession();

    expect(shellCubit.state.sessions, isEmpty);
    expect(shellCubit.state.activeSessionId, isNull);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to create ACP session'),
    );

    await shellCubit.close();
    await application.dispose();
  });
}

final class _FailingStartTransport implements AcpTransport {
  final _inboundController = StreamController<JsonRpcMessage>.broadcast();
  final _eventController = StreamController<AcpTransportEvent>.broadcast();

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  @override
  AcpTransportState get state => AcpTransportState.failed;

  @override
  Future<void> start() async {
    throw const AcpTransportException(
      code: AcpTransportErrorCode.startFailed,
      message: 'Failed to start stdio ACP agent.',
    );
  }

  @override
  Future<void> send(JsonRpcMessage message) async {}

  @override
  Future<void> close({Duration? timeout}) async {
    await _inboundController.close();
    await _eventController.close();
  }
}
