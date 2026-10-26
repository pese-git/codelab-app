import 'package:codelab_client_core/codelab_client_core.dart'
    show WorkspaceSnapshotStore;
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ снимка рабочего пространства в `shared_preferences`.
const kWorkspaceSnapshotPrefsKey = 'codelab.workspace.snapshot';

/// [WorkspaceSnapshotStore] на `shared_preferences`.
///
/// Почему: снимок нужен после перезапуска app, а хранилище рядом с
/// недавними проектами уже есть и живёт в app — это Flutter-плагин (design
/// D6 change `add-session-list-and-reload`).
///
/// Для чего: хранит строку JSON снимка под [kWorkspaceSnapshotPrefsKey];
/// формат, версия и разбор — забота `codelab_client_core`.
///
/// Как использовать: граф cherrypick передаёт его в `ClientWorkspace`.
final class SharedPreferencesWorkspaceSnapshotStore
    implements WorkspaceSnapshotStore {
  const SharedPreferencesWorkspaceSnapshotStore();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(kWorkspaceSnapshotPrefsKey);

  @override
  Future<void> write(String snapshot) async {
    await (await SharedPreferences.getInstance()).setString(
      kWorkspaceSnapshotPrefsKey,
      snapshot,
    );
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(
      kWorkspaceSnapshotPrefsKey,
    );
  }
}
