// Строка вызова `agent` в транскрипте TUI: итог в статусе (задача 2.1 «CLI»
// change `add-subagents-and-tasks`; spec codelab-tui «Субагенты и список задач
// в TUI», сценарий «Итог в статусе»; design.md, D24, D27; задача 2.9).
//
// Красные тесты: у `ToolCallView` нет `subagentCall` и `subagentSummary`
// (задача 2.9 kit) — файл не компилируется; затем TUI печатает вызов
// обычной строкой `toolRow` (итог в скобках REPL и «tokens»), а не
// `✓ Subagent explore: … 4 tool calls · 18.2k · 48s`. Правила:
//  - `completed`: глиф ✓ и сокращённый итог без слова `tokens`, без скобок и
//    без слова «Done»;
//  - `failed` и отмена: явное слово `Failed` или `Cancelled` и тот же итог;
//  - без итога (сторонний агент) — глиф или слово статуса без итога;
//  - пока вызов идёт, итога нет.
// Блок «хвоста» потомков (этап 2, C16) и раскрытие отчёта — отдельные задачи
// итерации 5; здесь только строка статуса.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _summary = SubagentSummaryView(
  toolCalls: 4,
  inputTokens: 15200,
  outputTokens: 3000,
  duration: Duration(seconds: 48),
);

String _plain(String line) => line.replaceAll(RegExp('\x1b\\[[0-9;]*m'), '');

void main() {
  late TranscriptLayout layout;

  setUp(() => layout = TranscriptLayout());

  List<String> lines(
    ToolCallStatusView status, {
    SubagentSummaryView? summary,
    bool subagent = true,
  }) {
    final item = TranscriptItem.toolCall(
      id: 't1',
      toolCallId: const ToolCallId('call_1'),
      title: 'Subagent explore: Map callers of restore()',
      details: ToolCallView(
        kind: ToolKind.think,
        status: status,
        rawInput: const {'type': 'explore'},
        subagentCall: subagent
            ? const SubagentCallView(id: 'sub_a1', type: 'explore')
            : null,
        subagentSummary: summary,
        textOutput: const ['The report.'],
      ),
    );
    return layout
        .lines(
          SessionView(
            revision: 1,
            status: SessionStatusView.idle,
            transcript: [item],
          ),
          width: 120,
        )
        .map(_plain)
        .toList();
  }

  test('completed: the check mark and the short summary without "Done"', () {
    final out = lines(ToolCallStatusView.succeeded, summary: _summary);

    expect(out, hasLength(1));
    expect(
      out.single,
      matches(
        RegExp(
          r'^✓ Subagent explore: Map callers of restore\(\) +'
          r'4 tool calls · 18\.2k · 48s$',
        ),
      ),
    );
    expect(out.single, isNot(contains('Done')));
    expect(out.single, isNot(contains('tokens')));
    expect(out.single, isNot(contains('(')));
  });

  test('failed: the word Failed and the same summary', () {
    final out = lines(ToolCallStatusView.failed, summary: _summary);

    expect(out, hasLength(1));
    expect(out.single, contains('Failed'));
    expect(out.single, contains('4 tool calls · 18.2k · 48s'));
    expect(out.single, isNot(contains('✓')));
  });

  test('cancelled: the word Cancelled and the same summary', () {
    final out = lines(ToolCallStatusView.cancelled, summary: _summary);

    expect(out, hasLength(1));
    expect(out.single, contains('Cancelled'));
    expect(out.single, contains('4 tool calls · 18.2k · 48s'));
  });

  test('a third-party agent without summary: the glyph only, no summary', () {
    final out = lines(ToolCallStatusView.succeeded, subagent: false);

    expect(out, hasLength(1));
    expect(out.single, startsWith('✓ '));
    expect(out.single, isNot(contains('tool calls')));
  });

  test('a CodeLab call that failed without summary: the word Failed, no '
      'summary', () {
    final out = lines(ToolCallStatusView.failed);

    expect(out.single, contains('Failed'));
    expect(out.single, isNot(contains('tool calls')));
  });

  test('a running call has no summary', () {
    final out = lines(ToolCallStatusView.running, summary: _summary);

    expect(out.single, isNot(contains('tool calls')));
    expect(out.single, isNot(contains('✓')));
  });
}
