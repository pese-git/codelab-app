// Красные тесты AppAppearanceCubit (задачи 4.5 и 4.9 change
// `add-app-appearance-page`; design.md D4, D7, D12, D13; spec app-settings
// «Режим оформления и темы режимов», «Системный акцент», «Карточки тем и
// превью» (Use, Reset), «Хранение оформления» (сбой записи), «События журнала
// оформления»).
//
// Cubit — единственный владелец применённого оформления: сначала `emit`,
// потом запись; записи идут по очереди, побеждает последний выбор, обогнанная
// запись состояние не публикует (`concurrency.md` §47б, по образцу языка).

import 'dart:async';
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_cubit.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_system_accent_source.dart';
import '../../support/recording_logger.dart';

/// Порт хранения с управляемым завершением записей.
final class _ControlledPreferences implements AppAppearancePreferences {
  final saves = <AppAppearanceSettings>[];
  final _gates = <Completer<void>>[];
  bool autoComplete = false;
  Object? failWith;

  @override
  Future<AppAppearanceLoad> load() async =>
      const AppAppearanceLoad(AppAppearanceSettings());

  @override
  Future<void> save(AppAppearanceSettings settings) {
    saves.add(settings);
    if (autoComplete) {
      return failWith == null ? Future.value() : Future.error(failWith!);
    }
    final gate = Completer<void>();
    _gates.add(gate);
    return gate.future;
  }

  void complete(int index, [Object? error]) => error == null
      ? _gates[index].complete()
      : _gates[index].completeError(error);
}

/// Каталог, у которого `list()` завершается по сигналу теста.
final class _GatedLibrary implements ThemeLibrary {
  _GatedLibrary(this._inner);

  final InMemoryThemeLibrary _inner;
  final gates = <Completer<void>>[];

  @override
  Future<List<ThemeEntry>> list() async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return _inner.list();
  }

  @override
  Future<ThemeImportResult> import(String sourcePath, {bool replace = false}) =>
      _inner.import(sourcePath, replace: replace);
}

String _theme(
  String name, {
  String base = 'dark',
  String accent = '#b4a0ff',
  String success = '#00ff00',
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'name': name,
  'extends': base,
  'colors': {'accent': accent, 'success': success, ...extra},
});

ThemeLoaded _loaded(String name, String text) =>
    ThemeFile.parse('$name.json', text) as ThemeLoaded;

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Color _success(FluentThemeData theme) => CodeLabPalette.of(theme).success;

