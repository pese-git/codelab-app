// Строка вызова инструмента (tasks 5.5; spec codelab-cli «Рендер хода в
// REPL»; §12.2.11, TUI-6; design.md change `add-codelab-cli`, D6).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

ToolCallItem _call(
  ToolCallStatusView status, {
  String title = 'Run tests',
  String? command,
  ApprovalStateView? approval,
}) => ToolCallItem(
  id: 'c1',
  toolCallId: const ToolCallId('call_1'),
  title: title,
  details: ToolCallView(
    kind: ToolKind.execute,
    status: status,
    command: command,
  ),
  approval: approval,
);

void main() {
  test('icons follow the status', () {
    expect(toolRow(_call(ToolCallStatusView.queued)), startsWith('… '));
    expect(toolRow(_call(ToolCallStatusView.running)), startsWith('… '));
    expect(toolRow(_call(ToolCallStatusView.succeeded)), startsWith('✓ '));
    expect(toolRow(_call(ToolCallStatusView.failed)), startsWith('✗ '));
    expect(toolRow(_call(ToolCallStatusView.cancelled)), startsWith('⊘ '));
  });

  test('a rejected approval shows the rejected icon', () {
    final row = toolRow(
      _call(
        ToolCallStatusView.failed,
        approval: const ResolvedApprovalView(
          label: 'Rejected',
          outcome: ApprovalOutcomeView.rejected,
        ),
      ),
    );

    expect(row, startsWith('⊘ '));
  });

  test('ASCII icons replace UTF-8 ones', () {
    String ascii(ToolCallStatusView status) =>
        toolRow(_call(status), unicode: false).substring(0, 2);

    expect(ascii(ToolCallStatusView.running), '* ');
    expect(ascii(ToolCallStatusView.succeeded), '+ ');
    expect(ascii(ToolCallStatusView.failed), 'x ');
    expect(ascii(ToolCallStatusView.cancelled), '- ');
  });

  test('the detail is the command', () {
    expect(
      toolRow(_call(ToolCallStatusView.running, command: 'npm test')),
      '… Run tests npm test',
    );
  });

  test('a command already in the title is not repeated', () {
    expect(
      toolRow(
        _call(
          ToolCallStatusView.running,
          title: 'Run npm test',
          command: 'npm test',
        ),
      ),
      '… Run npm test',
    );
  });

  test('the elapsed time goes last', () {
    expect(
      toolRow(
        _call(ToolCallStatusView.succeeded, command: 'ls'),
        elapsed: const Duration(milliseconds: 3240),
      ),
      '✓ Run tests ls 3.2s',
    );
  });

  test('a multi-line command keeps only its first line', () {
    expect(
      toolRow(_call(ToolCallStatusView.running, command: 'echo a\necho b')),
      '… Run tests echo a …',
    );
  });

  test('control characters from the agent are removed', () {
    expect(
      toolRow(_call(ToolCallStatusView.running, title: 'Run \x1b[31mx')),
      '… Run [31mx',
    );
  });

  test('a call without details is shown as pending', () {
    const item = ToolCallItem(
      id: 'c1',
      toolCallId: ToolCallId('call_1'),
      title: 'Read file',
    );

    expect(toolRow(item), '… Read file');
  });
}
