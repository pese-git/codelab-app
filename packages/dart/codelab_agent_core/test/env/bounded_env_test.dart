import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/env/bounded_env.dart';
import 'package:test/test.dart';

import 'resolving_env.dart';

void main() {
  late MemoryExecutionEnv memory;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/src/a.dart', 'void main() {}\n');
    await memory.writeText('/proj/a/b/c', 'c\n');
    await memory.writeText('/proj_evil/x', 'evil\n');
    await memory.writeText('/x', 'x\n');
    await memory.writeText('/etc/passwd', 'root\n');
  });

  test('rejects sibling directory with shared prefix', () async {
    final plain = PlainEnv(memory);
    final env = await BoundedEnv.wrap(plain, '/proj');

    final result = await env.readText('/proj_evil/x');

    expect(fileErrorOf(result), FileErrorCode.outsideWorkspace);
    expect(plain.operations, isEmpty);
  });

  test('the table of §4.4 without links', () async {
    final plain = PlainEnv(memory);
    final env = await BoundedEnv.wrap(plain, '/proj');

    Future<FileErrorCode?> check(String path) async =>
        fileErrorOf(await env.stat(path));

    expect(await check('src/a.dart'), isNull);
    expect(await check('/proj'), isNull);
    expect(await check('./a//b/./c'), isNull);
    expect(await check('../x'), FileErrorCode.outsideWorkspace);
    expect(await check('src/../../etc/passwd'), FileErrorCode.outsideWorkspace);
    expect(await check('~/.ssh/id_rsa'), FileErrorCode.outsideWorkspace);
    expect(await check('~'), FileErrorCode.outsideWorkspace);
    expect(plain.operations, [
      'stat /proj/src/a.dart',
      'stat /proj',
      'stat /proj/a/b/c',
    ]);
  });

  test('the inner env receives abs, not the resolved path', () async {
    final resolving = ResolvingEnv(
      memory,
      links: {'/proj/docs': '/proj/site/docs'},
    );
    await memory.writeText('/proj/site/docs/readme.md', 'docs\n');
    final env = await BoundedEnv.wrap(resolving, '/proj');

    final result = await env.readText('docs/readme.md');

    expect(result, isA<Ok<String, FileError>>());
    expect(resolving.operations, ['readText /proj/docs/readme.md']);
  });

  test('a link out of the root is rejected', () async {
    final resolving = ResolvingEnv(memory, links: {'/proj/link': '/etc'});
    final env = await BoundedEnv.wrap(resolving, '/proj');

    final result = await env.readText('link/passwd');

    expect(fileErrorOf(result), FileErrorCode.outsideWorkspace);
    expect(resolving.operations, isEmpty);
  });

  test('a new file behind a link into the root is accepted', () async {
    await memory.writeText('/proj/site/docs/index.md', 'i\n');
    final resolving = ResolvingEnv(
      memory,
      links: {'/proj/docs': '/proj/site/docs'},
    );
    final env = await BoundedEnv.wrap(resolving, '/proj');

    final result = await env.writeText('docs/new/file.md', 'new\n');

    expect(result, isA<Ok<void, FileError>>());
    expect(
      await memory.readText('/proj/site/docs/new/file.md'),
      const Ok<String, FileError>('new\n'),
    );
  });

  test('Windows paths after conversion: a sibling drive folder', () async {
    await memory.writeText('/c/proj2/x', 'x\n');
    final plain = PlainEnv(memory);
    final env = await BoundedEnv.wrap(plain, '/c/proj');

    expect(
      fileErrorOf(await env.readText('/c/proj2/x')),
      FileErrorCode.outsideWorkspace,
    );
    expect(
      fileErrorOf(await env.readText('/c/proj/../proj2/x')),
      FileErrorCode.outsideWorkspace,
    );
    expect(plain.operations, isEmpty);
  });

  test('exec checks the working directory, not the command', () async {
    final plain = PlainEnv(memory);
    final env = await BoundedEnv.wrap(plain, '/proj');

    final outside = await env.exec(
      'cat /etc/passwd',
      ExecOptions(cwd: '/proj_evil'),
    );
    final inside = await env.exec('cat /etc/passwd', ExecOptions(cwd: 'src'));

    expect(
      outside,
      isA<Err<ExecResult, ExecError>>().having(
        (e) => e.error.code,
        'code',
        ExecErrorCode.outsideWorkspace,
      ),
    );
    expect(
      inside,
      isA<Err<ExecResult, ExecError>>().having(
        (e) => e.error.code,
        'code',
        ExecErrorCode.shellUnavailable,
      ),
    );
    expect(plain.operations, ['exec /proj/src']);
  });

  test('cwd of the bounded env is the normalized root', () async {
    final env = await BoundedEnv.wrap(memory, '/proj/./src/..');

    expect(env.cwd, '/proj');
  });
}
