// Политика одобрений headless (tasks 4.3; spec cli-headless «Политика
// одобрений headless»; design.md change `add-codelab-cli`, D9).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const _allowAlways = PermissionOption(
  optionId: PermissionOptionId('always'),
  name: 'Always allow',
  kind: PermissionOptionKind.allowAlways,
);
const _rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);
const _rejectAlways = PermissionOption(
  optionId: PermissionOptionId('never'),
  name: 'Always reject',
  kind: PermissionOptionKind.rejectAlways,
);

PendingApprovalView _approval({
  List<PermissionOption> options = const [
    _allowOnce,
    _allowAlways,
    _rejectOnce,
    _rejectAlways,
  ],
  bool critical = false,
}) => PendingApprovalView(
  approvalId: const ApprovalRequestId('a1'),
  sessionId: const SessionId('s1'),
  risk: ApprovalRiskLevel.shell,
  options: options,
  focused: true,
  critical: critical,
);

void main() {
  test('reject answers reject_once', () {
    final decision = decideApproval(
      _approval(),
      ApprovePolicy.reject,
      kind: ToolKind.execute,
    );

    expect(decision.optionId, _rejectOnce.optionId);
    expect(decision.outcome, 'reject_once');
    expect(decision.reason, ApprovalReason.policy);
  });

  test('read-only allows a read once and rejects anything else', () {
    expect(
      decideApproval(
        _approval(),
        ApprovePolicy.readOnly,
        kind: ToolKind.read,
      ).optionId,
      _allowOnce.optionId,
    );
    for (final kind in [
      ToolKind.edit,
      ToolKind.execute,
      ToolKind.fetch,
      null,
    ]) {
      expect(
        decideApproval(
          _approval(),
          ApprovePolicy.readOnly,
          kind: kind,
        ).optionId,
        _rejectOnce.optionId,
        reason: '$kind',
      );
    }
  });

  test('allow-all allows once', () {
    final decision = decideApproval(
      _approval(),
      ApprovePolicy.allowAll,
      kind: ToolKind.execute,
    );

    expect(decision.optionId, _allowOnce.optionId);
    expect(decision.reason, ApprovalReason.policy);
  });

  test('allow-all rejects a critical request', () {
    final decision = decideApproval(
      _approval(critical: true),
      ApprovePolicy.allowAll,
      kind: ToolKind.execute,
    );

    expect(decision.optionId, _rejectOnce.optionId);
    expect(decision.reason, ApprovalReason.critical);
  });

  test('a missing wanted option falls back to the first reject option', () {
    expect(
      decideApproval(
        _approval(options: const [_allowOnce, _rejectAlways]),
        ApprovePolicy.reject,
        kind: ToolKind.execute,
      ).optionId,
      _rejectAlways.optionId,
    );
    expect(
      decideApproval(
        _approval(options: const [_allowAlways, _rejectOnce]),
        ApprovePolicy.allowAll,
        kind: ToolKind.execute,
      ).optionId,
      _rejectOnce.optionId,
    );
  });

  test('without any reject option the request is cancelled', () {
    final decision = decideApproval(
      _approval(options: const [_allowAlways]),
      ApprovePolicy.reject,
      kind: ToolKind.execute,
    );

    expect(decision.optionId, isNull);
    expect(decision.outcome, 'cancelled');
    expect(decision.reason, ApprovalReason.cancelled);
  });

  test('the stderr line names the tool, the decision and the reason', () {
    final decision = decideApproval(
      _approval(critical: true),
      ApprovePolicy.allowAll,
      kind: ToolKind.execute,
    );

    expect(
      describeApproval('Run rm -rf build', decision),
      'codelab: permission "Run rm -rf build": reject_once (critical)',
    );
  });
}
