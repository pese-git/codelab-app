import 'dart:io';

import 'package:codelab_agent_io/src/project/skill_roots.dart';
import 'package:test/test.dart';

/// Подъём к корню репозитория в форме ядра (design.md change
/// `add-agent-skills`, D17; задача 2.8): пути ядра `/c/proj` поднимаются по
/// сегментам `/`, а в `dart:io` уходят формой хоста, иначе на Windows `.git`
/// не находится и смешанные формы ломают загрузку.
void main() {
  test('windows: the core path is climbed by segments, .git is asked in the '
      'host form, levels stay in the core form', () {
    final asked = <String>[];
    final result = projectLevels(
      '/c/proj/sub/deep',
      windows: true,
      typeOf: (host) {
        asked.add(host);
        return host == r'C:\proj\.git'
            ? FileSystemEntityType.directory
            : FileSystemEntityType.notFound;
      },
    );

    expect(result.found, isTrue);
    expect(result.levels, ['/c/proj', '/c/proj/sub', '/c/proj/sub/deep']);
    expect(asked, [
      r'C:\proj\sub\deep\.git',
      r'C:\proj\sub\.git',
      r'C:\proj\.git',
    ]);
  });

  test('windows: the search stops at the drive root, which is checked too', () {
    final asked = <String>[];
    final result = projectLevels(
      '/c/proj',
      windows: true,
      typeOf: (host) {
        asked.add(host);
        return FileSystemEntityType.notFound;
      },
    );

    expect(result.found, isFalse);
    expect(result.limitHit, isFalse);
    expect(result.levels, ['/c/proj']);
    expect(asked, [r'C:\proj\.git', r'C:\.git']);
  });

  test('posix: the filesystem root is checked, a trailing slash is cut', () {
    final asked = <String>[];
    final result = projectLevels(
      '/a/b/',
      windows: false,
      typeOf: (host) {
        asked.add(host);
        return host == '/.git'
            ? FileSystemEntityType.file
            : FileSystemEntityType.notFound;
      },
    );

    expect(result.levels, ['/', '/a', '/a/b']);
    expect(asked, ['/a/b/.git', '/a/.git', '/.git']);
  });

  test('a symlink .git is not a marker, 64 levels is the limit', () {
    final deep = '/${List.filled(80, 'd').join('/')}';
    final result = projectLevels(
      deep,
      windows: false,
      typeOf: (_) => FileSystemEntityType.link,
    );

    expect(result.found, isFalse);
    expect(result.limitHit, isTrue);
    expect(result.levels, [deep]);
  });
}
