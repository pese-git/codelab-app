// `codelab provider add|list|remove` и `codelab mcp add|list|remove` без
// агента (задача 4.5 change `add-config-writer-and-reload`; spec codelab-cli
// «Подкоманды codelab provider и codelab mcp»; design.md D6). Вывод самих
// подкоманд проверяют тесты `ProviderCommands` и `McpServerCommands`; здесь —
// разбор argv, коды `64`, справка и то, что CLI печатает ровно результат
// общей реализации. Значения «секретов» выдуманные, настоящий `~/.codelab` не
// читается.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Слово, имитирующее ключ, переданный аргументом по ошибке: ни одно
/// сообщение не вправе его процитировать.
const _leak = 'sk-LEAK-0123456789';

final class _SilentLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

void main() {
  late Directory temp;
  late String home;
  late String project;
  late Map<String, String> env;

  setUp(() {
    // Каталог сразу канонический: писатель раскрывает ссылки (на macOS `/var` —
    // ссылка на `/private/var`), и путь в выводе должен совпасть с ожиданием.
    temp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_provider_mcp_')
          .resolveSymbolicLinksSync(),
    );
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    env = {'CODELAB_HOME': home, 'HOME': '${temp.path}/no-home'};
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(List<String> args) async {
    final io = FakeCliIo();
    final code = await runCodelab(args, environment: env, io: io);
    return (code, io);
  }

  String read(String path) => File(path).readAsStringSync();

  group('parseCliArgs', () {
    test('provider и mcp — подкоманды со своими аргументами', () {
      final provider = parseCliArgs([
        'provider',
        'add',
        'gw',
        '--kind',
        'anthropic',
      ]);
      expect(provider.command, CliCommand.provider);
      expect(provider.subcommand?.name, 'add');
      expect(provider.subcommand?.rest, ['gw']);

      final mcp = parseCliArgs(['mcp', 'list']);
      expect(mcp.command, CliCommand.mcp);
      expect(mcp.subcommand?.name, 'list');
    });

    test('значение --arg, начинающееся с дефисов, остаётся значением', () {
      // Спека: `codelab mcp add docs … --arg --stdio`.
      final options = parseCliArgs([
        'mcp',
        'add',
        'docs',
        '--type',
        'stdio',
        '--command',
        'docs-mcp',
        '--arg',
        '--stdio',
      ]);
      expect(options.command, CliCommand.mcp);
    });
  });

  group('provider', () {
    test('--help называет provider и mcp', () async {
      final (code, io) = await run(['--help']);

      expect(code, 0);
      expect(io.stdoutText, contains('codelab provider add|list|remove'));
      expect(io.stdoutText, contains('codelab mcp add|list|remove'));
    });

    test('add без обязательных флагов: 64, одна строка называет все три '
        'флага, файлы не изменены', () async {
      final (code, io) = await run(['provider', 'add', 'gw']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        'provider add: missing required options: '
        '--kind, --model, --context-window\n',
      );
      expect(File('$home/config.yaml').existsSync(), isFalse);
    });

    test('add с частью флагов называет только недостающие', () async {
      final (code, io) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'anthropic',
      ]);

      expect(code, 64);
      expect(
        io.stderrText,
        'provider add: missing required options: --model, --context-window\n',
      );
    });

    test('unknown provider arguments (1): слово подкоманды не цитируется, '
        'справка provider', () async {
      final (code, io) = await run(['provider', 'frob']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(io.stderrText, contains('unknown provider arguments (1)'));
      expect(io.stderrText, contains('codelab provider'));
      expect(io.stderrText, isNot(contains('frob')));
    });

    test('--project и --local вместе: 64 от общего кода, файлы не '
        'изменены', () async {
      final (code, io) = await run([
        'provider',
        'remove',
        'gw',
        '--project',
        '--local',
      ]);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        contains(
          '--project and --local cannot be '
          'combined',
        ),
      );
      expect(File('$home/config.yaml').existsSync(), isFalse);
    });

    test('list --cwd подкоманды сильнее общего -C', () async {
      final other = '${temp.path}/other';
      Directory(other).createSync();
      File(
        '$home/config.yaml',
      ).writeAsStringSync('trusted_projects: ["$project"]\n');
      Directory('$project/.codelab').createSync();
      File('$project/.codelab/config.local.yaml').writeAsStringSync('''
providers:
  loc:
    kind: openai-compatible
    base_url: https://l/v1
    api_key_env: LOC_KEY
    models:
      m: {context_window: 8192}
agent:
  default_model: loc/m
''');

      final (code, io) = await run([
        '-C',
        other,
        'provider',
        'list',
        '--cwd',
        project,
      ]);
      final (plain, plainIo) = await run(['-C', project, 'provider', 'list']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('loc'));
      expect(io.stdoutText, plainIo.stdoutText);
      expect(plain, 0);
    });

    test('add с флагами пишет провайдера; вывод и байты как у моста', () async {
      final args = [
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--base-url',
        'https://x/v1',
        '--model',
        'm',
        '--context-window',
        '8192',
        '--api-key-env',
        'GW_KEY',
        '--default',
      ];
      final (code, io) = await run(args);

      expect(code, 0, reason: io.stderrText);
      final written = read('$home/config.yaml');
      expect(written, contains('api_key_env: GW_KEY'));
      expect(written, contains('default_model: gw/m'));

      File('$home/config.yaml').deleteSync();
      final expected = await ProviderCommands().add(
        ProviderAddOptions(
          id: 'gw',
          cwd: Directory.current.path,
          environment: env,
          kind: 'openai-compatible',
          baseUrl: 'https://x/v1',
          model: 'm',
          contextWindow: '8192',
          apiKeyEnv: 'GW_KEY',
          makeDefault: true,
        ),
        StdinSecretInput(),
      );
      expect(io.stdoutText, expected.stdout.map((l) => '$l\n').join());
      expect(io.stderrText, expected.stderr.map((l) => '$l\n').join());
      expect(read('$home/config.yaml'), written);
    });

    test('add существующего id обновляет поля (upsert)', () async {
      const base = [
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--model',
        'm',
        '--context-window',
        '8192',
        '--api-key-env',
        'GW_KEY',
      ];
      await run(base);
      final (code, io) = await run([...base, '--base-url', 'https://y/v1']);

      expect(code, 0, reason: io.stderrText);
      expect(read('$home/config.yaml'), contains('https://y/v1'));
    });

    test(
      'list: Secrets первой строкой, найденный секрет без значения',
      () async {
        File('$home/config.yaml').writeAsStringSync('''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: https://x/v1
    api_key_secret: codelab/gw
    models:
      m: {context_window: 8192}
agent:
  default_model: gw/m
''');
        const value = 'sk-test-0123456789abcdef';
        final admin = SecretAdmin(
          store: openSecretStore(
            choice: 'file',
            environment: const {},
            home: home,
            logger: _SilentLogger(),
          ),
          environment: const {},
        );
        expect(await admin.store('codelab/gw', value), isA<SecretStored>());

        final (code, io) = await run(['provider', 'list']);

        expect(code, 0, reason: io.stderrText);
        final lines = io.stdoutText.split('\n');
        expect(lines.first, 'Secrets: file');
        expect(
          lines.singleWhere((l) => l.startsWith('gw')),
          contains('secret codelab/gw: found'),
        );
        expect('${io.stdoutText}${io.stderrText}', isNot(contains(value)));
      },
    );

    test('remove провайдера и remove отсутствующего (код 0)', () async {
      // `keep` держит agent.default_model: конфиг остаётся валидным, пока
      // `gw` добавляют и удаляют.
      File('$home/config.yaml').writeAsStringSync('''
providers:
  keep:
    kind: openai-compatible
    base_url: https://k/v1
    api_key_env: KEEP_KEY
    models:
      k: {context_window: 8192}
agent:
  default_model: keep/k
''');
      final (addCode, add) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--base-url',
        'https://g/v1',
        '--model',
        'm',
        '--context-window',
        '8192',
        '--api-key-env',
        'GW_KEY',
      ]);
      expect(addCode, 0, reason: add.stderrText);

      final (code, io) = await run(['provider', 'remove', 'gw']);
      final (again, again0) = await run(['provider', 'remove', 'gw']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('Removed providers.gw from'));
      expect(again, 0, reason: again0.stderrText);
      expect(again0.stdoutText, contains('providers.gw is not set in'));
    });

    test(
      'ошибки использования: 64, справка provider, слова не цитируются',
      () async {
        for (final args in [
          ['provider'],
          ['provider', 'frobnicate'],
          ['provider', 'frobnicate', _leak],
          ['provider', 'add'],
          ['provider', 'remove'],
          ['provider', 'list', _leak],
          ['provider', 'add', 'gw', _leak],
          ['provider', 'add', 'gw', '--api-key=$_leak'],
          ['provider', 'add', 'gw', '--api-key', _leak],
          ['--approve=$_leak', 'provider', 'list'],
          ['--X-leak', 'provider', 'add', 'gw'],
          ['provider', 'add', 'gw', '--X-leak'],
        ]) {
          final (code, io) = await run(args);

          expect(code, 64, reason: '$args: ${io.stderrText}');
          expect(io.stdoutText, isEmpty, reason: '$args');
          expect(io.stderrText, contains('codelab provider'), reason: '$args');
          expect(io.stderrText, isNot(contains(_leak)), reason: '$args');
          expect(io.stderrText, isNot(contains('X-leak')), reason: '$args');
          expect(io.stderrText, isNot(contains('codelab-agent')));
        }
        expect(File('$home/config.yaml').existsSync(), isFalse);
      },
    );

    for (final flags in [
      ['-p', 'hi'],
      ['--agent', 'x'],
      ['-m', 'x'],
      ['--ui', 'tui'],
    ]) {
      test('${flags.join(' ')} с provider list: 64', () async {
        final (code, io) = await run([...flags, 'provider', 'list']);

        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(io.stderrText, contains('does not apply to provider'));
      });
    }

    test('несуществующий -C: 64', () async {
      final (code, io) = await run([
        '-C',
        '${temp.path}/missing',
        'provider',
        'list',
      ]);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
    });
  });

  group('mcp', () {
    test('add, list, remove; комментарии файла сохранены', () async {
      File('$home/config.yaml').writeAsStringSync('# keep me\nbudget: {}\n');

      final (addCode, add) = await run([
        'mcp',
        'add',
        'docs',
        '--type',
        'stdio',
        '--command',
        'docs-mcp',
        '--arg',
        '--stdio',
      ]);
      final (listCode, list) = await run(['mcp', 'list']);
      final (removeCode, remove) = await run(['mcp', 'remove', 'docs']);

      expect(addCode, 0, reason: add.stderrText);
      expect(add.stdoutText, contains('Updated mcp.servers[docs] in'));
      expect(listCode, 0, reason: list.stderrText);
      for (final word in ['docs', 'stdio', 'user', 'enabled']) {
        expect(list.stdoutText, contains(word));
      }
      expect(removeCode, 0, reason: remove.stderrText);
      final text = read('$home/config.yaml');
      expect(text, contains('# keep me'));
      expect(text, isNot(contains('docs')));
    });

    test('add --local пишет в config.local.yaml проекта (общий -C)', () async {
      // Серверы MCP проекта действуют только в доверенном проекте.
      File(
        '$home/config.yaml',
      ).writeAsStringSync('trusted_projects: ["$project"]\n');
      final (code, io) = await run([
        '-C',
        project,
        'mcp',
        'add',
        'docs',
        '--type',
        'http',
        '--url',
        'https://h',
        '--local',
      ]);

      expect(code, 0, reason: io.stderrText);
      expect(read('$project/.codelab/config.local.yaml'), contains('docs'));
    });

    test('литеральный токен в заголовке: 1, значение не печатается', () async {
      final (code, io) = await run([
        'mcp',
        'add',
        'github',
        '--type',
        'http',
        '--url',
        'https://h',
        '--header',
        'Authorization=Bearer ghp_x',
      ]);

      expect(code, 1);
      expect(io.stdoutText, isEmpty);
      expect(io.stderrText, isNot(contains('ghp_x')));
      expect(File('$home/config.yaml').existsSync(), isFalse);
    });

    test(
      'ошибки использования: 64, справка mcp, слова не цитируются',
      () async {
        for (final args in [
          ['mcp'],
          ['mcp', 'frobnicate'],
          ['mcp', 'add'],
          ['mcp', 'remove'],
          ['mcp', 'list', _leak],
          ['mcp', 'add', 'x', '--header=Authorization=$_leak', '--bogus'],
          ['mcp', 'add', 'x', '--bogus=$_leak'],
          ['--X-leak', 'mcp', 'list'],
        ]) {
          final (code, io) = await run(args);

          expect(code, 64, reason: '$args: ${io.stderrText}');
          expect(io.stdoutText, isEmpty, reason: '$args');
          expect(io.stderrText, contains('codelab mcp'), reason: '$args');
          expect(io.stderrText, isNot(contains(_leak)), reason: '$args');
          expect(io.stderrText, isNot(contains('X-leak')), reason: '$args');
        }
      },
    );

    test('--project и --local вместе: 64 от общего кода', () async {
      final (code, io) = await run([
        'mcp',
        'remove',
        'x',
        '--project',
        '--local',
      ]);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        contains(
          '--project and --local cannot be '
          'combined',
        ),
      );
    });

    test('remove с недопустимым именем: 64 и текст общего кода', () async {
      final (code, io) = await run(['mcp', 'remove', 'a b']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        'mcp remove: the server name must not contain whitespace, [, ] or '
        '"\n',
      );
    });

    test('list --cwd подкоманды сильнее общего -C (слой local доверенного '
        'проекта)', () async {
      final other = '${temp.path}/other';
      Directory(other).createSync();
      File(
        '$home/config.yaml',
      ).writeAsStringSync('trusted_projects: ["$project"]\n');
      Directory('$project/.codelab').createSync();
      File('$project/.codelab/config.local.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: docs
      type: http
      url: https://h
''');

      final (code, io) = await run([
        '-C',
        other,
        'mcp',
        'list',
        '--cwd',
        project,
      ]);
      final (viaC, viaCIo) = await run(['-C', project, 'mcp', 'list']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('docs'));
      expect(io.stdoutText, contains('local'));
      expect(viaC, 0, reason: viaCIo.stderrText);
      expect(io.stdoutText, viaCIo.stdoutText);
    });

    test('-p hi mcp list: 64, ничего не создано', () async {
      final (code, io) = await run(['-p', 'hi', 'mcp', 'list']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(Directory(home).listSync(), isEmpty);
    });

    test('запись не создаёт sessions/, profiles.json и cli_history', () async {
      await run(['mcp', 'add', 'docs', '--type', 'http', '--url', 'https://h']);

      final names = Directory(home)
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet();
      expect(names, {'config.yaml'});
    });
  });
}
