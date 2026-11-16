// `UrlLauncherPathOpener` (задача 2.1 change `add-settings-agents-modes`;
// spec app-settings «Открытие файла и каталога определений»; design.md D8,
// Q8 (б), Q11).
//
// Красные тесты: реализация — задача 2.5. Платформа подменена швом `launch`;
// каталоги — во временной папке, `$CODELAB_HOME` разработчика не читается.

import 'dart:io';

import 'package:codelab_desktop/core/platform/path_opener.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<Uri> launched;
  late bool launchResult;
  Object? launchError;

  UrlLauncherPathOpener make() => UrlLauncherPathOpener(
    launch: (uri) async {
      launched.add(uri);
      if (launchError case final error?) {
        throw error;
      }
      return launchResult;
    },
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('codelab_path_opener_');
    launched = [];
    launchResult = true;
    launchError = null;
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('open', () {
    test('opens the file through Uri.file', () async {
      final file = File('${root.path}/migrator.md')..writeAsStringSync('x');

      final outcome = await make().open(file.path);

      expect(outcome, PathOpenOutcome.opened);
      expect(launched, [Uri.file(file.path)]);
    });

    test('a platform that refuses is "failed"', () async {
      launchResult = false;
      final file = File('${root.path}/a.md')..writeAsStringSync('x');

      final outcome = await make().open(file.path);

      expect(outcome, PathOpenOutcome.failed);
    });

    test('a platform exception is "failed", not a throw', () async {
      launchError = PlatformException(code: 'no-handler');
      final file = File('${root.path}/a.md')..writeAsStringSync('x');

      final outcome = await make().open(file.path);

      expect(outcome, PathOpenOutcome.failed);
    });
  });

  group('what may be opened (D8, review of iteration 2)', () {
    test('a symlink to a definition is not opened', () async {
      final target = File('${root.path}/real.md')..writeAsStringSync('x');
      final link = Link('${root.path}/link.md')..createSync(target.path);

      final outcome = await make().open(link.path);

      expect(outcome, PathOpenOutcome.notAllowed);
      expect(launched, isEmpty);
    });

    test('a file that is not a .md definition is not opened', () async {
      final file = File('${root.path}/id_rsa')..writeAsStringSync('x');

      final outcome = await make().open(file.path);

      expect(outcome, PathOpenOutcome.notAllowed);
      expect(launched, isEmpty);
    });

    test('a folder is not opened as a file', () async {
      final dir = Directory('${root.path}/dir.md')..createSync();

      final outcome = await make().open(dir.path);

      expect(outcome, PathOpenOutcome.notAllowed);
      expect(launched, isEmpty);
    });

    test('a missing file is not opened', () async {
      final outcome = await make().open('${root.path}/missing.md');

      expect(outcome, PathOpenOutcome.notAllowed);
      expect(launched, isEmpty);
    });

    test(
      'a symlink to a folder is not opened, with or without create',
      () async {
        final target = Directory('${root.path}/real')..createSync();
        final link = Link('${root.path}/agents')..createSync(target.path);

        expect(
          await make().openDirectory(link.path),
          PathOpenOutcome.notAllowed,
        );
        expect(
          await make().openDirectory(link.path, create: true),
          PathOpenOutcome.notAllowed,
        );
        expect(launched, isEmpty);
      },
    );

    test('a file in place of a folder is not opened', () async {
      final file = File('${root.path}/agents')..writeAsStringSync('x');

      final outcome = await make().openDirectory(file.path, create: true);

      expect(outcome, PathOpenOutcome.notAllowed);
      expect(launched, isEmpty);
    });
  });

  group('openDirectory', () {
    test(
      'opens an existing folder through Uri.file and creates nothing',
      () async {
        final dir = Directory('${root.path}/agents')..createSync();

        final outcome = await make().openDirectory(dir.path);

        expect(outcome, PathOpenOutcome.opened);
        expect(launched, [Uri.file(dir.path)]);
      },
    );

    test('an existing folder with create is "opened", not "created"', () async {
      final dir = Directory('${root.path}/agents')..createSync();

      final outcome = await make().openDirectory(dir.path, create: true);

      expect(outcome, PathOpenOutcome.opened);
    });

    test('create makes a missing folder with its parents and opens it '
        '(Пользовательского каталога нет)', () async {
      final path = '${root.path}/home/.codelab/agents';

      final outcome = await make().openDirectory(path, create: true);

      expect(outcome, PathOpenOutcome.created);
      expect(Directory(path).existsSync(), isTrue);
      expect(launched, [Uri.file(path)]);
    });

    test('without create a missing folder is not created and the platform '
        'is not called', () async {
      final path = '${root.path}/.codelab/agents';

      final outcome = await make().openDirectory(path);

      expect(outcome, PathOpenOutcome.failed);
      expect(Directory(path).existsSync(), isFalse);
      expect(launched, isEmpty);
    });

    test('a creation that fails is "failed" and the platform is not '
        'called', () async {
      final blocker = File('${root.path}/blocker')..writeAsStringSync('x');

      final outcome = await make().openDirectory(
        '${blocker.path}/agents',
        create: true,
      );

      expect(outcome, PathOpenOutcome.failed);
      expect(launched, isEmpty);
    });

    test('a refusing platform after the creation is "failed"', () async {
      launchResult = false;
      final path = '${root.path}/agents';

      final outcome = await make().openDirectory(path, create: true);

      expect(outcome, PathOpenOutcome.failed);
    });

    test('a platform exception while opening a folder is "failed"', () async {
      launchError = PlatformException(code: 'no-handler');
      final dir = Directory('${root.path}/agents')..createSync();

      final outcome = await make().openDirectory(dir.path);

      expect(outcome, PathOpenOutcome.failed);
    });
  });
}
