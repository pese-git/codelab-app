// Строка статуса после хода в REPL (задача 3.7 change `add-usage-extension`;
// spec codelab-cli «Строка статуса после хода в REPL»: «Ход с usage»,
// «Агент без usage», «Отменённый ход», «Сорвавшийся ход», «Промпт в
// очередь», «Вывод в pipe»; design.md, D12, D23 Т5, Q9 (б), Q18 (а)).
//
// Красные тесты: `ReplSession.onOutcome` строки статуса не печатает и метода
// `TerminalRenderer` для неё нет (задача 3.12); тексты строятся функцией
// сегментов поверх `codelab_client_core` (3.0a, 3.11). Файл компилируется;
// падают проверки вывода. «Агент без usage» красный только пока строки нет
// вовсе. Отсутствие строки в headless проверяет
// `test/headless/headless_usage_status_test.dart` (там `ReplSession` не
// используется, проверка зелёная и без доработок); ветку `PromptQueued` —
// `test/repl/repl_session_queued_test.dart`.
//
// Формат строки (spec): `─ <режим> · <модель> · ctx N% · ↑<вход> ↓<выход> ·
// $<стоимость сессии>`; на `ansi` — внутри `ESC[2m … ESC[0m`, на `plain` —
// без SGR, на `raw` не печатается.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart';

const _enter = [0x0d];
const _esc = [0x1b];
const _ctrlD = [0x04];

const _modeOption = {
  'type': 'select',
  'id': 'mode',
  'name': 'Mode',
  'category': 'mode',
  'currentValue': 'ask',
  'options': [
    {'value': 'ask', 'name': 'Ask'},
  ],
};
const _modelOption = {
  'type': 'select',
  'id': 'model',
  'name': 'Model',
  'category': 'model',
  'currentValue': 'a',
  'options': [
    {'value': 'a', 'name': 'Model A'},
  ],
};

/// Строка статуса первого хода: контекст 9 %, вход 18000, выход 500,
/// стоимость сессии 0.04 (числа scripted-агента `withUsage`, 3.5).
const _statusText = '─ ask · a · ctx 9% · ↑18.0k ↓500 · \$0.04';

