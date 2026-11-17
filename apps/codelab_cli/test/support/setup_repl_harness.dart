import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart';

import 'fake_agent.dart';
import 'fake_terminal.dart';
import 'setup_fakes.dart';

/// Профиль встроенной стороны агента: `resolveSettingsAccess` видит команду
/// `codelab-agent` и отдаёт `EditableSettings` (design.md change
/// `add-provider-setup-ui`, D5, D17).
const editableProfile = StdioProfile(
  id: 'local',
  label: 'Local',
  command: '/opt/bin/codelab-agent',
  args: ['serve', '--stdio'],
  runInProjectDirectory: true,
);

/// То же, но агент не работает в папке проекта: слой `projectLocal`
/// недоступен (D5).
const editableNoProjectProfile = StdioProfile(
  id: 'local-no-project',
  label: 'Local',
  command: '/opt/bin/codelab-agent',
  args: ['serve', '--stdio'],
);

/// Удалённый агент: `RemoteReadOnly` (D5).
final remoteProfile = WebSocketProfile(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('ws://127.0.0.1:9/acp'),
);

/// Чужой stdio-агент `agent` (`FakeAgent.profile`): `NotManaged('agent')`.
const foreignProfile = FakeAgent.profile;

/// Строки только для чтения, §12.4.8, шаг 3.
const remoteReadOnlyText =
    'Provider settings are read-only for a remote agent. Run "codelab '
    'provider add" on the agent host.';

/// Порт `SetupCommands` для тестов REPL: журнал вызовов и ответы теста.
///
/// Почему фейк, а не `run.dart`: порт собирает единственное место с
/// `codelab_setup/io.dart`; команды REPL не знают, откуда берутся данные
/// (D17, «Сверка с кодом»).
final class FakeSetupCommands implements SetupCommands {
  FakeSetupCommands({
    required FakeConfigStore configStore,
    required this.check,
    required this.keys,
    this.codelabHome = '/h',
  }) : store = configStore;

  /// Хранилище, которое порт отдаёт любому доступу.
  final FakeConfigStore store;

  @override
  final String codelabHome;

  final FakeProviderCheck check;
  final FakeProviderKeys keys;

  /// Области, с которыми команды обращались к порту (по порядку).
  final scopeSeen = <SetupScope>[];

  /// Доступы тех же обращений.
  List<EditableSettings> get accessSeen => [
    for (final scope in scopeSeen) scope.access,
  ];

  /// Каталоги, с которыми вызвали `listProviders`.
  final listCalls = <String>[];

  /// Вызовы `removeProvider`.
  final removeCalls = <({String id, String cwd, bool local})>[];

  /// Сколько раз команда просила автомат мастера.
  var flowRequests = 0;

  /// Если задан, `newProviderFlow` ждёт его: команда «в пути», мастер ещё не
  /// открыт.
  Completer<void>? flowGate;

  SetupCommandResult listResult = const SetupCommandResult(
    exitCode: 0,
    stdout: ['Secrets: file', 'gw  openai-compatible'],
  );

  SetupCommandResult removeResult = const SetupCommandResult(
    exitCode: 0,
    stdout: ['Removed providers.gw from /h/config.yaml'],
  );

  @override
  Future<AgentConfigStore> configStore(SetupScope scope) async {
    scopeSeen.add(scope);
    return store;
  }

  @override
  Future<SetupCommandResult> listProviders(SetupScope scope) async {
    scopeSeen.add(scope);
    listCalls.add(scope.cwd);
    return listResult;
  }

  @override
  Future<SetupCommandResult> removeProvider(
    String id,
    SetupScope scope, {
    required bool local,
  }) async {
    scopeSeen.add(scope);
    removeCalls.add((id: id, cwd: scope.cwd, local: local));
    return removeResult;
  }

  @override
  Future<ProviderSetupFlow> newProviderFlow(SetupScope scope) async {
    scopeSeen.add(scope);
    flowRequests++;
    await flowGate?.future;
    return buildWizardFlow(
      check: check,
      keys: keys,
      config: store,
      entry: ProviderWizardEntry.cli,
      cwd: scope.cwd,
    );
  }
}

