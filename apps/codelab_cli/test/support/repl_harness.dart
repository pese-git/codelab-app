import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import 'fake_agent.dart';
import 'fake_terminal.dart';

/// REPL на [FakeAgent] и [FakeTerminal] для тестов команд и одобрений.
///
/// Почему: каждой клиентской команде нужен запущенный REPL с открытой
/// сессией; обвязка убирает повтор из файлов `test/repl/commands/`.
///
/// Как использовать: `final repl = ReplHarness(); await repl.start();`, затем
/// [line] вводит строку с Enter, [waitText] ждёт вывод, [exit] — Ctrl+D и
/// код выхода. В `tearDown` — [dispose].
final class ReplHarness {
  ReplHarness({FakeAgent? agent, this.profiles = const {}})
    : agent = agent ?? FakeAgent();

  FakeAgent agent;
  final terminal = FakeTerminal();

  /// Профили для `/profile <id>`.
  final Map<String, ConnectionProfile> profiles;

  late Future<int> _exit;

  /// Длина вывода до последней команды: [waitText] ищет после неё.
  var _mark = 0;

  String get output => terminal.text;

  /// Вывод после последнего [line].
  String get lastOutput => terminal.text.substring(_mark);

  /// Запускает REPL; агент принимает новую сессию [sessionId] с опциями
  /// [configOptions], если [acceptSession].
  Future<void> start({
    String sessionId = 's1',
    List<Map<String, Object?>>? configOptions,
    bool acceptSession = true,
  }) async {
    _exit = Repl(
      workspace: agent.workspace,
      terminal: terminal,
      profile: FakeAgent.profile,
      cwd: '/work',
      history: _NoHistory(),
      escapeTimeout: const Duration(milliseconds: 10),
      cancelGrace: const Duration(milliseconds: 200),
      resolveProfile: (id) async =>
          profiles[id] ??
          (throw UsageError(
            'Unknown agent profile "$id". Run "codelab profiles list".',
          )),
    ).run();
    if (acceptSession) {
      await agent.acceptNewSession(sessionId, configOptions: configOptions);
    }
    await eventually(() => terminal.rawEnabled, reason: 'raw mode');
  }

  /// Вводит [text] и нажимает Enter.
  void line(String text) {
    _mark = terminal.text.length;
    terminal
      ..type(text)
      ..press(const [0x0d]);
  }

  void press(List<int> bytes) => terminal.press(bytes);

  void type(String text) {
    _mark = terminal.text.length;
    terminal.type(text);
  }

  /// Ждёт [text] в выводе после последнего [line].
  Future<void> waitText(String text) => eventually(
    () => lastOutput.contains(text),
    reason: 'no "$text" in:\n$output',
  );

  /// Методы запросов, которые клиент отправил агенту.
  List<String> get sentMethods => [
    for (final message in agent.transport.sentMessages)
      if (message is JsonRpcRequest) message.method,
  ];

  /// Ctrl+D на пустой строке и код выхода.
  Future<int> exit() {
    terminal.press(const [0x04]);
    return _exit;
  }

  Future<int> get exitCode => _exit;

  Future<void> dispose() => agent.dispose();
}

/// Ответ агента на `session/prompt` с текстом [text] и `end_turn`.
Future<void> answerPrompt(
  FakeAgent agent,
  String sessionId,
  String text,
) async {
  final prompt = await agent.next(sessionPromptMethod);
  agent
    ..chunk(sessionId, text)
    ..respond(prompt, {'stopReason': 'end_turn'});
}

/// Текст промпта запроса `session/prompt`.
String promptTextOf(JsonRpcRequest request) {
  final prompt = (request.params! as Map<String, Object?>)['prompt']! as List;
  return (prompt.single as Map<String, Object?>)['text']! as String;
}

final class _NoHistory implements HistoryStore {
  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> entries) async {}
}
