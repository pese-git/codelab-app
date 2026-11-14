// Порт открытия каталога в файловом менеджере ОС (задача 4.1 change
// `add-app-skills-page`; spec app-settings «Страница «Skills & extensions»:
// открытие папок»; design.md D8; `platform-integration.md`).
//
// Красный тест: `lib/core/platform/local_folder_opener.dart` ещё нет
// (реализация — задача 4.2). Ожидаемый API (выбран здесь):
//
// * `enum FolderOpenOutcome { opened, failed, missing }`: `opened` — платформа
//   приняла каталог; `missing` — пути нет на диске или это не каталог
//   (файл), платформа не вызывалась; `failed` — путь не абсолютный
//   (платформа не вызывалась), платформа отказала или бросила исключение;
// * `abstract interface class LocalFolderOpener { Future<FolderOpenOutcome>
//   open(String directory); }`;
// * `UrlLauncherLocalFolderOpener({Future<bool> Function(Uri uri)? launch})` —
//   шов тестов `launch`, как у `UrlLauncherExternalLinkOpener`; по умолчанию
//   `launchUrl(Uri.directory(path))`.
//
// Файлы не открываются и не запускаются: у `.md` обработчиком ОС может быть
// что угодно, у исполняемых — запуск (приоритет 1, D8). Тесты используют
// настоящий временный каталог: проверка существования — часть самого порта.

import 'dart:io';

import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late List<Uri> launched;

  UrlLauncherLocalFolderOpener opener({
    Future<bool> Function(Uri uri)? launch,
  }) => UrlLauncherLocalFolderOpener(
    launch: (uri) {
      launched.add(uri);
      return launch == null ? Future.value(true) : launch(uri);
    },
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('local_folder_opener_test');
    launched = [];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('opens an absolute path of an existing directory', () async {
    final dir = Directory('${temp.path}/skills')..createSync();

    expect(await opener().open(dir.path), FolderOpenOutcome.opened);

    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'file');
    expect(launched.single.toFilePath(), contains('skills'));
  });

  test('a file is refused as missing and the platform is not called', () async {
    final file = File('${temp.path}/SKILL.md')..writeAsStringSync('# skill');

    expect(await opener().open(file.path), FolderOpenOutcome.missing);

    expect(launched, isEmpty);
  });

  test('a directory that does not exist is missing, not launched', () async {
    expect(
      await opener().open('${temp.path}/nowhere'),
      FolderOpenOutcome.missing,
    );
    expect(launched, isEmpty);
  });

  test('a relative path is refused and the platform is not called', () async {
    Directory('${temp.path}/rel').createSync();
    final previous = Directory.current;
    Directory.current = temp;
    addTearDown(() => Directory.current = previous);

    for (final path in ['rel', './rel', '../rel', '', '~/skills']) {
      expect(
        await opener().open(path),
        FolderOpenOutcome.failed,
        reason: 'path "$path"',
      );
    }
    expect(launched, isEmpty);
  });

  test('a platform refusal is "failed", not an exception', () async {
    final dir = Directory('${temp.path}/skills')..createSync();

    expect(
      await opener(launch: (uri) async => false).open(dir.path),
      FolderOpenOutcome.failed,
    );
  });

  test('a platform error is "failed" without leaking its text', () async {
    final dir = Directory('${temp.path}/skills')..createSync();
    final failing = opener(launch: (uri) => throw StateError('no handler'));

    expect(await failing.open(dir.path), FolderOpenOutcome.failed);
  });
}
