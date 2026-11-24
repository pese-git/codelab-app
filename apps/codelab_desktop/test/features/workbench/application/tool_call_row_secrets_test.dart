// Красные тесты задачи 3.3 change `redact-tool-row-text`: маппер ленты не
// несёт сырой вывод инструмента в `CodeLabToolCallRow` — вторая строка, метка
// `other` и хвост вывода приходят из kit уже без секретов (D1, D2, D7;
// agent-workbench-ui «Вывод раскрытой строки инструмента без секретов»,
// acp-client-kit «Строка инструмента без сырого JSON»).
//
// Границы: маскирует и решает о повторе kit (`ToolRowFormatter`), маппер
// только переносит результат; вызов `agent` по-прежнему показывает `report`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

CodeLabToolCallRow _rowOf(ToolCallView details, {String title = 'tool'}) {
  final rows = transcriptRowsOf(
    [
      TranscriptItem.toolCall(
        id: 't1/tool-call-1',
        toolCallId: const ToolCallId('call-1'),
        title: title,
        details: details,
      ),
    ],
    cwd: '/work',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
    l10n: AppLocalizationsEn(),
  );
  return rows.single as CodeLabToolCallRow;
}

void main() {
  group('tool call row without secrets', () {
    test('a failed fetch with one line: masked secondary, empty output', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.fetch,
          status: ToolCallStatusView.failed,
          rawInput: {'url': 'https://host/x'},
          textOutput: ['Error: request to https://user:pass@host/x failed'],
        ),
      );

      expect(
        row.secondary,
        'Error: request to https://<redacted>@host/x failed',
      );
      expect(row.secondary, isNot(contains('pass')));
      expect(row.output, isEmpty);
    });

    test('a completed read masks the output and keeps the other lines', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.read,
          status: ToolCallStatusView.succeeded,
          rawInput: {'path': '/work/.env'},
          textOutput: ['API_KEY=sk-live-123\nDEBUG=1'],
        ),
      );

      final output = row.output.join('\n');
      expect(output, isNot(contains('sk-live-123')));
      expect(output, contains('DEBUG=1'));
    });

    test('a failed call with two lines keeps both in the output', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.execute,
          status: ToolCallStatusView.failed,
          rawInput: {'command': 'make'},
          textOutput: ['Error: boom\n    at main (a.dart:1)'],
        ),
      );

      final output = row.output.join('\n');
      expect(output, contains('Error: boom'));
      expect(output, contains('at main (a.dart:1)'));
    });

    test('an other call label has no password from the title', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.other,
          status: ToolCallStatusView.succeeded,
        ),
        title: 'curl https://user:pass@host/x',
      );

      expect(row.label, isNot(contains('pass')));
      expect(row.detail, isNot(contains('pass')));
    });

    test('an agent call still takes its output from the report', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.succeeded,
          rawInput: {'type': 'explore', 'description': 'Find auth code'},
          subagentCall: SubagentCallView(id: 'sub_a1', type: 'explore'),
          textOutput: ['Auth lives in lib/auth.dart.'],
        ),
        title: 'agent',
      );

      expect(row.output, ['Auth lives in lib/auth.dart.']);
    });
  });
}
