// Красные тесты AppearanceSettingsCubit (задача 5.3 change
// `add-app-appearance-page`; design.md D8, D9, D11, D12, D13; spec
// app-settings «Карточки тем и превью», «Пользовательские темы на странице
// «Appearance»», «Импорт темы на странице «Appearance»», «Контраст на фоне
// кода», «События журнала оформления»).
//
// Cubit — временное состояние страницы: каталог, выбранная для превью карточка,
// диалог замены. Применяет тему только «Use» и «Reset» через
// `AppAppearanceCubit`; выбор карточки и импорт тему не применяют.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_cubit.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:codelab_desktop/core/platform/system_accent_source.dart';
import 'package:codelab_desktop/features/settings/application/appearance_settings_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_theme_file_picker.dart';
import '../../../support/recording_logger.dart';

/// Хранилище оформления в памяти: записи не нужны, нужен только порт.
final class _MemoryPreferences implements AppAppearancePreferences {
  @override
  Future<AppAppearanceLoad> load() async =>
      const AppAppearanceLoad(AppAppearanceSettings());

  @override
  Future<void> save(AppAppearanceSettings settings) async {}
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
  Future<ThemeEntry?> read(String name) => _inner.read(name);

  @override
  Future<ThemeImportResult> import(String sourcePath, {bool replace = false}) =>
      _inner.import(sourcePath, replace: replace);
}

/// Файл темы из артборда: ключи `acent` (строка 6) и `tab_bg` (строка 9).
const _twoWarnings = '''{
  "name": "acme-night",
  "extends": "dark",
  "colors": {
    "accent": "#b4a0ff",
    "acent": "#b4a0ff",
    "success": "#a6e3a1",
    "error": "#f38ba8",
    "tab_bg": "#1b1830",
    "code": { "keyword": "#ff79c6", "string": "#a6e3a1",
      "type": "#89b4fa", "comment": "#c0c4d8" }
  }
}''';

String _theme(String name, {String base = 'dark', String accent = '#b4a0ff'}) =>
    jsonEncode({
      'name': name,
      'extends': base,
      'colors': {'accent': accent},
    });

const _lowContrast = '''{
  "name": "dim",
  "extends": "dark",
  "colors": { "code": { "background": "#14121f", "comment": "#3a3650" } }
}''';

