import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: открывать ли проект прошлого запуска (`bool`;
/// для включённого значения ключа нет).
const kReopenLastProjectKey = 'codelab.workspace.reopen_last_project';

/// Результат чтения настройки «Reopen the last project and its tabs».
///
/// Почему не голое значение: чтение идёт до восстановления проекта, диагностику
/// пишет вызывающий (`app.reopen_last_project_unreadable`, D9), а текст ошибки
/// хранилища в журнал не попадает: в нём бывают пути (CFG-10).
final class StartupLoad {
  const StartupLoad(
    this.reopenLastProject, {
    this.storedValueInvalid = false,
    this.readFailure,
  });

  /// Открывать проект прошлого запуска. При нечитаемом значении — `true`.
  final bool reopenLastProject;

  /// В ключе лежит небулево значение.
  final bool storedValueInvalid;

  /// Имя типа ошибки хранилища; `null` — чтение прошло.
  final String? readFailure;
}

/// Порт хранения настроек запуска app (design.md change
/// `add-app-general-page`, D9).
///
/// Заглушка итерации 3 (красные тесты 3.3): методы ничего не читают и не
/// пишут. Реализация — задача 3.4.
abstract interface class StartupPreferences {
  Future<StartupLoad> load();

  Future<void> save(bool reopenLastProject);
}

/// [StartupPreferences] в `shared_preferences` под ключом
/// [kReopenLastProjectKey]. Заглушка итерации 3 (задача 3.4).
final class SharedPreferencesStartupPreferences implements StartupPreferences {
  /// [open] — шов тестов: по умолчанию `SharedPreferences.getInstance`.
  const SharedPreferencesStartupPreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  });

  @override
  Future<StartupLoad> load() async => const StartupLoad(true);

  @override
  Future<void> save(bool reopenLastProject) async {}
}
