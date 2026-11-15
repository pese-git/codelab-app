// Шаги потомков деревом в построчном выводе REPL (задача 5.1 `[client]`,
// часть CLI, change `add-subagents-and-tasks`; spec codelab-cli «Субагенты и
// список задач в REPL»: сценарии «Шаги ребёнка с отступом» и «Внук в REPL»,
// правило про вызовы потомков и блок одобрения при дереве; design.md, D21,
// D27 п. 4, D47 Т10, D48 п. 3, 4).
//
// Опора: `ToolCallItem.children` kit — вложенные `ToolCallItem`/`TaskOpsItem`
// по порядку прихода. Правила, которые фиксируют тесты:
//  - вызов потомка печатается строкой завершения (бегущий — не печатается;
//    прогресс потомков на месте не обновляется) с отступом в два пробела на
//    уровень глубины и префиксом `↳ ` (на `raw` — `> `, в stderr);
//  - вложенный `agent` — строка завершения с итогом в скобках из
//    `subagentSummary`, без отчёта; отчёт печатается только у `agent` корня;
//  - тихая строка операции потомка — тот же отступ и `↳`, приглушённо, без
//    значка статуса и времени;
//  - перед строкой потомка закрывается строка прогресса на месте (ansi);
//  - при дереве печатаются и строка исхода одобрения, и строка завершения
//    вызова потомка (D47 Т10).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

var _revision = 0;

final _sgr = RegExp('\x1b\\[[0-9;]*m');

const _summary = SubagentSummaryView(
  toolCalls: 4,
  inputTokens: 15200,
  outputTokens: 3000,
  duration: Duration(seconds: 48),
);

const _grandchildSummary = SubagentSummaryView(
  toolCalls: 2,
  inputTokens: 1000,
  outputTokens: 200,
  duration: Duration(seconds: 3),
);

/// Вызов потомка или корня; [children] — вложенные элементы.
ToolCallItem _call(
  String id,
  String title, {
  ToolCallStatusView status = ToolCallStatusView.succeeded,
  ToolKind kind = ToolKind.read,
  String? parent,
  List<TranscriptItem> children = const [],
  List<ApprovalStateView> childApprovals = const [],
  ApprovalStateView? approval,
  SubagentCallView? subagentCall,
  SubagentSummaryView? summary,
  List<String> textOutput = const [],
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
        : {'type': subagentCall.type, 'description': 'Find auth code'},
    subagentCall: subagentCall,
    subagentSummary: summary,
    textOutput: textOutput,
  ),
  approval: approval,
  childApprovals: childApprovals,
  children: children,
);

ToolCallItem _rootAgent({
  ToolCallStatusView status = ToolCallStatusView.running,
  List<TranscriptItem> children = const [],
  List<ApprovalStateView> childApprovals = const [],
  List<String> textOutput = const [],
  SubagentSummaryView? summary,
}) => _call(
  'call_1',
  'Subagent explore: Find auth code',
  status: status,
  kind: ToolKind.think,
  subagentCall: const SubagentCallView(id: 'sub_a1', type: 'explore'),
  children: children,
  childApprovals: childApprovals,
  textOutput: textOutput,
  summary: summary,
);

ToolCallItem _read(String id, String path, {String parent = 'call_1'}) =>
    _call(id, 'Read $path', parent: parent);

SessionView _view(List<TranscriptItem> transcript) => SessionView(
  revision: ++_revision,
  status: SessionStatusView.running,
  transcript: transcript,
);

List<String> _lines(StringBuffer out) => out.toString().split('\n');

