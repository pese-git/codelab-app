// Корень файловой системы как проект (задачи A1.5 и A1.13 change
// `require-project-folder`; design.md D10, D24): снимок старой версии мог
// хранить `/` вместо проекта, а `cwd` сессии мог быть записан как `/tmp/..`.
// Сравнивать нужно нормализованный путь.

import 'package:codelab_desktop/features/workbench/application/project_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('/ and C:\\ are filesystem roots', () {
    expect(isFilesystemRoot('/'), isTrue);
    expect(isFilesystemRoot(r'C:\'), isTrue);
  });

  test('unnormalized spellings of a root are roots', () {
    for (final path in ['//', '/.', '/tmp/..']) {
      expect(isFilesystemRoot(path), isTrue, reason: path);
    }
    expect(isFilesystemRoot(r'C:\.'), isTrue);
  });

  test('a folder and an empty string are not roots', () {
    expect(isFilesystemRoot('/work'), isFalse);
    expect(isFilesystemRoot('/work/app'), isFalse);
    expect(isFilesystemRoot(r'C:\work'), isFalse);
    expect(isFilesystemRoot(''), isFalse);
  });

  // `cwd` удалённого агента может быть путём другой ОС (D24).
  test('a root of either path style is a root on any host', () {
    expect(isFilesystemRoot(r'C:\'), isTrue);
    expect(isFilesystemRoot(r'C:\tmp\..'), isTrue);
    expect(isFilesystemRoot('/'), isTrue);
    expect(isFilesystemRoot(r'C:\work'), isFalse);
  });
}
