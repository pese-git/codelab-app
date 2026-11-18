// `LocalFolderOpener.open(directory, {create})` (change
// `add-settings-agents-modes`; design.md D8, D20.3, D21; spec app-settings
// «Открытие каталогов определений»): создание отсутствующего каталога
// определений и политика ссылок. Существующие тесты порта
// (`local_folder_opener_test.dart`, `local_folder_opener_hardening_test.dart`)
// не менялись.

import 'dart:io';

import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late List<Uri> launched;

  UrlLauncherLocalFolderOpener opener({bool launchResult = true}) =>
      UrlLauncherLocalFolderOpener(
        launch: (uri) async {
          launched.add(uri);
          return launchResult;
        },
      );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('folder_opener_create_test');
    launched = [];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('create makes a missing folder with its parents, opens it and '
      'reports "created"', () async {
    final path = '${temp.path}/home/.codelab/agents';

    final outcome = await opener().open(path, create: true);

    expect(outcome, FolderOpenOutcome.created);
    expect(Directory(path).existsSync(), isTrue);
    expect(launched, hasLength(1));
  });

  test('create on an existing folder is "opened", not "created"', () async {
    final dir = Directory('${temp.path}/agents')..createSync();

    expect(
      await opener().open(dir.path, create: true),
      FolderOpenOutcome.opened,
    );
  });

  test(
    'without create a missing folder is "missing" and not created',
    () async {
      final path = '${temp.path}/agents';

      expect(await opener().open(path), FolderOpenOutcome.missing);
      expect(Directory(path).existsSync(), isFalse);
      expect(launched, isEmpty);
    },
  );

  test('create does not touch a broken link: "missing", the target is not '
      'created, the link stays', () async {
    final target = '${temp.path}/nowhere';
    final link = Link('${temp.path}/agents')..createSync(target);

    final outcome = await opener().open(link.path, create: true);

    expect(outcome, FolderOpenOutcome.missing);
    expect(Directory(target).existsSync(), isFalse);
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(launched, isEmpty);
  });

  test('create does not replace a file on the path: "missing"', () async {
    final file = File('${temp.path}/agents')..writeAsStringSync('x');

    final outcome = await opener().open(file.path, create: true);

    expect(outcome, FolderOpenOutcome.missing);
    expect(file.existsSync(), isTrue);
    expect(launched, isEmpty);
  });

  test(
    'a creation that fails is "failed" and the platform is not called',
    () async {
      final blocker = File('${temp.path}/blocker')..writeAsStringSync('x');

      final outcome = await opener().open(
        '${blocker.path}/agents',
        create: true,
      );

      expect(outcome, FolderOpenOutcome.failed);
      expect(launched, isEmpty);
    },
  );

  test('a refusing platform after the creation is "failed"', () async {
    final path = '${temp.path}/agents';

    final outcome = await opener(launchResult: false).open(path, create: true);

    expect(outcome, FolderOpenOutcome.failed);
  });

  test('a link to a folder is opened by its resolved path and is not '
      'created over (Каталог-ссылка)', () async {
    final real = Directory('${temp.path}/data')..createSync();
    final link = Link('${temp.path}/agents')..createSync(real.path);

    final outcome = await opener().open(link.path, create: true);

    expect(outcome, FolderOpenOutcome.opened);
    expect(
      launched.single.toFilePath(),
      contains(real.resolveSymbolicLinksSync()),
    );
  });
}
