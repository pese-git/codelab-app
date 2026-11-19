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
/// Почему отдельный порт: настройка принадлежит окну app, а не агенту и не
/// профилю, поэтому `config.yaml` и `profiles.json` не трогаются (образец —
/// `AppLanguagePreferences`).
///
/// Как использовать: `load` читает значение до восстановления проекта и НЕ
/// бросает: сбой хранилища и нечитаемое значение дают «включено» с признаком,
/// иначе повреждённый файл настроек мешал бы запуску. `save(true)` удаляет
/// ключ; ошибки записи порт не скрывает — их показывает страница («Retry»).
abstract interface class StartupPreferences {
  Future<StartupLoad> load();

  Future<void> save(bool reopenLastProject);
}

/// [StartupPreferences] в `shared_preferences` под ключом
/// [kReopenLastProjectKey].
///
/// Небулево значение читается как «включено» и НЕ перезаписывается: данные
/// пользователя не портятся молча (AGENTS.md §2).
final class SharedPreferencesStartupPreferences implements StartupPreferences {
  /// [open] — шов тестов: по умолчанию `SharedPreferences.getInstance`.
  const SharedPreferencesStartupPreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  }) : _open = open;

  final Future<SharedPreferences> Function() _open;

  @override
  Future<StartupLoad> load() async {
    final Object? value;
    try {
      final prefs = await _open();
      // `get`, а не `getBool`: небулево значение не должно бросать `TypeError`
      // и ронять запуск.
      value = prefs.get(kReopenLastProjectKey);
    } on Object catch (error) {
      return StartupLoad(true, readFailure: error.runtimeType.toString());
    }
    return switch (value) {
      null => const StartupLoad(true),
      final bool enabled => StartupLoad(enabled),
      _ => const StartupLoad(true, storedValueInvalid: true),
    };
  }

  @override
  Future<void> save(bool reopenLastProject) async {
    final prefs = await _open();
    if (reopenLastProject) {
      await prefs.remove(kReopenLastProjectKey);
    } else {
      await prefs.setBool(kReopenLastProjectKey, false);
    }
  }
}
