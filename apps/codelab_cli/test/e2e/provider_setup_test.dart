// PTY-e2e мастера провайдера, первого запуска, `/provider` и `/settings`
// (задача 4.4 change `add-provider-setup-ui`; spec codelab-cli «Мастер
// первого запуска CLI», «Команды /provider и /settings в REPL и TUI»,
// «Подкоманды codelab provider и codelab mcp»; design.md D15–D17;
// testing-quality «PTY-e2e терминального клиента»).
//
// Только Dart VM. Каждый тест работает во временных `CODELAB_HOME` и `HOME`;
// хранилище секретов — `secrets.backend: file` во временном доме (настоящие
// keychain и `~/.codelab` не читаются); ответы `/models` даёт фиктивный
// сервер на петле. Маркер утечки — `sk-test-leak-0123456789`.
//
// Точки входа: `scriptedEmbedded` — встроенный агент со сценарием модели
// (ход REPL без сети), `production` — настоящий агент (перечитывание конфига
// и `/model`). Мастер первого запуска и `/provider` читают конфиг самого
// CLI, поэтому сценарная точка входа им не мешает.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import '../support/fake_models_server.dart';
import '../support/setup_fakes.dart' show leakMarker;
import 'support/e2e_agent.dart';
import 'support/pty_process.dart';

const _down = '\x1b[B';
const _ctrlC = '\x03';
const _ctrlD = '\x04';

const _answer = 'hello from the embedded agent';

/// Конфиг с готовым провайдером: первый запуск не срабатывает.
const _readyConfig = '''
# my settings
providers:
  gw:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
secrets:
  backend: file
''';

/// Дом, из которого читается только `secrets.backend: file`: провайдеров нет.
const _emptyConfig = 'secrets:\n  backend: file\n';