/// Снимок `_codelab/session/usage` (D2) хода [turn] с накоплением сессии.
Map<String, Object?> _usage({
  required int seq,
  required String trigger,
  int turn = 1,
}) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': trigger,
  'turnId': 'turn-$turn',
  'turn': {
    'steps': 1,
    'tokens': {'input': 18000, 'output': 500, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.04',
  },
  'session': {
    'turns': turn,
    'steps': turn,
    'tokens': {'input': 18000, 'output': 500, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.04',
  },
  'currency': 'USD',
  'context': {'used': 18000, 'size': 200000},
};

const _usageCapabilities = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

/// История в памяти вместо `cli_history`.
final class _MemoryHistoryStore implements HistoryStore {
  List<String> entries = const [];

  @override
  Future<List<String>> load() async => entries;

  @override
  Future<void> save(List<String> entries) async => this.entries = entries;
}

void main() {
  late FakeAgent agent;
  late FakeTerminal terminal;

  tearDown(() => agent.dispose());

  /// REPL на поверхности [surface]; [withUsage] — агент объявил `usage`.
  Future<Future<int>> started({
    OutputSurface surface = OutputSurface.ansi,
    bool withUsage = true,
    String? firstMessage = 'hi',
  }) async {
    agent = FakeAgent(
      capabilities: withUsage ? _usageCapabilities : const AgentCapabilities(),
    );
    terminal = FakeTerminal();
    final exit = Repl(
      workspace: agent.workspace,
      terminal: terminal,
      profile: FakeAgent.profile,
      tokenSource: fakeTokenSource,
      cwd: '/work',
      history: _MemoryHistoryStore(),
      surface: surface,
      firstMessage: firstMessage,
      escapeTimeout: const Duration(milliseconds: 10),
      cancelGrace: const Duration(milliseconds: 200),
    ).run();
    await agent.acceptNewSession(
      's1',
      configOptions: const [_modeOption, _modelOption],
    );
    await eventually(() => terminal.rawEnabled, reason: 'raw mode');
    return exit;
  }

  void sendUsage(int seq, String trigger, {int turn = 1}) =>
      agent.transport.emitInbound(
        JsonRpcMessage.notification(
          method: '_codelab/session/usage',
          params: _usage(seq: seq, trigger: trigger, turn: turn),
        ),
      );

  /// Снимки `step` и `turn` до ответа — порядок D7.
  void usageThenRespond(
    JsonRpcRequest prompt,
    String stopReason, {
    int first = 1,
    int turn = 1,
  }) {
    sendUsage(first, 'step', turn: turn);
    sendUsage(first + 1, 'turn', turn: turn);
    agent.respond(prompt, {'stopReason': stopReason});
  }

  Future<void> quit(Future<int> exit) async {
    terminal.press(_ctrlD);
    expect(await exit, 0);
  }

  test('ansi: после хода приглушённая строка с ctx, токенами и стоимостью '
      '(«Ход с usage»)', () async {
    final exit = await started();
    final prompt = await agent.next(sessionPromptMethod);
    agent.chunk('s1', 'answer text');
    usageThenRespond(prompt, 'end_turn');

    await eventually(() => terminal.text.contains(_statusText));
    expect(terminal.text, contains('\x1b[2m$_statusText'));
    expect(
      terminal.text.indexOf('answer text'),
      lessThan(terminal.text.indexOf(_statusText)),
    );
    await quit(exit);
  });

  test('plain: та же строка без SGR', () async {
    final exit = await started(surface: OutputSurface.plain);
    final prompt = await agent.next(sessionPromptMethod);
    usageThenRespond(prompt, 'end_turn');

    await eventually(() => terminal.text.contains(_statusText));
    expect(terminal.text, isNot(contains('\x1b[2m─')));
    await quit(exit);
  });

  test(
    'raw: строки статуса нет ни в stdout, ни в stderr («Вывод в pipe»)',
    () async {
      final exit = await started(surface: OutputSurface.raw);
      final prompt = await agent.next(sessionPromptMethod);
      agent.chunk('s1', 'answer text');
      usageThenRespond(prompt, 'end_turn');
      await eventually(() => terminal.text.contains('answer text'));
      // Ход завершён: ждём, пока REPL снова примет ввод.
      terminal
        ..type('x')
        ..press(_enter);
      await agent.next(sessionPromptMethod);

      for (final output in [terminal.text, terminal.errorText]) {
        expect(output, isNot(contains('─ ask')));
        expect(output, isNot(contains('ctx ')));
      }
      await quit(exit);
    },
  );

  test('агент без usage: только режим и модель («Агент без usage»)', () async {
    final exit = await started(withUsage: false);
    final prompt = await agent.next(sessionPromptMethod);
    agent.respond(prompt, {'stopReason': 'end_turn'});

    await eventually(() => terminal.text.contains('─ ask · a'));
    // SGR снимаем: `ESC[0m` содержит «0», а проверяется текст строки.
    final line = terminal.text
        .split('\n')
        .firstWhere((l) => l.contains('─ ask · a'))
        .replaceAll(RegExp('\x1b\\[[0-9;]*m'), '');
    for (final mark in ['ctx', r'$', '0', '↑', '↓']) {
      expect(line, isNot(contains(mark)), reason: line);
    }
    await quit(exit);
  });

  test('отменённый ход: строка статуса после строки cancelled', () async {
    final exit = await started();
    final prompt = await agent.next(sessionPromptMethod);

    terminal.press(_esc);
    await agent.nextNotification(sessionCancelMethod);
    usageThenRespond(prompt, 'cancelled');

    await eventually(() => terminal.text.contains(_statusText));
    final text = terminal.text;
    expect(
      text.indexOf(turnCancelled),
      lessThan(text.indexOf(_statusText)),
      reason: 'строка статуса — после `cancelled`',
    );
    await quit(exit);
  });

  test('сорвавшийся ход: строка статуса после строки причины сбоя', () async {
    final exit = await started();
    final prompt = await agent.next(sessionPromptMethod);

    sendUsage(1, 'step');
    sendUsage(2, 'turn');
    agent.fail(prompt, 'boom');

    await eventually(() => terminal.text.contains(_statusText));
    final text = terminal.text;
    expect(text.indexOf('boom'), greaterThanOrEqualTo(0));
    expect(
      text.indexOf('boom'),
      lessThan(text.indexOf(_statusText)),
      reason: 'строка статуса — после причины сбоя',
    );
    await quit(exit);
  });

  test('промпт в очереди: строка не печатается до исхода его хода', () async {
    final exit = await started();
    final first = await agent.next(sessionPromptMethod);

    terminal
      ..type('second')
      ..press(_enter);
    await eventually(() => terminal.text.contains('queued: 1'));
    expect('─ ask'.allMatches(terminal.text), isEmpty);

    usageThenRespond(first, 'end_turn');
    final second = await agent.next(sessionPromptMethod);
    await eventually(() => terminal.text.contains(_statusText));
    expect(_statusText.allMatches(terminal.text), hasLength(1));

    usageThenRespond(second, 'end_turn', first: 3, turn: 2);
    await eventually(() => _statusText.allMatches(terminal.text).length == 2);
    await quit(exit);
  });

  test('ESC и управляющие символы в режиме и модели не доходят до терминала '
      '(sanitize сегментов, ревью итерации 3)', () async {
    agent = FakeAgent(capabilities: _usageCapabilities);
    terminal = FakeTerminal();
    final exit = Repl(
      workspace: agent.workspace,
      terminal: terminal,
      profile: FakeAgent.profile,
      tokenSource: fakeTokenSource,
      cwd: '/work',
      history: _MemoryHistoryStore(),
      surface: OutputSurface.ansi,
      firstMessage: 'hi',
      escapeTimeout: const Duration(milliseconds: 10),
      cancelGrace: const Duration(milliseconds: 200),
    ).run();
    await agent.acceptNewSession(
      's1',
      configOptions: [
        {
          ..._modeOption,
          'currentValue': 'as\x1b[31mk-test-leak-0123456789\x07',
        },
        {..._modelOption, 'currentValue': 'mo\x1b]0;evil\x07del\nx'},
      ],
    );
    await eventually(() => terminal.rawEnabled, reason: 'raw mode');
    final prompt = await agent.next(sessionPromptMethod);
    usageThenRespond(prompt, 'end_turn');

    await eventually(() => terminal.text.contains('─ as'));
    // Берём текст от начала строки статуса: перед ней идёт управление
    // курсором самой строки ввода, а проверяется то, что пришло от агента.
    final text = terminal.text;
    final line = text.substring(text.indexOf('─ as')).split('\n').first;
    expect(line, contains('as[31mk-test-leak-0123456789 · mo]0;evildel x'));
    expect(line, isNot(contains('\x07')));
    // Единственные ESC после начала строки — SGR самого рендера (`ESC[0m`).
    expect(line.replaceAll('\x1b[0m', ''), isNot(contains('\x1b')));
    await quit(exit);
  });
}
