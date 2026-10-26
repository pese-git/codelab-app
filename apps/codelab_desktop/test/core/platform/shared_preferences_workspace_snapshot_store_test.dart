// Тесты хранилища снимка рабочего пространства на `shared_preferences`
// (tasks 4.4 change `add-session-list-and-reload`; design D6).

import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing saved reads as null', () async {
    expect(
      await const SharedPreferencesWorkspaceSnapshotStore().read(),
      isNull,
    );
  });

  test('a written snapshot is read back from its own key', () async {
    const store = SharedPreferencesWorkspaceSnapshotStore();

    await store.write('{"version":1}');

    expect(await store.read(), '{"version":1}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWorkspaceSnapshotPrefsKey), '{"version":1}');
    expect(kWorkspaceSnapshotPrefsKey, 'codelab.workspace.snapshot');
  });

  test('clear removes the snapshot', () async {
    const store = SharedPreferencesWorkspaceSnapshotStore();
    await store.write('{"version":1}');

    await store.clear();

    expect(await store.read(), isNull);
  });
}
