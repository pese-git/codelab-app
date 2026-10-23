import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// ignore: implementation_imports, the boundary decorator is internal to the core; the test checks it over real links
import 'package:codelab_agent_core/src/env/bounded_env.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../../codelab_agent_core/test/env/execution_env_contract.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_env_');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  executionEnvContract(
    'LocalExecutionEnv',
    create: () async => LocalExecutionEnv(
      cwd: Directory.systemTemp
          .createTempSync('local_contract_')
          .resolveSymbolicLinksSync(),
    ),
    writeBytes: (env, path, bytes) async {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    },
  );

  test('implements every optional capability', () {
    final env = LocalExecutionEnv(cwd: tmp.path);

    expect(env, isA<DirectoryListing>());
    expect(env, isA<BinaryFiles>());
    expect(env, isA<PathResolver>());
  });

  test('a BOM at the start of a file is kept by readText', () async {
    final root = tmp.resolveSymbolicLinksSync();
    File('$root/b.txt').writeAsBytesSync([0xEF, 0xBB, 0xBF, 0x61]);
    final env = LocalExecutionEnv(cwd: root);

    expect(await env.readText('b.txt'), const Ok<String, FileError>('\uFEFFa'));
  });

  group('BoundedEnv over real links', () {
    late String root;
    late String outside;

    setUp(() {
      final base = tmp.resolveSymbolicLinksSync();
      root = '$base/proj';
      outside = '$base/proj_evil';
      Directory('$root/site/docs').createSync(recursive: true);
      Directory(outside).createSync();
      File('$outside/secret').writeAsStringSync('token');
      Link('$root/link').createSync(outside);
      Link('$root/docs').createSync('$root/site/docs');
    });

    test('a sibling directory with a shared prefix is outside', () async {
      final env = await BoundedEnv.wrap(LocalExecutionEnv(cwd: root), root);

      final result = await env.readText('$outside/secret');

      expect(
        result,
        isA<Err<String, FileError>>().having(
          (e) => e.error.code,
          'code',
          FileErrorCode.outsideWorkspace,
        ),
      );
    });

    test('a link out of the root is outside', () async {
      final env = await BoundedEnv.wrap(LocalExecutionEnv(cwd: root), root);

      final result = await env.readText('link/secret');

      expect(
        result,
        isA<Err<String, FileError>>().having(
          (e) => e.error.code,
          'code',
          FileErrorCode.outsideWorkspace,
        ),
      );
    });

    test('a new file behind a link into the root is written', () async {
      final env = await BoundedEnv.wrap(LocalExecutionEnv(cwd: root), root);

      final result = await env.writeText('docs/new/file.md', 'new');

      expect(result, isA<Ok<void, FileError>>());
      expect(File('$root/site/docs/new/file.md').readAsStringSync(), 'new');
    });

    test('listDir shows a link as a link', () async {
      final env = LocalExecutionEnv(cwd: root);

      final listing = await env.listDir(root);

      expect(
        listing,
        isA<Ok<List<FileStat>, FileError>>().having(
          (r) => {for (final s in r.value) s.path.split('/').last: s.type},
          'entries',
          {
            'docs': FileType.link,
            'link': FileType.link,
            'site': FileType.directory,
          },
        ),
      );
    });
  });
}
