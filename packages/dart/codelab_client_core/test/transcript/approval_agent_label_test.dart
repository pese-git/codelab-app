// Подпись агента в решённом одобрении (change `add-desktop-localization`,
// D6): ядро отдаёт `agentLabel`, чтобы хост отличал запасные подписи ядра
// (`Cancelled`, `Resolved`) от названия варианта агента и переводил первые.
// `label` для CLI не меняется.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:test/test.dart';

const _session = SessionId('s-1');
const _call = ToolCallId('call-1');
const _options = [
  PermissionOption(
    optionId: PermissionOptionId('allow-once'),
    name: 'Allow once',
    kind: PermissionOptionKind.allowOnce,
  ),
];

AcpSession _session0({
  required ApprovalStatus status,
  PermissionOptionId? selected,
}) {
  final approval = ApprovalRequest(
    id: const ApprovalRequestId('permission-1'),
    sessionId: _session,
    turnId: const PromptTurnId('turn-1'),
    toolCall: const ToolCallRecord(id: _call, title: 'Run tests'),
    options: _options,
    status: status,
    selectedOptionId: selected,
  );
  final turn = PromptTurn(
    id: const PromptTurnId('turn-1'),
    sessionId: _session,
    prompt: const [ContentBlock.text(text: 'go')],
    status: PromptTurnStatus.running,
    toolCalls: {_call: approval.toolCall},
    approvals: {approval.id: approval},
  );
  return AcpSession(id: _session, cwd: '/work', turns: [turn]);
}

ResolvedApprovalView _approvalOf(List<TranscriptItem> items) =>
    items.whereType<ToolCallItem>().single.approval! as ResolvedApprovalView;

ResolvedApprovalView _project({
  required ApprovalStatus status,
  PermissionOptionId? selected,
}) {
  final projector = TranscriptProjector()
    ..apply(_session0(status: status, selected: selected));
  return _approvalOf(projector.items);
}

void main() {
  group('ResolvedApprovalView.agentLabel', () {
    test('cancelled: no agent label, label stays Cancelled', () {
      final view = _project(status: ApprovalStatus.cancelled);
      expect(view.agentLabel, isNull);
      expect(view.label, 'Cancelled');
    });

    test('no option selected: no agent label, label stays Resolved', () {
      final view = _project(status: ApprovalStatus.selected);
      expect(view.agentLabel, isNull);
      expect(view.label, 'Resolved');
    });

    test('selected option: the agent option name', () {
      final view = _project(
        status: ApprovalStatus.selected,
        selected: const PermissionOptionId('allow-once'),
      );
      expect(view.agentLabel, 'Allow once');
      expect(view.label, 'Allow once');
    });

    test('unknown option id: the id itself', () {
      final view = _project(
        status: ApprovalStatus.selected,
        selected: const PermissionOptionId('custom-7'),
      );
      expect(view.agentLabel, 'custom-7');
      expect(view.label, 'custom-7');
    });
  });

  // Спека: инкрементальная проекция и пересчёт с нуля дают равный agentLabel.
  group('incremental projection and projectTranscript agree', () {
    for (final (name, status, selected) in [
      ('selected', ApprovalStatus.selected, 'allow-once'),
      ('unknown id', ApprovalStatus.selected, 'custom-7'),
      ('no option', ApprovalStatus.selected, null),
      ('cancelled', ApprovalStatus.cancelled, null),
    ]) {
      test(name, () {
        final session = _session0(
          status: status,
          selected: selected == null ? null : PermissionOptionId(selected),
        );
        final incremental = (TranscriptProjector()..apply(session)).items;
        final rebuilt = projectTranscript(session);

        expect(
          _approvalOf(incremental).agentLabel,
          _approvalOf(rebuilt).agentLabel,
        );
      });
    }
  });
}
