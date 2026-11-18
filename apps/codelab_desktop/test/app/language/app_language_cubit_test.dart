// Красные тесты AppLanguageCubit и порта AppStrings (задача 1.3 change
// `add-desktop-localization`; design.md D2, D5, D9, D13; spec app-settings
// «Сбой записи», «Два выбора подряд», «Закрытый компонент не реагирует на
// смену языка»).
//
// Cubit — единственный владелец языка: применяет выбор синхронно, до записи,
// а запись ставит в очередь; побеждает последний выбор.

import 'dart:async';
import 'dart:ui';

import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/language/app_locale.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_logger.dart';

/// Порт хранения с управляемым завершением записей.
final class _ControlledPreferences implements AppLanguagePreferences {
  final saves = <AppLanguagePreference>[];
  final _gates = <Completer<void>>[];
  bool autoComplete = false;
  Object? failWith;

  @override
  Future<AppLanguageLoad> load() async =>
      const AppLanguageLoad(AppLanguagePreference.system);

  @override
  Future<void> save(AppLanguagePreference preference) {
    saves.add(preference);
    if (autoComplete) {
      return failWith == null ? Future.value() : Future.error(failWith!);
    }
    final gate = Completer<void>();
    _gates.add(gate);
    return gate.future;
  }

  /// Завершает запись с номером [index] успешно или с [error].
  void complete(int index, [Object? error]) => error == null
      ? _gates[index].complete()
      : _gates[index].completeError(error);
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _ControlledPreferences preferences;
  late RecordingLogger logger;

  AppLanguageCubit build({
    AppLanguagePreference preference = AppLanguagePreference.en,
  }) => AppLanguageCubit(
    preferences: preferences,
    preference: preference,
    locale: resolveAppLocale(preference, const []),
    logger: logger,
    // Короткий срок: записи, которые тест не завершает, не держат `close()`.
    closeWriteTimeout: const Duration(milliseconds: 50),
  );

  setUp(() {
    preferences = _ControlledPreferences();
    logger = RecordingLogger();
  });

  test('начальное состояние берётся из шва, без загрузки и записи', () {
    final cubit = build(preference: AppLanguagePreference.ru);
    addTearDown(cubit.close);

    expect(cubit.state.preference, AppLanguagePreference.ru);
    expect(cubit.state.locale, const Locale('ru'));
    expect(cubit.state.strings.localeName, 'ru');
    expect(cubit.state.saveFailed, isFalse);
    expect(cubit.current.localeName, 'ru');
    expect(preferences.saves, isEmpty);
  });

  test('select(ru) публикует состояние синхронно, до завершения записи', () {
    final cubit = build();
    addTearDown(cubit.close);

    final done = cubit.select(AppLanguagePreference.ru);

    expect(cubit.state.locale, const Locale('ru'));
    expect(cubit.state.strings.localeName, 'ru');
    expect(preferences.saves, [AppLanguagePreference.ru]);
    preferences.complete(0);
    return done;
  });

  test('сбой записи: язык остаётся, saveFailed, событие без текста', () async {
    final cubit = build();
    addTearDown(cubit.close);

    final done = cubit.select(AppLanguagePreference.ru);
    preferences.complete(0, StateError('disk full'));
    await done;

    expect(cubit.state.locale, const Locale('ru'));
    expect(cubit.state.saveFailed, isTrue);
    final failed = logger.entries.singleWhere(
      (e) => e['event'] == 'settings.language_save_failed',
    );
    expect(failed['level'], 'warning');
    expect(failed['error_class'], 'StateError');
    expect(failed.values.whereType<String>().join(), isNot(contains('disk')));
  });

  test('успешная запись после сбоя снимает saveFailed', () async {
    final cubit = build();
    addTearDown(cubit.close);

    final first = cubit.select(AppLanguagePreference.ru);
    preferences.complete(0, StateError('x'));
    await first;
    final second = cubit.select(AppLanguagePreference.en);
    preferences.complete(1);
    await second;

    expect(cubit.state.saveFailed, isFalse);
  });

  test('ru, затем en при незавершённой первой записи: итог en, обогнанная '
      'запись состояние не публикует', () async {
    final cubit = build();
    addTearDown(cubit.close);
    final states = <AppLanguageState>[];
    final sub = cubit.stream.listen(states.add);
    addTearDown(sub.cancel);

    final first = cubit.select(AppLanguagePreference.ru);
    final second = cubit.select(AppLanguagePreference.en);
    expect(cubit.state.locale, const Locale('en'));

    // Первая запись завершается позже выбора en и с ошибкой: на состояние
    // она влиять не должна.
    preferences.complete(0, StateError('late failure'));
    await _pump();
    // Записи идут по очереди: обе начаты, порядок — ru, затем en.
    expect(preferences.saves, [
      AppLanguagePreference.ru,
      AppLanguagePreference.en,
    ]);
    preferences.complete(1);
    await Future.wait([first, second]);
    await _pump();

    expect(preferences.saves.last, AppLanguagePreference.en);
    expect(cubit.state.locale, const Locale('en'));
    expect(cubit.state.preference, AppLanguagePreference.en);
    expect(cubit.state.saveFailed, isFalse);
    expect(
      states.skip(1).every((s) => s.locale == const Locale('en')),
      isTrue,
      reason: 'после выбора en состояние на ru не возвращается',
    );
  });

  test('после close запись не применяется, changes закрыт', () async {
    final cubit = build();
    final done = cubit.select(AppLanguagePreference.ru);

    final closing = cubit.close();
    preferences.complete(0, StateError('after close'));
    await closing;
    await done;

    expect(cubit.state.saveFailed, isFalse);
    await expectLater(cubit.changes, emitsDone);
  });

