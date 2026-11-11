import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_client_io/src/files/io_project_files.dart'
    show resolveLexicallyInsideRoot, openFileRange;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `IoProjectFiles` на временной папке (change `add-file-preview-and-tree`,
/// задача 1.3; spec `acp-client-kit` «IO-адаптеры клиента» и
/// `workspace-file-browser` «Граница рабочей папки браузера»).
void main() {
  late Directory sandbox;
  late String root; // канонический корень
  late String outside; // папка рядом с корнем, вне него
  const files = IoProjectFiles();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('io_project_files_');
    final realSandbox = await sandbox.resolveSymbolicLinks();
    root = p.join(realSandbox, 'root');
    outside = p.join(realSandbox, 'outside');
    await Directory(root).create();
    await Directory(outside).create();
  });

  tearDown(() async {
    // Закрытая папка теста Q16 мешала бы удалению.
    final locked = Directory(p.join(outside, 'locked'));
    if (!Platform.isWindows && await locked.exists()) {
      await Process.run('chmod', ['755', locked.path]);
    }
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Matcher failure(ProjectFilesFailureKind kind) =>
      throwsA(isA<ProjectFilesFailure>().having((e) => e.kind, 'kind', kind));

  Future<void> writeFile(String path, List<int> bytes) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes);
  }

  group('canonicalRoot', () {
    test('раскрывает ссылку на папку проекта', () async {
      final link = p.join(p.dirname(root), 'rootLink');
      await Link(link).create(root);
      expect(await files.canonicalRoot(link), root);
    });

    test('нет папки — notFound', () async {
      await expectLater(
        files.canonicalRoot(p.join(root, 'missing')),
        failure(ProjectFilesFailureKind.notFound),
      );
    });
  });

  group('list', () {
    test('папки, затем файлы; относительные POSIX-пути и размер', () async {
      await writeFile(p.join(root, 'b.txt'), [1, 2, 3]);
      await writeFile(p.join(root, 'A.txt'), []);
      await Directory(p.join(root, 'src')).create();
      await writeFile(p.join(root, 'src', 'x.dart'), [1]);

      final root0 = await files.list(root, '');
      expect(root0.omitted, 0);
      expect(root0.relativeDir, '');
      expect(root0.entries.map((e) => e.name), ['src', 'A.txt', 'b.txt']);
      expect(root0.entries.first.kind, ProjectEntryKind.directory);
      expect(root0.entries.last.size, 3);

      final sub = await files.list(root, 'src');
      expect(sub.relativeDir, 'src');
      expect(sub.entries.single.relativePath, 'src/x.dart');
      expect(sub.entries.single.kind, ProjectEntryKind.file);
    });

    test('.git нет в перечислении, остальные скрытые файлы есть', () async {
      await Directory(p.join(root, '.git')).create();
      await writeFile(p.join(root, '.env'), [1]);
      final listing = await files.list(root, '');
      expect(listing.entries.map((e) => e.name), ['.env']);
    });

    test('файл .git (рабочее дерево git worktree) тоже скрыт', () async {
      await writeFile(p.join(root, '.git'), [1]);
      final listing = await files.list(root, '');
      expect(listing.entries, isEmpty);
    });

    test('ссылка внутри корня: docs -> doc раскрывается как папка', () async {
      await writeFile(p.join(root, 'doc', 'a.md'), [0x23]);
      await Link(p.join(root, 'docs')).create(p.join(root, 'doc'));

      final top = await files.list(root, '');
      final docs = top.entries.firstWhere((e) => e.name == 'docs');
      expect(docs.kind, ProjectEntryKind.directory);

      final inner = await files.list(root, 'docs');
      expect(inner.entries.single.relativePath, 'docs/a.md');
      final preview = await files.read(root, 'docs/a.md');
      expect((preview as TextPreview).text, '#');
    });

    test(
      'ссылка наружу: symlinkOutside, раскрытие и чтение — outsideRoot',
      () async {
        await writeFile(p.join(outside, 'x.txt'), [0x78]);
        await Link(p.join(root, 'out')).create(outside);
        await Link(p.join(root, 'outFile')).create(p.join(outside, 'x.txt'));

        final top = await files.list(root, '');
        expect(
          top.entries.singleWhere((e) => e.name == 'out').kind,
          ProjectEntryKind.symlinkOutside,
        );
        expect(
          top.entries.singleWhere((e) => e.name == 'outFile').kind,
          ProjectEntryKind.symlinkOutside,
        );

        await expectLater(
          files.list(root, 'out'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
        await expectLater(
          files.read(root, 'out/x.txt'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
        await expectLater(
          files.read(root, 'outFile'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
      },
    );

    test('битая ссылка — other', () async {
      await Link(p.join(root, 'dangling')).create(p.join(root, 'nowhere'));
      final top = await files.list(root, '');
      expect(top.entries.single.kind, ProjectEntryKind.other);
    });

    test('../ и абсолютный путь — invalidPath до обращения к диску', () async {
      await expectLater(
        files.list(root, '..'),
        failure(ProjectFilesFailureKind.invalidPath),
      );
      await expectLater(
        files.read(root, '../outside/x.txt'),
        failure(ProjectFilesFailureKind.invalidPath),
      );
      await expectLater(
        files.read(root, p.join(outside, 'x.txt')),
        failure(ProjectFilesFailureKind.invalidPath),
      );
    });

    test('нет папки или файла — notFound', () async {
      await expectLater(
        files.list(root, 'nope'),
        failure(ProjectFilesFailureKind.notFound),
      );
      await expectLater(
        files.read(root, 'nope.txt'),
        failure(ProjectFilesFailureKind.notFound),
      );
    });

    test('сосед с общим префиксом имени не считается внутри корня', () async {
      final sibling = '$root-evil';
      await Directory(sibling).create();
      await writeFile(p.join(sibling, 'x.txt'), [1]);
      await Link(p.join(root, 'sib')).create(sibling);
      final top = await files.list(root, '');
      expect(top.entries.single.kind, ProjectEntryKind.symlinkOutside);
      await expectLater(
        files.read(root, 'sib/x.txt'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    });

    test('5001 запись: возвращено 5000, omitted — 1', () async {
      for (var i = 0; i < 5001; i++) {
        await File(p.join(root, 'f${i.toString().padLeft(5, '0')}')).create();
      }
      final listing = await files.list(root, '');
      expect(listing.entries, hasLength(5000));
      expect(listing.omitted, 1);
      expect(listing.entries.first.name, 'f00000');
    });

    test('maxEntries задаёт лимит', () async {
      for (var i = 0; i < 5; i++) {
        await File(p.join(root, 'f$i')).create();
      }
      final listing = await files.list(root, '', maxEntries: 2);
      expect(listing.entries.map((e) => e.name), ['f0', 'f1']);
      expect(listing.omitted, 3);
    });
  });

  group('read', () {
    test('текст в UTF-8', () async {
      await File(p.join(root, 'a.txt')).writeAsString('привет');
      final r = await files.read(root, 'a.txt');
      expect((r as TextPreview).text, 'привет');
    });

    test('двоичный файл по содержимому, а не по расширению', () async {
      await writeFile(p.join(root, 'notes.txt'), [0x61, 0, 0x62]);
      final r = await files.read(root, 'notes.txt');
      expect(r, isA<BinaryPreview>());
      expect((r as BinaryPreview).size, 3);
    });

    test(
      'файл 3 МиБ при maxBytes 1 МиБ — TooLargePreview с полным размером',
      () async {
        await writeFile(p.join(root, 'big.txt'), List.filled(3 << 20, 0x61));
        final r = await files.read(root, 'big.txt');
        expect(r, isA<TooLargePreview>());
        expect((r as TooLargePreview).size, 3 << 20);
      },
    );

    test('файл ровно maxBytes читается как текст', () async {
      await writeFile(p.join(root, 'edge.txt'), List.filled(100, 0x61));
      final r = await files.read(root, 'edge.txt', maxBytes: 100);
      expect(r, isA<TextPreview>());
    });

    test('папка вместо файла — unreadable', () async {
      await Directory(p.join(root, 'dir')).create();
      await expectLater(
        files.read(root, 'dir'),
        failure(ProjectFilesFailureKind.unreadable),
      );
    });
  });

  group('граница: цепочки, циклы, несуществующие цели', () {
    test('цепочка a -> b -> outside: symlinkOutside и outsideRoot', () async {
      await writeFile(p.join(outside, 'x.txt'), [0x78]);
      await Link(p.join(root, 'b')).create(outside);
      await Link(p.join(root, 'a')).create(p.join(root, 'b'));
      final top = await files.list(root, '');
      expect(
        top.entries.singleWhere((e) => e.name == 'a').kind,
        ProjectEntryKind.symlinkOutside,
      );
      await expectLater(
        files.read(root, 'a/x.txt'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    });

    test('ссылка с относительной целью ../outside — наружу', () async {
      await writeFile(p.join(outside, 'x.txt'), [0x78]);
      await Link(p.join(root, 'rel')).create('../outside');
      final top = await files.list(root, '');
      expect(top.entries.single.kind, ProjectEntryKind.symlinkOutside);
      await expectLater(
        files.read(root, 'rel/x.txt'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    });

    test('цикл ссылок: в списке other, чтение — unreadable', () async {
      await Link(p.join(root, 'l1')).create(p.join(root, 'l2'));
      await Link(p.join(root, 'l2')).create(p.join(root, 'l1'));
      final top = await files.list(root, '');
      expect(
        top.entries.map((e) => e.kind),
        everyElement(ProjectEntryKind.other),
      );
      await expectLater(
        files.read(root, 'l1'),
        failure(ProjectFilesFailureKind.unreadable),
      );
    });

    test('Q16: существование файла вне корня не различается', () async {
      await writeFile(p.join(outside, 'exists'), [1]);
      await Link(p.join(root, 'out')).create(outside);
      await expectLater(
        files.read(root, 'out/exists'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
      await expectLater(
        files.read(root, 'out/missing'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
      await expectLater(
        files.read(root, 'out/missing/deeper'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
      await expectLater(
        files.list(root, 'out/missing'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    });

    test(
      'Q16: отсутствующий файл внутри корня — по-прежнему notFound',
      () async {
        await Directory(p.join(root, 'in')).create();
        await expectLater(
          files.read(root, 'in/missing'),
          failure(ProjectFilesFailureKind.notFound),
        );
        await expectLater(
          files.read(root, 'in/missing/deeper'),
          failure(ProjectFilesFailureKind.notFound),
        );
      },
    );

    test('\\0 на уровне адаптера — invalidPath', () async {
      await expectLater(
        files.read(root, 'a\u0000b'),
        failure(ProjectFilesFailureKind.invalidPath),
      );
      await expectLater(
        files.list(root, 'a\u0000b'),
        failure(ProjectFilesFailureKind.invalidPath),
      );
      await expectLater(
        files.list('$root\u0000', ''),
        failure(ProjectFilesFailureKind.invalidPath),
      );
      await expectLater(
        files.canonicalRoot('$root\u0000'),
        failure(ProjectFilesFailureKind.invalidPath),
      );
    });

    test('list файла и read папки — оба unreadable', () async {
      await writeFile(p.join(root, 'f.txt'), [1]);
      await Directory(p.join(root, 'dir')).create();
      await expectLater(
        files.list(root, 'f.txt'),
        failure(ProjectFilesFailureKind.unreadable),
      );
      await expectLater(
        files.read(root, 'dir'),
        failure(ProjectFilesFailureKind.unreadable),
      );
    });

    test('Q16: ответ не зависит от того, что лежит вне корня', () async {
      await writeFile(p.join(outside, 'exists'), [1]);
      await Link(p.join(root, 'out')).create(outside);
      // ENOTDIR вне корня.
      await expectLater(
        files.read(root, 'out/exists/deeper'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
      // Цикл ссылок вне корня (ELOOP).
      await Link(p.join(outside, 'l1')).create(p.join(outside, 'l2'));
      await Link(p.join(outside, 'l2')).create(p.join(outside, 'l1'));
      await expectLater(
        files.read(root, 'out/l1'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
      await expectLater(
        files.read(root, 'out/l1/x'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    });

    test(
      'Q16: ссылка прямо на отсутствующую или существующую цель вне корня',
      () async {
        await writeFile(p.join(outside, 'existing-file'), [1]);
        await Link(p.join(root, 'gone')).create(p.join(outside, 'missing'));
        await Link(
          p.join(root, 'there'),
        ).create(p.join(outside, 'existing-file'));
        await expectLater(
          files.read(root, 'gone'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
        await expectLater(
          files.read(root, 'there'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
        await expectLater(
          files.list(root, 'gone'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
      },
    );

    test('Q16: закрытая папка вне корня (EACCES)', () async {
      final uid = await Process.run('id', ['-u']);
      if ((uid.stdout as String).trim() == '0') {
        markTestSkipped('под root chmod 000 не закрывает папку');
        return;
      }
      await Directory(p.join(outside, 'locked')).create();
      await Link(p.join(root, 'out')).create(outside);
      addTearDown(
        () => Process.run('chmod', ['755', p.join(outside, 'locked')]),
      );
      await Process.run('chmod', ['000', p.join(outside, 'locked')]);
      await expectLater(
        files.read(root, 'out/locked/x'),
        failure(ProjectFilesFailureKind.outsideRoot),
      );
    }, skip: Platform.isWindows ? 'chmod недоступен' : false);

    test(
      'Q16: цепочка a -> b -> цель вне корня не зависит от её существования',
      () async {
        await writeFile(p.join(outside, 'existing'), [1]);
        await Link(p.join(root, 'a')).create(p.join(root, 'b'));
        await Link(p.join(root, 'b')).create(p.join(outside, 'missing'));
        await Link(p.join(root, 'c')).create(p.join(root, 'd'));
        await Link(p.join(root, 'd')).create(p.join(outside, 'existing'));
        await expectLater(
          files.read(root, 'a'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
        await expectLater(
          files.read(root, 'c'),
          failure(ProjectFilesFailureKind.outsideRoot),
        );
      },
    );

    test(
      'цепочка a -> b -> отсутствующий путь внутри корня — notFound',
      () async {
        await Link(p.join(root, 'a')).create(p.join(root, 'b'));
        await Link(p.join(root, 'b')).create(p.join(root, 'missing'));
        await expectLater(
          files.read(root, 'a'),
          failure(ProjectFilesFailureKind.notFound),
        );
        final top = await files.list(root, '');
        expect(
          top.entries.map((e) => e.kind),
          everyElement(ProjectEntryKind.other),
        );
      },
    );

    test('list: битые цепочки вне корня — other', () async {
      await Link(p.join(root, 'a')).create(p.join(root, 'b'));
      await Link(p.join(root, 'b')).create(p.join(outside, 'missing'));
      final top = await files.list(root, '');
      expect(
        top.entries.map((e) => e.kind),
        everyElement(ProjectEntryKind.other),
      );
    });

    test('внутри корня ошибки не маскируются', () async {
      await writeFile(p.join(root, 'in', 'file.txt'), [1]);
      await expectLater(
        files.read(root, 'in/file.txt/x'),
        failure(ProjectFilesFailureKind.unreadable),
      );
      await expectLater(
        files.read(root, 'in/missing'),
        failure(ProjectFilesFailureKind.notFound),
      );
      await Link(p.join(root, 'dangling')).create(p.join(root, 'nowhere'));
      await expectLater(
        files.read(root, 'dangling'),
        failure(ProjectFilesFailureKind.notFound),
      );
    });
  });

  group('FIFO', () {
    late String fifo;
    setUp(() async {
      fifo = p.join(root, 'pipe');
      final r = await Process.run('mkfifo', [fifo]);
      expect(r.exitCode, 0);
    });

    test('list не виснет и даёт other', () async {
      final top = await files
          .list(root, '')
          .timeout(const Duration(seconds: 5));
      expect(top.entries.single.kind, ProjectEntryKind.other);
    });

    test('read — unreadable без открытия канала', () async {
      await expectLater(
        files.read(root, 'pipe').timeout(const Duration(seconds: 5)),
        failure(ProjectFilesFailureKind.unreadable),
      );
    });
  }, skip: Platform.isWindows ? 'mkfifo недоступен' : false);

  group('шов openRange: чтение ограничено maxBytes + 1', () {
    test(
      'адаптер просит ровно [0, maxBytes + 1) и получает не больше',
      () async {
        await writeFile(p.join(root, 'big.txt'), List.filled(3 << 20, 0x61));
        int? start;
        int? end;
        var received = 0;
        final spy = IoProjectFiles(
          openRange: (file, s, e) {
            start = s;
            end = e;
            return file.openRead(s, e).map((chunk) {
              received += chunk.length;
              return chunk;
            });
          },
        );
        final r = await spy.read(root, 'big.txt', maxBytes: 1 << 20);
        expect(r, isA<TooLargePreview>());
        expect(start, 0);
        expect(end, (1 << 20) + 1);
        expect(received, lessThanOrEqualTo((1 << 20) + 1));
      },
    );

    test('openFileRange по умолчанию уважает end', () async {
      await writeFile(p.join(root, 'big.bin'), List.filled(3 << 20, 0x61));
      var total = 0;
      await for (final c in openFileRange(
        File(p.join(root, 'big.bin')),
        0,
        100,
      )) {
        total += c.length;
      }
      expect(total, 100);
    });
  });

  group('resolveLexicallyInsideRoot', () {
    final posix = p.Context(style: p.Style.posix);
    final win = p.Context(style: p.Style.windows);

    Matcher invalid() => throwsA(
      isA<ProjectFilesFailure>().having(
        (e) => e.kind,
        'kind',
        ProjectFilesFailureKind.invalidPath,
      ),
    );

    test('POSIX: возвращает склеенный путь', () {
      expect(resolveLexicallyInsideRoot(posix, '/w', ''), '/w');
      expect(resolveLexicallyInsideRoot(posix, '/w', 'a/b'), '/w/a/b');
    });

    test('POSIX: .. и абсолютный путь — invalidPath', () {
      expect(() => resolveLexicallyInsideRoot(posix, '/w', '../x'), invalid());
      expect(() => resolveLexicallyInsideRoot(posix, '/w', '/etc'), invalid());
    });

    test(r'Windows: сегмент с \ или : — invalidPath', () {
      for (final rel in [r'a\..\..\b', 'C:/x', 'a:b', r'a\b']) {
        expect(() => resolveLexicallyInsideRoot(win, r'C:\w', rel), invalid());
      }
    });

    test('Windows: обычные сегменты склеиваются', () {
      expect(resolveLexicallyInsideRoot(win, r'C:\w', 'a/b'), r'C:\w\a\b');
      expect(resolveLexicallyInsideRoot(win, r'C:\w', ''), r'C:\w');
    });

    test(r'POSIX: \ и : — допустимые символы имени', () {
      expect(resolveLexicallyInsideRoot(posix, '/w', r'a\b:c'), r'/w/a\b:c');
    });
  });
}
