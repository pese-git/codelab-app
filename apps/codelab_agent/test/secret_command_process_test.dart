import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent secret` как процесс (agent-binary «Подкоманда secret
/// бинаря», все сценарии; agent-secrets «Значение аргументом», «Только чтение
/// при auto», «Сохранение в file»; задача 8.5, design.md change
/// `add-agent-secret-store`, D8). Интеграционный тест на Dart VM: процесс
/// бинаря во временном `CODELAB_HOME`; значения — тестовые.
void main() {
  late Directory temp;
  late String home;

  const value = 'sk-test-0123456789abcdef';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_secret_cmd_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Запускает бинарь; [stdin] — строка для stdin, затем он закрывается.
  Future<(int, String, String)> run(
    List<String> args, {
    String stdin = '',
    Map<String, String> environment = const {},
  }) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': home, ...environment},
      workingDirectory: temp.path,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    if (stdin.isNotEmpty) {
      agent.sendLine(stdin);
    }
    await agent.closeStdin();
    final code = await agent.exitCode.timeout(const Duration(seconds: 60));
    final out = StringBuffer();
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.writeln(line);
    }
    return (code, out.toString(), agent.stderrText);
  }

  test(
    'no home folder at all: secret list exits 64 and creates nothing in cwd',
    () async {
      final (code, out, err) = await run(
        ['secret', 'list'],
        environment: {'CODELAB_HOME': '', 'HOME': ''},
      );

      expect(code, 64, reason: err);
      expect(out, isEmpty);
      expect(
        err,
        contains('cannot find the home folder: set CODELAB_HOME or HOME'),
      );
      expect(err, isNot(contains('Usage:')));
      expect(Directory('${temp.path}/.codelab').existsSync(), isFalse);
      expect(File('${temp.path}/secrets.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('no home folder at all: set with secrets.backend: file in '
      'CODELAB_CONFIG exits 64 and creates nothing in cwd', () async {
    // agent-secrets «Нет домашнего каталога»: `set` и `delete` так же, как
    // `list`, отказывают до записи и до создания файлов в текущем каталоге.
    final extra = File('${temp.path}/extra.yaml')
      ..writeAsStringSync('secrets:\n  backend: file\n');
    final env = {'CODELAB_HOME': '', 'HOME': '', 'CODELAB_CONFIG': extra.path};

    final (setCode, setOut, setErr) = await run(
      ['secret', 'set', 'codelab/openai'],
      stdin: value,
      environment: env,
    );
    final (delCode, delOut, delErr) = await run([
      'secret',
      'delete',
      'codelab/openai',
    ], environment: env);

    for (final (code, out, err) in [
      (setCode, setOut, setErr),
      (delCode, delOut, delErr),
    ]) {
      expect(code, 64, reason: err);
      expect(out, isEmpty);
      expect(
        err,
        contains('cannot find the home folder: set CODELAB_HOME or HOME'),
      );
      expect(err, isNot(contains('Usage:')));
      expect(err, isNot(contains(value)));
    }
    expect(Directory('${temp.path}/.codelab').existsSync(), isFalse);
    expect(File('${temp.path}/secrets.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('CODELAB_CONFIG gives secrets.backend to the subcommand: set stores '
      'in file, list names the explicit backend', () async {
    // agent-secrets «Подкоманды secret»: бэкенд берётся из файла
    // `CODELAB_CONFIG` (он сильнее `config.yaml`, который его не задаёт).
    final extra = File('${temp.path}/extra.yaml')
      ..writeAsStringSync('secrets:\n  backend: file\n');
    final env = {'CODELAB_CONFIG': extra.path};

    final (setCode, setOut, setErr) = await run(
      ['secret', 'set', 'codelab/openai'],
      stdin: value,
      environment: env,
    );
    final (listCode, listOut, listErr) = await run([
      'secret',
      'list',
    ], environment: env);

    expect(setCode, 0, reason: setErr);
    expect(setOut, 'Stored secret codelab/openai in file\n');
    expect(File('$home/secrets.yaml').existsSync(), isTrue);
    expect(listCode, 0, reason: listErr);
    expect(listOut, 'Backend: file\ncodelab/openai\n');
    expect(setOut + setErr + listOut + listErr, isNot(contains(value)));
  }, timeout: const Timeout(Duration(seconds: 180)));

  test(
    'an unknown subcommand: code 64, the secret usage, stdout is empty',
    () async {
      final (code, out, err) = await run(['secret', 'show', 'codelab/openai']);

      expect(code, 64, reason: err);
      expect(out, isEmpty);
      expect(err, contains('Usage: codelab-agent secret'));
      // agent-binary «Неизвестная подкоманда»: текст и отсутствие слова
      // пользователя в выводе (в аргументах может быть секрет).
      expect(err, contains('secret needs a subcommand'));
      expect(err, isNot(contains('codelab/openai')));
      expect(out, isNot(contains('codelab/openai')));
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('no subcommand: code 64 and the usage', () async {
    final (code, out, err) = await run(['secret']);

    expect(code, 64);
    expect(out, isEmpty);
    expect(err, contains('Usage: codelab-agent secret'));
  }, timeout: const Timeout(Duration(seconds: 120)));

  // Значение, переданное флагом или «коротким флагом»: разбор аргументов
  // упал бы с текстом, цитирующим слово. Ни значения, ни его кусков из
  // 4+ символов в выводе быть не должно.
  for (final argument in ['--value=$value', '-$value']) {
    test('the value as "${argument.substring(0, 8)}…": code 64, the secret '
        'usage, no part of the value in the output', () async {
      final (code, out, err) = await run([
        'secret',
        'set',
        'codelab/x',
        argument,
      ]);

      expect(code, 64, reason: err);
      expect(err, contains('Usage: codelab-agent secret'));
      for (final text in [out, err]) {
        for (var i = 0; i + 4 <= value.length; i++) {
          expect(
            text,
            isNot(contains(value.substring(i, i + 4))),
            reason: 'substring at $i leaked',
          );
        }
      }
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 120)));
  }

  test('list with secrets.backend: env: the first line is Backend: env, '
      'code 0', () async {
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');

    final (code, out, err) = await run(
      ['secret', 'list'],
      environment: {'CODELAB_SECRET_X': '1'},
    );

    expect(code, 0, reason: err);
    expect(out.split('\n').first, 'Backend: env');
    expect(out, contains('Environment overrides: CODELAB_SECRET_X'));
    expect(err, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a value argument: code 64, the argument is not printed, the store '
      'is not touched', () async {
    final (code, out, err) = await run([
      'secret',
      'set',
      'codelab/openai',
      value,
    ]);

    expect(code, 64);
    expect(err, contains('pass the secret value on stdin, not as an argument'));
    expect(err, isNot(contains(value)));
    expect(out, isNot(contains(value)));
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('auto: set is read-only, code 1, stdin is not read', () async {
    final (code, out, err) = await run([
      'secret',
      'set',
      'codelab/openai',
    ], stdin: value);

    expect(code, 1);
    expect(out, isEmpty);
    expect(err, contains('secrets.backend: file'));
    expect(err, contains('CODELAB_SECRET_CODELAB_OPENAI'));
    expect(err, isNot(contains(value)));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('file: set stores from stdin, then list and delete work', () async {
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: file\n');

    final (setCode, setOut, setErr) = await run([
      'secret',
      'set',
      'codelab/openai',
    ], stdin: value);

    expect(setCode, 0, reason: setErr);
    expect(setOut, 'Stored secret codelab/openai in file\n');
    expect(setErr, contains('warning: secrets are stored unencrypted'));
    expect(setOut + setErr, isNot(contains(value)));
    final file = File('$home/secrets.yaml');
    expect(file.existsSync(), isTrue);
    expect(file.statSync().mode & 0x1ff, 384); // 0600

    final (listCode, listOut, _) = await run(['secret', 'list']);
    expect(listCode, 0);
    expect(listOut, 'Backend: file\ncodelab/openai\n');

    final (delCode, delOut, _) = await run([
      'secret',
      'delete',
      'codelab/openai',
    ]);
    expect(delCode, 0);
    expect(delOut, 'Deleted secret codelab/openai from file\n');
  }, timeout: const Timeout(Duration(seconds: 180)));

  // agent-secrets «Ошибка флага верхнего уровня перед secret» (для
  // `codelab-agent`): текст `package:args` цитирует слово, а это могло быть
  // значение секрета — печатается только фиксированная фраза и справка.
  for (final args in [
    ['--$value', 'secret', 'list'],
    ['--no-such-flag=$value', 'secret', 'set', 'codelab/x'],
  ]) {
    test(
      'a top-level flag error before secret (${args.first.substring(0, 6)}…): '
      '64, fixed text, the secret usage, no echo',
      () async {
        final (code, out, err) = await run(args);

        expect(code, 64, reason: err);
        expect(out, isEmpty);
        expect(err, contains('codelab-agent: invalid arguments for secret'));
        expect(err, contains('Usage: codelab-agent secret'));
        expect(err, isNot(contains('Could not find an option')));
        for (final text in [out, err]) {
          for (var i = 0; i + 4 <= value.length; i++) {
            expect(
              text,
              isNot(contains(value.substring(i, i + 4))),
              reason: 'substring at $i leaked',
            );
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }

  for (final args in [
    ['serve', '--stdio', 'secret', 'set', 'codelab/x', value],
    ['config', 'check', 'secret', 'set', 'n', value],
  ]) {
    test('${args.take(2).join(' ')} with trailing secret tokens: 64, '
        'rest tokens are never quoted', () async {
      final (code, out, err) = await run(args);

      expect(code, 64, reason: err);
      for (final text in [out, err]) {
        for (var i = 0; i + 4 <= value.length; i++) {
          expect(
            text,
            isNot(contains(value.substring(i, i + 4))),
            reason: 'substring at $i leaked',
          );
        }
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  }

  test('the general usage names secret set|delete|list', () async {
    final (code, _, err) = await run(['bogus']);

    expect(code, 64);
    expect(err, contains('secret set|delete|list'));
  }, timeout: const Timeout(Duration(seconds: 120)));
}
