// Запись недавних проектов в `runCodelab` (change
// `share-recent-projects-store`, задача 3.3; spec codelab-cli «Недавние
// проекты CLI»; design.md D2, D6, решение Q3).
//
// Почему модульный уровень: сценарии REPL проверяются через шов
// `runCodelab(…, environment:, io:)` с временным `CODELAB_HOME`; процесс и
// PTY — в `test/e2e/recent_projects_test.dart` (задача 3.6). TUI здесь не
// покрыт: ему нужен настоящий терминал.
//
// У `runCodelab` нет шва терминала: REPL и мастер первого запуска читают
// настоящий stdin процесса `dart test`, который не закрывается (зависание) и
// слушается один раз (второй REPL в процессе падает). Поэтому REPL здесь
// запускается с `--resume <несуществующая сессия>`: встроенный агент не
// умеет `session/load`, запуск завершается ошибкой старта до `Repl.run`, а
// запись папки (D6: после `connect`, до загрузки сессии) к этому моменту уже
// должна быть сделана.
// Обычный REPL без `--resume`, мастер первого запуска и TUI — только PTY-e2e
// (задача 3.6, `test/e2e/recent_projects_test.dart`).

import 'dart:convert';
import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Логгер, который ничего не пишет: агент в этих тестах молчит.
final class _NoLogger implements Logger {
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

const _script = {
  'model': {
    'provider': 'scripted',
    'modelId': 'scripted-1',
    'contextWindow': 32768,
  },
  'steps': [
    {
      'reply': [
        {'text': 'hello'},
      ],
      'stopReason': 'stop',
    },
  ],
};

/// Готовый провайдер: мастер первого запуска не вызывается.
const _readyConfig = '''
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
''';

void main() {
  late Directory tmp;
  late String project;
  late String home;
  late File recent;

  setUp(() {
    tmp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_run_recent_')
          .resolveSymbolicLinksSync(),
    );
    project = '${tmp.path}/proj';
    Directory(project).createSync();
    home = '${tmp.path}/home';
    Directory(home).createSync();
    recent = File('$home/recent_projects.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  EmbeddedAgentOpener scripted() => scriptedEmbeddedAgentOpener(
    llm: _script,
    codelabHome: home,
    logger: _NoLogger(),
  );

  Map<String, String> env() => {'CODELAB_HOME': home, 'HOME': tmp.path};

  /// Пути из файла по порядку: формат файла — деталь хранилища (D1), тест
  /// читает только `path`.
  List<String> recordedPaths() {
    final json = jsonDecode(recent.readAsStringSync()) as Map<String, Object?>;
    return [
      for (final project in json['projects']! as List<Object?>)
        (project! as Map<String, Object?>)['path']! as String,
    ];
  }

  /// Интерактивный запуск, который сам завершается на старте агента.
  Future<(int, FakeCliIo)> repl(List<String> args) async {
    final io = FakeCliIo(stdinIsTerminal: true);
    final code = await runCodelab(
      [...args, '--resume', 'no-such-session'],
      environment: env(),
      io: io,
      embeddedOpener: scripted(),
    );
    return (code, io);
  }

  group('интерактивные режимы пишут папку (D6)', () {
    setUp(() => File('$home/config.yaml').writeAsStringSync(_readyConfig));

    test('REPL записывает -C-папку первой записью', () async {
      await repl(['-C', project]);

      expect(recordedPaths(), [project]);
    });

    test('--continue — обычный интерактивный запуск, папка записана '
        '(решение Q3)', () async {
      await runCodelab(
        ['--continue', '-C', project],
        environment: env(),
        io: FakeCliIo(stdinIsTerminal: true),
        embeddedOpener: scripted(),
      );

      expect(recordedPaths(), [project]);
    });

    test('повторный запуск в той же папке не плодит записей', () async {
      await repl(['-C', project]);
      await repl(['-C', project]);

      expect(recordedPaths(), [project]);
    });
  });

  // Точка записи — после успешного `connect` (D6, уточнение 2026-11-22;
  // spec «Неудачный старт не записывает папку», задача 3.7). Запуск, который
  // не начался, не попадает в список; `--resume` идёт после записи, поэтому
  // проверяет именно порядок «подключение, запись, загрузка сессии».
  group('неудачный старт агента не записывает папку (задача 3.7)', () {
    test('встроенный агент без модели: код 64, файла нет', () async {
      // Конфига нет: модель не настроена. Настоящий открыватель (без шва)
      // бросает `EmbeddedAgentConfigException`; `stdoutIsTerminal: false` —
      // мастер первого запуска не стартует.
      final io = FakeCliIo(stdinIsTerminal: true);

      final code = await runCodelab(
        ['-C', project, '--resume', 'no-such-session'],
        environment: env(),
        io: io,
      );

      expect(code, 64, reason: io.stderrText);
      expect(recent.existsSync(), isFalse);
    });

    test('stdio: с несуществующей командой: код 1, файла нет', () async {
      final io = FakeCliIo(stdinIsTerminal: true);

      final code = await runCodelab(
        [
          '-C',
          project,
          '-a',
          'stdio:$home/no-such-agent',
          '--resume',
          'no-such-session',
        ],
        environment: env(),
        io: io,
      );

      expect(code, 1, reason: io.stderrText);
      expect(recent.existsSync(), isFalse);
    });

    test('страж: --resume без такой сессии после успешного подключения '
        'по-прежнему записывает папку (Q3)', () async {
      File('$home/config.yaml').writeAsStringSync(_readyConfig);

      await repl(['-C', project]);

      expect(recordedPaths(), [project]);
    });
  });

  group('остальные режимы не создают и не меняют файл', () {
    test('-p: файла нет', () async {
      final io = FakeCliIo();

      await runCodelab(
        ['-p', 'hi', '-C', project],
        environment: env(),
        io: io,
        embeddedOpener: scripted(),
      );

      expect(recent.existsSync(), isFalse);
    });

    test('промпт из stdin без TTY: файла нет', () async {
      final io = FakeCliIo(stdin: 'hi\n');

      await runCodelab(
        ['-C', project],
        environment: env(),
        io: io,
        embeddedOpener: scripted(),
      );

      expect(recent.existsSync(), isFalse);
    });

    group('подкоманды: байты существующего файла прежние', () {
      const seeded =
          '{"version":1,"projects":[{"path":"/seed",'
          '"lastOpenedAt":"2026-01-01T00:00:00.000"}]}';

      setUp(() {
        File('$home/config.yaml').writeAsStringSync(_readyConfig);
        recent.writeAsStringSync(seeded);
      });

      for (final args in [
        ['config', 'check'],
        ['test-scenario'],
        ['profiles', 'list'],
        ['--version'],
        ['--help'],
      ]) {
        test(args.join(' '), () async {
          await runCodelab(
            [
              ...args,
              if (args.first == 'config') ...['-C', project],
            ],
            environment: env(),
            io: FakeCliIo(),
            embeddedOpener: scripted(),
          );

          expect(recent.readAsStringSync(), seeded);
        });
      }
    });
  });

  group('нечитаемый файл (D2, spec «Нечитаемый файл не мешает REPL»)', () {
    const broken = '{not json';

    setUp(() {
      File('$home/config.yaml').writeAsStringSync(_readyConfig);
      recent.writeAsStringSync(broken);
    });

    test('--verbose: одна строка с типом ошибки, код как без файла, байты '
        'прежние', () async {
      final (code, io) = await repl(['--verbose', '-C', project]);

      final lines = io.stderrText
          .split('\n')
          .where((l) => l.startsWith('codelab: cannot record'))
          .toList();
      expect(lines, [
        'codelab: cannot record a recent project: FormatException',
      ]);
      expect(recent.readAsStringSync(), broken);

      recent.deleteSync();
      final (control, _) = await repl(['--verbose', '-C', project]);
      expect(code, control);
    });

    test(
      'без --verbose: строки нет, код как без файла, байты прежние',
      () async {
        final (code, io) = await repl(['-C', project]);

        expect(io.stderrText, isNot(contains('cannot record')));
        expect(recent.readAsStringSync(), broken);

        recent.deleteSync();
        final (control, _) = await repl(['-C', project]);
        expect(code, control);
      },
    );
  });
}
