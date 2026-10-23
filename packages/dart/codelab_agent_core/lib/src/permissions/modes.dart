import '../tools/agent_tool.dart';

/// Permission modes and tiers (`agent-core-architecture` §7.3).

/// The order of declaration is the order of softness (§7.3.1).
enum PermissionMode { alwaysAsk, write, acceptEdits, yolo, autopilot }

/// A per-tool rule of the configuration (`permissions.tools`).
enum ToolPolicy { allow, deny, ask }

enum TierDecision { allow, ask, deny }

/// The `mode × tier` table of §7.3; «ask» is a call of the gate.
TierDecision tierDecision(PermissionMode mode, ToolTier tier) => switch ((
  mode,
  tier,
)) {
  (PermissionMode.alwaysAsk, _) => TierDecision.ask,
  (_, ToolTier.read) => TierDecision.allow,
  (PermissionMode.autopilot, ToolTier.network) => TierDecision.deny,
  (_, ToolTier.network) => TierDecision.ask,
  (PermissionMode.write, _) => TierDecision.ask,
  (PermissionMode.acceptEdits, ToolTier.write) => TierDecision.allow,
  (PermissionMode.acceptEdits, _) => TierDecision.ask,
  (PermissionMode.yolo || PermissionMode.autopilot, _) => TierDecision.allow,
};

/// A mode of the session as the client sees it (§13.6). `autopilot` is not
/// a mode id: it is enabled only by a launch flag (CFG-4; design.md change
/// `add-agent-core-permission-policy`, D3).
extension type const ModeId._(String value) {
  static const plan = ModeId._('plan');
  static const ask = ModeId._('ask');
  static const standard = ModeId._('standard');
  static const acceptEdits = ModeId._('accept-edits');
  static const bypass = ModeId._('bypass');

  static const values = [plan, ask, standard, acceptEdits, bypass];

  /// Only the main ids; the ACP adapter normalizes synonyms (stage 4).
  static ModeId parse(String id) =>
      values.where((m) => m.value == id).firstOrNull ??
      (throw ArgumentError.value(id, 'id', 'unknown mode'));

  PermissionMode get permissionMode => switch (value) {
    'ask' => PermissionMode.alwaysAsk,
    'accept-edits' => PermissionMode.acceptEdits,
    'bypass' => PermissionMode.yolo,
    _ => PermissionMode.write,
  };

  /// Tiers the mode forbids without asking: `plan` forbids changes.
  Set<ToolTier> get deniedTiers =>
      value == 'plan' ? const {ToolTier.write, ToolTier.exec} : const {};
}
