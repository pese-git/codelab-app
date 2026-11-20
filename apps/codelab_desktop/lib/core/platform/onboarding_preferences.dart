import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: onboarding первого запуска пройден
/// (`add-app-onboarding`, D2). Значение — только `true`.
const kOnboardingDoneKey = 'codelab.app.onboarding_done';

/// Результат чтения флага onboarding.
///
/// Почему не голый `bool`: чтение идёт в `main` до `runApp`, когда журнал ещё
/// не настроен, поэтому диагностику несёт результат, а события
/// `onboarding.flag_invalid` и `onboarding.flag_unreadable` пишет composition
/// root (D2, D3).
///
/// [done] — onboarding НЕ показывать. Он `false` только при отсутствии ключа.
/// [storedValueInvalid] — в ключе не `true`; [readFailure] — имя типа ошибки
/// хранилища (текст не хранится: в нём бывают пути). В обоих случаях [done]
/// равно `true`: целостность данных важнее UX (AGENTS.md §2).
final class OnboardingLoad {
  const OnboardingLoad(
    this.done, {
    this.storedValueInvalid = false,
    this.readFailure,
  });

  final bool done;
  final bool storedValueInvalid;
  final String? readFailure;
}

/// Порт хранения флага «onboarding пройден».
///
/// Почему отдельный порт: флаг — настройка окна app, а не агента и не CLI
/// (D2); образец — `AppLanguagePreferences`.
///
/// Как использовать: `load` НЕ бросает и вызывается до `runApp`; `markDone`
/// вызывается один раз при «Start using CodeLab» и бросает при сбое записи —
/// решение о повторе принимает вызывающий.
abstract interface class OnboardingPreferences {
  Future<OnboardingLoad> load();

  Future<void> markDone();
}

/// [OnboardingPreferences] в `shared_preferences` под ключом
/// [kOnboardingDoneKey].
///
/// Незнакомое значение или тип читается как «пройден» и НЕ перезаписывается.
final class SharedPreferencesOnboardingPreferences
    implements OnboardingPreferences {
  /// [open] — шов тестов: по умолчанию `SharedPreferences.getInstance`.
  const SharedPreferencesOnboardingPreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  }) : _open = open;

  final Future<SharedPreferences> Function() _open;

  @override
  Future<OnboardingLoad> load() async {
    final Object? value;
    try {
      final prefs = await _open();
      // `get`, а не `getBool`: другой тип не должен бросать `TypeError`.
      value = prefs.get(kOnboardingDoneKey);
    } on Object catch (error) {
      return OnboardingLoad(true, readFailure: error.runtimeType.toString());
    }
    return switch (value) {
      null => const OnboardingLoad(false),
      true => const OnboardingLoad(true),
      _ => const OnboardingLoad(true, storedValueInvalid: true),
    };
  }

  @override
  Future<void> markDone() async {
    final prefs = await _open();
    await prefs.setBool(kOnboardingDoneKey, true);
  }
}
