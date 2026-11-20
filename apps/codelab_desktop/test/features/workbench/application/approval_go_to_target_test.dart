// Выбор цели сочетания «Go to approval» (задача 2.3 change
// `fix-approval-focus`; design.md D4, п. 1; spec agent-workbench-ui
// «Переход к ожидающему одобрению с клавиатуры»).
//
// Цель выбирает application в момент нажатия: самое раннее ожидающее
// одобрение активной сессии по признаку `focused` модели клиентского ядра, а
// не по порядку списка. Для одобрения субагента цель — строка `agent` корня
// (путь не раскрывается). Цели нет без ожидающего одобрения, без соединения
// `Connected` и у сессии `detached`.
//
// Красный до задачи 2.4: `goToApprovalTargetOf` — заглушка, всегда `null`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId, ApprovalRiskLevel;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/approval_go_to_target.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);

PendingApprovalView _pending(
  String id, {
  required bool focused,
  SubagentRequester? subagent,
}) => PendingApprovalView(
  approvalId: ApprovalRequestId(id),
  sessionId: const SessionId('s1'),
  risk: ApprovalRiskLevel.shell,
  options: const [_allowOnce],
  focused: focused,
  subagent: subagent,
);

SessionView _view(
  List<PendingApprovalView> pending, {
  SessionStatusView status = SessionStatusView.running,
}) => SessionView(revision: 1, status: status, pendingApprovals: pending);

CodeLabTranscriptApproval _row(String targetId) =>
    CodeLabTranscriptApproval.pending(
      risk: CodeLabApprovalRisk.shell,
      options: const [
        CodeLabApprovalOption(
          id: 'allow-once',
          label: 'Allow once',
          kind: CodeLabApprovalOptionKind.allowOnce,
        ),
      ],
      onOptionSelected: (_) {},
      targetId: targetId,
    );

CodeLabToolCallRow _call(String id, String approvalId) => CodeLabToolCallRow(
  id: id,
  status: CodeLabToolCallStatus.running,
  label: 'Run echo',
  approval: _row(approvalId),
);

void main() {
  const connected = CodeLabConnectionStatus.connected;

  group('самое раннее ожидающее одобрение активной сессии', () {
    test('выбирается по признаку focused, а не по порядку списка', () {
      final target = goToApprovalTargetOf(
        connectionStatus: connected,
        // Позднее одобрение стоит в списке первым: порядок решает признак.
        view: _view([
          _pending('permission-B', focused: false),
          _pending('permission-A', focused: true),
        ]),
        rows: [
          _call('tool-1', 'permission-A'),
          _call('tool-2', 'permission-B'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.rowId, 'tool-1');
      // Цель собственного одобрения строки — сама строка (как у панели
      // Agents, `AgentsPaneData`).
      expect(target.targetId, 'tool-1');
      expect(target.expand, isEmpty);
    });

    test('одобрение субагента — строка agent корня, путь не раскрывается', () {
      final target = goToApprovalTargetOf(
        connectionStatus: connected,
        view: _view([
          _pending(
            'permission-S',
            focused: true,
            subagent: const SubagentRequester(
              id: 'sub_aaaaaaaa',
              type: 'explore',
              description: 'Find callers',
              depth: 1,
              parentToolCallId: 'call_1',
            ),
          ),
        ]),
        rows: [
          CodeLabToolCallRow(
            id: 'tool-1',
            status: CodeLabToolCallStatus.running,
            label: 'Subagent review',
            subagent: const CodeLabSubagentCall(),
            childApprovals: [_row('permission-S')],
          ),
        ],
      );

      expect(target, isNotNull);
      expect(target!.rowId, 'tool-1');
      expect(target.targetId, 'permission-S');
      expect(
        target.expand,
        isEmpty,
        reason: 'строка agent корня остаётся свёрнутой',
      );
    });
  });

  group('цели нет', () {
    final rows = [_call('tool-1', 'permission-A')];

    test('без ожидающего одобрения', () {
      expect(
        goToApprovalTargetOf(
          connectionStatus: connected,
          view: _view(const []),
          rows: rows,
        ),
        isNull,
      );
      expect(
        goToApprovalTargetOf(
          connectionStatus: connected,
          view: null,
          rows: rows,
        ),
        isNull,
      );
    });

    test('соединение не Connected', () {
      for (final status in CodeLabConnectionStatus.values) {
        if (status == connected) continue;
        expect(
          goToApprovalTargetOf(
            connectionStatus: status,
            view: _view([_pending('permission-A', focused: true)]),
            rows: rows,
          ),
          isNull,
          reason: '$status',
        );
      }
    });

    test('сессия detached', () {
      expect(
        goToApprovalTargetOf(
          connectionStatus: connected,
          view: _view([
            _pending('permission-A', focused: true),
          ], status: SessionStatusView.detached),
          rows: rows,
        ),
        isNull,
      );
    });
  });
}
