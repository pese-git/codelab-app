import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';

/// Тестовая замена прежнего `connect([profile])` (change
/// `require-project-folder`, D20).
///
/// Почему: ручного Connect нет, агент стартует по триггерам D13. Тесты, которые
/// проверяли подключение профиля, теперь «Use» профиля и триггер запуска
/// (`startOnLaunch`); ожидания исхода те же.
///
/// Как использовать: `await cubit.startWith(profile)` — выбрать профиль и
/// стартовать агента в выбранном проекте. Проект тест выбирает сам (снимок
/// `CodeLabTestBinding(project:)` или `selectProject`); если выбор проекта уже
/// стартовал агента другим профилем, `startWith` его не перезапускает — тест
/// сначала выбирает профиль (`useProfile`), а потом проект.
extension CodeLabShellStart on CodeLabShellCubit {
  Future<void> startWith([ConnectionProfile? profile]) async {
    if (profile != null) {
      await useProfile(profile);
    }
    await startOnLaunch();
  }
}
