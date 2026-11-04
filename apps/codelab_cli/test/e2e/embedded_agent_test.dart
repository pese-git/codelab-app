// E2E встроенного агента в CLI (tasks 3.7; spec codelab-cli «Профили
// подключения CLI» и «Встроенный агент в CLI»; testing-quality «Встроенный
// режим в e2e и conformance»; design.md change `add-embedded-agent-mode`, D5,
// D6, D8, D13 п. 1).
//
// Тесты идут в любом варианте прогона: встроенный агент — часть самого CLI, а
// не внешний процесс. Сценарий модели подставляет тестовая точка входа
// `support/embedded_cli_main.dart` (`CliEntry.scriptedEmbedded`); тесты
// настоящего открывателя (конфиг, отладка секретов) идут через рабочий
// `bin/codelab.dart` (`CliEntry.production`).
@Timeout(Duration(seconds: 180))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

const _embeddedAnswer = 'hello from the embedded agent';

/// Сценарий модели с одним ответом [text].
Map<String, Object?> _textScript(String text) => {
  'llm': {
    'model': {
      'provider': 'scripted',
      'modelId': 'scripted-1',
      'contextWindow': 32768,
    },
    'steps': [
      {
        'reply': [
          {'text': text},
        ],
        'stopReason': 'stop',
      },
    ],
  },
};

/// Сценарий: модель просит записать файл `notes.txt`.
Map<String, Object?> _writeScript() => {
  'llm': {
    'model': {
      'provider': 'scripted',
      'modelId': 'scripted-1',
      'contextWindow': 32768,
    },
    'steps': [
      {
        'reply': [
          {
            'toolCall': {
              'id': 'write_1',
              'name': 'write',
              'arguments': {'path': 'notes.txt', 'content': 'x'},
            },
          },
        ],
        'stopReason': 'toolUse',
      },
      {
        'expect': {
          'toolResult': {'toolCallId': 'write_1'},
        },
        'reply': [
          {'text': 'done'},
        ],
        'stopReason': 'stop',
      },
    ],
  },
};

void main() {
  // Встроенный агент — часть самого CLI, а не выбранный агент: достаточно
  // вариантов `scripted` (прогон `test`) и `embedded`; в `dart` и `python`
  // они только удлинили бы прогон.
  final skip = switch (E2eCliAgent.current.kind) {
    E2eAgentKind.scripted || E2eAgentKind.embedded => null,
    _ => 'covered by the scripted and embedded runs',
  };
  group('embedded agent in the CLI', () {
    body();
  }, skip: skip);
}

