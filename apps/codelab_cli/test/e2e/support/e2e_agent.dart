import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;

import '../../support/cli_process.dart';

typedef _Mode = CodelabCompatibleStdioAgentMode;

/// Какой агент стоит за e2e терминального клиента.
enum E2eAgentKind { scripted, dart, python }

/// Тег тестов поведения, которое есть только у scripted-агента, и тестов, не
/// зависящих от агента; прогон против Dart-агента их исключает.
const scriptedOnly = 'scripted-only';

/// Тег тестов обычного хода, которые идут и против Python-агента: его
/// mock-провайдер отвечает текстом, без инструментов (design.md, D4).
const pythonAgent = 'python-agent';

/// Агент e2e CLI, выбранный переменной окружения `CODELAB_E2E_AGENT`.
///
/// Почему: одни и те же тесты `cli/*` проверяют CLI и против scripted-агента
/// из `codelab_acp_testing`, и против `codelab-agent`; тексты ответов у
/// агентов разные, и тест не должен их знать (testing-quality «PTY-e2e
/// терминального клиента»; design.md change `add-cli-e2e-agent-matrix`,
/// D1–D3).
///
/// Для чего: единственное место, где тест узнаёт значение `--agent` и
/// ожидания, которые у агентов различаются ([E2eCliLaunch]).
///
/// Как использовать: `final launch = await E2eCliAgent.current.launch(dir,
/// mode: …)`; `launch.agent` — значение `--agent`. Режим без сценария
/// Dart-агента — [StateError]: такой тест помечается [scriptedOnly].
final class E2eCliAgent {
  E2eCliAgent._(this.kind, this._path);

  /// Агент из окружения процесса тестов.
  static final E2eCliAgent current = E2eCliAgent.fromEnvironment(
    Platform.environment,
  );

  /// Агент по [environment]; без `CODELAB_E2E_AGENT` — scripted.
  factory E2eCliAgent.fromEnvironment(Map<String, String> environment) =>
      E2eCliAgent._(switch (environment['CODELAB_E2E_AGENT'] ?? 'scripted') {
        'scripted' => E2eAgentKind.scripted,
        'dart' => E2eAgentKind.dart,
        'python' => E2eAgentKind.python,
        final other => throw ArgumentError.value(other, 'CODELAB_E2E_AGENT'),
      }, environment['PATH'] ?? '');

  final E2eAgentKind kind;

  /// `PATH`, в котором ищется Python-агент.
  final String _path;

  /// Причина пропустить тест: агента нет; `null` — агент есть.
  ///
  /// Python-агент — `codelab` из `PATH`, который отвечает на `serve --help`
  /// кодом `0` и флагом `--stdio`. Другая программа `codelab` (бинарь CLI
  /// этапа 9) так не отвечает — тест пропускается, а не падает (D4).
  Future<String?> unavailable() async {
    if (kind != E2eAgentKind.python) {
      return null;
    }
    try {
      final help = await Process.run(
        'codelab',
        const ['serve', '--help'],
        environment: {'PATH': _path},
      );
      if (help.exitCode == 0 && '${help.stdout}'.contains('--stdio')) {
        return null;
      }
    } on ProcessException {
      // Нет `codelab` в `PATH`.
    }
    return 'Python agent (codelab serve) is not installed';
  }

  bool get isScripted => kind == E2eAgentKind.scripted;

  /// scripted: пишет агента в [dir]; dart: агент из kernel со сценарием
  /// `test/e2e/llm_scripts/<mode.wireName>.json` и журналом в
  /// `[dir]/agent-sessions`.
  Future<E2eCliLaunch> launch(
    Directory dir, {
    CodelabCompatibleStdioAgentMode mode = _Mode.normal,
  }) => switch (kind) {
    E2eAgentKind.scripted => _scripted(dir, mode),
    E2eAgentKind.dart => _dart(dir, mode),
    E2eAgentKind.python => _python(dir, mode),
  };

