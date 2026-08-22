import 'dart:async';

import 'package:codelab_app/main.dart';
import 'package:codelab_app/src/app_scope.dart';
import 'package:codelab_app/src/presentation/shell_cubit.dart';
import 'package:acp_client_core/acp_client_core.dart';
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
    expect(find.text('Codelab Agent'), findsWidgets);
    expect(
      find.text('Connect an ACP agent to start a session.'),
      findsOneWidget,
    );
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

  testWidgets('records shell-only actions without touching transport', (
    tester,
  ) async {
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
      'Prompt sending is wired in task 7.5.',
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

  test('connect starts selected stdio transport through application', () async {
    final configs = <StdioAcpTransportConfig>[];
    final initialTransport = FakeAcpTransport();
    final stdioTransport = FakeAcpTransport();
    final application = AcpClientApplication(transport: initialTransport);
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
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

  test('connect reports missing stdio command without crashing', () async {
    final configs = <StdioAcpTransportConfig>[];
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final shellCubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
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
      contains('WebSocket connect is deferred to task 7.7'),
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
