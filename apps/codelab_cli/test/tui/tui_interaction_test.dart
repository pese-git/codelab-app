// Ядро экрана TUI: одобрение, пикеры и дополнение команд (tasks 4.1, 5.3
// change `add-cli-tui`; spec codelab-tui «Одобрение в TUI», «Команды и
// пикеры TUI»; design.md, D9, D10, D12).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 12);
final _sgr = RegExp('\x1b\\[[0-9;]*m');

String _plain(String line) => line.replaceAll(_sgr, '');

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const _rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);

PendingApprovalView _approval(String id, {String command = 'make test'}) =>
    PendingApprovalView(
      approvalId: ApprovalRequestId(id),
      sessionId: const SessionId('s1'),
      risk: ApprovalRiskLevel.shell,
      command: command,
      rawInput: {'command': command, 'apiKey': 'sk-secret-value'},
      options: const [_allowOnce, _rejectOnce],
      focused: true,
    );

SessionView _view(
  int revision, {
  SessionStatusView status = SessionStatusView.running,
  List<PendingApprovalView> approvals = const [],
  List<TranscriptItem> transcript = const [],
}) => SessionView(
  revision: revision,
  status: status,
  pendingApprovals: approvals,
  transcript: transcript,
);

TuiModel _model({int rows = 30, int columns = 100}) => TuiModel.initial(
  profile: 'default',
  size: TerminalSize(columns: columns, rows: rows),
  cwd: '/work',
  commands: mvpReplCommands,
);

(TuiModel, List<TuiCmd>) _run(TuiModel model, List<TuiMsg> messages) {
  final cmds = <TuiCmd>[];
  for (final msg in messages) {
    final (next, out) = reduce(model, msg);
    model = next;
    cmds.addAll(out);
  }
  return (model, cmds);
}

KeyMsg _key(Key key) => KeyMsg(SpecialKey(key), at: _t0);
KeyMsg _text(String text) => KeyMsg(TextKey(text), at: _t0);

TuiModel _asking([List<PendingApprovalView>? approvals]) => _run(_model(), [
  SessionViewMsg(_view(1, approvals: approvals ?? [_approval('a1')]), at: _t0),
]).$1;

TuiChrome _chrome({List<String>? picker}) =>
    TuiChrome(hints: 'Enter send', picker: picker, now: _t0);

List<String> _frame(TuiModel model, {List<String>? picker}) => [
  for (final line in render(model, _chrome(picker: picker)).lines) _plain(line),
];

const _models = PickerSpec(
  title: 'Model (model):',
  items: [
    PickerItem(label: 'm1  Model 1', line: '/model m1'),
    PickerItem(label: 'm2  Model 2', line: '/model m2'),
  ],
);