/// Видимые строки ansi-вывода: всё, что стёрто `\r\x1b[2K` на той же строке,
/// не считается видимым.
List<String> _visible(StringBuffer out) => [
  for (final line in _lines(out)) line.split(clearCurrentLine).last,
];

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
    _revision = 0;
  });

  TerminalRenderer renderer(OutputSurface surface) => TerminalRenderer(
    surface: surface,
    out: out,
    err: err,
    clock: () => DateTime(2026, 11, 15, 12),
  );

  group('«Шаги ребёнка с отступом»', () {
    test('the child call is a completion line `  ↳ ` under the agent row, '
        'then the report', () {
      final r = renderer(OutputSurface.plain);
      r.render(_view([_rootAgent()]));
      r.render(
        _view([
          _rootAgent(children: [_read('call_1/call_1', 'lib/a.dart')]),
        ]),
      );
      r.render(
        _view([
          _rootAgent(
            status: ToolCallStatusView.succeeded,
            summary: _summary,
            textOutput: const ['Auth lives in lib/auth.dart.'],
            children: [_read('call_1/call_1', 'lib/a.dart')],
          ),
        ]),
      );
      r.finishTurn();

      final lines = _lines(out);
      final step = lines.indexWhere((l) => l.contains('Read lib/a.dart'));
      expect(step, isNonNegative, reason: 'the child line is printed');
      expect(lines[step], startsWith('  ↳ '));
      final report = lines.indexWhere(
        (l) => l.contains('Auth lives in lib/auth.dart.'),
      );
      expect(report, greaterThan(step), reason: 'the report follows steps');
      // Строка потомка печатается один раз, сколько бы ревизий ни пришло.
      expect('Read lib/a.dart'.allMatches(out.toString()), hasLength(1));
    });

    test('a running child call is not printed; progress of children is not '
        'updated in place, only the completion line is printed', () {
      final r = renderer(OutputSurface.plain);
      r.render(_view([_rootAgent()]));
      r.render(
        _view([
          _rootAgent(
            children: [
              _call(
                'call_1/call_1',
                'Read lib/a.dart',
                status: ToolCallStatusView.running,
                parent: 'call_1',
              ),
            ],
          ),
        ]),
      );
      expect(out.toString(), isNot(contains('↳')));

      r.render(
        _view([
          _rootAgent(children: [_read('call_1/call_1', 'lib/a.dart')]),
        ]),
      );
      expect('↳'.allMatches(out.toString()), hasLength(1));
    });

    test('on raw the prefix is `> ` and the line goes to stderr', () {
      final r = renderer(OutputSurface.raw);
      r.render(
        _view([
          _rootAgent(children: [_read('call_1/call_1', 'lib/a.dart')]),
        ]),
      );
      r.finishTurn();

      expect(out.toString(), isNot(contains('↳')));
      expect(err.toString(), isNot(contains('↳')));
      expect(
        err.toString(),
        matches(RegExp(r'^  > .*Read lib/a\.dart', multiLine: true)),
      );
    });

    test('on ansi the progress line is closed before the child line', () {
      final r = renderer(OutputSurface.ansi);
      r.render(_view([_rootAgent()]));
      r.render(
        _view([
          _rootAgent(textOutput: const ['explore · 1 tool call · 4s']),
        ]),
      );
      r.render(
        _view([
          _rootAgent(
            textOutput: const ['explore · 1 tool call · 4s'],
            children: [_read('call_1/call_1', 'lib/a.dart')],
          ),
        ]),
      );

      final visible = _visible(out);
      final step = visible.indexWhere((l) => l.contains('Read lib/a.dart'));
      expect(step, isNonNegative, reason: 'the child line is printed');
      expect(visible[step].replaceAll(_sgr, ''), startsWith('  ↳ '));
      expect(
        visible.where((l) => l.contains('explore · 1 tool call')),
        isEmpty,
        reason: 'the progress line is erased, not left before the child line',
      );
    });

    test('the title of the child is sanitized', () {
      final r = renderer(OutputSurface.plain);
      r.render(
        _view([
          _rootAgent(
            children: [
              _call(
                'call_1/call_1',
                'Read \x1b[31mred\x07.dart',
                parent: 'call_1',
              ),
            ],
          ),
        ]),
      );

      expect(out.toString(), contains('↳'));
      expect(out.toString(), isNot(contains('\x1b')));
      expect(out.toString(), isNot(contains('\x07')));
    });
  });

  group('«Внук в REPL» (D48 п. 3, 4)', () {
    // Ребёнок `explore` корня запускает внука `explore` (вложенный `agent`),
    // внук делает два чтения и завершается с `summary`, затем ребёнок
    // отмечает пункт (`task_update` — тихая строка) и завершается.
    ToolCallItem grandchildAgent({required ToolCallStatusView status}) => _call(
      'call_1/call_1',
      'Subagent explore: Find auth code',
      status: status,
      kind: ToolKind.think,
      parent: 'call_1',
      subagentCall: const SubagentCallView(id: 'sub_b2', type: 'explore'),
      summary: status == ToolCallStatusView.succeeded
          ? _grandchildSummary
          : null,
      textOutput: const ['GRANDCHILD REPORT'],
      children: [
        _read('call_1/call_1/call_1', 'lib/b.dart', parent: 'call_1/call_1'),
        _read('call_1/call_1/call_2', 'lib/c.dart', parent: 'call_1/call_1'),
      ],
    );

    const taskDone = TaskOpsItem(id: 'ops-1', completed: ['1']);

    test('the nested agent is one `  ↳ ` line with the summary in '
        'parentheses and no report; the grandchild steps are `    ↳ `; the '
        'task operation is a quiet `  ↳ ` line; the report only at the '
        'root', () {
      final r = renderer(OutputSurface.plain);
      r.render(
        _view([
          _rootAgent(
            children: [grandchildAgent(status: ToolCallStatusView.running)],
          ),
        ]),
      );
      r.render(
        _view([
          _rootAgent(
            children: [
              grandchildAgent(status: ToolCallStatusView.succeeded),
              taskDone,
            ],
          ),
        ]),
      );
      r.render(
        _view([
          _rootAgent(
            status: ToolCallStatusView.succeeded,
            summary: _summary,
            textOutput: const ['ROOT REPORT'],
            children: [
              grandchildAgent(status: ToolCallStatusView.succeeded),
              taskDone,
            ],
          ),
        ]),
      );
      r.finishTurn();

      final lines = _lines(out);
      final nested = lines.indexWhere(
        (l) => l.startsWith('  ↳ ') && l.contains('Subagent explore'),
      );
      expect(nested, isNonNegative, reason: 'nested agent line');
      expect(lines[nested], contains('(2 tool calls · 1.2k tokens · 3s)'));

      final readB = lines.indexWhere((l) => l.contains('Read lib/b.dart'));
      final readC = lines.indexWhere((l) => l.contains('Read lib/c.dart'));
      expect(lines[readB], startsWith('    ↳ '));
      expect(lines[readC], startsWith('    ↳ '));

      final task = lines.indexOf('  ↳ Task #1 done');
      expect(task, isNonNegative, reason: 'quiet task line with the indent');

      // Порядок завершения: шаги внука, затем его строка, затем операция.
      expect(readB, lessThan(readC));
      expect(readC, lessThan(nested));
      expect(nested, lessThan(task));

      expect(out.toString(), isNot(contains('GRANDCHILD REPORT')));
      expect('ROOT REPORT'.allMatches(out.toString()), hasLength(1));
      final root = lines.indexWhere((l) => l.contains('ROOT REPORT'));
      expect(root, greaterThan(task));
    });

    test('on ansi the quiet task line of a child is dim, without a status '
        'icon and time', () {
      final r = renderer(OutputSurface.ansi);
      r.render(
        _view([
          _rootAgent(children: const [taskDone]),
        ]),
      );
      r.finishTurn();

      final matches = _lines(out).where((l) => l.contains('Task #1 done'));
      expect(matches, hasLength(1), reason: 'the quiet line is printed');
      final line = matches.single;
      expect(line, contains('\x1b[2m'));
      expect(line.replaceAll(_sgr, ''), '  ↳ Task #1 done');
    });

    test('the quiet task line is printed once for repeated revisions', () {
      final r = renderer(OutputSurface.plain);
      final tree = _rootAgent(children: const [taskDone]);
      r.render(_view([tree]));
      r.render(
        _view([
          _rootAgent(children: const [taskDone]),
        ]),
      );
      r.finishTurn();

      expect('Task #1 done'.allMatches(out.toString()), hasLength(1));
    });
  });

  group('the approval outcome and the child call together (D47 Т10)', () {
    test('with a tree both the outcome line at the block and the `↳` '
        'completion line of the child call are printed', () {
      const review = SubagentRequester(
        id: 'sub_a1',
        type: 'review',
        description: 'Check the diff',
        depth: 1,
        parentToolCallId: 'call_1',
      );
      const resolved = ResolvedApprovalView(
        label: 'Allow once',
        outcome: ApprovalOutcomeView.allowed,
        subagent: review,
      );
      final r = renderer(OutputSurface.plain);
      r.render(
        _view([
          _rootAgent(
            childApprovals: const [resolved],
            children: [
              _call(
                'call_1/call_1',
                'Run git diff --stat',
                kind: ToolKind.execute,
                parent: 'call_1',
                approval: resolved,
              ),
            ],
          ),
        ]),
      );

      final lines = _lines(out);
      expect(lines, contains('  review: Allow once'));
      expect(
        lines.where((l) => l.startsWith('  ↳ ') && l.contains('git diff')),
        hasLength(1),
      );
    });
  });
}
