// Мастер первого запуска CLI (задача 4.2 change `add-provider-setup-ui`; spec
// codelab-cli «Мастер первого запуска CLI»; design.md D16, решение Q12;
// §12.4.3).
//
// Ожидаемый API реализации (задача 4.6), см. отчёт:
//   lib/src/setup/first_run.dart —
//     enum FirstRunResult { proceed, cancelled }
//     Future<FirstRunResult> runFirstRun({
//       required Future<AgentConfigSnapshot> Function() loadSnapshot,
//       required Future<ProviderKeys> Function() openKeys,
//       required Map<String, String> environment,
//       required Terminal terminal,
//       required ProviderSetupFlow Function() newWizard,
//     });
//
// `proceed` — обычный старт (после любой строки ветки), `cancelled` — выход
// `130`. Фабрика `newWizard` вызывается только в ветке `NoProviderConfigured`;
// run.dart строит её с `entry: firstRun`, `forceDefault: true`, цель `user`.
// Сбой `loadSnapshot` или `openKeys` — `proceed` без вывода (D16, «Сверка с
// кодом»). Все строки — в `Terminal.output`.
//
// Снимки строит настоящий `FileAgentConfigStore` на временном
// `CODELAB_HOME`: готовность `ProviderReady`/`ConfigBroken`/… определяет
// мост (`checkProviderReadiness`), а не тест. Порты ключей, проверки и
// записи мастера — фейки. Один владелец stdin на мастер и следующий за ним
// REPL проверяют PTY-e2e `test/e2e/provider_setup_test.dart`: single-
// subscription `FakeTerminal.input` этого не показывает.

import 'dart:convert';
import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart' show runCodelab;
import 'package:codelab_cli/src/setup/first_run.dart';
import 'package:codelab_cli/src/setup/prompt_line.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart'
    show ClientSecretAccess, FileAgentConfigStore;
import 'package:test/test.dart';

import '../support/cli_process.dart' show appDirectory;
import '../support/fake_cli_io.dart';
import '../support/fake_terminal.dart';
import '../support/setup_fakes.dart';

const _setupText =
    'No model provider is configured for the embedded agent.\n'
    'Let\'s set one up. Press Ctrl+C to quit; run "codelab provider add" '
    'later to change it.';

