import 'dart:io';

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

  ConfigCommandResult check({Map<String, String> env = const {}}) =>
      ConfigCommands().check(
        CheckOptions(cwd: cwd, environment: {'CODELAB_HOME': home, ...env}),
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

  test('a valid config: Sources first, Config: valid last, code 0', () {
    write('$home/config.yaml', providers);

    final result = check();

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(result.stdout.first, startsWith('Sources:'));
    expect(result.stdout.first, contains('$home/config.yaml'));
    expect(result.stdout.last, 'Config: valid');
  });

  test(
    'a typo: file:line:column, key, message; invalid (issues: 1); code 1',
    () {
      write(
        '$cwd/.codelab/config.yaml',
        '${providers}budget:\n  max_stepz: 3\n',
      );

      final result = check();

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

  test('a syntax error is reported without a position crash', () {
    write('$home/config.yaml', 'providers: [unclosed\n');

    final result = check();

    expect(result.exitCode, 1);
    expect(result.stdout.last, startsWith('Config: invalid (issues: '));
  });

  test('codelab.toml alone: a warning line, the path once, and the only '
      'issue is the missing default model (code 1)', () {
    write('$cwd/codelab.toml', 'x = 1\n');

    // YAML-слоёв нет, поэтому единственная проблема — нет модели по
    // умолчанию. Предупреждение о `codelab.toml` (D12) проблемой не
    // считается и в счётчик не входит.
    final result = check();

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
      'named in the text', () {
    write('$cwd/codelab.toml', 'x = 1\n');
    write('$cwd/codelab.local.toml', 'x = 1\n');

    final result = check();

    final line = result.stdout.singleWhere((l) => l.startsWith('warning: '));
    expect(line, startsWith('warning: $cwd/codelab.toml: '));
    expect('$cwd/codelab.toml'.allMatches(line), hasLength(1));
    expect(line, contains('$cwd/codelab.local.toml'));
  });

  test('an unknown CODELAB_* variable is a warning line; the config stays '
      'valid (config.env.unknown)', () {
    write('$home/config.yaml', providers);

    final result = check(env: {'CODELAB_MAX_STEP': '3'});

    expect(result.exitCode, 0, reason: result.stdout.join('\n'));
    expect(
      result.stdout,
      contains(allOf(startsWith('warning: '), contains('CODELAB_MAX_STEP'))),
    );
    expect(result.stdout.last, 'Config: valid');
  });

  test('config.yml next to nothing: warning line, config stays valid', () {
    write('$home/config.yaml', providers);
    write('$cwd/.codelab/config.yml', 'x: 1\n');

    final result = check();

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains(startsWith('warning: $cwd/.codelab/config.yml: ignored')),
    );
    expect(result.stdout.last, 'Config: valid');
  });

  test('check writes nothing', () {
    write('$home/config.yaml', providers);
    write('$cwd/codelab.toml', 'x');
    final before = snapshot();

    check();

    expect(snapshot(), before);
    expect(Directory('$home/logs').existsSync(), isFalse);
  });

  test('an inline secret never reaches the output', () {
    write(
      '$home/config.yaml',
      providers.replaceFirst(
        'kind: openai-compatible',
        'kind: openai-compatible\n    api_key: sk-test-secret',
      ),
    );

    final result = check();

    expect(result.exitCode, 1);
    final all = [...result.stdout, ...result.stderr].join('\n');
    expect(all, contains('providers.p.api_key'));
    expect(all, isNot(contains('sk-test-secret')));
  });

  test('an env var holding a secret value is not printed', () {
    write('$home/config.yaml', providers);

    final result = check(env: {'CODELAB_API_KEY': 'sk-test-secret'});

    final all = [...result.stdout, ...result.stderr].join('\n');
    expect(all, isNot(contains('sk-test-secret')));
  });

  test('a bad CODELAB_CONFIG file name is a usage error: code 64, stderr', () {
    final result = check(env: {'CODELAB_CONFIG': '/x/codelab.toml'});

    expect(result.exitCode, 64);
    expect(result.stdout, isEmpty);
    expect(result.stderr.join('\n'), contains('codelab.toml'));
  });

  test('a missing cwd is a usage error: code 64', () {
    final result = ConfigCommands().check(
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
        'the same server has a problem', () {
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

      final result = check(
        env: {'TOKEN': 'tok-test-secret', 'VAR': 'var-test-secret'},
      );

      expect(result.exitCode, 1, reason: all(result));
      expect(all(result), contains('mcp.servers'));
      expect(all(result), isNot(contains('tok-test-secret')));
      expect(all(result), isNot(contains('var-test-secret')));
    });

    test('a valid server with substitutions prints nothing of the values', () {
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

      final result = check(env: {'TOKEN': 'tok-test-secret'});

      expect(result.exitCode, 0, reason: all(result));
      expect(all(result), isNot(contains('tok-test-secret')));
    });

    test('a secret written into api_key_env is not echoed', () {
      write(
        '$home/config.yaml',
        providers.replaceFirst(
          'kind: openai-compatible',
          'kind: openai-compatible\n    api_key_env: sk-test-secret-123',
        ),
      );

      final result = check();

      expect(result.exitCode, 1, reason: all(result));
      expect(all(result), isNot(contains('sk-test-secret-123')));
    });

    test('CODELAB_AGENT_TOKEN in the environment is not printed', () {
      write('$home/config.yaml', providers);

      final result = check(env: {'CODELAB_AGENT_TOKEN': 'agent-test-token'});

      expect(result.exitCode, 0, reason: all(result));
      expect(all(result), isNot(contains('agent-test-token')));
    });

    test('an untrusted project cannot add providers or mcp servers: warning '
        'lines, keys not accepted', () {
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

      final result = check();

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
}
