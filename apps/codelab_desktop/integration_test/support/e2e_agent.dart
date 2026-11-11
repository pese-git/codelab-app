import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, ProfileSecrets, parseShellWords;
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileProfileStore;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/client_profile_secrets.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/connection_environment.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
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
/// mode: …)` сохраняет профиль агента в `profiles.json` временного
/// `CODELAB_HOME` этого теста, а `launch.connect(tester, shellCubit)` выбирает
/// его на странице «Connection» (design.md change `add-app-settings-shell`,
/// D6, D7; форма подключения и диалог удалены). Режим без сценария
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

  /// Режим сценария для теста встроенной команды `compact`.
  ///
  /// Почему: scripted-агент объявляет `compact` только в режиме
  /// `withAvailableCommands`; Dart-агент и встроенный объявляют её сами
  /// (capability `agent-slash-commands`), им хватает обычного сценария
  /// (design.md change `add-agent-builtin-slash-commands`, D9, tasks 3.2).
  CodelabCompatibleStdioAgentMode get compactMode => isScripted
      ? CodelabCompatibleStdioAgentMode.withAvailableCommands
      : CodelabCompatibleStdioAgentMode.normal;

  /// Режим сценария для теста markdown в ленте (change `add-desktop-markdown`,
  /// задача 5.1).
  ///
  /// Почему один режим для всех агентов: scripted-агент в режиме `withMarkdownReply`
  /// отвечает `echo: <промпт>`, а Dart-агент и встроенный отвечают одним и тем
  /// же текстом из `llm_scripts/with_markdown_reply.json` (тот же markdown, что
  /// [markdownPrompt]); тест не зависит от того, чей это ответ.
  CodelabCompatibleStdioAgentMode get markdownMode =>
      CodelabCompatibleStdioAgentMode.withMarkdownReply;

  /// Промпт, который scripted-агент возвращает как ответ; для остальных
  /// агентов ответ задаёт сценарий модели с тем же текстом.
  static const markdownPrompt = '''Here is the report:

# Release notes

- first item
- second item

| Name | Value |
|---|---|
| alpha | 1 |

```dart
void main() {
  print('hi');
}
```

![](https://x.example/y.png)''';

  /// Ответ агента на `/compact` в новой сессии.
  ///
  /// Почему различается: scripted-агент отвечает отчётом о сжатии, а у
  /// Dart-агента история новой сессии пуста, и ответ — `Nothing to compact.`
  /// (Q10, Q11 (а) design.md). Тест `command_palette_flow_test` берёт ожидание
  /// отсюда.
  String get compactReply =>
      isScripted ? 'Compacted the conversation.' : 'Nothing to compact.';

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

  /// Пропустить тест, который проверяет запуск дочернего stdio-процесса
  /// агента (записи `Starting stdio ACP agent:` / `Stdio ACP agent started:`).
  ///
  /// Причина: встроенный агент работает в процессе app и подключается без
  /// дочернего процесса, поэтому этих записей у него нет; своё подключение он
  /// пишет как `Starting embedded ACP agent:` (design.md change
  /// `add-embedded-agent-mode`, D8, D10).
  bool get skipStdioProcess => kind == E2eAgentKind.embedded;

  /// Суффикс описания stdio-теста: при пропуске причина видна в выводе
  /// раннера.
  String get skipStdioProcessNote => skipStdioProcess
      ? ' [skipped: the embedded agent starts no stdio child process]'
      : '';

  /// Пропустить тесты, которым нужен процесс `codelab-agent serve --ws`:
  /// есть только в режиме `dart`; у scripted-агента сервера WebSocket нет, у
  /// встроенного — тоже.
  bool get skipWebSocketAgent => kind != E2eAgentKind.dart;

  /// Токен WebSocket-агента, которого запускает [startWebSocketAgent]: app
  /// читает его из этой переменной окружения по ссылке `env:` профиля (D13).
  static const webSocketTokenVariable = 'CODELAB_E2E_WS_TOKEN';

  /// Временный `CODELAB_HOME` теста: в нём `profiles.json` с профилем агента.
  /// Создаётся лениво (тест может вызвать [launch] раньше [bootstrap]) и
  /// удаляется в конце теста; перезапуск app внутри теста видит те же профили.
  Directory? _home;

  Directory get _homeDirectory {
    final existing = _home;
    if (existing != null) {
      return existing;
    }
    final created = Directory.systemTemp.createTempSync('codelab_app_home_');
    _home = created;
    addTearDown(() {
      _home = null;
      if (created.existsSync()) {
        created.deleteSync(recursive: true);
      }
    });
    return created;
  }

  /// Путь к `profiles.json` временного `CODELAB_HOME`: тесты диалога
  /// «Add connection profile» проверяют, что записал app (общий файл с CLI).
  String get profilesPath => '${_homeDirectory.path}/profiles.json';

  /// Сохраняет [profile] в `profiles.json` временного `CODELAB_HOME`.
  Future<void> saveProfile(ConnectionProfile profile) => JsonFileProfileStore(
    '${_homeDirectory.path}/profiles.json',
  ).save(profile);

  /// Данные следующего подключения встроенного агента: их задаёт [launch], а
  /// открыватель scope читает в момент подключения. Поэтому порядок
  /// `bootstrap()` и `launch()` любой, а перезапуск app внутри теста
  /// (повторный `bootstrap()`) подключается с теми же данными. Сбрасывает их
  /// `addTearDown`, который регистрирует [launch]: данные прошлого теста не
  /// попадают в подключение нового.
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
  Widget bootstrap({ProfileSecrets? profileSecrets}) =>
      _bootstrap(profileSecrets);

  /// Окружение app теста: временный `CODELAB_HOME` и токен WebSocket-агента.
  Map<String, String> get _environment => {
    ...Platform.environment,
    'CODELAB_HOME': _homeDirectory.path,
    webSocketTokenVariable: E2eWebSocketAgent.token,
  };

  /// Открывает хранилище секретов `file` во временном `CODELAB_HOME` теста
  /// (design.md change `add-provider-setup-ui`, D3, D4; задача 1.15).
  ///
  /// Почему тест включает `file` сам: пользовательский слой `secrets.backend`
  /// app не пишет (D3), а бэкенд по умолчанию — `env`, только для чтения.
  /// Настоящие `~/.codelab` и хранилище ОС не затрагиваются. Результат
  /// передаётся в `bootstrap(profileSecrets:)`; повторный вызов даёт ещё одно
  /// чтение того же хранилища — так тест проверяет, что записал app.
  Future<ProfileSecrets> openFileSecrets() async {
    final home = _homeDirectory.path;
    // Бэкенд `file` требует закрытый от группы `$CODELAB_HOME`.
    await Process.run('/bin/chmod', ['700', home]);
    final config = File('$home/config.yaml');
    if (!config.existsSync()) {
      config.writeAsStringSync('secrets:\n  backend: file\n');
    }
    return openProfileSecrets(
      environment: ConnectionEnvironment.of(_environment),
      logger: CodeLabEmbeddedLogger(),
    );
  }

  /// Один корень для всех режимов: окружение app задаёт `CODELAB_HOME` с
  /// профилями теста и токен WebSocket-агента (D7, D15); открыватель со
  /// сценарием нужен только встроенному режиму (D9).
  Widget _bootstrap(ProfileSecrets? profileSecrets) => CodeLabBootstrap(
    scope: createCodeLabRootScope(
      embeddedOpener: kind == E2eAgentKind.embedded ? _embeddedOpener : null,
      environment: _environment,
      profileSecrets: profileSecrets,
    ),
    child: const CodeLabApp(),
  );

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
        return await _launched(
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
        return await _launched(
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
        // Сброс в конце теста, а не в `bootstrap()`: тест вправе вызвать
        // `launch()` до `bootstrap()` и перезапустить app внутри себя
        // (session_list_load_flow_test).
        addTearDown(() => _embeddedSetup = null);
        return E2eLaunch._(
          command: '',
          args: '',
          profileId: 'embedded',
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

  /// Профиль внешнего stdio-агента теста: пишется в `profiles.json` и
  /// выбирается на странице «Connection» ([E2eLaunch.connect]).
  Future<E2eLaunch> _launched({
    required String command,
    required String args,
    required Matcher sessionLabel,
    required List<({String value, String name})> models,
    required String rawInputMarker,
  }) async {
    await saveProfile(
      ConnectionProfile.stdio(
        id: E2eLaunch.profileIdOfExternal,
        label: 'E2E agent',
        command: command,
        args: parseShellWords(args),
        runInProjectDirectory: true,
      ),
    );
    return E2eLaunch._(
      command: command,
      args: args,
      profileId: E2eLaunch.profileIdOfExternal,
      sessionLabel: sessionLabel,
      models: models,
      rawInputMarker: rawInputMarker,
    );
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
  /// Как использовать: агент получает профиль в `profiles.json`
  /// ([E2eWebSocketAgent.connect] выбирает его на странице «Connection»;
  /// токен app читает из переменной окружения [webSocketTokenVariable]);
  /// процесс останавливается в `addTearDown` через [E2eWebSocketAgent.stop].
  Future<E2eWebSocketAgent> startWebSocketAgent(
    Directory tempDir, {
    required String script,
  }) async {
    if (kind != E2eAgentKind.dart) {
      throw StateError('a WebSocket agent needs CODELAB_E2E_AGENT=dart');
    }
    const bin = String.fromEnvironment('CODELAB_E2E_AGENT_BIN');
    const token = E2eWebSocketAgent.token;
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
    final agent = E2eWebSocketAgent._(process, listening);
    await saveProfile(
      ConnectionProfile.webSocket(
        id: E2eWebSocketAgent.profileId,
        label: 'E2E WebSocket',
        uri: Uri.parse(agent.endpoint),
        tokenRef: 'env:$webSocketTokenVariable',
      ),
    );
    return agent;
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
        CodelabCompatibleStdioAgentMode.withMarkdownReply ||
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
    required this.profileId,
    required this.sessionLabel,
    required this.models,
    required this.rawInputMarker,
    this.embedded = false,
  });

  /// Id профиля внешнего stdio-агента в `profiles.json`.
  static const profileIdOfExternal = 'e2e-agent';

  /// Встроенный агент: профиля в файле нет, на странице «Connection» нажимается
  /// «Connect» в строке «Embedded agent».
  final bool embedded;

  /// Команда профиля.
  final String command;

  /// Аргументы профиля одной строкой (разбираются как в shell).
  final String args;

  /// Id строки страницы «Connection», которую выбирает [connect].
  final String profileId;

  /// Метка новой сессии в списке.
  final Matcher sessionLabel;

  /// Значения и подписи опции `model`, по умолчанию — первая.
  final List<({String value, String name})> models;

  /// Текст, который есть только в сырых аргументах вызова (`rawInput`).
  final String rawInputMarker;

  /// Подключается к агенту теста: открывает «Connection», нажимает «Connect» в
  /// строке профиля, ждёт исхода и возвращается на рабочее место.
  ///
  /// Почему общий шаг: запуск внешнего агента — профиль из `profiles.json`,
  /// встроенного — строка «Embedded agent» (D5, D6). Реальный процесс не
  /// гарантирует кадров для `pumpAndSettle`, поэтому исход читается из
  /// Cubit-а, а не ждётся по кадрам.
  Future<void> connect(WidgetTester tester, CodeLabShellCubit shellCubit) =>
      connectProfileViaSettings(tester, shellCubit, profileId);

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
  E2eWebSocketAgent._(this._process, this.port);

  /// Токен сервера; app получает его из переменной окружения
  /// [E2eAgent.webSocketTokenVariable] по ссылке профиля.
  static const token = 'e2e-ws-token';

  /// Id профиля агента в `profiles.json`.
  static const profileId = 'e2e-ws';

  final Process _process;

  /// Порт, который сервер выбрал для `--port 0`.
  final int port;

  String get endpoint => 'ws://127.0.0.1:$port/acp';

  /// Подключается к агенту строкой его профиля на странице «Connection».
  Future<void> connect(WidgetTester tester, CodeLabShellCubit shellCubit) =>
      connectProfileViaSettings(tester, shellCubit, profileId);

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

/// Выбирает профиль [profileId] на странице «Connection», ждёт исхода
/// подключения и закрывает настройки.
///
/// Почему: профили теперь общий список страницы настроек; единственный способ
/// подключить окно — «Connect» в строке (D5, D6). Ожидание — опросом Cubit-а
/// до 10 секунд, а не `pumpAndSettle`: реальный процесс или сокет не держит
/// кадры.
Future<void> connectProfileViaSettings(
  WidgetTester tester,
  CodeLabShellCubit shellCubit,
  String profileId,
) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('connection-profile-connect-$profileId')),
  );
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while ((shellCubit.state.connectionStatus ==
              CodeLabConnectionStatus.connecting ||
          shellCubit.state.connectionStatus ==
              CodeLabConnectionStatus.reconnecting) &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(CodeLabSettingsNavigation.backKey));
  await tester.pumpAndSettle();
}
