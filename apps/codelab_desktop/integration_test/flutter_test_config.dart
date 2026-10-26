// Общая настройка e2e-тестов app: Flutter подхватывает этот файл для каждого
// теста в `integration_test/`.

import 'dart:async';

import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перед каждым тестом удаляет снимок рабочего пространства.
///
/// Почему: на macOS e2e-тесты делят `NSUserDefaults`, а app пишет туда снимок
/// для восстановления после перезапуска; снимок прошлого теста выбрал бы его
/// проект и при подключении восстановил бы его сессии (design D8 change
/// `add-session-list-and-reload`). Тест перезапуска сам пишет снимок внутри
/// теста, и его это не задевает.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() async {
    await const SharedPreferencesWorkspaceSnapshotStore().clear();
  });
  await testMain();
}
