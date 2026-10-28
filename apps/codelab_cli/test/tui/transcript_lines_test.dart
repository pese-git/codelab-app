// Строки транскрипта TUI (tasks 2.1 change `add-cli-tui`; spec codelab-tui
// «Кадр TUI»; §12.2.11, TUI-6, TUI-11; design.md, D6).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

SessionView _view(List<TranscriptItem> items) =>
    SessionView(revision: 1, status: SessionStatusView.idle, transcript: items);

String _plain(String line) => line.replaceAll(RegExp('\x1b\\[[0-9;]*m'), '');

void main() {
  late TranscriptLayout layout;

  setUp(() => layout = TranscriptLayout());

  List<String> lines(
    List<TranscriptItem> items, {
    int width = 40,
    ThoughtsMode thoughts = ThoughtsMode.dim,
    List<TuiNote> notes = const [],
  }) => layout
      .lines(_view(items), notes: notes, width: width, thoughts: thoughts)
      .map(_plain)
      .toList();

  test('the user prompt, the answer and a notice', () {
    expect(
      lines(const [
        TranscriptItem.user(id: 'u1', text: 'hi\nthere'),
        TranscriptItem.agentText(id: 'a1', text: 'Hello'),
        TranscriptItem.notice(
          id: 'n1',
          kind: NoticeKind.emptyTurn,
          text: 'empty',
        ),
      ]),
      ['> hi', '  there', 'Hello', 'note: empty'],
    );
  });

  test('the answer wraps to the width', () {
    expect(
      lines(const [
        TranscriptItem.agentText(id: 'a1', text: 'one two three four'),
      ], width: 10),
      ['one two', 'three four'],
    );
  });

  test('control characters of the agent are cut out (TUI-11)', () {
    final out = layout.lines(
      _view(const [TranscriptItem.agentText(id: 'a1', text: 'a\x1b[2Jb\x07c')]),
      width: 40,
    );

    // Вырезаются управляющие символы, а не печатаемый хвост
    // последовательности: так же санитизирует REPL (TUI-11).
    expect(out.join().replaceAll(RegExp('\x1b\\[[0-9;]*m'), ''), 'a[2Jbc');
    expect(out.join(), isNot(contains('\x07')));
  });

  test('a tool call is one row without the raw input (TUI-6)', () {
    final out = lines([
      TranscriptItem.toolCall(
        id: 't1',
        toolCallId: const ToolCallId('call-1'),
        title: 'Run tests',
        details: const ToolCallView(
          kind: ToolKind.execute,
          status: ToolCallStatusView.running,
          command: 'make test',
          rawInput: {'command': 'make test', 'secret': 'x'},
        ),
      ),
    ]);

    expect(out, hasLength(1));
    expect(out.single, contains('Run tests'));
    expect(out.single, isNot(contains('secret')));
  });

  test('thoughts follow the /thoughts mode', () {
    const items = [
      TranscriptItem.thought(id: 'th', text: 'pondering'),
      TranscriptItem.agentText(id: 'a1', text: 'answer'),
    ];

    expect(lines(items), ['pondering', 'answer']);
    expect(lines(items, thoughts: ThoughtsMode.collapsed), [
      'thinking…',
      'answer',
    ]);
    expect(lines(items, thoughts: ThoughtsMode.hidden), ['answer']);
  });

  test('client notes go after the transcript item they followed', () {
    expect(
      lines(
        const [
          TranscriptItem.user(id: 'u1', text: 'a'),
          TranscriptItem.agentText(id: 'a1', text: 'b'),
        ],
        notes: const [
          TuiNote(after: 1, text: 'note one'),
          TuiNote(after: 2, text: 'note two'),
        ],
      ),
      ['> a', 'note one', 'b', 'note two'],
    );
  });

  test('the cache recomputes only the changed item', () {
    const first = TranscriptItem.agentText(id: 'a1', text: 'one');
    lines(const [TranscriptItem.user(id: 'u1', text: 'q'), first]);
    final before = layout.computed;

    lines(const [
      TranscriptItem.user(id: 'u1', text: 'q'),
      TranscriptItem.agentText(id: 'a1', text: 'one two'),
    ]);

    expect(layout.computed - before, 1);
  });
}
