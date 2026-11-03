import 'dart:io';

import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// Компиляция реэкспортов подкоманд записи и чтения конфига (change
/// `add-config-writer-and-reload`, задача 4.3, D6): клиенту, которому запрещён
/// `package:codelab_agent_*`, подкоманды `config path|get|set|unset`,
/// `provider` и `mcp` доступны через мост, вместе с их опциями.
void main() {
  test('io.dart exposes the config write command symbols', () {
    // Ссылки на типы: тест падает на компиляции, если реэкспорта нет.
    final types = <Type>[
      ConfigCommands,
      ConfigCommandResult,
      ConfigGetLayer,
      ConfigPathOptions,
      ConfigGetOptions,
      ConfigSetOptions,
      ConfigUnsetOptions,
      ProviderCommands,
      ProviderAddOptions,
      ProviderListOptions,
      ProviderRemoveOptions,
      McpServerCommands,
      McpAddOptions,
      McpListOptions,
      McpRemoveOptions,
    ];
    expect(types, hasLength(15));
  });

  test('config set and get run through io.dart alone', () async {
    final root = Directory.systemTemp.createTempSync('config_write_exports');
    addTearDown(() => root.deleteSync(recursive: true));
    final home = '${root.path}/home';
    final cwd = '${root.path}/proj';
    Directory(cwd).createSync();
    final environment = {'CODELAB_HOME': home};

    final set = await ConfigCommands().set(
      ConfigSetOptions(
        key: 'budget.max_steps',
        value: '12',
        cwd: cwd,
        environment: environment,
      ),
    );
    final get = await ConfigCommands().get(
      ConfigGetOptions(
        key: 'budget.max_steps',
        cwd: cwd,
        environment: environment,
      ),
    );

    expect(set.exitCode, configValidExit, reason: set.stderr.join('\n'));
    expect(get.exitCode, configValidExit, reason: get.stderr.join('\n'));
    expect(get.stdout, ['12', 'layer: user']);
  });

  test('provider and mcp commands are constructible through io.dart', () {
    expect(ProviderCommands(), isA<ProviderCommands>());
    expect(McpServerCommands(), isA<McpServerCommands>());
  });
}