void body() {
  late Directory tmp;
  late String home;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_embedded_');
    home = '${tmp.path}/home';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Окружение процесса со сценарием [script], записанным в файл.
  Map<String, String> scripted(
    Map<String, Object?> script, {
    String? permissionMode,
  }) {
    final file = File('${tmp.path}/script.json')
      ..writeAsStringSync(jsonEncode(script));
    return {
      'CODELAB_HOME': home,
      'CODELAB_E2E_LLM_SCRIPT': file.path,
      'CODELAB_E2E_PERMISSION_MODE': ?permissionMode,
    };
  }

  Future<CliResult> run(
    List<String> args,
    Map<String, String> environment, {
    CliEntry entry = CliEntry.scriptedEmbedded,
  }) => CliProcess.run(
    [...args, '-C', tmp.path],
    environment: environment,
    entry: entry,
  );

  /// Профиль `external` — внешний scripted-агент, чей ответ отличается от
  /// ответа встроенного. Профиль `default` сохранить нельзя: он
  /// зарезервирован (D21).
  Future<void> addExternalProfile(Map<String, String> environment) async {
    final agent = await scriptedAgent(tmp);
    final added = await CliProcess.run([
      'profiles',
      'add',
      'external',
      agent,
    ], environment: environment);
    expect(added.exitCode, 0, reason: '$added');
  }

  group('profile choice', () {
    test(
      'without a profile the embedded agent runs the turn, no agent '
      'process is started (cli/connect-profiles-stdio-ws-embedded)',
      () async {
        final result = await run([
          '-p',
          'hi',
        ], scripted(_textScript(_embeddedAnswer)));

        expect(result.exitCode, 0, reason: '$result');
        expect(result.stdout, '$_embeddedAnswer\n');
      },
    );

    test('a stored profile does not beat the embedded agent without '
        '--agent and is selected by -a <id>', () async {
      final environment = scripted(_textScript(_embeddedAnswer));
      await addExternalProfile(environment);

      final implicit = await run(['-p', 'hi'], environment);
      final explicit = await run(['-a', 'external', '-p', 'hi'], environment);

      expect(implicit.exitCode, 0, reason: '$implicit');
      expect(implicit.stdout, '$_embeddedAnswer\n');
      expect(explicit.exitCode, 0, reason: '$explicit');
      expect(explicit.stdout, 'hello from compatible stdio agent\n');
    });

    test('-a default is the embedded agent, an old "default" record is '
        'ignored with one warning and stays in the file (D21)', () async {
      final environment = scripted(_textScript(_embeddedAnswer));
      Directory(home).createSync(recursive: true);
      File('$home/profiles.json').writeAsStringSync(
        jsonEncode({
          'version': 1,
          'profiles': [
            {
              'type': 'stdio',
              'id': 'default',
              'label': 'Default',
              'command': '/opt/secret-agent',
              'args': <String>[],
              'env': <String, String>{},
              'runInProjectDirectory': false,
            },
          ],
        }),
      );

      final result = await run(['-a', 'default', '-p', 'hi'], environment);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, '$_embeddedAnswer\n');
      expect(
        result.stderr,
        contains('profile "default" in profiles.json is ignored'),
      );
      expect(result.stderr, isNot(contains('/opt/secret-agent')));
      expect(
        File('$home/profiles.json').readAsStringSync(),
        contains('default'),
      );
    });

    test('-a embedded beats a stored profile', () async {
      final environment = scripted(_textScript(_embeddedAnswer));
      await addExternalProfile(environment);

      final result = await run(['-a', 'embedded', '-p', 'hi'], environment);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, '$_embeddedAnswer\n');
    });

    test('a broken profiles.json without --agent does not stop the '
        'embedded agent, with -a <id> it is 64', () async {
      final environment = scripted(_textScript(_embeddedAnswer));
      Directory(home).createSync(recursive: true);
      File('$home/profiles.json').writeAsStringSync('{not json');

      final implicit = await run(['-p', 'hi'], environment);
      final explicit = await run(['-a', 'dev', '-p', 'hi'], environment);

      expect(implicit.exitCode, 0, reason: '$implicit');
      expect(implicit.stdout, '$_embeddedAnswer\n');
      expect(explicit.exitCode, 64, reason: '$explicit');
      expect(explicit.stdout, isEmpty);
      expect(explicit.stderr, contains('Cannot read agent profiles'));
    });
  });

  group('permissions', () {
    test('without --approve a write is rejected, the file is not '
        'changed (spec «Отказ по умолчанию в headless»)', () async {
      final result = await run([
        '-a',
        'embedded',
        '-p',
        'write file',
      ], scripted(_writeScript(), permissionMode: 'standard'));

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stderr, contains('reject_once (policy)'));
      expect(File('${tmp.path}/notes.txt').existsSync(), isFalse);
    });

    test('--approve allow-all lets the same write run', () async {
      final result = await run([
        '-a',
        'embedded',
        '-p',
        'write file',
        '--approve',
        'allow-all',
      ], scripted(_writeScript(), permissionMode: 'standard'));

      expect(result.exitCode, 0, reason: '$result');
      expect(File('${tmp.path}/notes.txt').readAsStringSync(), 'x');
    });
  });

  group('configuration of the real opener', () {
    test('an invalid project config is 64 with the problem, the file and '
        'the hint (spec «Невалидный конфиг встроенного агента»)', () async {
      Directory('${tmp.path}/.codelab').createSync();
      File(
        '${tmp.path}/.codelab/config.yaml',
      ).writeAsStringSync('budget:\n  max_steps: 0\n');

      final result = await run(
        ['-a', 'embedded', '-p', 'hi'],
        {'CODELAB_HOME': home},
        entry: CliEntry.production,
      );

      expect(result.exitCode, 64, reason: '$result');
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('budget.max_steps'));
      expect(result.stderr, contains('config.yaml'));
      expect(
        result.stderr,
        contains(
          'Configure the embedded agent in $home/config.yaml; '
          'check it with: codelab config check',
        ),
      );
    });

    test('--debug-secrets --verbose logs the lookup by name and source, '
        'never the value (spec «Отладка секретов»)', () async {
      const value = 'sk-e2e-embedded-secret-value';
      Directory(home).createSync(recursive: true);
      File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: http://127.0.0.1:1/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
      final process = await CliProcess.start(
        [
          '-a',
          'embedded',
          '--debug-secrets',
          '--verbose',
          '-p',
          'hi',
          '-C',
          tmp.path,
        ],
        environment: {'CODELAB_HOME': home, 'CODELAB_SECRET_CODELAB_P': value},
        entry: CliEntry.production,
      );
      addTearDown(() => process.kill(ProcessSignal.sigkill));

      // Ключ запрашивается перед первым запросом к провайдеру; сам запрос
      // уходит на закрытый порт, сети нет.
      await process.waitFor('secrets.lookup');
      process.kill(ProcessSignal.sigterm);
      final result = await process.result();

      expect(result.stderr, contains('secrets.lookup'));
      expect(result.stderr, contains('name=codelab/p'));
      expect(result.stderr, contains('source=env'));
      expect('${result.stdout}${result.stderr}', isNot(contains(value)));
    });
  });

  test('SIGTERM during the turn is 143 and the journal ends the turn with '
      '"aborted" (cancelled) before the process exits (spec «Журнал '
      'дописан при SIGTERM»)', () async {
    final environment = scripted(
      jsonDecode(
            File(
              '$appDirectory/test/e2e/llm_scripts/hangs_until_cancel.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>,
    );
    final process = await CliProcess.start(
      ['-a', 'embedded', '-p', 'hello', '-C', tmp.path, '-v'],
      environment: environment,
      entry: CliEntry.scriptedEmbedded,
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    await process.waitFor('to=ClientConnectionReady');
    // Ход начался, когда в журнале есть реплика пользователя: сигнал раньше
    // отменил бы только подключение.
    final sessions = Directory('$home/sessions');
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!_journals(
      sessions,
    ).any((f) => f.readAsStringSync().contains('hello'))) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the turn did not start:\n${process.stderrText}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    process.kill(ProcessSignal.sigterm);
    final result = await process.result();

    expect(result.exitCode, 143, reason: '$result');
    // Журнал называет отменённый ход `aborted` (итог ACP — `cancelled`):
    // итоговая запись хода дописана до выхода процесса, `dispose`
    // встроенного агента дождались (design.md change
    // `add-embedded-agent-mode`, D6). Последнее сообщение — ответ агента с
    // `aborted`, а не просто упоминание слова где-то в журнале.
    final messages = [
      for (final file in _journals(sessions))
        for (final line in const LineSplitter().convert(
          file.readAsStringSync(),
        ))
          if (jsonDecode(line) case {'type': 'message', 'message': final Map m})
            m,
    ];
    expect(messages.last['role'], 'assistant');
    expect(messages.last['stopReason'], 'aborted');
  });
}

List<File> _journals(Directory sessions) => sessions.existsSync()
    ? [
        for (final entity in sessions.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.jsonl')) entity,
      ]
    : const [];
