// Ужесточение `UrlLauncherLocalFolderOpener` по ревью итерации 4 change
// `add-app-skills-page` (безопасность, HIGH): на macOS каталоги `.app`,
// `.workflow`, `.pkg`, `.prefPane` ЗАПУСКАЮТСЯ, а не показываются, на Windows
// `name.{GUID}` — объект оболочки. Порт разрешает симлинки, отказывает при
// расширении или `{…}`-суффиксе имени разрешённого каталога и передаёт
// платформе уже разрешённый путь. Остаточная гонка TOCTOU (подмена самого
// каталога между проверкой и запуском) не устраняется — зафиксировано в
// doc-комментарии порта.

import 'dart:io';

import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late List<Uri> launched;

  UrlLauncherLocalFolderOpener opener() => UrlLauncherLocalFolderOpener(
    launch: (uri) async {
      launched.add(uri);
      return true;
    },
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('folder_opener_hardening');
    launched = [];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('a directory with an extension (x.app) is refused without the '
      'platform', () async {
    final dir = Directory('${temp.path}/x.app')..createSync();

    expect(await opener().open(dir.path), FolderOpenOutcome.failed);
    expect(launched, isEmpty);
  });

  test('other launchable bundle extensions are refused too', () async {
    for (final name in ['a.workflow', 'b.pkg', 'c.prefPane', 'd.d']) {
      final dir = Directory('${temp.path}/$name')..createSync();
      expect(
        await opener().open(dir.path),
        FolderOpenOutcome.failed,
        reason: name,
      );
    }
    expect(launched, isEmpty);
  });

  test('dot-directories without an extension (.codelab, .agents) are '
      'opened', () async {
    for (final name in ['.codelab', '.agents']) {
      final dir = Directory('${temp.path}/$name')..createSync();
      expect(
        await opener().open(dir.path),
        FolderOpenOutcome.opened,
        reason: name,
      );
    }
    expect(launched, hasLength(2));
  });

  test('a symlink .codelab that points to x.app is refused: the resolved '
      'path decides', () async {
    final app = Directory('${temp.path}/x.app')..createSync();
    final link = Link('${temp.path}/.codelab')..createSync(app.path);

    expect(await opener().open(link.path), FolderOpenOutcome.failed);
    expect(launched, isEmpty);
  });

  test('a symlink to a file is missing and not launched', () async {
    final file = File('${temp.path}/SKILL.md')..writeAsStringSync('# s');
    final link = Link('${temp.path}/skills')..createSync(file.path);

    expect(await opener().open(link.path), FolderOpenOutcome.missing);
    expect(launched, isEmpty);
  });

  test('a dangling symlink is missing', () async {
    final link = Link('${temp.path}/gone')..createSync('${temp.path}/nowhere');

    expect(await opener().open(link.path), FolderOpenOutcome.missing);
    expect(launched, isEmpty);
  });

  test('a name ending with a {GUID} suffix is refused', () async {
    final dir = Directory(
      '${temp.path}/name.{00000000-0000-0000-0000-000000000000}',
    )..createSync();

    expect(await opener().open(dir.path), FolderOpenOutcome.failed);
    expect(launched, isEmpty);
  });

  test('a plain directory reached through a symlink: the platform gets '
      'the resolved path', () async {
    final real = Directory('${temp.path}/real')..createSync();
    final link = Link('${temp.path}/link')..createSync(real.path);

    expect(await opener().open(link.path), FolderOpenOutcome.opened);

    final resolved = await real.resolveSymbolicLinks();
    expect(launched.single.toFilePath(), contains('real'));
    expect(
      Directory.fromUri(launched.single).path.replaceAll(RegExp(r'/$'), ''),
      resolved,
    );
  });
}
