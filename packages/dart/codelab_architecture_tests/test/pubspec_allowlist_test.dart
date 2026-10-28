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
  'toml',
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

/// Dependencies of the agent binary (workspace-architecture «Автоматический
/// сторож границ пакетов»; design.md change `add-codelab-agent-binary`, D11).
const binaryAllowlist = {
  'codelab_agent_core',
  'codelab_agent_io',
  'codelab_agent_acp',
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

/// Dependencies of the terminal client (workspace-architecture
/// «Автоматический сторож границ пакетов»; design.md change
/// `add-codelab-cli`, D3): the client layer, the ACP packages, the testing
/// package for `test-scenario` and `args`; no Flutter and no agent packages.
const cliAllowlist = {
  'codelab_client_core',
  'codelab_client_io',
  'codelab_client_acp',
  'codelab_acp_protocol',
  'codelab_acp_transports',
  'codelab_acp_testing',
  'dart_tui',
  'args',
  'async',
  'path',
  'meta',
};

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

  test('codelab_agent_acp depends only on its allowlist', () {
    final pubspec = File(
      p.join(root, 'packages/dart/codelab_agent_acp/pubspec.yaml'),
    ).readAsStringSync();

    final extra = dependencyKeys(pubspec).difference(acpAllowlist);

    expect(extra, isEmpty, reason: 'not in allowlist: ${extra.join(', ')}');
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
