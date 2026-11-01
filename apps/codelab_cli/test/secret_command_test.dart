// `codelab secret set|delete|list` на уровне аргументов и запуска без
// процесса (задача 9.2 change `add-agent-secret-store`; spec codelab-cli
// «Подкоманда codelab secret»; agent-secrets «Подкоманды secret»; design.md
// D8, D15). Вывод самой `SecretCommands` проверяют её тесты и e2e-сравнение
// с `codelab-agent`; здесь — разбор argv, коды `64` и то, что CLI не трогает
// `CODELAB_HOME`.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Слово, имитирующее значение секрета, переданное аргументом по ошибке: ни
/// одно сообщение не вправе его процитировать.
const _leak = 'sk-LEAK-0123456789';

/// Логгер-заглушка для `openSecretStore`: тесту нужны только результаты.
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

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_cli_secret_cmd_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final io = FakeCliIo();
    final code = await runCodelab(
      args,
      // HOME несуществующий: тест не видит настоящий `~/.codelab`.
      environment:
          environment ?? {'CODELAB_HOME': home, 'HOME': '${temp.path}/x'},
      io: io,
    );
    return (code, io);
  }

  Map<String, String> snapshot(String root) => {
    for (final entity in Directory(root).listSync(recursive: true))
      entity.path.substring(root.length): entity is File
          ? entity.readAsStringSync()
          : 'dir',
  };

  group('parseCliArgs', () {
    test('secret set|delete|list parse into CliCommand.secret', () {
      final set = parseCliArgs(['secret', 'set', 'codelab/x']);
      expect(set.command, CliCommand.secret);
      expect(set.positional, ['set', 'codelab/x']);
      expect(parseCliArgs(['secret', 'list']).positional, ['list']);
      expect(parseCliArgs(['secret', 'delete', 'a']).positional, [
        'delete',
        'a',
      ]);
    });

    test('an extra argument of set is kept for hasValueArgument', () {
      expect(parseCliArgs(['secret', 'set', 'a', _leak]).positional, [
        'set',
        'a',
        _leak,
      ]);
    });

    test('no subcommand and unknown subcommand: usage error, no quoting', () {
      for (final args in [
        ['secret'],
        ['secret', _leak],
      ]) {
        expect(
          () => parseCliArgs(args),
          throwsA(
            isA<UsageError>()
                .having(
                  (e) => e.message,
                  'message',
                  'secret needs a subcommand: set, delete or list',
                )
                .having((e) => e.showSecretUsage, 'showSecretUsage', isTrue),
          ),
          reason: '$args',
        );
      }
    });

    test('missing or extra arguments: usage error, no quoting', () {
      final cases = {
        ['secret', 'set']: 'secret set needs the secret name',
        ['secret', 'delete']: 'secret delete needs exactly one name',
        ['secret', 'delete', 'a', _leak]:
            'secret delete needs exactly one name',
        ['secret', 'list', _leak]: 'secret list takes no arguments',
      };
      cases.forEach((args, message) {
        expect(
          () => parseCliArgs(args),
          throwsA(
            isA<UsageError>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.showSecretUsage, 'showSecretUsage', isTrue),
          ),
          reason: '$args',
        );
      });
    });

    test(
      'an unknown flag after secret: invalid arguments, flag not quoted',
      () {
        for (final args in [
          ['secret', 'set', 'a', '--$_leak'],
          ['secret', '--$_leak'],
          ['secret', 'list', '-z'],
          // Разбор падает до подкоманды или после неё: `secret` где угодно в
          // argv — всё равно фиксированная фраза, без текста `package:args`.
          ['--approve=$_leak', 'secret', 'set', 'x'],
          ['--ui', _leak, 'secret', 'list'],
          ['secret', 'set', 'x', '--value=$_leak'],
          ['secret', 'set', 'x', '-$_leak'],
          ['secret', 'list', '--approve=$_leak'],
        ]) {
          expect(
            () => parseCliArgs(args),
            throwsA(
              isA<UsageError>()
                  .having(
                    (e) => e.message,
                    'message',
                    'invalid arguments for secret',
                  )
                  .having((e) => e.message, 'no leak', isNot(contains(_leak)))
                  .having((e) => e.showSecretUsage, 'showSecretUsage', isTrue),
            ),
            reason: '$args',
          );
        }
      },
    );

    test('connection flags with secret are usage errors', () {
      // флаг -> имя в сообщении (сокращение раскрывается в длинное имя).
      final flags = <List<String>, String>{
        ['-a', _leak]: 'agent',
        ['--agent', _leak]: 'agent',
        ['-C', _leak]: 'cwd',
        ['-m', _leak]: 'model',
        ['--model', _leak]: 'model',
        ['--mode', _leak]: 'mode',
        ['-r', _leak]: 'resume',
        ['--resume', _leak]: 'resume',
        ['-c']: 'continue',
        ['--continue']: 'continue',
        ['-p', _leak]: 'print',
        ['--print', _leak]: 'print',
        ['-f', _leak]: 'prompt-file',
        ['--prompt-file', _leak]: 'prompt-file',
        ['--approve', 'allow-all']: 'approve',
        ['--timeout', '5s']: 'timeout',
        ['--ui', 'tui']: 'ui',
      };
      flags.forEach((flag, name) {
        expect(
          () => parseCliArgs([...flag, 'secret', 'list']),
          throwsA(
            isA<UsageError>()
                .having(
                  (e) => e.message,
                  'message',
                  '--$name does not apply to secret',
                )
                .having((e) => e.message, 'no leak', isNot(contains(_leak))),
          ),
          reason: '${flag.join(' ')} secret list',
        );
      });
    });
  });

  group('runCodelab', () {
    test('--help names secret set|delete|list', () async {
      final (code, io) = await run(['--help']);
      expect(code, 0);
      expect(io.stdoutText, contains('codelab secret set|delete|list'));
    });

    test(
      'no subcommand: 64, message and usage in stderr, stdout empty',
      () async {
        final (code, io) = await run(['secret']);
        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(
          io.stderrText,
          startsWith(
            'codelab: secret needs a subcommand: set, delete or list\n\n'
            'Usage: codelab secret set|delete|list\n',
          ),
        );
      },
    );

    test('a value passed as an argument: 64, never printed', () async {
      final (code, io) = await run(['secret', 'set', 'codelab/x', _leak]);
      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        contains('pass the secret value on stdin, not as an argument'),
      );
      expect(io.stderrText, isNot(contains(_leak)));
      expect(io.stderrText, contains('codelab secret'));
      expect(io.stderrText, isNot(contains('codelab-agent')));
    });

    test('a parse error never quotes the sent words', () async {
      final (code, io) = await run(['secret', 'set', 'a', '--$_leak']);
      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        startsWith('codelab: invalid arguments for secret\n'),
      );
      expect(io.stderrText, isNot(contains(_leak)));
    });

    test(
      '-p hi secret list: 64, stdout empty, CODELAB_HOME untouched',
      () async {
        final before = snapshot(home);
        final (code, io) = await run(['-p', 'hi', 'secret', 'list']);
        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(snapshot(home), before);
      },
    );

    test(
      'list with env backend from CODELAB_CONFIG: empty home unchanged',
      () async {
        // Scenario «Подкоманда не меняет CODELAB_HOME»: пустой CODELAB_HOME,
        // бэкенд env задан файлом CODELAB_CONFIG вне домашней папки.
        File('$home/config.yaml').deleteSync();
        final cfg = File('${temp.path}/cfg.yaml')
          ..writeAsStringSync('secrets:\n  backend: env\n');
        final (code, io) = await run(
          ['secret', 'list'],
          environment: {
            'CODELAB_HOME': home,
            'CODELAB_CONFIG': cfg.path,
            'HOME': '${temp.path}/x',
          },
        );
        expect(code, 0, reason: io.stderrText);
        expect(io.stdoutText, startsWith('Backend: env'));
        expect(snapshot(home), isEmpty);
        expect(Directory(home).listSync(), isEmpty);
      },
    );

    test(
      'list with the env backend: 0, Backend line, home unchanged',
      () async {
        final before = snapshot(home);
        final (code, io) = await run(['secret', 'list']);
        expect(code, 0, reason: io.stderrText);
        expect(io.stdoutText, startsWith('Backend: env'));
        // spec: ни `sessions/`, ни `profiles.json`, ни `cli_history`, ни
        // `secrets.yaml`.
        expect(snapshot(home), before);
        expect(before.keys, ['/config.yaml']);
      },
    );

    test('--cwd <dir> / -C <dir> secret list: 64, exact message, secret usage, '
        'store untouched', () async {
      // spec codelab-cli «--cwd с secret»: длинная и короткая формы.
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');
      final before = snapshot(home);
      for (final flag in ['--cwd', '-C']) {
        final (code, io) = await run([flag, temp.path, 'secret', 'list']);
        expect(code, 64, reason: flag);
        expect(io.stdoutText, isEmpty, reason: flag);
        expect(
          io.stderrText,
          startsWith('codelab: --cwd does not apply to secret\n'),
          reason: flag,
        );
        expect(
          io.stderrText,
          contains('Usage: codelab secret set|delete|list'),
          reason: flag,
        );
        expect(snapshot(home), before, reason: flag);
        expect(File('$home/secrets.yaml').existsSync(), isFalse);
      }
    });

    test(
      'a bad top-level flag before secret: 64, fixed phrase, flag not echoed',
      () async {
        // spec codelab-cli «Ошибка верхнего парсера с secret»; agent-secrets
        // «Ошибка флага верхнего уровня перед secret».
        const secretLike = 'sk-test-0123456789abcdef';
        for (final flag in ['--no-such-flag', '--$secretLike']) {
          final before = snapshot(home);
          final (code, io) = await run([flag, 'secret', 'list']);
          expect(code, 64, reason: flag);
          expect(io.stdoutText, isEmpty, reason: flag);
          expect(
            io.stderrText,
            startsWith('codelab: invalid arguments for secret\n\nUsage: '),
            reason: flag,
          );
          expect(io.stderrText, contains('codelab secret set|delete|list'));
          expect(io.stderrText, isNot(contains('no-such-flag')));
          expect(io.stderrText, isNot(contains(secretLike)));
          expect(io.stderrText, isNot(contains('Could not find an option')));
          expect(io.stderrText, isNot(contains('package:args')));
          expect(snapshot(home), before);
        }
      },
    );

    test('SecretAdmin.store from the app, then codelab secret list shows the '
        'name and never the value', () async {
      // spec agent-secrets «Запись из приложения и список в CLI».
      const name = 'codelab/openai';
      const value = 'sk-test-0123456789abcdef';
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');
      final admin = SecretAdmin(
        store: openSecretStore(
          choice: 'file',
          environment: const {},
          home: home,
          logger: _SilentLogger(),
        ),
        environment: const {},
      );

      expect(await admin.store(name, value), isA<SecretStored>());

      final (code, io) = await run(['secret', 'list']);
      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains(name));
      expect('${io.stdoutText}${io.stderrText}', isNot(contains(value)));
    });

    test('CODELAB_HOME=~user/x: 64 with the home message', () async {
      final (code, io) = await run(
        ['secret', 'list'],
        environment: {'CODELAB_HOME': '~root/x', 'HOME': '${temp.path}/x'},
      );
      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(io.stderrText, contains('CODELAB_HOME: ~user is not supported'));
    });

    test('CODELAB_HOME=~/cl is expanded with HOME, no ./~ folder', () async {
      final userHome = '${temp.path}/user';
      Directory('$userHome/cl').createSync(recursive: true);
      File(
        '$userHome/cl/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: env\n');
      final cwd = Directory.current.path;
      final (code, io) = await run(
        ['secret', 'list'],
        environment: {'CODELAB_HOME': '~/cl', 'HOME': userHome},
      );
      expect(code, 0, reason: io.stderrText);
      expect(Directory('$cwd/~').existsSync(), isFalse);
    });
  });

  // Утечка класса «разбор удался, поздняя ошибка цитирует хвост argv»
  // (spec agent-secrets: при `secret` в argv ни одна ошибка не цитирует токены).
  group('no argv quoting in late errors when secret is in argv', () {
    final cases = <String, List<String>>{
      'headless with positional': [
        '-p',
        'hi',
        'x',
        'secret',
        'set',
        'n',
        _leak,
      ],
      'config check rest': ['config', 'check', 'secret', 'set', 'n', _leak],
      'config unknown sub': ['config', _leak, 'secret'],
      'profiles add rest': ['profiles', 'add', 'id', 'secret', _leak],
      'profiles show unknown': ['profiles', 'show', _leak, 'secret'],
      'later command': ['serve', _leak, 'secret'],
      'bad agent value': ['--agent', _leak, 'secret'],
      'bad folder': ['-C', '/no/such/$_leak', 'secret', 'x'],
      'scenario path': ['test-scenario', '/no/such/$_leak', 'secret'],
    };
    for (final entry in cases.entries) {
      test(entry.key, () async {
        final (code, io) = await run(entry.value);
        expect(code, isNot(0));
        final all = '${io.stdoutText}${io.stderrText}';
        expect(all, isNot(contains('sk-LEAK')));
        expect(all, isNot(contains('0123456789')));
      });
    }
    test('config frobnicate without secret keeps the spec text', () async {
      final (code, io) = await run(['config', 'frobnicate']);
      expect(code, 64);
      expect(io.stderrText, contains('Unknown command config frobnicate'));
    });

    test(
      'config frobnicate with secret in argv: fixed text, no token',
      () async {
        final (code, io) = await run(['config', 'frobnicate', 'secret', _leak]);
        expect(code, 64);
        expect(io.stderrText, isNot(contains('frobnicate')));
        expect(io.stderrText, isNot(contains('sk-LEAK')));
      },
    );
  });
}
