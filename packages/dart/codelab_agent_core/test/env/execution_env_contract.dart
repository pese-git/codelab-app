import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// The shared contract of every [ExecutionEnv] (`agent-core-architecture`
/// §4.11): run by `memory_env_test.dart` here and by the IO package on
/// `LocalExecutionEnv`.
///
/// [create] returns an env whose `cwd` is an existing empty directory;
/// [writeBytes] puts raw bytes into a file (for the non-UTF-8 case).
///
/// [clientBacked] — env исполняет файлы через ACP-клиента
/// (`AcpClientExecutionEnv`, §4.7): клиент различает только «не найдено»
/// (`-32002`), остальные отказы — `io` с его текстом, а `stat` — чтение одной
/// строки без размера и без каталогов. Тогда набор требует ошибку-значение,
/// но не её точный код.
void executionEnvContract(
  String name, {
  required Future<ExecutionEnv> Function() create,
  required Future<void> Function(ExecutionEnv env, String path, List<int> bytes)
  writeBytes,
  bool clientBacked = false,
}) {
  group('$name contract', () {
    late ExecutionEnv env;
    late String root;

    setUp(() async {
      env = await create();
      root = env.cwd;
    });

    test('writeText creates parents and readText reads it back', () async {
      final written = await env.writeText('$root/a/b/c.txt', 'one\ntwo\n');

      expect(written, isA<Ok<void, FileError>>());
      expect(
        await env.readText('$root/a/b/c.txt'),
        const Ok<String, FileError>('one\ntwo\n'),
      );
    });

    test('a relative path is relative to cwd', () async {
      await env.writeText('rel.txt', 'r\n');

      expect(
        await env.readText('$root/rel.txt'),
        const Ok<String, FileError>('r\n'),
      );
    });

    test('readText returns a range of lines with their terminators', () async {
      await env.writeText('$root/lines.txt', '1\n2\n3\n4\n5');

      expect(
        await env.readText('$root/lines.txt', line: 2, limit: 2),
        const Ok<String, FileError>('2\n3\n'),
      );
      expect(
        await env.readText('$root/lines.txt', line: 4),
        const Ok<String, FileError>('4\n5'),
      );
      expect(
        await env.readText('$root/lines.txt', line: 9),
        const Ok<String, FileError>(''),
      );
    });

    test('writeText overwrites an existing file', () async {
      await env.writeText('$root/o.txt', 'old');
      await env.writeText('$root/o.txt', 'new');

      expect(
        await env.readText('$root/o.txt'),
        const Ok<String, FileError>('new'),
      );
    });

    test('expected errors are values, never exceptions', () async {
      await env.writeText('$root/dir/file.txt', 'x');
      await writeBytes(env, '$root/bad.bin', [0xff, 0xfe, 0x00, 0xc3]);

      expect(
        _code(await env.readText('$root/missing.txt')),
        FileErrorCode.notFound,
      );
      expect(
        _code(await env.readText('$root/dir')),
        clientBacked ? isNotNull : FileErrorCode.isDirectory,
      );
      expect(
        _code(await env.readText('$root/bad.bin')),
        clientBacked ? isNotNull : FileErrorCode.notText,
      );
      expect(
        _code(await env.stat('$root/missing.txt')),
        FileErrorCode.notFound,
      );
      expect(
        _code(await env.writeText('$root/dir/file.txt/child', 'x')),
        clientBacked ? isNotNull : FileErrorCode.notDirectory,
      );
    });

    test('stat reports type and size', () async {
      await env.writeText('$root/s/f.txt', 'héllo');

      final file = await env.stat('$root/s/f.txt');

      expect(
        file,
        isA<Ok<FileStat, FileError>>()
            .having((r) => r.value.type, 'type', FileType.file)
            .having(
              (r) => r.value.size,
              'size',
              clientBacked ? isNull : utf8.encode('héllo').length,
            )
            .having((r) => r.value.path, 'path', '$root/s/f.txt'),
      );
      if (clientBacked) {
        return;
      }
      final dir = await env.stat('$root/s');
      expect(
        dir,
        isA<Ok<FileStat, FileError>>().having(
          (r) => r.value.type,
          'type',
          FileType.directory,
        ),
      );
    });

    test('listDir lists direct children in path order', () async {
      if (env is! DirectoryListing) {
        return;
      }
      await env.writeText('$root/l/b.txt', 'b');
      await env.writeText('$root/l/a.txt', 'a');
      await env.writeText('$root/l/sub/c.txt', 'c');

      final listing = await (env as DirectoryListing).listDir('$root/l');

      expect(
        listing,
        isA<Ok<List<FileStat>, FileError>>().having(
          (r) => [for (final s in r.value) '${s.path} ${s.type.name}'],
          'entries',
          ['$root/l/a.txt file', '$root/l/b.txt file', '$root/l/sub directory'],
        ),
      );
    });
  });
}

FileErrorCode? _code(Result<Object?, FileError> result) => switch (result) {
  Ok() => null,
  Err(:final error) => error.code,
};
