// Кадр TUI (tasks 2.7 change `add-cli-tui`; spec codelab-tui «Кадр TUI»,
// «Прокрутка транскрипта TUI», «Строка подсказок и статус-строка TUI»;
// §12.2.11, TUI-9, TUI-11; design.md, D5).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 12);
final _sgr = RegExp('\x1b\\[[0-9;]*m');

String _plain(String line) => line.replaceAll(_sgr, '');

TuiModel _model(
  List<TranscriptItem> transcript, {
  int columns = 100,
  int rows = 30,
  SessionStatusView status = SessionStatusView.idle,
}) {
  final (model, _) = reduce(
    TuiModel.initial(
      profile: 'default',
      size: TerminalSize(columns: columns, rows: rows),
    ),
    SessionViewMsg(
      SessionView(
        revision: 1,
        status: status,
        transcript: transcript,
        configOptions: const [
          ConfigOptionView(
            id: 'mode',
            name: 'Mode',
            category: 'mode',
            currentValue: 'plan',
            values: [ConfigOptionValueView(value: 'plan', name: 'Plan')],
          ),
        ],
      ),
      at: _t0,
    ),
  );
  return model;
}

TuiChrome _chrome({String? spinner}) => TuiChrome(
  spinner: spinner,
  hints: 'Enter send · Shift+Enter new line',
  now: _t0.add(const Duration(seconds: 12)),
);

void main() {
  test('the frame fills the screen, the status line is the last row', () {
    final frame = render(
      _model(const [
        TranscriptItem.user(id: 'u1', text: 'hi'),
        TranscriptItem.agentText(id: 'a1', text: 'Hello there'),
      ]),
      _chrome(),
    );

    expect(frame.lines, hasLength(30));
    final plain = frame.lines.map(_plain).toList();
    expect(plain, containsAllInOrder(['> hi', 'Hello there']));
    expect(plain.last, 'default · plan');
    expect(plain[28], 'Enter send · Shift+Enter new line');
    expect(
      plain.any((l) => l.startsWith('> ') && l.length == 2),
      isTrue,
      reason: 'the empty composer',
    );
  });

  test('every row fits the terminal and ends with a reset (TUI-9)', () {
    final frame = render(
      _model(
        [TranscriptItem.agentText(id: 'a1', text: '${'中' * 80} ${'x' * 150}')],
        columns: 60,
        rows: 10,
      ),
      _chrome(),
    );

    for (final line in frame.lines) {
      expect(displayWidth(line), lessThanOrEqualTo(60), reason: line);
      expect(line, endsWith('\x1b[0m'));
    }
  });

  test('the agent escape sequences do not reach the frame (TUI-11)', () {
    final frame = render(
      _model(const [TranscriptItem.agentText(id: 'a1', text: 'a\x1b[2Jb\x07')]),
      _chrome(),
    );

    final joined = frame.lines.join();
    expect(joined.replaceAll(_sgr, ''), isNot(contains('\x1b')));
    expect(joined, isNot(contains('\x07')));
  });

  test('the hint line is hidden below 15 rows', () {
    final frame = render(_model(const [], rows: 10), _chrome());

    expect(frame.lines, hasLength(10));
    expect(frame.lines.map(_plain), isNot(contains(startsWith('Enter send'))));
  });

  test('during a turn the status line has the spinner and the time', () {
    final frame = render(
      _model(const [], status: SessionStatusView.running),
      _chrome(spinner: '⠋'),
    );

    expect(_plain(frame.lines.last), '⠋ 12s · default · plan');
  });

  test('the cursor stands in the composer after the typed text', () {
    final (model, _) = reduce(
      _model(const []),
      KeyMsg(const TextKey('abc'), at: _t0),
    );
    final frame = render(model, _chrome());

    final (row, column) = frame.cursor!;
    expect(_plain(frame.lines[row]), '> abc');
    expect(column, 5);
  });

  test('holding shows the count of new lines', () {
    var (model, _) = reduce(
      _model([
        for (var i = 0; i < 40; i++)
          TranscriptItem.user(id: 'u$i', text: 'l$i'),
      ]),
      KeyMsg(const SpecialKey(Key.pageUp), at: _t0),
    );
    (model, _) = reduce(
      model,
      SessionViewMsg(
        SessionView(
          revision: 2,
          status: SessionStatusView.idle,
          transcript: [
            for (var i = 0; i < 43; i++)
              TranscriptItem.user(id: 'u$i', text: 'l$i'),
          ],
        ),
        at: _t0,
      ),
    );

    expect(render(model, _chrome()).lines.map(_plain), contains('↓ 3 new'));
  });

  test('a hint line wider than the terminal drops whole entries from the '
      'end', () {
    final frame = render(
      _model(const [], columns: 40),
      TuiChrome(
        hints: 'Enter send · Shift+Enter new line · Esc cancel · Ctrl+D exit',
        now: _t0,
      ),
    );

    expect(
      frame.lines.map(_plain).toList()[frame.lines.length - 2],
      'Enter send · Shift+Enter new line',
    );
  });
}
