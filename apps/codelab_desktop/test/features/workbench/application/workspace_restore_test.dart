// Тесты восстановления проекта после перезапуска app (tasks 4.4 change
// `add-session-list-and-reload`; spec agent-workbench-ui «Workbench restores
// sessions after reconnect and restart»; design D6).

import 'dart:convert';

import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