  test(
    'три выбора, последняя запись падает, предыдущие прошли: saveFailed',
    () async {
      final cubit = build();
      addTearDown(cubit.close);

      final all = Future.wait([
        cubit.select(AppLanguagePreference.ru),
        cubit.select(AppLanguagePreference.en),
        cubit.select(AppLanguagePreference.ru),
      ]);
      preferences.complete(0);
      await _pump();
      preferences.complete(1);
      await _pump();
      preferences.complete(2, StateError('last write'));
      await all;

      expect(cubit.state.preference, AppLanguagePreference.ru);
      expect(cubit.state.saveFailed, isTrue);
    },
  );

  group('close (D2, concurrency §47а)', () {
    test('подписчик на паузе не держит close()', () async {
      final cubit = build();
      final sub = cubit.changes.listen((_) {});
      sub.pause();

      await cubit.close().timeout(const Duration(seconds: 2));

      await sub.cancel();
    });

    test('close() ждёт запись в полёте и не публикует состояние', () async {
      final cubit = build();
      final states = <AppLanguageState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);
      final done = cubit.select(AppLanguagePreference.ru);
      await _pump();
      final emitted = states.length;

      var closed = false;
      final closing = cubit.close().then((_) => closed = true);
      await _pump();
      expect(closed, isFalse, reason: 'запись ещё идёт');

      preferences.complete(0, StateError('late'));
      await closing;
      await done;

      expect(closed, isTrue);
      expect(states.length, emitted, reason: 'после close состояний нет');
    });

    testWidgets('зависшая запись не держит close() дольше срока', (
      tester,
    ) async {
      // Поддельные часы `testWidgets` (`testing.md` §20): срок 50 мс не
      // ждётся по-настоящему.
      final cubit = build();
      unawaited(cubit.select(AppLanguagePreference.ru));

      var closed = false;
      unawaited(cubit.close().then((_) => closed = true));
      await tester.pump(const Duration(milliseconds: 10));
      expect(closed, isFalse, reason: 'срок ещё не вышел');

      await tester.pump(const Duration(milliseconds: 50));

      expect(closed, isTrue);
    });

    testWidgets('срок записи истёк: warning settings.language_save_timeout с '
        'timeout_ms, без выбора и текста ошибки', (tester) async {
      final cubit = build();
      unawaited(cubit.select(AppLanguagePreference.ru));
      unawaited(cubit.close());

      await tester.pump(const Duration(milliseconds: 50));

      final timeout = logger.entries.singleWhere(
        (e) => e['event'] == 'settings.language_save_timeout',
      );
      expect(timeout['level'], 'warning');
      expect(timeout['timeout_ms'], 50);
      expect(timeout.containsKey('language'), isFalse);
      expect(timeout.containsKey('error_class'), isFalse);
    });

    testWidgets('запись успела до срока: события таймаута нет', (tester) async {
      final cubit = build();
      final done = cubit.select(AppLanguagePreference.ru);
      final closing = cubit.close();
      preferences.complete(0);
      await done;
      await closing;

      expect(
        logger.entries.where(
          (e) => e['event'] == 'settings.language_save_timeout',
        ),
        isEmpty,
      );
    });

    test('select во время close не бросает и ничего не пишет', () async {
      final cubit = build();
      final closing = cubit.close();

      await cubit.select(AppLanguagePreference.ru);
      await closing;

      expect(preferences.saves, isEmpty);
      expect(cubit.state.locale, const Locale('en'));
    });

    test('подписка во время close сразу получает done', () async {
      final cubit = build();
      unawaited(cubit.select(AppLanguagePreference.ru));
      final closing = cubit.close();

      await expectLater(cubit.changes, emitsDone);
      preferences.complete(0);
      await closing;
    });

    test(
      'повтор того же значения при записи в полёте ждёт эту запись',
      () async {
        final cubit = build();
        addTearDown(cubit.close);
        final first = cubit.select(AppLanguagePreference.ru);

        var repeated = false;
        final again = cubit
            .select(AppLanguagePreference.ru)
            .then((_) => repeated = true);
        await _pump();
        expect(repeated, isFalse);

        preferences.complete(0);
        await Future.wait([first, again]);
        expect(repeated, isTrue);
      },
    );
  });

  group('AppStrings.changes', () {
    test(
      'один новый каталог на смену языка; тот же язык события не даёт',
      () async {
        preferences.autoComplete = true;
        final cubit = build();
        addTearDown(cubit.close);
        final received = <String>[];
        final sub = cubit.changes.listen((s) => received.add(s.localeName));
        addTearDown(sub.cancel);

        await cubit.select(AppLanguagePreference.ru);
        await _pump();
        expect(received, ['ru']);

        await cubit.select(AppLanguagePreference.ru);
        await _pump();
        expect(received, ['ru']);

        await cubit.select(AppLanguagePreference.en);
        await _pump();
        expect(received, ['ru', 'en']);
        expect(cubit.current.localeName, 'en');
      },
    );
  });

  group('события журнала (D13)', () {
    test('settings.language_changed и app.locale_applied', () async {
      preferences.autoComplete = true;
      final cubit = build();
      addTearDown(cubit.close);
      final sub = cubit.changes.listen((_) {});
      addTearDown(sub.cancel);

      await cubit.select(AppLanguagePreference.ru);

      final changed = logger.entries.singleWhere(
        (e) => e['event'] == 'settings.language_changed',
      );
      expect(changed['level'], 'info');
      expect(changed['language'], 'ru');
      expect(changed['locale'], 'ru');

      final applied = logger.entries.singleWhere(
        (e) => e['event'] == 'app.locale_applied',
      );
      expect(applied['level'], 'debug');
      expect(applied['locale'], 'ru');
      expect(applied['subscribers'], 1);
    });
  });
}
