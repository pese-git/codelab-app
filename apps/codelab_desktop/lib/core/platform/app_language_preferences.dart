import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: язык интерфейса app (`en`/`ru`; для `system`
/// ключа нет).
const kAppLanguageKey = 'codelab.app.language';

/// Выбор языка интерфейса пользователем.
///
/// `system` — «язык системы»: явного выбора нет, язык выводит
/// `resolveAppLocale` (`add-desktop-localization`, D2).
enum AppLanguagePreference { system, en, ru }

/// Результат чтения сохранённого языка.
///
/// Почему не голое значение: чтение идёт в `main` до `runApp`, когда журнал
/// ещё не настроен (`configureCodeLabLogging` — в root scope). Диагностику
/// поэтому несёт результат, а событие пишет `CodeLabLanguageModule` рядом с
/// `app.locale_resolved` (`add-desktop-localization`, D13).
///
/// [storedValueInvalid] — в ключе лежит незнакомое или нестроковое значение;
/// [readFailure] — имя типа ошибки хранилища (текст исключения не хранится:
/// в нём бывают пути). В обоих случаях [preference] — `system`.
final class AppLanguageLoad {
  const AppLanguageLoad(
    this.preference, {
    this.storedValueInvalid = false,
    this.readFailure,
  });

  final AppLanguagePreference preference;
  final bool storedValueInvalid;
  final String? readFailure;
}

/// Порт хранения выбранного языка интерфейса.
///
/// Почему отдельный порт: язык — настройка app, а не профиля и не агента, поэтому
/// `config.yaml` и `profiles.json` не трогаются (add-desktop-localization, D2;
/// образец — `ConnectionPreferences`).
///
/// Как использовать: `load` читает значение до `runApp` и НЕ бросает: сбой
/// хранилища даёт `system` и [AppLanguageLoad.readFailure], иначе повреждённый
/// файл настроек не давал бы запустить app. `save(system)` удаляет ключ;
/// ошибки записи порт не скрывает — вызывающий (`AppLanguageCubit`)
/// выставляет `saveFailed`.
abstract interface class AppLanguagePreferences {
  Future<AppLanguageLoad> load();

  Future<void> save(AppLanguagePreference preference);
}

/// [AppLanguagePreferences] в `shared_preferences` под ключом
/// [kAppLanguageKey].
///
/// Незнакомое или нестроковое сохранённое значение читается как `system` и НЕ
/// перезаписывается: данные пользователя не портятся молча (`AGENTS.md` §2).
final class SharedPreferencesAppLanguagePreferences
    implements AppLanguagePreferences {
  /// [open] — шов тестов: по умолчанию `SharedPreferences.getInstance`.
  const SharedPreferencesAppLanguagePreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  }) : _open = open;

  final Future<SharedPreferences> Function() _open;

  @override
  Future<AppLanguageLoad> load() async {
    final SharedPreferences prefs;
    final Object? value;
    try {
      prefs = await _open();
      // `get`, а не `getString`: нестроковое значение не должно бросать
      // `TypeError` и ронять запуск.
      value = prefs.get(kAppLanguageKey);
    } on Object catch (error) {
      return AppLanguageLoad(
        AppLanguagePreference.system,
        readFailure: error.runtimeType.toString(),
      );
    }
    return switch (value) {
      'en' => const AppLanguageLoad(AppLanguagePreference.en),
      'ru' => const AppLanguageLoad(AppLanguagePreference.ru),
      null => const AppLanguageLoad(AppLanguagePreference.system),
      _ => const AppLanguageLoad(
        AppLanguagePreference.system,
        storedValueInvalid: true,
      ),
    };
  }

  @override
  Future<void> save(AppLanguagePreference preference) async {
    final prefs = await _open();
    switch (preference) {
      case AppLanguagePreference.system:
        await prefs.remove(kAppLanguageKey);
      case AppLanguagePreference.en:
        await prefs.setString(kAppLanguageKey, 'en');
      case AppLanguagePreference.ru:
        await prefs.setString(kAppLanguageKey, 'ru');
    }
  }
}
