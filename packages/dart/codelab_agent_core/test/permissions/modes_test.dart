import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('the order of softness (§7.3.1)', () {
    expect(PermissionMode.values.map((m) => m.name), [
      'alwaysAsk',
      'write',
      'acceptEdits',
      'yolo',
      'autopilot',
    ]);
  });

  test('the mode × tier table of §7.3', () {
    const a = TierDecision.allow, q = TierDecision.ask, d = TierDecision.deny;
    final table = {
      PermissionMode.alwaysAsk: [q, q, q, q],
      PermissionMode.write: [a, q, q, q],
      PermissionMode.acceptEdits: [a, a, q, q],
      PermissionMode.yolo: [a, a, q, a],
      PermissionMode.autopilot: [a, a, d, a],
    };
    for (final MapEntry(key: mode, value: row) in table.entries) {
      expect(
        [for (final tier in ToolTier.values) tierDecision(mode, tier)],
        row,
        reason: mode.name,
      );
    }
  });

  test('ModeId maps to PermissionMode by §13.6', () {
    expect(ModeId.values, [
      ModeId.plan,
      ModeId.ask,
      ModeId.standard,
      ModeId.acceptEdits,
      ModeId.bypass,
    ]);
    expect(
      {for (final m in ModeId.values) m.value: m.permissionMode.name},
      {
        'plan': 'write',
        'ask': 'alwaysAsk',
        'standard': 'write',
        'accept-edits': 'acceptEdits',
        'bypass': 'yolo',
      },
    );
    expect(ModeId.plan.deniedTiers, {ToolTier.write, ToolTier.exec});
    expect(ModeId.standard.deniedTiers, isEmpty);
  });

  test('ModeId.parse knows only the main ids; autopilot is not a mode id', () {
    expect(ModeId.parse('accept-edits'), ModeId.acceptEdits);
    expect(() => ModeId.parse('autopilot'), throwsArgumentError);
    expect(() => ModeId.parse('code'), throwsArgumentError);
  });
}