void main() {
  late _ControlledPreferences preferences;
  late InMemoryThemeLibrary library;
  late FakeSystemAccentSource accent;
  late RecordingLogger logger;

  final night = _theme('acme-night');
  const customGreen = Color(0xFF00FF00);

  AppAppearanceCubit build({
    AppAppearanceSettings settings = const AppAppearanceSettings(),
    ThemeLoaded? lightTheme,
    ThemeLoaded? darkTheme,
    ThemeLibrary? themes,
    int? systemAccent,
    bool supported = true,
  }) => AppAppearanceCubit(
    preferences: preferences,
    library: themes ?? library,
    accentSource: accent,
    start: AppAppearanceStart(
      settings: settings,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      systemAccentSupported: supported,
      systemAccent: systemAccent,
    ),
    logger: logger,
    // Короткий срок: записи, которые тест не завершает, не держат `close()`.
    closeWriteTimeout: const Duration(milliseconds: 50),
  );

  setUp(() {
    preferences = _ControlledPreferences()..autoComplete = true;
    library = InMemoryThemeLibrary(themes: {'acme-night': night});
    accent = FakeSystemAccentSource(accent: 0xFFFF2D55);
    logger = RecordingLogger();
  });

  group('режим и темы двух режимов', () {
    test('начальное состояние берётся из шва, без записи', () {
      final cubit = build(
        settings: const AppAppearanceSettings(mode: AppearanceMode.dark),
      );
      addTearDown(cubit.close);

      expect(cubit.state.mode, AppearanceMode.dark);
      expect(cubit.state.themeMode, ThemeMode.dark);
      expect(cubit.state.lightTheme, 'light');
      expect(cubit.state.darkTheme, 'dark');
      expect(cubit.state.saveFailed, isFalse);
      expect(cubit.state.fallback, AppearanceFallback.none);
      expect(preferences.saves, isEmpty);
    });

    test('Match system даёт ThemeMode.system', () {
      final cubit = build();
      addTearDown(cubit.close);

      expect(cubit.state.themeMode, ThemeMode.system);
    });

    test(
      '«Темы двух режимов»: acme-night в тёмном, Fluent Light в светлом',
      () async {
        final cubit = build(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.light,
            darkTheme: 'acme-night',
          ),
          darkTheme: _loaded('acme-night', night),
        );
        addTearDown(cubit.close);

        await cubit.setMode(AppearanceMode.dark);

        expect(cubit.state.mode, AppearanceMode.dark);
        expect(cubit.state.themeMode, ThemeMode.dark);
        expect(_success(cubit.state.resolvedDark), customGreen);
        expect(
          preferences.saves.last,
          const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
        );

        await cubit.setMode(AppearanceMode.light);

        expect(cubit.state.themeMode, ThemeMode.light);
        expect(_success(cubit.state.resolvedLight), isNot(customGreen));
        expect(_success(cubit.state.resolvedLight), Colors.green);
      },
    );

    test('«Удалённый файл темы»: встроенная тема режима, выбор не '
        'перезаписан, fallback', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        // Файл не загрузился: шов не несёт `ThemeLoaded`.
        darkTheme: null,
      );
      addTearDown(cubit.close);

      expect(cubit.state.darkTheme, 'acme-night');
      expect(cubit.state.fallback, AppearanceFallback.dark);
      expect(_success(cubit.state.resolvedDark), isNot(customGreen));
      expect(preferences.saves, isEmpty);
    });

    test(
      'смена режима без смены темы пишет документ с прежними темами',
      () async {
        final cubit = build();
        addTearDown(cubit.close);

        await cubit.setMode(AppearanceMode.dark);

        expect(
          preferences.saves.single,
          const AppAppearanceSettings(mode: AppearanceMode.dark),
        );
      },
    );
  });

  group('Use и Reset (spec «Карточки тем и превью»)', () {
    test('«Use переключает фиксированный режим»: acme-night на Light → '
        'тёмная тема и режим Dark', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(mode: AppearanceMode.light),
      );
      addTearDown(cubit.close);

      await cubit.useTheme('acme-night');

      expect(cubit.state.darkTheme, 'acme-night');
      expect(cubit.state.mode, AppearanceMode.dark);
      expect(_success(cubit.state.resolvedDark), customGreen);
    });

    test('при Match system режим не меняется', () async {
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.useTheme('acme-night');

      expect(cubit.state.darkTheme, 'acme-night');
      expect(cubit.state.mode, AppearanceMode.system);
    });

    test(
      'тема светлого режима на Dark: светлая тема меняется, режим — Light',
      () async {
        library.files['acme-day'] = _theme('acme-day', base: 'light');
        final cubit = build(
          settings: const AppAppearanceSettings(mode: AppearanceMode.dark),
        );
        addTearDown(cubit.close);

        await cubit.useTheme('acme-day');

        expect(cubit.state.lightTheme, 'acme-day');
        expect(cubit.state.mode, AppearanceMode.light);
      },
    );

    test('встроенная dark на Light переключает на Dark', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(mode: AppearanceMode.light),
      );
      addTearDown(cubit.close);

      await cubit.useTheme('high-contrast');

      expect(cubit.state.darkTheme, 'high-contrast');
      expect(cubit.state.mode, AppearanceMode.dark);
    });

    test('тема, которая не загрузилась, не назначается', () async {
      library.files['broken'] = '{';
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.useTheme('broken');

      expect(cubit.state.darkTheme, 'dark');
      expect(cubit.state.lightTheme, 'light');
      expect(preferences.saves, isEmpty);
    });

    test('«Reset»: тёмная тема возвращается к dark', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        darkTheme: _loaded('acme-night', night),
      );
      addTearDown(cubit.close);

      await cubit.resetTheme(Brightness.dark);

      expect(cubit.state.darkTheme, 'dark');
      expect(cubit.state.lightTheme, 'light');
      expect(_success(cubit.state.resolvedDark), isNot(customGreen));
      expect(preferences.saves.last.darkTheme, 'dark');
    });
  });

  group('системный акцент (D7, Q4)', () {
    test(
      '«Системный акцент включён»: accentColor построен из #ff2d55',
      () async {
        final cubit = build();
        addTearDown(cubit.close);

        await cubit.setSystemAccent(true);

        expect(cubit.state.systemAccent, isTrue);
        expect(
          cubit.state.resolvedLight.accentColor.normal,
          const Color(0xFFFF2D55),
        );
        expect(
          cubit.state.resolvedDark.accentColor.normal,
          const Color(0xFFFF2D55),
        );
        expect(preferences.saves.last.systemAccent, isTrue);
      },
    );

    test(
      '«Пользовательская тема и системный акцент»: системный побеждает',
      () async {
        final cubit = build(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
          darkTheme: _loaded('acme-night', night),
        );
        addTearDown(cubit.close);
        expect(
          cubit.state.resolvedDark.accentColor.normal,
          const Color(0xFFB4A0FF),
          reason: 'без системного акцента действует accent темы',
        );

        await cubit.setSystemAccent(true);

        expect(
          cubit.state.resolvedDark.accentColor.normal,
          const Color(0xFFFF2D55),
        );
        expect(_success(cubit.state.resolvedDark), customGreen);
      },
    );

    test('начальный акцент из шва применяется в первом состоянии', () {
      final cubit = build(
        settings: const AppAppearanceSettings(systemAccent: true),
        systemAccent: 0xFF112233,
      );
      addTearDown(cubit.close);

      expect(
        cubit.state.resolvedLight.accentColor.normal,
        const Color(0xFF112233),
      );
    });

    test(
      'смена акцента в системе применяется сразу (macOS, Windows)',
      () async {
        final cubit = build(
          settings: const AppAppearanceSettings(systemAccent: true),
          systemAccent: 0xFF112233,
        );
        addTearDown(cubit.close);
        await _pump();

        accent.emit(0xFF445566);
        await _pump();

        expect(
          cubit.state.resolvedDark.accentColor.normal,
          const Color(0xFF445566),
        );
      },
    );

    test('ошибка потока: accent темы и appearance.system_accent_failed без '
        'текста ошибки', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(systemAccent: true),
        systemAccent: 0xFF112233,
      );
      addTearDown(cubit.close);
      await _pump();

      accent.emitError(StateError('channel secret'));
      await _pump();

      expect(
        cubit.state.resolvedDark.accentColor.normal,
        isNot(const Color(0xFF112233)),
      );
      final failed = logger.entries.singleWhere(
        (e) => e['event'] == 'appearance.system_accent_failed',
      );
      expect(failed['level'], 'warning');
      expect(failed['error_class'], 'StateError');
      expect(
        failed.values.whereType<String>().join(),
        isNot(contains('secret')),
      );
    });

    test('ошибка чтения при включении: accent темы, событие, переключатель '
        'остаётся выбором пользователя', () async {
      accent.readError = StateError('no channel');
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.setSystemAccent(true);

      expect(cubit.state.systemAccent, isTrue);
      expect(
        cubit.state.resolvedDark.accentColor.normal,
        isNot(const Color(0xFFFF2D55)),
      );
      expect(
        logger.entries.where(
          (e) => e['event'] == 'appearance.system_accent_failed',
        ),
        hasLength(1),
      );
    });

    test('«Linux без уведомлений»: refreshSystemAccent — одно чтение и новый '
        'цвет', () async {
      accent.accent = 0xFF112233;
      final cubit = build(
        settings: const AppAppearanceSettings(systemAccent: true),
        systemAccent: 0xFF112233,
      );
      addTearDown(cubit.close);
      accent.accent = 0xFFAABBCC;
      final before = accent.readCount;

      await cubit.refreshSystemAccent();

      expect(accent.readCount, before + 1);
      expect(
        cubit.state.resolvedDark.accentColor.normal,
        const Color(0xFFAABBCC),
      );
    });

    test('при выключенном переключателе refreshSystemAccent не меняет '
        'accentColor', () async {
      final cubit = build();
      addTearDown(cubit.close);
      final before = cubit.state.resolvedDark.accentColor.normal;

      await cubit.refreshSystemAccent();

      expect(cubit.state.resolvedDark.accentColor.normal, before);
    });

    test('без поддержки порта поток не слушается', () async {
      final cubit = build(supported: false);
      addTearDown(cubit.close);
      await _pump();

      expect(accent.listening, isFalse);
      expect(cubit.state.systemAccentSupported, isFalse);
    });
  });

  group('запись (spec «Сбой записи», D13)', () {
    test(
      'сбой записи: выбор остаётся, saveFailed, событие без текста',
      () async {
        preferences
          ..autoComplete = false
          ..failWith = null;
        final cubit = build();
        addTearDown(cubit.close);

        final done = cubit.setMode(AppearanceMode.dark);
        expect(cubit.state.mode, AppearanceMode.dark, reason: 'emit до записи');
        preferences.complete(0, StateError('disk full'));
        await done;

        expect(cubit.state.mode, AppearanceMode.dark);
        expect(cubit.state.saveFailed, isTrue);
        final failed = logger.entries.singleWhere(
          (e) => e['event'] == 'appearance.save_failed',
        );
        expect(failed['error_class'], 'StateError');
        expect(
          failed.values.whereType<String>().join(),
          isNot(contains('disk')),
        );
      },
    );

    test(
      'Retry повторяет запись текущего выбора и снимает saveFailed',
      () async {
        preferences.autoComplete = false;
        final cubit = build();
        addTearDown(cubit.close);
        final first = cubit.setMode(AppearanceMode.dark);
        preferences.complete(0, StateError('x'));
        await first;
        expect(cubit.state.saveFailed, isTrue);

        final retry = cubit.retrySave();
        preferences.complete(1);
        await retry;

        expect(preferences.saves.last.mode, AppearanceMode.dark);
        expect(cubit.state.saveFailed, isFalse);
      },
    );

    test('три выбора подряд: сохранён последний, обогнанная запись состояние '
        'не публикует', () async {
      preferences.autoComplete = false;
      final cubit = build();
      addTearDown(cubit.close);
      final states = <AppAppearanceState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      final all = Future.wait([
        cubit.setMode(AppearanceMode.dark),
        cubit.setMode(AppearanceMode.light),
        cubit.setMode(AppearanceMode.system),
      ]);
      expect(cubit.state.mode, AppearanceMode.system);

      // Первая запись падает позже выбора: на состояние влиять не должна.
      preferences.complete(0, StateError('late failure'));
      await _pump();
      preferences.complete(1);
      await _pump();
      preferences.complete(2);
      await all;
      await _pump();

      expect(preferences.saves.last.mode, AppearanceMode.system);
      expect(cubit.state.mode, AppearanceMode.system);
      expect(cubit.state.saveFailed, isFalse);
      expect(states.every((s) => !s.saveFailed), isTrue);
    });
  });

  group('Reload (spec «Reload применяет исправленный файл»)', () {
    test('исправленный файл применяется без перезапуска', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        darkTheme: _loaded('acme-night', night),
      );
      addTearDown(cubit.close);
      library.files['acme-night'] = _theme('acme-night', accent: '#112233');

      await cubit.reloadTheme('acme-night');

      expect(
        cubit.state.resolvedDark.accentColor.normal,
        const Color(0xFF112233),
      );
      expect(cubit.state.fallback, AppearanceFallback.none);
    });

    test('файл удалён или испорчен: встроенная тема режима и fallback, выбор '
        'не перезаписан', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        darkTheme: _loaded('acme-night', night),
      );
      addTearDown(cubit.close);
      library.files.remove('acme-night');

      await cubit.reloadTheme('acme-night');

      expect(cubit.state.darkTheme, 'acme-night');
      expect(cubit.state.fallback, AppearanceFallback.dark);
      expect(_success(cubit.state.resolvedDark), isNot(customGreen));
      expect(preferences.saves, isEmpty);
    });

    test('Reload темы, не назначенной режиму, ничего не меняет', () async {
      final cubit = build();
      addTearDown(cubit.close);
      final before = cubit.state.resolvedDark;

      await cubit.reloadTheme('acme-night');

      expect(identical(cubit.state.resolvedDark, before), isTrue);
    });

    test(
      'поздний reloadTheme после useTheme того же режима отброшен',
      () async {
        final gated = _GatedLibrary(library);
        final cubit = build(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
          darkTheme: _loaded('acme-night', night),
          themes: gated,
        );
        addTearDown(cubit.close);
        library.files['acme-night'] = _theme('acme-night', accent: '#112233');

        final reload = cubit.reloadTheme('acme-night');
        await _pump();
        // Пользователь возвращает встроенную тему того же режима.
        await cubit.useTheme('dark');
        expect(cubit.state.darkTheme, 'dark');

        for (final gate in gated.gates) {
          gate.complete();
        }
        await reload;

        expect(cubit.state.darkTheme, 'dark');
        expect(_success(cubit.state.resolvedDark), isNot(customGreen));
        expect(
          cubit.state.resolvedDark.accentColor.normal,
          isNot(const Color(0xFF112233)),
        );
      },
    );

    test(
      'поздний результат первого reloadTheme после второго отброшен',
      () async {
        final gated = _GatedLibrary(library);
        final cubit = build(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
          darkTheme: _loaded('acme-night', night),
          themes: gated,
        );
        addTearDown(cubit.close);

        library.files['acme-night'] = _theme('acme-night', accent: '#111111');
        final first = cubit.reloadTheme('acme-night');
        await _pump();
        library.files['acme-night'] = _theme('acme-night', accent: '#222222');
        final second = cubit.reloadTheme('acme-night');
        await _pump();

        // Вторая операция завершается раньше первой.
        gated.gates[1].complete();
        await second;
        gated.gates[0].complete();
        await first;

        expect(
          cubit.state.resolvedDark.accentColor.normal,
          const Color(0xFF222222),
        );
      },
    );
  });

  group('close (D13, concurrency §47б)', () {
    test('ждёт идущую запись, но не дольше срока', () async {
      preferences.autoComplete = false;
      final cubit = build();
      unawaited(cubit.setMode(AppearanceMode.dark));
      final stopwatch = Stopwatch()..start();

      await cubit.close();

      // Срок теста — 50 мс; запись не завершена, закрытие не зависло.
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 40)),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(cubit.isClosed, isTrue);
    });

    test(
      'идущая запись, завершённая до срока, не задерживает закрытие',
      () async {
        preferences.autoComplete = false;
        final cubit = build();
        unawaited(cubit.setMode(AppearanceMode.dark));
        final closing = cubit.close();
        preferences.complete(0);

        await closing;

        expect(cubit.isClosed, isTrue);
      },
    );

    test('после close состояние не публикуется поздней записью', () async {
      preferences.autoComplete = false;
      final cubit = build();
      final done = cubit.setMode(AppearanceMode.dark);
      final closing = cubit.close();
      preferences.complete(0, StateError('after close'));
      await closing;
      await done;

      expect(cubit.state.saveFailed, isFalse);
    });

    test('отменяет подписку на системный акцент', () async {
      final cubit = build(
        settings: const AppAppearanceSettings(systemAccent: true),
        systemAccent: 0xFF112233,
      );
      await _pump();
      expect(accent.listening, isTrue);

      await cubit.close();

      expect(accent.listening, isFalse);
    });
  });

  group('события журнала (spec «События журнала оформления», D12)', () {
    Iterable<Map<String, Object?>> events(String name) =>
        logger.entries.where((e) => e['event'] == name);

    test('settings.appearance_changed: field и новое значение', () async {
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.setMode(AppearanceMode.dark);
      await cubit.setSystemAccent(true);

      final changed = events('settings.appearance_changed').toList();
      expect(changed.map((e) => e['field']), ['mode', 'system_accent']);
      expect(changed.first['value'], 'dark');
      expect(changed.last['value'], true);
    });

    test(
      '«Журнал без имени пользовательской темы»: custom вместо имени',
      () async {
        final cubit = build(
          settings: const AppAppearanceSettings(mode: AppearanceMode.dark),
        );
        addTearDown(cubit.close);

        await cubit.useTheme('acme-night');
        await cubit.useTheme('high-contrast');

        final changed = events(
          'settings.appearance_changed',
        ).where((e) => e['field'] == 'dark_theme').toList();
        expect(changed.map((e) => e['value']), ['custom', 'high-contrast']);
        final loaded = events('appearance.theme_loaded').single;
        expect(loaded['theme'], 'custom');
        expect(loaded['extends'], 'dark');
        expect(loaded['warnings'], 0);
        expect(
          logger.entries.map((e) => e.values.join(' ')).join('\n'),
          isNot(contains('acme-night')),
        );
      },
    );

    test(
      'appearance.theme_loaded: число предупреждений и коды без ключей',
      () async {
        library.files['acme-night'] = _theme(
          'acme-night',
          extra: {'acent': '#ffffff'},
        );
        final cubit = build();
        addTearDown(cubit.close);

        await cubit.useTheme('acme-night');

        final loaded = events('appearance.theme_loaded').single;
        expect(loaded['warnings'], 1);
        expect(loaded['codes'], ['unknownKey']);
        expect(loaded.values.join(' '), isNot(contains('acent')));
      },
    );

    test(
      'appearance.theme_invalid: код и позиция без имени и текста',
      () async {
        library.files['broken'] = '{';
        final cubit = build();
        addTearDown(cubit.close);

        await cubit.useTheme('broken');

        final invalid = events('appearance.theme_invalid').single;
        expect(invalid['theme'], 'custom');
        expect(invalid['code'], 'invalidJson');
        expect(invalid, containsPair('line', isA<int>()));
        expect(invalid, containsPair('column', isA<int>()));
        expect(invalid.values.join(' '), isNot(contains('broken')));
      },
    );
  });
}
