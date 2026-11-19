// Тесты хранения настройки «Reopen the last project and its tabs»
// (задача 3.3 change `add-app-general-page`; design.md D9; spec app-settings
// «Открытие последнего проекта при запуске»).
//
// Реализация — задачи 3.3 и 3.4 change `add-app-general-page`.
//
// Ключ `codelab.workspace.reopen_last_project` (`bool`): включённое значение
// (по умолчанию) — ключа нет, выключенное — `false`. Нечитаемое значение
// читается как включённое, признак уходит вызывающему для журнала, а ключ НЕ
// перезаписывается (целостность данных, AGENTS.md §2). Ошибку записи порт не
// скрывает: её показывает страница («Retry»).

import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const preferences = SharedPreferencesStartupPreferences();

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
  }

  test('ключ хранилища — codelab.workspace.reopen_last_project', () {
    expect(kReopenLastProjectKey, 'codelab.workspace.reopen_last_project');
  });

  group('load', () {
    test('нет ключа — включено, без признаков', () async {
      await seed({});

      final load = await preferences.load();

      expect(load.reopenLastProject, isTrue);
      expect(load.storedValueInvalid, isFalse);
      expect(load.readFailure, isNull);
    });

    test('false читается как выключено', () async {
      await seed({kReopenLastProjectKey: false});

      final load = await preferences.load();

      expect(load.reopenLastProject, isFalse);
      expect(load.storedValueInvalid, isFalse);
    });

    test('true читается как включено', () async {
      await seed({kReopenLastProjectKey: true});

      expect((await preferences.load()).reopenLastProject, isTrue);
    });

    test('небулево значение — включено с признаком, ключ не '
        'перезаписывается', () async {
      await seed({kReopenLastProjectKey: 'no'});

      final load = await preferences.load();

      expect(load.reopenLastProject, isTrue);
      expect(load.storedValueInvalid, isTrue);
      expect(load.readFailure, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(kReopenLastProjectKey), 'no');
    });

    test('сбой хранилища не бросает: включено и имя типа ошибки без '
        'текста', () async {
      final failing = SharedPreferencesStartupPreferences(
        open: () => Future.error(StateError('disk is read-only: /secret/x')),
      );

      final load = await failing.load();

      expect(load.reopenLastProject, isTrue);
      expect(load.readFailure, 'StateError');
      expect(load.storedValueInvalid, isFalse);
      expect('${load.readFailure}', isNot(contains('/secret')));
    });
  });

  group('save', () {
    test('save(true) удаляет ключ', () async {
      await seed({kReopenLastProjectKey: false});

      await preferences.save(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kReopenLastProjectKey), isFalse);
      expect((await preferences.load()).reopenLastProject, isTrue);
    });

    test('save(false) пишет false', () async {
      await seed({});

      await preferences.save(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kReopenLastProjectKey), isFalse);
      expect((await preferences.load()).reopenLastProject, isFalse);
    });

    test('ошибку записи порт не скрывает', () async {
      final failing = SharedPreferencesStartupPreferences(
        open: () => Future.error(StateError('disk is full')),
      );

      await expectLater(failing.save(false), throwsStateError);
    });
  });
}
