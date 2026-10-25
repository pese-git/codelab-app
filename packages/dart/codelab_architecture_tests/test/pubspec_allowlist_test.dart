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
  'acp_protocol',
  'acp_transports',
  'meta',
  'async',
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
