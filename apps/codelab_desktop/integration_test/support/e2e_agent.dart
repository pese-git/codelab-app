import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, LogLevel, Logger;
// Сценарий модели — только для тестов: рабочий код app его не импортирует
// (сторож, design.md change `add-embedded-agent-mode`, D3, D8).
import 'package:codelab_embedded/testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Какой агент стоит за e2e-тестами app.
///
/// [embedded] — встроенный агент в процессе app: тип подключения «Embedded
/// agent», сценарий модели `scriptedEmbeddedAgentOpener` (design.md change
/// `add-embedded-agent-mode`, D8, D10).
enum E2eAgentKind { scripted, dart, embedded }

/// Тег тестов, которые проверяют поведение именно scripted-агента; в режиме
/// `dart` прогон идёт с `--exclude-tags scripted-only` (`dart_test.yaml`).
const scriptedOnly = 'scripted-only';

/// Агент e2e-тестов, выбранный `--dart-define=CODELAB_E2E_AGENT`.
///
/// Почему: одни и те же 8 тестов `integration_test/` проверяют app и против
/// scripted-агента из `codelab_acp_testing`, и против бинаря `codelab-agent`; код
/// `lib/` при этом не меняется (контракт e2e `09-09`; design.md change
/// `add-codelab-agent-binary`, D9).
///
/// Для чего: единственное место, где тест узнаёт команду запуска агента и
/// ожидания, которые у агентов различаются (метка сессии, модели, заголовок
/// одобрения, маркер сырых аргументов).
///
/// Как использовать: `final launch = await E2eAgent.current.launch(tempDir,
/// mode: …)`; [E2eLaunch.command] и [E2eLaunch.args] вводятся в поля
/// `transport-field-Command` и `transport-field-Args`. Режим без сценария
/// Dart-агента — [StateError]: такой тест помечается [scriptedOnly].
final class E2eAgent {
  E2eAgent._(this.kind);

  static final E2eAgent current = E2eAgent._(
    switch (const String.fromEnvironment(
      'CODELAB_E2E_AGENT',
      defaultValue: 'scripted',
    )) {
      'scripted' => E2eAgentKind.scripted,
      'dart' => E2eAgentKind.dart,
      'embedded' => E2eAgentKind.embedded,
      final other => throw ArgumentError.value(other, 'CODELAB_E2E_AGENT'),
    },
  );

  final E2eAgentKind kind;

  bool get isScripted => kind == E2eAgentKind.scripted;

  /// Пропустить тесты `fs/*` и `terminal/*` во встроенном режиме.
  ///
  /// Причина: встроенные профили исполняют файлы и команды локально, а не
  /// через ACP-методы клиента `fs/*` и `terminal/*`, поэтому эти тесты там
  /// нечего проверять (design.md change `add-embedded-agent-mode`, D4, D10).
  /// `skip` у `testWidgets` — `bool`, причина записана здесь.
  bool get skipFsAndTerminal => kind == E2eAgentKind.embedded;

  /// Суффикс описания теста `fs/*` и `terminal/*`: при пропуске причина видна
  /// в выводе раннера (у `skip: true` её нет).
  String get skipNote => skipFsAndTerminal
      ? ' [skipped: the embedded agent runs files and commands locally, not '
            'through ACP fs/* and terminal/*]'
      : '';

  /// Пропустить тесты, которым нужен процесс `codelab-agent serve --ws`:
  /// есть только в режиме `dart`; у scripted-агента сервера WebSocket нет, у
  /// встроенного — тоже.
  bool get skipWebSocketAgent => kind != E2eAgentKind.dart;

  /// Данные следующего подключения встроенного агента: их задаёт [launch], а
  /// открыватель scope читает в момент подключения. Поэтому `bootstrap()`
  /// можно звать до `launch()`, как делают тесты.
  _EmbeddedSetup? _embeddedSetup;

  /// Корень приложения теста.
  ///
  /// Почему не `const CodeLabBootstrap(child: CodeLabApp())` в каждом тесте:
  /// во встроенном режиме root scope должен получить открыватель со сценарием
  /// (шов `createCodeLabRootScope(embeddedOpener:)`, D9); в остальных режимах
  /// остаётся прежний корень.
  ///
  /// Как использовать: `await tester.pumpWidget(E2eAgent.current.bootstrap())`.
  /// Каждый вызов создаёт новый root scope, поэтому перезапуск app в тесте
  /// закрывает прежний `closeCodeLabRootScope()`.
  Widget bootstrap() {
    // Данные прошлого теста не должны попасть в подключение нового.
    _embeddedSetup = null;
    return _bootstrap();
  }

