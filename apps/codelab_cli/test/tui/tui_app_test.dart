// Адаптер TUI поверх dart_tui без терминала: `Program` с `withInput`,
// `withOutput`, `withWindowSize` и `withoutSignalHandler` против
// `FakeAgent` (tasks 3.1 change `add-cli-tui`; spec codelab-tui «Запуск
// полноэкранного режима», «Композер TUI», «Вставка в TUI», «Восстановление
// терминала после TUI»; testing-quality «PTY-e2e терминального клиента»;
// design.md, D7, D12, D13).
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:dart_tui/dart_tui.dart' as tea;
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart' show eventually;

final class _Bytes implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  String get text => utf8.decode(bytes, allowMalformed: true);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}
}

final class _NoHistory implements HistoryStore {
  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> entries) async {}
}

String _promptText(JsonRpcRequest request) {
  final prompt = (request.params! as Map<String, Object?>)['prompt']! as List;
  return (prompt.single as Map<String, Object?>)['text']! as String;
}

void main() {
  late FakeAgent agent;
  late StreamController<List<int>> input;
  late _Bytes output;
  late IOSink sink;

  setUp(() {
    agent = FakeAgent();
    input = StreamController<List<int>>();
    output = _Bytes();
    sink = IOSink(output);
  });

  tearDown(() async {
    // Без подписчика `close` не завершается: тест модели `TuiApp` не
    // запускает `Program`.
    unawaited(input.close());
    await agent.dispose();
  });

  TuiRunner runner({String? firstMessage}) => TuiRunner(
    workspace: agent.workspace,
    profile: FakeAgent.profile,
    cwd: '/w',
    history: _NoHistory(),
    firstMessage: firstMessage,
    output: sink,
    errorOutput: StringBuffer(),
    programOptions: [
      tea.withInput(input.stream),
      tea.withOutput(sink),
      tea.withWindowSize(100, 30),
      tea.withoutSignalHandler(),
    ],
  );

  Future<Future<int>> started({String? firstMessage}) async {
    final exit = runner(firstMessage: firstMessage).run();
    await agent.acceptNewSession('s1');
    await eventually(() => output.text.contains('\x1b[?1049h'));
    return exit;
  }

  void type(String text) => input.add(utf8.encode(text));

  test('a prompt streams into the frame and Ctrl+D restores the terminal '
      '(TUI-4)', () async {
    final exit = await started();

    type('hi');
    type('\r');
    final prompt = await agent.next(sessionPromptMethod);
    expect(_promptText(prompt), 'hi');
    agent
      ..chunk('s1', 'Hello ')
      ..chunk('s1', 'there')
      ..respond(prompt, {'stopReason': 'end_turn'});
    await eventually(() => output.text.contains('Hello there'));

    type('\x04');
    expect(await exit, 0);
    final text = output.text;
    expect(text, contains('\x1b[?1049l'));
    expect(text, contains('\x1b[?2004l'));
    expect(text, contains('\x1b[?25h'));
    // После выхода из альтернативного экрана — последний ответ.
    expect(
      text.substring(text.lastIndexOf('\x1b[?1049l')),
      contains('Hello there'),
    );
  });

  test('the first message is sent at once', () async {
    final exit = await started(firstMessage: 'hello');

    final prompt = await agent.next(sessionPromptMethod);
    expect(_promptText(prompt), 'hello');
    agent.respond(prompt, {'stopReason': 'end_turn'});

    type('\x04');
    expect(await exit, 0);
  });

  test('a bracketed paste with new lines is not sent (TUI-3)', () async {
    final exit = await started();

    type('\x1b[200~one\ntwo\x1b[201~');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      agent.transport.sentMessages.where(
        (m) => encodeJsonRpcMessage(m).contains(sessionPromptMethod),
      ),
      isEmpty,
    );
    type('\r');
    final prompt = await agent.next(sessionPromptMethod);
    expect(_promptText(prompt), 'one\ntwo');
    agent.respond(prompt, {'stopReason': 'end_turn'});

    type('\x04');
    expect(await exit, 0);
  });

  test(
    'Shift+Enter in kitty and modifyOtherKeys forms is a new line',
    () async {
      final exit = await started();

      type('a');
      type('\x1b[13;2u');
      type('b');
      type('\x1b[27;2;13~');
      type('c');
      type('\r');
      final prompt = await agent.next(sessionPromptMethod);
      expect(_promptText(prompt), 'a\nb\nc');
      agent.respond(prompt, {'stopReason': 'end_turn'});

      type('\x04');
      expect(await exit, 0);
    },
  );

  test(
    'the spinner and the hint line are drawn by dart_tui components',
    () async {
      final exit = await started(firstMessage: 'slow');
      final prompt = await agent.next(sessionPromptMethod);

      await eventually(
        () => RegExp('[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]').hasMatch(output.text),
        reason: 'the spinner during the turn',
      );
      expect(output.text, contains('Shift+Enter'));
      agent.respond(prompt, {'stopReason': 'end_turn'});

      type('\x04');
      expect(await exit, 0);
    },
  );

  test('a stop signal cancels the turn and exits with its code', () async {
    final tui = runner(firstMessage: 'slow');
    final exit = tui.run();
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);

    unawaited(tui.interrupt(143));
    await agent.nextNotification(sessionCancelMethod);
    agent.respond(prompt, {'stopReason': 'cancelled'});

    expect(await exit, 143);
    expect(output.text, contains('\x1b[?1049l'));
  });

  test('three failures of the core in a row quit with 1', () async {
    final quits = <int>[];
    final app = TuiApp(
      model: TuiModel.initial(
        profile: 'p',
        size: const TerminalSize(columns: 80, rows: 24),
      ),
      input: TuiInput(),
      effects: TuiEffects(
        session: () => throw StateError('no session'),
        history: _NoHistory(),
        onQuit: quits.add,
        runCommand: (_) async {},
      ),
      reduce: (model, msg) => throw StateError('broken'),
    );

    tea.Model current = app;
    tea.Cmd? last;
    for (var i = 0; i < 3; i++) {
      final (next, cmd) = current.update(DomainMsg(const NoteMsg('x')));
      current = next;
      last = cmd;
    }

    expect(await last!(), isA<tea.QuitMsg>());
    expect(quits, [1]);
    expect((current as TuiApp).lastError, isA<StateError>());
  });
}
