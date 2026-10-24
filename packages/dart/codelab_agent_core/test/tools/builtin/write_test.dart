import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';

void main() {
  late MemoryExecutionEnv memory;
  late ExecutorHarness h;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    h = await ExecutorHarness.create([WriteTool()], memory: memory);
  });

  test('schema, tier and kind of §6.4', () {
    final tool = WriteTool();

    expect(tool.tier, ToolTier.write);
    expect(tool.kind, ToolKind.edit);
    expect(tool.parameters['required'], ['path', 'content']);
    expect(tool.lockPath({'path': 'a.txt', 'content': ''}), 'a.txt');
    expect(tool.outputTrust({'path': 'a.txt'}), ContentTrust.trusted);
  });

  test('a new file: Created, parents made, diff without old text', () async {
    final outcome = await h.run('write', {
      'path': 'lib/src/a.dart',
      'content': 'void main() {}\n',
    });

    expect(outcome.outcome, ToolOutcome.completed);
    expect(textOf(outcome), 'Created lib/src/a.dart (15 bytes).');
    expect(
      await memory.readText('/proj/lib/src/a.dart'),
      const Ok<String, FileError>('void main() {}\n'),
    );
    expect(outcome.diffs, [
      const FileDiff(
        path: '/proj/lib/src/a.dart',
        oldText: null,
        newText: 'void main() {}\n',
      ),
    ]);
  });

  test('an existing file: Overwrote, bytes are UTF-8 bytes', () async {
    await memory.writeText('/proj/a.txt', 'old\n');

    final outcome = await h.run('write', {
      'path': 'a.txt',
      'content': 'привет',
    });

    expect(textOf(outcome), 'Overwrote a.txt (12 bytes).');
    expect(outcome.diffs.single.oldText, 'old\n');
    expect(outcome.diffs.single.newText, 'привет');
  });

  test('present builds the same diff for the approval request', () async {
    await memory.writeText('/proj/a.txt', 'old\n');

    await h.run('write', {'path': 'a.txt', 'content': 'new\n'});

    final started = h.events.whereType<ToolCallStarted>().single;
    expect(started.title, 'Write a.txt');
    expect(started.locations, [const Location('/proj/a.txt')]);
  });

  test('a directory and a path outside the workspace are errors', () async {
    await memory.writeText('/proj/dir/x.txt', 'x');

    final dir = await h.run('write', {'path': 'dir', 'content': 'x'});
    final outside = await h.run('write', {
      'path': '../etc/passwd',
      'content': 'x',
    }, id: 'call_2');

    expect(dir.outcome, ToolOutcome.failed);
    expect(textOf(dir), 'dir is a directory.');
    expect(textOf(outside), 'Path is outside the workspace: ../etc/passwd');
  });

  test('the pattern of allow-always is the normalized path', () {
    expect(
      WriteTool().permissionPattern({'path': './lib//a.dart'}, '/proj'),
      'lib/a.dart',
    );
  });
}