void main() {
  late Directory root;
  late String home;
  late String project;
  late FakeTerminal terminal;
  late FakeProviderCheck check;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late RecordingLogger logger;
  var created = 0;

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_first_run_')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    terminal = FakeTerminal();
    check = FakeProviderCheck();
    keys = FakeProviderKeys();
    config = FakeConfigStore(snapshotValue: snapshotOf(cwd: project));
    logger = RecordingLogger();
    created = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  void writeConfig(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  String configText() => File('$home/config.yaml').readAsStringSync();

  Future<AgentConfigSnapshot> load() async {
    final environment = {'HOME': root.path, 'CODELAB_HOME': home};
    final store = FileAgentConfigStore(
      paths: ConfigPaths(codelabHome: home, projectDir: project),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: logger,
      ),
      logger: logger,
    );
    return store.snapshot(cwd: project);
  }

  Future<FirstRunResult> start({
    Map<String, String> environment = const {},
    Future<AgentConfigSnapshot> Function()? loadSnapshot,
    Future<ProviderKeys> Function()? openKeys,
  }) => runFirstRun(
    loadSnapshot: loadSnapshot ?? load,
    openKeys: openKeys ?? () async => keys,
    environment: environment,
    terminal: terminal,
    newWizard: () {
      created++;
      return buildWizardFlow(
        check: check,
        keys: keys,
        config: config,
        logger: logger,
        entry: ProviderWizardEntry.firstRun,
        forceDefault: true,
        cwd: project,
      );
    },
  );

  Future<void> see(String text) => eventually(
    () => terminal.text.contains(text),
    reason: 'no "$text" in:\n${terminal.text}',
  );

  void pick(int index) {
    for (var i = 0; i < index; i++) {
      terminal.press(keyDown);
    }
    terminal.press(keyEnter);
  }

  /// Ветка печатает [line] и даёт обычный старт: ни вопроса, ни мастера.
  void expectLineThenStart(FirstRunResult result, String line) {
    expect(result, FirstRunResult.proceed);
    expect(terminal.text, contains(line));
    expect(terminal.text, isNot(contains('? ')));
    expect(created, 0, reason: 'ProviderSetupFlow не создаётся');
    expect(config.applied, isEmpty);
    expect(keys.written, isEmpty);
  }

  /// Ни вопроса, ни записи, ни мастера: ветка молча даёт обычный старт.
  void expectSilentStart(FirstRunResult result) {
    expect(result, FirstRunResult.proceed);
    expect(terminal.text, isEmpty);
    expect(terminal.errorText, isEmpty);
    expect(created, 0, reason: 'ProviderSetupFlow не создаётся');
    expect(config.applied, isEmpty);
    expect(keys.written, isEmpty);
  }

  group('ProviderReady и ConfigBroken: мастера нет', () {
    test('провайдер с моделью и default_model: обычный старт', () async {
      writeConfig('''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
''');
      final before = configText();

      expectSilentStart(await start());

      expect(configText(), before);
    });

    test('провайдер с моделью без agent.default_model: готов по '
        'CoreConfig.defaultModel (change optional-default-model)', () async {
      writeConfig('''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    models:
      m:
        context_window: 8000
''');

      expectSilentStart(await start());
    });

    test('ConfigBroken: мастер не вызван, файл не тронут', () async {
      writeConfig('secrets:\n  backend: file\nbudget:\n  max_steps: 0\n');
      final before = configText();

      expectSilentStart(await start());

      expect(configText(), before);
    });

    test('сбой снимка: прежний путь старта, без вывода', () async {
      expectSilentStart(
        await start(
          loadSnapshot: () async => throw const FileSystemException(),
        ),
      );
    });

    test('сбой открытия хранилища ключей: прежний путь старта', () async {
      writeConfig('secrets:\n  backend: file\n');

      expectSilentStart(
        await start(openKeys: () async => throw StateError('no store')),
      );
    });
  });

  group('NoProviderConfigured: полный мастер, цель user, makeDefault', () {
    Future<FirstRunResult> driveWizard() async {
      final result = start();
      await see('? API type');
      pick(4); // Custom OpenAI-compatible endpoint
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      pick(2); // No key
      await eventually(() => check.calls.isNotEmpty);
      check.respond(modelsOk(['m1']));
      await see('? Model (type to filter) ›');
      terminal.press(keyEnter);
      await see('? Save? [Y/n]');
      terminal.press(keyEnter);
      return result;
    }

    for (final (name, text) in [
      ('пустой дом', 'secrets:\n  backend: file\n'),
      (
        'явная модель без провайдеров',
        'secrets:\n  backend: file\nagent:\n  default_model: gw/m\n',
      ),
    ]) {
      test('$name: тексты спеки, мастер, Done → обычный старт', () async {
        writeConfig(text);
        final before = configText();

        final result = await driveWizard();

        expect(result, FirstRunResult.proceed);
        expect(terminal.text, contains(_setupText));
        expect(created, 1);
        expect(
          terminal.text,
          contains('Saved provider "gw-example". Starting the embedded agent…'),
        );
        expect(
          logger.fieldsOf('provider_wizard.started'),
          containsPair('entry', 'first_run'),
        );
        final applied = config.applied.single;
        expect(applied.base.target, const ConfigTarget.user());
        expect(
          applied.edits,
          contains(const SetValue('agent.default_model', 'gw-example/m1')),
        );
        // Запись шла через порт мастера: файл настоящего дома не менялся.
        expect(configText(), before);
      });
    }

    test('Ctrl+C в мастере → cancelled, файлы не изменены', () async {
      writeConfig('secrets:\n  backend: file\n');
      final result = start();
      await see('? API type');

      terminal.press(keyCtrlC);

      expect(await result, FirstRunResult.cancelled);
      expect(config.applied, isEmpty);
      expect(keys.written, isEmpty);
      expect(terminal.rawEnabled, isFalse);
    });
  });

  group('ProviderKeyMissing: только ключ, мастера нет (D16, Q12)', () {
    const secretConfig = '''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    api_key_secret: codelab/gw
    models:
      m:
        context_window: 8000
agent:
  default_model: gw/m
''';

    void expectConfigUntouched() {
      expect(created, 0, reason: 'ProviderSetupFlow не создаётся');
      expect(config.applied, isEmpty, reason: 'AgentConfigStore.apply');
      expect(configText(), secretConfig);
    }

    setUp(() => writeConfig(secretConfig));

    test('Enter → поле ключа, пустое значение просит ввести ещё раз, '
        'запись только секрета', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.press(keyEnter);
      await see('? API key ›');

      terminal.press(keyEnter);
      await see('Enter the API key.');
      expect(keys.written, isEmpty);

      terminal.type(leakMarker);
      await see('*' * leakMarker.length);
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(keys.written, {'codelab/gw': leakMarker});
      expect(
        terminal.text,
        contains(
          'Saved the key as "codelab/gw" in file. Starting the embedded '
          'agent…',
        ),
      );
      expect(terminal.text, isNot(contains(leakMarker)));
      expectConfigUntouched();
    });

    test('«y» тоже согласие', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.type('y');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type(leakMarker);
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(keys.written, {'codelab/gw': leakMarker});
    });

    test('вставка нескольких строк в поле ключа отклоняется, поле '
        'спрашивается снова (D14)', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.press(keyEnter);
      await see('? API key ›');

      terminal.press(utf8.encode('${leakMarker}A\r${leakMarker}B\r'));
      await see(keyRejectedLine);
      expect(terminal.text, isNot(contains(leakMarker)));
      terminal.type('good');
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(keys.written, {'codelab/gw': 'good'});
    });

    test('ProviderKeyReplaced даёт ту же строку «Saved the key»', () async {
      keys.onWrite = (name, value) => const ProviderKeyReplaced();
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type(leakMarker);
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(terminal.text, contains('Saved the key as "codelab/gw" in file.'));
    });

    test('ProviderKeyRefused: причина без значения, обычный старт', () async {
      keys.onWrite = (name, value) => const ProviderKeyRefused('disk is full');
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type(leakMarker);
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(terminal.text, contains('Could not store the key: disk is full'));
      expect(terminal.text, isNot(contains(leakMarker)));
      expectConfigUntouched();
    });

    test('«n»: подсказка и обычный старт, ничего не записано', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.type('n');
      terminal.press(keyEnter);

      expect(await result, FirstRunResult.proceed);
      expect(
        terminal.text,
        contains(
          'Starting without a key for "gw". Store it later with: codelab '
          'secret set codelab/gw',
        ),
      );
      expect(keys.written, isEmpty);
      expect(terminal.text, isNot(contains('? API key ›')));
      expectConfigUntouched();
    });

    test('Ctrl+C на вопросе → cancelled', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');

      terminal.press(keyCtrlC);

      expect(await result, FirstRunResult.cancelled);
      expect(keys.written, isEmpty);
      expectConfigUntouched();
    });

    test('Ctrl+C в поле ключа → cancelled, ничего не записано', () async {
      final result = start();
      await see('Store a key for "gw" in file? [Y/n]');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type(leakMarker);

      terminal.press(keyCtrlC);

      expect(await result, FirstRunResult.cancelled);
      expect(keys.written, isEmpty);
      expect(terminal.text, isNot(contains(leakMarker)));
      expectConfigUntouched();
    });

    test('бэкенд только для чтения: строка про CODELAB_SECRET_…, вопроса '
        'нет', () async {
      keys = FakeProviderKeys(
        backend: const SecretBackendInfo(
          id: 'env',
          writable: false,
          unavailableReason: 'no OS store',
        ),
      );

      expectLineThenStart(
        await start(),
        'No writable secret store (no OS store). Set '
        '${SecretNames.envOverride('codelab/gw')} or the provider\'s '
        'api_key_env variable.',
      );
      expect(terminal.text, isNot(contains('Store a key')));
      expectConfigUntouched();
    });

    test('api_key_env: переменная не задана → строка, вопроса нет', () async {
      writeConfig(
        secretConfig.replaceFirst(
          'api_key_secret: codelab/gw',
          'api_key_env: GW_KEY',
        ),
      );

      expectLineThenStart(
        await start(),
        'The key for "gw" is read from GW_KEY, which is not set. Set it and '
        'restart codelab.',
      );
      expect(terminal.text, isNot(contains('Store a key')));
      expect(created, 0);
      expect(config.applied, isEmpty);
    });

    test('api_key_env: переменная задана → ProviderReady, тишина', () async {
      writeConfig(
        secretConfig.replaceFirst(
          'api_key_secret: codelab/gw',
          'api_key_env: GW_KEY',
        ),
      );

      expectSilentStart(await start(environment: {'GW_KEY': 'value'}));
    });
  });

  group('без терминала, -p и внешний агент: готовность не вычисляется', () {
    test('codelab -p hi с пустым домом: код 64 и прежний текст, вопросов '
        'нет', () async {
      final io = FakeCliIo();

      final code = await runCodelab(
        ['-C', project, '-p', 'hi'],
        environment: {'CODELAB_HOME': home, 'HOME': '${root.path}/no-home'},
        io: io,
      );

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(io.stderrText, contains('codelab config check'));
      expect(io.stderrText, isNot(contains("Let's set one up")));
      expect(io.stderrText, isNot(contains('? API type')));
    });

    test(
      'REPL без терминала (stdin из pipe → headless): мастера нет',
      () async {
        final io = FakeCliIo(stdin: 'hi\n');

        final code = await runCodelab(
          ['-C', project],
          environment: {'CODELAB_HOME': home, 'HOME': '${root.path}/no-home'},
          io: io,
        );

        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(io.stderrText, isNot(contains("Let's set one up")));
      },
    );

    test('lib/src/run.dart вызывает первый запуск (_firstRun → runFirstRun) '
        'из _runRepl и _runTui до buildCliRuntime и не вызывает его из '
        '_runHeadless', () {
      final source = File('$appDirectory/lib/src/run.dart').readAsStringSync();
      // Тело функции — до следующей функции режима.
      const next = {
        '_runRepl': 'Future<int> _runTui(',
        '_runTui': 'Future<int> _runHeadless(',
        '_runHeadless': '/// Абсолютный путь рабочей папки',
      };
      String body(String name) {
        final start = source.indexOf('Future<int> $name(');
        expect(start, isNonNegative, reason: name);
        return source.substring(start, source.indexOf(next[name]!, start));
      }

      for (final name in ['_runRepl', '_runTui']) {
        final text = body(name);
        final first = text.indexOf('_firstRun(');
        final build = text.indexOf('buildCliRuntime');
        expect(first, isNonNegative, reason: '$name вызывает _firstRun');
        expect(first, lessThan(build), reason: '$name: до buildCliRuntime');
      }
      expect(body('_runHeadless'), isNot(contains('_firstRun(')));
      expect(source, contains('await runFirstRun('));
    });
  });
}
