import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Тексты ошибки имени `codelab mcp add|remove` (design.md change
/// `add-provider-setup-ui`, D11, решение Q20): правило имени переезжает в
/// ядро (`isValidMcpServerName`), а тексты и код `64` остаются прежними.
/// Характеризационный тест: зелёный до переноса и после него.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('mcp_name_text'));
  tearDown(() => root.deleteSync(recursive: true));

  const message = 'the server name must not contain whitespace, [, ] or "';

  for (final name in ['a b', 'a[0]', 'a"b', 'a]']) {
    test('add: имя "$name" — код 64 и прежний текст', () async {
      final result = await McpServerCommands().add(
        McpAddOptions(
          name: name,
          cwd: root.path,
          environment: {'CODELAB_HOME': '${root.path}/home'},
          type: 'http',
          url: 'https://h.test/mcp',
        ),
      );

      expect(result.exitCode, 64);
      expect(result.stderr, ['mcp add: $message']);
    });

    test('remove: имя "$name" — код 64 и прежний текст', () async {
      final result = await McpServerCommands().remove(
        McpRemoveOptions(
          name: name,
          cwd: root.path,
          environment: {'CODELAB_HOME': '${root.path}/home'},
        ),
      );

      expect(result.exitCode, 64);
      expect(result.stderr, ['mcp remove: $message']);
    });
  }
}
