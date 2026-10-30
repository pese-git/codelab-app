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

  group('ModeId softness (floor of an agent mode, OQ3)', () {
    // Неизвестный идентификатор в расширении-типе создаётся только через
    // приведение: так выглядит значение, пришедшее извне.
    final unknown = ('wild' as dynamic) as ModeId;

    test('the known ids are ordered plan < ask < standard < accept-edits < '
        'bypass, standard explicitly', () {
      expect([for (final m in ModeId.values) m.softness], [0, 1, 2, 3, 4]);
      expect(ModeId.standard.softness, 2);
    });

    test('an unknown id has no rank', () {
      expect(unknown.softness, isNull);
    });

    test('fitsFloor: not softer than the floor', () {
      expect(ModeId.plan.fitsFloor(ModeId.standard), isTrue);
      expect(ModeId.standard.fitsFloor(ModeId.standard), isTrue);
      expect(ModeId.acceptEdits.fitsFloor(ModeId.standard), isFalse);
      expect(ModeId.bypass.fitsFloor(ModeId.ask), isFalse);
    });

    test('an unknown candidate never fits, an unknown floor admits nothing '
        '(fail-closed)', () {
      // agent-definitions «Неизвестный режим»: пол `standard` из сценария.
      expect(unknown.fitsFloor(ModeId.standard), isFalse);
      expect(unknown.fitsFloor(ModeId.bypass), isFalse);
      expect(unknown.fitsFloor(unknown), isFalse);
      expect(ModeId.plan.fitsFloor(unknown), isFalse);
      expect(ModeId.ask.fitsFloor(unknown), isFalse);
    });
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