  Widget _bootstrap() => switch (kind) {
    E2eAgentKind.embedded => CodeLabBootstrap(
      scope: createCodeLabRootScope(embeddedOpener: _embeddedOpener),
      child: const CodeLabApp(),
    ),
    _ => const CodeLabBootstrap(child: CodeLabApp()),
  };

  /// Открыватель, который строит агента по данным последнего [launch]:
  /// сценарий `integration_test/llm_scripts/<режим>.json` с тем же набором
  /// режимов разрешений, моделей и журнала, что флаги бинаря
  /// ([_dartFlags]).
  Future<EmbeddedAgent> _embeddedOpener({
    required String cwd,
    required String hostProfile,
  }) {
    final setup = _embeddedSetup;
    if (setup == null) {
      throw StateError('E2eAgent.launch must run before the first connect');
    }
    return scriptedEmbeddedAgentOpener(
      llm: setup.llm,
      codelabHome: setup.home,
      permissionMode: setup.permissionMode,
      sessionsDir: setup.sessionsDir,
      models: setup.models,
      logger: _SilentLogger(),
    )(cwd: cwd, hostProfile: hostProfile);
  }

  /// scripted: пишет агента из `codelab_acp_testing` в [tempDir]; dart: ничего не
  /// пишет, сценарий — `integration_test/llm_scripts/<mode.wireName>.json`.
  Future<E2eLaunch> launch(
    Directory tempDir, {
    CodelabCompatibleStdioAgentMode mode =
        CodelabCompatibleStdioAgentMode.normal,
  }) async {
    switch (kind) {
      case E2eAgentKind.scripted:
        final agent = await writeCodelabCompatibleStdioAgent(
          tempDir,
          mode: mode,
        );
        const dart = String.fromEnvironment(
          'CODELAB_E2E_DART',
          defaultValue: 'dart',
        );
        return E2eLaunch._(
          command: _absolute(dart),
          args: '${_noSpaces(agent.path)} serve --stdio',
          // До первого промпта сессия называется «New session», а не по id
          // (fix #99 «называть сессию по первому промпту вместо id»).
          sessionLabel: equals('New session'),
          models: const [
            (value: 'gpt-5', name: 'GPT-5'),
            (value: 'gpt-4', name: 'GPT-4'),
          ],
          rawInputMarker: '/bin/bash',
        );
      case E2eAgentKind.dart:
        const bin = String.fromEnvironment('CODELAB_E2E_AGENT_BIN');
        if (bin.isEmpty) {
          throw StateError(
            'CODELAB_E2E_AGENT=dart needs CODELAB_E2E_AGENT_BIN '
            '(melos run test:e2e:app:dart-agent)',
          );
        }
        final script = File(
          'integration_test/llm_scripts/${mode.wireName}.json',
        ).absolute.path;
        return E2eLaunch._(
          command: _noSpaces(File(bin).absolute.path),
          args: [
            'serve',
            '--stdio',
            '--llm-script',
            _noSpaces(script),
            ..._dartFlags(mode, tempDir),
          ].join(' '),
          sessionLabel: equals('New session'),
          models: const [
            (value: 'scripted/gpt-5', name: 'gpt-5'),
            (value: 'scripted/gpt-4', name: 'gpt-4'),
          ],
          rawInputMarker: 'timeout',
        );
      case E2eAgentKind.embedded:
        _embeddedSetup = _EmbeddedSetup.of(mode, tempDir);
        return E2eLaunch._(
          command: '',
          args: '',
          embedded: true,
          sessionLabel: equals('New session'),
          // Ожидания те же, что у бинаря `--llm-script`: один и тот же
          // сценарий модели (D8).
          models: const [
            (value: 'scripted/gpt-5', name: 'gpt-5'),
            (value: 'scripted/gpt-4', name: 'gpt-4'),
          ],
          rawInputMarker: 'timeout',
        );
    }
  }

