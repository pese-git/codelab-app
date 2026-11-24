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

  // 6.1j-1 (D27, Q38): вызов без `tool_call`, отменённый вместе с ходом, kit
  // отдаёт со статусом `cancelled` и отменённым одобрением; значок остаётся `⊘`.
  test('a cancelled approval on a cancelled call keeps the cancelled icon', () {
    for (final status in [
      ToolCallStatusView.queued,
      ToolCallStatusView.cancelled,
    ]) {
      final row = toolRow(
        _call(
          status,
          approval: const ResolvedApprovalView(
            label: 'Cancelled',
            outcome: ApprovalOutcomeView.cancelled,
          ),
        ),
      );

      expect(row, startsWith('⊘ '), reason: '$status');
    }
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
      // CSI-последовательность заменяется пробелом целиком (D4, шаг 0
      // change `redact-tool-row-text`): раньше оставался хвост `[31m`.
      '… Run  x',
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

  // change `redact-tool-row-text`, D4; spec codelab-cli «Рендер хода в REPL».
  group('secrets in the row', () {
    test('title and command hide the credentials of an address', () {
      final row = toolRow(
        _call(
          ToolCallStatusView.succeeded,
          title: 'Fetch https://user:s3cr3t@host/x',
          command: 'curl https://user:s3cr3t@host/x?token=t0k3n',
        ),
      );

      expect(row, startsWith('✓ '));
      expect(row, contains('https://<redacted>@host/x'));
      expect(row, isNot(contains('s3cr3t')));
      expect(row, isNot(contains('t0k3n')));
    });

    test('a multi-line command is masked before the first line is taken', () {
      final row = toolRow(
        _call(
          ToolCallStatusView.succeeded,
          command:
              'curl -H "Authorization: Bearer t0k3n" https://host/x\n  --retry 3',
        ),
      );

      expect(row, isNot(contains('t0k3n')));
      expect(row, contains(' …'));
      expect(row, isNot(contains('--retry')));
    });

    test('an escape sequence inside the secret does not hide it', () {
      final row = toolRow(
        _call(
          ToolCallStatusView.succeeded,
          title: 'Bearer \x1b[0mt0k3n',
          command: 'curl -H "Authorization: Bearer \x1b[0mt0k3n" https://h/x',
        ),
      );

      expect(row, isNot(contains('t0k3n')));
      expect(row, isNot(contains('[0m')));
    });

    // spec codelab-cli «ESC-последовательность не прячет токен».
    test('an escape sequence between Bearer and the token hides nothing', () {
      final row = toolRow(
        _call(
          ToolCallStatusView.succeeded,
          command:
              "curl -H 'Authorization: Bearer\u001b[0m t0k3n' https://host/x",
        ),
      );

      expect(row, isNot(contains('t0k3n')));
      expect(row, isNot(contains('[0m')));
    });

    test('the same secret in title and command is not repeated', () {
      final row = toolRow(
        _call(
          ToolCallStatusView.succeeded,
          title: 'curl https://user:s3cr3t@host/x',
          command: 'curl https://user:s3cr3t@host/x',
        ),
      );

      expect(row, '✓ curl https://<redacted>@host/x');
    });

    test('a row without secrets stays as it was', () {
      expect(
        toolRow(
          _call(ToolCallStatusView.succeeded, command: 'npm test'),
          elapsed: const Duration(milliseconds: 100),
        ),
        '✓ Run tests npm test 0.1s',
      );
    });
  });
}
