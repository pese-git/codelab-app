import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent config` (agent-binary «Подкоманда config бинаря»; задачи
/// 10.3–10.4, design.md change `add-agent-configuration`, D13). Интеграционный
/// тест на Dart VM: процесс бинаря во временном каталоге, stdin не закрывается
/// и ничего не получает — процесс обязан выйти сам.
void main() {
  late Directory temp;
  late String project;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_config_cmd_');
    project = '${temp.path}/project';
    Directory('$project/.codelab').createSync(recursive: true);
  });

  tearDown(() => temp.delete(recursive: true));

  Future<(int, AgentProcess)> run(List<String> args) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': '${temp.path}/home'},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    final code = await agent.exitCode.timeout(const Duration(seconds: 30));
    return (code, agent);
  }

  test(
    'config check: valid config, Config: valid, code 0, no transport',
    () async {
      // Провайдеры принимаются только из глобального слоя: проект без доверия
      // их не расширяет (CFG-3).
      Directory('${temp.path}/home').createSync();
      File('${temp.path}/home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''');

      final (code, agent) = await run(['config', 'check']);

      expect(code, 0, reason: agent.stderrText);
      var last = '';
      String? line;
      while ((line = await agent.nextStdoutLine()) != null) {
        last = line!;
      }
      expect(last, 'Config: valid');
      expect(agent.stderrText, isEmpty);
      expect(Directory('${temp.path}/home/logs').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('config check: secrets.backend: keychain gives code 1 and the problem, '
      'no transport', () async {
    // agent-secrets «keychain ещё не поддерживается»: `config check` — код 1.
    Directory('${temp.path}/home').createSync();
    File(
      '${temp.path}/home/config.yaml',
    ).writeAsStringSync('secrets:\n  backend: keychain\n');

    final (code, agent) = await run(['config', 'check']);

    expect(code, 1, reason: agent.stderrText);
    final out = <String>[];
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.add(line!);
    }
    expect(
      out.join('\n'),
      contains(
        'secrets.backend: keychain is not supported yet '
        '(supported: auto, env, file)',
      ),
    );
    expect(out.last, isNot('Config: valid'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('config check: a typo gives code 1 and the position', () async {
    File('$project/.codelab/config.yaml').writeAsStringSync('budgett: {}\n');

    final (code, agent) = await run(['config', 'check']);

    expect(code, 1, reason: agent.stderrText);
    final out = <String>[];
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.add(line!);
    }
    expect(out.join('\n'), contains('config.yaml:1:1: budgett'));
    expect(out.last, startsWith('Config: invalid (issues: '));
  }, timeout: const Timeout(Duration(seconds: 90)));

  // Диагностика файлов проекта (change `add-agent-project-files`, D13):
  // битый шаблон пользователя виден в `config check` бинаря, конфиг остаётся
  // валидным, код выхода прежний.
  test('config check: a broken template is a warning line, code 0', () async {
    Directory('${temp.path}/home/prompts').createSync(recursive: true);
    File('${temp.path}/home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''');
    File('${temp.path}/home/prompts/Review.md').writeAsStringSync('body\n');

    final (code, agent) = await run(['config', 'check']);

    expect(code, 0, reason: agent.stderrText);
    final out = <String>[];
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.add(line!);
    }
    expect(
      out,
      contains(
        allOf(
          startsWith('warning: '),
          contains('home/prompts/Review.md'),
          contains('not a valid command name'),
        ),
      ),
    );
    expect(out.last, 'Config: valid');
  }, timeout: const Timeout(Duration(seconds: 90)));

  // «Сбой загрузчика» (change `add-agent-project-files`, D13, D14):
  // D17: `CODELAB_HOME=~user/x` — ошибка использования, код 64; тот же текст
  // и тот же код, что у `codelab config check` (сбой загрузчика файлов
  // проекта в процессе не воспроизвести, он покрыт фейковым источником).
  test(
    'config check: CODELAB_HOME=~user/x is a usage error, code 64',
    () async {
      final agent = await AgentProcess.start(
        ['config', 'check', '--cwd', project],
        environment: {'CODELAB_HOME': '~bob/x', 'HOME': '${temp.path}/h'},
        workingDirectory: project,
      );
      addTearDown(() async {
        agent.kill(ProcessSignal.sigkill);
        await agent.exitCode;
      });
      final code = await agent.exitCode.timeout(const Duration(seconds: 30));

      expect(code, 64, reason: agent.stderrText);
      expect(
        agent.stderrText,
        contains(
          'config check: CODELAB_HOME: ~user is not supported, use an '
          'absolute path',
        ),
      );
      expect(await agent.nextStdoutLine(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // agent-configuration «Тильда без домашнего каталога»: `~/x` без `HOME`
  // (пустой) и `USERPROFILE` (не задан — `AgentProcess` его не передаёт) —
  // ошибка использования, код 64, тот же текст, что у `codelab-agent serve`.
  test(
    'config check: CODELAB_HOME=~/x without HOME or USERPROFILE is code 64',
    () async {
      final agent = await AgentProcess.start(
        ['config', 'check', '--cwd', project],
        environment: {'CODELAB_HOME': '~/x', 'HOME': ''},
        workingDirectory: project,
      );
      addTearDown(() async {
        agent.kill(ProcessSignal.sigkill);
        await agent.exitCode;
      });
      final code = await agent.exitCode.timeout(const Duration(seconds: 30));

      expect(code, 64, reason: agent.stderrText);
      expect(
        agent.stderrText,
        contains(
          'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an '
          'absolute path',
        ),
      );
      expect(await agent.nextStdoutLine(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // D17, 10.5 (защита от регрессий): `serve --stdio` с `~bob/cl` завершается
  // кодом 64 с текстом ошибки до чтения stdin.
  test(
    'serve --stdio: CODELAB_HOME=~user/cl is code 64, stdin not read',
    () async {
      final agent = await AgentProcess.start(
        ['serve', '--stdio'],
        environment: {'CODELAB_HOME': '~bob/cl', 'HOME': '${temp.path}/h'},
        workingDirectory: project,
      );
      addTearDown(() async {
        agent.kill(ProcessSignal.sigkill);
        await agent.exitCode;
      });
      final code = await agent.exitCode.timeout(const Duration(seconds: 30));

      expect(code, 64, reason: agent.stderrText);
      expect(
        agent.stderrText,
        contains('CODELAB_HOME: ~user is not supported, use an absolute path'),
      );
      expect(await agent.nextStdoutLine(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('config check: CODELAB_HOME=~/x reads <HOME>/x/config.yaml', () async {
    Directory('${temp.path}/h/x').createSync(recursive: true);
    File('${temp.path}/h/x/config.yaml').writeAsStringSync('budgett: {}\n');

    final agent = await AgentProcess.start(
      ['config', 'check', '--cwd', project],
      environment: {'CODELAB_HOME': '~/x', 'HOME': '${temp.path}/h'},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    final code = await agent.exitCode.timeout(const Duration(seconds: 30));

    // Неизвестный ключ `budgett` в файле под тильдой даёт ошибку конфигурации:
    // значит, файл прочитан.
    expect(code, 1, reason: agent.stderrText);
    final out = <String>[];
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.add(line!);
    }
    expect('${out.join('\n')}\n${agent.stderrText}', contains('budgett'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('config check --cwd <dir> reads that directory', () async {
    final other = '${temp.path}/other';
    Directory('$other/.codelab').createSync(recursive: true);
    File('$other/.codelab/config.yaml').writeAsStringSync('budgett: {}\n');

    final (code, agent) = await run(['config', 'check', '--cwd', other]);

    expect(code, 1, reason: agent.stderrText);
  }, timeout: const Timeout(Duration(seconds: 90)));

  for (final args in [
    ['config', 'set', 'budget.max_steps', '10'],
    ['config', 'migrate'],
    ['config'],
  ]) {
    test(
      '${args.join(' ')}: code 64, usage in stderr, file untouched',
      () async {
        final file = File('$project/.codelab/config.yaml')
          ..writeAsStringSync('budget:\n  max_steps: 3\n');

        final (code, agent) = await run(args);

        expect(code, 64);
        expect(agent.stderrText, contains('config check'));
        expect(await agent.nextStdoutLine(), isNull);
        expect(file.readAsStringSync(), 'budget:\n  max_steps: 3\n');
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }

  // Ошибка разбора `config …` получает справку команды `config`, а не
  // `serve`: пользователь, написавший `config check --bogus`, ищет флаги
  // именно `check`.
  for (final args in [
    ['config', 'check', '--bogus'],
    ['config', 'check', '--cwd'],
    ['config', '--x'],
  ]) {
    test(
      '${args.join(' ')}: code 64, the config usage, empty stdout',
      () async {
        final (code, agent) = await run(args);

        expect(code, 64);
        expect(agent.stderrText, contains('config check'));
        expect(agent.stderrText, isNot(contains('--stdio | --ws')));
        expect(await agent.nextStdoutLine(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }

  test('the general usage names config check', () async {
    final (code, agent) = await run(['bogus']);

    expect(code, 64);
    expect(agent.stderrText, contains('codelab-agent config check'));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
