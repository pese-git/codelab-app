// PTY-e2e недавних проектов CLI (задача 3.6 change
// `share-recent-projects-store`; spec codelab-cli «Недавние проекты CLI»,
// сценарии «REPL записывает папку», «Полноэкранный режим записывает папку»,
// «Продолжение сессии записывает папку», «Headless не трогает список»;
// design.md D6, решение Q3).
//
// Только Dart VM. Каждый тест работает во временных `CODELAB_HOME` и `HOME`;
// встроенный агент — сценарная точка входа (ход без сети), конфиг с готовым
// провайдером обходит мастер первого запуска. Файл читается как JSON: формат
// — деталь хранилища (D1), тесту нужны только `path` записей.
@Timeout(Duration(seconds: 90))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/pty_process.dart';

const _ctrlC = '\x03';
const _ctrlD = '\x04';
const _answer = 'hello from the embedded agent';

const _readyConfig = '''
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

const _emptyConfig = 'secrets:\n  backend: file\n';

void main() async {
  final skip = await PtyProcess.unavailableReason();
  late Directory dir;
  late String home;
  late String project;
  late File recent;

  test('kernel сборки CLI готов', () async {
    await CliProcess.kernelOf(CliEntry.scriptedEmbedded);
  }, timeout: const Timeout(Duration(seconds: 240)));

  setUp(() {
    // Канонический путь: CLI записывает нормализованную папку (macOS: `/var`).
    dir = Directory(
      Directory.systemTemp
          .createTempSync('cli_recent_projects_')
          .resolveSymbolicLinksSync(),
    );
    home = '${dir.path}/codelab';
    project = '${dir.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    recent = File('$home/recent_projects.json');
    File('$home/config.yaml').writeAsStringSync(_readyConfig);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Сценарий модели с одним ответом [_answer] для сценарной точки входа.
  Map<String, String> scriptEnv() {
    final path = '${dir.path}/script.json';
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
    return {'CODELAB_E2E_LLM_SCRIPT': path};
  }

  Map<String, String> env() => {
    'HOME': '${dir.path}/no-home',
    'CODELAB_HOME': home,
    'LANG': 'en_US.UTF-8',
    ...scriptEnv(),
  };

  Future<PtyProcess> pty(List<String> args) async =>
      PtyProcess.start(dartExecutable(), [
        await CliProcess.kernelOf(CliEntry.scriptedEmbedded),
        '-C',
        project,
        ...args,
      ], environment: env());

  List<String> recordedPaths() {
    final json = jsonDecode(recent.readAsStringSync()) as Map<String, Object?>;
    return [
      for (final p in json['projects']! as List<Object?>)
        (p! as Map<String, Object?>)['path']! as String,
    ];
  }

  test(
    'cli/recent-projects-repl: REPL записывает папку первой записью',
    () async {
      final p = await pty([]);
      await p.waitFor('> ');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: p.text);
      expect(recordedPaths(), [project]);
    },
    skip: skip,
  );

  test(
    'cli/recent-projects-tui: полноэкранный режим записывает папку',
    () async {
      final p = await pty(['--ui', 'tui']);
      await p.waitFor('\x1b[?1049h');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: p.text);
      expect(recordedPaths(), [project]);
    },
    skip: skip,
  );

  test(
    'cli/recent-projects-continue: --continue записывает папку (Q3)',
    () async {
      // Сессии нет: запуск завершается ошибкой, но запись делается до
      // подключения (D6).
      final p = await pty(['--continue']);
      await p.exitCode;

      expect(recordedPaths(), [project]);
    },
    skip: skip,
  );

  test('cli/recent-projects-headless: -p не создаёт файл', () async {
    final result = await CliProcess.run(
      ['-C', project, '-p', 'hi'],
      environment: env(),
      entry: CliEntry.scriptedEmbedded,
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(recent.existsSync(), isFalse);
  });

  test('cli/recent-projects-first-run-cancel: мастер, завершивший процесс '
      '(Ctrl+C → 130), записи не оставляет', () async {
    File('$home/config.yaml').writeAsStringSync(_emptyConfig);

    final p = await pty([]);
    await p.waitFor('? API type');
    p.write(_ctrlC);

    expect(await p.exitCode, 130, reason: p.text);
    expect(recent.existsSync(), isFalse);
  }, skip: skip);
}
