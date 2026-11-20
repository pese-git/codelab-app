// Красный тест 2.1 change `add-app-appearance-page`: каталог тем на диске
// и импорт файла (spec `client-themes`, «Каталог пользовательских тем» и
// «Импорт файла темы»; design.md D2, D9). Реализация — задача 2.2.
import 'dart:convert';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _acme = '{\n  "name": "acme-night",\n  "extends": "dark"\n}\n';
const _acmeV2 = '{\n  "name": "acme-night",\n  "extends": "light"\n}\n';

void main() {
  late Directory tmp;
  late String home;
  late String themes;
  late IoThemeLibrary library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('codelab_themes_');
    home = p.join(tmp.path, 'home');
    themes = p.join(home, 'themes');
    await Directory(home).create();
    library = IoThemeLibrary(home: home);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> writeTheme(String file, String text) async {
    final target = File(p.join(themes, file));
    await target.parent.create(recursive: true);
    await target.writeAsString(text);
  }

  Future<String> source(String relative, String text) async {
    final file = File(p.join(tmp.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    return file.path;
  }

  List<String> themeFileNames() =>
      Directory(themes).listSync().map((e) => p.basename(e.path)).toList()
        ..sort();

  group('«Каталог пользовательских тем»', () {
    test('«Нет каталога тем»: пустой список, каталог не создаётся', () async {
      expect(await library.list(), isEmpty);
      expect(Directory(themes).existsSync(), isFalse);
    });

    test('пустой каталог — пустой список', () async {
      await Directory(themes).create();
      expect(await library.list(), isEmpty);
    });

    test('только *.json прямо в каталоге, по алфавиту имени', () async {
      await writeTheme('beta.json', '{}');
      await writeTheme('alpha.json', _acme);
      await writeTheme('gamma.json', '{}');
      await writeTheme('notes.txt', 'не тема');
      await writeTheme('theme.json.bak', '{}');
      await writeTheme('nested/inner.json', '{}'); // подкаталог не обходится

      final entries = await library.list();
      expect(entries.map((e) => e.name), ['alpha', 'beta', 'gamma']);
      expect(entries.first.text, _acme);
      expect(entries.first.error, isNull);
    });

    test('подкаталог без .json в имени не перечисляется', () async {
      await Directory(p.join(themes, 'sub')).create(recursive: true);
      await writeTheme('ok.json', '{}');
      expect((await library.list()).map((e) => e.name), ['ok']);
    });

    test('текст читается как есть, кириллица без искажений', () async {
      const text = '{"name": "ru", "note": "тёмная"}';
      await writeTheme('ru.json', text);
      expect((await library.list()).single.text, text);
    });

    test(
      '«Большой файл»: 100 КиБ — запись с tooLarge, не исключение',
      () async {
        await writeTheme('big.json', 'x' * (100 * 1024));
        await writeTheme('small.json', '{}');
        final entries = await library.list();
        expect(entries.map((e) => e.name), ['big', 'small']);
        expect(entries.first.error, ThemeReadError.tooLarge);
        expect(entries.first.text, isNull);
        expect(entries.last.error, isNull);
      },
    );

    test('граница: ровно 64 КиБ читается, на байт больше — tooLarge', () async {
      await writeTheme('edge.json', 'x' * themeFileMaxBytes);
      await writeTheme('over.json', 'x' * (themeFileMaxBytes + 1));
      final byName = {for (final e in await library.list()) e.name: e};
      expect(byName['edge']!.error, isNull);
      expect(byName['edge']!.text, hasLength(themeFileMaxBytes));
      expect(byName['over']!.error, ThemeReadError.tooLarge);
    });

    test(
      'читается не больше 64 КиБ + 1 байта: бесконечный файл не виснет',
      () async {
        // `/dev/zero` не кончается: чтение «целиком» не завершилось бы.
        await Directory(themes).create(recursive: true);
        await Link(p.join(themes, 'zero.json')).create('/dev/zero');
        final entry = (await library.list()).single;
        expect(entry.name, 'zero');
        expect(entry.error, ThemeReadError.tooLarge);
      },
      testOn: '!windows',
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('не UTF-8 — запись с notUtf8', () async {
      await Directory(themes).create(recursive: true);
      await File(p.join(themes, 'latin.json')).writeAsBytes([
        ...utf8.encode('{"name": "x", "v": "'),
        0xff,
        0x22,
        0x7d,
      ]);
      expect((await library.list()).single.error, ThemeReadError.notUtf8);
    });

    test('ссылка на обычный файл читается как файл', () async {
      final target = await source('elsewhere/real.json', _acme);
      await Directory(themes).create(recursive: true);
      await Link(p.join(themes, 'linked.json')).create(target);
      final entry = (await library.list()).single;
      expect(entry.name, 'linked');
      expect(entry.text, _acme);
      expect(entry.error, isNull);
    });

    test(
      'ссылка в никуда — запись с ошибкой чтения, перечисление живо',
      () async {
        await Directory(themes).create(recursive: true);
        await Link(
          p.join(themes, 'dangling.json'),
        ).create(p.join(tmp.path, 'missing.json'));
        await writeTheme('ok.json', '{}');
        final entries = await library.list();
        expect(entries.map((e) => e.name), ['dangling', 'ok']);
        expect(entries.first.error, ThemeReadError.unreadable);
        expect(entries.first.text, isNull);
      },
    );

    test('каталог с именем *.json — запись с ошибкой чтения', () async {
      await Directory(p.join(themes, 'folder.json')).create(recursive: true);
      final entry = (await library.list()).single;
      expect(entry.name, 'folder');
      expect(entry.error, ThemeReadError.unreadable);
    });

    test('чтение каталога ничего не создаёт и не меняет', () async {
      await writeTheme('a.json', _acme);
      await library.list();
      expect(themeFileNames(), ['a.json']);
    });
  });

  group('read: одна тема', () {
    test('есть файл — запись с текстом, без перечисления каталога', () async {
      await writeTheme('acme-night.json', _acme);
      await writeTheme('other.json', '{}');
      final entry = await library.read('acme-night');
      expect(entry!.name, 'acme-night');
      expect(entry.text, _acme);
    });

    test('нет файла и нет каталога тем — null, каталог не создан', () async {
      expect(await library.read('absent'), isNull);
      expect(Directory(themes).existsSync(), isFalse);
      await writeTheme('x.json', '{}');
      expect(await library.read('absent'), isNull);
    });

    test('большой файл — tooLarge, не UTF-8 — notUtf8', () async {
      await writeTheme('big.json', 'x' * (100 * 1024));
      await File(
        p.join(themes, 'latin.json'),
      ).writeAsBytes([...utf8.encode('{"v": "'), 0xff, 0x22, 0x7d]);
      expect((await library.read('big'))!.error, ThemeReadError.tooLarge);
      expect((await library.read('latin'))!.error, ThemeReadError.notUtf8);
    });

    test('битая ссылка и каталог с именем *.json — unreadable', () async {
      await Directory(themes).create(recursive: true);
      await Link(
        p.join(themes, 'dangling.json'),
      ).create(p.join(tmp.path, 'missing.json'));
      await Directory(p.join(themes, 'folder.json')).create();
      expect(
        (await library.read('dangling'))!.error,
        ThemeReadError.unreadable,
      );
      expect((await library.read('folder'))!.error, ThemeReadError.unreadable);
    });

    test('недопустимое имя — null и файл вне каталога не читается', () async {
      await source('secret.json', '{"name": "secret"}');
      await writeTheme('ok.json', '{}');
      for (final name in [
        '../../secret',
        '../secret',
        'a/b',
        'A',
        '',
        '.',
        'a' * 33,
      ]) {
        expect(await library.read(name), isNull, reason: name);
      }
    });
  });

  group('«Импорт файла темы»', () {
    test(
      '«Импорт новой темы»: файл копируется байт в байт, каталог создан',
      () async {
        final path = await source('Downloads/Acme Night.json', _acme);
        expect(Directory(themes).existsSync(), isFalse);

        final result = await library.import(path);

        expect(result, isA<ThemeImportImported>());
        expect((result as ThemeImportImported).name, 'acme-night');
        final target = File(p.join(themes, 'acme-night.json'));
        expect(await target.readAsString(), _acme);
        expect(themeFileNames(), ['acme-night.json']);
        expect((await library.list()).single.name, 'acme-night');
      },
    );

    test(
      'содержимое копируется байт в байт: CRLF, BOM-подобные и Unicode',
      () async {
        final bytes = utf8.encode(
          '{\r\n  "name": "acme-night",\r\n  "note": "тёмная \u{1F600}"\r\n}',
        );
        final src = File(p.join(tmp.path, 'src.json'));
        await src.writeAsBytes(bytes);
        await library.import(src.path);
        expect(
          await File(p.join(themes, 'acme-night.json')).readAsBytes(),
          bytes,
        );
      },
    );

    test('«Битый файл не копируется»: invalid, новых файлов нет', () async {
      final path = await source(
        'bad.json',
        '{"name": "bad", "colors": {"accent": "#zz0000"}}',
      );
      final result = await library.import(path);
      expect(result, isA<ThemeImportInvalid>());
      expect(
        (result as ThemeImportInvalid).issue.code,
        ThemeIssueCode.invalidValue,
      );
      expect(
        Directory(themes).existsSync() ? themeFileNames() : <String>[],
        isEmpty,
      );
    });

    test('имя файла-источника с name не сверяется', () async {
      // Источник `Acme Night.json` при `name: acme-night` — не nameMismatch.
      final path = await source('Downloads/Acme Night.json', _acme);
      expect(await library.import(path), isA<ThemeImportImported>());
    });

    test(
      'источник больше 64 КиБ — invalid tooLarge, ничего не записано',
      () async {
        final path = await source('big.json', 'x' * (100 * 1024));
        final result = await library.import(path);
        expect(result, isA<ThemeImportInvalid>());
        expect(
          (result as ThemeImportInvalid).issue.code,
          ThemeIssueCode.tooLarge,
        );
        expect(Directory(themes).existsSync() ? themeFileNames() : [], isEmpty);
      },
    );

    test('источника нет — failed, исключения нет', () async {
      final result = await library.import(p.join(tmp.path, 'nope.json'));
      expect(result, isA<ThemeImportFailed>());
    });

    test('источник — каталог — failed', () async {
      final dir = Directory(p.join(tmp.path, 'dir.json'))..createSync();
      expect(await library.import(dir.path), isA<ThemeImportFailed>());
    });

    test('«Замена только с подтверждением»: needsReplace без записи', () async {
      await writeTheme('acme-night.json', _acme);
      final path = await source('new/acme.json', _acmeV2);

      final result = await library.import(path);

      expect(result, isA<ThemeImportNeedsReplace>());
      expect((result as ThemeImportNeedsReplace).name, 'acme-night');
      expect(
        await File(p.join(themes, 'acme-night.json')).readAsString(),
        _acme,
      );
      expect(themeFileNames(), ['acme-night.json']);
    });

    test(
      'после подтверждения файл заменён целиком, временных файлов нет',
      () async {
        await writeTheme('acme-night.json', _acme + ' ' * 5000);
        final path = await source('new/acme.json', _acmeV2);

        final result = await library.import(path, replace: true);

        expect(result, isA<ThemeImportReplaced>());
        expect(
          await File(p.join(themes, 'acme-night.json')).readAsString(),
          _acmeV2,
        );
        expect(themeFileNames(), [
          'acme-night.json',
        ], reason: 'временный файл переименован или удалён');
      },
    );

    test('то же содержимое — unchanged, файл не перезаписан', () async {
      await writeTheme('acme-night.json', _acme);
      final target = File(p.join(themes, 'acme-night.json'));
      final before = await target.stat();
      final path = await source('same.json', _acme);

      expect(await library.import(path), isA<ThemeImportUnchanged>());
      expect(
        await library.import(path, replace: true),
        isA<ThemeImportUnchanged>(),
      );
      expect((await target.stat()).modified, before.modified);
      expect(themeFileNames(), ['acme-night.json']);
    });

    test('replace: true без существующего файла — imported', () async {
      final path = await source('a.json', _acme);
      expect(
        await library.import(path, replace: true),
        isA<ThemeImportImported>(),
      );
    });

    test(
      'сбой записи — failed, прежний файл цел, временных файлов нет',
      () async {
        await writeTheme('acme-night.json', _acme);
        final path = await source('new.json', _acmeV2);
        // Каталог тем без права записи: временный файл создать нельзя.
        await Process.run('chmod', ['555', themes]);
        addTearDown(() => Process.run('chmod', ['755', themes]));
        // Права не действуют (root, Windows): сценарий недоступен.
        try {
          File(p.join(themes, '.probe')).writeAsStringSync('');
          File(p.join(themes, '.probe')).deleteSync();
          return;
        } on FileSystemException {
          // ожидаемо
        }

        final result = await library.import(path, replace: true);

        expect(result, isA<ThemeImportFailed>());
        await Process.run('chmod', ['755', themes]);
        expect(
          await File(p.join(themes, 'acme-night.json')).readAsString(),
          _acme,
        );
        expect(themeFileNames(), ['acme-night.json']);
      },
      testOn: '!windows',
    );
  });

  group('путь назначения не зависит от источника', () {
    test('источник в подкаталоге с `..` и пробелами в имени', () async {
      final path = await source('a b/../c d/../x.json', _acme);
      await library.import(path);
      expect(themeFileNames(), ['acme-night.json']);
      expect(
        tmp
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.basename(f.path)),
        unorderedEquals(['acme-night.json', 'x.json']),
        reason: 'в дереве только источник и копия в themes',
      );
    });

    test('источник с именем `..x.json` и пробелами', () async {
      final path = await source('Downloads/..x  y.json', _acme);
      await library.import(path);
      expect(themeFileNames(), ['acme-night.json']);
    });

    test(
      'name с путём (`../evil`) — invalid, за пределами каталога пусто',
      () async {
        final path = await source('e.json', '{"name": "../evil"}');
        final result = await library.import(path);
        expect(result, isA<ThemeImportInvalid>());
        expect(
          (result as ThemeImportInvalid).issue.code,
          ThemeIssueCode.invalidName,
        );
        expect(File(p.join(home, 'evil.json')).existsSync(), isFalse);
        expect(File(p.join(tmp.path, 'evil.json')).existsSync(), isFalse);
        expect(Directory(themes).existsSync() ? themeFileNames() : [], isEmpty);
      },
    );

    test('name с разделителем пути `a/b` — invalid', () async {
      final path = await source('e2.json', '{"name": "a/b"}');
      expect(await library.import(path), isA<ThemeImportInvalid>());
      expect(Directory(themes).existsSync() ? themeFileNames() : [], isEmpty);
    });

    test('импорт не меняет файл-источник', () async {
      final path = await source('keep/Acme.json', _acme);
      await library.import(path);
      expect(await File(path).readAsString(), _acme);
    });
  });
}
