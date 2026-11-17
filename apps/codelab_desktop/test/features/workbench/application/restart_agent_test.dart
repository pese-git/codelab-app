// «Use» и «Restart agent» (задача B2.3 change `require-project-folder`; spec
// app-settings «Список профилей…», «Блок «Behavior»…»; design.md D18, D22,
// Q25, Q27).
//
// Тесты идут через граф app (`ShellHarness`): наблюдаются кадры агенту,
// число открытых транспортов, состояние фасада и события журнала.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';

import '../../../support/fake_project_files.dart';
import '../../../support/test_app_scope.dart';
import 'shell_cubit_characterization/harness.dart';

final _remote = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'Remote',
  uri: Uri.parse('wss://agent.example.test/acp'),
);

List<String> _methods(FakeAcpTransport agent) => [
  for (final message in agent.sentMessages)
    if (message case JsonRpcRequest(:final method)) method,
];

Iterable<Map<String, Object?>> _entries(ShellHarness h, String event) => h
    .binding
    .scope
    .resolve<LogBuffer>()
    .entries
    .value
    .where((entry) => entry['event'] == event);

void main() {
  setUp(setUpCharacterization);

  test('Use only selects the profile: the running agent, the project and '
      'the default profile stay (D18)', () async {
    final h = ShellHarness();
    await h.connect();
    final running = h.cubit.state.profileLabel;

    await h.cubit.useProfile(_remote);

    expect(h.stdioStarts, 1);
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(h.cubit.state.profileLabel, running);
    expect(h.cubit.state.selectedProjectPath, h.project);
  });

  test('Restart agent in rest has no dialog, restarts the selected profile '
      'and keeps the selected project (D22)', () async {
    final remote = FakeAcpTransport();
    final h = ShellHarness(webSocketTransportFactory: (_) => remote);
    await h.connect();
    await h.cubit.useProfile(_remote);

    await h.cubit.restartAgent();

    expect(h.cubit.state.pendingRestart, isNull);
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(h.cubit.state.profileLabel, 'Remote');
    expect(h.cubit.state.selectedProjectPath, h.project);
    final event = _entries(h, 'connection.restart').single;
    expect(event['reason'], 'profile_changed');
    expect(event['interrupted'], 0);
  });

  test('a running turn: the dialog names the session, Cancel changes '
      'nothing, Restart agent restarts without session/cancel and the '
      'event has no path', () async {
    final first = FakeAcpTransport();
    final second = FakeAcpTransport();
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.connect();
    await h.createSession('s1');
    final turn = await h.startTurn('work');

    await h.cubit.restartAgent();
    final pending = h.cubit.state.pendingRestart!;
    expect(pending.sessions, hasLength(1));
    expect(pending.message, startsWith('Restart '));
    expect(pending.message, contains('This interrupts 1 running session'));
    expect(pending.message, endsWith('Queued prompts stay.'));

    // Повторный перезапуск при открытом диалоге игнорируется.
    await h.cubit.restartAgent();
    expect(starts, 1);

    h.cubit.cancelRestart();
    expect(h.cubit.state.pendingRestart, isNull);
    expect(starts, 1);

    await h.cubit.restartAgent();
    await h.cubit.confirmRestart();
    await h.settle();

    expect(starts, 2);
    expect(_methods(first), isNot(contains(sessionCancelMethod)));
    final event = _entries(h, 'connection.restart').single;
    expect(event['interrupted'], 1);
    expect(event.values.join(), isNot(contains('/work')));
    unawaited(turn.done.then<void>((_) {}, onError: (Object _) {}));
  });

  test('without a project and without a previous root Restart agent does '
      'nothing: nothing starts (D18)', () async {
    var starts = 0;
    final binding = CodeLabTestBinding(
      stdioTransportFactory: (_) {
        starts++;
        return FakeAcpTransport();
      },
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.restartAgent();

    expect(starts, 0);
    expect(cubit.state.connectionStatus, CodeLabConnectionStatus.disconnected);
    expect(cubit.state.pendingRestart, isNull);
  });

  test('Restart agent during the start supersedes the attempt without a '
      'dialog and without an intermediate failed status (Q25)', () async {
    final first = FakeAcpTransport()..autoRespondToInitialize = false;
    final second = FakeAcpTransport();
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.projectReady();
    final (states, _) = h.recordStates();

    final starting = h.cubit.startOnLaunch();
    await pumpEventQueue();
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connecting);
    await h.cubit.restartAgent();
    await starting;
    await h.settle();

    expect(h.cubit.state.pendingRestart, isNull);
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(
      states.map((state) => state.connectionStatus),
      isNot(contains(CodeLabConnectionStatus.failed)),
    );
    expect(starts, 2);
  });

  test('the root of the restart is the folder of the focused session, the '
      'selected project stays (D18)', () async {
    final roots = <String?>[];
    final h = ShellHarness(
      stdioTransportFactory: (config) {
        roots.add(config.cwd);
        return FakeAcpTransport();
      },
    );
    await h.connect();
    expect(roots, [h.project]);
    // Сессия создана в проекте харнесса; затем проект сменили.
    final agent = h.binding.scope.resolve<ClientWorkspace>();
    expect(agent.current.projectDirectory, h.project);
    await h.cubit.selectProject('/work/other');
    await h.cubit.restartAgent();

    // Сессии в фокусе нет — корень берётся из выбранного проекта.
    expect(roots.last, '/work/other');
    expect(h.cubit.state.selectedProjectPath, '/work/other');
  });

  // B2.7, D18: «Use» WebSocket-профиля при работающем встроенном/stdio агенте
  // не скрывает Files: доступность считается по профилю работающего агента.
  test('Use of a WebSocket profile keeps the Files pane available for the '
      'running local agent (D18)', () async {
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/work/app',
      stdioTransportFactory: (_) => agent,
      projectFiles: FakeProjectFiles(),
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;
    // До старта агента с выбранным проектом Files показывает проект.
    expect(cubit.state.projectFilesAvailable, isTrue);

    await cubit.startOnLaunch();
    expect(cubit.state.projectFilesAvailable, isTrue);

    await cubit.useProfile(_remote);

    expect(cubit.state.projectFilesAvailable, isTrue);
    expect(cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
  });
}
