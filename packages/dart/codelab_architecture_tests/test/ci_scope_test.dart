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
  WorkspacePackage('codelab_agent_io', 'packages/dart/codelab_agent_io', {
    'codelab_agent_core',
  }),
  WorkspacePackage('codelab_setup', 'packages/dart/codelab_setup', {
    'codelab_agent_core',
    'codelab_agent_io',
  }),
  WorkspacePackage('codelab_agent_acp', 'packages/dart/codelab_agent_acp', {
    'codelab_acp_protocol',
    'codelab_agent_core',
  }),
  WorkspacePackage('codelab_agent', 'apps/codelab_agent', {
    'codelab_agent_acp',
  }),
  WorkspacePackage('codelab_embedded', 'packages/dart/codelab_embedded', {
    'codelab_agent_acp',
  }),
  WorkspacePackage('codelab_cli', 'apps/codelab_cli', {
    'codelab_client_acp',
    'codelab_embedded',
  }),
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

  test('Правка только матрицы: изменение agent-parity-goals.md даёт джоб '
      'guard (change switch-default-agent-to-dart, D7)', () {
    // Разбор матрицы (D2) ломается от правки таблицы, поэтому pull request,
    // который меняет только её, обязан прогнать сторож, а не ждать ночи.
    final scope = _scope(['docs/architecture/proposals/agent-parity-goals.md']);

    expect(scope.full, isFalse);
    expect(scope.jobs.map((j) => j.job), ['guard']);
    expect(_byName(scope)['guard']!.scripts, 'guard');
  });

  test('матрица рядом с другой документацией по-прежнему даёт guard', () {
    final scope = _scope([
      'docs/architecture/testing.md',
      'docs/architecture/proposals/agent-parity-goals.md',
      'openspec/changes/x/tasks.md',
    ]);

    expect(scope.full, isFalse);
    expect(scope.jobs.map((j) => j.job), ['guard']);
  });

  test('другой документ из docs/proposals по-прежнему не даёт джобов', () {
    final scope = _scope(['docs/architecture/proposals/delivery-roadmap.md']);

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
      'codelab_embedded',
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

    // Корпус против встроенного агента играет CLI: он затронут и клиентским
    // слоем, и мостом `codelab_embedded` (change `add-embedded-agent-mode`).
    expect(
      client['conformance']!.scripts,
      'conformance:client conformance:embedded',
    );
    expect(
      protocol['conformance']!.scripts,
      'protocol-conformance conformance:client conformance:agent '
      'conformance:embedded',
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

  test('the embedded CLI e2e and corpus run when the CLI or the embedded '
      'agent is affected', () {
    for (final file in [
      'apps/codelab_cli/lib/a.dart',
      'packages/dart/codelab_embedded/lib/a.dart',
      'packages/dart/codelab_agent_acp/lib/a.dart',
    ]) {
      final jobs = _byName(_scope([file]));

      expect(jobs.keys, contains('e2e-cli-embedded'), reason: file);
      expect(jobs['e2e-cli-embedded']!.scripts, 'test:e2e:cli:embedded');
      expect(jobs['conformance']!.scripts, contains('conformance:embedded'));
    }
    expect(
      _byName(_scope(['apps/codelab_desktop/lib/a.dart'])).keys,
      isNot(contains('e2e-cli-embedded')),
    );
  });

  test('the full run has the embedded jobs of the check script', () {
    final jobs = {for (final job in fullJobs) job.job: job};

    expect(jobs['e2e-cli-embedded']!.scripts, 'test:e2e:cli:embedded');
    expect(jobs['conformance']!.scripts, contains('conformance:embedded'));
  });

  test('the agent core adds prompts:check and web-compile, so does any of '
      'its dependencies', () {
    final core = _byName(
      _scope(['packages/dart/codelab_agent_core/prompts/system.md']),
    );
    final dependency = _byName(
      _scope(['packages/dart/codelab_util/lib/a.dart']),
    );

    expect(core['guard']!.scripts, 'guard prompts:check');
    expect(core.keys, contains('web-compile'));
    expect(dependency.keys, contains('web-compile'));
    expect(dependency['guard']!.scripts, 'guard');
  });

  test('web-compile runs when any web-smoke package or its dependency '
      'changes: the embedded agent and the setup bridge too', () {
    for (final file in [
      'packages/dart/codelab_embedded/lib/a.dart',
      'packages/dart/codelab_setup/lib/a.dart',
      // Зависимость только моста встроенного агента, не ядра.
      'packages/dart/codelab_agent_acp/lib/a.dart',
      // Зависимость только моста настроек, не ядра.
      'packages/dart/codelab_agent_io/lib/a.dart',
    ]) {
      final jobs = _byName(_scope([file]));

      expect(jobs.keys, contains('web-compile'), reason: file);
      expect(jobs['guard']!.scripts, 'guard', reason: file);
    }
  });

  test('web-compile does not run for a package no web-smoke entry point '
      'compiles', () {
    for (final file in [
      'apps/codelab_cli/lib/a.dart',
      'apps/codelab_agent/bin/a.dart',
      'packages/flutter/codelab_ui/lib/a.dart',
    ]) {
      expect(
        _byName(_scope([file])).keys,
        isNot(contains('web-compile')),
        reason: file,
      );
    }
  });

  test('web-compile follows only what the entry points compile: dev '
      'dependencies of the web-smoke packages themselves, not of their '
      'dependencies', () {
    final packages = readWorkspace(repoRoot());
    bool web(String dir) => ciScope(
      packages: packages,
      changedFiles: ['$dir/lib/a.dart'],
    ).jobs.any((job) => job.job == 'web-compile');

    // dev-зависимость codelab_embedded: её импортирует точка входа и замер.
    expect(web('packages/dart/codelab_client_core'), isTrue);
    // dev-зависимость только codelab_agent_acp и клиентских пакетов.
    expect(web('packages/dart/codelab_acp_testing'), isFalse);
    expect(web('packages/dart/codelab_client_io'), isFalse);
    expect(web('packages/dart/codelab_agent_mcp'), isTrue);
  });

  test('web-smoke packages match the entry points the web-compile script '
      'compiles', () {
    final root = repoRoot();
    final onDisk = {
      for (final pkg in readWorkspace(root))
        if (File(
          p.join(root, pkg.dir, 'test', 'web_smoke', 'main.dart'),
        ).existsSync())
          pkg.name,
    };
    final pubspec = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
    // Только строки после `run:` скрипта: путь из `description:` не
    // доказывает, что точка компилируется.
    final script = RegExp(
      r'^    web-compile:\n(?:      (?!run:).*\n)*      run: >-\n((?:        .*\n|\n)+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      script,
      isNotNull,
      reason: 'web-compile script with a folded run: not found in pubspec.yaml',
    );
    final compiled = {
      for (final match in RegExp(
        r'packages/dart/(\w+)/test/web_smoke/main\.dart',
      ).allMatches(script![1]!))
        match[1]!,
    };

    expect(webSmokePackages, onDisk);
    expect(webSmokePackages, compiled);
  });

  test('l10n:check runs when a catalog or generated localization code of '
      'the app or the kit changes (change add-desktop-localization, D3)', () {
    for (final file in [
      'apps/codelab_desktop/lib/l10n/app_en.arb',
      'apps/codelab_desktop/lib/l10n/app_ru.arb',
      'apps/codelab_desktop/l10n.yaml',
      'apps/codelab_desktop/lib/l10n/app_localizations_ru.dart',
      'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_en.arb',
      'packages/flutter/codelab_ui/l10n.yaml',
      // `generate`, `flutter_localizations` и `intl` задают генерацию.
      'apps/codelab_desktop/pubspec.yaml',
      'packages/flutter/codelab_ui/pubspec.yaml',
      'packages/flutter/codelab_ui/lib/src/l10n/codelab_localizations.dart',
    ]) {
      final jobs = _byName(_scope([file]));

      expect(jobs['l10n']?.scripts, 'l10n:check', reason: file);
    }
  });

  test('l10n:check does not run for ordinary code', () {
    expect(
      _byName(_scope(['apps/codelab_desktop/lib/a.dart'])).keys,
      isNot(contains('l10n')),
    );
    expect(
      _byName(_scope(['packages/dart/codelab_acp_protocol/lib/a.dart'])).keys,
      isNot(contains('l10n')),
    );
  });

  test('a change of the l10n:check script runs everything with l10n:check', () {
    final scope = _scope(['tool/l10n_check.dart']);

    expect(scope.full, isTrue);
    expect(_byName(scope)['l10n']?.scripts, 'l10n:check');
  });

  test('the full run has the l10n job of the check script', () {
    expect(
      {for (final job in fullJobs) job.job: job}['l10n']?.scripts,
      'l10n:check',
    );
  });

  // Второе измерение охвата — джоб сайта (change add-astro-site, D13;
  // project-site «Проверка сайта в CI»). Признак `site` не меняет
  // Dart-матрицу: те же файлы дают те же джобы, что и до change.
  group('site (add-astro-site, D13)', () {
    List<Map<String, String>> matrix(CiScope scope) => [
      for (final job in scope.jobs) job.toJson(),
    ];

    test('только файлы site/ запускают сайт без Dart-джобов: они не '
        '«вне пакетов»', () {
      for (final files in [
        ['site/src/pages/index.astro'],
        ['site/.nvmrc'],
        ['site/package-lock.json'],
      ]) {
        final scope = _scope(files);

        expect(scope.site, isTrue, reason: '$files');
        expect(scope.full, isFalse, reason: '$files');
        expect(scope.jobs, isEmpty, reason: '$files');
      }
    });

    test('опубликованная документация docs/ запускает сайт без '
        'Dart-джобов', () {
      final scope = _scope(['docs/user/configuration.md']);

      expect(scope.site, isTrue);
      expect(scope.full, isFalse);
      expect(scope.jobs, isEmpty);
    });

    test('doc/ приложения запускает сайт, а Dart-матрица прежняя — '
        'это файл пакета codelab_cli', () {
      final scope = _scope(['apps/codelab_cli/doc/user-guide.md']);
      // Та же матрица, что у правки кода того же пакета: классификация
      // `apps/*/doc/**` для Dart-джобов не меняется.
      final code = _scope(['apps/codelab_cli/lib/a.dart']);

      expect(scope.site, isTrue);
      expect(scope.full, isFalse);
      expect(scope.changed, {'codelab_cli'});
      expect(matrix(scope), matrix(code));
      expect(matrix(scope), isNotEmpty);
    });

    test('README.md пакета запускает сайт без Dart-джобов', () {
      final scope = _scope(['packages/dart/codelab_setup/README.md']);

      expect(scope.site, isTrue);
      expect(scope.full, isFalse);
      expect(scope.jobs, isEmpty);
    });

    test('README.md приложения запускает сайт без Dart-джобов: это '
        'документация, а не файл кода приложения', () {
      final scope = _scope(['apps/codelab_cli/README.md']);

      expect(scope.site, isTrue);
      expect(scope.full, isFalse);
      expect(scope.changed, isEmpty);
      expect(scope.jobs, isEmpty);
    });

    test('код пакета без документации не запускает сайт, матрица '
        'прежняя', () {
      final scope = _scope([
        'packages/dart/codelab_agent_core/lib/src/loop.dart',
      ]);
      final jobs = _byName(scope);

      expect(scope.site, isFalse);
      expect(scope.full, isFalse);
      expect(jobs.keys, [
        'format',
        'analyze',
        'test',
        'conformance',
        'guard',
        'web-compile',
        'e2e-cli-dart',
        'e2e-cli-embedded',
      ]);
      expect(jobs['guard']!.scripts, 'guard prompts:check');
    });

    test('openspec/ запускает сайт без Dart-джобов, в том числе перенос '
        'change в архив (D13, ответ на Q6)', () {
      for (final files in [
        ['openspec/specs/x/spec.md'],
        [
          'openspec/changes/add-x/proposal.md',
          'openspec/changes/archive/2026-11-18-add-x/proposal.md',
        ],
      ]) {
        final scope = _scope(files);

        expect(scope.site, isTrue, reason: '$files');
        expect(scope.full, isFalse, reason: '$files');
        expect(scope.jobs, isEmpty, reason: '$files');
      }
    });

    test('.claude/ и корневой CHANGELOG.md не запускают ни сайт, ни '
        'Dart-джобы', () {
      for (final file in ['.claude/agents/x.md', 'CHANGELOG.md']) {
        final scope = _scope([file]);

        expect(scope.site, isFalse, reason: file);
        expect(scope.full, isFalse, reason: file);
        expect(scope.jobs, isEmpty, reason: file);
      }
    });

    // Источники строк витрины (change redesign-site-showcase, D6; project-site
    // «Проверка сайта в CI»). Список файлов здесь повторяет `scopePatterns` в
    // `site/test/ci-scope-sync.test.ts`: правка одного списка без другого
    // ломает тот или другой тест.
    test('каталог локализации запускает сайт, а Dart-матрица прежняя '
        '(redesign-site-showcase, D6)', () {
      for (final file in [
        'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb',
        'apps/codelab_desktop/lib/l10n/app_ru.arb',
      ]) {
        final scope = _scope([file]);
        final owner = file.startsWith('apps/')
            ? 'codelab_desktop'
            : 'codelab_ui';

        expect(scope.site, isTrue, reason: file);
        expect(scope.full, isFalse, reason: file);
        expect(scope.changed, {owner}, reason: file);
        expect(_byName(scope)['l10n']?.scripts, 'l10n:check', reason: file);
      }
    });

    test('бренд docs/design/brand/ запускает сайт без Dart-джобов '
        '(redesign-site-showcase, D6)', () {
      final scope = _scope(['docs/design/brand/codelab-logo.svg']);

      expect(scope.site, isTrue);
      expect(scope.full, isFalse);
      expect(scope.jobs, isEmpty);
    });

    test('виджет codelab_ui вне каталога локализации не запускает сайт '
        '(redesign-site-showcase, D6)', () {
      final scope = _scope([
        'packages/flutter/codelab_ui/lib/src/widgets/x.dart',
      ]);

      expect(scope.site, isFalse);
      expect(scope.full, isFalse);
    });

    test('остальные файлы локализации пакетов не запускают сайт '
        '(redesign-site-showcase, D6; project-site «Проверка сайта в CI»)', () {
      // `pubspec.yaml` и `l10n.yaml` не служат источниками строк витрины:
      // с ними джоб `site` шёл бы на каждую правку зависимостей этих пакетов.
      for (final file in [
        'packages/flutter/codelab_ui/pubspec.yaml',
        'apps/codelab_desktop/l10n.yaml',
      ]) {
        final scope = _scope([file]);

        expect(scope.site, isFalse, reason: file);
        expect(scope.full, isFalse, reason: file);
      }
    });

    test('полный прогон всегда включает сайт', () {
      final explicit = _scope(['docs/x.md'], fullReason: 'push to develop');
      final outside = _scope(['.github/workflows/ci.yml']);

      for (final scope in [explicit, outside]) {
        expect(scope.full, isTrue);
        expect(scope.site, isTrue);
        expect(scope.jobs.map((j) => j.job), fullJobs.map((j) => j.job));
      }
    });
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
    expect(package.runtimeDependencies, {
      'codelab_client_core',
      'codelab_acp_testing',
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

  // Требование «Проверки workspace», сценарий «Полный прогон CI совпадает с
  // check» (change align-cross-cutting-specs, задача 3.1).
  test('Полный прогон CI совпадает с check', () {
    final lines = File(p.join(repoRoot(), 'pubspec.yaml')).readAsLinesSync();
    // Строковый разбор без пакета yaml: блок `    check:` секции melos,
    // внутри него `steps:` и элементы списка `- шаг`.
    final checkAt = lines.indexOf('    check:');
    expect(checkAt, isNonNegative, reason: 'скрипт check не найден');
    final stepsAt = lines.indexOf('      steps:', checkAt);
    expect(stepsAt, greaterThan(checkAt));
    final steps = <String>{};
    for (var i = stepsAt + 1; i < lines.length; i++) {
      final match = RegExp(r'^\s+-\s+(\S+)\s*$').firstMatch(lines[i]);
      if (match == null) break;
      steps.add(match.group(1)!);
    }
    expect(steps, isNotEmpty);

    final ciScripts = {for (final job in fullJobs) ...job.scripts.split(' ')};
    expect(ciScripts, steps);
    expect(
      ciScripts.where(
        (s) =>
            s.startsWith('test:e2e:app:') || s == 'test:e2e:cli:python-agent',
      ),
      isEmpty,
    );
  });

  // Требование «Непрерывная интеграция», сценарий «Джобов на macOS нет»
  // (задача 3.3).
  test('Джобов на macOS нет', () {
    final lines = File(
      p.join(repoRoot(), '.github', 'workflows', 'ci.yml'),
    ).readAsLinesSync();
    final runsOn = <String>[];
    for (final line in lines) {
      final match = RegExp(r'^\s*runs-on:\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      final value = match.group(1)!.split('#').first.trim();
      if (value.isNotEmpty) runsOn.add(value);
    }
    expect(
      runsOn.every((v) => v == 'ubuntu-latest'),
      isTrue,
      reason: '$runsOn',
    );

    // Джобы — ключи с отступом в два пробела внутри секции `jobs:`.
    final jobsAt = lines.indexOf('jobs:');
    expect(jobsAt, isNonNegative);
    final jobs = <String>{};
    for (var i = jobsAt + 1; i < lines.length; i++) {
      final match = RegExp(r'^  ([a-z][\w-]*):\s*$').firstMatch(lines[i]);
      if (match != null) jobs.add(match.group(1)!);
    }
    expect(jobs, containsAll(['scope', 'checks', 'site', 'parity', 'ci']));
    expect(runsOn.length, greaterThanOrEqualTo(5));
  });
}
