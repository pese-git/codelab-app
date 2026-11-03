import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent config path|get|set|unset`, `provider add|list|remove` и
/// `mcp add|list|remove` как процесс (agent-binary «Подкоманда config
/// бинаря», все сценарии; design.md change `add-config-writer-and-reload`,
/// D6, D15; задача 4.3). Интеграционный тест на Dart VM: процесс бинаря во
/// временных `CODELAB_HOME` и каталоге проекта, настоящий `~/.codelab` не
/// читается; значения «секретов» выдуманные.
void main() {
  late Directory temp;
  late String home;
  late String project;

  const key = 'sk-test-0123456789abcdef';

  setUp(() {
    // Каталог сразу канонический: писатель раскрывает ссылки (на macOS `/var` —
    // ссылка на `/private/var`), и путь в выводе должен совпасть с ожиданием.
    temp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_agent_config_write_')
          .resolveSymbolicLinksSync(),
    );
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Запускает бинарь без чтения stdin (кроме [stdin]) и ждёт выхода;
  /// возвращает код, stdout и stderr.
  Future<(int, String, String)> run(
    List<String> args, {
    String stdin = '',
    Map<String, String> environment = const {},
  }) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': home, ...environment},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    if (stdin.isNotEmpty) {
      agent.sendLine(stdin);
      await agent.closeStdin();
    }
    final code = await agent.exitCode.timeout(const Duration(seconds: 60));
    final out = StringBuffer();
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.writeln(line);
    }
    return (code, out.toString(), agent.stderrText);
  }

  String read(String path) => File(path).readAsStringSync();

  void expectNoServer() {
    // Подкоманда не запускает сервер: логов хоста и транспорта нет.
    expect(Directory('$home/logs').existsSync(), isFalse);
  }

  test('config set: код 0, ключ записан, комментарии файла сохранены, '
      'транспорт не открыт', () async {
    File(
      '$home/config.yaml',
    ).writeAsStringSync('# my settings\nbudget:\n  max_steps: 3 # three\n');

    final (code, out, err) = await run([
      'config',
      'set',
      'budget.max_steps',
      '10',
    ]);

    expect(code, 0, reason: err);
    expect(out, contains('Updated budget.max_steps in $home/config.yaml'));
    final text = read('$home/config.yaml');
    expect(text, contains('# my settings'));
    expect(text, contains('max_steps: 10 # three'));
    expectNoServer();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('config set, get, unset и path работают вместе', () async {
    final (setCode, _, setErr) = await run([
      'config',
      'set',
      'budget.max_steps',
      '40',
    ]);
    final (getCode, getOut, getErr) = await run([
      'config',
      'get',
      'budget.max_steps',
    ]);
    final (pathCode, pathOut, pathErr) = await run(['config', 'path']);
    final (unsetCode, unsetOut, unsetErr) = await run([
      'config',
      'unset',
      'budget.max_steps',
    ]);

    expect(setCode, 0, reason: setErr);
    expect(getCode, 0, reason: getErr);
    expect(getOut, '40\nlayer: user\n');
    expect(pathCode, 0, reason: pathErr);
    expect(pathOut, startsWith('user: $home/config.yaml (exists)\n'));
    expect(pathOut, contains('project: '));
    expect(unsetCode, 0, reason: unsetErr);
    expect(unsetOut, contains('Removed budget.max_steps from'));
    expect(read('$home/config.yaml'), isNot(contains('max_steps')));
  }, timeout: const Timeout(Duration(seconds: 240)));

  test(
    'config get: окружение учитывается, значение переменной не печатается',
    () async {
      final (code, out, err) = await run(
        ['config', 'get', 'agent.default_model'],
        environment: {'CODELAB_MODEL': 'p/secret-model-name'},
      );

      expect(code, 0, reason: err);
      expect(out, contains('<from env:CODELAB_MODEL>'));
      expect(out, isNot(contains('secret-model-name')));
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'config set неизвестного ключа: код 64 с подсказкой, файл не создан',
    () async {
      final (code, out, err) = await run([
        'config',
        'set',
        'budget.max_stepz',
        '10',
      ]);

      expect(code, 64, reason: err);
      expect(out, isEmpty);
      expect(err, contains('budget.max_steps'));
      expect(File('$home/config.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'config migrate и mcp frob: код 64, справка команды, файлы не изменены',
    () async {
      final (migrateCode, migrateOut, migrateErr) = await run([
        'config',
        'migrate',
      ]);
      final (frobCode, frobOut, frobErr) = await run(['mcp', 'frob']);

      expect(migrateCode, 64, reason: migrateErr);
      expect(migrateOut, isEmpty);
      expect(migrateErr, contains('Usage: codelab-agent config'));
      expect(frobCode, 64, reason: frobErr);
      expect(frobOut, isEmpty);
      expect(frobErr, contains('Usage: codelab-agent mcp'));
      expect(File('$home/config.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('config, provider и mcp без подкоманды, лишние и недостающие аргументы: '
      'код 64 со справкой', () async {
    for (final (args, usage) in [
      (['config'], 'Usage: codelab-agent config'),
      (['provider'], 'Usage: codelab-agent provider'),
      (['mcp'], 'Usage: codelab-agent mcp'),
      (['config', 'set', 'budget.max_steps'], 'Usage: codelab-agent config'),
      (['config', 'get', 'a', 'b'], 'Usage: codelab-agent config'),
      (['provider', 'remove'], 'Usage: codelab-agent provider'),
      (['mcp', 'remove'], 'Usage: codelab-agent mcp'),
    ]) {
      final (code, out, err) = await run(args);

      expect(code, 64, reason: '$args: $err');
      expect(out, isEmpty, reason: '$args');
      expect(err, contains(usage), reason: '$args');
    }
    expect(File('$home/config.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('ошибка разбора аргументов: config check --bogus и --cwd без значения — '
      'код 64, причина и справка config, stdout пуст', () async {
    final (bogusCode, bogusOut, bogusErr) = await run([
      'config',
      'check',
      '--bogus',
    ]);
    final (cwdCode, cwdOut, cwdErr) = await run(['config', 'check', '--cwd']);

    expect(bogusCode, 64, reason: bogusErr);
    expect(bogusOut, isEmpty);
    expect(bogusErr, contains('Usage: codelab-agent config'));
    expect(cwdCode, 64, reason: cwdErr);
    expect(cwdOut, isEmpty);
    expect(cwdErr, contains('Usage: codelab-agent config'));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'ошибка разбора provider и mcp не цитирует слово из argv: ключ флагом по '
    'ошибке и неизвестный флаг со значением (ревью итерации 4, arch M3)',
    () async {
      for (final (args, leak, usage) in [
        (
          ['provider', 'add', 'gw', '--api-key', 'sk-leak-1'],
          'sk-leak-1',
          'Usage: codelab-agent provider',
        ),
        (
          ['mcp', 'add', 'x', '--bogus=<leak>'],
          '<leak>',
          'Usage: codelab-agent mcp',
        ),
        // Флаг верхнего уровня перед командой: команда определяется по argv,
        // а не по первому слову.
        (
          ['--X-leak', 'provider', 'add', 'gw'],
          '--X-leak',
          'Usage: codelab-agent provider',
        ),
        (['--X-leak', 'mcp', 'list'], '--X-leak', 'Usage: codelab-agent mcp'),
      ]) {
        final (code, out, err) = await run(args);

        expect(code, 64, reason: '$args: $err');
        expect(out, isEmpty, reason: '$args');
        expect(
          err,
          contains(
            'codelab-agent: invalid arguments for ${args.contains('mcp') ? 'mcp' : 'provider'}',
          ),
          reason: '$args',
        );
        expect(err, contains(usage), reason: '$args');
        expect(err, isNot(contains(leak)), reason: '$args');
      }
      expect(File('$home/config.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 240)),
  );

  test('ошибка разбора config set|unset: фиксированная фраза без слов из argv '
      '(значение set может начинаться с "-")', () async {
    for (final (args, sub) in [
      (['config', 'set', 'logging.file', '--leak-1'], 'set'),
      (['config', 'set', 'logging.file', '-leak-2'], 'set'),
      (['config', 'unset', '--leak-3'], 'unset'),
    ]) {
      final (code, out, err) = await run(args);

      expect(code, 64, reason: '$args: $err');
      expect(out, isEmpty, reason: '$args');
      expect(
        err,
        contains('codelab-agent: invalid arguments for config $sub'),
        reason: '$args',
      );
      expect(err, contains('Usage: codelab-agent config'), reason: '$args');
      expect(err, isNot(contains('leak')), reason: '$args');
    }
    expect(File('$home/config.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('--project вместе с --local: код 64 и текст общей реализации, файлы не '
      'созданы (ревью итерации 4, arch L1)', () async {
    final (code, out, err) = await run([
      'config',
      'set',
      'budget.max_steps',
      '5',
      '--project',
      '--local',
    ]);
    final (mcpCode, _, mcpErr) = await run([
      'mcp',
      'remove',
      'srv',
      '--project',
      '--local',
    ]);

    expect(code, 64, reason: err);
    expect(out, isEmpty);
    expect(err, contains('config set: --project and --local cannot be '));
    expect(mcpCode, 64, reason: mcpErr);
    expect(mcpErr, contains('mcp remove: --project and --local cannot be '));
    expect(File('$home/config.yaml').existsSync(), isFalse);
    expect(Directory('$project/.codelab').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('общая справка называет config, provider и mcp', () async {
    final (code, out, err) = await run(['serve', '--stdio', '--bogus']);

    expect(code, 64, reason: err);
    expect(out, isEmpty);
    expect(err, contains('config'));
    expect(err, contains('provider'));
    expect(err, contains('mcp'));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'provider add --api-key-stdin на бэкенде file: ключ читается из stdin '
    'и не попадает ни в вывод, ни в конфиг; provider list и remove',
    () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');

      final (addCode, addOut, addErr) = await run([
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
        '--api-key-stdin',
        '--default',
      ], stdin: key);
      final (listCode, listOut, listErr) = await run(['provider', 'list']);
      final (removeCode, _, removeErr) = await run([
        'provider',
        'remove',
        'gw',
      ]);

      expect(addCode, 0, reason: addErr);
      expect(read('$home/secrets.yaml'), contains('codelab/gw'));
      final config = read('$home/config.yaml');
      expect(config, contains('api_key_secret: codelab/gw'));
      expect(config, contains('default_model: gw/m'));
      expect(config, isNot(contains(key)));
      expect(addOut + addErr, isNot(contains(key)));
      expect(listCode, 0, reason: listErr);
      expect(listOut, startsWith('Secrets: file\n'));
      expect(listOut, contains('secret codelab/gw: found'));
      expect(listOut + listErr, isNot(contains(key)));
      // gw — модель по умолчанию: удаление отклоняется, файл цел.
      expect(removeCode, 1, reason: removeErr);
      expect(removeErr, contains('agent.default_model'));
      expect(read('$home/config.yaml'), config);
    },
    timeout: const Timeout(Duration(seconds: 240)),
  );

  test('mcp add, list и remove без подключения к серверу', () async {
    final (addCode, addOut, addErr) = await run([
      'mcp',
      'add',
      'srv',
      '--type',
      'stdio',
      '--command',
      'definitely-not-installed-binary',
      '--arg',
      '-y',
      '--env',
      'MODE=fast',
    ]);
    final (listCode, listOut, listErr) = await run(['mcp', 'list']);
    final (removeCode, removeOut, removeErr) = await run([
      'mcp',
      'remove',
      'srv',
    ]);

    expect(addCode, 0, reason: addErr);
    expect(addOut, contains('Updated mcp.servers[srv] in'));
    expect(listCode, 0, reason: listErr);
    expect(listOut, contains('srv'));
    expect(listOut, contains('stdio'));
    expect(removeCode, 0, reason: removeErr);
    expect(removeOut, contains('Removed mcp.servers[srv] from'));
    expect(read('$home/config.yaml'), isNot(contains('srv')));
  }, timeout: const Timeout(Duration(seconds: 240)));

  test(
    'mcp add с литеральным токеном: код 1, значение не печатается',
    () async {
      final (code, out, err) = await run([
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

      expect(code, 1, reason: err);
      expect(out, isEmpty);
      expect(err, contains(r'${secret:codelab/mcp/github/authorization}'));
      expect(err, isNot(contains('ghp_x')));
      expect(File('$home/config.yaml').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
