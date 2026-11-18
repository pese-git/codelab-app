// Красные тесты хранения языка интерфейса (задача 1.1 change
// `add-desktop-localization`; design.md D2; spec app-settings «Язык
// интерфейса app»: «Незнакомое значение в хранилище»).
//
// Ключ `codelab.app.language`: `en`/`ru`; для `system` ключа нет. Незнакомое
// значение читается как `system` и НЕ перезаписывается (целостность данных,
// AGENTS.md §2).

import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import '../../support/recording_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const preferences = SharedPreferencesAppLanguagePreferences();

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
  }

  test('ключ хранилища — codelab.app.language', () {
    expect(kAppLanguageKey, 'codelab.app.language');
  });

  test('нет ключа — system', () async {
    await seed({});
    expect(await preferences.load(), AppLanguagePreference.system);
  });

  test('en и ru читаются как есть', () async {
    await seed({kAppLanguageKey: 'en'});
    expect(await preferences.load(), AppLanguagePreference.en);
    await seed({kAppLanguageKey: 'ru'});
    expect(await preferences.load(), AppLanguagePreference.ru);
  });

  test('незнакомое значение — system, ключ не перезаписывается', () async {
    await seed({kAppLanguageKey: 'fr'});
    expect(await preferences.load(), AppLanguagePreference.system);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAppLanguageKey), 'fr');
  });

  test('save(en) и save(ru) пишут значение', () async {
    await seed({});
    await preferences.save(AppLanguagePreference.ru);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAppLanguageKey), 'ru');
    await preferences.save(AppLanguagePreference.en);
    expect(prefs.getString(kAppLanguageKey), 'en');
  });

  test('save(system) удаляет ключ', () async {
    await seed({kAppLanguageKey: 'ru'});
    await preferences.save(AppLanguagePreference.system);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kAppLanguageKey), isFalse);
    expect(await preferences.load(), AppLanguagePreference.system);
  });

  group('предупреждение app.language_preference_invalid (D13)', () {
    test('незнакомое значение пишет warning без значения ключа', () async {
      await seed({kAppLanguageKey: 'fr'});
      final logger = RecordingLogger();

      await SharedPreferencesAppLanguagePreferences(logger: logger).load();

      final warning = logger.entries.singleWhere(
        (e) => e['event'] == 'app.language_preference_invalid',
      );
      expect(warning['level'], 'warning');
      expect(warning.values.whereType<String>().join(), isNot(contains('fr')));
    });

    test('допустимые значения и отсутствие ключа ничего не пишут', () async {
      final logger = RecordingLogger();
      final preferences = SharedPreferencesAppLanguagePreferences(
        logger: logger,
      );
      for (final value in <Map<String, Object>>[
        {},
        {kAppLanguageKey: 'en'},
        {kAppLanguageKey: 'ru'},
      ]) {
        await seed(value);
        await preferences.load();
      }

      expect(logger.entries, isEmpty);
    });
  });
}
