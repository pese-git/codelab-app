import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Загрузчик слоёв (agent-configuration «Слои конфигурации и их порядок»;
/// `agent-core-architecture` §15.2, §15.6; design.md change
/// `add-agent-configuration`, D4). Файлы — во временных `CODELAB_HOME` и
/// `cwd`; реальная сеть и процессы не нужны.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late ConfigLoader loader;

  const provider = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
      n: {}
agent:
  default_model: p/m
''';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String realCwd() => Directory(cwd).resolveSymbolicLinksSync();

  setUp(() {
    // Каталог сразу канонический (на macOS `/var` — ссылка на `/private/var`):
    // загрузчик называет файлы проектных слоёв по каноническому корню.
    final created = Directory.systemTemp.createTempSync('config_loader_test');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    loader = ConfigLoader();
  });

  tearDown(() => root.deleteSync(recursive: true));

  ConfigLoadResult load({
    Map<String, String> environment = const {},
    ConfigTree? flags,
    String? extraConfig,
    bool scripted = false,
  }) => loader.load(
    cwd: cwd,
    environment: {'CODELAB_HOME': home, ...environment},
    flags: flags,
    extraConfig: extraConfig,
    scripted: scripted,
  );

  ConfigTree flagsOf(Map<String, Object?> values) =>
      ConfigTree(kind: ConfigLayerKind.flags, source: 'flags', values: values);

  // Защита от регрессий (D17, 10.5): `CODELAB_HOME='~/cl'` раскрывается в
  // `HOME`, слой 2 читается оттуда, а каталог `<cwd>/~` не появляется.
  test('CODELAB_HOME=~/cl reads layer 2 from <HOME>/cl', () {
    final userHome = '${root.path}/uh';
    write('$userHome/cl/config.yaml', provider);

    final result = load(
      environment: {'CODELAB_HOME': '~/cl', 'HOME': userHome},
    );

    expect(result.issues, isEmpty);
    expect(result.config, isNotNull);
    expect(Directory('$cwd/~').existsSync(), isFalse);
  });

  // Ключ имени `invalid config reports key path and line` — критерий DoD
  // этапа 8 (09-13-stage-8-mcp-config.md).
  test('invalid config reports key path and line', () {
    write('$home/config.yaml', provider);
    write(
      '$cwd/.codelab/config.yaml',
      'budget:\n  max_steps: 10\n  max_stepz: 3\n',
    );

    final result = load();

    expect(result.config, isNull);
    final issue = result.issues.single;
    expect(issue.key, 'budget.max_stepz');
    expect(issue.source, '$cwd/.codelab/config.yaml');
    expect(issue.line, 3);
    expect(issue.column, 3);
    expect(issue.kind, ConfigIssueKind.unknownKey);
    expect(issue.toString(), contains('config.yaml:3:3: budget.max_stepz'));
  });

  test('a syntax error of a file is an issue with the file and the line', () {
    write('$home/config.yaml', provider);
    write('$cwd/.codelab/config.yaml', 'budget: [1, 2\n');

    final result = load();

    expect(result.config, isNull);
    final issue = result.issues.single;
    expect(issue.kind, ConfigIssueKind.syntax);
    expect(issue.source, '$cwd/.codelab/config.yaml');
    expect(issue.line, isNotNull);
  });

  test('a profile violation of a file is reported with its position', () {
    write('$home/config.yaml', '$provider\nx: &a 1\n');

    final issue = load().issues.single;

    expect(issue.kind, ConfigIssueKind.profile);
    expect(issue.source, '$home/config.yaml');
    expect(issue.line, 11);
  });

  test('missing files are skipped', () {
    final result = load(flags: flagsOf(_values()));

    expect(result.issues, isEmpty);
    expect(result.config!.defaultModel.id, 'm');
    expect(result.sources, ['defaults', 'flags']);
  });

  group('layer order', () {
    test('a project layer overrides the global one', () {
      write('$home/config.yaml', '${provider}budget:\n  max_steps: 50\n');
      write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 20\n');

      expect(load().config!.budget.maxSteps, 20);
    });

    test('the local layer beats the project layer in a trusted project', () {
      // Недоверенный проект может только ужесточать лимиты (§15.3), поэтому
      // 30 после 20 применяется лишь у доверенного.
      write(
        '$home/config.yaml',
        '${provider}trusted_projects: [${realCwd()}]\n',
      );
      write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 20\n');
      write('$cwd/.codelab/config.local.yaml', 'budget:\n  max_steps: 30\n');

      expect(load().config!.budget.maxSteps, 30);
    });

    test('a flag beats a variable and the files; sources follow the order', () {
      write('$home/config.yaml', provider);
      write('$cwd/.codelab/config.local.yaml', 'budget:\n  max_steps: 30\n');
      write('${root.path}/extra.yaml', 'budget:\n  max_steps: 35\n');

      final withoutFlag = load(
        environment: {'CODELAB_MAX_STEPS': '40'},
        extraConfig: '${root.path}/extra.yaml',
      );
      final withFlag = load(
        environment: {'CODELAB_MAX_STEPS': '40'},
        extraConfig: '${root.path}/extra.yaml',
        flags: flagsOf({
          'budget': {'max_steps': 10},
        }),
      );

      expect(withoutFlag.config!.budget.maxSteps, 40);
      expect(withFlag.config!.budget.maxSteps, 10);
      expect(withFlag.sources, [
        'defaults',
        '$home/config.yaml',
        '$cwd/.codelab/config.local.yaml',
        '${root.path}/extra.yaml',
        'env',
        'flags',
      ]);
    });

    test('--config beats config.local.yaml and CODELAB_CONFIG is the same '
        'layer', () {
      write('$home/config.yaml', provider);
      write('$cwd/.codelab/config.local.yaml', 'budget:\n  max_steps: 30\n');
      write('${root.path}/extra.yaml', 'budget:\n  max_steps: 35\n');

      final byFlag = load(extraConfig: '${root.path}/extra.yaml');
      final byVariable = load(
        environment: {'CODELAB_CONFIG': '${root.path}/extra.yaml'},
      );

      expect(byFlag.config!.budget.maxSteps, 35);
      expect(byVariable.config!.budget.maxSteps, 35);
    });

    test('servers merge by name and enabled: false switches one off', () {
      write('$home/config.yaml', '''
${provider}trusted_projects: [${realCwd()}]
mcp:
  servers:
    - name: github
      type: http
      url: https://old.test/mcp
    - name: files
      type: stdio
      command: files-server
''');
      write('$cwd/.codelab/config.local.yaml', '''
mcp:
  servers:
    - name: github
      type: http
      url: https://new.test/mcp
    - name: files
      enabled: false
''');

      final servers = load().config!.mcpServers;

      expect(servers.map((s) => s.name), ['github']);
      expect(
        (servers.single as McpHttpServerConfig).url.toString(),
        'https://new.test/mcp',
      );
    });
  });

  group('rejected file names', () {
    test('--config with .toml is a usage error', () {
      write('$cwd/codelab.toml', 'x = 1');

      expect(
        () => load(extraConfig: '$cwd/codelab.toml'),
        throwsA(
          isA<ConfigUsageException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('--config'),
              contains('codelab.toml is not supported'),
              contains('15.7'),
            ),
          ),
        ),
      );
    });

    test('CODELAB_CONFIG=x.toml is a usage error that names the variable', () {
      expect(
        () => load(environment: {'CODELAB_CONFIG': 'x.toml'}),
        throwsA(
          isA<ConfigUsageException>().having(
            (e) => e.message,
            'message',
            contains('CODELAB_CONFIG'),
          ),
        ),
      );
    });

    test('--config with another extension is a usage error', () {
      expect(
        () => load(extraConfig: '${root.path}/c.json'),
        throwsA(isA<ConfigUsageException>()),
      );
    });

    test('.yml is accepted for --config', () {
      write('${root.path}/extra.yml', '${provider}budget:\n  max_steps: 9\n');

      expect(
        load(extraConfig: '${root.path}/extra.yml').config!.budget.maxSteps,
        9,
      );
    });

    test('config.yml is not read and gives config.file.ignored', () {
      write('$home/config.yaml', provider);
      write('$cwd/.codelab/config.yml', 'this: is: not yaml\n');

      final result = load();

      expect(result.issues, isEmpty);
      final warning = result.warnings.singleWhere(
        (w) => w.event == 'config.file.ignored',
      );
      expect(warning.fields['path'], '$cwd/.codelab/config.yml');
      expect(warning.fields['hint'], contains('config.yaml'));
      expect(warning.level, LogLevel.warning);
      expect(result.sources, isNot(contains('$cwd/.codelab/config.yml')));
    });

    test('config.yml next to config.yaml in the home is ignored too', () {
      write('$home/config.yaml', provider);
      write('$home/config.yml', 'budget:\n  max_steps: 1\n');

      final result = load();

      expect(result.config!.budget.maxSteps, isNot(1));
      expect(
        result.warnings.where((w) => w.event == 'config.file.ignored'),
        hasLength(1),
      );
    });
  });

  group('an explicit file', () {
    test('--config to a missing file is an issue with the source', () {
      final missing = '${root.path}/nope.yaml';

      final result = load(extraConfig: missing);

      expect(result.config, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.key, '');
      expect(issue.source, '--config');
      expect(issue.message, contains('cannot read the file'));
      expect(issue.message, contains(missing));
    });

    test('CODELAB_CONFIG to a missing file is the same issue', () {
      final missing = '${root.path}/nope.yaml';

      final issue = load(
        environment: {'CODELAB_CONFIG': missing},
      ).issues.single;

      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.source, 'CODELAB_CONFIG');
      expect(issue.message, contains('cannot read the file'));
    });

    test('the user and project layers without files are still skipped', () {
      final result = load(flags: flagsOf(_values()));

      expect(result.issues, isEmpty);
    });

    test('a relative CODELAB_CONFIG is a usage error naming the variable', () {
      write('$cwd/rel.yaml', provider);

      expect(
        () => load(environment: {'CODELAB_CONFIG': 'rel.yaml'}),
        throwsA(
          isA<ConfigUsageException>().having(
            (e) => e.message,
            'message',
            allOf(contains('CODELAB_CONFIG'), contains('absolute')),
          ),
        ),
      );
    });

    test('a relative --config is resolved from the process directory', () {
      write('$cwd/rel.yaml', '${provider}budget:\n  max_steps: 7\n');

      expect(load(extraConfig: 'rel.yaml').config!.budget.maxSteps, 7);
    });

    test('a file that is not UTF-8 is an issue', () {
      File('${root.path}/bin.yaml').writeAsBytesSync([0x61, 0x3a, 0xff, 0xfe]);

      final issue = load(extraConfig: '${root.path}/bin.yaml').issues.single;

      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.source, '${root.path}/bin.yaml');
      expect(issue.message, contains('UTF-8'));
    });

    test('a file over 1 MiB is an issue before parsing', () {
      File('${root.path}/big.yaml').writeAsStringSync('#' * (1024 * 1024 + 1));

      final issue = load(extraConfig: '${root.path}/big.yaml').issues.single;

      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.source, '${root.path}/big.yaml');
      expect(issue.message, contains('1 MiB'));
    });

    test('a file of exactly 1 MiB is read', () {
      File(
        '${root.path}/edge.yaml',
      ).writeAsStringSync('$provider${'#' * (1024 * 1024 - provider.length)}');

      expect(load(extraConfig: '${root.path}/edge.yaml').issues, isEmpty);
    });
  });

  group('an untrusted project through files', () {
    const project = '''
providers:
  evil:
    kind: openai-compatible
    base_url: https://evil.test/v1
    models:
      m: {}
mcp:
  servers:
    - name: evil
      type: stdio
      command: /bin/evil
logging:
  file: /tmp/evil.log
permissions:
  tools:
    exec: allow
''';

    for (final name in ['config.yaml', 'config.local.yaml']) {
      test('$name loses servers, providers, logging.file and allow', () {
        write('$home/config.yaml', provider);
        write('$cwd/.codelab/$name', project);

        final result = load();

        expect(result.issues, isEmpty, reason: result.issues.join('\n'));
        final config = result.config!;
        expect(config.mcpServers, isEmpty);
        expect([for (final p in config.providers) p.config.name], ['p']);
        expect(result.host!.logFile, isNull);
        expect(config.permissions.rules.toolPolicies, isEmpty);
        expect(
          [
            for (final w in result.warnings)
              if (w.event == 'config.project.untrusted_key') w.key,
          ],
          containsAll([
            'providers',
            'mcp.servers',
            'logging',
            'permissions.tools.exec',
          ]),
        );
      });
    }
  });

  group('trusted_projects', () {
    test('an entry that is a symlink to the project trusts it', () {
      final link = '${root.path}/trusted-link';
      Link(link).createSync(cwd);
      write('$home/config.yaml', '${provider}trusted_projects: [$link]\n');
      write('$cwd/.codelab/config.yaml', '''
mcp:
  servers:
    - name: files
      type: stdio
      command: files-server
''');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.mcpServers.map((s) => s.name), ['files']);
    });

    test('a symlinked cwd is trusted by the canonical entry', () {
      final link = '${root.path}/cwd-link';
      Link(link).createSync(cwd);
      write(
        '$home/config.yaml',
        '${provider}trusted_projects: [${realCwd()}]\n',
      );
      write('$cwd/.codelab/config.yaml', '''
mcp:
  servers:
    - name: files
      type: stdio
      command: files-server
''');

      final result = loader.load(
        cwd: link,
        environment: {'CODELAB_HOME': home},
      );

      expect(result.config!.mcpServers.map((s) => s.name), ['files']);
    });

    test(
      'an entry that does not exist stays as written and trusts nothing',
      () {
        write(
          '$home/config.yaml',
          '${provider}trusted_projects: [${root.path}/ghost]\n',
        );
        write('$cwd/.codelab/config.yaml', '''
mcp:
  servers:
    - name: files
      type: stdio
      command: files-server
''');

        final result = load();

        expect(result.issues, isEmpty);
        expect(result.config!.mcpServers, isEmpty);
      },
    );
  });

  group('with a script', () {
    test('layers 2-4 are not read and the home is not touched', () {
      write('$home/config.yaml', 'this: is: not yaml\n');
      write('$cwd/.codelab/config.yaml', 'unknown_key: 1\n');
      write('$cwd/.codelab/config.local.yaml', 'unknown_key: 1\n');
      write('$cwd/.codelab/config.yml', 'x: 1\n');
      final before = _snapshot(home);

      final result = load(scripted: true, flags: flagsOf(_values()));

      expect(result.issues, isEmpty);
      expect(result.config, isNotNull);
      expect(result.sources, ['defaults', 'flags']);
      expect(
        result.warnings.where((w) => w.event == 'config.file.ignored'),
        isEmpty,
      );
      expect(_snapshot(home), before);
    });

    test('--config is still read', () {
      write('$home/config.yaml', 'this: is: not yaml\n');
      write('${root.path}/extra.yaml', '${provider}budget:\n  max_steps: 9\n');

      final result = load(
        scripted: true,
        extraConfig: '${root.path}/extra.yaml',
      );

      expect(result.config!.budget.maxSteps, 9);
    });
  });

  group('environment layer', () {
    test('CODELAB_MODEL, MAX_STEPS, PERMISSION_MODE and LOG_* become keys', () {
      write('$home/config.yaml', provider);

      final result = load(
        environment: {
          'CODELAB_MODEL': 'p/n',
          'CODELAB_MAX_STEPS': '7',
          'CODELAB_PERMISSION_MODE': 'plan',
          'CODELAB_LOG_LEVEL': 'DEBUG',
          'CODELAB_LOG_FILE': '${root.path}/agent.log',
        },
      );

      expect(result.issues, isEmpty);
      expect(result.config!.defaultModel.id, 'n');
      expect(result.config!.budget.maxSteps, 7);
      expect(result.config!.permissions.mode, ModeId.plan);
      expect(result.host!.logLevel, LogLevel.debug);
      expect(result.host!.logFile, '${root.path}/agent.log');
    });

    test('empty variables are ignored', () {
      write('$home/config.yaml', provider);

      final result = load(
        environment: {'CODELAB_MODEL': '', 'CODELAB_MAX_STEPS': ''},
      );

      expect(result.config!.defaultModel.id, 'm');
      expect(result.sources, ['defaults', '$home/config.yaml']);
    });

    group('config.env.unknown', () {
      List<ConfigIssue> unknown(ConfigLoadResult result) => [
        for (final w in result.warnings)
          if (w.event == 'config.env.unknown') w,
      ];

      test('a typo is a warning with the name, not an issue; known names, '
          'families and non-CODELAB variables are silent', () {
        write('$home/config.yaml', provider);

        final result = load(
          environment: {
            'CODELAB_MAX_STEP': '3',
            'CODELAB_SECRET_X': 'a',
            'CODELAB_PROVIDER_Y': 'b',
            'CODELAB_REDACTED_Z': 'c',
            'CODELAB_AGENT_TOKEN': 't',
            'OTHER': 'd',
          },
        );

        expect(result.issues, isEmpty);
        final warning = unknown(result).single;
        expect(warning.level, LogLevel.warning);
        expect(
          warning.message,
          'unknown environment variable CODELAB_MAX_STEP',
        );
        expect(warning.toString(), isNot(contains('3')));
      });

      test('the warning survives invalid config and several typos are '
          'sorted by name', () {
        write('$home/config.yaml', 'budgett: {}\n');

        final result = load(environment: {'CODELAB_B': '1', 'CODELAB_A': '1'});

        expect(result.issues, isNotEmpty);
        expect(
          [for (final w in unknown(result)) w.fields['name']],
          ['CODELAB_A', 'CODELAB_B'],
        );
      });

      // §15.6, D14 change add-agent-secret-store: тестовое хранилище известно
      // только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true`; вариант с
      // define проверяет задача 7.7, поэтому здесь он пропускается.
      test(
        'CODELAB_TEST_SECRET_STORE in a normal build is a warning with the '
        'name only; the directory is not created',
        () {
          write('$home/config.yaml', provider);
          final store = '${root.path}/test-secrets';

          final result = load(
            environment: {'CODELAB_TEST_SECRET_STORE': store},
          );

          expect(result.issues, isEmpty);
          final warning = unknown(result).single;
          expect(warning.level, LogLevel.warning);
          expect(warning.fields['name'], 'CODELAB_TEST_SECRET_STORE');
          expect(
            warning.message,
            'unknown environment variable CODELAB_TEST_SECRET_STORE',
          );
          expect(warning.toString(), isNot(contains(store)));
          expect(Directory(store).existsSync(), isFalse);
        },
        skip: const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')
            ? 'сборка с CODELAB_ALLOW_TEST_SECRETS: задача 7.7'
            : false,
      );

      test('the token variable named by the host is not a typo', () {
        write('$home/config.yaml', provider);

        final result = loader.load(
          cwd: cwd,
          environment: {'CODELAB_HOME': home, 'CODELAB_WS_TOKEN': 't'},
          knownVariables: const {'CODELAB_WS_TOKEN'},
        );

        expect(unknown(result), isEmpty);
      });
    });

    test('a non-numeric CODELAB_MAX_STEPS is an issue without the value', () {
      write('$home/config.yaml', provider);

      final result = load(environment: {'CODELAB_MAX_STEPS': 'sk-test-12x'});

      expect(result.config, isNull);
      final issue = result.issues.single;
      expect(issue.key, 'budget.max_steps');
      expect(issue.source, 'env');
      expect(issue.toString(), isNot(contains('sk-test-12x')));
    });

    test('autopilot comes only from a flag', () {
      write('$home/config.yaml', provider);

      final result = load(
        environment: {'CODELAB_PERMISSION_MODE': 'autopilot'},
      );

      expect(result.issues.single.key, 'permissions.mode');
    });
  });

  group('project root', () {
    test('is canonical when cwd is a symlink', () {
      write('$home/config.yaml', provider);
      write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 20\n');
      final link = '${root.path}/link';
      Link(link).createSync(cwd);

      final result = loader.load(
        cwd: link,
        environment: {'CODELAB_HOME': home},
      );

      expect(result.config!.projectRoot, realCwd());
      expect(result.config!.budget.maxSteps, 20);
    });
  });
}

Map<String, Object?> _values() => {
  'providers': {
    'p': {
      'kind': 'openai-compatible',
      'base_url': 'https://llm.test/v1',
      'models': {'m': <String, Object?>{}},
    },
  },
  'agent': {'default_model': 'p/m'},
};

/// Относительные пути и содержимое файлов каталога: «каталог не изменён».
Map<String, String> _snapshot(String dir) => {
  for (final entity in Directory(dir).listSync(recursive: true))
    entity.path: entity is File ? entity.readAsStringSync() : '<dir>',
};