void main() async {
  final skip = await PtyProcess.unavailableReason();
  late Directory dir;
  late String home;
  late String project;

  // Оба kernel собираются один раз и отдельным тестом: компиляция не должна
  // съедать 60 секунд таймаута сценария.
  test('kernel сборки CLI готовы', () async {
    await CliProcess.kernelOf(CliEntry.production);
    await CliProcess.kernelOf(CliEntry.scriptedEmbedded);
  }, timeout: const Timeout(Duration(seconds: 240)));

  setUp(() {
    // Канонический путь: писатель раскрывает ссылки (macOS: `/var`).
    dir = Directory(
      Directory.systemTemp
          .createTempSync('cli_provider_setup_')
          .resolveSymbolicLinksSync(),
    );
    home = '${dir.path}/codelab';
    project = '${dir.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void writeConfig(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  String config() => File('$home/config.yaml').readAsStringSync();

  /// Сценарий модели с одним ответом [_answer] для сценарной точки входа.
  Map<String, String> scriptEnv([String? scriptPath]) {
    final path = scriptPath ?? '${dir.path}/script.json';
    if (scriptPath == null) {
      File(path).writeAsStringSync(
        jsonEncode({
          'llm': {
            'model': {
              'provider': 'scripted',
              'modelId': 'scripted-1',
              'contextWindow': 32768,
            },
            'steps': [
              {
                'reply': [
                  {'text': _answer},
                ],
                'stopReason': 'stop',
              },
            ],
          },
        }),
      );
    }
    return {'CODELAB_E2E_LLM_SCRIPT': path};
  }

  Map<String, String> baseEnv([Map<String, String> extra = const {}]) => {
    'HOME': '${dir.path}/no-home',
    'CODELAB_HOME': home,
    'LANG': 'en_US.UTF-8',
    ...extra,
  };

  Future<PtyProcess> pty(
    List<String> args, {
    CliEntry entry = CliEntry.production,
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async => PtyProcess.start(
    dartExecutable(),
    [await CliProcess.kernelOf(entry), '-C', project, ...args],
    environment: baseEnv(environment),
    workingDirectory: workingDirectory,
  );

  /// Выбор пункта списка стрелками.
  void pick(PtyProcess pty, int index) {
    for (var i = 0; i < index; i++) {
      pty.write(_down);
    }
    pty.write('\r');
  }

  /// Ждёт любую из строк [needles] в выводе PTY.
  Future<void> waitForAny(PtyProcess pty, List<String> needles) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!needles.any(pty.text.contains)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('none of $needles in the terminal:\n${pty.text}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Проходит мастер Custom OpenAI-compatible: адрес [baseUrl], ключ [key]
  /// (`null` — «No key»), первая модель списка, подтверждение Enter.
  Future<void> walkWizard(PtyProcess pty, String baseUrl, {String? key}) async {
    await pty.waitFor('? API type');
    pick(pty, 4); // Custom OpenAI-compatible endpoint
    await pty.waitFor('? Base URL ›');
    pty.write('$baseUrl\r');
    await pty.waitFor('? API key source');
    if (key == null) {
      pick(pty, 2); // No key
    } else {
      pty.write('\r'); // Store in file as "codelab/<id>"
      await pty.waitFor('? API key ›');
      pty.write('$key\r');
    }
    await pty.waitFor('? Model (type to filter) ›');
    pty.write('\r');
    await pty.waitFor('? Save? [Y/n]');
    pty.write('\r');
  }

  void expectNoLeak(PtyProcess pty) {
    expect(pty.text, isNot(contains(leakMarker)));
    expect(config(), isNot(contains(leakMarker)));
    final history = File('$home/cli_history');
    if (history.existsSync()) {
      expect(history.readAsStringSync(), isNot(contains(leakMarker)));
    }
  }

  group('codelab provider add', () {
    test('cli/provider-wizard-writes-config: «Мастер provider add на TTY» — '
        'golden, комментарии и порядок сохранены', () async {
      final server = await FakeModelsServer.start();
      const initial =
          '# CodeLab user config\n'
          'secrets:\n'
          '  backend: file # keys live in secrets.yaml\n'
          '\n'
          '# models are added below\n';
      writeConfig(initial);
      final golden = File(
        '$appDirectory/test/e2e/golden/provider_add_config.yaml',
      ).readAsStringSync().replaceAll('<port>', '${server.port}');

      final p = await pty(['provider', 'add']);
      await walkWizard(p, server.baseUrl);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, contains('Saved provider "local-${server.port}"'));
      expect(
        p.text,
        contains(
          'Saved provider "local-${server.port}". Models are available in '
          '/model.',
        ),
      );
      expect(config(), golden);
      expect(server.requests.first.path, '/v1/models');
    }, skip: skip);

    test('cli/provider-wizard-entry-cli: provider_wizard.started с '
        'entry=cli', () async {
      writeConfig(_emptyConfig);

      final p = await pty(['provider', 'add', '--verbose']);
      await p.waitFor('? API type');
      p.write(_ctrlC);

      expect(await p.exitCode, 130, reason: 'провайдер удалён');
      expect(p.text, contains('provider_wizard.started mode=add entry=cli'));
      expect(config(), _emptyConfig);
    }, skip: skip);

    test('cli/provider-wizard-key-no-leak: «Ключ мастера не утекает» — '
        'маска, файл, история, лог', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty(['provider', 'add', '--verbose']);
      await walkWizard(p, server.baseUrl, key: leakMarker);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, contains('*' * leakMarker.length));
      expectNoLeak(p);
      expect(
        config(),
        contains('api_key_secret: codelab/local-${server.port}'),
      );
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
      expect(
        server.requests.first.authorization,
        'Bearer $leakMarker',
        reason: 'ключ ушёл только в проверку /models',
      );
    }, skip: skip);

    test('cli/provider-wizard-check-unauthorized: отказ ключа 401, '
        'Ctrl+C → 130, файлы не изменены', () async {
      final server = await FakeModelsServer.start()
        ..status = 401;
      writeConfig(_emptyConfig);

      final p = await pty(['provider', 'add']);
      await p.waitFor('? API type');
      pick(p, 4);
      await p.waitFor('? Base URL ›');
      p.write('${server.baseUrl}\r');
      await p.waitFor('? API key source');
      p.write('\r');
      await p.waitFor('? API key ›');
      p.write('$leakMarker\r');
      await p.waitFor('Checking ${server.origin}/v1/models');
      await waitForAny(p, ['401', 'unauthorized', 'rejected']);
      p.write(_ctrlC);

      expect(await p.exitCode, 130, reason: 'провайдер удалён');
      expect(config(), _emptyConfig);
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
      expectNoLeak(p);
    }, skip: skip);

    test(
      '«Неполный набор флагов ядра на TTY»: вопросов нет, вывод ядра',
      () async {
        writeConfig(_emptyConfig);

        final p = await pty([
          'provider',
          'add',
          'gw',
          '--kind',
          'openai-compatible',
        ]);

        expect(await p.exitCode, 64, reason: 'провайдер удалён');
        expect(
          p.text,
          contains('missing required options: --model, --context-window'),
        );
        expect(p.text, isNot(contains('? ')));
        final piped = await CliProcess.run(
          [
            '-C',
            project,
            'provider',
            'add',
            'gw',
            '--kind',
            'openai-compatible',
          ],
          environment: baseEnv(),
          entry: CliEntry.production,
        );
        expect(piped.stdout, isEmpty);
        expect(p.text.trim(), piped.stderr.trim());
        expect(config(), _emptyConfig);
      },
      skip: skip,
    );

    test('флаги без --yes на терминале: «? Save? [Y/n]», n → 130 без '
        'записи', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty([
        'provider',
        'add',
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
      ]);
      await p.waitFor('? Save? [Y/n]');
      p.write('n\r');

      expect(await p.exitCode, 130, reason: 'провайдер удалён');
      expect(config(), _emptyConfig);
    }, skip: skip);

    test('--api-key-stdin без --yes на терминале: скрытое поле, сводка, '
        'Enter → 0', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty([
        'provider',
        'add',
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--api-key-stdin',
      ]);
      await p.waitFor('? API key ›');
      p.write('$leakMarker\r');
      await p.waitFor('? Save? [Y/n]');
      p.write('\r');

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, contains('*' * leakMarker.length));
      expectNoLeak(p);
      expect(config(), contains('api_key_secret: codelab/gw'));
      expect(server.requests.first.authorization, 'Bearer $leakMarker');
    }, skip: skip);

    test('флаги без --yes на терминале: Enter записывает', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty([
        'provider',
        'add',
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
      ]);
      await p.waitFor('? Save? [Y/n]');
      p.write('\r');

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(
        p.text,
        contains('Saved provider "gw". Models are available in /model.'),
      );
      expect(config(), contains('gw:'));
    }, skip: skip);
  });

  group('codelab provider add без терминала', () {
    Future<CliResult> run(List<String> args, {String? stdin}) => CliProcess.run(
      ['-C', project, 'provider', 'add', ...args],
      environment: baseEnv(),
      stdin: stdin,
      entry: CliEntry.production,
    );

    test('cli/provider-add-noninteractive: «provider add без флагов без '
        'TTY» — 64 и недостающие флаги', () async {
      writeConfig(_emptyConfig);

      final result = await run(['gw']);

      expect(result.exitCode, 64, reason: '$result');
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'provider add: missing required options: '
        '--kind, --model, --context-window\n',
      );
      expect(config(), _emptyConfig);
    });

    test('cli/provider-add-noninteractive: --api-key-stdin, ключ в '
        'проверку и в хранилище, не в вывод', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final result = await run([
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--api-key-stdin',
        '--yes',
      ], stdin: '$leakMarker\n');

      expect(result.exitCode, 0, reason: '$result');
      expect(
        result.stdout,
        'Saved provider "gw". Models are available in /model.\n',
      );
      expect('${result.stdout}${result.stderr}', isNot(contains(leakMarker)));
      expect(server.requests.single.authorization, 'Bearer $leakMarker');
      expect(config(), contains('api_key_secret: codelab/gw'));
      expect(config(), isNot(contains(leakMarker)));
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
    });

    test('cli/provider-add-noninteractive: секрет codelab/gw уже есть — код '
        '1, конфиг не изменён (SETUP-5)', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);
      final args = [
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--api-key-stdin',
        '--yes',
      ];
      final first = await run(args, stdin: '$leakMarker\n');
      expect(first.exitCode, 0, reason: '$first');
      writeConfig(_emptyConfig);

      final second = await run(args, stdin: '$leakMarker\n');

      expect(second.exitCode, 1, reason: '$second');
      expect(second.stderr, startsWith('codelab: provider add failed: '));
      expect('${second.stdout}${second.stderr}', isNot(contains(leakMarker)));
      expect(config(), _emptyConfig);
    });

    test('cli/provider-add-noninteractive: --api-key-stdin при бэкенде '
        'только для чтения — код 1 «provider add failed»', () async {
      final server = await FakeModelsServer.start();
      const readOnly = 'secrets:\n  backend: env\n';
      writeConfig(readOnly);

      final result = await run([
        'gw',
        '--preset',
        'custom-openai',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--api-key-stdin',
        '--yes',
      ], stdin: '$leakMarker\n');

      expect(result.exitCode, 1, reason: '$result');
      expect(result.stdout, isEmpty);
      expect(result.stderr, startsWith('codelab: provider add failed: '));
      expect('${result.stdout}${result.stderr}', isNot(contains(leakMarker)));
      expect(config(), readOnly);
    });
  });

  group('первый запуск (U-17)', () {
    test('cli/onboarding-first-run: мастер, затем ход REPL на том же '
        'stdin', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty(
        ['--verbose'],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor(
        'No model provider is configured for the embedded agent.',
      );
      await p.waitFor(
        'Let\'s set one up. Press Ctrl+C to quit; run "codelab provider add" '
        'later to change it.',
      );
      await walkWizard(p, server.baseUrl, key: leakMarker);
      await p.waitFor(
        'Saved provider "local-${server.port}". Starting the embedded '
        'agent…',
      );

      // REPL читает клавиши из того же stdin: ход проходит.
      final from = p.text.length;
      await p.waitFor('> ', from: from);
      p.write('hello\r');
      await p.waitFor(_answer, from: from);
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(
        p.text,
        contains('provider_wizard.started mode=add entry=first_run'),
      );
      final written = config();
      expect(written, contains('api_key_secret: codelab/local-${server.port}'));
      expect(written, contains('default_model: local-${server.port}/m1'));
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
      expectNoLeak(p);
    }, skip: skip);

    test('cli/onboarding-first-run-tui: построчный мастер до экрана TUI, '
        'затем экран читает клавиши и проводит ход', () async {
      final server = await FakeModelsServer.start();
      writeConfig(_emptyConfig);

      final p = await pty(
        ['--ui', 'tui'],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor("Let's set one up.");
      expect(
        p.text,
        isNot(contains('\x1b[?1049h')),
        reason: 'экран TUI ещё не открыт',
      );
      await walkWizard(p, server.baseUrl);
      await p.waitFor('Saved provider "local-${server.port}". Starting the');
      final from = p.text.length;
      await p.waitFor('\x1b[?1049h', from: from);

      p.write('hello\r');
      await p.waitFor(_answer, from: from);
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, contains('\x1b[?1049l'), reason: 'терминал восстановлен');
    }, skip: skip);

    test('cli/onboarding-first-run-explicit-model: явная модель без '
        'провайдеров — мастер делает нового провайдера default '
        '(forceDefault, D7/D16)', () async {
      final server = await FakeModelsServer.start();
      writeConfig(
        '$_emptyConfig'
        'agent:\n  default_model: ghost/old\n',
      );

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await walkWizard(p, server.baseUrl);
      await p.waitFor('Starting the embedded agent…');
      final from = p.text.length;
      await p.waitFor('> ', from: from);
      p.write('hello\r');
      await p.waitFor(_answer, from: from);
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      final written = config();
      expect(written, contains('default_model: local-${server.port}/m1'));
      expect(written, isNot(contains('ghost/old')));
    }, skip: skip);

    test('cli/onboarding-first-run: Ctrl+C в мастере → 130, файлы не '
        'изменены', () async {
      writeConfig(_emptyConfig);

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor('? API type');
      p.write(_ctrlC);

      expect(await p.exitCode, 130, reason: 'провайдер удалён');
      expect(config(), _emptyConfig);
    }, skip: skip);

    test('cli/onboarding-no-key: «Ключ провайдера отсутствует» — вопрос, '
        'запись только секрета, конфиг побайтово прежний', () async {
      const gw = '''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    api_key_secret: codelab/gw
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
''';
      writeConfig(gw);

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor('Store a key for "gw" in file? [Y/n]');
      p.write('\r');
      await p.waitFor('? API key ›');
      p.write('$leakMarker\r');
      await p.waitFor(
        'Saved the key as "codelab/gw" in file. Starting the embedded '
        'agent…',
      );
      final from = p.text.length;
      await p.waitFor('> ', from: from);
      p.write('hello\r');
      await p.waitFor(_answer, from: from);
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(config(), gw);
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
      expect(p.text, isNot(contains('? API type')), reason: 'мастера нет');
      expectNoLeak(p);
    }, skip: skip);

    test('cli/onboarding-no-key: «n» — подсказка, обычный старт', () async {
      const gw = '''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    api_key_secret: codelab/gw
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
''';
      writeConfig(gw);

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor('Store a key for "gw" in file? [Y/n]');
      p.write('n\r');
      await p.waitFor(
        'Starting without a key for "gw". Store it later with: codelab '
        'secret set codelab/gw',
      );
      await p.waitFor('> ');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(config(), gw);
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    }, skip: skip);

    test('cli/onboarding-no-key: «Ключ из незаданной переменной» — строка, '
        'вопроса нет, конфиг прежний', () async {
      const gw = '''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    api_key_env: GW_KEY
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
''';
      writeConfig(gw);

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor(
        'The key for "gw" is read from GW_KEY, which is not set. Set it and '
        'restart codelab.',
      );
      await p.waitFor('> ');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, isNot(contains('Store a key')));
      expect(config(), gw);
    }, skip: skip);

    test('cli/onboarding-headless-no-key: -p без конфига даже на '
        'терминале — прежний код 64, мастера нет', () async {
      final p = await pty(['-p', 'hi']);

      expect(await p.exitCode, 64, reason: 'провайдер удалён');
      expect(p.text, contains('codelab config check'));
      expect(p.text, isNot(contains("Let's set one up")));
      expect(p.text, isNot(contains('? API type')));
    }, skip: skip);

    test('cli/onboarding-broken-config: мастер не запускается, 64, файл не '
        'тронут', () async {
      const broken = 'secrets:\n  backend: file\nbudget:\n  max_steps: 0\n';
      writeConfig(broken);

      final p = await pty(const []);

      expect(await p.exitCode, 64, reason: 'провайдер удалён');
      expect(p.text, contains('budget.max_steps'));
      expect(p.text, isNot(contains("Let's set one up")));
      expect(p.text, isNot(contains('? API type')));
      expect(config(), broken);
    }, skip: skip);

    test('внешний агент: мастер не запускается, REPL подключается', () async {
      final agent = await scriptedAgent(dir);

      final p = await pty(['--agent', agent]);
      await p.waitFor('> ');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(p.text, isNot(contains("Let's set one up")));
      expect(File('$home/config.yaml').existsSync(), isFalse);
    }, skip: skip);
  });

  group('/provider и /settings в REPL', () {
    test('cli/settings-change: «Изменение настройки» и «Секретный ключ не '
        'редактируется»', () async {
      writeConfig(_readyConfig);

      final p = await pty(
        const [],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(),
      );
      await p.waitFor('> ');
      p.write('/settings agent.effort high\r');
      await p.waitFor('Updated agent.effort in $home/config.yaml');
      final written = config();
      expect(written, contains('effort: high'));
      expect(written, contains('# my settings'), reason: 'комментарии целы');

      final from = p.text.length;
      p.write('/settings\r');
      await p.waitFor('agent.effort', from: from);
      expect(
        p.text.substring(from),
        contains(RegExp(r'agent\.effort\s+high\s+user')),
      );

      p.write('/settings providers.openai.api_key_secret x\r');
      await p.waitFor('Use codelab secret set <name>');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(config(), written, reason: 'секретный ключ конфиг не менял');
    }, skip: skip);

    test('cli/provider-add-during-turn: «/provider add во время хода» — '
        'строка отказа, ход продолжается', () async {
      writeConfig(_readyConfig);

      final p = await pty(
        ['slow'],
        entry: CliEntry.scriptedEmbedded,
        environment: scriptEnv(
          '$appDirectory/test/e2e/llm_scripts/hangs_until_cancel.json',
        ),
      );
      await p.waitFor('> slow');
      p.write('/provider add\r');
      await p.waitFor(
        'Finish or cancel the current turn first (Ctrl+C), then run '
        '/provider add.',
      );
      expect(p.text, isNot(contains('? API type')));

      p.write(_ctrlC);
      await p.waitFor('> ');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: 'провайдер удалён');
      expect(config(), _readyConfig);
    }, skip: skip);

    test('cli/provider-wizard-repl: /provider add записывает провайдера, '
        'агент присылает config_option_update и /model показывает новую '
        'модель', () async {
      final server = await FakeModelsServer.start();
      writeConfig('''
providers:
  gw:
    kind: openai-compatible
    base_url: ${server.baseUrl}
    models:
      m1:
        context_window: 8000
agent:
  default_model: gw/m1
secrets:
  backend: file
''');

      final p = await pty(const []);
      await p.waitFor('> ');
      p.write('/provider add\r');
      await walkWizard(p, server.baseUrl);
      await p.waitFor(
        'Saved provider "local-${server.port}". Models are available in '
        '/model.',
      );

      // Агент перечитывает конфиг сам: ждём, пока `/model` покажет модель.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var shown = false;
      while (!shown && DateTime.now().isBefore(deadline)) {
        final from = p.text.length;
        p.write('/model\r');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        shown = p.text.substring(from).contains('local-${server.port}/m1');
      }
      expect(shown, isTrue, reason: 'провайдер удалён');
      p.write(_ctrlD);
      expect(await p.exitCode, 0, reason: 'провайдер удалён');
    }, skip: skip);

    test(
      'cli/settings-profile-home: запись идёт в CODELAB_HOME профиля '
      'codelab-agent, а не клиента (D5, SETUP-2)',
      () async {
        // A — дом клиента, B — дом агента из `env` профиля.
        const aText = '# client home\nsecrets:\n  backend: file\n';
        writeConfig(aText);
        final b = Directory('${dir.path}/agent-home')..createSync();
        Process.runSync('/bin/chmod', ['700', b.path]);
        File('${b.path}/config.yaml').writeAsStringSync(
          _readyConfig.replaceFirst(
            'agent:',
            '  spare:\n'
                '    kind: openai-compatible\n'
                '    base_url: http://127.0.0.1:9/v1\n'
                '    models:\n'
                '      m:\n'
                '        context_window: 8000\n'
                'agent:',
          ),
        );
        // Профиль должен называться командой `codelab-agent` (D5): обёртка
        // запускает собранный Dart-агент.
        final wrapper = File('${dir.path}/codelab-agent')
          ..writeAsStringSync(
            '#!/bin/sh\nexec "${dartExecutable()}" '
            '"${await E2eCliAgent.agentKernel()}" "\$@"\n',
          );
        Process.runSync('/bin/chmod', ['755', wrapper.path]);
        final script = File('${dir.path}/agent-script.json')
          ..writeAsStringSync(
            jsonEncode({
              'llm': {
                'model': {
                  'provider': 'scripted',
                  'modelId': 'scripted-1',
                  'contextWindow': 32768,
                },
                'steps': [
                  {
                    'reply': [
                      {'text': 'hi'},
                    ],
                    'stopReason': 'stop',
                  },
                ],
              },
            }),
          );
        File('$home/profiles.json').writeAsStringSync(
          jsonEncode({
            'version': 1,
            'profiles': [
              {
                'type': 'stdio',
                'id': 'agent-b',
                'label': 'Agent B',
                'command': wrapper.path,
                'args': ['serve', '--stdio', '--llm-script', script.path],
                'env': {'CODELAB_HOME': b.path},
                'runInProjectDirectory': false,
              },
            ],
          }),
        );

        final p = await pty(['--agent', 'agent-b']);
        await p.waitFor('> ');
        p.write('/settings agent.effort high\r');
        await p.waitFor('Updated agent.effort in ${b.path}/config.yaml');
        final from = p.text.length;
        p.write('/provider remove spare\r');
        await p.waitFor('providers.spare', from: from);
        p.write(_ctrlD);

        expect(await p.exitCode, 0, reason: 'провайдер удалён');
        expect(config(), aText, reason: 'дом клиента не тронут');
        final changed = File('${b.path}/config.yaml').readAsStringSync();
        expect(changed, contains('effort: high'));
        expect(changed, isNot(contains('spare:')), reason: 'провайдер удалён');
        expect(changed, contains('gw:'));
      },
      skip: skip,
      tags: scriptedOnly,
    );

    /// REPL с профилем `codelab-agent` из `profiles.json`, чей `env` — [env];
    /// `HOME` процесса CLI — [fakeHome].
    Future<PtyProcess> profileRepl(
      Map<String, String> env, {
      required String fakeHome,
    }) async {
      final wrapper = File('${dir.path}/codelab-agent')
        ..writeAsStringSync(
          '#!/bin/sh\nexec "${dartExecutable()}" '
          '"${await E2eCliAgent.agentKernel()}" "\$@"\n',
        );
      Process.runSync('/bin/chmod', ['755', wrapper.path]);
      final script = File('${dir.path}/agent-script.json')
        ..writeAsStringSync(
          jsonEncode({
            'llm': {
              'model': {
                'provider': 'scripted',
                'modelId': 'scripted-1',
                'contextWindow': 32768,
              },
              'steps': [
                {
                  'reply': [
                    {'text': 'hi'},
                  ],
                  'stopReason': 'stop',
                },
              ],
            },
          }),
        );
      File('$home/profiles.json').writeAsStringSync(
        jsonEncode({
          'version': 1,
          'profiles': [
            {
              'type': 'stdio',
              'id': 'agent-b',
              'label': 'Agent B',
              'command': wrapper.path,
              'args': ['serve', '--stdio', '--llm-script', script.path],
              'env': env,
              'runInProjectDirectory': false,
            },
          ],
        }),
      );
      final p = await pty(
        ['--agent', 'agent-b'],
        environment: {'HOME': fakeHome},
        workingDirectory: dir.path,
      );
      await p.waitFor('> ');
      return p;
    }

    test(
      'cli/provider-profile-home-tilde: CODELAB_HOME профиля с «~» — один '
      'дом для конфига и хранилища секретов (D5)',
      () async {
        final server = await FakeModelsServer.start();
        writeConfig('secrets:\n  backend: file\n');
        final fakeHome = Directory('${dir.path}/fh')..createSync();
        final agentHome = Directory('${fakeHome.path}/agent-home')
          ..createSync();
        Process.runSync('/bin/chmod', ['700', agentHome.path]);
        File('${agentHome.path}/config.yaml').writeAsStringSync(_emptyConfig);

        final p = await profileRepl({
          'CODELAB_HOME': '~/agent-home',
        }, fakeHome: fakeHome.path);
        p.write('/provider add\r');
        await walkWizard(p, server.baseUrl, key: leakMarker);
        await p.waitFor('Saved provider "local-${server.port}"');
        p.write(_ctrlD);

        expect(await p.exitCode, 0, reason: p.text);
        // Конфиг и секрет — в одном доме агента, а не в `./~/agent-home`.
        expect(
          File('${agentHome.path}/config.yaml').readAsStringSync(),
          contains('api_key_secret: codelab/local-${server.port}'),
        );
        expect(File('${agentHome.path}/secrets.yaml').existsSync(), isTrue);
        expect(Directory('${dir.path}/~').existsSync(), isFalse);
        expect(config(), 'secrets:\n  backend: file\n');
        expect(p.text, isNot(contains(leakMarker)));
      },
      skip: skip,
      tags: scriptedOnly,
    );

    test(
      'cli/provider-profile-env: весь env профиля виден мастеру '
      '(api_key_env из env профиля)',
      () async {
        final server = await FakeModelsServer.start();
        writeConfig(_emptyConfig);
        final agentHome = Directory('${dir.path}/agent-home')..createSync();
        Process.runSync('/bin/chmod', ['700', agentHome.path]);
        File('${agentHome.path}/config.yaml').writeAsStringSync(_emptyConfig);

        final p = await profileRepl({
          'CODELAB_HOME': agentHome.path,
          'GW_KEY': 'env-key-value',
        }, fakeHome: '${dir.path}/fh');
        p.write('/provider add\r');
        await p.waitFor('? API type');
        pick(p, 4);
        await p.waitFor('? Base URL ›');
        p.write('${server.baseUrl}\r');
        await p.waitFor('? API key source');
        pick(p, 1); // Read from an environment variable
        await p.waitFor('? Environment variable ›');
        p.write('GW_KEY\r');
        await p.waitFor('? Model (type to filter) ›');
        p.write('\r');
        await p.waitFor('? Save? [Y/n]');
        p.write('\r');
        await p.waitFor('Saved provider');
        p.write(_ctrlD);

        expect(await p.exitCode, 0, reason: p.text);
        expect(server.requests.first.authorization, 'Bearer env-key-value');
        expect(
          File('${agentHome.path}/config.yaml').readAsStringSync(),
          contains('api_key_env: GW_KEY'),
        );
      },
      skip: skip,
      tags: scriptedOnly,
    );

    test(
      'cli/settings-remote-read-only: удалённый агент — только чтение, '
      'локальный конфиг не изменён (§12.4.13)',
      () async {
        const marker = '# marker config\nsecrets:\n  backend: file\n';
        writeConfig(marker);
        final port = await _startWebSocketAgent(dir);

        final p = await pty(
          ['--agent', 'ws://127.0.0.1:$port/acp'],
          environment: {'CODELAB_AGENT_TOKEN': _token},
        );
        await p.waitFor('> ');
        const readOnly =
            'Provider settings are read-only for a remote agent. Run "codelab '
            'provider add" on the agent host.';
        p.write('/provider add\r');
        await p.waitFor(readOnly);
        final from = p.text.length;
        p.write('/settings agent.effort high\r');
        await p.waitFor(readOnly, from: from);
        p.write(_ctrlD);

        expect(await p.exitCode, 0, reason: 'провайдер удалён');
        expect(p.text, isNot(contains('? API type')));
        expect(config(), marker);
      },
      skip: skip,
      tags: scriptedOnly,
    );
  });
}

