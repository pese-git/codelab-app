// Охват CI по затронутому (AGENTS.md §21, «Проверка перед pull request»;
// docs/architecture/testing.md §74). Логика лежит в корневом
// `tool/ci/ci_scope.dart`: её запускает лёгкий джоб `scope` в GitHub CI на
// SDK из `setup-dart`, без `pub get`, поэтому у неё нет зависимостей, а тест —
// здесь, в пакете сторожей monorepo.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../../tool/ci/ci_scope.dart';
import 'support/repo_root.dart';

/// Граф для тестов: имена как у настоящих пакетов, зависимости — упрощённые.
final _graph = [
  WorkspacePackage(
    'codelab_acp_protocol',
    'packages/dart/codelab_acp_protocol',
  ),
  WorkspacePackage('codelab_acp_testing', 'packages/dart/codelab_acp_testing', {
    'codelab_acp_protocol',
  }),
  WorkspacePackage('codelab_client_acp', 'packages/dart/codelab_client_acp', {
    'codelab_acp_protocol',
    'codelab_acp_testing',
  }),
  WorkspacePackage('codelab_agent_core', 'packages/dart/codelab_agent_core', {
    'codelab_util',
  }),
  WorkspacePackage('codelab_util', 'packages/dart/codelab_util'),
  WorkspacePackage('codelab_agent_acp', 'packages/dart/codelab_agent_acp', {
    'codelab_acp_protocol',
    'codelab_agent_core',
  }),
  WorkspacePackage('codelab_agent', 'apps/codelab_agent', {
    'codelab_agent_acp',
  }),
  WorkspacePackage('codelab_cli', 'apps/codelab_cli', {'codelab_client_acp'}),
  WorkspacePackage('codelab_ui', 'packages/flutter/codelab_ui'),
  WorkspacePackage('codelab_desktop', 'apps/codelab_desktop', {
    'codelab_ui',
    'codelab_client_acp',
  }),
];

CiScope _scope(List<String> files, {String? fullReason}) =>
    ciScope(packages: _graph, changedFiles: files, fullReason: fullReason);

Map<String, CiJob> _byName(CiScope scope) => {
  for (final job in scope.jobs) job.job: job,
};

