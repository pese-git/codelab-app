// Вызов `agent` в построчном выводе REPL и headless (задача 2.1 «CLI» change
// `add-subagents-and-tasks`; spec codelab-cli «Субагенты и список задач в
// REPL»: сценарии «Отчёт субагента в pipe», «Итог в строке вызова»; design.md,
// D24, D27, D28; задача 2.9).
//
// Красные тесты: у `ToolCallView` нет `subagentCall` и `subagentSummary`
// (задача 2.9 kit) — файл не компилируется; затем рендер не печатает итог в
// скобках, отчёт и прогресс. Правила, которые фиксируют тесты:
//  - вызов, опознанный как `agent` с первого кадра (D28), печатается сразу
//    (скрытие бегущего `think` на него не действует);
//  - на `ansi` строка прогресса обновляется на месте, на `plain` и `raw` —
//    не печатается вовсе;
//  - итог — ` (N tool calls · N.Nk tokens · <время>)` в строке вызова, без
//    слова «Done»; у стороннего агента без `summary` скобок нет;
//  - отчёт — до 20 строк с отступом и `… (<n> more lines)` (D27);
//  - весь текст сессии проходит очистку управляющих символов.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _title = 'Subagent explore: Find auth code';
const _summary = SubagentSummaryView(
  toolCalls: 4,
  inputTokens: 15200,
  outputTokens: 3000,
  duration: Duration(seconds: 48),
);

var _revision = 0;

ToolCallItem _agentCall({
  ToolCallStatusView status = ToolCallStatusView.running,
  List<String> textOutput = const [],
  SubagentSummaryView? summary,
  bool subagent = true,
  String title = _title,
}) => ToolCallItem(
  id: 'call-1',
  toolCallId: const ToolCallId('call_1'),
  title: title,
  details: ToolCallView(
    kind: ToolKind.think,
    status: status,
    rawInput: const {'type': 'explore', 'description': 'Find auth code'},
    subagentCall: subagent
        ? const SubagentCallView(id: 'sub_a1', type: 'explore')
        : null,
    subagentSummary: summary,
    textOutput: textOutput,
  ),
);

SessionView _view(ToolCallItem item) => SessionView(
  revision: ++_revision,
  status: SessionStatusView.running,
  transcript: [item],
);