void main() {
  group('approval', () {
    test('y answers the offered allow_once option', () {
      final (model, cmds) = _run(_asking(), [_text('y')]);

      expect(cmds, [
        const RespondCmd(
          ApprovalRequestId('a1'),
          PermissionOptionId('allow-once'),
        ),
      ]);
      expect(model.composer.isEmpty, isTrue, reason: 'y is not typed');
    });

    test('a key of an option the agent did not offer and Enter send '
        'nothing', () {
      expect(_run(_asking(), [_text('a')]).$2, isEmpty);
      expect(_run(_asking(), [_text('N')]).$2, isEmpty);
      expect(_run(_asking(), [_key(Key.enter)]).$2, isEmpty);
    });

    test('Esc and Ctrl+C cancel the turn', () {
      expect(reduce(_asking(), _key(Key.escape)).$2, [const CancelTurnCmd()]);
      expect(reduce(_asking(), _key(Key.ctrlC)).$2, [const CancelTurnCmd()]);
    });

    test('an answer follows the transcript again', () {
      final (model, _) = _run(_asking(), [
        SessionViewMsg(
          _view(
            2,
            approvals: [_approval('a1')],
            transcript: [
              for (var i = 0; i < 60; i++)
                TranscriptItem.user(id: 'u$i', text: 'line $i'),
            ],
          ),
          at: _t0,
        ),
        _key(Key.pageUp),
        _text('y'),
      ]);

      expect(model.scroll.follow, isTrue);
    });

    test('a request left after the turn does not block the composer', () {
      final (model, cmds) = _run(_model(), [
        SessionViewMsg(
          _view(
            1,
            status: SessionStatusView.idle,
            approvals: [_approval('a1')],
          ),
          at: _t0,
        ),
        _text('y'),
      ]);

      expect(model.composer.text, 'y');
      expect(cmds, isEmpty);
    });

    test('the zone replaces the composer with the call, the folder and '
        'only the offered keys', () {
      final frame = _frame(_asking());

      expect(frame.any((l) => l.startsWith('Permission: ')), isTrue);
      expect(frame, contains('  command: make test'));
      expect(frame, contains('  cwd: /work'));
      final hint = frame.singleWhere((l) => l.contains('[y] allow once'));
      expect(hint, contains('[n] reject once'));
      expect(hint, isNot(contains('[a]')));
      expect(frame.any((l) => l.startsWith('> ')), isFalse);
      expect(render(_asking(), _chrome()).cursor, isNull);
    });

    test('? shows the raw input with the secrets redacted', () {
      final (model, cmds) = _run(_asking(), [_text('?')]);
      final frame = _frame(model).join('\n');

      expect(cmds, isEmpty);
      expect(frame, contains('make test'));
      expect(frame, contains('apiKey'));
      expect(frame, isNot(contains('sk-secret-value')));
    });

    test('the zone wraps its lines instead of cutting the hint', () {
      final model = _run(_model(columns: 40), [
        SessionViewMsg(_view(1, approvals: [_approval('a1')]), at: _t0),
      ]).$1;
      final frame = _frame(model).join('\n');

      expect(frame, contains('[Esc] cancel'));
      expect(frame, contains('[?] details'));
    });

    test('the general hint line is hidden: its keys do not work in the '
        'zone', () {
      expect(_frame(_asking()), isNot(contains('Enter send')));
    });

    test('two requests are shown one at a time in order', () {
      final model = _asking([_approval('a1'), _approval('a2', command: 'ls')]);

      expect(_frame(model), contains('  command: make test'));
      expect(_frame(model), isNot(contains('  command: ls')));
      expect(reduce(model, _text('n')).$2, [
        const RespondCmd(
          ApprovalRequestId('a1'),
          PermissionOptionId('reject-once'),
        ),
      ]);
    });
  });

  group('pickers', () {
    test('a picker message opens the overlay', () {
      final (model, cmds) = _run(_model(), [const OpenPickerMsg(_models)]);

      expect(model.overlay, _models);
      expect(cmds, isEmpty);
    });

    test('a choice closes the picker and runs its command', () {
      final (model, cmds) = _run(_model(), [
        const OpenPickerMsg(_models),
        const PickerChosenMsg(1),
      ]);

      expect(model.overlay, isNull);
      expect(cmds, [const RunCommandCmd('/model m2')]);
      expect(model.notes.last.text, '> /model m2');
    });

    test('closing sends nothing', () {
      final (model, cmds) = _run(_model(), [
        const OpenPickerMsg(_models),
        const PickerClosedMsg(),
      ]);

      expect(model.overlay, isNull);
      expect(cmds, isEmpty);
    });

    test('the picker rows stand above the composer, at most half the '
        'screen', () {
      final (model, _) = _run(_model(rows: 20), [const OpenPickerMsg(_models)]);
      final rows = [for (var i = 0; i < 15; i++) 'item $i'];
      final frame = _frame(model, picker: rows);

      expect(frame, hasLength(20));
      expect(frame, contains('item 0'));
      expect(frame, isNot(contains('item 10')));
      final composer = frame.indexWhere((l) => l.startsWith('> '));
      expect(frame.indexOf('item 9'), lessThan(composer));
    });
  });

  test('the general hint line is hidden while a picker is open', () {
    final (model, _) = _run(_model(), [const OpenPickerMsg(_models)]);

    expect(_frame(model, picker: ['› m1']), isNot(contains('Enter send')));
  });

  group('Tab', () {
    test('one candidate is put into the composer', () {
      final (model, cmds) = _run(_model(), [_text('/he'), _key(Key.tab)]);

      expect(model.composer.text, '/help ');
      expect(model.overlay, isNull);
      expect(cmds, isEmpty);
    });

    test('several candidates open a picker that inserts the choice', () {
      var (model, _) = _run(_model(), [_text('/mo'), _key(Key.tab)]);

      final overlay = model.overlay!;
      expect(overlay.action, PickerAction.insert);
      expect([for (final i in overlay.items) i.line], ['/mode ', '/model ']);

      (model, _) = _run(model, [const PickerChosenMsg(1)]);
      expect(model.composer.text, '/model ');
      expect(model.overlay, isNull);
    });

    test('agent commands are marked in the picker', () {
      final (model, _) = _run(_model(), [
        SessionViewMsg(
          const SessionView(
            revision: 1,
            status: SessionStatusView.idle,
            agentCommands: [
              AgentCommandView(name: 'review', description: 'review code'),
              AgentCommandView(name: 'resolve', description: 'resolve'),
            ],
          ),
          at: _t0,
        ),
        _text('/re'),
        _key(Key.tab),
      ]);

      final labels = [for (final i in model.overlay!.items) i.label];
      expect(labels.where((l) => l.contains('(agent)')), hasLength(2));
    });
  });

  test('another session replaces the transcript even with a lower '
      'revision, and drops the notes', () {
    final (model, _) = _run(_model(), [
      SessionViewMsg(
        _view(
          9,
          status: SessionStatusView.idle,
          transcript: [TranscriptItem.user(id: 'u1', text: 'old')],
        ),
        at: _t0,
      ),
      const NoteMsg('> /new'),
      SessionAttachedMsg(_view(1, status: SessionStatusView.idle), at: _t0),
    ]);

    expect(model.session!.revision, 1);
    expect(model.session!.transcript, isEmpty);
    expect(model.notes, isEmpty);
    expect(_frame(model).join('\n'), isNot(contains('old')));
  });

  test('the thoughts mode and clearing the notes come as messages', () {
    final (model, _) = _run(_model(), [
      const NoteMsg('one'),
      const ThoughtsMsg(ThoughtsMode.hidden),
      const ClearNotesMsg(),
    ]);

    expect(model.thoughts, ThoughtsMode.hidden);
    expect(model.notes, isEmpty);
  });
}