void main() {
  test('documentation only needs no code jobs', () {
    final scope = _scope([
      'docs/architecture/testing.md',
      'openspec/changes/x/tasks.md',
      '.claude/commands/check.md',
      'apps/codelab_cli/AGENTS.md',
      'README.md',
    ]);

    expect(scope.full, isFalse);
    expect(scope.jobs, isEmpty);
  });

  test('a file outside the packages runs everything unscoped', () {
    for (final file in [
      'pubspec.lock',
      'pubspec.yaml',
      'analysis_options.yaml',
      '.github/workflows/ci.yml',
      'tool/ci/ci_scope.dart',
    ]) {
      final scope = _scope([file]);

      expect(scope.full, isTrue, reason: file);
      expect(scope.reason, contains(file));
      expect(
        scope.jobs.map((j) => j.job),
        fullJobs.map((j) => j.job),
        reason: file,
      );
      expect(scope.jobs.every((j) => j.packages == null), isTrue);
    }
  });

  test('an explicit full reason runs everything', () {
    final scope = _scope(['docs/x.md'], fullReason: 'push to develop');

    expect(scope.full, isTrue);
    expect(scope.reason, 'push to develop');
    expect(scope.jobs, hasLength(fullJobs.length));
  });

  test('a package change scopes analyze and test to it and its dependents', () {
    final scope = _scope(['packages/flutter/codelab_ui/lib/src/button.dart']);
    final jobs = _byName(scope);

    expect(scope.full, isFalse);
    expect(scope.changed, {'codelab_ui'});
    expect(scope.affected, {'codelab_ui', 'codelab_desktop'});
    expect(jobs.keys, ['format', 'analyze', 'test', 'guard']);
    expect(jobs['analyze']!.scripts, 'analyze:packages');
    expect(jobs['analyze']!.packages, 'codelab_desktop,codelab_ui');
    expect(jobs['test']!.packages, 'codelab_desktop,codelab_ui');
    expect(jobs['format']!.packages, isNull);
    expect(jobs['guard']!.scripts, 'guard');
  });

  test('dependents are transitive, dev dependencies included', () {
    final scope = _scope(['packages/dart/codelab_acp_protocol/lib/a.dart']);

    expect(scope.affected, {
      'codelab_acp_protocol',
      'codelab_acp_testing',
      'codelab_client_acp',
      'codelab_agent_acp',
      'codelab_agent',
      'codelab_cli',
      'codelab_desktop',
    });
  });

  test('conformance runs only the corpora of the affected ACP layers', () {
    final client = _byName(
      _scope(['packages/dart/codelab_client_acp/lib/a.dart']),
    );
    final protocol = _byName(
      _scope(['packages/dart/codelab_acp_protocol/lib/a.dart']),
    );

    expect(client['conformance']!.scripts, 'conformance:client');
    expect(
      protocol['conformance']!.scripts,
      'protocol-conformance conformance:client conformance:agent',
    );
    expect(_byName(_scope(['apps/codelab_desktop/lib/a.dart'])), {
      'format': anything,
      'analyze': anything,
      'test': anything,
      'guard': anything,
    });
  });

  test('the CLI e2e runs when the CLI or the agent binary is affected', () {
    expect(
      _byName(_scope(['packages/dart/codelab_client_acp/lib/a.dart'])).keys,
      contains('e2e-cli-dart'),
    );
    expect(
      _byName(_scope(['packages/dart/codelab_agent_core/lib/a.dart'])).keys,
      contains('e2e-cli-dart'),
    );
    expect(
      _byName(_scope(['packages/flutter/codelab_ui/lib/a.dart'])).keys,
      isNot(contains('e2e-cli-dart')),
    );
  });

  test('the agent core adds prompts:check and web-compile, so does any of '
      'its dependencies', () {
    final core = _byName(
      _scope(['packages/dart/codelab_agent_core/prompts/system.md']),
    );
    final dependency = _byName(
      _scope(['packages/dart/codelab_util/lib/a.dart']),
    );
    final dependent = _byName(
      _scope(['packages/dart/codelab_agent_acp/lib/a.dart']),
    );

    expect(core['guard']!.scripts, 'guard prompts:check');
    expect(core.keys, contains('web-compile'));
    expect(dependency.keys, contains('web-compile'));
    expect(dependency['guard']!.scripts, 'guard');
    expect(dependent.keys, isNot(contains('web-compile')));
  });

  test('a package pubspec lists workspace dependencies only', () {
    final package = WorkspacePackage.fromPubspec(
      'apps/codelab_cli',
      '''
name: codelab_cli
resolution: workspace

dependencies:
  args: ^2.7.0
  codelab_client_core: any
  # comment
  codelab_acp_testing:

dev_dependencies:
  codelab_architecture_tests: any
  test: ^1.26.3

flutter:
  codelab_ui: not-a-dependency
''',
      workspace: {
        'codelab_client_core',
        'codelab_acp_testing',
        'codelab_architecture_tests',
        'codelab_ui',
      },
    );

    expect(package.name, 'codelab_cli');
    expect(package.dependencies, {
      'codelab_client_core',
      'codelab_acp_testing',
      'codelab_architecture_tests',
    });
  });

  test('the real workspace parses into a graph with known edges', () {
    final packages = readWorkspace(repoRoot());
    final byName = {for (final pkg in packages) pkg.name: pkg};

    expect(byName.keys, containsAll(['codelab_cli', 'codelab_desktop']));
    expect(
      byName['codelab_cli']!.dependencies,
      contains('codelab_client_core'),
    );
    expect(
      Directory(p.join(repoRoot(), byName['codelab_ui']!.dir)).existsSync(),
      isTrue,
    );
  });
}
