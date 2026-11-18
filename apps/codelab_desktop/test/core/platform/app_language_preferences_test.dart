// Красные тесты хранения языка интерфейса (задача 1.1 change
// `add-desktop-localization`; design.md D2; spec app-settings «Язык
// интерфейса app»: «Незнакомое значение в хранилище»).
//
// Ключ `codelab.app.language`: `en`/`ru`; для `system` ключа нет. Незнакомое
// значение читается как `system` и НЕ перезаписывается (целостность данных,
// AGENTS.md §2).

import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
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
}