/// Терминал, который считает подписки на `input`.
///
/// Почему: ввод мастера `/provider add` идёт через ту же подписку `Repl`;
/// вторая подписка на `Terminal.input` запрещена (D15, D16, D17). Поток —
/// single-subscription: повторная подписка бросит `StateError`, а [listens]
/// покажет, сколько раз её пытались создать.
final class CountingTerminal implements Terminal {
  CountingTerminal(this.inner) {
    _input = StreamController<List<int>>(
      onListen: () {
        listens++;
        _subscription = inner.input.listen(
          _input.add,
          onDone: () => unawaited(_input.close()),
        );
      },
      onCancel: () => _subscription?.cancel(),
    );
  }

  final FakeTerminal inner;
  late final StreamController<List<int>> _input;
  StreamSubscription<List<int>>? _subscription;
  var listens = 0;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  StringSink get output => inner.output;

  @override
  StringSink get errorOutput => inner.errorOutput;

  @override
  bool get hasTerminal => inner.hasTerminal;

  @override
  int get columns => inner.columns;

  @override
  void enableRawMode() => inner.enableRawMode();

  @override
  void restore() => inner.restore();
}

/// REPL с портом `SetupCommands` на [FakeAgent] и [CountingTerminal].
///
/// Как использовать: как `ReplHarness` (`test/support/repl_harness.dart`), но
/// REPL получает `setup:`; [line] вводит строку с Enter, [press] и [type] —
/// клавиши, [waitText] ждёт вывод после последнего ввода. Профиль по
/// умолчанию — [editableProfile]. `hasTerminal: false` — построчный ввод.
final class SetupReplHarness {
  SetupReplHarness({
    FakeAgent? agent,
    this.profile = editableProfile,
    bool hasTerminal = true,
    AgentConfigSnapshot? snapshot,
  }) : agent = agent ?? FakeAgent(),
       terminal = FakeTerminal(hasTerminal: hasTerminal),
       check = FakeProviderCheck(),
       keys = FakeProviderKeys() {
    counting = CountingTerminal(terminal);
    store = FakeConfigStore(
      snapshotValue: snapshot ?? snapshotOf(cwd: '/work'),
    );
    setup = FakeSetupCommands(configStore: store, check: check, keys: keys);
  }

  final ConnectionProfile profile;
  final FakeAgent agent;
  final FakeTerminal terminal;
  late final CountingTerminal counting;
  final FakeProviderCheck check;
  final FakeProviderKeys keys;
  late final FakeConfigStore store;
  late final FakeSetupCommands setup;

  late Future<int> _exit;
  var _exited = false;
  var _mark = 0;

  /// REPL уже завершился.
  bool get exited => _exited;

  String get output => terminal.text;

  /// Вывод после последнего [line] или [type].
  String get lastOutput => terminal.text.substring(_mark);

  Future<void> start({String sessionId = 's1'}) async {
    _exit = Repl(
      workspace: agent.workspace,
      terminal: counting,
      profile: profile,
      cwd: '/work',
      history: _NoHistory(),
      escapeTimeout: const Duration(milliseconds: 10),
      cancelGrace: const Duration(milliseconds: 200),
      setup: setup,
    ).run();
    unawaited(_exit.whenComplete(() => _exited = true));
    await agent.acceptNewSession(sessionId);
    if (terminal.hasTerminal) {
      await eventually(() => terminal.rawEnabled, reason: 'raw mode');
    } else {
      await eventually(() => counting.listens > 0, reason: 'line input');
    }
  }

  /// Вводит [text] и Enter.
  void line(String text) {
    _mark = terminal.text.length;
    terminal
      ..type(text)
      ..press(keyEnter);
  }

  void press(List<int> bytes) => terminal.press(bytes);

  void type(String text) => terminal.type(text);

  /// Ждёт [text] в выводе после последнего [line].
  Future<void> waitText(String text) => eventually(
    () => lastOutput.contains(text),
    reason: 'no "$text" in:\n$lastOutput',
  );

  /// Поднимает вывод в целом (мастер печатает вопросы по ходу).
  Future<void> waitAny(String text) => eventually(
    () => output.contains(text),
    reason: 'no "$text" in:\n$output',
  );

  /// Методы запросов, которые клиент отправил агенту.
  List<String> get sentMethods => [
    for (final message in agent.transport.sentMessages)
      if (message is JsonRpcRequest) message.method,
  ];

  Future<int> get exitCode => _exit;

  Future<int> exit() {
    terminal.press(const [0x04]);
    return _exit;
  }

  Future<void> dispose() async {
    if (!_exited && terminal.hasTerminal) {
      terminal.press(const [0x04]);
    }
    await agent.dispose();
  }
}

final class _NoHistory implements HistoryStore {
  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> entries) async {}
}
