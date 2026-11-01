import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_input.dart';
import '../support/fake_secret_process_runner.dart';

/// Подкоманды `secret set|delete|list` (agent-secrets «Подкоманды secret»,
/// все сценарии; design.md change `add-agent-secret-store`, D8). Общая
/// реализация `SecretCommands` для `codelab-agent` и `codelab`: тексты и коды
/// выхода. Тест не читает настоящий `~/.codelab`: `CODELAB_HOME` и окружение
/// передаются явно, ввод — фейк.
void main() {
  late Directory root;
  late String home;

  const value = 'sk-test-0123456789abcdef';
  const name = 'codelab/openai';

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('secret_commands_test')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, String> env([Map<String, String> extra = const {}]) => {
    'CODELAB_HOME': home,
    ...extra,
  };

  /// Команды над фейковым хранилищем; [opened] считает открытия хранилища.
  SecretCommands over(DescribedSecretStore store, {List<String?>? opened}) =>
      SecretCommands(
        openStore: ({required choice, required environment, required home}) {
          opened?.add(choice);
          return store;
        },
      );

  /// Команды над настоящими бэкендами `env`/`file` (платформа задаётся).
  SecretCommands real({String platform = 'linux'}) =>
      SecretCommands(runner: FakeSecretProcessRunner(), platform: platform);

  SecretSetOptions setOf(
    String secretName, {
    Map<String, String>? environment,
    bool valueArgument = false,
  }) => SecretSetOptions(
    name: secretName,
    environment: environment ?? env(),
    hasValueArgument: valueArgument,
  );

  /// Ни значение, ни его длина не печатаются ни одной подкомандой.
  void expectNoValue(SecretCommandResult result) {
    final text = [...result.stdout, ...result.stderr].join('\n');
    expect(text, isNot(contains(value)));
    expect(text, isNot(contains('sk-test')));
    expect(text, isNot(matches(RegExp(r'\b24\b'))));
  }

  group('set: значение из ввода', () {
    test('без TTY: весь поток без одного завершающего \\n', () async {
      final store = MemorySecretStore();
      final input = FakeSecretInput('$value\n');

      final result = await over(store).set(setOf(name), input);

      expect(result.exitCode, 0);
      expect(result.stdout, ['Stored secret $name in memory']);
      expect(result.stderr, isEmpty);
      expect(await store.read(name), value);
      expect(input.events, ['readAll']);
      expectNoValue(result);
    });

    test('\\r\\n отбрасывается так же, как \\n', () async {
      final store = MemorySecretStore();

      final result = await over(
        store,
      ).set(setOf(name), FakeSecretInput('$value\r\n'));

      expect(result.exitCode, 0);
      expect(await store.read(name), value);
    });

    test('значение без завершающего перевода строки', () async {
      final store = MemorySecretStore();

      final result = await over(store).set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 0);
      expect(await store.read(name), value);
    });

    test('отбрасывается один перевод строки: второй остаётся и отвергает '
        'значение', () async {
      final store = MemorySecretStore();

      final result = await over(
        store,
      ).set(setOf(name), FakeSecretInput('$value\n\n'));

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('single line'));
      expect(await store.names(), isEmpty);
      expectNoValue(result);
    });

    test('с TTY: приглашение в readHidden, readAll не вызывается', () async {
      final store = MemorySecretStore();
      final input = FakeSecretInput(value, hasTerminal: true);

      final result = await over(store).set(setOf(name), input);

      expect(result.exitCode, 0);
      expect(input.events, ['readHidden:Secret value for $name: ']);
      expect(await store.read(name), value);
      expectNoValue(result);
    });

    test('с TTY: EOF (Ctrl+D) — пустое значение, код 64', () async {
      final store = MemorySecretStore();

      final result = await over(
        store,
      ).set(setOf(name), FakeSecretInput(null, hasTerminal: true));

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('empty secret value'));
      expect(await store.names(), isEmpty);
    });

    for (final empty in ['', '\n', '\r\n']) {
      test('пустое значение ${empty.codeUnits}: код 64', () async {
        final store = MemorySecretStore();

        final result = await over(
          store,
        ).set(setOf(name), FakeSecretInput(empty));

        expect(result.exitCode, 64);
        expect(result.stderr, contains('empty secret value'));
        expect(result.stdout, isEmpty);
        expect(await store.names(), isEmpty);
      });
    }

    test('перевод строки внутри: код 64, значение не печатается', () async {
      final store = MemorySecretStore();

      final result = await over(
        store,
      ).set(setOf(name), FakeSecretInput('$value\nsecond-line'));

      expect(result.exitCode, 64);
      expect(result.stderr, contains('secret value must be a single line'));
      expect(await store.names(), isEmpty);
      expectNoValue(result);
      expect(
        [...result.stdout, ...result.stderr].join(),
        isNot(contains('second')),
      );
    });

    test('длиннее 64 КиБ: код 64 с причиной SecretAdmin', () async {
      final result = await over(
        MemorySecretStore(),
      ).set(setOf(name), FakeSecretInput('x' * (64 * 1024 + 1)));

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('longer than 64 KiB'));
    });

    test('перезапись: Updated secret, без вопроса и флага', () async {
      final store = MemorySecretStore({name: 'old-value'});

      final result = await over(
        store,
      ).set(setOf(name), FakeSecretInput('$value\n'));

      expect(result.exitCode, 0);
      expect(result.stdout, ['Updated secret $name in memory']);
      expect(await store.read(name), value);
    });
  });

  group('set: сбои ввода (D8)', () {
    test('многострочная вставка с TTY: код 64, ничего не сохранено', () async {
      final store = MemorySecretStore();
      final input = FakeSecretInput(
        null,
        hasTerminal: true,
        failure: const MultilineSecretException(),
      );

      final result = await over(store).set(setOf(name), input);

      expect(result.exitCode, 64);
      expect(result.stderr, ['secret value must be a single line']);
      expect(result.stdout, isEmpty);
      expect(await store.read(name), isNull);
    });

    test('недопустимый UTF-8 без TTY: код 64, ничего не сохранено', () async {
      final store = MemorySecretStore();
      final input = FakeSecretInput(
        null,
        failure: const FormatException('bad bytes'),
      );

      final result = await over(store).set(setOf(name), input);

      expect(result.exitCode, 64);
      expect(result.stderr, ['secret value must be valid UTF-8']);
      expect(await store.read(name), isNull);
    });
  });

  group('set: проверки до чтения значения (D8)', () {
    test('значение аргументом: код 64, хранилище не открывается, stdin не '
        'читается', () async {
      final opened = <String?>[];
      final input = FakeSecretInput(value);

      final result = await over(
        MemorySecretStore(),
        opened: opened,
      ).set(setOf(name, valueArgument: true), input);

      expect(result.exitCode, 64);
      expect(
        result.stderr.join('\n'),
        contains('pass the secret value on stdin, not as an argument'),
      );
      expect(result.showUsage, isTrue);
      expect(opened, isEmpty);
      expect(input.events, isEmpty);
      expectNoValue(result);
    });

    test('неверное имя: код 64 и справка, хранилище не открывается', () async {
      final opened = <String?>[];
      final input = FakeSecretInput(value);

      final result = await over(
        MemorySecretStore(),
        opened: opened,
      ).set(setOf('Bad Name'), input);

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('expected a secret name'));
      expect(result.showUsage, isTrue);
      expect(opened, isEmpty);
      expect(input.events, isEmpty);
    });

    test('коллизия envOverride: код 64, называет оба имени и переменную, '
        'stdin не читается', () async {
      final store = MemorySecretStore({'codelab/a-b': 'x'});
      final input = FakeSecretInput(value);

      final result = await over(store).set(setOf('codelab/a.b'), input);

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains(
          'secret name codelab/a.b collides with codelab/a-b '
          '(both map to CODELAB_SECRET_CODELAB_A_B)',
        ),
      );
      expect(input.events, isEmpty);
      expect(await store.names(), ['codelab/a-b']);
    });

    test(
      'порядок: names() хранилища раньше чтения значения, запись после',
      () async {
        final events = <String>[];
        final store = _RecordingStore(events);
        final input = FakeSecretInput(value, events: events);

        final result = await over(store).set(setOf(name), input);

        expect(result.exitCode, 0);
        expect(events, ['names', 'readAll', 'names', 'write']);
      },
    );

    test('бэкенд env (auto): код 1, stdin не читается, подсказка с file и '
        'переменной', () async {
      final input = FakeSecretInput(value);

      final result = await real().set(setOf(name), input);

      expect(result.exitCode, 1);
      expect(input.events, isEmpty);
      expect(result.stdout, isEmpty);
      expect(result.stderr, [
        "secret store env is read-only. Add 'secrets.backend: file' to "
            '$home/config.yaml to store secrets in $home/secrets.yaml '
            '(plaintext, 0600), or set CODELAB_SECRET_CODELAB_OPENAI in the '
            'environment',
      ]);
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    });

    test('бэкенд env, заданный явно: та же подсказка', () async {
      File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');

      final result = await real().set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains("'secrets.backend: file'"));
    });

    test('Windows: подсказывает только переменную', () async {
      final result = await real(
        platform: 'windows',
      ).set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 1);
      expect(result.stderr, [
        'secret store env is read-only. Set CODELAB_SECRET_CODELAB_OPENAI in '
            'the environment',
      ]);
    });
  });

  group('set: бэкенд из конфига (D8)', () {
    test('невалидный конфиг с api_key значением не блокирует', () async {
      File('$home/config.yaml').writeAsStringSync('''
secrets:
  backend: file
providers:
  openai:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key: sk-test-INLINE-0000000000
''');

      final result = await real().set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 0, reason: result.stderr.join('\n'));
      expect(result.stdout, ['Stored secret $name in file']);
      expectNoValue(result);
      expect(
        [...result.stdout, ...result.stderr].join(),
        isNot(contains('INLINE')),
      );
    });

    test('file: secrets.yaml создан с правами 0600, предупреждение об '
        'открытом тексте в stderr', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');

      final result = await real().set(setOf(name), FakeSecretInput('$value\n'));

      expect(result.exitCode, 0);
      expect(
        result.stderr,
        contains(
          'warning: secrets are stored unencrypted in $home/secrets.yaml',
        ),
      );
      final file = File('$home/secrets.yaml');
      expect(file.existsSync(), isTrue);
      expect(file.statSync().mode & 0x1ff, 384); // 0600
      expectNoValue(result);
    });

    test('CODELAB_CONFIG сильнее пользовательского конфига', () async {
      File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');
      final extra = '${root.path}/extra.yaml';
      File(extra).writeAsStringSync('secrets:\n  backend: file\n');

      final result = await real().set(
        setOf(name, environment: env({'CODELAB_CONFIG': extra})),
        FakeSecretInput(value),
      );

      expect(result.exitCode, 0, reason: result.stderr.join('\n'));
      expect(result.stdout, ['Stored secret $name in file']);
    });

    test('CODELAB_CONFIG с расширением в любом регистре читается '
        '(.YAML, .Yml)', () async {
      final extra = '${root.path}/extra.YAML';
      File(extra).writeAsStringSync('secrets:\n  backend: file\n');

      final result = await real().set(
        setOf(name, environment: env({'CODELAB_CONFIG': extra})),
        FakeSecretInput(value),
      );

      expect(result.exitCode, 0, reason: result.stderr.join('\n'));
      expect(result.stdout, ['Stored secret $name in file']);
      expect(result.stderr.where((l) => l.contains('CODELAB_CONFIG')), isEmpty);
    });

    test('CODELAB_CONFIG с относительным путём игнорируется с предупреждением, '
        'код выхода прежний', () async {
      final result = await real().set(
        setOf(name, environment: env({'CODELAB_CONFIG': 'extra.yaml'})),
        FakeSecretInput(value),
      );

      // Бэкенд по умолчанию `auto` без файла: env только для чтения.
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains(
          'warning: CODELAB_CONFIG ignored: CODELAB_CONFIG must be an '
          'absolute path',
        ),
      );
    });

    test('CODELAB_CONFIG с чужим расширением: предупреждение, значение '
        'файла не читается', () async {
      final extra = '${root.path}/extra.json';
      File(extra).writeAsStringSync('secrets:\n  backend: file\n');

      final result = await real().list(
        SecretListOptions(environment: env({'CODELAB_CONFIG': extra})),
      );

      expect(result.exitCode, 0);
      expect(result.stdout.first, startsWith('Backend: env'));
      expect(
        result.stderr,
        contains(
          'warning: CODELAB_CONFIG ignored: CODELAB_CONFIG needs a .yaml or '
          '.yml file',
        ),
      );
    });

    test('синтаксическая ошибка YAML: код 1, проблема с файлом и позицией, '
        'значение не читается', () async {
      File('$home/config.yaml').writeAsStringSync('secrets: [unclosed\n');
      final input = FakeSecretInput(value);

      final result = await real().set(setOf(name), input);

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains('$home/config.yaml:'));
      expect(input.events, isEmpty);
    });

    test('secrets.backend: keychain: код 1, not supported yet', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: keychain\n');

      final result = await real().set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains('not supported yet'));
      expect(result.stdout, isEmpty);
    });

    test('file: отказ по правам secrets.yaml — код 1', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');
      File(
        '$home/secrets.yaml',
      ).writeAsStringSync('# CodeLab secrets in plaintext.\n');
      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);

      final result = await real().set(setOf(name), FakeSecretInput(value));

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains('chmod 600'));
      expect(
        result.stderr.join('\n'),
        contains('warning: secrets are stored unencrypted'),
      );
      expectNoValue(result);
    });

    test('CODELAB_HOME с ~user: код 64', () async {
      final result = await real().set(
        setOf(name, environment: {'CODELAB_HOME': '~someone/x'}),
        FakeSecretInput(value),
      );

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('CODELAB_HOME'));
    });
  });

  group('delete', () {
    test('существующий секрет', () async {
      final store = MemorySecretStore({name: value});

      final result = await over(
        store,
      ).delete(SecretDeleteOptions(name: name, environment: env()));

      expect(result.exitCode, 0);
      expect(result.stdout, ['Deleted secret $name from memory']);
      expect(await store.names(), isEmpty);
    });

    test('отсутствующий секрет: код 0, идемпотентно', () async {
      final result = await over(
        MemorySecretStore(),
      ).delete(SecretDeleteOptions(name: name, environment: env()));

      expect(result.exitCode, 0);
      expect(result.stdout, ['Secret $name was not set in memory']);
    });

    test('бэкенд env: код 1 с подсказкой', () async {
      final result = await real().delete(
        SecretDeleteOptions(name: name, environment: env()),
      );

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains('secrets.backend: file'));
    });

    test('неверное имя: код 64 и справка', () async {
      final result = await real().delete(
        SecretDeleteOptions(name: 'Bad Name', environment: env()),
      );

      expect(result.exitCode, 64);
      expect(result.showUsage, isTrue);
    });

    test('file: предупреждение об открытом тексте в stderr', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');

      final result = await real().delete(
        SecretDeleteOptions(name: name, environment: env()),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, ['Secret $name was not set in file']);
      expect(result.stderr, [
        'warning: secrets are stored unencrypted in $home/secrets.yaml',
      ]);
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    });
  });

  group('без домашнего каталога', () {
    // Ревью итерации 4: без CODELAB_HOME, HOME и USERPROFILE `codelabHomeOf`
    // даёт `./.codelab`, и `secrets.yaml` лёг бы в текущий каталог (возможно,
    // git-репозиторий). Подкоманды `secret` отказывают, `serve` не меняется.
    const text = 'cannot find the home folder: set CODELAB_HOME or HOME';
    final noHome = <String, String>{'HOME': '', 'CODELAB_HOME': ''};

    test('set: код 64 и текст, значение не читается', () async {
      final input = FakeSecretInput('$value\n');
      final result = await real().set(
        SecretSetOptions(name: name, environment: noHome),
        input,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, [text]);
      expect(result.showUsage, isFalse);
      expect(result.stdout, isEmpty);
    });

    test('delete и list: код 64 и тот же текст', () async {
      final deleted = await real().delete(
        SecretDeleteOptions(name: name, environment: noHome),
      );
      final listed = await real().list(SecretListOptions(environment: noHome));

      expect(deleted.exitCode, 64);
      expect(deleted.stderr, [text]);
      expect(listed.exitCode, 64);
      expect(listed.stderr, [text]);
      expect(deleted.showUsage, isFalse);
      expect(listed.showUsage, isFalse);
    });

    test('USERPROFILE без HOME домашним каталогом считается', () async {
      final result = await real().list(
        SecretListOptions(
          environment: {'USERPROFILE': root.path, 'CODELAB_HOME': ''},
        ),
      );

      expect(result.exitCode, 0);
    });
  });

  group('list', () {
    test('auto: Backend: env (причина), имён нет, переопределения только '
        'именами', () async {
      final result = await real().list(
        SecretListOptions(
          environment: env({
            'CODELAB_SECRET_Z': 'zz-value-1',
            'CODELAB_SECRET_X': 'xx-value-2',
          }),
        ),
      );

      expect(result.exitCode, 0);
      expect(result.stdout.first, startsWith('Backend: env (OS keychain'));
      expect(result.stdout.first, contains('secrets.backend: file'));
      expect(
        result.stdout.last,
        'Environment overrides: CODELAB_SECRET_X, CODELAB_SECRET_Z',
      );
      expect(
        [...result.stdout, ...result.stderr].join(),
        isNot(contains('value')),
      );
    });

    test('env явно: первая строка — Backend: env, без переопределений нет '
        'строки', () async {
      File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');

      final result = await real().list(SecretListOptions(environment: env()));

      expect(result.exitCode, 0);
      expect(result.stdout, ['Backend: env']);
    });

    test('имена по алфавиту после строки бэкенда', () async {
      final store = MemorySecretStore({'codelab/b': '1', 'codelab/a': '2'});

      final result = await over(
        store,
      ).list(SecretListOptions(environment: env()));

      expect(result.stdout, ['Backend: memory', 'codelab/a', 'codelab/b']);
    });

    test('Windows: причина называет только переменные', () async {
      final result = await real(
        platform: 'windows',
      ).list(SecretListOptions(environment: env()));

      expect(result.stdout.first, isNot(contains('secrets.backend: file')));
      expect(result.stdout.first, contains('CODELAB_SECRET_*'));
    });

    test('file: имена, предупреждение в stderr; права 0644 — код 1', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');
      final set = await real().set(setOf(name), FakeSecretInput(value));
      expect(set.exitCode, 0);

      final ok = await real().list(SecretListOptions(environment: env()));
      expect(ok.exitCode, 0);
      expect(ok.stdout, ['Backend: file', name]);
      expect(ok.stderr, [
        'warning: secrets are stored unencrypted in $home/secrets.yaml',
      ]);

      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);
      final wide = await real().list(SecretListOptions(environment: env()));
      expect(wide.exitCode, 1);
      expect(wide.stderr.join('\n'), contains('chmod 600 $home/secrets.yaml'));
      expectNoValue(wide);
    });
  });
}

/// Хранилище, фиксирующее порядок обращений (D8: `checkStore` до чтения).
final class _RecordingStore implements DescribedSecretStore {
  _RecordingStore(this.events);

  final List<String> events;
  final _inner = MemorySecretStore();

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> delete(String name) => _inner.delete(name);

  @override
  Future<List<String>> names() {
    events.add('names');
    return _inner.names();
  }

  @override
  Future<void> write(String name, String value) {
    events.add('write');
    return _inner.write(name, value);
  }
}
