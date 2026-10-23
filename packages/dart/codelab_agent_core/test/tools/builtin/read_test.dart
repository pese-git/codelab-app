import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';
import '../fake_tools.dart';

void main() {
  late MemoryExecutionEnv memory;
  late ExecutorHarness h;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    h = await ExecutorHarness.create([
      ReadTool(),
      FakeTool('ls'),
    ], memory: memory);
  });

  Future<ToolExecutionOutcome> read(Map<String, Object?> args) =>
      h.run('read', args);

  test('schema, tier and kind of §6.4', () {
    final tool = ReadTool();

    expect(tool.tier, ToolTier.read);
    expect(tool.kind, ToolKind.read);
    expect(tool.parameters['required'], ['path']);
    expect((tool.parameters['properties']! as Map).keys, [
      'path',
      'offset',
      'limit',
    ]);
  });

  test('lines are numbered "<n>| <text>"', () async {
    await memory.writeText(
      '/proj/lib/a.dart',
      "import 'dart:io';\n\nvoid main() {}\n",
    );

    final outcome = await read({'path': 'lib/a.dart'});

    expect(outcome.outcome, ToolOutcome.completed);
    expect(textOf(outcome), "1| import 'dart:io';\n2| \n3| void main() {}");
  });

  test('offset and limit select lines and say how to continue', () async {
    await memory.writeText(
      '/proj/n.txt',
      [for (var i = 1; i <= 30; i++) 'n$i'].join('\n'),
    );

    final outcome = await read({'path': 'n.txt', 'offset': 5, 'limit': 3});

    expect(
      textOf(outcome),
      '5| n5\n6| n6\n7| n7\n'
      '[Showing lines 5-7. More lines may follow: use offset=8.]',
    );
  });

  test('the default limit is 2000 lines', () async {
    await memory.writeText(
      '/proj/big.txt',
      [for (var i = 1; i <= 2500; i++) 'b$i'].join('\n'),
    );

    final lines = textOf(await read({'path': 'big.txt'})).split('\n');

    expect(lines, hasLength(2001));
    expect(lines[1999], '2000| b2000');
    expect(
      lines.last,
      '[Showing lines 1-2000. More lines may follow: use offset=2001.]',
    );
  });

  test(
    'offset below 1 becomes 1 with a note; limit below 1 is an error',
    () async {
      await memory.writeText('/proj/a.txt', 'a\n');

      final fixed = await read({'path': 'a.txt', 'offset': 0});
      final bad = await read({'path': 'a.txt', 'limit': 0});

      expect(textOf(fixed), '1| a\n[Note: offset must be >= 1; using 1.]');
      expect(bad.outcome, ToolOutcome.failed);
      expect(textOf(bad), 'limit must be >= 1');
    },
  );

  test('a long line is cut to 2000 characters', () async {
    await memory.writeText('/proj/long.txt', 'x' * 2500);

    expect(
      textOf(await read({'path': 'long.txt'})),
      '1| ${'x' * 2000} [line truncated]',
    );
  });

  test('an empty file and a binary file', () async {
    await memory.writeText('/proj/empty.txt', '');
    await memory.writeText('/proj/bin.dat', 'ab\u0000cd');

    final empty = await read({'path': 'empty.txt'});
    final binary = await read({'path': 'bin.dat'});

    expect(textOf(empty), '(empty file)');
    expect(binary.outcome, ToolOutcome.failed);
    expect(textOf(binary), 'bin.dat appears to be a binary file.');
  });

  test('env errors become texts of §6.4', () async {
    await memory.writeText('/proj/dir/f.txt', 'f');

    final missing = await read({'path': 'missing.txt'});
    final dir = await read({'path': 'dir'});
    final outside = await read({'path': '../etc/passwd'});

    expect(textOf(missing), 'File not found: missing.txt');
    expect(textOf(dir), 'dir is a directory. Use ls to list it.');
    expect(textOf(outside), 'Path is outside the workspace: ../etc/passwd');
    expect(missing.outcome, ToolOutcome.failed);
  });

  test('without ls in the step the hint is not given', () async {
    await memory.writeText('/proj/dir/f.txt', 'f');

    final outcome = await h.run('read', {
      'path': 'dir',
    }, invocation: h.invocation(stepTools: ['read']));

    expect(textOf(outcome), 'dir is a directory.');
  });

  test('present: title and location of the file', () async {
    await memory.writeText('/proj/lib/a.dart', 'a\n');

    await read({'path': 'lib/a.dart', 'offset': 3});

    final started = h.events.first as ToolCallStarted;
    expect(started.title, 'Read lib/a.dart');
    expect(started.kind, ToolKind.read);
    expect(started.locations.single.path, '/proj/lib/a.dart');
    expect(started.locations.single.line, 3);
  });
}