  /// Запускает `codelab-agent serve --ws` со сценарием
  /// `integration_test/llm_scripts/[script].json` и журналом сессий в
  /// `[tempDir]/agent-sessions`; только режим `dart`.
  ///
  /// Почему тест запускает агента сам: по WebSocket app не порождает процесс,
  /// а подключается к уже слушающему серверу. Reconnect меняет только
  /// соединение, процесс агента остаётся прежним, поэтому отмену хода при
  /// обрыве решает сам агент (`detachGrace` ноль, change
  /// `cancel-turn-on-ws-disconnect`), а не смерть процесса, как у stdio.
  ///
  /// Как использовать: адрес [E2eWebSocketAgent.endpoint] и
  /// [E2eWebSocketAgent.token] вводятся в поля `transport-field-Endpoint` и
  /// `transport-field-Token`; процесс останавливается в `addTearDown` через
  /// [E2eWebSocketAgent.stop].
  Future<E2eWebSocketAgent> startWebSocketAgent(
    Directory tempDir, {
    required String script,
  }) async {
    if (kind != E2eAgentKind.dart) {
      throw StateError('a WebSocket agent needs CODELAB_E2E_AGENT=dart');
    }
    const bin = String.fromEnvironment('CODELAB_E2E_AGENT_BIN');
    const token = 'e2e-ws-token';
    final process = await Process.start(
      File(bin).absolute.path,
      [
        'serve',
        '--ws',
        '--port',
        '0',
        '--llm-script',
        File('integration_test/llm_scripts/$script.json').absolute.path,
        '--sessions-dir',
        '${tempDir.absolute.path}/agent-sessions',
      ],
      environment: {'CODELAB_AGENT_TOKEN': token},
    );
    unawaited(process.stdout.drain<void>());
    // Порт `--port 0` известен только из строки лога `serve.ws.listening`.
    final port = Completer<int>();
    final stderr = StringBuffer();
    process.stderr.transform(utf8.decoder).listen((chunk) {
      stderr.write(chunk);
      final match = RegExp(
        r'serve\.ws\.listening .*port: (\d+)',
      ).firstMatch(stderr.toString());
      if (match != null && !port.isCompleted) {
        port.complete(int.parse(match.group(1)!));
      }
    });
    final listening = await port.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        process.kill();
        throw StateError('codelab-agent --ws did not listen: $stderr');
      },
    );
    return E2eWebSocketAgent._(process, listening, token);
  }

  /// Флаги бинаря по таблице контракта: режим разрешений даёт тот же
  /// видимый результат, что у scripted-агента (вопрос на `exec`, запись без
  /// вопроса и так далее).
  ///
  /// `withSessionList` хранит журнал сессий в `[tempDir]/agent-sessions`:
  /// без `--sessions-dir` сессии `--llm-script` живут в памяти процесса, и
  /// агент не объявляет `loadSession` (change `add-llm-script-session-store`,
  /// D4). Папка общая для всех запусков теста, поэтому Reconnect и
  /// перезапуск app видят прежние сессии.
  static List<String> _dartFlags(
    CodelabCompatibleStdioAgentMode mode,
    Directory tempDir,
  ) {
    final settings = _modeSettings(mode);
    return [
      if (settings.permissionMode != null) ...[
        '--permission-mode',
        settings.permissionMode!,
      ],
      for (final model in settings.models) ...['--model', model],
      if (settings.sessions) ...[
        '--sessions-dir',
        _noSpaces('${tempDir.absolute.path}/agent-sessions'),
      ],
    ];
  }

  /// Единая таблица режимов сценария для бинаря Dart-агента (флаги) и
  /// встроенного агента (параметры `scriptedEmbeddedAgentOpener`): режим без
  /// сценария падает одинаково — [StateError], а не молча без настроек.
  static _ModeSettings _modeSettings(CodelabCompatibleStdioAgentMode mode) =>
      switch (mode) {
        CodelabCompatibleStdioAgentMode.normal ||
        CodelabCompatibleStdioAgentMode.withPlan ||
        CodelabCompatibleStdioAgentMode.echoesCwd => const _ModeSettings(),
        CodelabCompatibleStdioAgentMode.withConfigOptions =>
          const _ModeSettings(models: ['gpt-5', 'gpt-4']),
        CodelabCompatibleStdioAgentMode.withPermissionRequest ||
        CodelabCompatibleStdioAgentMode.withQueuedPromptDrain ||
        CodelabCompatibleStdioAgentMode.withConcurrentSessions =>
          const _ModeSettings(permissionMode: 'standard'),
        CodelabCompatibleStdioAgentMode.withFsAccess => const _ModeSettings(
          permissionMode: 'accept-edits',
        ),
        CodelabCompatibleStdioAgentMode.withTerminalExecution =>
          const _ModeSettings(permissionMode: 'bypass'),
        CodelabCompatibleStdioAgentMode.withSessionList => const _ModeSettings(
          sessions: true,
        ),
        final other => throw StateError(
          '${other.name} has no Dart agent scenario: tag the test '
          '$scriptedOnly',
        ),
      };

  /// Относительная команда разрешается от `apps/codelab_desktop`: спавн агента
  /// идёт из папки проекта, где относительный путь уже не найдётся. Голое
  /// имя (`dart`) ищется в `PATH` и остаётся как есть.
  static String _absolute(String command) =>
      command.contains('/') ? File(command).absolute.path : command;

  /// Поле `Args` делится по пробелам, путь с пробелом развалится на части.
  static String _noSpaces(String path) {
    if (path.contains(' ')) {
      throw StateError('e2e paths must not contain spaces: $path');
    }
    return path;
  }
}

