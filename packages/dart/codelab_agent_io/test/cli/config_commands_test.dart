import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Подкоманда `config check` (agent-configuration «Подкоманда config check»;
/// design.md change `add-agent-configuration`, D13, D12). Общая реализация
/// `ConfigCommands` для `codelab-agent` и `codelab`: тексты и коды выхода.
void main() {
  late Directory root;
  late String home;
  late String cwd;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  const providers = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_commands');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ConfigCommandResult> check({
    Map<String, String> env = const {},
    String? at,
    ConfigCommands? commands,
  }) async => (commands ?? ConfigCommands()).check(
    CheckOptions(cwd: at ?? cwd, environment: {'CODELAB_HOME': home, ...env}),
  );

  /// Снимок всех сущностей каталога (файлы, каталоги, ссылки) с типом,
  /// размером и временем изменения: `check` ничего не пишет, не создаёт
  /// каталогов и не трогает существующие файлы.
  Map<String, String> snapshot() => {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      entity.path: () {
        final stat = entity.statSync();
        return '${stat.type} ${stat.size} ${stat.modified.toIso8601String()}';
      }(),
  };

  test('a valid config: Sources first, Config: valid last, code 0', () async {
    write('$home/config.yaml', providers);

    final result = await check();

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(result.stdout.first, startsWith('Sources:'));
    expect(result.stdout.first, contains('$home/config.yaml'));
    expect(result.stdout.last, 'Config: valid');
  });

  test(
    'a typo: file:line:column, key, message; invalid (issues: 1); code 1',
    () async {
      write(
        '$cwd/.codelab/config.yaml',
        '${providers}budget:\n  max_stepz: 3\n',
      );

      final result = await check();

      expect(result.exitCode, 1);
      final line = result.stdout.singleWhere((l) => l.contains('max_stepz'));
      expect(line, startsWith('$cwd/.codelab/config.yaml:'));
      expect(
        line,
        matches(RegExp(r'config\.yaml:\d+:\d+: budget\.max_stepz: ')),
      );
      expect(line, contains('did you mean max_steps?'));
      expect(result.stdout.last, 'Config: invalid (issues: 1)');
    },
  );

  test('a syntax error is reported without a position crash', () async {
    write('$home/config.yaml', 'providers: [unclosed\n');

    final result = await check();

    expect(result.exitCode, 1);
    expect(result.stdout.last, startsWith('Config: invalid (issues: '));
  });

  test('codelab.toml alone: a warning line, the path once, and the only '
      'issue is the missing default model (code 1)', () async {
    write('$cwd/codelab.toml', 'x = 1\n');

    // YAML-слоёв нет, поэтому единственная проблема — нет модели по
    // умолчанию. Предупреждение о `codelab.toml` (D12) проблемой не
    // считается и в счётчик не входит.
    final result = await check();

    expect(result.exitCode, 1, reason: result.stdout.join('\n'));
    final line = result.stdout.singleWhere(
      (l) => l.startsWith('warning: ') && l.contains('codelab.toml'),
    );
    expect(line, startsWith('warning: $cwd/codelab.toml: '));
    expect(
      '$cwd/codelab.toml'.allMatches(line),
      hasLength(1),
      reason: 'the path is already the location of the line: $line',
    );
    expect(result.stdout.last, 'Config: invalid (issues: 1)');
  });

  test('several legacy files: the first is the location, the others are '
      'named in the text', () async {
    write('$cwd/codelab.toml', 'x = 1\n');
    write('$cwd/codelab.local.toml', 'x = 1\n');

    final result = await check();

    final line = result.stdout.singleWhere((l) => l.startsWith('warning: '));
    expect(line, startsWith('warning: $cwd/codelab.toml: '));
    expect('$cwd/codelab.toml'.allMatches(line), hasLength(1));
    expect(line, contains('$cwd/codelab.local.toml'));
  });

  test('an unknown CODELAB_* variable is a warning line; the config stays '
      'valid (config.env.unknown)', () async {
    write('$home/config.yaml', providers);

    final result = await check(env: {'CODELAB_MAX_STEP': '3'});

    expect(result.exitCode, 0, reason: result.stdout.join('\n'));
    expect(
      result.stdout,
      contains(allOf(startsWith('warning: '), contains('CODELAB_MAX_STEP'))),
    );
    expect(result.stdout.last, 'Config: valid');
  });

  test(
    'CODELAB_TEST_SECRET_STORE in a regular build: a warning naming the '
    'variable, not the path; the directory is not created; the config stays '
    'valid (config.env.unknown, §12.4.13)',
    () async {
      write('$home/config.yaml', providers);
      final store = '${root.path}/secret-store';

      final result = await check(env: {'CODELAB_TEST_SECRET_STORE': store});

      expect(result.exitCode, 0, reason: result.stdout.join('\n'));
      final warning = result.stdout.singleWhere(
        (l) => l.startsWith('warning: '),
      );
      expect(warning, contains('CODELAB_TEST_SECRET_STORE'));
      expect(result.stdout.join('\n'), isNot(contains(store)));
      expect(result.stdout.last, 'Config: valid');
      expect(Directory(store).existsSync(), isFalse);
    },
    skip: const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')
        ? 'сборка с CODELAB_ALLOW_TEST_SECRETS: задача 7.7'
        : false,
  );

  test(
    'config.yml next to nothing: warning line, config stays valid',
    () async {
      write('$home/config.yaml', providers);
      write('$cwd/.codelab/config.yml', 'x: 1\n');

      final result = await check();

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(startsWith('warning: $cwd/.codelab/config.yml: ignored')),
      );
      expect(result.stdout.last, 'Config: valid');
    },
  );

  test('check writes nothing', () async {
    write('$home/config.yaml', providers);
    write('$cwd/codelab.toml', 'x');
    final before = snapshot();

    await check();

    expect(snapshot(), before);
    expect(Directory('$home/logs').existsSync(), isFalse);
  });

  test('an inline secret never reaches the output', () async {
    write(
      '$home/config.yaml',
      providers.replaceFirst(
        'kind: openai-compatible',
        'kind: openai-compatible\n    api_key: sk-test-secret',
      ),
    );

    final result = await check();

    expect(result.exitCode, 1);
    final all = [...result.stdout, ...result.stderr].join('\n');
    expect(all, contains('providers.p.api_key'));
    expect(all, isNot(contains('sk-test-secret')));
  });

  test('an env var holding a secret value is not printed', () async {
    write('$home/config.yaml', providers);

    final result = await check(env: {'CODELAB_API_KEY': 'sk-test-secret'});

    final all = [...result.stdout, ...result.stderr].join('\n');
    expect(all, isNot(contains('sk-test-secret')));
  });

  test(
    'a bad CODELAB_CONFIG file name is a usage error: code 64, stderr',
    () async {
      final result = await check(env: {'CODELAB_CONFIG': '/x/codelab.toml'});

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr.join('\n'), contains('codelab.toml'));
    },
  );

  test('a missing cwd is a usage error: code 64', () async {
    final result = await ConfigCommands().check(
      CheckOptions(
        cwd: '${root.path}/nope',
        environment: {'CODELAB_HOME': home},
      ),
    );

    expect(result.exitCode, 64);
    expect(result.stderr.join('\n'), contains('${root.path}/nope'));
  });

  group('output safety', () {
    String all(ConfigCommandResult r) => [...r.stdout, ...r.stderr].join('\n');

    test('header and env substitutions never reach the output, also when '
        'the same server has a problem', () async {
      write(
        '$home/config.yaml',
        '$providers'
            'mcp:\n'
            '  servers:\n'
            '    - name: gh\n'
            '      type: http\n'
            '      url: https://gh.test/mcp\n'
            '      connect_timeout: nonsense\n'
            '      headers:\n'
            r'        Authorization: "Bearer ${TOKEN}"'
            '\n'
            '    - name: local\n'
            '      type: stdio\n'
            '      command: srv\n'
            '      env:\n'
            r'        K: ${VAR}'
            '\n'
            r'        L: ${MISSING}'
            '\n',
      );

      final result = await check(
        env: {'TOKEN': 'tok-test-secret', 'VAR': 'var-test-secret'},
      );

      expect(result.exitCode, 1, reason: all(result));
      expect(all(result), contains('mcp.servers'));
      expect(all(result), isNot(contains('tok-test-secret')));
      expect(all(result), isNot(contains('var-test-secret')));
    });

    test(
      'a valid server with substitutions prints nothing of the values',
      () async {
        write(
          '$home/config.yaml',
          '$providers'
              'mcp:\n'
              '  servers:\n'
              '    - name: gh\n'
              '      type: http\n'
              '      url: https://gh.test/mcp\n'
              '      headers:\n'
              r'        Authorization: "Bearer ${TOKEN}"'
              '\n',
        );

        final result = await check(env: {'TOKEN': 'tok-test-secret'});

        expect(result.exitCode, 0, reason: all(result));
        expect(all(result), isNot(contains('tok-test-secret')));
      },
    );

    test('a secret written into api_key_env is not echoed', () async {
      write(
        '$home/config.yaml',
        providers.replaceFirst(
          'kind: openai-compatible',
          'kind: openai-compatible\n    api_key_env: sk-test-secret-123',
        ),
      );

      final result = await check();

      expect(result.exitCode, 1, reason: all(result));
      expect(all(result), isNot(contains('sk-test-secret-123')));
    });

    test('CODELAB_AGENT_TOKEN in the environment is not printed', () async {
      write('$home/config.yaml', providers);

      final result = await check(
        env: {'CODELAB_AGENT_TOKEN': 'agent-test-token'},
      );

      expect(result.exitCode, 0, reason: all(result));
      expect(all(result), isNot(contains('agent-test-token')));
    });

    test('an untrusted project cannot add providers or mcp servers: warning '
        'lines, keys not accepted', () async {
      write('$home/config.yaml', providers);
      write(
        '$cwd/.codelab/config.yaml',
        'providers:\n'
            '  evil:\n'
            '    kind: openai-compatible\n'
            '    base_url: https://evil.test/v1\n'
            '    models:\n'
            '      m: {}\n'
            'mcp:\n'
            '  servers:\n'
            '    - name: evil\n'
            '      type: stdio\n'
            '      command: evil\n',
      );

      final result = await check();

      expect(result.exitCode, 0, reason: all(result));
      for (final key in ['providers', 'mcp.servers']) {
        expect(
          result.stdout,
          contains(
            allOf(
              startsWith('warning: $cwd/.codelab/config.yaml:'),
              contains(': $key: ignored: the project is not trusted'),
            ),
          ),
          reason: all(result),
        );
      }
      expect(result.stdout.last, 'Config: valid');
    });
  });

  // Диагностика файлов проекта в `config check` (agent-configuration «config
  // check показывает диагностику файлов проекта»; design.md change
  // `add-agent-project-files`, D13).
  group('project files (D13)', () {
    /// Валидный глобальный конфиг; [trusted] добавляет `cwd` в доверенные.
    void validConfig({bool trusted = false}) => write(
      '$home/config.yaml',
      '$providers${trusted ? 'trusted_projects:\n  - $cwd\n' : ''}',
    );

    const badAgent =
        '---\nname: reviewer\ndescription: Reviews\ncolor: red\n---\n'
        'secret body sk-test-secret\n';

    test('a broken agent definition: a warning with path, line and column; '
        'Config: valid; code 0', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/agents/reviewer.md', badAgent);

      final result = await check();

      expect(result.exitCode, 0, reason: result.stdout.join('\n'));
      expect(
        result.stdout,
        contains(
          matches(
            RegExp(
              '^warning: ${RegExp.escape(cwd)}/\\.codelab/agents/reviewer\\.md'
              r':4:1: unknown frontmatter key',
            ),
          ),
        ),
      );
      // Имя ключа во фрагмент файла не входит (D14): в строке нет `color`.
      expect(
        result.stdout.singleWhere((l) => l.contains('reviewer.md')),
        isNot(contains('color')),
      );
      expect(result.stdout.last, 'Config: valid');
      expect(result.stderr, isEmpty);
    });

    test('a broken template in the user area is reported by the same '
        'format', () async {
      validConfig();
      write('$home/prompts/Review.md', 'Do the review\n');

      final result = await check();

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          allOf(
            startsWith('warning: $home/prompts/Review.md: '),
            contains('not a valid command name'),
          ),
        ),
      );
      expect(result.stdout.last, 'Config: valid');
    });

    // Защита от регрессий (D17, 10.5): `CODELAB_HOME='~/cl'` раскрывается, и
    // пользовательская область файлов проекта читается из `<HOME>/cl`.
    test('CODELAB_HOME=~/cl: the user area is read from <HOME>/cl', () async {
      validConfig();
      final userHome = '${root.path}/uh';
      write('$userHome/cl/prompts/Review.md', 'Do the review\n');
      write('$userHome/cl/config.yaml', providers);

      final result = await check(
        env: {'CODELAB_HOME': '~/cl', 'HOME': userHome},
      );

      expect(
        result.stdout,
        contains(startsWith('warning: $userHome/cl/prompts/Review.md: ')),
      );
      expect(
        result.stdout.where((l) => l.contains('could not be read')),
        isEmpty,
      );
    });

    /// Положительный контроль отрицательных тестов: битый шаблон
    /// пользователя всегда даёт свою строку `warning:`. Без него «нет такой
    /// строки» совпало бы с тем, что `check` вообще не печатает диагностику.
    const control = 'warning: ';
    void brokenUserTemplate() =>
        write('$home/prompts/Bad Name.md', 'Do the review\n');
    void expectControl(ConfigCommandResult result) => expect(
      result.stdout.where(
        (l) => l.startsWith('$control$home/prompts/Bad Name.md: '),
      ),
      hasLength(1),
      reason: result.stdout.join('\n'),
    );

    test('shadowed (info) is not printed; the control warning is', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/prompts/review.md', 'Project body\n');
      write('$home/prompts/review.md', 'User body\n');
      brokenUserTemplate();

      final result = await check();

      expectControl(result);
      expect(
        result.stdout.where((l) => l.startsWith('warning: ')),
        hasLength(1),
      );
      expect(result.stdout.join('\n'), isNot(contains('shadowed')));
      expect(result.stdout.where((l) => l.startsWith('note: ')), isEmpty);
      expect(result.stdout.last, 'Config: valid');
    });

    test('an untrusted project: one note per directory, nothing is read, '
        'code 0', () async {
      validConfig();
      write('$cwd/.codelab/prompts/Project Bad.md', 'x sk-test-secret\n');
      write('$cwd/.codelab/agents/reviewer.md', badAgent);
      brokenUserTemplate();

      final result = await check();

      expect(result.exitCode, 0);
      expect(
        result.stdout.where((l) => l.startsWith('note: ')),
        unorderedEquals([
          'note: $cwd/.codelab/prompts: the project is not trusted; '
              'add it to trusted_projects',
          'note: $cwd/.codelab/agents: the project is not trusted; '
              'add it to trusted_projects',
        ]),
      );
      // Файлы недоверенного проекта не читались: их ошибок нет, а чтение
      // пользовательской области (контроль) работает.
      expectControl(result);
      expect(
        result.stdout.where((l) => l.startsWith('warning: ')),
        hasLength(1),
      );
      expect(result.stdout.join('\n'), isNot(contains('reviewer.md')));
      expect(result.stdout.join('\n'), isNot(contains('Project Bad')));
      expect(result.stdout.join('\n'), isNot(contains('sk-test-secret')));
    });

    test(
      'an untrusted project without .codelab directories prints no note',
      () async {
        validConfig();

        final result = await check();

        expect(result.stdout.where((l) => l.startsWith('note: ')), isEmpty);
      },
    );

    test('an invalid config: project files are not checked', () async {
      write(
        '$home/config.yaml',
        '${providers}trusted_projects:\n  - $cwd\nbudget:\n  max_stepz: 3\n',
      );
      write('$cwd/.codelab/agents/reviewer.md', badAgent);
      brokenUserTemplate();

      final result = await check();

      // Этот тест не бывает красным до кода: до итерации 4 `check` файлов не
      // читал вовсе. Он охраняет контракт D13 от регрессии (невалидный
      // конфиг не даёт каталога моделей и доверия). Положительный контроль —
      // валидный конфиг с тем же набором файлов в тестах выше.
      expect(result.exitCode, 1);
      expect(result.stdout.join('\n'), isNot(contains('reviewer.md')));
      expect(result.stdout.join('\n'), isNot(contains('Review.md')));
      expect(result.stdout.last, 'Config: invalid (issues: 1)');
    });

    test('an unknown model in the definition is checked against the '
        'catalog of the loaded config', () async {
      validConfig(trusted: true);
      write(
        '$cwd/.codelab/agents/reviewer.md',
        '---\nname: reviewer\ndescription: R\nmodel: p/missing\n---\nBody\n',
      );

      final result = await check();

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(startsWith('warning: $cwd/.codelab/agents/reviewer.md')),
      );
    });

    test('no file fragments in the output', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/agents/reviewer.md', badAgent);
      write('$home/prompts/Review.md', 'body sk-test-secret\n');

      final result = await check();

      // Контроль: обе диагностики напечатаны, значит, фильтр фрагментов
      // действительно что-то отсекает.
      expect(
        result.stdout.where((l) => l.startsWith('warning: ')),
        hasLength(2),
        reason: result.stdout.join('\n'),
      );
      final text = [...result.stdout, ...result.stderr].join('\n');
      expect(text, isNot(contains('sk-test-secret')));
      expect(text, isNot(contains('secret body')));
    });

    test('exit codes are unchanged by diagnostics', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/agents/reviewer.md', badAgent);
      write('$home/prompts/Review.md', 'x\n');
      final before = snapshot();

      final result = await check();

      expect(result.exitCode, 0);
      expect(snapshot(), before);
    });

    group('trust and boundaries', () {
      test('cwd through a symlink to a trusted root stays trusted', () async {
        validConfig(trusted: true);
        write('$cwd/.codelab/agents/reviewer.md', badAgent);
        final link = '${root.path}/link';
        Link(link).createSync(cwd);

        final result = await check(at: link);

        expect(
          result.stdout,
          contains(startsWith('warning: $cwd/.codelab/agents/reviewer.md:')),
          reason: result.stdout.join('\n'),
        );
        expect(result.stdout.where((l) => l.startsWith('note: ')), isEmpty);
      });

      test('a symlink named like a trusted project to a foreign directory '
          'gets no trust', () async {
        validConfig(trusted: true);
        final foreign = '${root.path}/foreign';
        write('$foreign/.codelab/agents/reviewer.md', badAgent);
        // Имя ссылки — рядом с доверенным корнем, цель — чужой каталог.
        final link = '$cwd-link';
        Link(link).createSync(foreign);

        final result = await check(at: link);

        expect(result.exitCode, 0);
        expect(result.stdout.join('\n'), isNot(contains('reviewer.md')));
        expect(
          result.stdout,
          contains(startsWith('note: $foreign/.codelab/agents: ')),
        );
      });

      test('a prompts symlink pointing outside is outside_root and the '
          'target content is not printed', () async {
        validConfig(trusted: true);
        final outside = '${root.path}/outside';
        write('$outside/evil.md', 'outside body sk-outside-secret\n');
        Directory('$cwd/.codelab').createSync(recursive: true);
        Link('$cwd/.codelab/prompts').createSync(outside);

        final result = await check();

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            allOf(
              startsWith('warning: $cwd/.codelab/prompts: '),
              contains('outside its root'),
            ),
          ),
          reason: result.stdout.join('\n'),
        );
        final text = result.stdout.join('\n');
        expect(text, isNot(contains('sk-outside-secret')));
        expect(text, isNot(contains('evil')));
      });
    });

    group('failures of the phase', () {
      test(
        'a throwing source: one warning line with the type, code 0',
        () async {
          validConfig(trusted: true);

          final result = await check(
            commands: ConfigCommands(projectFiles: _ThrowingSource()),
          );

          expect(result.exitCode, 0);
          expect(result.stdout.where((l) => l.startsWith('warning: ')), [
            'warning: $cwd: project files could not be read: StateError',
          ]);
          expect(result.stdout.join('\n'), isNot(contains('secret detail')));
          expect(result.stdout.last, 'Config: valid');
          expect(result.stderr, isEmpty);
        },
      );

      test('a source that never answers: a timeout line, the load is '
          'cancelled, code 0', () async {
        validConfig(trusted: true);
        final source = _HangingSource();

        final result = await check(
          commands: ConfigCommands(
            projectFiles: source,
            projectFilesTimeout: const Duration(milliseconds: 20),
          ),
        );

        expect(result.exitCode, 0);
        expect(result.stdout.where((l) => l.startsWith('warning: ')), [
          'warning: $cwd: project files were not read within 0 s',
        ]);
        expect(source.cancel?.isCancelled, isTrue);
        expect(result.stdout.last, 'Config: valid');
      });

      test(
        'CODELAB_HOME=~user/x: usage error, code 64, nothing on stdout',
        () async {
          // D17: `~user` не раскрывается и не принимается молча.
          final result = await ConfigCommands().check(
            CheckOptions(
              cwd: cwd,
              environment: {'CODELAB_HOME': '~bob/x', 'HOME': home},
            ),
          );

          expect(result.exitCode, 64);
          expect(result.stdout, isEmpty);
          expect(result.stderr, [
            'config check: CODELAB_HOME: ~user is not supported, use an '
                'absolute path',
          ]);
        },
      );

      test('CODELAB_HOME=~/x is expanded to HOME: no loader failure', () async {
        final other = '${root.path}/other';
        Directory(other).createSync();
        write('${root.path}/h/x/config.yaml', providers);

        final result = await ConfigCommands().check(
          CheckOptions(
            cwd: other,
            environment: {'CODELAB_HOME': '~/x', 'HOME': '${root.path}/h'},
          ),
        );

        expect(result.stdout.last, 'Config: valid');
        expect(result.stdout.where((l) => l.startsWith('warning: ')), isEmpty);
        expect(result.exitCode, 0);
      });
    });
  });

  // Состояние секретов (agent-configuration «config check показывает
  // состояние секретов», все сценарии; design.md change
  // `add-agent-secret-store`, D9). Тест не читает настоящий `~/.codelab`:
  // хранилище — фейк или `secrets.yaml` во временном `CODELAB_HOME`.
  group('secrets', () {
    // Бэкенд `file` отказывает при каталоге, доступном на запись группе
    // (umask 0002 на Debian), поэтому права задаются явно (D14).
    setUp(() => Process.runSync('/bin/chmod', ['700', home]));

    const value = 'sk-test-0123456789abcdef';

    const withSecretKey = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/openai
    models:
      m: {}
agent:
  default_model: p/m
''';

    /// Команда над фейковым хранилищем; [opened] фиксирует выбор бэкенда.
    ConfigCommands over(
      DescribedSecretStore store, {
      List<String?>? opened,
      String? platform,
    }) => ConfigCommands(
      platform: platform,
      openStore: ({required choice, required environment, required home}) {
        opened?.add(choice);
        return store;
      },
    );

    List<String> secretLines(ConfigCommandResult result) => [
      for (final line in result.stdout)
        if (line.startsWith('note: secrets') ||
            line.startsWith('warning: secrets') ||
            line.contains(': secret '))
          line,
    ];

    void seedFile(String mode) {
      write('$home/secrets.yaml', '# CodeLab secrets in plaintext.\n');
      Process.runSync('/bin/chmod', ['700', home]);
      Process.runSync('/bin/chmod', [mode, '$home/secrets.yaml']);
    }

    test('auto: note с причиной и warning с подсказкой env/file, перед '
        'Config: valid, код 0', () async {
      write('$home/config.yaml', withSecretKey);

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(result.exitCode, 0, reason: result.stdout.join('\n'));
      final note = result.stdout.indexWhere(
        (l) => l.startsWith('note: secrets backend: env ('),
      );
      final warning = result.stdout.indexWhere(
        (l) => l.contains('secret codelab/openai is not set'),
      );
      expect(note, greaterThan(0));
      expect(warning, greaterThan(note));
      expect(warning, lessThan(result.stdout.length - 1));
      expect(
        result.stdout[warning],
        matches(
          RegExp(
            '^warning: ${RegExp.escape(home)}/config\\.yaml:\\d+:\\d+: '
            r'providers\.p\.api_key_secret: secret codelab/openai is not set; '
            r"set CODELAB_SECRET_CODELAB_OPENAI or add 'secrets.backend: file' "
            r'and run: codelab secret set codelab/openai$',
          ),
        ),
      );
      expect(result.stdout.last, 'Config: valid');
    });

    test('Windows: подсказка только с переменной', () async {
      write('$home/config.yaml', withSecretKey);

      final result = await check(commands: ConfigCommands(platform: 'windows'));

      final warning = result.stdout.singleWhere(
        (l) => l.contains('secret codelab/openai is not set'),
      );
      expect(
        warning,
        endsWith('is not set; set CODELAB_SECRET_CODELAB_OPENAI'),
      );
      expect(result.exitCode, 0);
    });

    test('file без секрета: подсказка set, note без причины, строка об '
        'открытом тексте', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$withSecretKey');
      seedFile('600');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(result.exitCode, 0, reason: result.stdout.join('\n'));
      expect(result.stdout, contains('note: secrets backend: file'));
      expect(
        result.stdout,
        contains(
          'warning: secrets: file backend stores secrets unencrypted in '
          '$home/secrets.yaml',
        ),
      );
      expect(
        result.stdout.singleWhere((l) => l.contains('is not set')),
        endsWith(
          'secret codelab/openai is not set; run: codelab secret set codelab/openai',
        ),
      );
      expect(result.stdout.last, 'Config: valid');
    });

    test('секрет задан переменной: строки warning нет, значение не '
        'печатается', () async {
      write('$home/config.yaml', withSecretKey);

      final result = await check(
        env: {'CODELAB_SECRET_CODELAB_OPENAI': value},
        commands: ConfigCommands(platform: 'linux'),
      );

      expect(result.exitCode, 0);
      expect(result.stdout.where((l) => l.contains('is not set')), isEmpty);
      expect(result.stdout, contains(startsWith('note: secrets backend: env')));
      expect(
        [...result.stdout, ...result.stderr].join(),
        isNot(contains(value)),
      );
    });

    test('секрет найден в хранилище: ни warning, ни значения', () async {
      write('$home/config.yaml', withSecretKey);

      final result = await check(
        commands: over(MemorySecretStore({'codelab/openai': value})),
      );

      expect(secretLines(result), ['note: secrets backend: memory']);
      expect(result.stdout.join(), isNot(contains(value)));
    });

    test('заголовок и MCP: каждое имя проверяется, без повторов', () async {
      write('$home/config.yaml', r'''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/openai
    headers:
      X-Org: "${secret:codelab/openai}"
      X-Team: "${secret:codelab/team}"
    models:
      m: {}
agent:
  default_model: p/m
mcp:
  servers:
    - name: gh
      type: http
      url: https://gh.test/mcp
      headers:
        Authorization: "Bearer ${secret:codelab/gh}"
''');

      final result = await check(commands: over(MemorySecretStore()));

      final missing = result.stdout.where((l) => l.contains('is not set'));
      expect(missing, hasLength(3));
      expect(
        missing,
        containsAll([
          contains(
            'providers.p.api_key_secret: secret codelab/openai is not set',
          ),
          contains(
            'providers.p.headers.X-Team: secret codelab/team is not set',
          ),
          contains(
            'mcp.servers[gh].headers.Authorization: secret codelab/gh is not set',
          ),
        ]),
      );
      expect(result.exitCode, 0);
    });

    test(
      'без ссылок на секреты хранилище не вызывается, вывод прежний',
      () async {
        write('$home/config.yaml', providers);
        final opened = <String?>[];
        final store = _CountingStore();

        final result = await check(commands: over(store, opened: opened));

        expect(store.calls, 0);
        expect(opened, isEmpty);
        expect(secretLines(result), isEmpty);
        expect(result.stdout.last, 'Config: valid');
      },
    );

    test(
      'только api_key_env: строк секретов нет, хранилище не вызывается',
      () async {
        write('$home/config.yaml', '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_env: P_KEY
    models:
      m: {}
agent:
  default_model: p/m
''');
        final store = _CountingStore();

        final result = await check(
          env: {'P_KEY': 'k-test-value'},
          commands: over(store),
        );

        expect(store.calls, 0);
        expect(secretLines(result), isEmpty);
      },
    );

    test('недоступное хранилище: одна строка unavailable, код 0', () async {
      write('$home/config.yaml', r'''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/openai
    headers:
      X-Team: "${secret:codelab/team}"
    models:
      m: {}
agent:
  default_model: p/m
''');

      final result = await check(commands: over(_UnavailableStore()));

      expect(secretLines(result), [
        'note: secrets backend: osfake',
        'warning: secrets: osfake is unavailable (locked by test)',
      ]);
      expect(result.exitCode, 0);
    });

    test('бэкенд берётся из secrets.backend загруженного конфига', () async {
      write('$home/config.yaml', 'secrets:\n  backend: env\n$withSecretKey');
      final opened = <String?>[];

      await check(commands: over(MemorySecretStore(), opened: opened));

      expect(opened, ['env']);
    });

    test(
      'невалидный конфиг: строк секретов нет, хранилище не вызывается',
      () async {
        write('$home/config.yaml', '${withSecretKey}budgett: {}\n');
        final store = _CountingStore();

        final result = await check(commands: over(store));

        expect(result.exitCode, 1);
        expect(store.calls, 0);
        expect(secretLines(result), isEmpty);
      },
    );

    test('file без ссылок: строка об открытом тексте всегда, права 0600 — '
        'строки о правах нет', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$providers');
      seedFile('600');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(secretLines(result), [
        'warning: secrets: file backend stores secrets unencrypted in '
            '$home/secrets.yaml',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout.last, 'Config: valid');
    });

    test('file без файла и без ссылок: файл не создаётся', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$providers');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(secretLines(result), hasLength(1));
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    });

    test('file с правами 0644: строка о правах с chmod 600, код 0', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$providers');
      seedFile('644');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(
        result.stdout,
        containsAllInOrder([
          'warning: secrets: file backend stores secrets unencrypted in '
              '$home/secrets.yaml',
          'warning: secrets: $home/secrets.yaml has permissions 0644; run: '
              'chmod 600 $home/secrets.yaml',
        ]),
      );
      expect(result.exitCode, 0);
      expect(result.stdout.last, 'Config: valid');
    });

    test('file с правами 0644 и ссылками: секреты недоступны, отдельных '
        'warning на каждое имя нет', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$withSecretKey');
      seedFile('644');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expect(result.stdout.where((l) => l.contains('is not set')), isEmpty);
      expect(
        result.stdout.where((l) => l.contains('has permissions 0644')),
        hasLength(1),
      );
      expect(result.exitCode, 0);
    });

    /// Отказ файлового бэкенда не про права: строка `file is unavailable
    /// (<причина>)` (D9), без строки о правах и без строк по именам.
    void expectUnavailable(ConfigCommandResult result, String reasonPart) {
      final lines = secretLines(result);
      expect(
        lines.where(
          (l) => l.startsWith('warning: secrets: file is unavailable ('),
        ),
        hasLength(1),
        reason: lines.join('\n'),
      );
      expect(
        lines.singleWhere((l) => l.contains('file is unavailable')),
        contains(reasonPart),
      );
      expect(lines.where((l) => l.contains('has permissions')), isEmpty);
      expect(lines.where((l) => l.contains('is not set')), isEmpty);
      expect(result.exitCode, 0);
    }

    test('file: secrets.yaml — символьная ссылка: file is unavailable '
        '(symbolic link)', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$withSecretKey');
      Process.runSync('/bin/chmod', ['700', home]);
      write('$home/real.yaml', '# CodeLab secrets in plaintext.\n');
      Link('$home/secrets.yaml').createSync('$home/real.yaml');

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expectUnavailable(result, 'is a symbolic link');
    });

    test('file: каталог доступен на запись группе: file is unavailable '
        '(writable by group or others)', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$withSecretKey');
      write('$home/secrets.yaml', '# CodeLab secrets in plaintext.\n');
      Process.runSync('/bin/chmod', ['600', '$home/secrets.yaml']);
      Process.runSync('/bin/chmod', ['770', home]);

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expectUnavailable(result, 'writable by group or others');
    });

    test('file: secrets.yaml больше 1 МиБ: file is unavailable '
        '(larger than 1 MiB)', () async {
      write('$home/config.yaml', 'secrets:\n  backend: file\n$withSecretKey');
      write('$home/secrets.yaml', 'x' * (1024 * 1024 + 1));
      Process.runSync('/bin/chmod', ['700', home]);
      Process.runSync('/bin/chmod', ['600', '$home/secrets.yaml']);

      final result = await check(commands: ConfigCommands(platform: 'linux'));

      expectUnavailable(result, 'larger than 1 MiB');
    });
  });
}

