import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'execution_env_contract.dart';

void main() {
  executionEnvContract(
    'MemoryExecutionEnv',
    create: () async => MemoryExecutionEnv(cwd: '/work'),
    writeBytes: (env, path, bytes) async =>
        (env as MemoryExecutionEnv).putBytes(path, Uint8List.fromList(bytes)),
  );

  test('root and cwd always exist', () async {
    final env = MemoryExecutionEnv(cwd: '/work/demo');

    expect(await env.stat('/'), isA<Ok<FileStat, FileError>>());
    expect(
      await env.stat('/work/demo'),
      isA<Ok<FileStat, FileError>>().having(
        (r) => r.value.type,
        'type',
        FileType.directory,
      ),
    );
  });

  test('modified comes from the host clock', () async {
    final clock = FakeClock(start: DateTime.utc(2026, 10, 23, 9));
    final env = MemoryExecutionEnv(cwd: '/work', clock: clock);

    await env.writeText('/work/a.txt', 'a');

    expect(
      await env.stat('/work/a.txt'),
      isA<Ok<FileStat, FileError>>().having(
        (r) => r.value.modified,
        'modified',
        DateTime.utc(2026, 10, 23, 9),
      ),
    );
  });

  test('writeText into a directory path is isDirectory', () async {
    final env = MemoryExecutionEnv(cwd: '/work');
    await env.writeText('/work/d/f.txt', 'x');

    final result = await env.writeText('/work/d', 'x');

    expect(
      result,
      isA<Err<void, FileError>>().having(
        (e) => e.error.code,
        'code',
        FileErrorCode.isDirectory,
      ),
    );
  });

  test('exec answers shellUnavailable', () async {
    final env = MemoryExecutionEnv(cwd: '/work');

    final result = await env.exec('ls', ExecOptions(cwd: '/work'));

    expect(
      result,
      isA<Err<ExecResult, ExecError>>()
          .having((e) => e.error.code, 'code', ExecErrorCode.shellUnavailable)
          .having(
            (e) => e.error.message,
            'message',
            'shell is not available on this platform',
          ),
    );
  });

  test('the memory env lists but resolves no links', () {
    final env = MemoryExecutionEnv(cwd: '/work');

    expect(env, isA<DirectoryListing>());
    expect(env, isNot(isA<PathResolver>()));
  });

  test('listDir of a file is notDirectory, of nothing notFound', () async {
    final env = MemoryExecutionEnv(cwd: '/work');
    await env.writeText('/work/f.txt', 'x');

    expect(
      await env.listDir('/work/f.txt'),
      isA<Err<List<FileStat>, FileError>>().having(
        (e) => e.error.code,
        'code',
        FileErrorCode.notDirectory,
      ),
    );
    expect(
      await env.listDir('/work/none'),
      isA<Err<List<FileStat>, FileError>>().having(
        (e) => e.error.code,
        'code',
        FileErrorCode.notFound,
      ),
    );
  });
}
