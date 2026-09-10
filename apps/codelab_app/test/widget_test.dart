import 'dart:async';

import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/core/platform/project_folder_picker.dart';
import 'package:codelab_app/core/platform/recent_projects_store.dart';
import 'package:codelab_app/core/platform/working_directory_provider.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:codelab_app/features/workbench/presentation/widgets/connection_setup_dialog.dart';
import 'package:codelab_app/features/workbench/presentation/widgets/debug_log_viewer_dialog.dart';
import 'package:codelab_app/features/workbench/presentation/widgets/main_pane.dart';
import 'package:codelab_app/features/workbench/presentation/workbench_shell.dart'
    show selectPaletteCommand;
import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentApp, TextBox;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:structured_log_fluent/structured_log_fluent.dart'
    show FluentLogViewerPage;

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

    expect(
      binding.scope.resolve<LogBuffer>().entries.value.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    await shellCubit.selectProject('/workspace');
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
      logger.entries.map((entry) => entry['event']),
      contains('Created ACP session session-1.'),
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('createSession sends the selected project as cwd over WebSocket too, '
      'the same as it does for stdio', () async {
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
      webSocketTransportFactory: (_) => agentTransport,
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp');
    await shellCubit.selectProject('/remote/workspace');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    final sentRequest = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final request = await sentRequest as dynamic;
    expect(request.method, 'session/new');
    expect(request.params, containsPair('cwd', '/remote/workspace'));

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: request.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    await shellCubit.close();
    await application.dispose();
  });

  test('createSession falls back to the process cwd when no project is '
      'selected', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    const workingDirectoryProvider = IoWorkingDirectoryProvider();
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
      workingDirectoryProvider: workingDirectoryProvider,
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
    );

    await shellCubit.connect();
    final sentRequest = agentTransport.sent.first;
    final createFuture = shellCubit.createSession();
    final request = await sentRequest as dynamic;
    expect(
      request.params,
      containsPair('cwd', workingDirectoryProvider.currentPath),
    );

    agentTransport.emitInbound(
      JsonRpcMessage.response(
        id: request.id as JsonRpcId,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await createFuture;

    await shellCubit.close();
    await application.dispose();
  });

  test("_stdioConfigFromState's cwd follows runAgentFromProjectDirectory: on "
      'matches the selected project, off is null', () async {
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
    );

    await shellCubit.selectProject('/workspace');
    expect(shellCubit.state.runAgentFromProjectDirectory, isTrue);
    await shellCubit.connect();
    expect(configs.single.cwd, '/workspace');

    shellCubit.toggleRunAgentFromProjectDirectory(false);
    await shellCubit.reconnect();
    expect(configs[1].cwd, isNull);
    // The selected project itself is untouched by the toggle.
    expect(shellCubit.state.selectedProjectPath, '/workspace');

    await shellCubit.close();
    await application.dispose();
  });

  test('submitPrompt sends text content and records agent response', () async {
    final initialTransport = FakeAcpTransport();
    final agentTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    await shellCubit.selectProject('/workspace');
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
      logger.entries.last['event'],
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    await shellCubit.selectProject('/workspace');
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
      logger.entries.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    shellCubit.updateStdioCommand('missing-codelab');
    await shellCubit.connect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    final lossMessages = logger.entries.where(
      (entry) => (entry['event'] as String? ?? '').contains('Connection to ACP agent lost'),
    );
    expect(lossMessages, isEmpty);
    expect(
      logger.entries.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    await shellCubit.selectProject('/workspace');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    await shellCubit.reconnect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    final lossMessages = logger.entries.where(
      (entry) => (entry['event'] as String? ?? '').contains('Connection to ACP agent lost'),
    );
    expect(lossMessages, isEmpty);
    expect(
      logger.entries.last['event'],
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
      binding.scope.resolve<LogBuffer>().entries.value.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
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
      logger.entries.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
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
      logger.entries.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    await shellCubit.selectProject('/tmp/codelab');
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
      logger.entries.map((entry) => entry['event']),
      contains('Starting stdio ACP agent: codelab serve --stdio.'),
    );
    expect(
      logger.entries.map((entry) => entry['event']),
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
      final logger = _RecordingLogger();
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
        logger: logger,
      );

      await shellCubit.connect();
      shellCubit
        ..updateStdioCommand('custom-agent')
        ..updateStdioArgs('serve --stdio --profile local')
        ..updateStdioEnv('CODELAB_LOG_LEVEL=TRACE\nFEATURE_FLAG=enabled');
      await shellCubit.selectProject('/tmp/custom-codelab');
      await shellCubit.reconnect();

      expect(configs, [
        StdioAcpTransportConfig(
          command: 'codelab',
          args: const ['serve', '--stdio'],
          cwd: const IoWorkingDirectoryProvider().currentPath,
          env: const {'CODELAB_LOG_LEVEL': 'DEBUG'},
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
        logger.entries.map((entry) => entry['event']),
        contains(
          'Reconnecting stdio ACP agent: custom-agent serve --stdio --profile local.',
        ),
      );
      expect(
        logger.entries.map((entry) => entry['event']),
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    shellCubit.updateStdioCommand('');
    await shellCubit.connect();

    expect(configs, isEmpty);
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      logger.entries.last['event'],
      'Stdio command is required before connecting.',
    );

    await shellCubit.close();
    await application.dispose();
  });

  test('connect reports stdio start failure without crashing', () async {
    final configs = <StdioAcpTransportConfig>[];
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    shellCubit.updateStdioCommand('missing-codelab');
    await shellCubit.connect();

    expect(configs.single.command, 'missing-codelab');
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      logger.entries.last['event'],
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
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
      logger.entries.map((entry) => entry['event']),
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
      final logger = _RecordingLogger();
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
        logger: logger,
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
        logger.entries.map((entry) => entry['event']),
        contains(
          'Reconnecting WebSocket ACP agent: wss://agent.example.test/acp-v2.',
        ),
      );
      expect(
        logger.entries.map((entry) => entry['event']),
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
    );

    shellCubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('wss://agent.example.test/acp');
    await shellCubit.connect();
    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.connected);

    await shellCubit.reconnect();

    expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      logger.entries.last['event'],
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
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
      final logger = _RecordingLogger();
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
        logger: logger,
      );

      shellCubit.updateStdioCommand('missing-codelab');
      await shellCubit.connect();

      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
      final message = logger.entries.last['event'];
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
    final logger = _RecordingLogger();
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
      projectFolderPicker: _FakeProjectFolderPicker(),
      recentProjectsStore: _FakeRecentProjectsStore(),
      logger: logger,
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
      logger.entries.last['event'],
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
          tester.element(find.byType(CodeLabApp)),
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

  testWidgets('selecting /logs opens the full-screen log viewer', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();

    // The narrow-layout Offstage toggle that this flag drives is covered
    // directly on `AcpWorkbenchLayout` in acp_organisms_test.dart, at a
    // width narrow enough to trigger it — the full CodeLabApp's command
    // bar isn't adaptive at that width (a pre-existing, unrelated gap), so
    // this test only checks the state/UI wiring this change owns.
    expect(shellCubit.state.isInspectorVisibleInNarrowLayout, isTrue);
    expect(shellCubit.state.isCommandPaletteOpen, isFalse);
    expect(find.byType(DebugLogViewerDialog), findsOneWidget);
    expect(find.byType(FluentLogViewerPage), findsOneWidget);

    // Esc closes the dialog without touching workbench state underneath
    // (spec: "Закрытие возвращает к workbench без изменений").
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DebugLogViewerDialog), findsNothing);
    expect(shellCubit.state.activeSessionId, isNull);

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
      final diagnosticsBefore = binding.scope.resolve<LogBuffer>().entries.value.length;

      await tester.tap(find.text('/plan'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(shellCubit.state.isCommandPaletteOpen, isTrue);
      expect(binding.scope.resolve<LogBuffer>().entries.value.length, diagnosticsBefore);
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

  group('plan progress checklist', () {
    // `testWidgets` runs its body inside `AutomatedTestWidgetsFlutterBinding`,
    // which fakes async time — a real, unresolved `Future` (from
    // `FakeAcpTransport`'s real `Stream`s) `await`ed directly there simply
    // never completes, hanging the test until its own timeout. `runAsync`
    // escapes that zone for the real async gaps; a plain `test()` (no
    // `tester`) already runs in real async and needs no such escape — see
    // the existing "a config option the agent declared..." test above for
    // the same pattern this mirrors.
    Future<T> settle<T>(WidgetTester? tester, Future<T> Function() body) {
      if (tester == null) {
        return body();
      }
      return tester.runAsync(body).then((value) => value as T);
    }

    Future<
      ({
        CodeLabShellCubit shellCubit,
        FakeAcpTransport agentTransport,
        AcpClientApplication application,
      })
    >
    createSessionCubit({WidgetTester? tester}) async {
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
      );

      await settle(tester, shellCubit.connect);
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest =
          await settle(tester, () => createRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await settle(tester, () => createFuture);

      return (
        shellCubit: shellCubit,
        agentTransport: agentTransport,
        application: application,
      );
    }

    // A bare `session/update` notification with no turn to attach to is
    // dropped by the domain (same reason every `plan` update in
    // codelab_compatible_stdio_agent.dart is sent mid-`session/prompt`, never
    // standalone) — so plan updates here are driven through a real prompt
    // turn, not emitted in isolation.
    Future<void> submitPromptWithPlan(
      CodeLabShellCubit shellCubit,
      FakeAcpTransport agentTransport,
      List<Map<String, Object?>> entries, {
      WidgetTester? tester,
    }) async {
      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt('continue with the plan');
      final promptRequest =
          await settle(tester, () => promptRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.notification(
          method: 'session/update',
          params: {
            'sessionId': 'session-1',
            'update': {'sessionUpdate': 'plan', 'entries': entries},
          },
        ),
      );
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await settle(tester, () => submitFuture);
    }

    const readEntry = {
      'content': 'Read auth module and locate token refresh call sites',
      'priority': 'medium',
      'status': 'completed',
    };
    const testEntry = {
      'content': 'Run melos analyze to confirm no new lint issues',
      'priority': 'high',
      'status': 'in_progress',
    };

    test('a plan update populates currentPlan with mapped statuses and '
        'priorities; no plan update means it stays null', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      expect(harness.shellCubit.state.currentPlan, isNull);

      await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
        readEntry,
        testEntry,
      ]);

      final plan = harness.shellCubit.state.currentPlan;
      expect(plan, hasLength(2));
      expect(plan![0].content, readEntry['content']);
      expect(plan[0].status, AcpPlanEntryStatus.completed);
      expect(plan[0].priority, AcpPlanEntryPriority.medium);
      expect(plan[1].content, testEntry['content']);
      expect(plan[1].status, AcpPlanEntryStatus.inProgress);
      expect(plan[1].priority, AcpPlanEntryPriority.high);
    });

    test('a later plan update fully replaces the previous one, not merges '
        'it', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
        readEntry,
        testEntry,
      ]);
      expect(harness.shellCubit.state.currentPlan, hasLength(2));

      const openPrEntry = {
        'content': 'Open PR for review',
        'priority': 'low',
        'status': 'pending',
      };
      await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
        openPrEntry,
      ]);

      final plan = harness.shellCubit.state.currentPlan;
      expect(plan, hasLength(1));
      expect(plan!.single.content, 'Open PR for review');
    });

    test(
      'dismissPlan clears currentPlan; a later plan update repopulates it',
      () async {
        final harness = await createSessionCubit();
        addTearDown(harness.shellCubit.close);
        addTearDown(harness.application.dispose);

        await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
          readEntry,
          testEntry,
        ]);
        expect(harness.shellCubit.state.currentPlan, isNotNull);

        harness.shellCubit.dismissPlan();
        expect(harness.shellCubit.state.currentPlan, isNull);

        await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
          readEntry,
          testEntry,
        ]);
        expect(harness.shellCubit.state.currentPlan, hasLength(2));
      },
    );

    testWidgets(
      'the activity bar shows the plan while it has an active entry, and '
      'hides entirely once every entry is completed',
      (tester) async {
        final harness = await createSessionCubit(tester: tester);
        addTearDown(harness.shellCubit.close);
        addTearDown(harness.application.dispose);

        Future<void> pumpMainPane(CodeLabShellState state) => tester.pumpWidget(
          FluentApp(
            home: WorkbenchMainPane(state: state, cubit: harness.shellCubit),
          ),
        );

        final activeState = harness.shellCubit.state.copyWith(
          transcriptEntries: const [
            AcpTranscriptEntry(
              id: 'user-1',
              kind: AcpTranscriptEntryKind.user,
              title: 'You',
              body: 'Fix the token refresh race condition.',
            ),
          ],
          currentPlan: const [
            AcpPlanEntry(
              content: 'Reproduce the token refresh race condition',
              status: AcpPlanEntryStatus.completed,
              priority: AcpPlanEntryPriority.high,
            ),
            AcpPlanEntry(
              content: 'Run melos analyze to confirm no new lint issues',
              status: AcpPlanEntryStatus.inProgress,
              priority: AcpPlanEntryPriority.medium,
            ),
          ],
        );
        await pumpMainPane(activeState);

        expect(find.byType(AcpActivityBar), findsOneWidget);
        expect(
          find.text('Run melos analyze to confirm no new lint issues'),
          findsOneWidget,
        );

        final allCompletedState = activeState.copyWith(
          currentPlan: const [
            AcpPlanEntry(
              content: 'Reproduce the token refresh race condition',
              status: AcpPlanEntryStatus.completed,
              priority: AcpPlanEntryPriority.high,
            ),
            AcpPlanEntry(
              content: 'Run melos analyze to confirm no new lint issues',
              status: AcpPlanEntryStatus.completed,
              priority: AcpPlanEntryPriority.medium,
            ),
          ],
        );
        await pumpMainPane(allCompletedState);

        expect(find.byType(AcpActivityBar), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('dismissing the plan from the activity bar clears it on the '
        'real cubit', (tester) async {
      final harness = await createSessionCubit(tester: tester);
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      await submitPromptWithPlan(harness.shellCubit, harness.agentTransport, [
        readEntry,
        testEntry,
      ], tester: tester);

      final stateWithTranscript = harness.shellCubit.state.copyWith(
        transcriptEntries: const [
          AcpTranscriptEntry(
            id: 'user-1',
            kind: AcpTranscriptEntryKind.user,
            title: 'You',
            body: 'Fix the token refresh race condition.',
          ),
        ],
      );
      await tester.pumpWidget(
        FluentApp(
          home: WorkbenchMainPane(
            state: stateWithTranscript,
            cubit: harness.shellCubit,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Clear plan'));
      await tester.pumpAndSettle();

      expect(harness.shellCubit.state.currentPlan, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('prompt queue', () {
    // Same `runAsync` escape as the "plan progress checklist" group above —
    // `FakeAcpTransport`'s real `Stream`s never resolve inside
    // `AutomatedTestWidgetsFlutterBinding`'s fake async zone.
    Future<T> settle<T>(WidgetTester? tester, Future<T> Function() body) {
      if (tester == null) {
        return body();
      }
      return tester.runAsync(body).then((value) => value as T);
    }

    Future<
      ({
        CodeLabShellCubit shellCubit,
        FakeAcpTransport agentTransport,
        AcpClientApplication application,
        _RecordingLogger logger,
      })
    >
    createSessionCubit({WidgetTester? tester}) async {
      final initialTransport = FakeAcpTransport();
      final agentTransport = FakeAcpTransport();
      final application = AcpClientApplication(transport: initialTransport);
      final logger = _RecordingLogger();
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
        logger: logger,
      );

      await settle(tester, shellCubit.connect);
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest =
          await settle(tester, () => createRequestFuture) as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await settle(tester, () => createFuture);

      return (
        shellCubit: shellCubit,
        agentTransport: agentTransport,
        application: application,
        logger: logger,
      );
    }

    // Starts a turn and leaves it mid-flight with an unresolved permission
    // request, so `_isSessionBusy()` reports true via the pending-approval
    // path (not `isPromptSubmitting`) — mirrors the `session/request_permission`
    // simulation in "respondToApproval maps a pending approval..." above.
    Future<({dynamic promptRequest, Future<void> submitFuture})>
    startTurnWithPendingApproval(
      CodeLabShellCubit shellCubit,
      FakeAcpTransport agentTransport, {
      WidgetTester? tester,
      String prompt = 'run a command',
    }) async {
      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt(prompt);
      final promptRequest =
          await settle(tester, () => promptRequestFuture) as dynamic;
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
            ],
          ).toJson(),
        ),
      );
      return (promptRequest: promptRequest, submitFuture: submitFuture);
    }

    Future<void> resolvePendingApproval(
      CodeLabShellCubit shellCubit,
      FakeAcpTransport agentTransport,
      dynamic promptRequest,
      Future<void> submitFuture, {
      WidgetTester? tester,
    }) async {
      final permissionResponseFuture = agentTransport.sent.first;
      final respondFuture = shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-7'),
        sessionId: const SessionId('session-1'),
        optionId: 'allow-once',
      );
      await settle(tester, () => permissionResponseFuture);
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await settle(tester, () => respondFuture);
      await settle(tester, () => submitFuture);
    }

    test('submit while an approval is pending queues the prompt instead of '
        'sending it, without a "Prompt failed" diagnostic', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final turn = await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );

      await harness.shellCubit.submitPrompt('second prompt while busy');

      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));
      expect(
        harness.shellCubit.state.queuedPrompts.single.content,
        'second prompt while busy',
      );
      expect(
        harness.logger.entries.any(
          (entry) => (entry['event'] as String? ?? '').contains('Prompt failed'),
        ),
        isFalse,
      );

      // Cleanup only — resolving the approval below would otherwise
      // auto-drain this queued entry into a second `session/prompt` this
      // test never mocks a response for.
      harness.shellCubit.clearQueuedPrompts();

      await resolvePendingApproval(
        harness.shellCubit,
        harness.agentTransport,
        turn.promptRequest,
        turn.submitFuture,
      );
    });

    test('submit while a prompt round trip is already in flight (no approval '
        'involved) queues the prompt', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final promptRequestFuture = harness.agentTransport.sent.first;
      final firstSubmit = harness.shellCubit.submitPrompt('first prompt');
      final promptRequest = await promptRequestFuture as dynamic;
      expect(harness.shellCubit.state.isPromptSubmitting, isTrue);

      await harness.shellCubit.submitPrompt('queued while in flight');

      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));
      expect(
        harness.shellCubit.state.queuedPrompts.single.content,
        'queued while in flight',
      );

      // Cleanup only — completing the turn below would otherwise auto-drain
      // this queued entry into a second `session/prompt` this test never
      // mocks a response for.
      harness.shellCubit.clearQueuedPrompts();

      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await firstSubmit;
    });

    test('submit while the session is free sends immediately, unchanged from '
        'before the queue existed', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final promptRequestFuture = harness.agentTransport.sent.first;
      final submitFuture = harness.shellCubit.submitPrompt(
        'send me right away',
      );
      final promptRequest = await promptRequestFuture as dynamic;

      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
      expect(harness.shellCubit.state.isPromptSubmitting, isTrue);

      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await submitFuture;

      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
    });

    test('editQueuedPrompt moves the entry back into the composer draft and '
        'removes it from the queue', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final turn = await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );
      await harness.shellCubit.submitPrompt('edit me later');
      final id = harness.shellCubit.state.queuedPrompts.single.id;

      harness.shellCubit.editQueuedPrompt(id);

      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
      expect(harness.shellCubit.state.composerDraft, 'edit me later');

      await resolvePendingApproval(
        harness.shellCubit,
        harness.agentTransport,
        turn.promptRequest,
        turn.submitFuture,
      );
    });

    test(
      'deleteQueuedPrompt removes the entry without ever sending it',
      () async {
        final harness = await createSessionCubit();
        addTearDown(harness.shellCubit.close);
        addTearDown(harness.application.dispose);

        final turn = await startTurnWithPendingApproval(
          harness.shellCubit,
          harness.agentTransport,
        );
        await harness.shellCubit.submitPrompt('delete me');
        final id = harness.shellCubit.state.queuedPrompts.single.id;

        harness.shellCubit.deleteQueuedPrompt(id);

        expect(harness.shellCubit.state.queuedPrompts, isEmpty);

        await resolvePendingApproval(
          harness.shellCubit,
          harness.agentTransport,
          turn.promptRequest,
          turn.submitFuture,
        );

        // The deleted entry never reached the agent as a second prompt —
        // only the original "run a command" ever went out as `session/
        // prompt` (the sent log also carries `initialize`/`session/new`).
        final promptSends = harness.agentTransport.sentMessages
            .whereType<JsonRpcRequest>()
            .where((message) => message.method == sessionPromptMethod);
        expect(promptSends, hasLength(1));
      },
    );

    test('sendQueuedPromptNow on an id no longer in the queue is a safe '
        'no-op — the actual free-session dispatch it shares with auto-drain '
        'is exercised end-to-end by the "resolving the pending approval '
        'automatically drains..." test below', () async {
      // Every path that frees the session (`_dispatchPrompt`'s own
      // completion, `cancelTurn`, `respondToApproval`) drains the whole
      // queue in the very same continuation before returning control —
      // see design.md, Decisions. So "free session + still-queued id" is
      // never externally observable to call `sendQueuedPromptNow`
      // against: by the time anything can see the session as free, the
      // queue has already been drained. What *is* independently worth
      // covering here is the id-not-found guard on an otherwise idle,
      // fully free session (e.g. a stale "Send Now" tap firing after the
      // entry already left the queue).
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      await harness.shellCubit.sendQueuedPromptNow('not-a-real-id');

      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
      expect(
        harness.agentTransport.sentMessages.whereType<JsonRpcRequest>().where(
          (message) => message.method == sessionPromptMethod,
        ),
        isEmpty,
      );
    });

    test('sendQueuedPromptNow during a race where the session is still busy '
        'leaves the entry in the queue without an error, and it is still '
        'delivered once the session frees up', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final turn = await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );
      await harness.shellCubit.submitPrompt('stuck behind the approval');
      final id = harness.shellCubit.state.queuedPrompts.single.id;

      // The session is still busy (pending approval unresolved) at this
      // point — Send Now must be a no-op, not an error.
      await harness.shellCubit.sendQueuedPromptNow(id);

      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));
      expect(harness.shellCubit.state.queuedPrompts.single.id, id);
      expect(
        harness.logger.entries.any(
          (entry) => (entry['event'] as String? ?? '').contains('Prompt failed'),
        ),
        isFalse,
      );

      // Once the session frees up, the entry Send Now couldn't claim is
      // still delivered via auto-drain — not lost. Answering the
      // permission alone doesn't free the session (the turn itself is
      // still in flight), so drain only fires once the turn's own
      // response arrives below — same sequencing as the "resolving the
      // pending approval automatically drains..." test.
      final permissionResponseFuture = harness.agentTransport.sent.first;
      final respondFuture = harness.shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-7'),
        sessionId: const SessionId('session-1'),
        optionId: 'allow-once',
      );
      await permissionResponseFuture;
      await respondFuture;

      final drainedRequestFuture = harness.agentTransport.sent.first;
      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: turn.promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      final drainedRequest = await drainedRequestFuture as dynamic;
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: drainedRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await turn.submitFuture;
    });

    test('clearQueuedPrompts empties the whole queue at once', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final turn = await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );
      await harness.shellCubit.submitPrompt('first queued');
      await harness.shellCubit.submitPrompt('second queued');
      expect(harness.shellCubit.state.queuedPrompts, hasLength(2));

      harness.shellCubit.clearQueuedPrompts();

      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      await resolvePendingApproval(
        harness.shellCubit,
        harness.agentTransport,
        turn.promptRequest,
        turn.submitFuture,
      );
    });

    test('resolving the pending approval automatically drains and sends the '
        'oldest queued prompt', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      final turn = await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );
      await harness.shellCubit.submitPrompt('oldest queued');
      await harness.shellCubit.submitPrompt('newest queued');
      expect(harness.shellCubit.state.queuedPrompts, hasLength(2));

      // Answering the permission request only resolves the *approval* —
      // the turn itself (and thus `_isSessionBusy()`) stays busy until the
      // original `session/prompt` request below also gets its response, so
      // draining does not start yet.
      final permissionResponseFuture = harness.agentTransport.sent.first;
      final respondFuture = harness.shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-7'),
        sessionId: const SessionId('session-1'),
        optionId: 'allow-once',
      );
      await permissionResponseFuture;
      await respondFuture;
      expect(harness.shellCubit.state.queuedPrompts, hasLength(2));

      // Completing the original turn frees the session, so auto-drain
      // fires as part of it and sends the oldest queued entry next.
      final drainedRequestFuture = harness.agentTransport.sent.first;
      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: turn.promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      final drainedRequest = await drainedRequestFuture as dynamic;

      // Only the oldest entry auto-drained; the second stays queued until
      // this turn also frees up.
      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));
      expect(
        harness.shellCubit.state.queuedPrompts.single.content,
        'newest queued',
      );
      expect(harness.shellCubit.state.isPromptSubmitting, isTrue);

      // Draining recurses, so completing this turn sends the second entry
      // automatically too — settle it the same way to avoid a pending
      // completer.
      final secondRequestFuture = harness.agentTransport.sent.first;
      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: drainedRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      final secondRequest = await secondRequestFuture as dynamic;
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: secondRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await turn.submitFuture;
    });

    test("switching sessions shows each session's own queue, never mixed "
        "with another session's — queuedPrompts is per-session, not flat "
        '(design.md, Non-Goals/Risks)', () async {
      final harness = await createSessionCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      await startTurnWithPendingApproval(
        harness.shellCubit,
        harness.agentTransport,
      );
      await harness.shellCubit.submitPrompt('queued on session-1');
      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));

      final createRequestFuture = harness.agentTransport.sent.first;
      final createFuture = harness.shellCubit.createSession();
      final createRequest = await createRequestFuture as dynamic;
      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: const {'sessionId': 'session-2'},
        ),
      );
      await createFuture;
      expect(harness.shellCubit.state.activeSessionId, 'session-2');

      // A brand-new session must not inherit session-1's queue.
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      harness.shellCubit.selectSession('session-1');
      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));
      expect(
        harness.shellCubit.state.queuedPrompts.single.content,
        'queued on session-1',
      );

      harness.shellCubit.selectSession('session-2');
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
    });

    testWidgets(
      'the activity bar shows both the plan and the queue sections at once '
      'when both are non-empty',
      (tester) async {
        final harness = await createSessionCubit(tester: tester);
        addTearDown(harness.shellCubit.close);
        addTearDown(harness.application.dispose);

        final state = harness.shellCubit.state.copyWith(
          transcriptEntries: const [
            AcpTranscriptEntry(
              id: 'user-1',
              kind: AcpTranscriptEntryKind.user,
              title: 'You',
              body: 'Fix the token refresh race condition.',
            ),
          ],
          currentPlan: const [
            AcpPlanEntry(
              content: 'Run melos analyze to confirm no new lint issues',
              status: AcpPlanEntryStatus.inProgress,
              priority: AcpPlanEntryPriority.medium,
            ),
          ],
          queuedPrompts: const [
            AcpQueuedPrompt(id: 'queued-0', content: 'do the next thing'),
          ],
        );

        await tester.pumpWidget(
          FluentApp(
            home: WorkbenchMainPane(state: state, cubit: harness.shellCubit),
          ),
        );

        expect(find.byType(AcpActivityBar), findsOneWidget);
        // Plan's collapsed header shows the in-progress entry directly.
        expect(
          find.text('Run melos analyze to confirm no new lint issues'),
          findsOneWidget,
        );
        // Queue's collapsed header shows its own title and count — both
        // sections are present at once, not just one of them.
        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('1 queued'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('multi-session concurrency', () {
    Future<
      ({
        CodeLabShellCubit shellCubit,
        FakeAcpTransport agentTransport,
        AcpClientApplication application,
      })
    >
    createConnectedCubit() async {
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
        projectFolderPicker: _FakeProjectFolderPicker(),
        recentProjectsStore: _FakeRecentProjectsStore(),
      );

      await shellCubit.connect();
      return (
        shellCubit: shellCubit,
        agentTransport: agentTransport,
        application: application,
      );
    }

    Future<void> createSessionWithId(
      CodeLabShellCubit shellCubit,
      FakeAcpTransport agentTransport,
      String sessionId,
    ) async {
      final createRequestFuture = agentTransport.sent.first;
      final createFuture = shellCubit.createSession();
      final createRequest = await createRequestFuture as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: createRequest.id as JsonRpcId,
          result: {'sessionId': sessionId},
        ),
      );
      await createFuture;
    }

    // Same pattern as the "prompt queue" group's `startTurnWithPendingApproval`
    // above, parametrized by session/tool-call/request id so two sessions on
    // the same transport never collide on those ids.
    Future<({dynamic promptRequest, Future<void> submitFuture})>
    startTurnWithPendingApproval({
      required CodeLabShellCubit shellCubit,
      required FakeAcpTransport agentTransport,
      required String sessionId,
      required JsonRpcId permissionRequestId,
      required String toolCallId,
      String prompt = 'run a command',
    }) async {
      final promptRequestFuture = agentTransport.sent.first;
      final submitFuture = shellCubit.submitPrompt(prompt);
      final promptRequest = await promptRequestFuture as dynamic;
      agentTransport.emitInbound(
        JsonRpcMessage.request(
          id: permissionRequestId,
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: SessionId(sessionId),
            toolCall: ToolCallUpdate(
              toolCallId: ToolCallId(toolCallId),
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
            ],
          ).toJson(),
        ),
      );
      return (promptRequest: promptRequest, submitFuture: submitFuture);
    }

    // Session A is created first and starts a turn that immediately hangs on
    // a pending approval; session B is created afterward (so it becomes
    // active) while A's turn is still in flight in the background — the
    // exact setup the "Starting a second session while the first is still
    // running" scenario in specs/agent-workbench-ui/spec.md describes.
    Future<
      ({
        CodeLabShellCubit shellCubit,
        FakeAcpTransport agentTransport,
        AcpClientApplication application,
        dynamic promptRequestA,
        Future<void> submitFutureA,
      })
    >
    setUpBackgroundSessionAWithActiveSessionB() async {
      final harness = await createConnectedCubit();
      await createSessionWithId(
        harness.shellCubit,
        harness.agentTransport,
        'session-a',
      );
      final turnA = await startTurnWithPendingApproval(
        shellCubit: harness.shellCubit,
        agentTransport: harness.agentTransport,
        sessionId: 'session-a',
        permissionRequestId: const JsonRpcId.integer(701),
        toolCallId: 'tool-a',
      );
      await createSessionWithId(
        harness.shellCubit,
        harness.agentTransport,
        'session-b',
      );

      return (
        shellCubit: harness.shellCubit,
        agentTransport: harness.agentTransport,
        application: harness.application,
        promptRequestA: turnA.promptRequest,
        submitFutureA: turnA.submitFuture,
      );
    }

    Future<void> resolveSessionATurn(
      CodeLabShellCubit shellCubit,
      FakeAcpTransport agentTransport,
      dynamic promptRequestA,
      Future<void> submitFutureA,
    ) async {
      final permissionResponseFuture = agentTransport.sent.first;
      final respondFuture = shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-701'),
        sessionId: const SessionId('session-a'),
        optionId: 'allow-once',
      );
      await permissionResponseFuture;
      agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequestA.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await respondFuture;
      await submitFutureA;
    }

    test('starting a second session while the first is still running lets the '
        'user submit a prompt in the newly active session immediately, '
        'without queuing it', () async {
      final setup = await setUpBackgroundSessionAWithActiveSessionB();
      addTearDown(setup.shellCubit.close);
      addTearDown(setup.application.dispose);

      expect(setup.shellCubit.state.activeSessionId, 'session-b');
      expect(setup.shellCubit.state.isPromptSubmitting, isFalse);
      expect(setup.shellCubit.state.canCancel, isFalse);

      final promptRequestBFuture = setup.agentTransport.sent.first;
      final submitFutureB = setup.shellCubit.submitPrompt('hello from B');
      final promptRequestB = await promptRequestBFuture as dynamic;

      // Sent right away, not queued — session A being busy must not
      // affect session B, the active one.
      expect(setup.shellCubit.state.queuedPrompts, isEmpty);
      expect(setup.shellCubit.state.isPromptSubmitting, isTrue);

      setup.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequestB.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await submitFutureB;
      expect(setup.shellCubit.state.isPromptSubmitting, isFalse);

      await resolveSessionATurn(
        setup.shellCubit,
        setup.agentTransport,
        setup.promptRequestA,
        setup.submitFutureA,
      );
    });

    test("a background session's turn completing while another session is "
        'active does not alter the transcript, submitting or cancel state '
        'the active session shows', () async {
      final setup = await setUpBackgroundSessionAWithActiveSessionB();
      addTearDown(setup.shellCubit.close);
      addTearDown(setup.application.dispose);

      final transcriptBeforeCompletion =
          setup.shellCubit.state.transcriptEntries;
      expect(transcriptBeforeCompletion, isEmpty);
      expect(setup.shellCubit.state.isPromptSubmitting, isFalse);
      expect(setup.shellCubit.state.canCancel, isFalse);

      await resolveSessionATurn(
        setup.shellCubit,
        setup.agentTransport,
        setup.promptRequestA,
        setup.submitFutureA,
      );

      // Session B (still active) is untouched by A's completion.
      expect(setup.shellCubit.state.activeSessionId, 'session-b');
      expect(setup.shellCubit.state.transcriptEntries, isEmpty);
      expect(setup.shellCubit.state.isPromptSubmitting, isFalse);
      expect(setup.shellCubit.state.canCancel, isFalse);

      // Session A's own transcript did get updated, in the background.
      final sessionA = setup.application.sessionById(
        const SessionId('session-a'),
      );
      expect(sessionA!.turns.single.status, PromptTurnStatus.completed);
    });

    test("a background session's own queue drains when its own turn completes, "
        'even while a different session stays active throughout — no need to '
        'switch back to it first', () async {
      final harness = await createConnectedCubit();
      addTearDown(harness.shellCubit.close);
      addTearDown(harness.application.dispose);

      await createSessionWithId(
        harness.shellCubit,
        harness.agentTransport,
        'session-a',
      );
      final turnA = await startTurnWithPendingApproval(
        shellCubit: harness.shellCubit,
        agentTransport: harness.agentTransport,
        sessionId: 'session-a',
        permissionRequestId: const JsonRpcId.integer(701),
        toolCallId: 'tool-a',
      );
      // Still active on session A here — queues behind A's own pending
      // approval, exactly like the single-session prompt-queue behavior.
      await harness.shellCubit.submitPrompt('queued for A');
      expect(harness.shellCubit.state.queuedPrompts, hasLength(1));

      // Switching to B leaves A's queue in place, attached to A.
      await createSessionWithId(
        harness.shellCubit,
        harness.agentTransport,
        'session-b',
      );
      expect(harness.shellCubit.state.activeSessionId, 'session-b');
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      // Resolving A's turn while B stays active must still auto-drain
      // A's queue — the drained request is A's queued content going out
      // as a real `session/prompt`, without switching back to A first.
      final permissionResponseFuture = harness.agentTransport.sent.first;
      final respondFuture = harness.shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-701'),
        sessionId: const SessionId('session-a'),
        optionId: 'allow-once',
      );
      await permissionResponseFuture;

      final drainedRequestFuture = harness.agentTransport.sent.first;
      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: turnA.promptRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await respondFuture;
      final drainedRequest = await drainedRequestFuture as dynamic;

      // B is untouched the whole time — the drain happened purely
      // in the background.
      expect(harness.shellCubit.state.activeSessionId, 'session-b');
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);

      harness.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: drainedRequest.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await turnA.submitFuture;

      // A's own queue, checked by switching to it, is empty — the
      // drained prompt actually left it, it was not silently dropped.
      harness.shellCubit.selectSession('session-a');
      expect(harness.shellCubit.state.queuedPrompts, isEmpty);
    });

    test("a non-active session's sidebar status stays live — running, "
        'awaiting-approval, then idle — as its turn progresses, without the '
        'user ever switching to it', () async {
      final setup = await setUpBackgroundSessionAWithActiveSessionB();
      addTearDown(setup.shellCubit.close);
      addTearDown(setup.application.dispose);

      AcpSessionStatus statusOf(String sessionId) => setup
          .shellCubit
          .state
          .sessions
          .firstWhere((item) => item.id == sessionId)
          .status;

      expect(setup.shellCubit.state.activeSessionId, 'session-b');
      expect(statusOf('session-a'), AcpSessionStatus.awaitingApproval);

      final permissionResponseFuture = setup.agentTransport.sent.first;
      final respondFuture = setup.shellCubit.respondToApproval(
        approvalId: const ApprovalRequestId('permission-701'),
        sessionId: const SessionId('session-a'),
        optionId: 'allow-once',
      );
      await permissionResponseFuture;
      await respondFuture;

      // Still active on B — the resolved approval alone must already be
      // reflected in A's sidebar entry.
      expect(setup.shellCubit.state.activeSessionId, 'session-b');
      expect(statusOf('session-a'), AcpSessionStatus.running);

      setup.agentTransport.emitInbound(
        JsonRpcMessage.response(
          id: setup.promptRequestA.id as JsonRpcId,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await setup.submitFutureA;

      expect(setup.shellCubit.state.activeSessionId, 'session-b');
      expect(statusOf('session-a'), AcpSessionStatus.idle);
    });
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

/// Always resolves with no selection — sufficient for tests that only need
/// [CodeLabShellCubit] to construct; browse-flow tests set [nextResult].
final class _FakeProjectFolderPicker implements ProjectFolderPicker {
  String? nextResult;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async => nextResult;
}

/// In-memory stand-in for [RecentProjectsStore] — avoids touching the real
/// `shared_preferences` plugin (unavailable without platform-channel mocking)
/// in plain `test()`/`testWidgets()` runs.
final class _FakeRecentProjectsStore implements RecentProjectsStore {
  final List<RecentProject> _entries = [];

  @override
  Future<List<RecentProject>> load() async => List.unmodifiable(_entries);

  @override
  Future<void> record(String path) async {
    _entries.removeWhere((entry) => entry.path == path);
    _entries.insert(0, RecentProject(path: path, lastOpenedAt: DateTime.now()));
  }
}

/// In-memory [Logger] used by the `plan progress checklist` group's
/// bespoke `createSessionCubit()` harness — that harness builds
/// [CodeLabShellCubit] directly (not via `createCodeLabRootScope`), so it
/// has no `LogBuffer` from `configureCodeLabLogging()` to assert against.
/// [entries] records every call as a plain map, `event`/`level` alongside
/// bound context — enough for the harness's diagnostic assertions without
/// touching the global `structured_log` singleton other tests configure.
final class _RecordingLogger implements Logger {
  _RecordingLogger([Map<String, Object?> context = const {}, List<Map<String, Object?>>? sink])
    : _context = context,
      entries = sink ?? [];

  final Map<String, Object?> _context;
  final List<Map<String, Object?>> entries;

  @override
  Logger bind(Map<String, Object?> context) =>
      _RecordingLogger({..._context, ...context}, entries);

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => bind({
    if (sessionId != null) 'session_id': sessionId,
    if (requestId != null) 'request_id': requestId,
    if (connectionGeneration != null)
      'connection_generation': connectionGeneration,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (messageId != null) 'message_id': messageId,
    if (operationId != null) 'operation_id': operationId,
  });

  void _log(String level, String? event, Map<String, Object?>? context) {
    entries.add({..._context, ...?context, 'event': event, 'level': level});
  }

  @override
  void trace(String? event, {Map<String, Object?>? context}) =>
      _log('trace', event, context);

  @override
  void debug(String? event, {Map<String, Object?>? context}) =>
      _log('debug', event, context);

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _log('info', event, context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _log('warning', event, context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _log('error', event, context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _log('critical', event, context);
}
