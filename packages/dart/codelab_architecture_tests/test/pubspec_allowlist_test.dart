import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// Dependencies the agent core may declare (PKG-2,
/// agent-core-architecture §1.2); extending the set requires an OpenSpec
/// change.
const coreAllowlist = {'http', 'meta', 'collection', 'async', 'crypto'};

/// Dependencies of the IO package of the agent (agent-core-architecture
/// §1.2).
const ioAllowlist = {
  'codelab_agent_core',
  'path',
  'meta',
  'async',
  'yaml',
  'yaml_edit',
};

/// Dependencies of the ACP server of the agent (agent-core-architecture
/// §1.2).
const acpAllowlist = {
  'codelab_agent_core',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'meta',
  'async',
};

/// Dependencies of the MCP client of the agent (agent-core-architecture
/// §1.2; design.md change `add-agent-mcp-client`, D14): the core, `http` for
/// streamable HTTP, `meta` and `async`; no `dart:io`, ACP or client packages.
const mcpAllowlist = {'codelab_agent_core', 'http', 'meta', 'async'};

/// Dependencies of the agent binary (workspace-architecture «Автоматический
/// сторож границ пакетов»; design.md change `add-codelab-agent-binary`, D11).
const binaryAllowlist = {
  'codelab_agent_core',
  'codelab_agent_io',
  'codelab_agent_acp',
  'codelab_agent_mcp',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'args',
  'http',
  'async',
  'meta',
};

/// Dependencies of the client kit (design D2 change
/// `extract-acp-client-kit`): only web-safe packages, so the kit stays free
/// of Flutter and `dart:io` transitively.
const kitAllowlist = {
  'codelab_client_acp',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'freezed_annotation',
  'meta',
  'collection',
  'async',
};

/// Dependencies of the client IO adapters (design D2 change
/// `extract-acp-client-kit`): the kit, the ACP client packages and `path`,
/// no Flutter.
const clientIoAllowlist = {
  'codelab_client_core',
  'codelab_client_acp',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'path',
  'meta',
};

/// Допустимые зависимости терминального клиента (workspace-architecture
/// «Автоматический сторож границ пакетов»; design.md change `add-codelab-cli`,
/// D3): клиентский слой, ACP-пакеты, тестовый пакет для `test-scenario`,
/// `args`, `dart_tui` для полноэкранного режима и мост `codelab_setup` для
/// `codelab config check` (change `add-agent-configuration`, D14). Пакетов
/// агента и Flutter здесь нет: к агенту CLI ходит только по ACP.
const cliAllowlist = {
  'codelab_client_core',
  'codelab_client_io',
  'codelab_client_acp',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'codelab_acp_testing',
  'codelab_setup',
  'dart_tui',
  'args',
  'async',
  'path',
  'meta',
};

/// Допустимые зависимости моста настроек `codelab_setup` (workspace-
/// architecture «Автоматический сторож границ пакетов»; design.md change
/// `add-agent-configuration`, D14): ядро агента, его IO-пакет (используется
/// только в `lib/io.dart`) и `meta`. Мост — единственное место, через которое
/// клиенты (CLI, desktop) достают конфигурацию агента, не импортируя
/// `package:codelab_agent_*` сами.
const setupAllowlist = {'codelab_agent_core', 'codelab_agent_io', 'meta'};

final _section = RegExp(r'^(\w+):\s*(?:#.*)?$');
final _key = RegExp(r'^  ([a-zA-Z0-9_]+):');

/// Keys of the top-level `dependencies:` section of a `pubspec.yaml`.
Set<String> dependencyKeys(String pubspec) {
  final keys = <String>{};
  var inDependencies = false;
  for (final line in pubspec.split('\n')) {
    final section = _section.firstMatch(line);
    if (section != null) {
      inDependencies = section.group(1) == 'dependencies';
      continue;
    }
    final key = _key.firstMatch(line);
    if (inDependencies && key != null) keys.add(key.group(1)!);
  }
  return keys;
}

void main() {
  final root = repoRoot();

  test('codelab_agent_core depends only on the allowlist (PKG-2)', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_agent_core/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(coreAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('codelab_agent_io depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_agent_io/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(ioAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('reports toml in the dependencies of the IO package of the agent', () {
    // `codelab.toml` не читается (design.md change `add-agent-configuration`,
    // D12): зависимость `toml` в allowlist пакета не входит.
    const pubspec = '''
name: codelab_agent_io
dependencies: # allowlist
  codelab_agent_core:
    path: ../codelab_agent_core
  yaml: ^3.1.3
  toml: ^0.16.0
''';

    expect(dependencyKeys(pubspec).difference(ioAllowlist), {'toml'});
  });

  test('codelab_agent_acp depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_agent_acp/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(acpAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('codelab_agent_mcp depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_agent_mcp/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(mcpAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('reports json_rpc_2 in the dependencies of the MCP client', () {
    const pubspec = '''
name: codelab_agent_mcp
dependencies: # allowlist
  codelab_agent_core:
    path: ../codelab_agent_core
  json_rpc_2: ^3.0.0
  http: ^1.5.0
''';

    expect(dependencyKeys(pubspec).difference(mcpAllowlist), {'json_rpc_2'});
  });

  test('apps/codelab_agent depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'apps/codelab_agent/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(binaryAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('codelab_client_core depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_client_core/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(kitAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('codelab_client_io depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_client_io/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(clientIoAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('apps/codelab_cli depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'apps/codelab_cli/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(cliAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('codelab_setup depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_setup/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(setupAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
  });

  test('reports http in the dependencies of the setup bridge', () {
    // Мост не ходит в сеть до появления мастера провайдера (этап 7):
    // `http` в allowlist не входит (change `add-agent-configuration`, D14).
    const pubspec = '''
name: codelab_setup
dependencies: # allowlist
  codelab_agent_core:
    path: ../codelab_agent_core
  http: ^1.5.0
''';

    expect(dependencyKeys(pubspec).difference(setupAllowlist), {'http'});
  });

  test('the terminal client may depend on the setup bridge', () {
    expect(cliAllowlist, contains('codelab_setup'));
    expect(cliAllowlist, isNot(contains('codelab_agent_io')));
  });

  test('reports a dependency outside the allowlist', () {
    const pubspec = '''
name: codelab_agent_core
dependencies: # allowlist
  http: ^1.2.0
  path: ^1.9.0
  meta:
    sdk: flutter
dev_dependencies:
  test: ^1.26.3
''';

    expect(dependencyKeys(pubspec).difference(coreAllowlist), {'path'});
  });
}
