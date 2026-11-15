// Хвост работающего субагента и раскрытие строк `agent` в TUI (задача 5.1
// `[client]`, часть CLI, change `add-subagents-and-tasks`; spec codelab-tui
// «Субагенты и список задач в TUI»: сценарии «Хвост работающего субагента в
// TUI» и «Ctrl+O раскрывает строки agent»; design.md, D25, D47 Т10, D48 п. 2).
//
// Красные тесты. Заглушки (без логики, реализация — задача 5.4):
//   kit: `ToolCallItem.children`, `.tail` (`SubagentTailView`), `.subtreeCalls`;
//   CLI: `Key.ctrlO` и `KeyAction.toggleDetails` — клавиша не привязана к
//     таблице `KeyBindings.tui`, не декодируется `TuiInput`, не входит в
//     подсказки, действие ничего не делает.
// Флаг раскрытия в `TuiModel` в тестах не читается: проверяется кадр
// (`render`) после `reduce`, чтобы имя флага выбирала реализация.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:dart_tui/dart_tui.dart' as tea;
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 11, 15, 12);
final _sgr = RegExp('\x1b\\[[0-9;]*m');

String _plain(String line) => line.replaceAll(_sgr, '');

const _summary = SubagentSummaryView(
  toolCalls: 4,
  inputTokens: 15200,
  outputTokens: 3000,
  duration: Duration(seconds: 48),
);

ToolCallItem _call(
  String id,
  String title, {
  ToolCallStatusView status = ToolCallStatusView.succeeded,
  ToolKind kind = ToolKind.read,
  String? parent,
  List<TranscriptItem> children = const [],
  SubagentCallView? subagentCall,
  SubagentSummaryView? summary,
  List<String> textOutput = const [],
  SubagentTailView tail = const SubagentTailView(),
  int subtreeCalls = 0,
}) => ToolCallItem(
  id: 'item-${id.replaceAll('/', '-')}',
  toolCallId: ToolCallId(id),
  title: title,
  details: ToolCallView(
    kind: kind,
    status: status,
    parentToolCallId: parent,
    rawInput: subagentCall == null
        ? null
        : {'type': subagentCall.type, 'description': 'Map callers'},
    subagentCall: subagentCall,
    subagentSummary: summary,
    textOutput: textOutput,
  ),
  children: children,
  tail: tail,
  subtreeCalls: subtreeCalls,
);

const _agentCall = SubagentCallView(id: 'sub_a1', type: 'explore');

ToolCallItem _read(String n, {ToolCallStatusView? status}) => _call(
  'call_1/call_$n',
  'Read lib/f$n.dart',
  parent: 'call_1',
  status: status ?? ToolCallStatusView.succeeded,
);

TuiModel _model(List<TranscriptItem> transcript, {String draft = ''}) {
  var (model, _) = reduce(
    TuiModel.initial(
      profile: 'default',
      size: const TerminalSize(columns: 100, rows: 80),
    ),
    SessionViewMsg(
      SessionView(
        revision: 1,
        status: SessionStatusView.idle,
        transcript: transcript,
      ),
      at: _t0,
    ),
  );
  if (draft.isNotEmpty) {
    model = reduce(model, KeyMsg(TextKey(draft), at: _t0)).$1;
  }
  return model;
}

TuiModel _press(TuiModel model, Key key) =>
    reduce(model, KeyMsg(SpecialKey(key), at: _t0)).$1;

List<String> _frame(TuiModel model, {String hints = 'Enter send'}) => [
  for (final line in render(model, TuiChrome(hints: hints, now: _t0)).lines)
    _plain(line),
];

List<String> _report(int lines) => [
  for (var i = 1; i <= lines; i++) 'report line $i',
];