const _token = 'e2e-secret-token';

/// Поднимает `codelab-agent serve --ws`, требующий [_token], и возвращает
/// порт (как `connect_profiles_test.dart`: сервер — всегда Dart-агент).
Future<String> _startWebSocketAgent(Directory dir) async {
  final kernel = await E2eCliAgent.agentKernel();
  final script = File('${dir.path}/ws-hello.json')
    ..writeAsStringSync(
      jsonEncode({
        'llm': {
          'model': {
            'provider': 'scripted',
            'modelId': 'scripted-1',
            'contextWindow': 32768,
          },
          'steps': [
            {
              'reply': [
                {'text': 'hello over websocket'},
              ],
              'stopReason': 'stop',
            },
          ],
        },
      }),
    );
  final server = await Process.start(
    dartExecutable(),
    [kernel, 'serve', '--ws', '--port', '0', '--llm-script', script.path],
    environment: {
      'CODELAB_HOME': '${dir.path}/agent-home',
      'CODELAB_AGENT_TOKEN': _token,
    },
  );
  addTearDown(() => server.kill(ProcessSignal.sigkill));
  final stderr = StringBuffer();
  server.stdout.drain<void>().ignore();
  final listening = RegExp(r'serve\.ws\.listening .*port: (\d+)');
  server.stderr.transform(utf8.decoder).listen(stderr.write);
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (listening.firstMatch('$stderr') == null) {
    if (DateTime.now().isAfter(deadline)) {
      fail('codelab-agent did not listen:\n$stderr');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return listening.firstMatch('$stderr')!.group(1)!;
}
