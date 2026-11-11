// Тесты восстановления проекта после перезапуска app (tasks 4.4 change
// `add-session-list-and-reload`; spec agent-workbench-ui «Workbench restores
// sessions after reconnect and restart»; design D6).

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabSessionStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

String _snapshot(String project) => jsonEncode({
  'version': 1,
  'windows': {
    'main': {'projectDirectory': project, 'openSessions': <Object?>[]},
  },
});

void main() {
  test('the project of the previous run is selected at start', () async {
    final binding = CodeLabTestBinding(
      preferences: {kWorkspaceSnapshotPrefsKey: _snapshot('/work/app')},
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();

    await pumpEventQueue();

    expect(cubit.state.selectedProjectPath, '/work/app');
  });

  test('without a snapshot no project is selected', () async {
    final binding = CodeLabTestBinding();
    final cubit = binding.scope.resolve<CodeLabShellCubit>();

    await pumpEventQueue();

    expect(cubit.state.selectedProjectPath, isNull);
  });

  test('selecting a project saves it in the snapshot', () async {
    final binding = CodeLabTestBinding();
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await pumpEventQueue();

    await cubit.selectProject('/work/other');
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString(kWorkspaceSnapshotPrefsKey)!)
            as Map<String, Object?>;
    expect(
      ((saved['windows']! as Map)['main'] as Map)['projectDirectory'],
      '/work/other',
    );
  });

  // Версии, подставлявшие папку процесса вместо не выбранного проекта,
  // записывали в снимок `/` (require-project-folder/design.md, D10).
  test('a snapshot project at the filesystem root is not selected and its '
      'sessions are neither loaded nor kept', () async {
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = const AgentCapabilities(
        loadSession: true,
      );
    final binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => agent,
      preferences: {
        kWorkspaceSnapshotPrefsKey: jsonEncode({
          'version': 1,
          'windows': {
            'main': {
              'projectDirectory': '/',
              'activeSessionId': 's1',
              'openSessions': [
                {'id': 's1', 'cwd': '/'},
              ],
            },
          },
        }),
      },
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();

    await pumpEventQueue();

    expect(cubit.state.selectedProjectPath, isNull);
    final warnings = binding.scope.resolve<LogBuffer>().entries.value.where(
      (entry) =>
          entry['event'] ==
          'Project folder from the last run is the filesystem root: /. '
              'Choose a folder with Open folder….',
    );
    expect(warnings, hasLength(1));
    expect(warnings.single['level'], 'warning');
    expect(warnings.single['source'], 'project');

    await cubit.selectProject('/work/app');
    await cubit.connect();
    await pumpEventQueue();

    final methods = [
      for (final message in agent.sentMessages)
        if (message case JsonRpcRequest(:final method)) method,
    ];
    expect(methods, isNot(contains(sessionLoadMethod)));
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(kWorkspaceSnapshotPrefsKey)!);
    final window = (saved['windows'] as Map)['main'] as Map;
    expect(window['projectDirectory'], '/work/app');
    expect(window['openSessions'], isEmpty);
  });

  // HIGH-1 ревью (D10): активная сессия снимка в другой папке не должна
  // загружаться при первом подключении, иначе агент получил бы корень диска
  // без действия пользователя.
  test('an active session of the snapshot whose cwd is not the project is '
      'neither loaded nor created; it stays a notLoaded row', () async {
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = const AgentCapabilities(
        loadSession: true,
      );
    final binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => agent,
      preferences: {
        kWorkspaceSnapshotPrefsKey: jsonEncode({
          'version': 1,
          'windows': {
            'main': {
              'projectDirectory': '/work/app',
              'activeSessionId': 's1',
              'openSessions': [
                {'id': 's1', 'cwd': '/'},
              ],
            },
          },
        }),
      },
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.connect();
    await pumpEventQueue();

    expect(cubit.state.selectedProjectPath, '/work/app');
    final methods = [
      for (final message in agent.sentMessages)
        if (message case JsonRpcRequest(:final method)) method,
    ];
    expect(methods, isNot(contains(sessionLoadMethod)));
    expect(methods, isNot(contains(sessionNewMethod)));
    expect(cubit.state.activeSessionId, isNull);
    expect(cubit.state.sessions.single.id, 's1');
    expect(cubit.state.sessions.single.status, CodeLabSessionStatus.notLoaded);
  });
}
