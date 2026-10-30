import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'resolving_env.dart';

void main() {
  late MemoryExecutionEnv memory;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/lib/a.dart', 'a\n');
    await memory.writeText('/other/b.dart', 'b\n');
  });

  test('a wrap of an env without DirectoryListing does not list', () async {
    final env = await BoundedEnv.wrap(PlainEnv(memory), '/proj');

    expect(env, isNot(isA<DirectoryListing>()));
    expect(env, isNot(isA<PathResolver>()));
  });

  test(
    'a wrap of an env with DirectoryListing lists and checks the path',
    () async {
      final env = await BoundedEnv.wrap(memory, '/proj');

      expect(env, isA<DirectoryListing>());
      final listing = env as DirectoryListing;
      final inside = await listing.listDir('lib');
      final outside = await listing.listDir('/other');

      expect(
        inside,
        isA<Ok<List<FileStat>, FileError>>().having(
          (r) => [for (final s in r.value) s.path],
          'paths',
          ['/proj/lib/a.dart'],
        ),
      );
      expect(fileErrorOf(outside), FileErrorCode.outsideWorkspace);
    },
  );

  test('a resolver is kept and its answer is checked', () async {
    final resolving = ResolvingEnv(memory, links: {'/proj/out': '/other'});
    final env = await BoundedEnv.wrap(resolving, '/proj');

    expect(env, isA<PathResolver>());
    final resolver = env as PathResolver;
    expect(
      await resolver.realpath('lib/a.dart'),
      const Ok<String, FileError>('/proj/lib/a.dart'),
    );
    expect(
      fileErrorOf(await resolver.realpath('out/b.dart')),
      FileErrorCode.outsideWorkspace,
    );
  });
}
