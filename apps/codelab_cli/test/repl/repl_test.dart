// REPL: ход, очередь, отмена и выход (tasks 6.5; spec codelab-cli «Редактор
// строки и клавиши», «Очередь промптов в REPL», «Рендер хода в REPL»;
// design.md change `add-codelab-cli`, D5, D7).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart';

const _enter = [0x0d];
const _esc = [0x1b];
const _ctrlC = [0x03];
const _ctrlD = [0x04];
const _up = [0x1b, 0x5b, 0x41];

/// История в памяти вместо `cli_history`.
final class _MemoryHistoryStore implements HistoryStore {
  _MemoryHistoryStore([this.entries = const []]);

  List<String> entries;

  @override
  Future<List<String>> load() async => entries;

  @override
  Future<void> save(List<String> entries) async => this.entries = entries;
}

void main() {
  late FakeAgent agent;
  late FakeTerminal terminal;
  late _MemoryHistoryStore history;

  setUp(() {
    agent = FakeAgent();
    terminal = FakeTerminal();
    history = _MemoryHistoryStore();
  });
  tearDown(() => agent.dispose());

  Repl repl({
    String? firstMessage,
    OutputSurface surface = OutputSurface.ansi,
  }) => Repl(
    workspace: agent.workspace,
    terminal: terminal,
    profile: FakeAgent.profile,
    cwd: '/work',
    history: history,
    surface: surface,
    firstMessage: firstMessage,
    escapeTimeout: const Duration(milliseconds: 10),
    cancelGrace: const Duration(milliseconds: 200),
  );

  String promptText(JsonRpcRequest request) {
    final prompt = (request.params! as Map<String, Object?>)['prompt']! as List;
    return (prompt.single as Map<String, Object?>)['text']! as String;
  }

  /// Запускает REPL и принимает его новую сессию `s1`.
  Future<Future<int>> started({String? firstMessage}) async {
    final exit = repl(firstMessage: firstMessage).run();
    await agent.acceptNewSession('s1');
    await eventually(() => terminal.rawEnabled, reason: 'raw mode');
    return exit;
  }

  test('the first message from the arguments is sent at once', () async {
    final exit = await started(firstMessage: 'hello');

    final prompt = await agent.next(sessionPromptMethod);
    expect(promptText(prompt), 'hello');
    agent
      ..chunk('s1', 'Hi ')
      ..chunk('s1', 'there')
      ..respond(prompt, {'stopReason': 'end_turn'});
    await eventually(() => terminal.text.contains('Hi there'));

    terminal.press(_ctrlD);
    expect(await exit, 0);
  });

  test('Enter sends the typed line and the answer streams', () async {
    final exit = await started();

    terminal
      ..type('hi')
      ..press(_enter);
    final prompt = await agent.next(sessionPromptMethod);
    expect(promptText(prompt), 'hi');
    agent
      ..chunk('s1', 'one ')
      ..chunk('s1', 'two')
      ..respond(prompt, {'stopReason': 'end_turn'});
    await eventually(() => terminal.text.contains('one two'));
    expect('one two'.allMatches(terminal.text), hasLength(1));

    terminal.press(_ctrlD);
    expect(await exit, 0);
  });

  test('Enter during a turn queues the prompt, and the queue drains after '
      'the turn', () async {
    final exit = await started(firstMessage: 'first');
    final first = await agent.next(sessionPromptMethod);

    terminal
      ..type('second')
      ..press(_enter);
    await eventually(() => terminal.text.contains('queued: 1'));

    agent.respond(first, {'stopReason': 'end_turn'});
    final second = await agent.next(sessionPromptMethod);
    expect(promptText(second), 'second');
    agent.respond(second, {'stopReason': 'end_turn'});

    terminal.press(_ctrlD);
    expect(await exit, 0);
  });

  for (final (name, key) in [('Esc', _esc), ('Ctrl+C', _ctrlC)]) {
    test('$name during a turn cancels it, and input is open again', () async {
      final exit = await started(firstMessage: 'slow');
      final prompt = await agent.next(sessionPromptMethod);

      terminal.press(key);
      await agent.nextNotification(sessionCancelMethod);
      agent.respond(prompt, {'stopReason': 'cancelled'});

      terminal
        ..type('next')
        ..press(_enter);
      expect(promptText(await agent.next(sessionPromptMethod)), 'next');

      unawaited(terminal.closeInput());
      expect(await exit, 0);
    });
  }

  test('Esc outside a turn clears the line', () async {
    final exit = await started();

    terminal
      ..type('abc')
      ..press(_esc);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    terminal
      ..type('x')
      ..press(_enter);

    expect(promptText(await agent.next(sessionPromptMethod)), 'x');
    unawaited(terminal.closeInput());
    await exit;
  });

  test('Ctrl+C twice within a second exits with 0 and restores the '
      'terminal', () async {
    final exit = await started();

    terminal
      ..type('draft')
      ..press(_ctrlC)
      ..press(_ctrlC);

    expect(await exit, 0);
    expect(terminal.rawEnabled, isFalse);
    expect(terminal.restoreCount, greaterThanOrEqualTo(1));
    expect(
      agent.transport.sentMessages.whereType<JsonRpcRequest>().map(
        (r) => r.method,
      ),
      isNot(contains(sessionPromptMethod)),
    );
  });

  test('Ctrl+D on a non-empty line does not exit', () async {
    final exit = await started();

    terminal
      ..type('x')
      ..press(_ctrlD)
      ..press(_enter);
    expect(promptText(await agent.next(sessionPromptMethod)), 'x');

    unawaited(terminal.closeInput());
    await exit;
  });

  test('the history is saved and comes back with Up', () async {
    history = _MemoryHistoryStore(['earlier']);
    final exit = await started();

    terminal
      ..press(_up)
      ..press(_enter);
    final prompt = await agent.next(sessionPromptMethod);
    expect(promptText(prompt), 'earlier');
    agent.respond(prompt, {'stopReason': 'end_turn'});

    terminal
      ..type('later')
      ..press(_enter);
    agent.respond(await agent.next(sessionPromptMethod), {
      'stopReason': 'end_turn',
    });

    terminal.press(_ctrlD);
    await exit;
    expect(history.entries, ['earlier', 'later']);
  });

  test('a failed connection is 1 with the reason', () async {
    await agent.dispose();
    agent = FakeAgent(openError: StateError('no such agent'));

    final code = await repl().run();

    expect(code, 1);
    expect(terminal.errorText, contains('no such agent'));
    expect(terminal.rawEnabled, isFalse);
  });

  test('interrupt() cancels the turn and gives the signal code', () async {
    final r = repl(firstMessage: 'slow');
    final exit = r.run();
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);

    final cancel = agent.nextNotification(sessionCancelMethod);
    unawaited(r.interrupt(143));
    await cancel;
    agent.respond(prompt, {'stopReason': 'cancelled'});

    expect(await exit, 143);
    expect(terminal.rawEnabled, isFalse);
  });

  group('without a terminal', () {
    setUp(() => terminal = FakeTerminal(hasTerminal: false));

    test('lines are read one by one without raw mode, and the end of input '
        'exits after the turns', () async {
      final exit = repl(surface: OutputSurface.raw).run();
      await agent.acceptNewSession('s1');

      terminal.type('one\ntwo\n');
      unawaited(terminal.closeInput());
      final first = await agent.next(sessionPromptMethod);
      expect(promptText(first), 'one');
      agent
        ..chunk('s1', 'A1')
        ..respond(first, {'stopReason': 'end_turn'});
      final second = await agent.next(sessionPromptMethod);
      expect(promptText(second), 'two');
      agent
        ..chunk('s1', 'A2')
        ..respond(second, {'stopReason': 'end_turn'});

      expect(await exit, 0);
      expect(terminal.rawEnabled, isFalse);
      expect(terminal.text, contains('A1'));
      expect(terminal.text, contains('A2'));
      expect(terminal.text, isNot(contains('\x1b')));
    });
  });
}
