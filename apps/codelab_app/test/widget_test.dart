import 'dart:async';

import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/core/platform/working_directory_provider.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:codelab_app/features/workbench/presentation/workbench_shell.dart'
    show selectPaletteCommand;
import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter/services.dart';
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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

  test('respondToApproval maps a pending approval and resolves it via the use '
      'case', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: initialTransport,
      stdioTransportFactory: (_) => agentTransport,
    );
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
    final submitFuture = shellCubit.submitPrompt('run a command');
    final promptRequest = await promptRequestFuture as dynamic;

    expect(shellCubit.state.pendingApproval, isNull);

    agentTransport.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(7),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('session-1'),
          toolCall: ToolCallUpdate(
            toolCallId: const ToolCallId('tool-1'),
            title: 'Run command',
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

    final pending = shellCubit.state.pendingApproval;
    expect(pending, isNotNull);
    expect(pending!.title, 'Run command');
    expect(pending.risk, AcpApprovalRisk.shell);
    expect(pending.command, 'echo hi');
    expect(pending.options.map((option) => option.id), [
      'allow-once',
      'reject-once',
    ]);

    final permissionResponseFuture = agentTransport.sent.first;
    final respondFuture = shellCubit.respondToApproval('allow-once');
    expect(shellCubit.state.isRespondingToApproval, isTrue);

    final permissionResponse =
        await permissionResponseFuture as JsonRpcResponse;
    expect(permissionResponse.id, const JsonRpcId.integer(7));
    await respondFuture;

    expect(shellCubit.state.isRespondingToApproval, isFalse);
    expect(shellCubit.state.pendingApproval, isNull);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Resolved approval permission-7'),
    );

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture.timeout(const Duration(seconds: 2));

    await closeCodeLabRootScope();
  });

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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return stdioTransport;
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
        respondToPermissionUseCase: RespondToPermission(application),
        stdioTransportFactory: (config) {
          configs.add(config);
          return replacements.removeAt(0);
        },
        workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return _FailingStartTransport();
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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

  test('inspector raw input redacts sensitive tool call fields', () async {
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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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
    final submitFuture = shellCubit.submitPrompt('call the api');
    final promptRequest = await promptRequestFuture as dynamic;

    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.toolCallUpdate(
            toolCallUpdate: ToolCallUpdate(
              toolCallId: const ToolCallId('tool-1'),
              title: 'Call API',
              kind: ToolKind.fetch,
              status: ToolCallStatus.inProgress,
              rawInput: const {
                'url': 'https://api.example.test',
                'apiKey': 'sk-super-secret-value',
              },
            ),
          ),
        ).toJson(),
      ),
    );

    final rawInputs = shellCubit.state.inspectorEntries
        .map((entry) => entry.rawInput)
        .whereType<String>();
    expect(rawInputs, isNotEmpty);
    for (final rawInput in rawInputs) {
      expect(rawInput, isNot(contains('sk-super-secret-value')));
    }
    expect(rawInputs, anyElement(contains(redactedSecret)));

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture.timeout(const Duration(seconds: 2));

    await shellCubit.close();
    await application.dispose();
  });

  test(
    'connect redacts secrets leaked through transport factory failures',
    () async {
      final application = AcpClientApplication(transport: FakeAcpTransport());
      final shellCubit = CodeLabShellCubit(
        profile: codelabAgentStdioProfile,
        application: application,
        createSessionUseCase: CreateSession(application),
        sendPromptUseCase: SendPrompt(application),
        cancelTurnUseCase: CancelTurn(application),
        reconnectUseCase: Reconnect(application),
        respondToPermissionUseCase: RespondToPermission(application),
        stdioTransportFactory: (config) {
          throw StateError('auth failed: token=sk-super-secret-value');
        },
        workingDirectoryProvider: const IoWorkingDirectoryProvider(),
      );

      shellCubit.updateStdioCommand('missing-codelab');
      await shellCubit.connect();

      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
      final message = shellCubit.state.diagnostics.last.message;
      expect(message, contains('Failed to start stdio ACP agent'));
      expect(message, isNot(contains('sk-super-secret-value')));
      expect(message, contains(redactedSecret));

      await shellCubit.close();
      await application.dispose();
    },
  );

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
      respondToPermissionUseCase: RespondToPermission(application),
      stdioTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
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

  testWidgets('Ctrl+K opens the command palette and Esc closes it', (
    tester,
  ) async {
    final binding = CodeLabTestBinding();
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    expect(shellCubit.state.isCommandPaletteOpen, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(shellCubit.state.isCommandPaletteOpen, isTrue);
    expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(shellCubit.state.isCommandPaletteOpen, isFalse);
    expect(find.byType(AcpCommandPaletteSurface), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets('selecting /new from the palette creates a session and closes '
      'it', (tester) async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: initialTransport,
      stdioTransportFactory: (_) => agentTransport,
    );
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    await tester.runAsync(() => shellCubit.connect());
    await tester.pump();
    shellCubit.openCommandPalette();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    final createRequestFuture = agentTransport.sent.first;
    await tester.tap(find.text('/new'));
    await tester.pump(const Duration(milliseconds: 100));

    final createRequest =
        await tester.runAsync(() => createRequestFuture) as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await tester.pump();

    expect(shellCubit.state.activeSessionId, 'session-1');
    expect(shellCubit.state.isCommandPaletteOpen, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets(
    'selecting /reconnect from the palette reconnects and closes it',
    (tester) async {
      final initialTransport = FakeAcpTransport();
      final connectedTransport = FakeAcpTransport();
      final reconnectedTransport = FakeAcpTransport();
      final replacements = [connectedTransport, reconnectedTransport];
      final binding = CodeLabTestBinding(
        transport: initialTransport,
        stdioTransportFactory: (_) => replacements.removeAt(0),
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.runAsync(() => shellCubit.connect());
      await tester.pump();
      shellCubit.openCommandPalette();
      await tester.pump();
      expect(shellCubit.state.isCommandPaletteOpen, isTrue);

      // Select the same way the palette row's onPressed would (tap-driven
      // UI wiring is already covered by the /new test above); reconnect()'s
      // transport teardown/rebind chain needs the real event loop, which a
      // tap handler running inside the fake test zone can't provide, so run
      // it — and wait for it to actually finish — via `tester.runAsync`.
      await tester.runAsync(() async {
        selectPaletteCommand(
          shellCubit,
          AcpCommandAction.defaults.firstWhere((a) => a.id == 'reconnect'),
        );
        while (shellCubit.state.connectionStatus !=
            AcpConnectionStatus.connected) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(connectedTransport.state, AcpTransportState.closed);
      expect(reconnectedTransport.state, AcpTransportState.connected);
      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);
      expect(shellCubit.state.isCommandPaletteOpen, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets('selecting /logs reveals the debug log panel', (tester) async {
    final binding = CodeLabTestBinding();
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    expect(shellCubit.state.isInspectorVisibleInNarrowLayout, isFalse);

    shellCubit.openCommandPalette();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.tap(find.text('/logs'));
    await tester.pump(const Duration(milliseconds: 100));

    // The narrow-layout Offstage toggle that this flag drives is covered
    // directly on `AcpWorkbenchLayout` in acp_organisms_test.dart, at a
    // width narrow enough to trigger it — the full CodeLabApp's command
    // bar isn't adaptive at that width (a pre-existing, unrelated gap), so
    // this test only checks the state/UI wiring this change owns.
    expect(shellCubit.state.isInspectorVisibleInNarrowLayout, isTrue);
    expect(shellCubit.state.isCommandPaletteOpen, isFalse);
    expect(find.byType(AcpDebugLogPanel), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets(
    'selecting an unavailable command keeps the palette open without a '
    'fake diagnostic',
    (tester) async {
      final binding = CodeLabTestBinding();
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      shellCubit.openCommandPalette();
      await tester.pump();
      final diagnosticsBefore = shellCubit.state.diagnostics.length;

      await tester.tap(find.text('/plan'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(shellCubit.state.isCommandPaletteOpen, isTrue);
      expect(shellCubit.state.diagnostics.length, diagnosticsBefore);
      expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets('typing / at the start of the composer opens the inline '
      'palette with the same command set as Ctrl+K', (tester) async {
    final binding = CodeLabTestBinding();
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    await tester.enterText(find.byType(EditableText).last, '/ne');
    await tester.pump();

    expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets(
    'agent-declared commands appear in a separate palette section and are '
    'replaced by later updates',
    (tester) async {
      // A submitted prompt (needed below to attach the available-commands
      // update to an active turn) grows the main pane beyond the default
      // test surface height, so use a taller one.
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialTransport = FakeAcpTransport();
      final agentTransport = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: initialTransport,
        stdioTransportFactory: (_) => agentTransport,
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.runAsync(() => shellCubit.connect());
      await tester.pump();
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest =
          await tester.runAsync(() => createRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await tester.runAsync(() => createFuture);

      expect(shellCubit.state.agentCommands, isEmpty);

      shellCubit.openCommandPalette();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('From agent'), findsNothing);
      for (final action in AcpCommandAction.defaults) {
        expect(find.text(action.slashCommand), findsOneWidget);
      }
      shellCubit.closeCommandPalette();
      await tester.pump();

      // `availableCommandsUpdate` is only applied to the session's active
      // prompt turn (see `SessionStateMachine._applyUpdate` in
      // acp_client_core) — a bare session/update notification with no turn
      // in flight is ignored, so a prompt must be in progress first.
      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt('hello');
      final promptRequest =
          await tester.runAsync(() => promptRequestFuture) as dynamic;

      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.availableCommandsUpdate(
              availableCommands: const [
                AvailableCommand(name: 'deploy', description: 'Deploy the app'),
              ],
            ),
          ).toJson(),
        ),
      );
      await tester.pump();

      expect(
        shellCubit.state.agentCommands.map((action) => action.slashCommand),
        ['/deploy'],
      );

      shellCubit.openCommandPalette();
      // Not pumpAndSettle: the prompt is still in flight, so the composer's
      // Send button is showing a perpetual busy spinner that never settles.
      // Pump repeatedly instead to drain any one-shot transition frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // '/new' is the first row, still visible without scrolling; 'From
      // agent'/'/deploy' sit below the six client rows, so scroll the
      // palette's list to bring them into the built/visible range.
      expect(find.text('/new'), findsOneWidget);
      final paletteScrollable = find.descendant(
        of: find.byKey(AcpCommandPaletteSurface.listKey),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('From agent'),
        100,
        scrollable: paletteScrollable,
      );
      expect(find.text('From agent'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('/deploy'),
        100,
        scrollable: paletteScrollable,
      );
      expect(find.text('/deploy'), findsOneWidget);
      shellCubit.closeCommandPalette();
      await tester.pump();

      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.availableCommandsUpdate(
              availableCommands: const [
                AvailableCommand(
                  name: 'rollback',
                  description: 'Roll back the last deploy',
                ),
              ],
            ),
          ).toJson(),
        ),
      );
      await tester.pump();

      expect(
        shellCubit.state.agentCommands.map((action) => action.slashCommand),
        ['/rollback'],
      );

      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await tester.runAsync(() => submitFuture);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'selecting an agent-declared command inserts it into the composer '
    'instead of executing it',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialTransport = FakeAcpTransport();
      final agentTransport = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: initialTransport,
        stdioTransportFactory: (_) => agentTransport,
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.runAsync(() => shellCubit.connect());
      await tester.pump();
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest =
          await tester.runAsync(() => createRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await tester.runAsync(() => createFuture);

      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt('hello');
      final promptRequest =
          await tester.runAsync(() => promptRequestFuture) as dynamic;

      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.availableCommandsUpdate(
              availableCommands: const [
                AvailableCommand(name: 'deploy', description: 'Deploy the app'),
              ],
            ),
          ).toJson(),
        ),
      );
      await tester.pump();

      final sentBefore = agentTransport.sentMessages.length;

      shellCubit.openCommandPalette();
      // Not pumpAndSettle: the prompt is still in flight, so the composer's
      // Send button is showing a perpetual busy spinner that never settles.
      // Pump repeatedly instead to drain any one-shot transition frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // `/deploy` sits below the six client-native rows in the scrollable
      // list — likely outside the sliver's build range — so scroll toward
      // it (rather than ensureVisible, which requires the element to
      // already be built) before tapping it.
      await tester.scrollUntilVisible(
        find.text('/deploy'),
        100,
        scrollable: find.descendant(
          of: find.byKey(AcpCommandPaletteSurface.listKey),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('/deploy'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(shellCubit.state.isCommandPaletteOpen, isFalse);
      expect(shellCubit.state.composerDraft, '/deploy ');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        '/deploy ',
      );
      expect(agentTransport.sentMessages.length, sentBefore);

      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await tester.runAsync(() => submitFuture);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'switching the active session clears the previous agent command list',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialTransport = FakeAcpTransport();
      final agentTransport = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        transport: initialTransport,
        stdioTransportFactory: (_) => agentTransport,
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.runAsync(() => shellCubit.connect());
      await tester.pump();
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest =
          await tester.runAsync(() => createRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await tester.runAsync(() => createFuture);

      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt('hello');
      final promptRequest =
          await tester.runAsync(() => promptRequestFuture) as dynamic;

      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.availableCommandsUpdate(
              availableCommands: const [
                AvailableCommand(name: 'deploy', description: 'Deploy the app'),
              ],
            ),
          ).toJson(),
        ),
      );
      await tester.pump();
      expect(shellCubit.state.agentCommands, isNotEmpty);

      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await tester.runAsync(() => submitFuture);

      final createRequestFuture2 = agentTransport.sent.first;
      final createFuture2 = shellCubit.createSession();
      final createRequest2 =
          await tester.runAsync(() => createRequestFuture2) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest2.id as JsonRpcId,
          result: const {'sessionId': 'session-2'},
        ),
      );
      await tester.runAsync(() => createFuture2);

      expect(shellCubit.state.agentCommands, isEmpty);

      shellCubit.selectSession('session-1');
      await tester.pump();

      expect(shellCubit.state.agentCommands, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );
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
