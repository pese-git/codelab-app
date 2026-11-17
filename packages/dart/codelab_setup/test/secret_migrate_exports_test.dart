import 'dart:io';

import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// Реэкспорты `secret migrate` и флагов stdin у `mcp add` (change
/// `add-config-literal-secrets-and-migrate`, задача 3.5, находка №7):
/// клиенту, которому запрещён `package:codelab_agent_*`, движок и опции
/// доступны через мост.
void main() {
  test('io.dart exposes the secret migrate symbols', () {
    final types = <Type>[
      SecretMigrator,
      SecretMigrationOptions,
      SecretMigrationReport,
      SecretMigrationItem,
      SecretMigrationAction,
      SecretPlanItem,
      SecretReusedItem,
      SecretMovedItem,
      SecretReplacedItem,
      SecretActionRequiredItem,
      SecretNotMigratedItem,
      SecretMigrateOptions,
    ];
    expect(types, hasLength(12));
  });

  // change `bind-mcp-secrets-to-origin`, D7, D9: пункт отчёта о переезде
  // HTTP-сервера MCP доступен клиенту через мост; строка без значений.
  test('io.dart exposes the moved MCP server item', () {
    const item = SecretMcpServerMovedItem(
      server: 'mcp.servers[team]',
      from: '/p/.codelab/config.yaml',
      to: '/p/.codelab/config.local.yaml',
    );
    expect(
      item.describe(),
      'Moved mcp.servers[team] (with its secrets) to '
      '/p/.codelab/config.local.yaml; removed the secret values from '
      '/p/.codelab/config.yaml',
    );
  });

  test('mcp add options carry the stdin flags', () {
    const options = McpAddOptions(
      name: 'gh',
      cwd: '.',
      environment: {},
      headerStdin: ['Authorization'],
      headerScheme: 'Bearer',
      envStdin: ['TOKEN'],
    );
    expect(options.headerStdin, ['Authorization']);
    expect(options.headerScheme, 'Bearer');
    expect(options.envStdin, ['TOKEN']);
  });

  test('secret migrate runs through io.dart alone', () async {
    final root = Directory.systemTemp.createTempSync('secret_migrate_exports');
    addTearDown(() => root.deleteSync(recursive: true));
    final home = '${root.path}/home';
    Directory(home).createSync();
    File('$home/config.yaml').writeAsStringSync(
      'providers:\n  p:\n    kind: openai-compatible\n'
      '    base_url: https://llm.test/v1\n    models:\n      m: {}\n'
      'agent:\n  default_model: p/m\n',
    );

    final result = await SecretCommands().migrate(
      SecretMigrateOptions(environment: {'CODELAB_HOME': home}, cwd: root.path),
    );

    expect(result.exitCode, configValidExit, reason: result.stderr.join('\n'));
    expect(result.stdout, ['Nothing to migrate']);
  });
}