  /// Python-агент со своим `CODELAB_HOME`: провайдер `mock` отвечает без
  /// сети, а `codelab-stdio.lock` агента не пересекается с CLI и другими
  /// тестами. `CODELAB_HOME` задаётся в самой команде (`env`): агент
  /// наследует окружение CLI, а у CLI свой `CODELAB_HOME`.
  static Future<E2eCliLaunch> _python(Directory dir, _Mode mode) async {
    if (mode != _Mode.normal) {
      throw StateError(
        'the Python agent mock answers text only, not ${mode.wireName}: '
        'tag only plain-turn tests "$pythonAgent"',
      );
    }
    final home = '${dir.path}/python-home';
    await Directory(home).create(recursive: true);
    File(
      '$home/codelab.toml',
    ).writeAsStringSync('[llm]\nprovider = "mock"\nmodel = "mock/mock"\n');
    // У mock-провайдера нет инструментов, опций и списка сессий: такие
    // ожидания в тестах с тегом python-agent не нужны.
    Never unsupported([Object? _]) =>
        throw StateError('not a plain-turn expectation of the Python agent');
    return E2eCliLaunch._(
      agent: "stdio:env CODELAB_HOME='$home' codelab serve --stdio",
      answer: 'Mock response',
      permissionTitle: '',
      criticalTitle: '',
      permissionCommand: '',
      allowedMarker: '',
      rejectedMarker: '',
      allowedAnswer: '',
      rejectedAnswer: '',
      models: const [],
      completedToolRow: '',
      sessionAnswer: unsupported,
      listedSession: unsupported,
      savedSessions: unsupported,
    );
  }

  static Future<E2eCliLaunch> _scripted(Directory dir, _Mode mode) async =>
      E2eCliLaunch._(
        agent: await scriptedAgent(dir, mode: mode),
        answer: 'hello from compatible stdio agent',
        permissionTitle: 'Run test command',
        criticalTitle: 'Run rm -rf build',
        permissionCommand: 'echo hello',
        allowedMarker: 'approved: allow_once',
        rejectedMarker: 'approved: reject_once',
        allowedAnswer: 'approved: allow_once',
        rejectedAnswer: 'approved: reject_once',
        models: const ['gpt-5', 'gpt-4'],
        completedToolRow: '✓ Run',
        sessionAnswer: (prompt) => 'echo: $prompt',
        listedSession: (_) => 'codelab-list-session-1',
        savedSessions: () {
          final file = File(
            '${dir.path}/codelab_compatible_stdio_agent.dart.sessions.json',
          );
          return file.existsSync()
              ? (jsonDecode(file.readAsStringSync()) as List).length
              : 0;
        },
      );

  static Future<E2eCliLaunch> _dart(Directory dir, _Mode mode) async {
    final flags = switch (mode) {
      _Mode.normal ||
      _Mode.withSessionList ||
      _Mode.hangsUntilCancel ||
      _Mode.promptError ||
      _Mode.emptyResponse => const <String>[],
      _Mode.withPermissionRequest ||
      _Mode.withCriticalPermission => const ['--permission-mode', 'standard'],
      _Mode.withConfigOptions => const ['--model', 'gpt-5', '--model', 'gpt-4'],
      // Чтение и запись — без вопроса, команда — с вопросом: ход кончается
      // одобрением, как у scripted-агента.
      _Mode.withToolCalls => const ['--permission-mode', 'accept-edits'],
      _ => throw StateError(
        'no codelab-agent script for ${mode.wireName}: tag the test '
        '"$scriptedOnly"',
      ),
    };
    if (mode == _Mode.withToolCalls) {
      File('${dir.path}/README.md').writeAsStringSync('# e2e\n');
    }
    final sessions = '${dir.path}/agent-sessions';
    final script = '$appDirectory/test/e2e/llm_scripts/${mode.wireName}.json';
    return E2eCliLaunch._(
      agent: [
        "stdio:'${dartExecutable()}' '${await agentKernel()}'",
        'serve --stdio',
        "--llm-script '$script'",
        "--sessions-dir '$sessions'",
        ...flags,
      ].join(' '),
      answer: 'hello from compatible stdio agent',
      // Заголовок `exec` — сама команда (ToolPresentation инструмента).
      permissionTitle: 'echo hello',
      // `rm -rf build` для Dart-агента не критичен (P-07: критичны корень,
      // домашний и системный каталоги, предок рабочей папки). `rm -rf .` —
      // критичен, а при поломке защиты удалит только временную папку теста.
      criticalTitle: 'rm -rf .',
      permissionCommand: 'echo hello',
      // Сценарий не знает решения пользователя: итог виден по строке
      // вызова, а ответ модели после результата один.
      allowedMarker: '✓ echo hello',
      rejectedMarker: '⊘ echo hello',
      allowedAnswer: 'approved',
      rejectedAnswer: 'approved',
      models: const ['scripted/gpt-5', 'scripted/gpt-4'],
      completedToolRow: '✓ Write',
      sessionAnswer: (_) => 'session answer',
      // Заголовок сессии Dart-агент берёт из первого промпта.
      listedSession: (firstPrompt) => firstPrompt,
      savedSessions: () {
        final directory = Directory(sessions);
        return directory.existsSync()
            ? directory
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.jsonl'))
                  .length
            : 0;
      },
    );
  }

