// Красные тесты флага onboarding (задача 1.3 change `add-app-onboarding`;
// design.md D2; spec app-onboarding «Показ onboarding при первом запуске»:
// «Повреждённое значение флага», «Хранилище не читается»).
//
// Красные по причине компиляции: `onboarding_preferences.dart` появляется в
// задаче 1.4.
//
// Ключ `codelab.app.onboarding_done`: только `true`. Незнакомое значение или
// тип читается как «пройден» и НЕ перезаписывается (целостность данных,
// AGENTS.md §2); сбой хранилища — «пройден» с `readFailure` (имя типа без
// текста: в нём бывают пути).

import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const preferences = SharedPreferencesOnboardingPreferences();

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
  }

  test('ключ хранилища — codelab.app.onboarding_done', () {
    expect(kOnboardingDoneKey, 'codelab.app.onboarding_done');
  });

  test(
    'нет ключа — onboarding показывается (done: false), без диагностики',
    () async {
      await seed({});

      final load = await preferences.load();

      expect(load.done, isFalse);
      expect(load.storedValueInvalid, isFalse);
      expect(load.readFailure, isNull);
      // Чтение ключ не создаёт: он пишется только при завершении шага «Open a project».
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kOnboardingDoneKey), isFalse);
    },
  );

  test('true — onboarding пройден', () async {
    await seed({kOnboardingDoneKey: true});

    final load = await preferences.load();

    expect(load.done, isTrue);
    expect(load.storedValueInvalid, isFalse);
    expect(load.readFailure, isNull);
  });

  test(
    'строка "yes" — пройден, storedValueInvalid, ключ не перезаписан',
    () async {
      await seed({kOnboardingDoneKey: 'yes'});

      final load = await preferences.load();

      expect(load.done, isTrue);
      expect(load.storedValueInvalid, isTrue);
      expect(load.readFailure, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(kOnboardingDoneKey), 'yes');
    },
  );

  test('false и число — тоже повреждённое значение, ключ цел', () async {
    await seed({kOnboardingDoneKey: false});
    final falseLoad = await preferences.load();
    expect(falseLoad.done, isTrue);
    expect(falseLoad.storedValueInvalid, isTrue);

    await seed({kOnboardingDoneKey: 1});
    final intLoad = await preferences.load();
    expect(intLoad.done, isTrue);
    expect(intLoad.storedValueInvalid, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.get(kOnboardingDoneKey), 1);
  });

  test(
    'сбой хранилища: пройден, readFailure — имя типа без текста и пути',
    () async {
      final failing = SharedPreferencesOnboardingPreferences(
        open: () async =>
            throw StateError('нет доступа к /Users/x/secret.json'),
      );

      final load = await failing.load();

      expect(load.done, isTrue);
      expect(load.storedValueInvalid, isFalse);
      expect(load.readFailure, 'StateError');
      expect(load.readFailure, isNot(contains('/Users')));
    },
  );

  test('markDone пишет true', () async {
    await seed({});

    await preferences.markDone();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
    expect((await preferences.load()).done, isTrue);
  });

  test('markDone пробрасывает ошибку записи', () async {
    final failing = SharedPreferencesOnboardingPreferences(
      open: () async => throw StateError('write failed'),
    );

    await expectLater(failing.markDone(), throwsA(isA<StateError>()));
  });
}
