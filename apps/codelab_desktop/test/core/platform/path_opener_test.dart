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

      final outcome = await make().open('${root.path}/a.md');

      expect(outcome, PathOpenOutcome.failed);
    });

    test('a platform exception is "failed", not a throw', () async {
      launchError = PlatformException(code: 'no-handler');

      final outcome = await make().open('${root.path}/a.md');

      expect(outcome, PathOpenOutcome.failed);
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
