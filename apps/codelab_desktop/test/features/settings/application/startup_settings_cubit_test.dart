// `StartupSettingsCubit` (задача 3.5 change `add-app-general-page`; spec
// app-settings «Открытие последнего проекта при запуске»: переключение,
// «Сбой записи» с «Retry», событие журнала; design.md D9, D16).
//
// Красные тесты: Cubit — заглушка итерации 3, логика появится в задаче 3.6.
//
// Cubit владеет только значением настройки и портом хранения: рабочего
// пространства и подключения у него нет, поэтому переключение не может
// тронуть текущую работу (сценарий «Переключение не трогает текущую работу»
// на уровне страницы — в `general_page_test.dart`).

import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:codelab_desktop/features/settings/application/startup_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

/// Порт-двойник: записи идут в [saves], сбой задаёт тест.
final class _Port implements StartupPreferences {
  _Port({this.stored = const StartupLoad(true)});

  StartupLoad stored;
  final saves = <bool>[];

  /// Ошибка вместо записи; `null` — запись проходит.
  Object? saveError;

  @override
  Future<StartupLoad> load() async => stored;

  @override
  Future<void> save(bool reopenLastProject) async {
    saves.add(reopenLastProject);
    if (saveError case final error?) {
      throw error;
    }
  }
}

void main() {
  late RecordingLogger logger;
  late _Port port;
  late StartupSettingsCubit cubit;

  StartupSettingsCubit make([_Port? custom]) {
    port = custom ?? _Port();
    cubit = StartupSettingsCubit(preferences: port, logger: logger);
    addTearDown(cubit.close);
    return cubit;
  }

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  setUp(() => logger = RecordingLogger());

  test('до чтения значение по умолчанию — включено, без сбоя', () {
    make();

    expect(cubit.state.reopenLastProject, isTrue);
    expect(cubit.state.saveFailed, isFalse);
  });

  group('load', () {
    test('читает выключенное значение', () async {
      make(_Port(stored: const StartupLoad(false)));

      await cubit.load();

      expect(cubit.state.reopenLastProject, isFalse);
      expect(cubit.state.saveFailed, isFalse);
    });

    test('нечитаемое значение — включено, ничего не записывается', () async {
      make(_Port(stored: const StartupLoad(true, storedValueInvalid: true)));

      await cubit.load();

      expect(cubit.state.reopenLastProject, isTrue);
      expect(port.saves, isEmpty);
    });
  });

  group('select', () {
    test('выключение: запись false, значение в состоянии, событие без '
        'путей', () async {
      make();

      await cubit.select(false);

      expect(port.saves, [false]);
      expect(cubit.state.reopenLastProject, isFalse);
      expect(cubit.state.saveFailed, isFalse);
      final changed = events('settings.reopen_last_project_changed').single;
      expect(changed['enabled'], false);
      expect(changed['level'], 'info');
    });

    test('включение: запись true', () async {
      make(_Port(stored: const StartupLoad(false)));
      await cubit.load();

      await cubit.select(true);

      expect(port.saves, [true]);
      expect(cubit.state.reopenLastProject, isTrue);
      expect(
        events('settings.reopen_last_project_changed').single['enabled'],
        true,
      );
    });
  });

  group('сбой записи (D9)', () {
    test('переключатель остаётся в выбранном положении, saveFailed, событие '
        'с именем типа без текста', () async {
      make();
      port.saveError = StateError('disk is read-only: /secret/path');

      await cubit.select(false);

      expect(cubit.state.reopenLastProject, isFalse);
      expect(cubit.state.saveFailed, isTrue);
      final failed = events('settings.reopen_last_project_save_failed').single;
      expect(failed['error_type'], 'StateError');
      expect(failed['level'], 'warning');
      expect(logger.entries.toString(), isNot(contains('/secret/path')));
      expect(logger.entries.toString(), isNot(contains('read-only')));
      expect(events('settings.reopen_last_project_changed'), isEmpty);
    });

    test('Retry повторяет запись выбранного значения; успех снимает '
        'сбой', () async {
      make();
      port.saveError = StateError('boom');
      await cubit.select(false);

      port.saveError = null;
      await cubit.retry();

      expect(port.saves, [false, false]);
      expect(cubit.state.saveFailed, isFalse);
      expect(cubit.state.reopenLastProject, isFalse);
      expect(
        events('settings.reopen_last_project_changed').single['enabled'],
        false,
      );
    });

    test('Retry без сбоя ничего не пишет', () async {
      make();

      await cubit.retry();

      expect(port.saves, isEmpty);
    });

    test('новый выбор после сбоя снимает предупреждение при успехе', () async {
      make();
      port.saveError = StateError('boom');
      await cubit.select(false);
      port.saveError = null;

      await cubit.select(true);

      expect(cubit.state.saveFailed, isFalse);
      expect(cubit.state.reopenLastProject, isTrue);
    });
  });

  test('запись после close() не меняет состояние и не бросает', () async {
    make();
    final done = cubit.select(false);
    await cubit.close();

    await done;

    expect(cubit.isClosed, isTrue);
  });
}
