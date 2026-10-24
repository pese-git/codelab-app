import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/search.dart';
import 'package:test/test.dart';

import '../capability_envs.dart';
import '../executor_harness.dart';

void main() {
  late MemoryExecutionEnv memory;
  late ExecutorHarness h;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    h = await ExecutorHarness.create([SearchTool()], memory: memory);
  });

  Future<String> search(Map<String, Object?> args) async =>
      textOf(await h.run('search', args));

  test('schema, tier and kind of §6.4', () {
    final tool = SearchTool();

    expect(tool.tier, ToolTier.read);
    expect(tool.kind, ToolKind.search);
    expect(tool.parameters['required'], ['pattern']);
    expect((tool.parameters['properties']! as Map).keys, [
      'pattern',
      'path',
      'glob',
      'literal',
      'ignoreCase',
      'limit',
    ]);
  });

  test('a regex, breadth first, files sorted, lines ascending (T-07)', () async {
    await memory.writeText('/proj/b.dart', 'void b() {}\nfinal x = 1;\n');
    await memory.writeText('/proj/a.dart', 'void a() {}\n');
    await memory.writeText('/proj/lib/c.dart', 'void c() {}\n');

    expect(
      await search({'pattern': r'void \w\('}),
      'a.dart:1: void a() {}\nb.dart:1: void b() {}\nlib/c.dart:1: void c() {}',
    );
  });

  test('a literal and ignoreCase', () async {
    await memory.writeText('/proj/a.txt', 'a.b\naxb\nA.B\n');

    expect(await search({'pattern': 'a.b', 'literal': true}), 'a.txt:1: a.b');
    expect(
      await search({'pattern': 'a.b', 'literal': true, 'ignoreCase': true}),
      'a.txt:1: a.b\na.txt:3: A.B',
    );
  });

  test('a syntax error of the regex', () async {
    final outcome = await h.run('search', {'pattern': '('});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), startsWith('Invalid regular expression: '));
  });

  test('service and hidden directories are skipped', () async {
    for (final dir in [
      '.git',
      '.hg',
      '.svn',
      'node_modules',
      '.dart_tool',
      'build',
      '.idea',
      '.cache',
    ]) {
      await memory.writeText('/proj/$dir/x.txt', 'needle\n');
    }
    await memory.writeText('/proj/src/x.txt', 'needle\n');
    await memory.writeText('/proj/.hidden.txt', 'needle\n');

    // Скрытый файл ищется: пропускаются только скрытые каталоги.
    expect(
      await search({'pattern': 'needle'}),
      '.hidden.txt:1: needle\nsrc/x.txt:1: needle',
    );
  });

  test('a skipped directory is searched when path points to it', () async {
    await memory.writeText('/proj/node_modules/pkg/x.js', 'needle\n');

    final outcome = await h.run('search', {
      'pattern': 'needle',
      'path': 'node_modules',
    });

    // Вывод из node_modules — недоверенный (§6.3.6, P-15).
    expect(
      textOf(outcome),
      '<untrusted-content source="search">\n'
      'node_modules/pkg/x.js:1: needle\n'
      '</untrusted-content>',
    );
  });

  test('binary files and files above 1 MiB are skipped', () async {
    memory.putBytes(
      '/proj/bin.dat',
      Uint8List.fromList([...'needle'.codeUnits, 0, 1]),
    );
    await memory.writeText('/proj/big.txt', 'needle\n${'x' * (1 << 20)}');
    await memory.writeText('/proj/ok.txt', 'needle\n');

    expect(await search({'pattern': 'needle'}), 'ok.txt:1: needle');
  });

  test('glob filters by the path relative to path', () async {
    await memory.writeText('/proj/lib/a.dart', 'needle\n');
    await memory.writeText('/proj/lib/src/b.dart', 'needle\n');
    await memory.writeText('/proj/lib/c.yaml', 'needle\n');
    await memory.writeText('/proj/d.md', 'needle\n');

    expect(
      await search({'pattern': 'needle', 'glob': '**/*.dart'}),
      'lib/a.dart:1: needle\nlib/src/b.dart:1: needle',
    );
    expect(
      await search({
        'pattern': 'needle',
        'path': 'lib',
        'glob': '*.{dart,yaml}',
      }),
      'lib/a.dart:1: needle\nlib/c.yaml:1: needle\nlib/src/b.dart:1: needle',
    );
    expect(
      await search({'pattern': 'needle', 'path': 'lib', 'glob': 'src/*.dart'}),
      'lib/src/b.dart:1: needle',
    );
  });

  test('path may be a single file', () async {
    await memory.writeText('/proj/a.txt', 'one\nneedle\n');

    expect(
      await search({'pattern': 'needle', 'path': 'a.txt'}),
      'a.txt:2: needle',
    );
  });

  test('long lines are cut to 200 characters', () async {
    await memory.writeText('/proj/a.txt', 'needle${'y' * 300}\n');

    final text = await search({'pattern': 'needle'});

    expect(text, 'a.txt:1: needle${'y' * 194}');
  });

  test('no matches', () async {
    await memory.writeText('/proj/a.txt', 'hay\n');

    expect(await search({'pattern': 'needle'}), 'No matches found.');
  });

  test('the match limit with its notice', () async {
    await memory.writeText(
      '/proj/a.txt',
      [for (var i = 0; i < 5; i++) 'needle $i'].join('\n'),
    );

    expect(
      await search({'pattern': 'needle', 'limit': 3}),
      'a.txt:1: needle 0\na.txt:2: needle 1\na.txt:3: needle 2\n'
      '[Showing first 3 matches. Narrow the pattern or the glob.]',
    );
  });

  test('exactly limit matches give no notice', () async {
    await memory.writeText('/proj/a.txt', 'needle\nneedle\n');

    expect(
      await search({'pattern': 'needle', 'limit': 2}),
      'a.txt:1: needle\na.txt:2: needle',
    );
  });

  test('the default limit is 100 matches', () async {
    await memory.writeText(
      '/proj/a.txt',
      List.filled(150, 'needle').join('\n'),
    );

    final lines = (await search({'pattern': 'needle'})).split('\n');

    expect(lines, hasLength(101));
    expect(
      lines.last,
      '[Showing first 100 matches. Narrow the pattern or the glob.]',
    );
  });

  test('the walk stops after 10000 files', () async {
    for (var i = 0; i < 10001; i++) {
      await memory.writeText('/proj/f${i.toString().padLeft(5, '0')}', 'x\n');
    }
    await memory.writeText('/proj/f10001', 'needle\n');

    expect(
      await search({'pattern': 'needle'}),
      'No matches found.\n[Search stopped after scanning 10000 files.]',
    );
  });

  test('a missing path, a bad limit, no DirectoryListing', () async {
    final missing = await h.run('search', {'pattern': 'x', 'path': 'nope'});
    final limit = await h.run('search', {
      'pattern': 'x',
      'limit': 0,
    }, id: 'call_2');
    final noListing = await ExecutorHarness.create([
      SearchTool(),
    ], base: FilesOnlyEnv(MemoryExecutionEnv(cwd: '/proj')));

    expect(textOf(missing), 'File not found: nope');
    expect(textOf(limit), 'limit must be >= 1');
    expect(
      textOf(await noListing.run('search', {'pattern': 'x'})),
      'This operation is not supported in the current environment.',
    );
  });
}
