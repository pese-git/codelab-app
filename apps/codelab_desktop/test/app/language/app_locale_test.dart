// Красные тесты разрешения языка интерфейса (задача 1.1 change
// `add-desktop-localization`; design.md D2; spec app-settings «Язык
// интерфейса app»: «По умолчанию — язык системы», «Незнакомый язык
// системы», «Явный выбор сильнее системы»).
//
// Итерация 6 (задача 6.1): временное правило D2 снято — `system` даёт `ru`,
// если `languageCode` первого языка системы `ru`, иначе `en` (Q5 (а)).

import 'dart:ui';

import 'package:codelab_desktop/app/language/app_locale.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ruRu = Locale('ru', 'RU');
  const deDe = Locale('de', 'DE');
  const enUs = Locale('en', 'US');

  group('явный выбор', () {
    test('en остаётся en при любом языке системы', () {
      expect(
        resolveAppLocale(AppLanguagePreference.en, const [ruRu]),
        const Locale('en'),
      );
    });

    test('ru остаётся ru при любом языке системы', () {
      expect(
        resolveAppLocale(AppLanguagePreference.ru, const [enUs]),
        const Locale('ru'),
      );
      expect(
        resolveAppLocale(AppLanguagePreference.ru, const []),
        const Locale('ru'),
      );
    });
  });

  group('system — язык системы (D2, Q5 (а))', () {
    test('ru-RU даёт ru (сценарий «По умолчанию — язык системы»)', () {
      expect(
        resolveAppLocale(AppLanguagePreference.system, const [ruRu]),
        const Locale('ru'),
      );
    });

    test('de-DE даёт en', () {
      expect(
        resolveAppLocale(AppLanguagePreference.system, const [deDe]),
        const Locale('en'),
      );
    });

    test('пустой список языков системы даёт en', () {
      expect(
        resolveAppLocale(AppLanguagePreference.system, const []),
        const Locale('en'),
      );
    });

    test('берётся только первый язык: ru вторым не даёт ru', () {
      expect(
        resolveAppLocale(AppLanguagePreference.system, const [deDe, ruRu]),
        const Locale('en'),
      );
    });

    test('ru первым, de вторым даёт ru', () {
      expect(
        resolveAppLocale(AppLanguagePreference.system, const [ruRu, deDe]),
        const Locale('ru'),
      );
    });
  });
}
