import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/env/bounded_env.dart';
import 'package:test/test.dart';

/// agent-execution-env «ListingOverlayEnv» (задача 3.1; design.md change
/// `add-dart-agent-acp-server`, D5).
void main() {
  late _CountingEnv primary;
  late MemoryExecutionEnv listing;

  setUp(() async {
    primary = _CountingEnv(MemoryExecutionEnv(cwd: '/work'));
    listing = MemoryExecutionEnv(cwd: '/work');
    await primary.inner.writeText('/work/client.txt', 'from client\n');
    await listing.writeText('/work/local/a.txt', 'a');
  });

  test('listDir comes from listing, the rest from primary', () async {
    final env = ListingOverlayEnv(primary, listing);

    final entries = await env.listDir('/work/local');
    final read = await env.readText('/work/client.txt');
    final written = await env.writeText('/work/new.txt', 'n');
    final stat = await env.stat('/work/client.txt');
    final exec = await env.exec('true', ExecOptions(cwd: '/work'));

    expect(
      entries,
      isA<Ok<List<FileStat>, FileError>>().having(
        (r) => [for (final s in r.value) s.path],
        'paths',
        ['/work/local/a.txt'],
      ),
    );
    expect(read, const Ok<String, FileError>('from client\n'));
    expect(written, isA<Ok<void, FileError>>());
    expect(stat, isA<Ok<FileStat, FileError>>());
    expect(exec, isA<Ok<ExecResult, ExecError>>());
    expect(primary.calls, [
      'readText /work/client.txt',
      'writeText /work/new.txt',
      'stat /work/client.txt',
      'exec true',
    ]);
    expect(
      await listing.stat('/work/new.txt'),
      isA<Err<FileStat, FileError>>(),
    );
  });

  test('cwd is the cwd of primary', () {
    expect(ListingOverlayEnv(primary, listing).cwd, '/work');
  });

  test('BoundedEnv over the overlay keeps one boundary', () async {
    final bounded = await BoundedEnv.wrap(
      ListingOverlayEnv(primary, _ForbiddenListing()),
      '/work',
    );

    expect(bounded, isA<DirectoryListing>());
    final outside = await (bounded as DirectoryListing).listDir('/etc');

    expect(
      outside,
      isA<Err<List<FileStat>, FileError>>().having(
        (r) => r.error.code,
        'code',
        FileErrorCode.outsideWorkspace,
      ),
    );
  });
}

/// Primary env, который записывает обращения.
final class _CountingEnv implements ExecutionEnv {
  _CountingEnv(this.inner);

  final MemoryExecutionEnv inner;
  final calls = <String>[];

  @override
  String get cwd => inner.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) {
    calls.add('readText $path');
    return inner.readText(path, line: line, limit: limit);
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) {
    calls.add('writeText $path');
    return inner.writeText(path, content);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) {
    calls.add('stat $path');
    return inner.stat(path);
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    calls.add('exec $command');
    return const Ok(
      ExecResult(
        exitCode: 0,
        output: '',
        truncated: false,
        duration: Duration.zero,
      ),
    );
  }
}

/// Листинг, к которому граница не должна пускать.
final class _ForbiddenListing implements ExecutionEnv, DirectoryListing {
  @override
  String get cwd => '/work';

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      throw StateError('listDir must not be reached for $path');

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => throw UnimplementedError();

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      throw UnimplementedError();

  @override
  Future<Result<FileStat, FileError>> stat(String path) =>
      throw UnimplementedError();

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => throw UnimplementedError();
}
