// Ядро экрана TUI: сообщения → модель и команды (tasks 2.7 change
// `add-cli-tui`; spec codelab-tui «Композер TUI», «Прокрутка транскрипта
// TUI», «Граница ядра экрана и адаптера»; design.md, D5, D6, D8).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 12);

TuiModel _model({int rows = 20, int columns = 60}) => TuiModel.initial(
  profile: 'default',
  size: TerminalSize(columns: columns, rows: rows),
);

SessionView _view(
  int revision, {
  SessionStatusView status = SessionStatusView.idle,
  List<TranscriptItem> transcript = const [],
}) => SessionView(revision: revision, status: status, transcript: transcript);

(TuiModel, List<TuiCmd>) _run(TuiModel model, List<TuiMsg> messages) {
  final cmds = <TuiCmd>[];
  for (final msg in messages) {
    final (next, out) = reduce(model, msg);
    model = next;
    cmds.addAll(out);
  }
  return (model, cmds);
}

KeyMsg _key(Key key, [DateTime? at]) => KeyMsg(SpecialKey(key), at: at ?? _t0);
KeyMsg _text(String text) => KeyMsg(TextKey(text), at: _t0);

List<TranscriptItem> _lines(int count) => [
  for (var i = 0; i < count; i++)
    TranscriptItem.user(id: 'u$i', text: 'line $i'),
];

void main() {
  test('Enter sends the prompt and saves the history', () {
    final (model, cmds) = _run(_model(), [_text('hi'), _key(Key.enter)]);

    expect(cmds, [
      const SaveHistoryCmd(['hi']),
      const SubmitCmd('hi'),
    ]);
    expect(model.composer.isEmpty, isTrue);
  });

  test('during a turn Enter still sends: the kit queues it', () {
    final (_, cmds) = _run(_model(), [
      SessionViewMsg(_view(1, status: SessionStatusView.running), at: _t0),
      _text('next'),
      _key(Key.enter),
    ]);

    expect(cmds.whereType<SubmitCmd>().single.text, 'next');
  });

  test('a slash line is a command, not a prompt', () {
    final (_, cmds) = _run(_model(), [_text('/mode plan'), _key(Key.enter)]);

    expect(cmds.last, const RunCommandCmd('/mode plan'));
  });

  test('Shift+Enter and Alt+Enter insert a new line', () {
    final (model, cmds) = _run(_model(), [
      _text('a'),
      _key(Key.shiftEnter),
      _text('b'),
      _key(Key.altEnter),
      _text('c'),
    ]);

    expect(model.composer.text, 'a\nb\nc');
    expect(cmds, isEmpty);
  });

  test('a paste never submits (TUI-3)', () {
    final (model, cmds) = _run(_model(), [const PasteMsg('one\ntwo\n')]);

    expect(model.composer.text, 'one\ntwo\n');
    expect(cmds, isEmpty);
  });

  test('Esc and Ctrl+C during a turn cancel it', () {
    final running = _run(_model(), [
      SessionViewMsg(_view(1, status: SessionStatusView.running), at: _t0),
    ]).$1;

    expect(reduce(running, _key(Key.escape)).$2, [const CancelTurnCmd()]);
    expect(reduce(running, _key(Key.ctrlC)).$2, [const CancelTurnCmd()]);
  });

  test('without a turn Esc clears, Ctrl+C twice within 1 s exits', () {
    final (cleared, _) = _run(_model(), [_text('abc'), _key(Key.escape)]);
    expect(cleared.composer.isEmpty, isTrue);

    final (_, twice) = _run(_model(), [
      _key(Key.ctrlC, _t0),
      _key(Key.ctrlC, _t0.add(const Duration(milliseconds: 500))),
    ]);
    expect(twice, [const QuitCmd(0)]);

    final (_, slow) = _run(_model(), [
      _key(Key.ctrlC, _t0),
      _key(Key.ctrlC, _t0.add(const Duration(seconds: 2))),
    ]);
    expect(slow, isEmpty);
  });

  test('Ctrl+D exits only on an empty composer', () {
    expect(reduce(_model(), _key(Key.ctrlD)).$2, [const QuitCmd(0)]);
    expect(_run(_model(), [_text('x'), _key(Key.ctrlD)]).$2, isEmpty);
  });

  test('an older revision is dropped', () {
    final (model, _) = _run(_model(), [
      SessionViewMsg(_view(5, transcript: _lines(2)), at: _t0),
      SessionViewMsg(_view(4, transcript: _lines(1)), at: _t0),
    ]);

    expect(model.session!.revision, 5);
  });

  test('the turn start comes from the message time', () {
    final later = _t0.add(const Duration(seconds: 3));
    final (model, _) = _run(_model(), [
      SessionViewMsg(_view(1, status: SessionStatusView.running), at: _t0),
      SessionViewMsg(_view(2, status: SessionStatusView.running), at: later),
    ]);
    expect(model.turnStartedAt, _t0);

    final (idle, _) = _run(model, [SessionViewMsg(_view(3), at: later)]);
    expect(idle.turnStartedAt, isNull);
  });

  test('PgUp holds the window, new lines are counted, End follows again', () {
    var (model, _) = _run(_model(rows: 10), [
      SessionViewMsg(_view(1, transcript: _lines(30)), at: _t0),
      _key(Key.pageUp),
    ]);
    expect(model.scroll.follow, isFalse);

    (model, _) = _run(model, [
      SessionViewMsg(_view(2, transcript: _lines(35)), at: _t0),
    ]);
    expect(model.scroll.follow, isFalse, reason: 'deltas do not follow');
    expect(newSinceHold(model), 5);

    (model, _) = _run(model, [_key(Key.end)]);
    expect(model.scroll.follow, isTrue);
  });

  test('sending a prompt follows again', () {
    final (model, _) = _run(_model(rows: 10), [
      SessionViewMsg(_view(1, transcript: _lines(30)), at: _t0),
      _key(Key.pageUp),
      _text('go'),
      _key(Key.enter),
    ]);

    expect(model.scroll.follow, isTrue);
  });

  test('PgDn down to the bottom follows again', () {
    var (model, _) = _run(_model(rows: 10), [
      SessionViewMsg(_view(1, transcript: _lines(30)), at: _t0),
      _key(Key.pageUp),
    ]);
    for (var i = 0; i < 5 && !model.scroll.follow; i++) {
      (model, _) = _run(model, [_key(Key.pageDown)]);
    }

    expect(model.scroll.follow, isTrue);
  });

  test('a note goes into the transcript', () {
    final (model, _) = _run(_model(), [
      SessionViewMsg(_view(1, transcript: _lines(2)), at: _t0),
      const NoteMsg('Unknown command /x'),
    ]);

    expect(
      model.notes.single,
      const TuiNote(after: 2, text: 'Unknown command /x'),
    );
  });

  test('resize changes the size', () {
    final (model, _) = _run(_model(), [
      const ResizeMsg(TerminalSize(columns: 120, rows: 40)),
    ]);

    expect(model.size, const TerminalSize(columns: 120, rows: 40));
  });
}
