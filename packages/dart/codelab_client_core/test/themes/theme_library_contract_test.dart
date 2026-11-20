// Красный тест 1.5 change `add-app-appearance-page`: контракт порта
// `ThemeLibrary` на `InMemoryThemeLibrary` (spec `client-themes`, «Каталог
// пользовательских тем» и «Импорт файла темы»). Реализация — задача 1.6.
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _acme = '{\n  "name": "acme-night",\n  "extends": "dark"\n}\n';
const _acmeV2 = '{\n  "name": "acme-night",\n  "extends": "light"\n}\n';

void main() {
  group('list: каталог', () {
    test('пустой каталог — пустой список без ошибки', () async {
      expect(await InMemoryThemeLibrary().list(), isEmpty);
    });

    test('записи идут по алфавиту имени, а не в порядке добавления', () async {
      final library = InMemoryThemeLibrary(
        themes: {'beta': '{}', 'alpha': '{}', 'gamma': '{}'},
      );
      expect((await library.list()).map((e) => e.name), [
        'alpha',
        'beta',
        'gamma',
      ]);
    });

    test('запись несёт текст файла без изменений', () async {
      final library = InMemoryThemeLibrary(themes: {'acme-night': _acme});
      final entry = (await library.list()).single;
      expect(entry.text, _acme);
      expect(entry.error, isNull);
    });

    test('запись с ошибкой чтения остаётся в списке, исключения нет', () async {
      final library = InMemoryThemeLibrary(
        themes: {'ok': '{}'},
        broken: {
          'big': ThemeReadError.tooLarge,
          'dead': ThemeReadError.unreadable,
        },
      );
      final entries = await library.list();
      expect(entries.map((e) => e.name), ['big', 'dead', 'ok']);
      expect(entries[0].error, ThemeReadError.tooLarge);
      expect(entries[0].text, isNull);
      expect(entries[1].error, ThemeReadError.unreadable);
      expect(entries[2].error, isNull);
    });
  });

  group('сбой каталога', () {
    test('list бросает ThemeCatalogException с причиной, без путей', () async {
      final library = InMemoryThemeLibrary(themes: {'a': '{}'})
        ..catalogFailure = ThemeCatalogFailure.notADirectory;
      await expectLater(
        library.list(),
        throwsA(
          isA<ThemeCatalogException>().having(
            (e) => e.failure,
            'failure',
            ThemeCatalogFailure.notADirectory,
          ),
        ),
      );
      library.catalogFailure = null;
      expect(await library.list(), hasLength(1));
      expect(
        const ThemeCatalogException(ThemeCatalogFailure.unreadable).toString(),
        isNot(contains('/')),
      );
    });
  });

  group('import: expectedName', () {
    test('replace с другим name в файле — sourceChanged, без записи', () async {
      final library = InMemoryThemeLibrary(
        themes: {'acme-night': _acme, 'other': '{"name": "other"}'},
        sources: {'/s.json': '{"name": "other", "extends": "light"}'},
      );
      final result = await library.import(
        '/s.json',
        replace: true,
        expectedName: 'acme-night',
      );
      expect(result, isA<ThemeImportSourceChanged>());
      expect((result as ThemeImportSourceChanged).name, 'other');
      expect(library.files['other'], '{"name": "other"}');
      expect(library.files['acme-night'], _acme);
    });

    test('replace с тем же name — заменяет', () async {
      final library = InMemoryThemeLibrary(
        themes: {'acme-night': _acme},
        sources: {'/s.json': _acmeV2},
      );
      expect(
        await library.import(
          '/s.json',
          replace: true,
          expectedName: 'acme-night',
        ),
        isA<ThemeImportReplaced>(),
      );
    });

    test('без replace expectedName не учитывается', () async {
      final library = InMemoryThemeLibrary(sources: {'/s.json': _acme});
      expect(
        await library.import('/s.json', expectedName: 'zzz'),
        isA<ThemeImportImported>(),
      );
    });
  });

  group('read: одна тема', () {
    test('есть файл — запись с текстом', () async {
      final library = InMemoryThemeLibrary(themes: {'acme-night': _acme});
      final entry = await library.read('acme-night');
      expect(entry!.name, 'acme-night');
      expect(entry.text, _acme);
      expect(entry.error, isNull);
    });

    test('нет файла — null', () async {
      expect(await InMemoryThemeLibrary().read('absent'), isNull);
    });

    test('ошибка чтения — запись с error, как в list', () async {
      final library = InMemoryThemeLibrary(
        broken: {'big': ThemeReadError.tooLarge},
      );
      final entry = await library.read('big');
      expect(entry!.error, ThemeReadError.tooLarge);
      expect(entry.text, isNull);
    });

    test('недопустимое имя — null', () async {
      final library = InMemoryThemeLibrary(themes: {'../x': '{}', 'A': '{}'});
      for (final name in ['../x', 'A', '', 'a/b', 'a' * 33]) {
        expect(await library.read(name), isNull, reason: name);
      }
    });
  });

  group('import: результаты', () {
    test(
      'imported: новая тема записана байт в байт под именем из name',
      () async {
        final library = InMemoryThemeLibrary(
          sources: {'/home/u/Downloads/Acme Night.json': _acme},
        );
        final result = await library.import(
          '/home/u/Downloads/Acme Night.json',
        );
        expect(result, isA<ThemeImportImported>());
        expect((result as ThemeImportImported).name, 'acme-night');
        expect(library.files, {'acme-night': _acme});
      },
    );

    test(
      'путь назначения зависит только от name, не от имени источника',
      () async {
        final library = InMemoryThemeLibrary(
          sources: {'../x.json': _acme, '/tmp/a b/..%2Fy.json': _acmeV2},
        );
        await library.import('../x.json');
        expect(library.files.keys, ['acme-night']);
      },
    );

    test('invalid: битый файл не копируется, код проблемы доступен', () async {
      final library = InMemoryThemeLibrary(
        sources: {
          '/src/bad.json': '{"name": "bad", "colors": {"accent": "#zz0000"}}',
        },
      );
      final result = await library.import('/src/bad.json');
      expect(result, isA<ThemeImportInvalid>());
      expect(
        (result as ThemeImportInvalid).issue.code,
        ThemeIssueCode.invalidValue,
      );
      expect(library.files, isEmpty);
    });

    test('invalid: имя файла-источника с name не сверяется', () async {
      // `Acme Night.json` и `name: acme-night` — не nameMismatch.
      final library = InMemoryThemeLibrary(sources: {'Acme Night.json': _acme});
      expect(
        await library.import('Acme Night.json'),
        isA<ThemeImportImported>(),
      );
    });

    test('invalid: зарезервированное имя встроенной темы', () async {
      final library = InMemoryThemeLibrary(
        sources: {'/src/dark.json': '{"name": "dark"}'},
      );
      final result = await library.import('/src/dark.json');
      expect(
        (result as ThemeImportInvalid).issue.code,
        ThemeIssueCode.reservedName,
      );
      expect(library.files, isEmpty);
    });

    test('invalid: name с путём не даёт записи вне каталога', () async {
      final library = InMemoryThemeLibrary(
        sources: {'/src/e.json': '{"name": "../evil"}'},
      );
      final result = await library.import('/src/e.json');
      expect(result, isA<ThemeImportInvalid>());
      expect(library.files, isEmpty);
    });

    test(
      'needsReplace: другое содержимое — без записи без подтверждения',
      () async {
        final library = InMemoryThemeLibrary(
          themes: {'acme-night': _acme},
          sources: {'/src/new.json': _acmeV2},
        );
        final result = await library.import('/src/new.json');
        expect(result, isA<ThemeImportNeedsReplace>());
        expect((result as ThemeImportNeedsReplace).name, 'acme-night');
        expect(library.files['acme-night'], _acme);
      },
    );

    test('replaced: replace: true заменяет файл целиком', () async {
      final library = InMemoryThemeLibrary(
        themes: {'acme-night': _acme},
        sources: {'/src/new.json': _acmeV2},
      );
      final result = await library.import('/src/new.json', replace: true);
      expect(result, isA<ThemeImportReplaced>());
      expect((result as ThemeImportReplaced).name, 'acme-night');
      expect(library.files['acme-night'], _acmeV2);
    });

    test('unchanged: то же содержимое — без записи, с replace и без', () async {
      final library = InMemoryThemeLibrary(
        themes: {'acme-night': _acme},
        sources: {'/src/same.json': _acme},
      );
      expect(
        await library.import('/src/same.json'),
        isA<ThemeImportUnchanged>(),
      );
      expect(
        await library.import('/src/same.json', replace: true),
        isA<ThemeImportUnchanged>(),
      );
      expect(library.files, {'acme-night': _acme});
    });

    test('replace: true без существующего файла — просто imported', () async {
      final library = InMemoryThemeLibrary(sources: {'/src/a.json': _acme});
      expect(
        await library.import('/src/a.json', replace: true),
        isA<ThemeImportImported>(),
      );
    });

    test('failed: источник не прочитан — исключения нет, записи нет', () async {
      final library = InMemoryThemeLibrary();
      expect(await library.import('/nope.json'), isA<ThemeImportFailed>());
      expect(library.files, isEmpty);
    });

    test('после импорта тема видна в list в алфавитном порядке', () async {
      final library = InMemoryThemeLibrary(
        themes: {'zeta': '{}', 'alpha': '{}'},
        sources: {'/src/a.json': _acme},
      );
      await library.import('/src/a.json');
      expect((await library.list()).map((e) => e.name), [
        'acme-night',
        'alpha',
        'zeta',
      ]);
    });
  });
}