/// Запуск агента и ожидания теста, которые зависят от агента.
final class E2eLaunch {
  E2eLaunch._({
    required this.command,
    required this.args,
    required this.sessionLabel,
    required this.models,
    required this.rawInputMarker,
    this.embedded = false,
  });

  /// Встроенный агент: вместо команды и аргументов выбирается тип «Embedded
  /// agent» ([enterConnection]).
  final bool embedded;

  /// Поле `transport-field-Command`.
  final String command;

  /// Поле `transport-field-Args`.
  final String args;

  /// Метка новой сессии в списке.
  final Matcher sessionLabel;

  /// Значения и подписи опции `model`, по умолчанию — первая.
  final List<({String value, String name})> models;

  /// Текст, который есть только в сырых аргументах вызова (`rawInput`).
  final String rawInputMarker;

  /// Заполняет форму подключения; диалог подключения должен быть открыт.
  ///
  /// Почему общий шаг: запуск внешнего агента вводится в поля `Command` и
  /// `Args`, а встроенному полей не нужно — достаточно выбрать тип (D9).
  Future<void> enterConnection(WidgetTester tester) async {
    if (embedded) {
      await tester.tap(find.widgetWithText(CodeLabButton, 'Embedded agent'));
      await tester.pumpAndSettle();
      return;
    }
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      command,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Args')),
      args,
    );
  }

  /// Текстовые виджеты, совпавшие с [sessionLabel].
  Finder get sessionLabelFinder => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        sessionLabel.matches(widget.data ?? widget.textSpan?.toPlainText(), {}),
    description: 'session label',
  );
}

/// Процесс `codelab-agent serve --ws`, запущенный тестом
/// ([E2eAgent.startWebSocketAgent]).
final class E2eWebSocketAgent {
  E2eWebSocketAgent._(this._process, this.port, this.token);

  final Process _process;

  /// Порт, который сервер выбрал для `--port 0`.
  final int port;

  /// Bearer-токен сервера: поле `transport-field-Token`.
  final String token;

  /// Поле `transport-field-Endpoint`.
  String get endpoint => 'ws://127.0.0.1:$port/acp';

  /// SIGTERM и ожидание выхода, чтобы процесс не пережил тест.
  Future<void> stop() async {
    _process.kill();
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return _process.exitCode;
      },
    );
  }
}

/// Лог встроенного агента в e2e-тестах не нужен: журнал app и транскрипт
/// проверяются сами.
final class _SilentLogger implements Logger {
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

/// Настройки сценария одного режима: режим разрешений, каталог моделей и
/// журнал сессий (`--sessions-dir` бинаря, change
/// `add-llm-script-session-store`, D4: без него сессии `--llm-script` живут в
/// памяти и агент не объявляет `loadSession`).
final class _ModeSettings {
  const _ModeSettings({
    this.permissionMode,
    this.models = const [],
    this.sessions = false,
  });

  final String? permissionMode;
  final List<String> models;
  final bool sessions;
}

/// Сценарий и настройки встроенного агента для одного режима теста.
///
/// Почему: у встроенного агента нет флагов командной строки, а те же режимы
/// разрешений, моделей и журнала, что у `codelab-agent serve --stdio`
/// (`E2eAgent._dartFlags`), задаются параметрами `scriptedEmbeddedAgentOpener`.
/// Режим без сценария Dart-агента — [StateError]: такой тест помечается
/// `scripted-only` и в этом режиме исключается.
final class _EmbeddedSetup {
  _EmbeddedSetup._({
    required this.llm,
    required this.home,
    required this.permissionMode,
    required this.sessionsDir,
    required this.models,
  });

  factory _EmbeddedSetup.of(
    CodelabCompatibleStdioAgentMode mode,
    Directory tempDir,
  ) {
    // Таблица режимов — общая с бинарём; неизвестный режим падает здесь же.
    final settings = E2eAgent._modeSettings(mode);
    final script = File('integration_test/llm_scripts/${mode.wireName}.json');
    if (!script.existsSync()) {
      throw StateError(
        '${mode.name} has no model script ${script.path}: tag the test '
        '$scriptedOnly',
      );
    }
    final json = jsonDecode(script.readAsStringSync()) as Map<String, Object?>;
    return _EmbeddedSetup._(
      llm: json['llm']! as Map<String, Object?>,
      // Путь вводится не в форму, а передаётся открывателю: пробелы не мешают.
      home: '${tempDir.absolute.path}/codelab-home',
      permissionMode: settings.permissionMode,
      sessionsDir: settings.sessions
          ? '${tempDir.absolute.path}/agent-sessions'
          : null,
      models: [for (final model in settings.models) 'scripted/$model'],
    );
  }

  final Map<String, Object?> llm;
  final String home;
  final String? permissionMode;
  final String? sessionsDir;
  final List<String> models;
}
