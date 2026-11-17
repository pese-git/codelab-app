import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

/// Таблицы чистых правил браузера файлов (change
/// `add-file-preview-and-tree`, задача 1.1; spec `acp-client-kit`,
/// «Чтение папки проекта в границах рабочей папки»).
void main() {
  group('normalizeRelativePath', () {
    const ok = <String, String>{
      '': '',
      '.': '',
      './': '',
      'a': 'a',
      './a': 'a',
      'a/': 'a',
      'a//b': 'a/b',
      'a/./b': 'a/b',
      'lib/src/a.dart': 'lib/src/a.dart',
      '.hidden/.env': '.hidden/.env',
      'a..b/c': 'a..b/c',
      // `..` вычисляется как в POSIX: пока путь остаётся внутри корня, он валиден.
      'a/..': '',
      'lib/a b/ф.dart': 'lib/a b/ф.dart',
    };
    ok.forEach((input, expected) {
      test('«$input» -> «$expected»', () {
        expect(normalizeRelativePath(input), expected);
      });
    });

    const bad = <String>[
      'a\u0000b',
      '\u0000',
      '/etc/passwd',
      '/',
      '..',
      '../a',
      'lib/../../etc/passwd',
      'a/../..',
      'a/../../b',
    ];
    for (final input in bad) {
      test('«${input.replaceAll('\u0000', r'\0')}» -> invalidPath', () {
        expect(
          () => normalizeRelativePath(input),
          throwsA(
            isA<ProjectFilesFailure>().having(
              (e) => e.kind,
              'kind',
              ProjectFilesFailureKind.invalidPath,
            ),
          ),
        );
      });
    }

    test('внутренний .. внутри корня разрешён и схлопывается', () {
      expect(normalizeRelativePath('a/b/../c'), 'a/c');
    });
  });

  group('classifyPreview', () {
    Uint8List bytes(List<int> v) => Uint8List.fromList(v);

    test('обычный текст в UTF-8', () {
      final data = bytes(utf8.encode('привет\nworld'));
      final p = classifyPreview(data, size: data.length);
      expect(p, isA<TextPreview>());
      expect((p as TextPreview).text, 'привет\nworld');
    });

    test('NUL в первых 8 КиБ — бинарный независимо от расширения', () {
      final data = bytes([0x68, 0x69, 0, 0x21]);
      final p = classifyPreview(data, size: 4);
      expect(p, isA<BinaryPreview>());
      expect((p as BinaryPreview).size, 4);
    });

    test('NUL на последней позиции 8 КиБ (индекс 8191) — бинарный', () {
      final data = Uint8List(9000)..fillRange(0, 9000, 0x61);
      data[8191] = 0;
      expect(classifyPreview(data, size: 9000), isA<BinaryPreview>());
    });

    test('NUL после 8 КиБ (индекс 8192) — текст', () {
      final data = Uint8List(9000)..fillRange(0, 9000, 0x61);
      data[8192] = 0;
      expect(classifyPreview(data, size: 9000), isA<TextPreview>());
    });

    test('ровно maxBytes — текст, maxBytes + 1 — слишком большой', () {
      final atLimit = Uint8List(100)..fillRange(0, 100, 0x61);
      expect(
        classifyPreview(atLimit, size: 100, maxBytes: 100),
        isA<TextPreview>(),
      );
      final over = Uint8List(101)..fillRange(0, 101, 0x61);
      final p = classifyPreview(over, size: 101, maxBytes: 100);
      expect(p, isA<TooLargePreview>());
      expect((p as TooLargePreview).size, 101);
    });

    test('размер берётся из size, а не из длины прочитанной головы', () {
      final head = Uint8List(1025)..fillRange(0, 1025, 0x61);
      final p = classifyPreview(head, size: 3 << 20, maxBytes: 1024);
      expect((p as TooLargePreview).size, 3 << 20);
    });

    test('большой файл с NUL в голове — бинарный', () {
      final head = Uint8List(1025)..fillRange(0, 1025, 0x61);
      head[10] = 0;
      expect(
        classifyPreview(head, size: 3 << 20, maxBytes: 1024),
        isA<BinaryPreview>(),
      );
    });

    test('неверный UTF-8 заменяется U+FFFD, а не ошибкой', () {
      final p = classifyPreview(bytes([0x61, 0xff, 0x62]), size: 3);
      expect((p as TextPreview).text, 'a�b');
    });

    test('пустой файл — пустой текст', () {
      final p = classifyPreview(Uint8List(0), size: 0);
      expect((p as TextPreview).text, '');
    });

    test('maxBytes по умолчанию — 1 МиБ', () {
      final head = Uint8List((1 << 20) + 1)..fillRange(0, (1 << 20) + 1, 0x61);
      expect(
        classifyPreview(head, size: (1 << 20) + 1),
        isA<TooLargePreview>(),
      );
    });
  });

  group('isMaybeSecretFileName', () {
    const secret = [
      '.env',
      '.env.local',
      '.env.production',
      'server.pem',
      'tls.key',
      'id_ed25519',
      'id_rsa',
      // Q15: без учёта регистра.
      '.ENV',
      '.Env.Local',
      'Server.PEM',
      'KEY.PEM',
      'ID_RSA',
    ];
    const plain = [
      'env.dart',
      'environment.md',
      'key.dart',
      'pem.txt',
      'monkey',
      'valid_id',
      'Env.dart',
      'KEY.dart',
      'README.md',
      '',
    ];
    for (final n in secret) {
      test(
        '«$n» похож на секрет',
        () => expect(isMaybeSecretFileName(n), true),
      );
    }
    for (final n in plain) {
      test(
        '«$n» не похож на секрет',
        () => expect(isMaybeSecretFileName(n), false),
      );
    }
  });

  group('relativeToRoot', () {
    test('другой путь к той же папке (/private/tmp и /tmp)', () {
      expect(
        relativeToRoot(
          '/private/tmp/w/lib/a.dart',
          sessionCwd: '/tmp/w',
          root: '/private/tmp/w',
        ),
        'lib/a.dart',
      );
    });

    test('путь через cwd сессии', () {
      expect(
        relativeToRoot(
          '/tmp/w/lib/a.dart',
          sessionCwd: '/tmp/w',
          root: '/private/tmp/w',
        ),
        'lib/a.dart',
      );
    });

    test('завершающий слеш у cwd и корня не мешает', () {
      expect(
        relativeToRoot('/w/a.dart', sessionCwd: '/w/', root: '/w/'),
        'a.dart',
      );
    });

    test('вне обоих — null', () {
      expect(
        relativeToRoot('/etc/passwd', sessionCwd: '/tmp/w', root: '/tmp/w'),
        isNull,
      );
    });

    test('сосед с общим префиксом имени — null', () {
      expect(
        relativeToRoot('/tmp/w2/a', sessionCwd: '/tmp/w', root: '/tmp/w'),
        isNull,
      );
    });

    test('.. в абсолютном пути, уводящий за корень — null', () {
      expect(
        relativeToRoot(
          '/tmp/w/../etc/passwd',
          sessionCwd: '/tmp/w',
          root: '/tmp/w',
        ),
        isNull,
      );
    });

    test('сам корень — null: место вызова должно быть файлом', () {
      expect(
        relativeToRoot('/tmp/w', sessionCwd: '/tmp/w', root: '/tmp/w'),
        isNull,
      );
    });

    test('пустой sessionCwd пропускается, а не равен «/»', () {
      expect(relativeToRoot('/a/b', sessionCwd: '', root: '/tmp/w'), isNull);
      expect(relativeToRoot('/tmp/w/a', sessionCwd: '', root: '/tmp/w'), 'a');
    });

    test('относительный путь — null', () {
      expect(
        relativeToRoot('lib/a.dart', sessionCwd: '/tmp/w', root: '/tmp/w'),
        isNull,
      );
    });
  });

  group('sortProjectEntries', () {
    ProjectEntry e(String name, ProjectEntryKind kind) =>
        ProjectEntry(relativePath: name, name: name, kind: kind);

    test('папки, затем файлы; без учёта регистра', () {
      final sorted = sortProjectEntries([
        e('b.txt', ProjectEntryKind.file),
        e('Zeta', ProjectEntryKind.directory),
        e('A.txt', ProjectEntryKind.file),
        e('alpha', ProjectEntryKind.directory),
        e('link', ProjectEntryKind.symlinkOutside),
        e('.env', ProjectEntryKind.file),
      ]);
      expect(sorted.map((x) => x.name), [
        'alpha',
        'Zeta',
        '.env',
        'A.txt',
        'b.txt',
        'link',
      ]);
    });

    test('равные без учёта регистра упорядочены детерминированно', () {
      final a = sortProjectEntries([
        e('a', ProjectEntryKind.file),
        e('A', ProjectEntryKind.file),
      ]);
      final b = sortProjectEntries([
        e('A', ProjectEntryKind.file),
        e('a', ProjectEntryKind.file),
      ]);
      expect(a.map((x) => x.name), b.map((x) => x.name));
    });

    test('исходный список не меняется', () {
      final input = [
        e('b', ProjectEntryKind.file),
        e('a', ProjectEntryKind.directory),
      ];
      sortProjectEntries(input);
      expect(input.first.name, 'b');
    });
  });
}