void main() {
  late TranscriptLayout layout;

  setUp(() => layout = TranscriptLayout());

  List<String> lines(List<TranscriptItem> items) => layout
      .lines(
        SessionView(
          revision: 1,
          status: SessionStatusView.running,
          transcript: items,
        ),
        width: 120,
      )
      .map(_plain)
      .toList();

  group('«Хвост работающего субагента в TUI» (D25)', () {
    ToolCallItem running({required int more, List<ToolCallItem>? tail}) =>
        _call(
          'call_1',
          'Subagent explore: Map callers',
          status: ToolCallStatusView.running,
          kind: ToolKind.think,
          subagentCall: _agentCall,
          // Строка прогресса несёт токены: хвост их не показывает (Q15).
          textOutput: const ['explore · 5 tool calls · 12.3k tokens · 9s'],
          tail: SubagentTailView(
            calls:
                tail ??
                [
                  _read('3'),
                  _read('4'),
                  _read('5', status: ToolCallStatusView.running),
                ],
            moreCount: more,
          ),
          subtreeCalls: 3 + more,
          children: [for (var i = 1; i <= 5; i++) _read('$i')],
        );

    test('under the status row: three last calls with the status glyph and '
        '`+2 more tool calls`; no progress line and no tokens', () {
      final out = lines([running(more: 2)]);

      expect(out, hasLength(5));
      expect(out[0], contains('Subagent explore: Map callers'));
      expect(out[1], allOf(contains('✓'), contains('lib/f3.dart')));
      expect(out[2], allOf(contains('✓'), contains('lib/f4.dart')));
      expect(out[3], allOf(contains('…'), contains('lib/f5.dart')));
      expect(out[4], contains('+2 more tool calls'));
      expect(out.join('\n'), isNot(contains('tokens')));
      expect(out.join('\n'), isNot(contains('12.3k')));
    });

    test('three calls or fewer: no `+N more` row', () {
      final out = lines([
        running(more: 0, tail: [_read('1'), _read('2')]),
      ]);

      expect(out.join('\n'), isNot(contains('more tool calls')));
      expect(out.where((l) => l.contains('lib/f')), hasLength(2));
    });

    test('the tail is visible while the rows are collapsed (the default)', () {
      final frame = _frame(_model([running(more: 2)]));

      expect(frame.any((l) => l.contains('+2 more tool calls')), isTrue);
      expect(frame.any((l) => l.contains('lib/f5.dart')), isTrue);
    });

    test('without calls of children the progress line is shown as before '
        '(a client without the tree)', () {
      final out = lines([
        _call(
          'call_1',
          'Subagent explore: Map callers',
          status: ToolCallStatusView.running,
          kind: ToolKind.think,
          subagentCall: _agentCall,
          textOutput: const ['explore · 1 tool call · 4s'],
        ),
      ]);

      expect(out, hasLength(1));
      expect(out.single, contains('explore · 1 tool call · 4s'));
    });

    test('control characters of a tail row are removed (TUI-11)', () {
      final out = layout.lines(
        SessionView(
          revision: 1,
          status: SessionStatusView.running,
          transcript: [
            running(
              more: 0,
              tail: [
                _call(
                  'call_1/call_9',
                  'Read \x1b[31mred\x07.dart',
                  parent: 'call_1',
                ),
              ],
            ),
          ],
        ),
        width: 120,
      );

      expect(out.join('\n'), contains('red'), reason: 'the tail row is shown');
      expect(out.join('\n').replaceAll(_sgr, ''), isNot(contains('\x1b')));
      expect(out.join('\n'), isNot(contains('\x07')));
    });
  });

  group('«Ctrl+O раскрывает строки agent» (D48 п. 2)', () {
    // Вызов `agent` с ребёнком: `read`, вложенный `agent` с внуком и
    // `task_update` (тихая строка); отчёт — 30 строк.
    ToolCallItem tree() => _call(
      'call_1',
      'Subagent explore: Map callers',
      kind: ToolKind.think,
      subagentCall: _agentCall,
      summary: _summary,
      textOutput: [_report(30).join('\n')],
      children: [
        _call('call_1/call_1', 'Read lib/a.dart', parent: 'call_1'),
        _call(
          'call_1/call_2',
          'Subagent explore: Find auth code',
          kind: ToolKind.think,
          parent: 'call_1',
          subagentCall: const SubagentCallView(id: 'sub_b2', type: 'explore'),
          summary: const SubagentSummaryView(
            toolCalls: 2,
            inputTokens: 1000,
            outputTokens: 200,
            duration: Duration(seconds: 3),
          ),
          textOutput: const ['GRANDCHILD REPORT'],
          children: [
            _call(
              'call_1/call_2/call_1',
              'Read lib/b.dart',
              parent: 'call_1/call_2',
            ),
          ],
        ),
        const TaskOpsItem(id: 'ops-1', completed: ['1']),
      ],
    );

    test('Ctrl+O is the toggle_details action in the TUI table, works '
        'during a turn and is decoded from the terminal', () {
      final tui = KeyBindings.tui;

      expect(tui.actionFor(Key.ctrlO, running: false), KeyAction.toggleDetails);
      expect(tui.actionFor(Key.ctrlO, running: true), KeyAction.toggleDetails);
      expect(tui.helpLines().join('\n'), contains('Ctrl+O'));

      final decoded = TuiInput().translate(
        tea.KeyPressMsg(
          tea.TeaKey(
            code: tea.KeyCode.rune,
            text: 'o',
            modifiers: const {tea.KeyMod.ctrl},
          ),
        ),
        now: _t0,
      );
      expect(decoded, isA<KeyMsg>());
      expect((decoded! as KeyMsg).key, const SpecialKey(Key.ctrlO));
    });

    test('the hint line has `ctrl+o details` right after `ctrl+t tasks`', () {
      final help = tea.HelpModel.fromKeyMap(
        RegistryKeyMap(),
        title: '',
        styles: const tea.HelpStyles(),
      );

      expect(hintLine(help), contains('ctrl+t tasks · ctrl+o details'));
    });

    test('collapsed by default: one status row with the summary, no steps '
        'and no report', () {
      final frame = _frame(_model([tree()]));
      final rows = frame.where((l) => l.contains('Subagent explore'));

      expect(rows, hasLength(1));
      expect(rows.single, contains('4 tool calls · 18.2k · 48s'));
      expect(frame.any((l) => l.contains('↳')), isFalse);
      expect(frame.any((l) => l.contains('report line')), isFalse);
    });

    test('the first Ctrl+O shows steps with `↳`, quiet rows, the report up '
        'to 20 lines and `… (10 more lines)`; the second one collapses '
        'again; the composer keeps its text', () {
      var model = _model([tree()], draft: 'draft');

      model = _press(model, Key.ctrlO);
      var frame = _frame(model);
      final status = frame.indexWhere(
        (l) => l.contains('Subagent explore: Map callers'),
      );
      final read = frame.indexWhere((l) => l.contains('Read lib/a.dart'));
      final nested = frame.indexWhere(
        (l) => l.contains('Subagent explore: Find auth code'),
      );
      final grandchild = frame.indexWhere((l) => l.contains('lib/b.dart'));
      final task = frame.indexWhere((l) => l.contains('Task #1 done'));
      final firstReport = frame.indexWhere((l) => l.contains('report line 1'));

      expect(read, greaterThan(status), reason: 'steps are under the status');
      expect(frame[read], startsWith('  ↳ '));
      expect(frame[nested], startsWith('  ↳ '));
      expect(frame[nested], contains('2 tool calls · 1.2k'));
      expect(frame[grandchild], startsWith('    ↳ '));
      expect(frame[task].trimRight(), '  ↳ Task #1 done');
      expect(read, lessThan(nested));
      expect(nested, lessThan(task));
      expect(task, lessThan(firstReport), reason: 'the report is after steps');
      expect(
        frame.any((l) => l.contains('GRANDCHILD REPORT')),
        isFalse,
        reason: 'the nested agent has no report (D48 п. 4)',
      );
      expect(frame.where((l) => l.contains('report line ')), hasLength(20));
      expect(frame.any((l) => l.contains('report line 21')), isFalse);
      expect(frame.any((l) => l.contains('… (10 more lines)')), isTrue);
      expect(frame.where((l) => l.contains('> draft')), hasLength(1));

      model = _press(model, Key.ctrlO);
      frame = _frame(model);
      expect(frame.any((l) => l.contains('↳')), isFalse);
      expect(frame.any((l) => l.contains('report line')), isFalse);
      expect(frame.where((l) => l.contains('Subagent explore')), hasLength(1));
      expect(frame.where((l) => l.contains('> draft')), hasLength(1));
    });

    test('Ctrl+O expands all agent rows at once', () {
      final model = _press(
        _model([
          tree(),
          _call(
            'call_7',
            'Subagent review: Check',
            kind: ToolKind.think,
            subagentCall: const SubagentCallView(id: 'sub_z9', type: 'review'),
            children: [
              _call('call_7/call_1', 'Read lib/z.dart', parent: 'call_7'),
            ],
          ),
        ]),
        Key.ctrlO,
      );

      final frame = _frame(model);
      expect(frame.any((l) => l.contains('Read lib/a.dart')), isTrue);
      expect(frame.any((l) => l.contains('Read lib/z.dart')), isTrue);
    });

    test('Ctrl+O works while a turn runs and does not type into the '
        'composer', () {
      final (running, _) = reduce(
        _model([tree()]),
        SessionViewMsg(
          SessionView(
            revision: 2,
            status: SessionStatusView.running,
            transcript: [tree()],
          ),
          at: _t0,
        ),
      );

      final model = _press(running, Key.ctrlO);

      expect(_frame(model).any((l) => l.contains('Read lib/a.dart')), isTrue);
      expect(model.composer.isEmpty, isTrue);
    });
  });
}
