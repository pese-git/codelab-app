// Правило «брошенная строка — абсолютный локальный путь» для обоих стилей
// путей (ревью change `add-empty-project-screen`, итерация 1; design.md D4).
// Стиль передаётся явно, поэтому оба проверяются на любом хосте.
//
// Красный: функции `isLocalAbsolutePath` ещё нет, тест не компилируется.

import 'package:codelab_desktop/features/workbench/application/project_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('posix', () {
    bool ok(String path) => isLocalAbsolutePath(path, context: p.posix);

    test('абсолютные пути принимаются', () {
      expect(ok('/a'), isTrue);
      expect(ok('/work/app'), isTrue);
    });

    test('относительные пути и URI отклоняются', () {
      for (final path in const [
        'a',
        'work/app',
        './a',
        '../a',
        'https://user:token@host/a',
        'smb://nas/share',
        'file:///a',
      ]) {
        expect(ok(path), isFalse, reason: path);
      }
    });
  });

  group('windows', () {
    bool ok(String path) => isLocalAbsolutePath(path, context: p.windows);

    test('диск и UNC принимаются', () {
      for (final path in const [
        r'C:\x',
        'C:/x',
        r'\\server\share',
        r'\\?\C:\x',
      ]) {
        expect(ok(path), isTrue, reason: path);
      }
    });

    test('путь от корня текущего диска, диск без каталога и URI '
        'отклоняются', () {
      for (final path in const [
        r'C:x',
        r'\x',
        '/x',
        'x',
        'https://user:token@host/a',
        'file:///C:/a',
      ]) {
        expect(ok(path), isFalse, reason: path);
      }
    });
  });

  test('без контекста берётся стиль хоста', () {
    expect(isLocalAbsolutePath(p.context.absolute('x')), isTrue);
    expect(isLocalAbsolutePath('relative/dir'), isFalse);
  });
}
