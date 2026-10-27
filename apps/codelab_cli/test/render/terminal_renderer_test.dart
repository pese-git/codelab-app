// Рендер ревизий `SessionView` в терминал (tasks 5.5; spec codelab-cli «Рендер
// хода в REPL», «Поверхности вывода»; design.md change `add-codelab-cli`, D6).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _dim = '\x1b[2m';
const _reset = '\x1b[0m';

var _revision = 0;

SessionView _view(
  List<TranscriptItem> transcript, {
  List<PlanEntryView> plan = const [],
}) => SessionView(
  revision: ++_revision,
  status: SessionStatusView.running,
  transcript: transcript,
  plan: plan,
);

ToolCallItem _call(String id, ToolCallStatusView status, {String? command}) =>
    ToolCallItem(
      id: id,
      toolCallId: ToolCallId(id),
      title: 'Run',
      details: ToolCallView(
        kind: ToolKind.execute,
        status: status,
        command: command,
      ),
    );

void main() {
  late StringBuffer out;
  late StringBuffer err;
  late DateTime now;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
    now = DateTime(2026, 10, 27, 12);
  });

  TerminalRenderer renderer({
    OutputSurface surface = OutputSurface.ansi,
    ThoughtsMode thoughts = ThoughtsMode.dim,
  }) => TerminalRenderer(
    surface: surface,
    out: out,
    err: err,
    thoughts: thoughts,
    clock: () => now,
  );

  group('agent text', () {
    test('deltas are printed once, without repeating the printed '
        'part', () {
      final r = renderer();
      r.render(_view([const AgentTextItem(id: 't', text: 'Hel')]));
      r.render(_view([const AgentTextItem(id: 't', text: 'Hello')]));
      r.render(_view([const AgentTextItem(id: 't', text: 'Hello, world')]));

      expect(out.toString(), 'Hello, world');
      expect(r.atLineStart, isFalse);
    });

    test('several updates glued into one revision are printed '
        'together', () {
      final r = renderer();
      r.render(_view([const AgentTextItem(id: 't', text: 'a')]));
      r.render(
        _view([
          const AgentTextItem(id: 't', text: 'abc'),
          _call('c1', ToolCallStatusView.succeeded),
          const AgentTextItem(id: 't2', text: 'done'),
        ]),
      );

      expect(out.toString(), 'abc\n✓ Run\ndone');
    });

    test('an identical revision prints nothing', () {
      final r = renderer();
      final view = _view([const AgentTextItem(id: 't', text: 'x')]);
      r.render(view);
      r.render(view);

      expect(out.toString(), 'x');
    });

    test('finishTurn ends an open line once', () {
      final r = renderer();
      r.render(_view([const AgentTextItem(id: 't', text: 'x')]));
      r.finishTurn();
      r.finishTurn();

      expect(out.toString(), 'x\n');
      expect(r.atLineStart, isTrue);
    });

    test('control characters are removed on ansi', () {
      final r = renderer();
      r.render(_view([const AgentTextItem(id: 't', text: 'a\x1b]0;x\x07b')]));

      expect(out.toString(), 'a]0;xb');
    });

    test('raw prints the answer byte for byte', () {
      final r = renderer(surface: OutputSurface.raw);
      r.render(_view([const AgentTextItem(id: 't', text: '# T\n\n`x`\t')]));

      expect(out.toString(), '# T\n\n`x`\t');
    });
  });

  group('thoughts', () {
    test('dim thoughts come before the answer, each line wrapped in '
        'SGR 2 and a reset', () {
      final r = renderer();
      r.render(_view([const ThoughtItem(id: 'th', text: 'think')]));
      r.render(_view([const ThoughtItem(id: 'th', text: 'think\nmore')]));
      r.render(
        _view([
          const ThoughtItem(id: 'th', text: 'think\nmore'),
          const AgentTextItem(id: 't', text: 'answer'),
        ]),
      );

      expect(
        out.toString(),
        '${_dim}think$_reset\n${_dim}more$_reset\n\nanswer',
      );
    });

    test('plain prints thoughts without SGR', () {
      final r = renderer(surface: OutputSurface.plain);
      r.render(
        _view([
          const ThoughtItem(id: 'th', text: 'think'),
          const AgentTextItem(id: 't', text: 'answer'),
        ]),
      );

      expect(out.toString(), 'think\n\nanswer');
      expect(out.toString(), isNot(contains('\x1b')));
    });

    test('raw prints no thoughts and no ANSI at all', () {
      final r = renderer(surface: OutputSurface.raw);
      r.render(
        _view([
          const ThoughtItem(id: 'th', text: 'think'),
          _call('c1', ToolCallStatusView.succeeded),
          const AgentTextItem(id: 't', text: 'answer'),
        ]),
      );
      r.finishTurn();

      expect(out.toString(), 'answer\n');
      expect(err.toString(), '✓ Run\n');
      expect('$out$err', isNot(contains('\x1b')));
    });

    test('collapsed prints one line with the duration after the '
        'thought', () {
      final r = renderer(thoughts: ThoughtsMode.collapsed);
      r.render(_view([const ThoughtItem(id: 'th', text: 'a')]));
      now = now.add(const Duration(seconds: 3));
      r.render(
        _view([
          const ThoughtItem(id: 'th', text: 'ab'),
          const AgentTextItem(id: 't', text: 'answer'),
        ]),
      );

      expect(out.toString(), '${_dim}thought for 3s$_reset\nanswer');
    });

    test('collapsed closes a thought at the end of the turn', () {
      final r = renderer(thoughts: ThoughtsMode.collapsed);
      r.render(_view([const ThoughtItem(id: 'th', text: 'a')]));
      now = now.add(const Duration(seconds: 1));
      r.finishTurn();

      expect(out.toString(), '${_dim}thought for 1s$_reset\n');
    });

    test('hidden prints nothing for thoughts', () {
      final r = renderer(thoughts: ThoughtsMode.hidden);
      r.render(
        _view([
          const ThoughtItem(id: 'th', text: 'a'),
          const AgentTextItem(id: 't', text: 'answer'),
        ]),
      );

      expect(out.toString(), 'answer');
    });

    test('the mode can change during the process', () {
      final r = renderer();
      r.thoughts = ThoughtsMode.hidden;
      r.render(_view([const ThoughtItem(id: 'th', text: 'a')]));

      expect(out.toString(), isEmpty);
    });
  });

  group('tool calls', () {
    test('a call is printed when it appears and again when it ends, with '
        'the time', () {
      final r = renderer();
      r.render(_view([_call('c1', ToolCallStatusView.running, command: 'ls')]));
      now = now.add(const Duration(milliseconds: 1500));
      r.render(_view([_call('c1', ToolCallStatusView.running, command: 'ls')]));
      r.render(
        _view([_call('c1', ToolCallStatusView.succeeded, command: 'ls')]),
      );

      expect(out.toString(), '… Run ls\n✓ Run ls 1.5s\n');
    });

    test('a call that is final at once is printed once without a '
        'time', () {
      final r = renderer();
      r.render(_view([_call('c1', ToolCallStatusView.failed)]));

      expect(out.toString(), '✗ Run\n');
    });

    test('a tool row starts on a new line after streamed text', () {
      final r = renderer();
      r.render(_view([const AgentTextItem(id: 't', text: 'Let me check')]));
      r.render(
        _view([
          const AgentTextItem(id: 't', text: 'Let me check'),
          _call('c1', ToolCallStatusView.succeeded),
        ]),
      );

      expect(out.toString(), 'Let me check\n✓ Run\n');
    });
  });

  group('plan', () {
    const read = PlanEntryView(
      content: 'Read',
      status: PlanEntryStatus.completed,
      priority: PlanEntryPriority.high,
    );
    const edit = PlanEntryView(
      content: 'Edit',
      status: PlanEntryStatus.inProgress,
      priority: PlanEntryPriority.medium,
    );
    const test_ = PlanEntryView(
      content: 'Test',
      status: PlanEntryStatus.pending,
      priority: PlanEntryPriority.low,
    );

    test('a changed plan is printed as a whole', () {
      final r = renderer();
      r.render(_view(const [], plan: const [edit, test_]));
      r.render(_view(const [], plan: const [edit, test_]));
      r.render(_view(const [], plan: const [read, edit, test_]));

      expect(
        out.toString(),
        'Plan:\n  [~] Edit\n  [ ] Test\n'
        'Plan:\n  [x] Read\n  [~] Edit\n  [ ] Test\n',
      );
    });
  });

  group('notices', () {
    test('a notice is a line with a prefix by kind', () {
      final r = renderer();
      r.render(
        _view([
          const NoticeItem(
            id: 'n1',
            kind: NoticeKind.emptyTurn,
            text: 'The agent returned no answer.',
          ),
          const NoticeItem(
            id: 'n2',
            kind: NoticeKind.error,
            text: 'Prompt failed.',
            failure: AgentPromptFailure(
              message: 'Provider unavailable',
              errorClass: 'provider',
            ),
          ),
        ]),
      );

      expect(
        out.toString(),
        'note: The agent returned no answer.\n'
        'error: Provider unavailable (provider)\n',
      );
    });
  });

  group('history', () {
    test('skip marks the transcript as printed', () {
      final r = renderer();
      r.skip(_view([const AgentTextItem(id: 't', text: 'old')]));
      r.render(
        _view([
          const AgentTextItem(id: 't', text: 'old'),
          const AgentTextItem(id: 't2', text: 'new'),
        ]),
      );

      expect(out.toString(), 'new');
    });

    test('replay prints a loaded session with user prompts', () {
      final r = renderer();
      r.replay(
        _view([
          const UserItem(id: 'u', text: 'hi'),
          const AgentTextItem(id: 't', text: 'hello'),
        ]),
      );

      expect(out.toString(), '> hi\nhello\n');
    });

    test('a prompt is printed when its turn starts, a queued one '
        'too', () {
      final r = renderer();
      r.render(
        _view([
          const UserItem(id: 'u', text: 'hi'),
          const AgentTextItem(id: 't', text: 'hello'),
        ]),
      );
      r.render(
        _view([
          const UserItem(id: 'u', text: 'hi'),
          const AgentTextItem(id: 't', text: 'hello'),
          const UserItem(id: 'u2', text: 'queued\none'),
        ]),
      );

      expect(out.toString(), '> hi\nhello\n> queued\n  one\n');
    });

    test('raw does not print prompts', () {
      final r = renderer(surface: OutputSurface.raw);
      r.render(
        _view([
          const UserItem(id: 'u', text: 'hi'),
          const AgentTextItem(id: 't', text: 'hello'),
        ]),
      );

      expect(out.toString(), 'hello');
    });
  });
}
