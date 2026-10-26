import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/ls.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';
import '../capability_envs.dart';

void main() {
  late MemoryExecutionEnv memory;
  late ExecutorHarness h;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    h = await ExecutorHarness.create([LsTool()], memory: memory);
  });

  test('schema, tier and kind of §6.4', () {
    final tool = LsTool();

    expect(tool.tier, ToolTier.read);
    expect(tool.kind, ToolKind.search);
    expect((tool.parameters['properties']! as Map).keys, ['path', 'limit']);
    expect(tool.parameters.containsKey('required'), isFalse);
  });

  test('one level, case-insensitive order, dirs with / (T-06)', () async {
    for (final path in ['b.txt', 'A.md', '.env', 'lib/x.dart', 'Docs/y.md']) {
      await memory.writeText('/proj/$path', '');
    }

    final outcome = await h.run('ls', {});

    expect(outcome.outcome, ToolOutcome.completed);
    expect(textOf(outcome), '.env\nA.md\nb.txt\nDocs/\nlib/');
  });

  test('a subdirectory by a relative path', () async {
    await memory.writeText('/proj/lib/src/a.dart', '');
    await memory.writeText('/proj/lib/b.dart', '');

    expect(textOf(await h.run('ls', {'path': 'lib'})), 'b.dart\nsrc/');
  });

  test('an empty directory', () async {
    expect(textOf(await h.run('ls', {})), '(empty directory)');
  });

  test('the limit cuts the list and says how many there are', () async {
    for (var i = 0; i < 12; i++) {
      await memory.writeText('/proj/f${i.toString().padLeft(2, '0')}', '');
    }

    final text = textOf(await h.run('ls', {'limit': 10}));

    expect(text.split('\n'), hasLength(11));
    expect(
      text.split('\n').last,
      '[Showing 10 of 12 entries. Use a more specific path.]',
    );
  });

  test('the default limit is 500 entries', () async {
    for (var i = 0; i < 501; i++) {
      await memory.writeText('/proj/f${i.toString().padLeft(3, '0')}', '');
    }

    final lines = textOf(await h.run('ls', {})).split('\n');

    expect(lines, hasLength(501));
    expect(
      lines.last,
      '[Showing 500 of 501 entries. Use a more specific path.]',
    );
  });

  test('a file, a missing path and a bad limit are errors', () async {
    await memory.writeText('/proj/a.txt', '');

    final file = await h.run('ls', {'path': 'a.txt'});
    final missing = await h.run('ls', {'path': 'nope'}, id: 'call_2');
    final limit = await h.run('ls', {'limit': 0}, id: 'call_3');

    expect(textOf(file), 'a.txt is not a directory.');
    expect(textOf(missing), 'File not found: nope');
    expect(textOf(limit), 'limit must be >= 1');
    expect(
      [file, missing, limit].map((o) => o.outcome),
      everyElement(ToolOutcome.failed),
    );
  });

  test('an env without DirectoryListing is not supported', () async {
    final noListing = await ExecutorHarness.create([
      LsTool(),
    ], base: FilesOnlyEnv(MemoryExecutionEnv(cwd: '/proj')));

    expect(
      textOf(await noListing.run('ls', {})),
      'This operation is not supported in the current environment.',
    );
  });
}
