// Лента для вызова смены режима и вызова незнакомого вида (задача 1.10 change
// `tolerate-unknown-tool-kind`; agent-workbench-ui «Вызов смены режима и
// неизвестного вида в ленте»; design.md D5, D7).
//
// Почему отдельный файл: тест ссылается на `ToolKind.switchMode`, которого
// пока нет (красный до задачи 2.1 — ошибка компиляции). В отдельном файле
// красный не ломает компиляцию остальных случаев `ui_mappers_test.dart`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/transcript_rows.dart';

const _autoAccept = PermissionOption(
  optionId: PermissionOptionId('auto-accept'),
  name: 'Yes, and auto-accept all actions',
  kind: PermissionOptionKind.allowAlways,
);
const _manualAccept = PermissionOption(
  optionId: PermissionOptionId('manual-accept'),
  name: 'Yes, and manually accept actions',
  kind: PermissionOptionKind.allowOnce,
);
const _stay = PermissionOption(
  optionId: PermissionOptionId('stay'),
  name: 'No, stay in architect mode',
  kind: PermissionOptionKind.rejectOnce,
);

CodeLabToolCallRow _rowOf(ToolKind kind, String title, {String? approvalId}) {
  final rows = transcriptRowsOf(
    [
      TranscriptItem.toolCall(
        id: 't1/tool-call-1',
        toolCallId: const ToolCallId('call-1'),
        title: title,
        details: ToolCallView(kind: kind, status: ToolCallStatusView.queued),
        approval: const PendingApprovalView(
          approvalId: ApprovalRequestId('permission-1'),
          sessionId: SessionId('session-1'),
          risk: ApprovalRiskLevel.unknown,
          options: [_autoAccept, _manualAccept, _stay],
          focused: true,
        ),
      ),
    ],
    cwd: '/work',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
  );
  return rows.single as CodeLabToolCallRow;
}

void main() {
  test('a switch_mode call reads "Mode <title>" with the unknown-risk tag and '
      'the three agent options', () {
    final row = _rowOf(ToolKind.switchMode, 'Ready for implementation');

    expect(row.label, 'Mode');
    expect(row.detail, 'Ready for implementation');
    final approval = row.approval! as CodeLabTranscriptApprovalPending;
    expect(approval.risk, CodeLabApprovalRisk.unknown);
    expect(approval.options.map((option) => option.id), [
      'auto-accept',
      'manual-accept',
      'stay',
    ]);
    expect(row.text, isNot(contains('switch_mode')));
  });

  test('an other call shows its title and the unknown-risk tag', () {
    final row = _rowOf(ToolKind.other, 'Plan sync');

    expect(row.label, 'Plan sync');
    expect(
      (row.approval! as CodeLabTranscriptApprovalPending).risk,
      CodeLabApprovalRisk.unknown,
    );
    expect(row.text, isNot(contains('future_kind')));
  });
}
