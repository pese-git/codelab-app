// Красные тесты хранения оформления app (задача 4.1 change
// `add-app-appearance-page`; design.md D5; spec app-settings «Хранение
// оформления»: «Повреждённый документ»).
//
// Один ключ `codelab.app.appearance` с JSON-документом: `version`, `mode`,
// `light_theme`, `dark_theme`, `system_accent`. `load()` не бросает; незнакомое
// значение читается как значение по умолчанию для своего поля и НЕ
// перезаписывается до явного выбора (целостность данных, AGENTS.md §2).

import 'dart:convert';

import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const preferences = SharedPreferencesAppAppearancePreferences();

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
  }

  Future<Object?> stored() async =>
      (await SharedPreferences.getInstance()).get(kAppAppearanceKey);

  test('ключ хранилища — codelab.app.appearance', () {
    expect(kAppAppearanceKey, 'codelab.app.appearance');
  });

  test('нет ключа: Match system, light, dark, акцент выключен, без '
      'диагностики', () async {
    await seed({});

    final load = await preferences.load();

    expect(load.settings, const AppAppearanceSettings());
    expect(load.settings.mode, AppearanceMode.system);
    expect(load.settings.lightTheme, 'light');
    expect(load.settings.darkTheme, 'dark');
    expect(load.settings.systemAccent, isFalse);
    expect(load.storedValueInvalid, isFalse);
    expect(load.readFailure, isNull);
  });

  test('save пишет один JSON-документ версии 1 с полями формата', () async {
    await seed({});

    await preferences.save(
      const AppAppearanceSettings(
        mode: AppearanceMode.dark,
        lightTheme: 'light',
        darkTheme: 'acme-night',
        systemAccent: true,
      ),
    );

    final raw = await stored();
    expect(raw, isA<String>());
    expect(jsonDecode(raw! as String), {
      'version': 1,
      'mode': 'dark',
      'light_theme': 'light',
      'dark_theme': 'acme-night',
      'system_accent': true,
    });
  });

  test('save и load возвращают тот же выбор', () async {
    await seed({});
    const chosen = AppAppearanceSettings(
      mode: AppearanceMode.light,
      lightTheme: 'acme-day',
      darkTheme: 'high-contrast',
      systemAccent: true,
    );

    await preferences.save(chosen);

    expect((await preferences.load()).settings, chosen);
  });

  test('отсутствующее поле берётся по умолчанию, остальные читаются', () async {
    await seed({
      kAppAppearanceKey: jsonEncode({'version': 1, 'dark_theme': 'acme-night'}),
    });

    final load = await preferences.load();

    expect(load.settings, const AppAppearanceSettings(darkTheme: 'acme-night'));
    expect(load.storedValueInvalid, isFalse);
  });

  group('повреждённый документ (spec «Повреждённый документ»)', () {
    test(
      '{"mode": "sepia"}: умолчания, признак, ключ не перезаписан',
      () async {
        const document = '{"mode": "sepia"}';
        await seed({kAppAppearanceKey: document});

        final load = await preferences.load();

        expect(load.settings, const AppAppearanceSettings());
        expect(load.storedValueInvalid, isTrue);
        expect(load.readFailure, isNull);
        expect(await stored(), document);
      },
    );

    test('незнакомое значение одного поля не портит остальные', () async {
      await seed({
        kAppAppearanceKey: jsonEncode({
          'version': 1,
          'mode': 'sepia',
          'dark_theme': 'acme-night',
          'system_accent': true,
        }),
      });

      final load = await preferences.load();

      expect(load.settings.mode, AppearanceMode.system);
      expect(load.settings.darkTheme, 'acme-night');
      expect(load.settings.systemAccent, isTrue);
      expect(load.storedValueInvalid, isTrue);
    });

    test('не JSON: умолчания, признак, ключ не перезаписан', () async {
      await seed({kAppAppearanceKey: 'not json {'});

      final load = await preferences.load();

      expect(load.settings, const AppAppearanceSettings());
      expect(load.storedValueInvalid, isTrue);
      expect(await stored(), 'not json {');
    });

    test('нестроковое значение ключа не роняет чтение', () async {
      await seed({kAppAppearanceKey: 1});

      final load = await preferences.load();

      expect(load.settings, const AppAppearanceSettings());
      expect(load.storedValueInvalid, isTrue);
      expect(await stored(), 1);
    });

    test('неизвестная версия документа читается как умолчания', () async {
      await seed({
        kAppAppearanceKey: jsonEncode({'version': 2, 'mode': 'dark'}),
      });

      final load = await preferences.load();

      expect(load.settings, const AppAppearanceSettings());
      expect(load.storedValueInvalid, isTrue);
    });

    test('поле не того типа читается как умолчание поля', () async {
      await seed({
        kAppAppearanceKey: jsonEncode({
          'version': 1,
          'mode': 5,
          'system_accent': 'yes',
        }),
      });

      final load = await preferences.load();

      expect(load.settings, const AppAppearanceSettings());
      expect(load.storedValueInvalid, isTrue);
    });

    test(
      'имя темы вне формата [a-z0-9-]{1,32} читается как умолчание',
      () async {
        await seed({
          kAppAppearanceKey: jsonEncode({
            'version': 1,
            'dark_theme': '../secret',
          }),
        });

        final load = await preferences.load();

        expect(load.settings.darkTheme, 'dark');
        expect(load.storedValueInvalid, isTrue);
      },
    );
  });

  group('тема чужого режима в поле режима', () {
    test('тёмная встроенная в light_theme — light', () async {
      await seed({
        kAppAppearanceKey: jsonEncode({
          'version': 1,
          'light_theme': 'dark',
          'dark_theme': 'dark',
        }),
      });

      final load = await preferences.load();

      expect(load.settings.lightTheme, 'light');
      expect(load.settings.darkTheme, 'dark');
      expect(load.storedValueInvalid, isTrue);
    });

    test(
      'light и high-contrast в dark_theme — dark; ключ не перезаписан',
      () async {
        final document = jsonEncode({
          'version': 1,
          'light_theme': 'high-contrast',
          'dark_theme': 'light',
        });
        await seed({kAppAppearanceKey: document});

        final load = await preferences.load();

        expect(load.settings.lightTheme, 'light');
        expect(load.settings.darkTheme, 'dark');
        expect(load.storedValueInvalid, isTrue);
        expect(await stored(), document);
      },
    );

    test('high-contrast в dark_theme допустима', () async {
      await seed({
        kAppAppearanceKey: jsonEncode({
          'version': 1,
          'dark_theme': 'high-contrast',
        }),
      });

      final load = await preferences.load();

      expect(load.settings.darkTheme, 'high-contrast');
      expect(load.storedValueInvalid, isFalse);
    });
  });

  group('сбой хранилища при старте', () {
    test('load не бросает: умолчания и имя типа ошибки без текста', () async {
      final failing = SharedPreferencesAppAppearancePreferences(
        open: () => Future.error(const FormatException('/secret/path')),
      );

      final load = await failing.load();

      expect(load.settings, const AppAppearanceSettings());
      expect(load.readFailure, 'FormatException');
      expect(load.storedValueInvalid, isFalse);
    });

    test('save не скрывает ошибку записи', () async {
      final failing = SharedPreferencesAppAppearancePreferences(
        open: () => Future.error(StateError('disk full')),
      );

      await expectLater(
        failing.save(const AppAppearanceSettings()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