  static Future<String>? _kernel;

  /// Путь к kernel `apps/codelab_agent/bin/codelab_agent.dart`; один раз на
  /// процесс тестов, как `CliProcess.kernel()` CLI. Тесты CLI не импортируют
  /// `package:codelab_agent_*` (сторож): агент — отдельный процесс.
  static Future<String> agentKernel() => _kernel ??= _compileAgent();

  static Future<String> _compileAgent() async {
    final agent = '$appDirectory/../codelab_agent';
    final dir = await Directory.systemTemp.createTemp('codelab_agent_kernel_');
    final output = '${dir.path}/codelab_agent.dill';
    final result = await Process.run(dartExecutable(), [
      'compile',
      'kernel',
      '$agent/bin/codelab_agent.dart',
      '-o',
      output,
    ], workingDirectory: agent);
    if (result.exitCode != 0) {
      throw StateError('cannot compile codelab-agent: ${result.stderr}');
    }
    return output;
  }
}

/// Значение `--agent` и ожидания, которые у агентов различаются.
final class E2eCliLaunch {
  E2eCliLaunch._({
    required this.agent,
    required this.answer,
    required this.permissionTitle,
    required this.criticalTitle,
    required this.permissionCommand,
    required this.allowedMarker,
    required this.rejectedMarker,
    required this.allowedAnswer,
    required this.rejectedAnswer,
    required this.models,
    required this.completedToolRow,
    required String Function(String prompt) sessionAnswer,
    required String Function(String firstPrompt) listedSession,
    required int Function() savedSessions,
  }) : _sessionAnswer = sessionAnswer,
       _listedSession = listedSession,
       _savedSessions = savedSessions;

  /// Значение `--agent` (`stdio:…`).
  final String agent;

  /// Ответ на обычный промпт (режим `normal`).
  final String answer;

  /// Заголовок вызова в строке `Permission: …` и в решении headless.
  final String permissionTitle;

  /// Заголовок критического вызова (`rm -rf build`).
  final String criticalTitle;

  /// Команда в строке `command: …` блока одобрения.
  final String permissionCommand;

  /// Что видно в REPL и TUI после `y` и после `n`.
  final String allowedMarker;
  final String rejectedMarker;

  /// stdout headless после разрешения и после отказа.
  final String allowedAnswer;
  final String rejectedAnswer;

  /// Значения опции `model`: текущее первым.
  final List<String> models;

  /// Строка завершённого вызова в ходе `with_tool_calls`.
  final String completedToolRow;

  final String Function(String) _sessionAnswer;
  final String Function(String) _listedSession;
  final int Function() _savedSessions;

  /// Ответ на [prompt] в режиме `with_session_list`.
  String sessionAnswer(String prompt) => _sessionAnswer(prompt);

  /// Что строка `/sessions` показывает о сессии с первым промптом
  /// [firstPrompt].
  String listedSession(String firstPrompt) => _listedSession(firstPrompt);

  /// Сколько сессий агент сохранил.
  int savedSessions() => _savedSessions();
}
