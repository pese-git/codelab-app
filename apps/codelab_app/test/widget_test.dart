import 'dart:async';

import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/core/platform/working_directory_provider.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:codelab_app/features/workbench/presentation/widgets/connection_setup_dialog.dart';
import 'package:codelab_app/features/workbench/presentation/workbench_shell.dart'
    show selectPaletteCommand;
import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show TextBox;
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

    await tester.tap(
      find.byKey(const ValueKey('command-bar-configure-connection')),
    );
    await tester.pumpAndSettle();

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

  testWidgets('does not open the connection setup dialog on first run', (
    tester,
  ) async {
    final binding = CodeLabTestBinding();

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    expect(find.byType(ConnectionSetupDialog), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets(
    'Configure connection in the command bar opens the dialog regardless '
    'of transcript state',
    (tester) async {
      final binding = CodeLabTestBinding();

      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

      await tester.tap(
        find.byKey(const ValueKey('command-bar-configure-connection')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionSetupDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'Configure connection on the empty connection screen opens the same '
    'dialog pre-filled with current values',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final binding = CodeLabTestBinding();

      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      final buttonFinder = find.descendant(
        of: find.byType(AcpConnectionScreen),
        matching: find.text('Configure connection'),
      );
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionSetupDialog), findsOneWidget);
      expect(
        tester
            .widget<TextBox>(
              find.byKey(const ValueKey('transport-field-Command')),
            )
            .controller!
            .text,
        shellCubit.state.stdioCommand,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets('editing a field inside the connection setup dialog applies '
      'immediately to shell state', (tester) async {
    final binding = CodeLabTestBinding();

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    await tester.tap(
      find.byKey(const ValueKey('command-bar-configure-connection')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      'custom-agent',
    );
    await tester.pump();

    expect(shellCubit.state.stdioCommand, 'custom-agent');

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });

  testWidgets(
    'Esc closes the connection setup dialog and keeps the last-edited '
    'field values',
    (tester) async {
      final binding = CodeLabTestBinding();

      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.tap(
        find.byKey(const ValueKey('command-bar-configure-connection')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        'custom-agent',
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionSetupDialog), findsNothing);
      expect(shellCubit.state.stdioCommand, 'custom-agent');
      expect(
        shellCubit.state.connectionStatus,
        AcpConnectionStatus.disconnected,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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

  test('submitPrompt coalesces consecutive agent_message_chunk updates into a '
      'single, growing transcript entry', () async {
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
    final submitFuture = shellCubit.submitPrompt('hello agent');
    final promptRequest = await promptRequestFuture as dynamic;

    void sendMessageChunk(String text) {
      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: SessionUpdate.agentMessageChunk(
              content: ContentBlock.text(text: text),
            ),
          ).toJson(),
        ),
      );
    }

    sendMessageChunk('hi ');

    final agentEntriesAfterFirstChunk = shellCubit.state.transcriptEntries
        .where((entry) => entry.title == 'Agent')
        .toList();
    expect(agentEntriesAfterFirstChunk, hasLength(1));
    expect(agentEntriesAfterFirstChunk.single.body, 'hi');
    expect(
      shellCubit.state.isPromptSubmitting,
      isTrue,
      reason:
          'the entry above must already be visible while the turn is '
          'still running, not only once it completes',
    );
    final growingEntryId = agentEntriesAfterFirstChunk.single.id;

    sendMessageChunk('from ');
    sendMessageChunk('agent');

    final agentEntriesWhileRunning = shellCubit.state.transcriptEntries
        .where((entry) => entry.title == 'Agent')
        .toList();
    expect(
      agentEntriesWhileRunning,
      hasLength(1),
      reason:
          'consecutive agent_message_chunk updates must coalesce into '
          'one entry instead of one per chunk',
    );
    expect(agentEntriesWhileRunning.single.body, 'hi from agent');
    expect(
      agentEntriesWhileRunning.single.id,
      growingEntryId,
      reason: 'the growing entry keeps its id stable as more chunks arrive',
    );

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture;

    final finalAgentEntries = shellCubit.state.transcriptEntries
        .where((entry) => entry.title == 'Agent')
        .toList();
    expect(finalAgentEntries, hasLength(1));
    expect(finalAgentEntries.single.body, 'hi from agent');
    expect(finalAgentEntries.single.id, growingEntryId);

    await shellCubit.close();
    await application.dispose();
  });

  test('a tool call update between two agent_message_chunk runs starts a new '
      'transcript entry instead of merging their text', () async {
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
    final submitFuture = shellCubit.submitPrompt('inspect tool');
    final promptRequest = await promptRequestFuture as dynamic;

    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'let me check the file'),
          ),
        ).toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.toolCallUpdate(
            toolCallUpdate: ToolCallUpdate(
              toolCallId: const ToolCallId('tool-1'),
              title: 'Read file',
              kind: ToolKind.read,
              status: ToolCallStatus.completed,
            ),
          ),
        ).toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'here is what I found'),
          ),
        ).toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture;

    final agentEntries = shellCubit.state.transcriptEntries
        .where((entry) => entry.title == 'Agent')
        .toList();
    expect(agentEntries, hasLength(2));
    expect(agentEntries[0].body, 'let me check the file');
    expect(agentEntries[1].body, 'here is what I found');

    await shellCubit.close();
    await application.dispose();
  });

  test(
    'SessionUpdate.toolCall entries appear in the transcript at the '
    'position they were created, ahead of any pending completion text',
    () async {
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
        setSessionConfigOptionUseCase: SetSessionConfigOption(application),
        stdioTransportFactory: (_) => agentTransport,
        webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      final submitFuture = shellCubit.submitPrompt('inspect two files');
      final promptRequest = await promptRequestFuture as dynamic;

      void emitToolCall(ToolCall toolCall) {
        agentTransport.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: SessionNotification(
              sessionId: const SessionId('session-1'),
              update: SessionUpdate.toolCall(toolCall: toolCall),
            ).toJson(),
          ),
        );
      }

      void emitAgentText(String text) {
        agentTransport.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: SessionNotification(
              sessionId: const SessionId('session-1'),
              update: SessionUpdate.agentMessageChunk(
                content: ContentBlock.text(text: text),
              ),
            ).toJson(),
          ),
        );
      }

      emitAgentText('before');
      emitToolCall(
        const ToolCall(
          toolCallId: ToolCallId('tool-a'),
          title: 'Read config',
          kind: ToolKind.read,
          status: ToolCallStatus.inProgress,
        ),
      );

      // Several tool calls in a row, back to back.
      emitToolCall(
        const ToolCall(
          toolCallId: ToolCallId('tool-b'),
          title: 'Run build',
          kind: ToolKind.execute,
          status: ToolCallStatus.pending,
        ),
      );

      // A tool call with no completion text yet, mid-turn (not terminal) —
      // it must already be visible, not held back until the turn ends.
      expect(shellCubit.state.canCancel, isTrue);
      final midStreamEntries = shellCubit.state.transcriptEntries;
      expect(midStreamEntries.last.title, 'Run build');
      expect(midStreamEntries.last.toolCall!.status, AcpToolCallStatus.queued);

      emitAgentText('after');
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await submitFuture;

      final titles = shellCubit.state.transcriptEntries
          .map((entry) => entry.title)
          .toList();
      expect(titles, ['You', 'Agent', 'Read config', 'Run build', 'Agent']);

      final readConfigEntry = shellCubit.state.transcriptEntries[2];
      expect(readConfigEntry.toolCall!.name, 'read');
      expect(readConfigEntry.toolCall!.status, AcpToolCallStatus.running);

      await shellCubit.close();
      await application.dispose();
    },
  );

  test('switching from agent_message_chunk to agent_thought_chunk starts a new '
      'transcript entry instead of merging their text', () async {
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
    final submitFuture = shellCubit.submitPrompt('think then answer');
    final promptRequest = await promptRequestFuture as dynamic;

    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.agentThoughtChunk(
            content: ContentBlock.text(text: 'thinking it through'),
          ),
        ).toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'here is the answer'),
          ),
        ).toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture;

    final agentEntries = shellCubit.state.transcriptEntries
        .where((entry) => entry.title == 'Agent')
        .toList();
    expect(agentEntries, hasLength(2));
    expect(agentEntries[0].body, 'thinking it through');
    expect(agentEntries[1].body, 'here is the answer');

    await shellCubit.close();
    await application.dispose();
  });

  test('a spontaneous transport failure while a turn is running marks the '
      'connection failed and clears the now-unreliable active-request state, '
      'without discarding the transcript', () async {
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
    );

    shellCubit.updateStdioCwd('/workspace');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

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
    final submitFuture = shellCubit.submitPrompt('hello agent');
    await promptRequestFuture;
    expect(shellCubit.state.isPromptSubmitting, isTrue);
    expect(shellCubit.state.canCancel, isTrue);

    // The agent's process dies mid-turn — the transport reports it as an
    // unexpected failure, exactly like `StdioAcpTransport._handleProcessExit`
    // does for a real child process exit.
    agentTransport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code -9.',
      ),
    );

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(shellCubit.state.isPromptSubmitting, isFalse);
    expect(shellCubit.state.canCancel, isFalse);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Connection to ACP agent lost'),
    );
    // The transcript up to the point of failure is history, not part of
    // the now-untrustworthy active request — it must stay visible.
    expect(shellCubit.state.transcriptEntries, isNotEmpty);
    expect(shellCubit.state.transcriptEntries.last.body, 'hello agent');

    // `submitFuture` itself never resolves on its own at this point — a
    // spontaneous transport failure doesn't fail pending requests (only an
    // explicit `_replaceTransport`/`dispose()` does), and that's fine: the
    // UI-facing state above is already corrected by the connection-loss
    // handler, independently of this dangling call (resuming/settling the
    // request itself is out of scope — see design.md Non-Goals). `dispose()`
    // is what finally fails it (same as any other pending request) — await
    // it before closing the cubit, so its catch-driven `emit` lands while
    // the cubit is still open rather than crashing on a closed BlocBase.
    await application.dispose();
    await submitFuture;
    await shellCubit.close();
  });

  test('an explicit connect() failure is not duplicated by the spontaneous '
      'connection-loss handler', () async {
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return _FailingStartTransport();
      },
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
    );

    shellCubit.updateStdioCommand('missing-codelab');
    await shellCubit.connect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    final lossMessages = shellCubit.state.diagnostics.where(
      (entry) => entry.message.contains('Connection to ACP agent lost'),
    );
    expect(lossMessages, isEmpty);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to start stdio ACP agent'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('an explicit reconnect() failure is not duplicated by the spontaneous '
      'connection-loss handler', () async {
    final initialTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    var reconnectAttempts = 0;
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      respondToPermissionUseCase: RespondToPermission(application),
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) {
        reconnectAttempts += 1;
        // The first call is the initial connect(); the second is the
        // reconnect() under test, which must fail.
        return reconnectAttempts == 1
            ? FakeAcpTransport()
            : _FailingStartTransport();
      },
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
    );

    shellCubit.updateStdioCwd('/workspace');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    await shellCubit.reconnect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    final lossMessages = shellCubit.state.diagnostics.where(
      (entry) => entry.message.contains('Connection to ACP agent lost'),
    );
    expect(lossMessages, isEmpty);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to reconnect stdio ACP agent'),
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

    AcpTranscriptEntry? pendingApprovalEntry() {
      final matches = shellCubit.state.transcriptEntries
          .where((entry) => entry.approval is AcpTranscriptApprovalPending)
          .toList();
      return matches.isEmpty ? null : matches.single;
    }

    expect(pendingApprovalEntry(), isNull);

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

    final pendingEntry = pendingApprovalEntry();
    expect(pendingEntry, isNotNull);
    expect(pendingEntry!.title, 'Run command');
    final pending = pendingEntry.approval! as AcpTranscriptApprovalPending;
    expect(pending.risk, AcpApprovalRisk.shell);
    expect(pending.command, 'echo hi');
    expect(pending.options.map((option) => option.id), [
      'allow-once',
      'reject-once',
    ]);

    final permissionResponseFuture = agentTransport.sent.first;
    // Calls the cubit method directly (rather than `pending.onOptionSelected`,
    // a `void Function` that can't be awaited) — this is what that callback
    // invokes under the hood; see `_transcriptApproval` in shell_cubit.dart.
    final respondFuture = shellCubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-7'),
      sessionId: const SessionId('session-1'),
      optionId: 'allow-once',
    );
    expect(shellCubit.state.isRespondingToApproval, isTrue);

    final permissionResponse =
        await permissionResponseFuture as JsonRpcResponse;
    expect(permissionResponse.id, const JsonRpcId.integer(7));
    await respondFuture;

    expect(shellCubit.state.isRespondingToApproval, isFalse);
    expect(pendingApprovalEntry(), isNull);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Resolved approval permission-7'),
    );

    // The entry stays in the transcript, collapsed to a resolved marker —
    // it does not disappear (embed-approval-in-thread/specs/
    // agent-workbench-ui: "Approval остаётся в истории после решения").
    final resolvedEntries = shellCubit.state.transcriptEntries
        .where((entry) => entry.approval is AcpTranscriptApprovalResolved)
        .toList();
    expect(resolvedEntries, hasLength(1));
    expect(resolvedEntries.single.title, 'Run command');
    expect(
      (resolvedEntries.single.approval! as AcpTranscriptApprovalResolved).label,
      'Allow once',
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

  test('two parallel pending approvals are both embedded independently, and '
      'only the earliest-requested one owns keyboard shortcuts', () async {
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
    final submitFuture = shellCubit.submitPrompt('run two commands');
    final promptRequest = await promptRequestFuture as dynamic;

    RequestPermissionRequest permissionRequestFor(
      String toolCallId,
      String title,
    ) {
      return RequestPermissionRequest(
        sessionId: const SessionId('session-1'),
        toolCall: ToolCallUpdate(
          toolCallId: ToolCallId(toolCallId),
          title: title,
          kind: ToolKind.execute,
          status: ToolCallStatus.inProgress,
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
      );
    }

    agentTransport.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(1),
        method: sessionRequestPermissionMethod,
        params: permissionRequestFor('tool-1', 'Run first command').toJson(),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(2),
        method: sessionRequestPermissionMethod,
        params: permissionRequestFor('tool-2', 'Run second command').toJson(),
      ),
    );

    final pendingEntries = shellCubit.state.transcriptEntries
        .where((entry) => entry.approval is AcpTranscriptApprovalPending)
        .toList();
    expect(pendingEntries, hasLength(2));
    expect(pendingEntries[0].title, 'Run first command');
    expect(pendingEntries[1].title, 'Run second command');

    final firstApproval =
        pendingEntries[0].approval! as AcpTranscriptApprovalPending;
    final secondApproval =
        pendingEntries[1].approval! as AcpTranscriptApprovalPending;
    expect(
      firstApproval.shortcutsEnabled,
      isTrue,
      reason: 'the earliest-requested pending approval owns the shortcut',
    );
    expect(
      secondApproval.shortcutsEnabled,
      isFalse,
      reason:
          'a later pending approval stays mouse-only until the first '
          'one resolves',
    );

    final firstResponseFuture = agentTransport.sent.first;
    await shellCubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-1'),
      sessionId: const SessionId('session-1'),
      optionId: 'allow-once',
    );
    await firstResponseFuture;

    // The second approval — now the only one still pending — takes over
    // the shortcut.
    final remainingPending = shellCubit.state.transcriptEntries
        .where((entry) => entry.approval is AcpTranscriptApprovalPending)
        .toList();
    expect(remainingPending, hasLength(1));
    expect(
      (remainingPending.single.approval! as AcpTranscriptApprovalPending)
          .shortcutsEnabled,
      isTrue,
    );

    // Resolve the second approval before the turn ends — a turn already
    // terminal ignores approval selection (see `_selectApproval` in
    // `state_machines.dart`), same as it would for a real agent.
    await shellCubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-2'),
      sessionId: const SessionId('session-1'),
      optionId: 'allow-once',
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return stdioTransport;
      },
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
        setSessionConfigOptionUseCase: SetSessionConfigOption(application),
        stdioTransportFactory: (config) {
          configs.add(config);
          return replacements.removeAt(0);
        },
        webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (config) {
        configs.add(config);
        return _FailingStartTransport();
      },
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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

  test('connect starts WebSocket ACP transport with configured endpoint and '
      'token', () async {
    final configs = <WebSocketAcpTransportConfig>[];
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => FakeAcpTransport(),
      webSocketTransportFactory: (config) {
        configs.add(config);
        return agentTransport;
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp')
      ..updateWebSocketToken('secret-token');
    await shellCubit.connect();

    expect(configs, [
      WebSocketAcpTransportConfig(
        uri: Uri.parse('wss://agent.example.test/acp'),
        token: 'secret-token',
      ),
    ]);
    expect(agentTransport.state, AcpTransportState.connected);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);
    expect(
      shellCubit.state.diagnostics.map((entry) => entry.message),
      contains('WebSocket ACP agent connected: wss://agent.example.test/acp.'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test(
    'reconnect starts replacement WebSocket transport from editable state',
    () async {
      final configs = <WebSocketAcpTransportConfig>[];
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
        setSessionConfigOptionUseCase: SetSessionConfigOption(application),
        stdioTransportFactory: (_) => FakeAcpTransport(),
        webSocketTransportFactory: (config) {
          configs.add(config);
          return replacements.removeAt(0);
        },
        workingDirectoryProvider: const IoWorkingDirectoryProvider(),
      );

      shellCubit
        ..selectTransport(CodeLabTransportType.webSocket)
        ..updateWebSocketEndpoint('wss://agent.example.test/acp')
        ..updateWebSocketToken('initial-token');
      await shellCubit.connect();

      shellCubit
        ..updateWebSocketEndpoint('wss://agent.example.test/acp-v2')
        ..updateWebSocketToken('rotated-token');
      await shellCubit.reconnect();

      expect(configs, [
        WebSocketAcpTransportConfig(
          uri: Uri.parse('wss://agent.example.test/acp'),
          token: 'initial-token',
        ),
        WebSocketAcpTransportConfig(
          uri: Uri.parse('wss://agent.example.test/acp-v2'),
          token: 'rotated-token',
        ),
      ]);
      expect(connectedTransport.state, AcpTransportState.closed);
      expect(reconnectedTransport.state, AcpTransportState.connected);
      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);
      expect(
        shellCubit.state.diagnostics.map((entry) => entry.message),
        contains(
          'Reconnecting WebSocket ACP agent: wss://agent.example.test/acp-v2.',
        ),
      );
      expect(
        shellCubit.state.diagnostics.map((entry) => entry.message),
        contains(
          'WebSocket ACP agent reconnected: wss://agent.example.test/acp-v2.',
        ),
      );

      await shellCubit.close();
      await application.dispose();
    },
  );

  test('reconnect reports WebSocket failure without crashing', () async {
    final initialTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    var attempts = 0;
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      createSessionUseCase: CreateSession(application),
      sendPromptUseCase: SendPrompt(application),
      cancelTurnUseCase: CancelTurn(application),
      reconnectUseCase: Reconnect(application),
      respondToPermissionUseCase: RespondToPermission(application),
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => FakeAcpTransport(),
      webSocketTransportFactory: (_) {
        attempts += 1;
        // The first call is the initial connect(); the second is the
        // reconnect() under test, which must fail (e.g. auth rejected).
        return attempts == 1 ? FakeAcpTransport() : _FailingStartTransport();
      },
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    await shellCubit.reconnect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      shellCubit.state.diagnostics.last.message,
      contains('Failed to reconnect WebSocket ACP agent'),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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
        setSessionConfigOptionUseCase: SetSessionConfigOption(application),
        stdioTransportFactory: (config) {
          throw StateError('auth failed: token=sk-super-secret-value');
        },
        webSocketTransportFactory: (_) => FakeAcpTransport(),
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
      setSessionConfigOptionUseCase: SetSessionConfigOption(application),
      stdioTransportFactory: (_) => agentTransport,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
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

      // No prompt is in flight here on purpose: ACP lets an agent send
      // `available_commands_update` at any time, including right after
      // `session/new` before the user has typed anything — this must not
      // require an active turn to take effect.
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
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
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

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'selecting an agent-declared command inserts it into the composer '
    'instead of executing it',
    (tester) async {
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
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
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

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'switching sessions reloads each session\'s own agent command list '
    'instead of clearing it unconditionally',
    (tester) async {
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

      // session-2 has not declared any commands of its own.
      expect(shellCubit.state.agentCommands, isEmpty);

      // Switching back to session-1 restores *its* command list — it was
      // never actually lost, session-1 just wasn't the active session.
      shellCubit.selectSession('session-1');
      await tester.pump();

      expect(
        shellCubit.state.agentCommands.map((action) => action.slashCommand),
        contains('/deploy'),
      );

      // Switching to session-2 again shows its (still empty) list, not
      // session-1's, proving this isn't just "never clear again".
      shellCubit.selectSession('session-2');
      await tester.pump();

      expect(shellCubit.state.agentCommands, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  test('switching sessions reloads transcript, inspector and pending approval '
      'for the newly selected session instead of leaving the previous '
      'session\'s state visible', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: initialTransport,
      stdioTransportFactory: (_) => agentTransport,
    );
    final application = binding.scope.resolve<AcpClientApplication>();
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    await shellCubit.connect();

    // session-1: create it, submit a prompt, and leave an approval
    // pending on it.
    final createRequestFuture1 = agentTransport.sent.first;
    final createFuture1 = shellCubit.createSession();
    final createRequest1 = await createRequestFuture1 as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest1.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture1;

    final promptRequestFuture1 = agentTransport.sent.first;
    final submitFuture1 = shellCubit.submitPrompt('work on session one');
    final promptRequest1 = await promptRequestFuture1 as dynamic;

    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: const ContentBlock.text(text: 'Working on it.'),
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

    AcpTranscriptEntry? pendingApprovalEntry() {
      final matches = shellCubit.state.transcriptEntries
          .where((entry) => entry.approval is AcpTranscriptApprovalPending)
          .toList();
      return matches.isEmpty ? null : matches.single;
    }

    expect(shellCubit.state.transcriptEntries, isNotEmpty);
    expect(pendingApprovalEntry(), isNotNull);
    final session1Transcript = shellCubit.state.transcriptEntries;

    // session-2: a fresh session with none of that state.
    final createRequestFuture2 = agentTransport.sent.first;
    final createFuture2 = shellCubit.createSession();
    final createRequest2 = await createRequestFuture2 as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest2.id as JsonRpcId,
        result: const {'sessionId': 'session-2'},
      ),
    );
    await createFuture2;

    // Creating session-2 must not leave session-1's transcript/approval
    // visible.
    expect(shellCubit.state.transcriptEntries, isEmpty);
    expect(pendingApprovalEntry(), isNull);

    // Switching back to session-1 must restore its transcript and pending
    // approval — not leave session-2's (empty) state showing.
    shellCubit.selectSession('session-1');

    expect(shellCubit.state.transcriptEntries, isNotEmpty);
    expect(
      shellCubit.state.transcriptEntries.map((entry) => entry.body),
      containsAll(session1Transcript.map((entry) => entry.body)),
    );
    expect(pendingApprovalEntry(), isNotNull);
    expect(pendingApprovalEntry()!.title, 'Patch file');

    // Switching to session-2 again must clear session-1's state again.
    shellCubit.selectSession('session-2');

    expect(shellCubit.state.transcriptEntries, isEmpty);
    expect(pendingApprovalEntry(), isNull);

    await application.respondToPermission(
      const RespondToPermissionCommand.cancelled(
        sessionId: SessionId('session-1'),
        approvalId: ApprovalRequestId('permission-42'),
      ),
    );
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest1.id as JsonRpcId,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await submitFuture1.timeout(const Duration(seconds: 2));

    await closeCodeLabRootScope();
  });

  testWidgets(
    'a config option the agent declared at session/new shows up as a chip '
    'in the composer',
    (tester) async {
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
          result: {
            'sessionId': 'session-1',
            'configOptions': [
              {
                'type': 'select',
                'id': 'model',
                'name': 'Model',
                'currentValue': 'gpt-5',
                'options': [
                  {'value': 'gpt-5', 'name': 'GPT-5'},
                  {'value': 'gpt-4', 'name': 'GPT-4'},
                ],
              },
            ],
          },
        ),
      );
      await tester.runAsync(() => createFuture);
      await tester.pump();

      expect(shellCubit.state.configOptions, hasLength(1));
      expect(shellCubit.state.configOptions.single.id, 'model');
      expect(shellCubit.state.configOptions.single.currentValue, 'gpt-5');
      expect(find.text('GPT-5'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    },
  );

  test('selecting a config option value sends session/set_config_option and '
      "reflects the agent's response, not the tapped value directly", () async {
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
        result: {
          'sessionId': 'session-1',
          'configOptions': [
            {
              'type': 'select',
              'id': 'model',
              'name': 'Model',
              'currentValue': 'gpt-5',
              'options': [
                {'value': 'gpt-5', 'name': 'GPT-5'},
                {'value': 'gpt-4', 'name': 'GPT-4'},
              ],
            },
          ],
        },
      ),
    );
    await createFuture;

    final setRequestFuture = agentTransport.sent.first;
    final setFuture = shellCubit.setSessionConfigOption('model', 'gpt-4');
    final setRequest = await setRequestFuture as dynamic;
    expect(setRequest.method, sessionSetConfigOptionMethod);
    expect(
      SetSessionConfigOptionRequest.fromJson(setRequest.params),
      const SetSessionConfigOptionRequest(
        sessionId: SessionId('session-1'),
        configId: SessionConfigId('model'),
        value: SessionConfigValueId('gpt-4'),
      ),
    );

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: setRequest.id as JsonRpcId,
        result: {
          'configOptions': [
            {
              'type': 'select',
              'id': 'model',
              'name': 'Model',
              'currentValue': 'gpt-4',
              'options': [
                {'value': 'gpt-5', 'name': 'GPT-5'},
                {'value': 'gpt-4', 'name': 'GPT-4'},
              ],
            },
          ],
        },
      ),
    );
    await setFuture;

    expect(shellCubit.state.configOptions.single.currentValue, 'gpt-4');
    expect(shellCubit.state.isRespondingToConfigOption, isFalse);

    await closeCodeLabRootScope();
  });

  test('a config_option_update without an active turn updates the config '
      'options shown for the session', () async {
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

    expect(shellCubit.state.configOptions, isEmpty);

    // No prompt is in flight here on purpose — per ACP
    // (docs/acp/protocol/13-Session Config Options.md), an agent may send
    // config_option_update "at any point during a session", not just
    // during a prompt turn.
    agentTransport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: SessionUpdate.configOptionUpdate(
            configOptions: const [
              SessionConfigOption.select(
                id: SessionConfigId('mode'),
                name: 'Session Mode',
                currentValue: SessionConfigValueId('ask'),
                options: [
                  SessionConfigSelectOption(
                    value: SessionConfigValueId('ask'),
                    name: 'Ask',
                  ),
                ],
              ),
            ],
          ),
        ).toJson(),
      ),
    );

    expect(shellCubit.state.configOptions, hasLength(1));
    expect(shellCubit.state.configOptions.single.id, 'mode');
    expect(shellCubit.state.configOptions.single.currentValue, 'ask');

    await closeCodeLabRootScope();
  });

  test("switching sessions shows the newly active session's own config "
      'options, not the previous session\'s', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: initialTransport,
      stdioTransportFactory: (_) => agentTransport,
    );
    final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

    await shellCubit.connect();

    final createRequestFuture1 = agentTransport.sent.first;
    final createFuture1 = shellCubit.createSession();
    final createRequest1 = await createRequestFuture1 as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest1.id as JsonRpcId,
        result: {
          'sessionId': 'session-1',
          'configOptions': [
            {
              'type': 'select',
              'id': 'model',
              'name': 'Model',
              'currentValue': 'gpt-5',
              'options': [
                {'value': 'gpt-5', 'name': 'GPT-5'},
              ],
            },
          ],
        },
      ),
    );
    await createFuture1;

    expect(shellCubit.state.configOptions, hasLength(1));

    final createRequestFuture2 = agentTransport.sent.first;
    final createFuture2 = shellCubit.createSession();
    final createRequest2 = await createRequestFuture2 as dynamic;
    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: createRequest2.id as JsonRpcId,
        result: const {'sessionId': 'session-2'},
      ),
    );
    await createFuture2;

    expect(shellCubit.state.configOptions, isEmpty);

    shellCubit.selectSession('session-1');

    expect(shellCubit.state.configOptions, hasLength(1));
    expect(shellCubit.state.configOptions.single.currentValue, 'gpt-5');

    shellCubit.selectSession('session-2');

    expect(shellCubit.state.configOptions, isEmpty);

    await closeCodeLabRootScope();
  });

  group('resizable workbench panels', () {
    Future<CodeLabTestBinding> pumpDesktopShell(WidgetTester tester) async {
      final binding = CodeLabTestBinding();
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      return binding;
    }

    testWidgets(
      'dragging the sessions/main divider live-resizes the pane before the '
      'drag ends, without emitting to the cubit mid-drag',
      (tester) async {
        final binding = await pumpDesktopShell(tester);
        final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

        final handle = find.byType(AcpResizeHandle).first;
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();

        expect(
          tester.getSize(find.byKey(AcpWorkbenchLayout.sessionsPaneKey)).width,
          closeTo(320, 1),
        );
        expect(shellCubit.state.sessionsPaneWidth, 280);

        await gesture.up();
        await tester.pump();

        expect(shellCubit.state.sessionsPaneWidth, closeTo(320, 1));

        await tester.pumpWidget(const SizedBox.shrink());
        await closeCodeLabRootScope();
      },
    );

    testWidgets(
      'dragging the main/inspector divider left grows the inspector pane',
      (tester) async {
        final binding = await pumpDesktopShell(tester);
        final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

        await tester.drag(
          find.byType(AcpResizeHandle).last,
          const Offset(-40, 0),
        );
        await tester.pump();

        expect(shellCubit.state.inspectorPaneWidth, closeTo(360, 1));
        expect(
          tester.getSize(find.byKey(AcpWorkbenchLayout.inspectorPaneKey)).width,
          closeTo(360, 1),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await closeCodeLabRootScope();
      },
    );

    testWidgets('dragging the sessions divider past the minimum stops at the '
        'configured floor', (tester) async {
      final binding = await pumpDesktopShell(tester);
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.drag(
        find.byType(AcpResizeHandle).first,
        const Offset(-1000, 0),
      );
      await tester.pump();

      expect(shellCubit.state.sessionsPaneWidth, kSessionsPaneMinWidth);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });

    testWidgets('dragging the sessions divider past the maximum stops at the '
        'configured ceiling', (tester) async {
      final binding = await pumpDesktopShell(tester);
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.drag(
        find.byType(AcpResizeHandle).first,
        const Offset(1000, 0),
      );
      await tester.pump();

      expect(shellCubit.state.sessionsPaneWidth, kSessionsPaneMaxWidth);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });

    testWidgets('dragging the inspector divider past the minimum stops at '
        'the configured floor', (tester) async {
      final binding = await pumpDesktopShell(tester);
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      // Dragging right shrinks the inspector (its divider sits on its left
      // edge) — the mirror image of the sessions-pane min test.
      await tester.drag(
        find.byType(AcpResizeHandle).last,
        const Offset(1000, 0),
      );
      await tester.pump();

      expect(shellCubit.state.inspectorPaneWidth, kInspectorPaneMinWidth);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });

    testWidgets('dragging the inspector divider past the maximum stops at '
        'the configured ceiling', (tester) async {
      final binding = await pumpDesktopShell(tester);
      final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

      await tester.drag(
        find.byType(AcpResizeHandle).last,
        const Offset(-1000, 0),
      );
      await tester.pump();

      expect(shellCubit.state.inspectorPaneWidth, kInspectorPaneMaxWidth);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });

    testWidgets(
      'a resized pane keeps its width across a rebuild triggered by an '
      'unrelated state change',
      (tester) async {
        final binding = await pumpDesktopShell(tester);
        final shellCubit = binding.scope.resolve<CodeLabShellCubit>();

        await tester.drag(
          find.byType(AcpResizeHandle).first,
          const Offset(40, 0),
        );
        await tester.pump();

        expect(shellCubit.state.sessionsPaneWidth, closeTo(320, 1));

        // Unrelated state change: opening the command palette.
        shellCubit.openCommandPalette();
        await tester.pump();

        expect(shellCubit.state.sessionsPaneWidth, closeTo(320, 1));
        expect(
          tester.getSize(find.byKey(AcpWorkbenchLayout.sessionsPaneKey)).width,
          closeTo(320, 1),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await closeCodeLabRootScope();
      },
    );
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
