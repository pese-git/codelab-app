import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';

void main() {
  const cwd = '/proj';

  test('write and edit: the path relative to the root (§7.5)', () {
    expect(
      EditTool().permissionPattern({'path': './lib//a.dart'}, cwd),
      'lib/a.dart',
    );
    expect(
      EditTool().permissionPattern({'path': '/proj/lib/a.dart'}, cwd),
      'lib/a.dart',
    );
  });

  test('read: the normalized path, the root by default', () {
    expect(
      ReadTool().permissionPattern({'path': 'lib/../lib/a'}, cwd),
      'lib/a',
    );
    expect(ReadTool().permissionPattern({'path': '.'}, cwd), '.');
  });

  test('exec: the command without surrounding spaces', () {
    expect(
      ExecTool().permissionPattern({'command': '  dart test '}, cwd),
      'dart test',
    );
  });

  test('other tools: the canonical JSON of the arguments', () {
    expect(
      FakeTool('mcp__x__y').permissionPattern({'b': 1, 'a': 'x'}, cwd),
      '{"a":"x","b":1}',
    );
  });
}