/// Источник, бросающий исключение с «секретным» текстом: в вывод попадает
/// только тип.
final class _ThrowingSource implements ProjectFilesSource {
  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) =>
      Future.error(StateError('secret detail'));
}

/// Источник, не отвечающий никогда; запоминает токен отмены запроса.
final class _HangingSource implements ProjectFilesSource {
  CancelToken? cancel;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) {
    cancel = query.cancel;
    return Completer<ProjectFiles>().future;
  }
}

/// Хранилище, считающее обращения: «без ссылок оно не вызывается» (D9).
final class _CountingStore implements DescribedSecretStore {
  int calls = 0;

  @override
  SecretBackendInfo get backend {
    calls++;
    return const SecretBackendInfo(id: 'counting', writable: true);
  }

  @override
  Future<String?> read(String name) async {
    calls++;
    return null;
  }

  @override
  Future<void> write(String name, String value) async => calls++;

  @override
  Future<void> delete(String name) async => calls++;

  @override
  Future<List<String>> names() async {
    calls++;
    return const [];
  }
}

/// Хранилище, отказывающее при чтении (`SecretUnavailable`).
final class _UnavailableStore implements DescribedSecretStore {
  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'osfake', writable: true);

  @override
  Future<String?> read(String name) async =>
      throw const SecretStoreUnavailableException(
        backend: 'osfake',
        reason: 'locked by test',
      );

  @override
  Future<void> write(String name, String value) async {}

  @override
  Future<void> delete(String name) async {}

  @override
  Future<List<String>> names() async => const [];
}