const _themesDirectory = '/home/user/.codelab/themes';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late InMemoryThemeLibrary library;
  late FakeThemeFilePicker picker;
  late FakeLocalFolderOpener opener;
  late RecordingLogger logger;
  late AppAppearanceCubit appearance;

  AppearanceSettingsCubit build({
    ThemeLibrary? themes,
    Brightness system = Brightness.dark,
    String? directory = _themesDirectory,
  }) {
    final cubit = AppearanceSettingsCubit(
      library: themes ?? library,
      appearance: appearance,
      picker: picker,
      folderOpener: opener,
      systemBrightness: () => system,
      themesDirectory: directory,
      logger: logger,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  AppAppearanceCubit buildAppearance({
    AppAppearanceSettings settings = const AppAppearanceSettings(),
    ThemeLoaded? dark,
    ThemeLibrary? themes,
  }) {
    final cubit = AppAppearanceCubit(
      preferences: _MemoryPreferences(),
      library: themes ?? library,
      accentSource: const UnsupportedSystemAccentSource(),
      start: AppAppearanceStart(settings: settings, darkTheme: dark),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  setUp(() {
    library = InMemoryThemeLibrary(
      themes: {'acme-night': _twoWarnings, 'dim': _lowContrast},
      broken: {'huge': ThemeReadError.tooLarge},
    );
    picker = FakeThemeFilePicker();
    opener = FakeLocalFolderOpener();
    logger = RecordingLogger();
    appearance = buildAppearance();
  });

  group('каталог и карточки', () {
    test('до load() каталог читается, после — готов', () async {
      final cubit = build();

      expect(cubit.state.loading, isTrue);
      await cubit.load();

      expect(cubit.state.loading, isFalse);
    });

    test('сначала встроенные light, dark, high-contrast, затем '
        'пользовательские в порядке каталога', () async {
      final cubit = build();

      await cubit.load();

      expect(cubit.state.cards.map((c) => c.id), [
        'light',
        'dark',
        'high-contrast',
        'acme-night',
        'dim',
        'huge',
      ]);
      expect(cubit.state.cards.take(3).map((c) => c.kind), [
        AppearanceThemeKind.builtInDefault,
        AppearanceThemeKind.builtInDefault,
        AppearanceThemeKind.builtIn,
      ]);
      expect(
        cubit.state.cards.skip(3).map((c) => c.kind),
        everyElement(AppearanceThemeKind.custom),
      );
    });

    test('режим карточки: light — светлый, dark и high-contrast — тёмный, '
        'пользовательская — по extends, не загрузившаяся — null', () async {
      library.files['acme-day'] = _theme('acme-day', base: 'light');
      final cubit = build();

      await cubit.load();

      Brightness? mode(String id) =>
          cubit.state.cards.singleWhere((c) => c.id == id).mode;
      expect(mode('light'), Brightness.light);
      expect(mode('dark'), Brightness.dark);
      expect(mode('high-contrast'), Brightness.dark);
      expect(mode('acme-night'), Brightness.dark);
      expect(mode('acme-day'), Brightness.light);
      expect(mode('huge'), isNull);
    });

    test('«Выбор по умолчанию — действующая тема»: Match system и светлая '
        'система → light', () async {
      final cubit = build(system: Brightness.light);

      await cubit.load();

      expect(cubit.state.selectedId, 'light');
    });

    test(
      'фиксированный Dark и назначенная acme-night → выбрана acme-night',
      () async {
        appearance = buildAppearance(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
          dark: ThemeFile.parse('acme-night.json', _twoWarnings) as ThemeLoaded,
        );
        final cubit = build();

        await cubit.load();

        expect(cubit.state.selectedId, 'acme-night');
        expect(cubit.state.selection?.card.id, 'acme-night');
      },
    );

    test('«Выбор карточки не применяет тему»: превью меняется, '
        'оформление app — нет', () async {
      final cubit = build();
      await cubit.load();

      await cubit.select('acme-night');

      expect(cubit.state.selectedId, 'acme-night');
      expect(appearance.state.darkTheme, 'dark');
      expect(appearance.state.lightTheme, 'light');
      expect(appearance.state.mode, AppearanceMode.system);
    });

    test('выбор встроенной темы даёт карточку без текста файла и без '
        'проблем', () async {
      final cubit = build();
      await cubit.load();

      await cubit.select('dark');

      final selection = cubit.state.selection!;
      expect(selection.card.id, 'dark');
      expect(selection.fileText, isNull);
      expect(selection.issues, isEmpty);
      expect(selection.error, isNull);
    });
  });

  group(
    'выбранная тема: проблемы (spec «Пользовательские темы на странице»)',
    () {
      test(
        '«Тема с двумя предупреждениями»: строки 6 и 9, коды, подсказка',
        () async {
          final cubit = build();
          await cubit.load();

          await cubit.select('acme-night');

          final selection = cubit.state.selection!;
          expect(selection.card.loaded, isTrue);
          expect(selection.card.parseWarnings, 2);
          expect(selection.card.warningCount, 2);
          expect(selection.fileText, _twoWarnings);
          expect(selection.warningLines, {6, 9});
          final issues = selection.issues
              .whereType<AppearanceParseIssue>()
              .map((i) => i.issue)
              .toList();
          expect(issues.map((i) => i.code), [
            ThemeIssueCode.unknownKey,
            ThemeIssueCode.unknownKey,
          ]);
          expect(issues.map((i) => (i.line, i.column)), [(6, 5), (9, 5)]);
          expect(issues.map((i) => i.key), ['acent', 'tab_bg']);
          expect(issues.first.hint, 'accent');
          expect(issues.last.hint, isNull);
        },
      );

      test(
        'справка о незаданных ролях без status_bg и approval_border',
        () async {
          final cubit = build();
          await cubit.load();

          await cubit.select('acme-night');

          final unset = cubit.state.selection!.unsetRoles;
          expect(
            unset,
            containsAll([
              ThemeRole.warning,
              ThemeRole.info,
              ThemeRole.selection,
              ThemeRole.codeNumber,
            ]),
          );
          expect(unset, isNot(contains(ThemeRole.statusBg)));
          expect(unset, isNot(contains(ThemeRole.approvalBorder)));
          expect(unset, isNot(contains(ThemeRole.accent)));
        },
      );

      test('тема с ошибкой: данные error, текст файла есть, справки о ролях '
          'нет, карточка не загрузилась', () async {
        library.files['broken'] = '{';
        final cubit = build();
        await cubit.load();

        await cubit.select('broken');

        final selection = cubit.state.selection!;
        expect(selection.card.loaded, isFalse);
        expect(selection.card.theme, isNull);
        expect(selection.error?.code, ThemeIssueCode.invalidJson);
        expect(selection.fileText, '{');
        expect(selection.unsetRoles, isEmpty);
      });

      test('файл не прочитан: readError и нет текста', () async {
        final cubit = build();
        await cubit.load();

        await cubit.select('huge');

        final selection = cubit.state.selection!;
        expect(selection.card.loaded, isFalse);
        expect(selection.readError, ThemeReadError.tooLarge);
        expect(selection.fileText, isNull);
      });

      test('«Низкий контраст пользовательской роли»: бейдж и список '
          'учитывают контраст, роль применяется как задана', () async {
        final cubit = build();
        await cubit.load();

        await cubit.select('dim');

        final selection = cubit.state.selection!;
        expect(selection.card.parseWarnings, 0);
        expect(selection.card.lowContrast, 1);
        expect(selection.card.warningCount, 1);
        final low = selection.issues
            .whereType<AppearanceLowContrastIssue>()
            .single;
        expect(low.role, ThemeRole.codeComment);
        expect(low.ratio, lessThan(4.5));
        expect(
          selection.card.contrast
              .singleWhere((c) => c.role == ThemeRole.codeComment)
              .passes,
          isFalse,
        );
      });

      test('у встроенных тем предупреждений нет', () async {
        final cubit = build();
        await cubit.load();

        for (final card in cubit.state.cards.take(3)) {
          expect(card.warningCount, 0, reason: card.id);
        }
      });
    },
  );

  group('чтение каталога (spec «Поздний результат чтения»)', () {
    test('поздний результат первого чтения после Reload отброшен, событие '
        'appearance.catalog_discarded', () async {
      final gated = _GatedLibrary(library);
      final cubit = build(themes: gated);

      final first = cubit.load();
      await _pump();
      library.files['late'] = _theme('late');
      final second = cubit.reload();
      await _pump();

      gated.gates[1].complete();
      await second;
      gated.gates[0].complete();
      await first;

      expect(cubit.state.cards.map((c) => c.id), contains('late'));
      final discarded = events('appearance.catalog_discarded').single;
      expect(discarded['reason'], 'reload');
    });

    test('результат после close() отброшен', () async {
      final gated = _GatedLibrary(library);
      final cubit = AppearanceSettingsCubit(
        library: gated,
        appearance: appearance,
        picker: picker,
        folderOpener: opener,
        systemBrightness: () => Brightness.dark,
        themesDirectory: _themesDirectory,
        logger: logger,
      );

      final loading = cubit.load();
      await _pump();
      await cubit.close();
      gated.gates.single.complete();
      await loading;

      expect(cubit.state.loading, isTrue);
      expect(events('appearance.catalog_discarded').single['reason'], 'closed');
    });

    test('пока каталог читается, встроенные карточки уже выбираются', () async {
      final gated = _GatedLibrary(library);
      final cubit = build(themes: gated);

      final loading = cubit.load();
      await _pump();
      await cubit.select('high-contrast');

      expect(cubit.state.loading, isTrue);
      expect(cubit.state.selectedId, 'high-contrast');
      expect(cubit.state.cards.map((c) => c.id), [
        'light',
        'dark',
        'high-contrast',
      ]);
      gated.gates.single.complete();
      await loading;
    });
  });

  group('«Reload»', () {
    test('перечитывает каталог', () async {
      final cubit = build();
      await cubit.load();
      library.files['new-one'] = _theme('new-one');

      await cubit.reload();

      expect(cubit.state.cards.map((c) => c.id), contains('new-one'));
    });

    test('выбранная назначенная тема применяется заново из файла '
        '(«Reload применяет исправленный файл»)', () async {
      appearance = buildAppearance(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        dark: ThemeFile.parse('acme-night.json', _twoWarnings) as ThemeLoaded,
      );
      final cubit = build();
      await cubit.load();
      library.files['acme-night'] = _theme('acme-night', accent: '#112233');

      await cubit.reload();

      expect(
        appearance.state.resolvedDark.accentColor.normal.toARGB32(),
        0xFF112233,
      );
    });
  });

  group('«Use» и «Reset»', () {
    test('Use у acme-night при Light: тёмная тема и режим Dark', () async {
      appearance = buildAppearance(
        settings: const AppAppearanceSettings(mode: AppearanceMode.light),
      );
      final cubit = build(system: Brightness.light);
      await cubit.load();
      await cubit.select('acme-night');

      await cubit.useSelected();

      expect(appearance.state.darkTheme, 'acme-night');
      expect(appearance.state.mode, AppearanceMode.dark);
    });

    test('Reset: тёмная тема возвращается к dark и выбирается карточка '
        '«Fluent Dark»', () async {
      appearance = buildAppearance(
        settings: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        dark: ThemeFile.parse('acme-night.json', _twoWarnings) as ThemeLoaded,
      );
      final cubit = build();
      await cubit.load();
      expect(cubit.state.selectedId, 'acme-night');

      await cubit.resetSelected();

      expect(appearance.state.darkTheme, 'dark');
      expect(cubit.state.selectedId, 'dark');
    });
  });

  group('импорт (spec «Импорт темы на странице «Appearance»»)', () {
    const source = '/Downloads/night.json';

    test('«Импорт и превью»: карточка появилась и выбрана, действующая тема '
        'не изменилась, событие imported без имени', () async {
      library.sources[source] = _theme('fresh');
      picker.next = source;
      final cubit = build();
      await cubit.load();

      await cubit.importJson();

      expect(cubit.state.cards.map((c) => c.id), contains('fresh'));
      expect(cubit.state.selectedId, 'fresh');
      expect(cubit.state.import.status, AppearanceImportStatus.idle);
      expect(appearance.state.darkTheme, 'dark');
      expect(appearance.state.lightTheme, 'light');
      final event = events('appearance.theme_imported').single;
      expect(event['outcome'], 'imported');
      expect(event.values.join(' '), isNot(contains('fresh')));
      expect(event.values.join(' '), isNot(contains('Downloads')));
    });

    test(
      'импорт темы с предупреждениями выбирает её с панелью проблем',
      () async {
        library.sources[source] = _twoWarnings.replaceAll('acme-night', 'twin');
        picker.next = source;
        final cubit = build();
        await cubit.load();

        await cubit.importJson();

        expect(cubit.state.selection?.card.id, 'twin');
        expect(cubit.state.selection?.warningLines, {6, 9});
      },
    );

    test(
      '«Отказ от замены»: нужна замена, файл не меняется до «Replace»',
      () async {
        library.sources[source] = _theme('acme-night', accent: '#111111');
        picker.next = source;
        final cubit = build();
        await cubit.load();

        await cubit.importJson();

        expect(cubit.state.import.status, AppearanceImportStatus.needsReplace);
        expect(cubit.state.import.name, 'acme-night');
        expect(library.files['acme-night'], _twoWarnings);

        cubit.cancelReplace();

        expect(cubit.state.import.status, AppearanceImportStatus.idle);
        expect(library.files['acme-night'], _twoWarnings);
      },
    );

    test('«Replace» заменяет файл и обновляет карточку', () async {
      final replacement = _theme('acme-night', accent: '#111111');
      library.sources[source] = replacement;
      picker.next = source;
      final cubit = build();
      await cubit.load();
      await cubit.importJson();

      await cubit.confirmReplace();

      expect(library.files['acme-night'], replacement);
      expect(cubit.state.import.status, AppearanceImportStatus.idle);
      expect(cubit.state.selectedId, 'acme-night');
      expect(events('appearance.theme_imported').last['outcome'], 'replaced');
    });

    test('тот же файл: unchanged — выбирается без записи', () async {
      library.sources[source] = _twoWarnings;
      picker.next = source;
      final cubit = build();
      await cubit.load();

      await cubit.importJson();

      expect(cubit.state.selectedId, 'acme-night');
      expect(cubit.state.import.status, AppearanceImportStatus.idle);
      expect(
        events('appearance.theme_imported').single['outcome'],
        'unchanged',
      );
    });

    test('invalid: ошибка разбора с позицией, файл не скопирован', () async {
      library.sources[source] = '{';
      picker.next = source;
      final cubit = build();
      await cubit.load();
      final before = Map.of(library.files);

      await cubit.importJson();

      expect(cubit.state.import.status, AppearanceImportStatus.failed);
      expect(cubit.state.import.issue?.code, ThemeIssueCode.invalidJson);
      expect(cubit.state.import.fileName, 'night.json');
      expect(cubit.state.import.writeFailed, isFalse);
      expect(library.files, before);
      expect(events('appearance.theme_imported').single['outcome'], 'invalid');
    });

    test('failed: ошибка записи без текста исключения', () async {
      // Источник не читается: библиотека отвечает `ThemeImportFailed`.
      picker.next = '/Downloads/missing.json';
      final cubit = build();
      await cubit.load();

      await cubit.importJson();

      expect(cubit.state.import.status, AppearanceImportStatus.failed);
      expect(cubit.state.import.writeFailed, isTrue);
      expect(cubit.state.import.issue, isNull);
      final event = events('appearance.theme_imported').single;
      expect(event['outcome'], 'failed');
      expect(event.values.join(' '), isNot(contains('missing.json')));
    });

    test('отмена диалога выбора файла ничего не меняет', () async {
      picker.next = null;
      final cubit = build();
      await cubit.load();
      final before = cubit.state;

      await cubit.importJson();

      expect(cubit.state.cards.length, before.cards.length);
      expect(cubit.state.selectedId, before.selectedId);
      expect(cubit.state.import.status, AppearanceImportStatus.idle);
      expect(
        events('appearance.theme_imported').single['outcome'],
        'cancelled',
      );
    });

    test('пока идёт импорт, повторный недоступен', () async {
      picker
        ..next = source
        ..gate = Completer<void>();
      library.sources[source] = _theme('fresh');
      final cubit = build();
      await cubit.load();

      final first = cubit.importJson();
      await _pump();
      expect(cubit.state.import.status, AppearanceImportStatus.importing);
      await cubit.importJson();

      expect(picker.calls, 1);
      picker.gate!.complete();
      await first;
      expect(cubit.state.import.status, AppearanceImportStatus.idle);
    });

    test('импорт после close() ничего не публикует', () async {
      picker
        ..next = source
        ..gate = Completer<void>();
      library.sources[source] = _theme('fresh');
      final cubit = build();
      await cubit.load();

      final importing = cubit.importJson();
      await _pump();
      await cubit.close();
      picker.gate!.complete();
      await importing;

      expect(library.files, isNot(contains('fresh')));
    });
  });

  group('«Open folder» (D11)', () {
    test(
      'открывает <home>/themes с create: true, файл не открывается',
      () async {
        final cubit = build();
        await cubit.load();

        await cubit.openFolder();

        expect(opener.calls, [(directory: _themesDirectory, create: true)]);
        expect(cubit.state.folder, FolderOpenOutcome.opened);
      },
    );

    test('отказ порта сохраняется в состоянии', () async {
      opener.outcome = FolderOpenOutcome.failed;
      final cubit = build();
      await cubit.load();

      await cubit.openFolder();

      expect(cubit.state.folder, FolderOpenOutcome.failed);
    });

    test('без пути каталога порт не вызывается', () async {
      final cubit = build(directory: null);
      await cubit.load();

      await cubit.openFolder();

      expect(opener.untouched, isTrue);
    });
  });
}
