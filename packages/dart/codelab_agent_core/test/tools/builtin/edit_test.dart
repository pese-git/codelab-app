import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';

void main() {
  late MemoryExecutionEnv memory;
  late ExecutorHarness h;

  setUp(() async {
    memory = MemoryExecutionEnv(cwd: '/proj');
    h = await ExecutorHarness.create([EditTool()], memory: memory);
  });

  Future<ToolExecutionOutcome> edit(
    String path,
    String oldText,
    String newText,
  ) => h.run('edit', {'path': path, 'oldText': oldText, 'newText': newText});

  Future<String> contentOf(String path) async =>
      switch (await memory.readText(path)) {
        Ok(:final value) => value,
        Err(:final error) => 'error ${error.code}',
      };

  test('schema, tier and kind of §6.4', () {
    final tool = EditTool();

    expect(tool.tier, ToolTier.write);
    expect(tool.kind, ToolKind.edit);
    expect(tool.parameters['required'], ['path', 'oldText', 'newText']);
  });

  test('exactly one match is replaced with a diff for the model', () async {
    await memory.writeText(
      '/proj/lib/main.dart',
      'a\nb\nc\nconst debug = false;\nd\ne\nf\ng\n',
    );

    final outcome = await edit(
      'lib/main.dart',
      'debug = false',
      'debug = true',
    );

    expect(outcome.outcome, ToolOutcome.completed);
    expect(
      await contentOf('/proj/lib/main.dart'),
      'a\nb\nc\nconst debug = true;\nd\ne\nf\ng\n',
    );
    expect(
      textOf(outcome),
      'Edited lib/main.dart: replaced lines 4-4.\n'
      '@@ -1,7 +1,7 @@\n'
      ' a\n'
      ' b\n'
      ' c\n'
      '-const debug = false;\n'
      '+const debug = true;\n'
      ' d\n'
      ' e\n'
      ' f',
    );
    expect(outcome.diffs, [
      const FileDiff(
        path: '/proj/lib/main.dart',
        oldText: 'a\nb\nc\nconst debug = false;\nd\ne\nf\ng\n',
        newText: 'a\nb\nc\nconst debug = true;\nd\ne\nf\ng\n',
      ),
    ]);
  });

  test('no match and several matches leave the file untouched (TOOL-8)', () async {
    await memory.writeText('/proj/a.txt', 'x = 1;\nx = 1;\n');

    final none = await edit('a.txt', 'y = 2;', 'y = 3;');
    final two = await edit('a.txt', 'x = 1;', 'x = 2;');

    expect(none.outcome, ToolOutcome.failed);
    expect(
      textOf(none),
      'No exact match for oldText in a.txt. The text must match byte for byte, '
      'including whitespace and indentation. Read the file again before editing.',
    );
    expect(
      textOf(two),
      'oldText occurs 2 times in a.txt. Include more surrounding context to '
      'make it unique.',
    );
    expect(await contentOf('/proj/a.txt'), 'x = 1;\nx = 1;\n');
  });

  test('occurrences do not overlap: "aa" occurs once in "aaa"', () async {
    await memory.writeText('/proj/a.txt', 'aaa');

    final outcome = await edit('a.txt', 'aa', 'b');

    expect(outcome.outcome, ToolOutcome.completed);
    expect(await contentOf('/proj/a.txt'), 'ba');
  });

  test('CRLF and BOM are kept', () async {
    await memory.writeText('/proj/w.txt', '﻿one\r\ntwo\r\nthree\r\n');

    final outcome = await edit('w.txt', 'two\nthree', 'TWO\nTHREE');

    expect(outcome.outcome, ToolOutcome.completed);
    expect(await contentOf('/proj/w.txt'), '﻿one\r\nTWO\r\nTHREE\r\n');
  });

  test('empty and identical texts are errors', () async {
    await memory.writeText('/proj/a.txt', 'a');

    expect(textOf(await edit('a.txt', '', 'b')), 'oldText must not be empty.');
    expect(
      textOf(await edit('a.txt', 'a', 'a')),
      'oldText and newText are identical; nothing to change.',
    );
  });

  test('a missing file is an env error text', () async {
    expect(
      textOf(await edit('none.txt', 'a', 'b')),
      'File not found: none.txt',
    );
  });

  test('present: title, location of the change and the full diff', () async {
    await memory.writeText('/proj/lib/main.dart', 'a\nb = 1;\n');

    await edit('lib/main.dart', 'b = 1;', 'b = 2;');

    final started = h.events.first as ToolCallStarted;
    expect(started.title, 'Edit lib/main.dart');
    expect(started.kind, ToolKind.edit);
    expect(started.locations.single.path, '/proj/lib/main.dart');
    expect(started.locations.single.line, 2);
  });

  test('the diff fragment is at most 40 lines', () async {
    final old = [for (var i = 1; i <= 60; i++) 'o$i'].join('\n');
    await memory.writeText('/proj/big.txt', old);

    final outcome = await edit('big.txt', old, 'new');

    final lines = textOf(outcome).split('\n');
    expect(lines.first, 'Edited big.txt: replaced lines 1-60.');
    expect(lines, hasLength(42));
    expect(lines.last, '...');
  });
}
