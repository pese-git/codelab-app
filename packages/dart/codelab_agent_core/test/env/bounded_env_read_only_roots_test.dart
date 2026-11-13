import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../skills/skills_support.dart';
import 'machine_env.dart';
import 'resolving_env.dart' show PlainEnv, fileErrorOf;

const skill = '/home/u/.codelab/skills/notes';

/// Корни только для чтения (agent-execution-env «Корни только для чтения», все
/// сценарии; agent-skills «Сопутствующие файлы и скрипты навыка»; design.md
/// change `add-agent-skills`, D5; решения Q4, Q17, Q23; SKL-9; ENV-3, ENV-4).
///
/// Фиксируемый API: `BoundedEnv.wrap(inner, root)` получает именованные
/// параметры `readOnlyRoots` (список строк, по умолчанию пуст), `readOnlyFs`
/// (`ExecutionEnv?`) и `execInReadOnlyRoots` (`bool`, по умолчанию `false`);
/// метод `SkillCatalog.readOnlyRoots(sessionRoot)` отдаёт канонические
/// каталоги загруженных навыков вне `sessionRoot`.
void main() {
  late MachineEnv inner;
  late MachineEnv hostFs;

  setUp(() async {
    inner = MachineEnv(cwd: '/proj');
    await inner.inner.writeText('/proj/src/a.dart', 'a\n');
    hostFs = MachineEnv(
      links: {'$skill/link': '/etc', '$skill/inside': '$skill/refs'},
    );
    await hostFs.inner.writeText('$skill/ref.md', 'reference\n');
    await hostFs.inner.writeText('$skill/refs/deep.md', 'deep\n');
    await hostFs.inner.writeText('/home/u/.codelab/config.yaml', 'secret\n');
    await hostFs.inner.writeText(
      '/home/u/.codelab/skills/other/SKILL.md',
      'other\n',
    );
    await hostFs.inner.writeText('/home/u/.codelab/skills/notes-evil/x', 'e\n');
    await hostFs.inner.writeText('/etc/passwd', 'root\n');
  });

  Future<ExecutionEnv> wrap({
    bool exec = false,
    bool withFs = true,
    ExecutionEnv? base,
    ExecutionEnv? fs,
  }) async {
    final env = await BoundedEnv.wrap(
      base ?? inner,
      '/proj',
      readOnlyRoots: const [skill],
      readOnlyFs: withFs ? (fs ?? hostFs) : null,
      execInReadOnlyRoots: exec,
    );
    inner.calls.clear();
    inner.resolves.clear();
    return env;
  }

  group('scenario "Чтение и запись в корне только для чтения"', () {
    test('readText goes to readOnlyFs, the inner env gets nothing', () async {
      final env = await wrap();
      hostFs.calls.clear();

      final result = await env.readText('$skill/ref.md');

      expect(result, isA<Ok<String, FileError>>());
      expect((result as Ok<String, FileError>).value, 'reference\n');
      expect(hostFs.calls, ['readText $skill/ref.md']);
      expect(inner.calls, isEmpty);
    });

    test('stat, listDir and readBytes go to readOnlyFs as well', () async {
      final env = await wrap();
      hostFs.calls.clear();

      final stat = await env.stat('$skill/ref.md');
      final listing = await (env as DirectoryListing).listDir(skill);
      final bytes = await (env as BinaryFiles).readBytes('$skill/ref.md');

      expect(stat, isA<Ok<FileStat, FileError>>());
      expect(listing, isA<Ok<List<FileStat>, FileError>>());
      expect(bytes, isA<Ok<dynamic, FileError>>());
      expect(hostFs.calls, ['listDir $skill', 'readBytes $skill/ref.md']);
      expect(inner.calls, isEmpty);
      expect(inner.resolves.where((r) => r.contains('/home/')), isEmpty);
    });

    test(
      'a relative path that resolves into the root is read the same way',
      () async {
        final env = await wrap();

        final result = await env.readText(
          '../home/u/.codelab/skills/notes/ref.md',
        );

        expect(result, isA<Ok<String, FileError>>());
        expect(inner.calls, isEmpty);
      },
    );

    test(
      'writeText is outsideWorkspace before any env sees it (ENV-3)',
      () async {
        final env = await wrap();
        hostFs.calls.clear();
        hostFs.resolves.clear();
        inner.resolves.clear();

        final result = await env.writeText('$skill/ref.md', 'changed');

        expect(fileErrorOf(result), FileErrorCode.outsideWorkspace);
        expect(inner.calls, isEmpty);
        expect(hostFs.calls, isEmpty);
        // ENV-3, D17: отказ — до `stat`/`realpath` любого env.
        expect(hostFs.resolves, isEmpty);
        expect(inner.resolves, isEmpty);
        expect(
          (await hostFs.inner.readText('$skill/ref.md')
                  as Ok<String, FileError>)
              .value,
          'reference\n',
        );
      },
    );

    test(
      'a new file in the root and the root itself cannot be written either',
      () async {
        final env = await wrap();
        hostFs.resolves.clear();
        inner.resolves.clear();

        expect(
          fileErrorOf(await env.writeText('$skill/new.md', 'x')),
          FileErrorCode.outsideWorkspace,
        );
        expect(
          fileErrorOf(await env.writeText(skill, 'x')),
          FileErrorCode.outsideWorkspace,
        );
        expect(inner.calls, isEmpty);
        expect(hostFs.calls, isEmpty);
        expect(hostFs.resolves, isEmpty);
        expect(inner.resolves, isEmpty);
      },
    );

    test('the workspace is read and written as before', () async {
      final env = await wrap();
      hostFs.calls.clear();

      expect(await env.readText('src/a.dart'), isA<Ok<String, FileError>>());
      expect(
        await env.writeText('src/b.dart', 'b'),
        isA<Ok<void, FileError>>(),
      );
      expect(inner.calls, [
        'readText /proj/src/a.dart',
        'writeText /proj/src/b.dart',
      ]);
      expect(hostFs.calls, isEmpty);
    });

    test(
      'the root is resolved through readOnlyFs once, at wrap time',
      () async {
        await wrap();

        expect(
          hostFs.resolves.where((r) => r == 'realpath $skill'),
          hasLength(1),
        );
      },
    );
  });

  group('scenario "Соседи корня только для чтения недоступны"', () {
    test(
      'config.yaml, a sibling skill and a prefix sibling are outside',
      () async {
        final env = await wrap();
        hostFs.calls.clear();

        for (final path in [
          '/home/u/.codelab/config.yaml',
          '/home/u/.codelab/skills/other/SKILL.md',
          '/home/u/.codelab/skills/notes-evil/x',
          '/home/u/.codelab/skills',
          '/home/u/.codelab',
        ]) {
          expect(
            fileErrorOf(await env.readText(path)),
            FileErrorCode.outsideWorkspace,
            reason: path,
          );
        }
        expect(hostFs.calls, isEmpty);
        expect(inner.calls, isEmpty);
      },
    );

    test('.. out of the root is outside', () async {
      final env = await wrap();

      expect(
        fileErrorOf(await env.readText('$skill/../other/SKILL.md')),
        FileErrorCode.outsideWorkspace,
      );
    });
  });

  group('scenario "cwd команды в каталоге навыка" (Q17, Q23)', () {
    test('execInReadOnlyRoots: true -> the command reaches the inner env '
        'with this cwd', () async {
      final env = await wrap(exec: true);

      final result = await env.exec(
        'python3 scripts/x.py',
        ExecOptions(cwd: skill),
      );

      expect(result, isA<Ok<ExecResult, ExecError>>());
      expect(inner.calls, ['exec $skill']);
    });

    test('a subdirectory of the root is accepted too when true', () async {
      final env = await wrap(exec: true);

      await env.exec('ls', ExecOptions(cwd: '$skill/refs'));

      expect(inner.calls, ['exec $skill/refs']);
    });

    test('execInReadOnlyRoots: false -> outsideWorkspace before the inner '
        'env', () async {
      final env = await wrap();

      final result = await env.exec('ls', ExecOptions(cwd: skill));

      expect(
        result,
        isA<Err<ExecResult, ExecError>>().having(
          (r) => r.error.code,
          'code',
          ExecErrorCode.outsideWorkspace,
        ),
      );
      expect(inner.calls, isEmpty);
    });

    test(
      'a cwd outside both areas is outsideWorkspace for both flags',
      () async {
        for (final exec in [true, false]) {
          final env = await wrap(exec: exec);

          for (final cwd in [
            '/etc',
            '/home/u/.codelab/skills/other',
            '/home/u',
          ]) {
            final result = await env.exec('ls', ExecOptions(cwd: cwd));

            expect(
              result,
              isA<Err<ExecResult, ExecError>>(),
              reason: '$cwd exec=$exec',
            );
          }
          expect(inner.calls, isEmpty);
        }
      },
    );

    test('the workspace cwd is not affected by the flag', () async {
      final env = await wrap();

      await env.exec('ls', ExecOptions(cwd: '/proj'));

      expect(inner.calls, ['exec /proj']);
    });
  });

  group('scenario "Ссылка наружу из корня только для чтения"', () {
    test(
      'a link out of the root is outsideWorkspace, nothing is read',
      () async {
        final env = await wrap();
        hostFs.calls.clear();

        final result = await env.readText('$skill/link/passwd');

        expect(fileErrorOf(result), FileErrorCode.outsideWorkspace);
        expect(hostFs.calls, isEmpty);
        expect(inner.calls, isEmpty);
      },
    );

    test('a link inside the root is followed', () async {
      final env = await wrap();

      final result = await env.readText('$skill/inside/deep.md');

      expect(result, isA<Ok<String, FileError>>());
    });

    test('a link as cwd out of the root is rejected even when true', () async {
      final env = await wrap(exec: true);

      final result = await env.exec('ls', ExecOptions(cwd: '$skill/link'));

      expect(result, isA<Err<ExecResult, ExecError>>());
      expect(inner.calls, isEmpty);
    });
  });

  group('without readOnlyFs the roots are ignored', () {
    test('the behavior is that of wrap(inner, root)', () async {
      final env = await wrap(withFs: false, exec: true);

      expect(
        fileErrorOf(await env.readText('$skill/ref.md')),
        FileErrorCode.outsideWorkspace,
      );
      expect(
        (await env.exec('ls', ExecOptions(cwd: skill))),
        isA<Err<ExecResult, ExecError>>(),
      );
      expect(inner.calls, isEmpty);
      expect(hostFs.calls, isEmpty);
    });
  });

  group('optional capabilities (ENV-4)', () {
    test('an inner env without listing: the wrap does not list, even if '
        'readOnlyFs can', () async {
      final env = await wrap(base: PlainEnv(inner.inner));

      expect(env, isNot(isA<DirectoryListing>()));
      expect(env, isNot(isA<BinaryFiles>()));
    });

    test('a readOnlyFs without listing: a path in the root is not listed, '
        'the workspace is', () async {
      final env = await wrap(fs: PlainEnv(hostFs.inner));
      final listing = env as DirectoryListing;

      expect(
        await listing.listDir('/proj'),
        isA<Ok<List<FileStat>, FileError>>(),
      );
      final result = await listing.listDir(skill);

      expect(result, isA<Err<List<FileStat>, FileError>>());
      expect(hostFs.calls, isEmpty);
    });

    test('a readOnlyFs without binary reads: readBytes in the root is an '
        'error', () async {
      final env = await wrap(fs: PlainEnv(hostFs.inner));

      final result = await (env as BinaryFiles).readBytes('$skill/ref.md');

      expect(result, isA<Err<dynamic, FileError>>());
    });
  });

  group('SkillCatalog.readOnlyRoots (SKL-9)', () {
    SkillCatalog catalogAt(List<String> dirs) => parse([
      for (final (i, dir) in dirs.indexed)
        skillFile(
          'n$i',
          frontmatter: {'name': 'n$i', 'description': 'About n$i.'},
          root: dir,
        ),
    ]);

    test('scenario "Каталог навыка внутри рабочей папки": only dirs outside '
        'the session root', () {
      final catalog = catalogAt([
        '/proj/.agents/skills',
        '/proj/.codelab/skills',
        '/home/u/.codelab/skills',
        '/home/u/.agents/skills',
      ]);

      expect(
        catalog.readOnlyRoots('/proj'),
        unorderedEquals([
          '/home/u/.codelab/skills/n2',
          '/home/u/.agents/skills/n3',
        ]),
      );
    });

    test('a prefix sibling of the root is outside by segments', () {
      final catalog = catalogAt(['/proj_evil/skills', '/proj/skills']);

      expect(catalog.readOnlyRoots('/proj'), ['/proj_evil/skills/n0']);
    });

    test('not the whole skills root, only the dirs of loaded skills', () {
      final catalog = catalogAt(['/home/u/.codelab/skills']);

      final roots = catalog.readOnlyRoots('/proj');

      expect(roots, ['/home/u/.codelab/skills/n0']);
      expect(roots, isNot(contains('/home/u/.codelab/skills')));
    });

    test('scenario "Сессия внутри каталога навыка": a skill dir that contains '
        'the session root is not a read-only root', () {
      final catalog = catalogAt(['/home/u/.codelab/skills']);

      expect(catalog.readOnlyRoots('/home/u/.codelab/skills/n0'), isEmpty);
      expect(
        catalog.readOnlyRoots('/home/u/.codelab/skills/n0/scripts'),
        isEmpty,
      );
      // Тот же каталог, но корень сессии рядом, — по-прежнему корень чтения.
      expect(catalog.readOnlyRoots('/home/u/.codelab/skills/n0-evil'), [
        '/home/u/.codelab/skills/n0',
      ]);
    });

    test('an empty catalog has no roots', () {
      expect(SkillCatalog.empty.readOnlyRoots('/proj'), isEmpty);
    });
  });
}