List<String> _report(int lines) => [
  for (var i = 1; i <= lines; i++) 'report line $i',
];

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  TerminalRenderer renderer(OutputSurface surface) => TerminalRenderer(
    surface: surface,
    out: out,
    err: err,
    clock: () => DateTime(2026, 11, 14, 12),
  );

  group('the call row (toolRow)', () {
    test('the summary goes in parentheses after the title, without "Done"', () {
      final row = toolRow(
        _agentCall(status: ToolCallStatusView.succeeded, summary: _summary),
      );

      expect(row, contains('$_title (4 tool calls · 18.2k tokens · 48s)'));
      expect(row, startsWith('✓ '));
      expect(row, isNot(contains('Done')));
    });

    test('a failed call keeps its icon together with the summary', () {
      final row = toolRow(
        _agentCall(status: ToolCallStatusView.failed, summary: _summary),
      );

      expect(row, startsWith('✗ '));
      expect(row, contains('(4 tool calls · 18.2k tokens · 48s)'));
    });

    test('a third-party agent without summary has no parentheses', () {
      final row = toolRow(
        _agentCall(
          status: ToolCallStatusView.succeeded,
          subagent: false,
          title: 'Thinking about it',
        ),
      );

      expect(row, '✓ Thinking about it');
    });

    test('a running call has no summary even if one arrived early', () {
      final row = toolRow(_agentCall(summary: _summary));

      expect(row, isNot(contains('tool calls')));
    });

    test('control characters in the title are removed, the summary stays', () {
      final row = toolRow(
        _agentCall(
          status: ToolCallStatusView.succeeded,
          summary: _summary,
          title: 'Subagent explore: \x1b[31mred',
        ),
      );

      expect(row, isNot(contains('\x1b')));
      expect(row, contains('(4 tool calls · 18.2k tokens · 48s)'));
    });
  });

  group('the report in a pipe (plain), "Отчёт субагента в pipe"', () {
    test('30 lines: no progress lines and no 0x1B, 20 lines of the report and '
        '"… (10 more lines)"', () {
      final r = renderer(OutputSurface.plain);
      r.render(_view(_agentCall()));
      r.render(
        _view(_agentCall(textOutput: const ['explore · 2 tool calls · 9s'])),
      );
      r.render(
        _view(
          _agentCall(
            status: ToolCallStatusView.succeeded,
            textOutput: [_report(30).join('\n')],
            summary: _summary,
          ),
        ),
      );
      r.finishTurn();

      final text = out.toString();
      expect(text, isNot(contains('explore · 2 tool calls')));
      expect(text, isNot(contains('\x1b')));
      expect(err.toString(), isNot(contains('\x1b')));
      final lines = text.split('\n');
      final reportLines = lines
          .where((l) => l.contains('report line'))
          .toList();
      expect(reportLines, hasLength(20));
      expect(reportLines.first, matches(RegExp(r'^\s+report line 1$')));
      expect(reportLines.last, matches(RegExp(r'^\s+report line 20$')));
      expect(text, contains('… (10 more lines)'));
      expect(text, isNot(contains('report line 21')));
    });

    test('a report of 20 lines or less has no "more lines" row', () {
      final r = renderer(OutputSurface.plain);
      r.render(_view(_agentCall()));
      r.render(
        _view(
          _agentCall(
            status: ToolCallStatusView.succeeded,
            textOutput: [_report(20).join('\n')],
          ),
        ),
      );
      r.finishTurn();

      expect('report line'.allMatches(out.toString()), hasLength(20));
      expect(out.toString(), isNot(contains('more lines')));
    });

    test('the report is printed once for repeated revisions', () {
      final r = renderer(OutputSurface.plain);
      final done = _agentCall(
        status: ToolCallStatusView.succeeded,
        textOutput: ['Auth lives in lib/auth.dart.'],
        summary: _summary,
      );
      r.render(_view(_agentCall()));
      r.render(_view(done));
      r.render(_view(done));
      r.finishTurn();

      expect(
        'Auth lives in lib/auth.dart.'.allMatches(out.toString()),
        hasLength(1),
      );
    });

    test('control characters of the report are removed', () {
      final r = renderer(OutputSurface.plain);
      r.render(_view(_agentCall()));
      r.render(
        _view(
          _agentCall(
            status: ToolCallStatusView.succeeded,
            textOutput: ['ok \x1b[2J done\x07'],
          ),
        ),
      );
      r.finishTurn();

      expect(out.toString(), isNot(contains('\x1b')));
      expect(out.toString(), isNot(contains('\x07')));
    });

    test(
      'a third-party think call without the sign prints no report block',
      () {
        final r = renderer(OutputSurface.plain);
        r.render(
          _view(
            _agentCall(
              status: ToolCallStatusView.succeeded,
              subagent: false,
              title: 'Thinking about it',
              textOutput: ['hidden thoughts'],
            ),
          ),
        );
        r.finishTurn();

        expect(out.toString(), '✓ Thinking about it\n');
      },
    );
  });

  group('progress (D27)', () {
    test(
      'a running agent call is printed at once, unlike an ordinary think',
      () {
        final r = renderer(OutputSurface.plain);
        r.render(_view(_agentCall()));

        expect(out.toString(), contains(_title));
      },
    );

    test(
      'on ansi progress is updated in place: the line count does not grow',
      () {
        final r = renderer(OutputSurface.ansi);
        r.render(_view(_agentCall()));
        r.render(
          _view(_agentCall(textOutput: const ['explore · 1 tool call · 4s'])),
        );
        final afterFirst = '\n'.allMatches(out.toString()).length;
        expect(out.toString(), contains('explore · 1 tool call · 4s'));

        r.render(
          _view(_agentCall(textOutput: const ['explore · 2 tool calls · 9s'])),
        );

        expect(out.toString(), contains('explore · 2 tool calls · 9s'));
        expect('\n'.allMatches(out.toString()).length, afterFirst);
      },
    );

    test('on ansi the final line follows the progress and the progress is not '
        'left as a separate line', () {
      final r = renderer(OutputSurface.ansi);
      r.render(_view(_agentCall()));
      r.render(
        _view(_agentCall(textOutput: const ['explore · 1 tool call · 4s'])),
      );
      r.render(
        _view(
          _agentCall(
            status: ToolCallStatusView.succeeded,
            textOutput: const ['Auth lives in lib/auth.dart.'],
            summary: _summary,
          ),
        ),
      );
      r.finishTurn();

      final lines = out.toString().split('\n');
      // Строка прогресса стёрта итоговой: отдельной строки с ней в выводе
      // нет, итоговая строка со скобками есть.
      expect(
        lines.where(
          (l) =>
              l.contains('explore · 1 tool call · 4s') &&
              !l.contains('\x1b[') &&
              !l.contains('\r'),
        ),
        isEmpty,
      );
      expect(
        lines.any((l) => l.contains('(4 tool calls · 18.2k tokens · 48s)')),
        isTrue,
      );
    });

    for (final surface in [OutputSurface.plain, OutputSurface.raw]) {
      test('on $surface progress is not printed', () {
        final r = renderer(surface);
        r.render(_view(_agentCall()));
        final before = '${out.toString()}|${err.toString()}';

        r.render(
          _view(_agentCall(textOutput: const ['explore · 1 tool call · 4s'])),
        );
        r.render(
          _view(_agentCall(textOutput: const ['explore · 2 tool calls · 9s'])),
        );

        expect('${out.toString()}|${err.toString()}', before);
        expect(out.toString(), isNot(contains('\x1b')));
      });
    }
  });
}
